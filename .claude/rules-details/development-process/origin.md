> Layer A: [`development-process.md`](../../rules/development-process.md) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 起源 (Layer B)

- **コーディング指針 (karpathy-guidelines)**: 採用済 skill `.claude/skills/karpathy-guidelines/SKILL.md`、LLM コーディング行動規約の SSoT
- **TDD 4 step**: 採用済 skill `.claude/skills/tdd-workflow/SKILL.md` 由来
- **委譲必須要件 7 件**: 各要件の起源は各 §「起源」 (要件 6: task-35 / 要件 7: task-35 + task-34)、規範化 task #38
- **staging 戦略**: task #12 (2026-05-13)、規範化 task #13
- **cross-repo write 例外**: task-24 W1 / task-26 W6 / task-21 W3.3 (2026-05-23)、規範化 task #31、緩和 task-42 (2026-05-26)
- **Confidence Gate F3**: F3 confidence-gate.sh、`docs/CONFIDENCE-GATE.md` SSoT、major subagent only block は task #9 (2026-05-13)
- **harness 取込チェックリスト**: task-59 (G2、2026-05-28)、前提 task-56 (F) / task-58 (G1)
- **副産物即時 draft 起こし義務**: `docs/draft/byproduct-discharge-mechanism.md`、強制機構は次セッション実装予定
- 各規範の commit hash / 採用判断は git log + 関連 draft 参照
