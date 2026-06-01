> Layer A: [`modes.md`](../../rules/modes.md) §関連 artifact (代表) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 関連 artifact 完全 list (Layer B)

本 file は Layer A に掲載する代表 4 件を補完する完全 artifact list。mode 系 hook / 5 層強制機構 / 設定 state / 設計起源 draft path を含む。

## mode 系 hook

- `.claude/hooks/mode-session-start.sh` (SessionStart、モード表示 / 切替提案)
- `.claude/hooks/mode-enforce.sh` (UserPromptSubmit、遵守事項再注入)
- `.claude/hooks/context-budget.sh` (UserPromptSubmit、context tier 監視)
- `.claude/hooks/lib/mode-loader.sh` (共通 lib、mode 解決)

## 5 層強制機構

- `.claude/rules/modes.md` (層 1、規範本体 = Layer A)
- `.claude/hooks/loop-auto-progress-reminder.sh` (層 2、UserPromptSubmit)
- `.claude/hooks/autonomous-action-guard.sh` (層 3、PreToolUse Bash)
- `.claude/settings.json` (層 4、hook 配線)
- `.claude/tests/loop-auto-progress-smoke.sh` (層 5、9 ケース smoke)
- `.claude/hooks/loop-confirmation-detector.sh` (層 6、Stop hook)

## 設定 / state

- `.claude/mode.yml` (mode 永続化、`mode: normal|loop`)
- `.claude/harness-config.yml` (`context_budget_threshold` / `HC_*` env 集中管理)
- `.claude/.workflow-state/bypass.log` (bypass 追跡 audit log)
- `.claude/.workflow-state/context-budget-tiers.json` (tier 発火状態)

## 設計起源 draft (採用プロジェクト側、本 harness は portable 設計のため path のみ参照)

- `docs/draft/loop-auto-progress-enforcement.md` (遵守事項 7+8 起源)
- `docs/draft/loop-mode-list-md-auto-enque.md` (遵守事項 9 起源、task #47)
- `docs/draft/task-equals-phase-step-status-list-normative.md` (task-management.md 採用 6 条と連動)
