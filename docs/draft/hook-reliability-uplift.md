# Hook Reliability Uplift — 26 hooks の fail-safety / test coverage / observe rotation 改善

**ステータス:** 🔲 **draft (2026-05-23 起案、user 承認待ち)**
**起点:** 2026-05-23 ハーネス網羅分析、CLAUDE.md Critical Operational Lessons HIGH 2 件 (set -e leak / 並列 subagent git 競合)、recall_poc 観察事案
**前提:**
- task #19 (git-destructive-deny smoke 基盤) 完了済
- 26 hooks の fail policy / jq 使用状況 grep 済 (2026-05-23 セッション)

**関連 fixture / rule:**
- `.claude/hooks/lib/*.sh` (subshell 関数化規範)
- `.claude/tests/*-smoke.sh` (既存 14 smoke)
- `~/.claude/homunculus/projects/<hash>/observations.jsonl` (rotation 対象)

---

## 1. 真因サマリ / 課題サマリ

2026-05-23 の網羅分析で **26 hooks の信頼性 / 性能に系統的問題** が判明:

- **C-1**: 8 hooks (mode-enforce / why-x5-reminder / agent-router-suggest / check-serena-mcp / mode-session-start / session-help-surface / workflow-guard / autonomous-action-guard) が file-top `set -euo pipefail` 採用、CLAUDE.md Critical Lessons HIGH「lib に書くな (exit 141 サイレント死)」と整合不完全
- **C-2**: 複数 hooks (delegation-guard / agent-router-suggest / byproduct-discharge-guard / next-actions-surface 等) が jq 使用しているのに `command -v jq` guard なし → jq 不在環境で crash
- **C-3**: 26 hooks に対し smoke test 14 件 (~50% coverage)、新 hook draft-flow-guard.sh / gateguard.sh / task-rule-guard.sh / confidence-gate.sh 等の主要 guard が test 不在
- **P-1**: observe.jsonl 17 MB / 5498 件で線形成長、rotation / archive 不在
- **P-5**: improvement-proposal.sh 491 LOC が毎 SessionStart で 7 日分 JSONL を fullscan

**真因**: ハーネス機能拡張 (26 hooks まで増加) に対し、test coverage / fail policy 規範 / 観測データ管理 が追いつかず、運用品質が暗黙の前提に依存している。

**副次**: hook 失敗が silent (exit 0 fail-open) で発生しても検知できないため、長期間の劣化が累積する可能性。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | 全 hook を 1 PR で一括修正 | 3.0 | 整合性高 | review 困難、blast radius 大 |
| **B** | hook 毎に 1 commit ずつ修正 | 4.0 | 粒度最適、revert 容易 | commit 数膨大 |
| **C ハイブリッド** | 系統別 4 Wave (fail policy / jq guard / smoke / observe rotation) | 3.5 | 系統的、Wave 単位 verify | Wave 間依存に注意 |

→ **C ハイブリッド** を推奨。系統別に Wave を切り、各 Wave は独立に rollback 可能。

---

## 3. 採用案の詳細設計

### Wave 分割

| Wave | 内容 | 工数 | 効果 |
|:---:|:---|---:|:---|
| W1 | 8 hooks の `set -euo pipefail` → `set -uo pipefail` 統一 (errexit 外す)、または subshell 関数化 | 0.5 | SIGPIPE → exit 141 サイレント死リスク解消 |
| W2 | jq 使用 hook 全件に `command -v jq` guard 追加 (fail-open) | 0.5 | jq 不在環境で crash 防止 |
| W3 | 主要 guard hook 4 件 (gateguard / task-rule-guard / confidence-gate / autonomous-action-guard) + draft-flow-guard の smoke test 追加 | 1.5 | coverage ~50% → ~75% |
| W4 | observe.jsonl rotation 機構新設 (30 日超 entry を `observations-YYYY-MM.jsonl.gz` に archive) | 0.7 | 線形成長 → 月次 rotation で context 削減 |
| W5 | improvement-proposal.sh の集計結果キャッシュ化 (`cache.json` TTL 1h) | 0.3 | SessionStart 時間短縮 |

合計: 3.5 session

### W1 詳細 (set -uo pipefail 統一)

#### スコープ
- 対象: 8 hooks (mode-enforce / why-x5-reminder / agent-router-suggest / check-serena-mcp / mode-session-start / session-help-surface / workflow-guard / autonomous-action-guard)
- 対象外: `.claude/hooks/lib/*.sh` (既に subshell 関数化対応済)

#### 変更内容
```bash
# before
set -euo pipefail

# after (errexit を外す、SIGPIPE 141 リスク解消)
set -uo pipefail

# または subshell 関数化 (lib スタイル)
do_work() ( set -euo pipefail; ... )
```

#### テスト
- 各 hook の既存 smoke test (存在分) で regression 確認
- 新規 `set-policy-smoke.sh` で全 hook を grep して `set -euo pipefail` 不在を機械検証

### W2 詳細 (jq guard 追加)

#### スコープ
- 対象: `command -v jq` guard 不在の jq 使用 hook (4-5 件、要 grep 確定)

#### 変更内容
```bash
# 各 hook の冒頭に追加
if ! command -v jq >/dev/null 2>&1; then
  exit 0  # fail-open (jq 不在環境では hook 機能停止)
fi
```

### W3 詳細 (smoke test 拡充)

#### スコープ
- 新規 smoke: `gateguard-smoke.sh` `task-rule-guard-smoke.sh` `confidence-gate-smoke.sh` `autonomous-action-guard-smoke.sh` `draft-flow-guard-smoke.sh`
- 各 5-7 ケース (BLOCK / PASS / bypass / edge case)

#### テスト構造
```bash
# 例: gateguard-smoke.sh
case_1_initial_write_blocked() {
  echo '{"tool_name":"Write","tool_input":{"file_path":".../foo.ts","content":"x"}}' \
    | bash .claude/hooks/gateguard.sh Write
  [ $? -eq 2 ] || fail "initial Write should BLOCK"
}
case_2_cleared_write_pass() { ... }
```

### W4 詳細 (observe.jsonl rotation)

#### スコープ
- 新 hook `.claude/scripts/observe-rotate.sh` (cron 想定、または harness-audit から手動起動)
- 30 日超の entry を `observations-YYYY-MM.jsonl.gz` に archive、本体は最近 30 日のみ保持

#### 変更内容
```bash
# 月次 cron (or harness-audit のサブコマンド) で起動
THRESHOLD=$(date -v-30d +%Y-%m-%d)
awk -v t="$THRESHOLD" '$0 ~ "\"ts\":\"" && $0 < t' observations.jsonl > archive.jsonl
awk -v t="$THRESHOLD" '$0 ~ "\"ts\":\"" && $0 >= t' observations.jsonl > observations.new.jsonl
gzip archive.jsonl
mv observations.new.jsonl observations.jsonl
```

### W5 詳細 (improvement-proposal cache)

#### スコープ
- 対象 hook: `.claude/hooks/improvement-proposal.sh`
- cache: `.claude/.improvement-proposal-state/cache.json` (TTL 1h)

#### 変更内容
```bash
# 集計前に cache check
CACHE=".claude/.improvement-proposal-state/cache.json"
if [ -f "$CACHE" ] && [ $(($(date +%s) - $(stat -f %m "$CACHE"))) -lt 3600 ]; then
  cat "$CACHE"
  exit 0
fi
# ... 集計処理 ...
echo "$result" > "$CACHE"
```

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| `set -e` 撤去で fail 検知漏れ | M | M | Wave 1 完了後、各 hook で `if ! cmd; then return 1; fi` パターンを review |
| jq guard 追加で hook 機能停止が silent | L | M | log に「jq 不在のため skip」を必ず出力 |
| observe.jsonl rotation で過去 instinct 喪失 | L | H | archive は削除せず保持、L4 学習は archive も走査可能に |

---

## 5. 移行計画

- [ ] W1 (set policy 統一) → 全 hook smoke で regression 0 確認
- [ ] W2 (jq guard 追加) → jq 不在 docker image で動作確認
- [ ] W3 (smoke test 拡充) → coverage % を harness-audit で表示
- [ ] W4 (observe rotation) → 1 ヶ月運用後、サイズ削減効果を計測
- [ ] W5 (improvement-proposal cache) → SessionStart 時間 before/after 計測
- [ ] recall_poc / taskManageSystem / classlab-weekly-news に install.sh --update で反映

---

## 6. 完了条件 (DoD)

- [ ] `set -euo pipefail` を file-top で使う hook が 0 件
- [ ] jq 使用 hook 全件に jq guard あり (grep 検証)
- [ ] 主要 guard hook 5 件の smoke test 追加 (各 5-7 ケース PASS)
- [ ] observe-rotate.sh 動作確認 + サイズ削減実測
- [ ] improvement-proposal cache hit 率測定
- [ ] 既存 smoke 全件 regression 0
- [ ] CLAUDE.md Critical Operational Lessons に「W3 主要 guard smoke 追加完了」を追記

---

## 7. 工数見積

合計 3.5 session (W1 0.5 + W2 0.5 + W3 1.5 + W4 0.7 + W5 0.3)。

---

## 8. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-23 | user | (待ち) |

---

## 9. 関連

- 既存設計: `docs/draft/system-reminder-attention-fix.md` (Wave 0 と独立、並行実装可)
- CLAUDE.md Critical Operational Lessons (HIGH 2 件: set -e leak / 並列 subagent git 競合)
- 関連タスク: 本 draft = task-22 想定
