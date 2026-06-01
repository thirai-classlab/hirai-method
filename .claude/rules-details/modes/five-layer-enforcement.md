> Layer A: [`modes.md`](../../rules/modes.md) §Loop モード自律規律の 5 層強制機構 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 5 層強制機構 詳細 (Layer B)

本 file は Layer A の SSoT を補完する詳細解説。5 層強制機構の各層動作 source / smoke list 完全版 / 層 6 起源を含む。

## 各層の動作 source code 参照

| 層 | source path | 主要 logic |
|---|---|---|
| 1 | `.claude/rules/modes.md` (本 file 規範) | 遵守事項 7 (subagent 待ち独立作業) + 8 (自律禁止 11 カテゴリ) |
| 2 | `.claude/hooks/loop-auto-progress-reminder.sh` | UserPromptSubmit hook、毎ターン「待ち中報告」regex 検出 + pending Agent tool_use 数集計 → `<system-reminder>` 注入 |
| 3 | `.claude/hooks/autonomous-action-guard.sh` | PreToolUse(Bash) hook、11 カテゴリ regex 照合 → Loop なら `{"decision":"block"}` exit 2 / Normal なら context 注入 + bypass.log 記録 |
| 4 | `.claude/settings.json` (hooks セクション) | UserPromptSubmit 末尾 + PreToolUse Bash 先頭に 5 層 hook を配置 |
| 5 | `.claude/tests/loop-auto-progress-smoke.sh` | 9 ケース smoke (Loop モード ON/OFF × 待ち中報告検出 / 11 カテゴリ block / bypass 動作) |
| 6 | `.claude/hooks/loop-confirmation-detector.sh` | Stop hook、AI 最終 message 出力後に確認質問 regex 検出 → `<system-reminder>` 強制注入で次 turn 自律是正 |

## smoke list 完全版 (9 ケース、`loop-auto-progress-smoke.sh`)

| ケース | 入力 | 期待 |
|---|---|---|
| 1 | Loop モード + 「subagent 完了待ち」発話 | `<system-reminder>` 注入 |
| 2 | Loop モード + pending Agent tool_use 数 ≥ 1 | reminder 注入 |
| 3 | Loop モード + 通常発話 | no-op |
| 4 | Normal モード + 「待ち中」発話 | no-op (Normal は監視外) |
| 5 | Loop モード + `git push origin main` | `{"decision":"block"}` (層 3) |
| 6 | Loop モード + `git push origin feat/xxx` | PASS (task #39 緩和) |
| 7 | Loop モード + `gh pr create` | PASS (task #39 緩和) |
| 8 | Loop モード + `ECC_AUTONOMOUS_ACTION_OVERRIDE=1` + `git push origin main` | PASS + bypass.log 記録 |
| 9 | Loop モード + `HC_AUTONOMOUS_ACTION_ENABLED=false` + `gh pr merge` | PASS + bypass.log 記録 |

## 層 6 (loop-confirmation-detector.sh) task-41 起源

**起源**: 2026-05-26 task-41。

**事案**: 別 session log で「Loop モード自律 patch 着手で OK ですか?」と AI が確認質問を発した事案を user が貼付指摘 (本 session でも user 「Loopモードなのに聞いてきます」指摘あり)。

**設計**:
- Stop hook (AI 最終 message 出力後) で確認質問 regex 検出: 「進めてよいですか」「OK ですか」「お待ちします」「次の指示お待ち」「どちらにしますか」「どうしますか」等
- match 時に `<system-reminder>` で次 turn 自律是正を強制 (BLOCK ではなく warn 注入で物理的に止めない、次 turn で AI が自律是正)
- bypass: `HC_LOOP_CONFIRMATION_DETECTION_ENABLED=false` (config 系統) / `ECC_LOOP_CONFIRMATION_OFF=1` (env 系統)

**他 5 層との差別化**:
- 層 2 (loop-auto-progress-reminder) = UserPromptSubmit (user 発話を受けた直後の AI 思考前)
- 層 6 (loop-confirmation-detector) = Stop (AI 最終 message が出力された直後)
- 両者で「AI の確認質問発話」を時系列の両端から防止
