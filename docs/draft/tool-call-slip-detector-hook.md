---
slug: tool-call-slip-detector-hook
status: approved
approved_by: user
approved_at: 2026-06-01
retroactive: false
---

# tool-call markup slip 自動検出 Stop hook

## §1 背景・問題

2026-06-01 task-69 実装 session (transcript `dc60eacc`) で、AI の tool 呼び出しが
「途中で止まる」現象が複数回発生し user が指摘。直近 400 行に standalone `call`
行を 12+ 回、`<parameter name="description">...` の本文 text 漏れを観測。

### 真因 (証拠ベース)

`antml:invoke` の構造化出力が生成中に部分破綻し、囲みタグ (`<invoke>`) が落ちて
中身 (`call` トークン / bare command / `<parameter ...>` 断片) が assistant message
の `.text` に流れ込む。tool は実行されないまま turn 終了 → 気づかず同じ batch を
再 emit → 無限ループに見える (user には「動いていない」)。

memory `feedback_multi_tool_block_serialization_failure` の「arity (1 ターン同時 tool 数)
× payload 複雑度 (長文・quote・markup) が閾値超過で構造化出力が壊れる」が正しい。
**新事実**: 多数 fan-out だけでなく **単発でも複雑 command (複数 `;`/`|` + grep
alternation + 日本語混在)** で誘発する。

### 誤診断の訂正

前 session で AI が自己診断した「tool 呼び出し前に `call` と書くと `antml:` prefix が
脱落する」説は **confabulation (誤り)**。モデルは自分の serializer を観測できない。
`call` は破綻した invoke wrapper の残渣であって原因ではない。

## §2 制約

- slip は **生成中 (parse 前)** に起きるため PreToolUse hook では捕捉不能
  (hook は parse 成功した tool 呼び出しにしか発火しない)。BLOCK 型機械強制は作れない。
- 唯一効くレバー = 「user が気づいて指摘」を「Stop hook が自動検出し次 turn で
  自己是正」に置換する (reactive recovery)。

## §3 採用案

### 検出 (Stop hook `tool-call-slip-detector.sh`)

成功した tool_use は `.type=="tool_use"` で `.text` を持たないため last_assistant
(= `.text` の join) に混入しない。slip 残渣のみ `.text` に現れる。よって最終
assistant `.text` を grep すれば「直前 tool 呼び出しが失敗」を確定できる。

- fenced code block (```` ``` ````) を除去してから照合 — bug の meta 議論で markup を
  引用 (常に fence 内) しても誤検出しないため。slip は fence の外に出る。
- slip 痕跡 regex: standalone `^call$` 行 / `<parameter name=` / `<invoke name=`
  / `</invoke>` / `function_calls>`。
- 検出時 `{"decision":"block","reason":"..."}` で AI を停止させず是正 context 注入
  (同 batch retry 禁止 / 1 ターン 1 件 / 複雑 command は分割 or 専用 smoke 実行 /
  3+ fan-out は Workflow / 前置き語禁止)。
- **mode 非依存** (Normal / Loop 両方で作動) — slip は mode に関係なく起きる。
- 同型先例: `loop-confirmation-detector.sh` (task-41) の構造を踏襲。

### 予防 (規範)

`development-process.md` §「多数 fan-out の Workflow 標準化 + 1 ターン tool block 上限」
に「複雑検証は ad-hoc 複合 grep を inline で組まず、既存/専用 smoke script を 1
コマンド実行」を追記し、slip の発生源 (grep-verify 義務 → 複雑 command 生成) を断つ。

## §4 bypass

| env | 効果 |
|---|---|
| `ECC_TOOL_CALL_SLIP_OFF=1` | 1 セッション一時 OFF (bypass.log 記録) |
| `HC_TOOL_CALL_SLIP_DETECTION_ENABLED=false` | config レベル無効化 (bypass.log 記録) |

fail-open: jq 不在 / transcript 不在 / parse 失敗 → silent exit 0。

## §5 DoD

- [x] `.claude/hooks/tool-call-slip-detector.sh` 新設 (bash -n OK)
- [x] `.claude/tests/tool-call-slip-detector-smoke.sh` 5 ケース PASS
      (positive 2 / negative 2 [clean prose / fence 内引用] / bypass 1)
- [x] `.claude/settings.json` Stop 配列に配線 (loop-confirmation-detector の直後)
- [x] memory + development-process.md 規範更新
- [x] next-actions #66 を resolved に更新

## §8 承認履歴

- 2026-06-01 user が AskUserQuestion で「機械検出 hook + 規範 (推奨)」を選択し承認。
