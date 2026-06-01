> Layer A: [`development-process.md`](../../rules/development-process.md) §サブエージェント委譲の必須要件 7 件 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 並列化義務 起源 (Layer B)

## 並列化義務 (要件 6) の起源

- 2026-05-25 task-35 Step 1+2+4 を 1 subagent に統合委譲した実例 (本来 3 並列起動可能だった file 領域独立 sub-task)
- 設計 draft: `docs/draft/parallel-subagent-enforcement.md` §4.1 (規範強化部)
- 副産物 entry #23
- 規範化 task: #38

## agent type 選定義務 (要件 7) の起源

- 2026-05-25 task-35 Subagent B (test 拡張) で `general-purpose` 採用、`test-automator` を逃失
- 2026-05-25 task-34 Step 5 (refactor) で `general-purpose` 採用、`refactoring-specialist` を逃失
- user 強調要件「設定不要で自動的に判断」(2026-05-25 13th save-state 後)
- 設計 draft: `docs/draft/parallel-subagent-enforcement.md` §4.5 + §4.5.0 設定不要原則
- 規範化 task: #38

## Hook による補助 (soft warning)

`.claude/hooks/agent-marker-set.sh` は PreToolUse(Agent) で foreground 起動を検出した場合、stderr に WARN を出す (block ではない)。`tool_input.run_in_background != true` のときに発火。
