<!--
approved_at: 2026-05-26
retroactive: true
approved_by: user
-->

# Loop モード確認質問検出 hook (loop-confirmation-detector)

## §1 真因 (背景)

Loop モード稼働中の main agent が、modes.md 遵守事項 2 (中間確認の停止) に違反して「進めてもよいですか?」「OK ですか?」「お待ちします」等の確認質問を出すケースが頻発。

### 観察証拠

- **本 session 末 (2026-05-26)**: 「次の指示をお待ちします」「user 判断待ち」表現で user 確認を求めた → user 「なぜ聞くのですか」で指摘
- **別 Claude Code session (user 共有 log)**: 「技術的修正のみで user 戦略判断不要、Loop モード自律 patch 着手で OK ですか?」と確認質問 → user 指摘
- **task-40 session 内**: PR create を「user manual 必須」と誤認識 → user 「なぜ PR を作成できないのですか?」で指摘

### 真因 3 階層

1. **規範のみで honor system**: modes.md 遵守事項 2 は規範文書のみで機械強制がない、AI が違反しても物理的に止まらない
2. **mode-enforce.sh は UserPromptSubmit hook で AI 行動の **前** に発火**: AI 出力後の検証機構がない、出力された確認質問を検出して是正する layer 不在
3. **観察不足**: observe.sh は tool call を観察するが、AI text 出力 (確認質問含む) の解析機構なし

## §2 採用案比較

| 案 | 内容 | 評価 |
|---|---|---|
| A | 規範追記のみ (modes.md に「確認質問パターン例」明示) | 軽実装だが honor system 継続、再発確実 |
| B | Stop hook 新設のみ (AI 最終 message を regex 検出 → warn 注入) | 機械強制、ただし規範文書化なしで意図不透明 |
| **C ハイブリッド** | Stop hook + 規範補強 + smoke + dogfooding | 3 層で再発防止、本 session 違反パターンを直接データソースに |

→ **C ハイブリッド** 採用。理由: 「Loop モードなのに聞いてくる」(user 指摘) の核心は機械強制で「物理的に止める」(or 是正注入)、規範追記 + hook + dogfooding で 3 層防御。

## §3 採用案 (実装仕様)

### 3.1 Stop hook 新設

**file**: `.claude/hooks/loop-confirmation-detector.sh`

**発火 timing**: Stop (AI 最終 assistant message 完了時)

**動作**:

1. `mode-loader.sh` で current mode 取得、Loop モード以外は早期 exit 0
2. `transcript_path` から最終 assistant message を抽出 (jq 経由)
3. 「確認質問パターン」(下記 regex) を grep
4. 検出時、`hookSpecificOutput.additionalContext` で次 turn に `<system-reminder>` 強制注入 ("Loop モード違反検出、自律実行に切替えよ")
5. bypass.log に記録 (audit trail)

### 3.2 検出 regex (initial set)

```
進めて(も|よろ)?(し)?い(い)?(ですか|でしょうか)
OK\s?(ですか|でしょうか)
どちら(に|を)?します?か?
どうします?か?
実行(し|して)も(よろし|よ)い?(ですか|でしょうか)
次の指示をお待ちします
お待ちし(て|)(い|お)?ます
user 判断待ち
user 確認待ち
進めますか
続行しますか
停止しますか
よろしいですか
```

regex は `harness-config.yml` の `loop_confirmation_patterns` で override 可能 (CSV or 改行区切り)。

### 3.3 bypass 経路

| 経路 | env | スコープ | 痕跡 |
|---|---|---|---|
| hook 無効化 | `HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false` | 1 セッション | bypass.log |
| 一時 OFF | `ECC_LOOP_CONFIRMATION_OFF=1` | 1 セッション | bypass.log |
| pattern override | `HC_LOOP_CONFIRMATION_PATTERNS=...` | env-set 中 | (記録なし) |

### 3.4 規範補強

- `.claude/rules/modes.md` 遵守事項 2 に「機械強制 hook (loop-confirmation-detector.sh) が確認質問検出で <system-reminder> 注入」追記
- `.claude/rules/modes.md` 「5 層強制機構」table に layer 追加
- `CLAUDE.md` Critical Lessons「hook で完全 BLOCK 強制済の旧教訓」section に「Loop モード時の確認質問は loop-confirmation-detector.sh が検出 → 強制注意喚起」を追記 (BLOCK ではなく warn だが、5 層機構の一部として)

### 3.5 dogfooding

本 task 自身を新 hook の最初の適用例とする。task 完遂までに main agent が確認質問を発した場合、新 hook が検出 → 次 turn で自律是正に切替。

## §4 TDD 戦略

### RED (smoke 新設)

`.claude/tests/loop-confirmation-detector-smoke.sh` (case 8+):

- Case 1: Loop モード、AI message に「進めてよいですか」→ warn 注入確認
- Case 2: Loop モード、AI message に「OK ですか」→ warn 注入確認
- Case 3: Loop モード、AI message に「お待ちします」→ warn 注入確認
- Case 4: Normal モード、AI message に「進めてよいですか」→ skip (warn なし)
- Case 5: Loop モード、AI message に確認質問なし → silent pass
- Case 6: bypass env `HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false` → skip
- Case 7: bypass env `ECC_LOOP_CONFIRMATION_OFF=1` → skip + bypass.log 記録
- Case 8: pattern override `HC_LOOP_CONFIRMATION_PATTERNS="custom1\ncustom2"` → custom patterns 動作

### GREEN (実装)

- `.claude/hooks/loop-confirmation-detector.sh` 新設
- `.claude/settings.json` Stop hook 配列に append
- `.claude/harness-config.yml` に `loop_confirmation_detection_enabled` + `loop_confirmation_patterns` 追加
- `.claude/hooks/lib/config-loader.sh` の `_HC_KNOWN_KEYS` + defaults + export 追加

### REFACTOR

3 観点 (持続可能性 / 汎用性 / 非冗長化) 判定、不要なら skip 明示。

## §5 Step 計画 (採用 6 条準拠、Task=Phase=N Step)

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | draft 起案 (本 file) + task file + list.md row 追加 | draft + task file 存在 + list.md row append |
| 2 | 🔲 | `.claude/hooks/loop-confirmation-detector.sh` 新設 (staging 戦略必須) | hook file 存在 + `bash -n` syntax OK |
| 3 | 🔲 | `.claude/settings.json` Stop hook 配線 + `harness-config.yml` + `config-loader.sh` 追加 | settings.json hook entry 存在 + grep config key hit |
| 4 | 🔲 | smoke 新設 (`.claude/tests/loop-confirmation-detector-smoke.sh`、8+ case) | smoke 全 PASS |
| 5 | 🔲 | 規範補強 (`.claude/rules/modes.md` + `CLAUDE.md`) | grep 確認 |
| 6 | 🔲 | (テスト設計レビュー) reviewer 3+ 並列、CRITICAL+HIGH+MEDIUM=0 まで反復 (上限 5) | iter 1+ 実施 + 収束 |
| 7 | 🔲 | (テスト合格) smoke 全 PASS + 既存 regression 0 + grep 検証 | 検証全 PASS |
| 8 | 🔲 | (リファクタリング) 3 観点判定、不要なら skip 明示 | skip 想定 |
| 9 | 🔲 | commit + push + PR create + user merge 案内 | PR URL 提示 |
| 10 | 🔲 | 3 リポ user manual install 案内 (`bash install.sh --update <target>` × 3) | install command 提示 |

## §6 DoD (Definition of Done)

- [ ] `.claude/hooks/loop-confirmation-detector.sh` 存在 + 実行可能
- [ ] Stop hook 配線済 (`settings.json`)
- [ ] config SSoT (`harness-config.yml` + `config-loader.sh`) 整合
- [ ] smoke 8+ case 全 PASS
- [ ] modes.md + CLAUDE.md grep 確認 PASS
- [ ] reviewer 3+ 並列 CRITICAL+HIGH+MEDIUM=0 収束
- [ ] PR create + user merge 待ち
- [ ] 3 リポ install command 提示 (user manual 実行)

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル (hook) | `.claude/hooks/loop-confirmation-detector.sh` (新規) |
| ファイル (test) | `.claude/tests/loop-confirmation-detector-smoke.sh` (新規) |
| ファイル (config) | `.claude/harness-config.yml` (key 追加) / `.claude/hooks/lib/config-loader.sh` (登録) |
| ファイル (settings) | `.claude/settings.json` Stop hook 配列 |
| ファイル (規範) | `.claude/rules/modes.md` (遵守事項 2 + 5 層 table) / `CLAUDE.md` (Critical Lessons) |
| ファイル (task 管理) | `docs/tasks/list.md` (row 追加) / `docs/tasks/task-41-loop-confirmation-detector-hook.md` (新規) |
| migration | なし |
| 環境変数 | `HC_LOOP_CONFIRMATION_DETECTION_ENABLED` / `ECC_LOOP_CONFIRMATION_OFF` / `HC_LOOP_CONFIRMATION_PATTERNS` |
| 互換性 | Normal モードは影響なし (早期 exit)、bypass env で各方向に OFF 可能 |

## §8 レビューサイクル (iter 履歴)

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| (空、reviewer 並列後に append) | | | | | | |

## §9 関連

- 関連 task: task-40 (draft-flow-guard.sh 拡張、retroactive 方式の起源)
- 関連 hook: `.claude/hooks/mode-enforce.sh` (UserPromptSubmit、本 hook と相補)
- 関連 memory: `feedback_loop_mode_confirmation_violation.md` (本 session 違反、起こす予定)
- 関連 user 指摘: 「Loop モードなのに聞いてきます」(2026-05-26、本 session)
