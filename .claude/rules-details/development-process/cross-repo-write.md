> Layer A: [`development-process.md`](../../rules/development-process.md) §cross-repo write 例外 (agent 経路 deny / user manual 専用) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# cross-repo write 起源 (Layer B)

## 実証経緯

- 2026-05-23 task-24 W1 subagent a174bcef696b54860 confidence 0.85 で実証 (cross-repo Write / cp / mv / heredoc redirect が一律 deny、`dangerouslyDisableSandbox: true` 付き Bash も block)
- task-26 W6 / task-21 W3.3 で同じ blocker を再確認、user manual `bash install.sh --update <target>` で 3 リポ反映完了

## 関連 artifact

- Serena memory: `feedback_cross_repo_write_sandbox_block.md` (2026-05-23、本 rule の事実根拠)
- 副産物 entry: `docs/tasks/next-actions.md` entry #17 (2026-05-23、🟡)
- 規範化 task: #31 (本セクション追加)
- audit: `.claude/.workflow-state/bypass.log` (cross-repo agent 試行 block 痕跡)、`harness-audit.py` `bypass_log_summary` (再発検知)

## 関連 memory (緩和方向)

- `feedback_cross_repo_write_sandbox_block.md` (2026-05-26 SUPERSEDED): task-42 Step 9 で 4 リポ全件 agent 直接 Read/Write 成功実証 (classlab-weekly-news / TEST / recall_poc / taskManageSystem confidence 0.92)、cross-repo task は最初に試行 → block 確認で user manual 切替の判断順序に変更

## 将来追随窓口

system-level sandbox 仕様変化 (例: Claude Code が cross-repo Write を opt-in で許可する future feature) への追随は `docs/tasks/parking-lot.md` 🔍「cross-repo sandbox 緩和の future Claude Code 仕様変化追随」entry で四半期 review、Claude Code release notes 監視を user manual で実施。
