> Layer A: [`task-management.md`](../../rules/task-management.md) §既存 task 移行ガイド | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 既存 task 移行 詳細 (Layer B)

## 移行優先度 (G2 → G3)

| task | 状態 | 優先度 | 備考 |
|---|---|---|---|
| **task-33 (list-md-plan-first-normative)** | 5 Phase 構造 (Phase 1 完遂、Phase 2 Step 2.2 まで) | **本 commit で即 restructure** | 本規範改定の起源、Wave C-1 で 5 task (33/34/35/36/37) に分割 |
| task-21 (system-reminder-attention) | W3 残 | **最優先** | 規範整備系で本規範の起源とも近い、整合性確保 |
| task-23 (recall-poc-recovery) | W4-W5 残 | 高 | 実装系、Wave 跨ぎの依存が多い |
| task-24 (taskmanagesystem-recovery) | W5 残 | 高 | 規範整備系、本 rule との整合性確保 |
| task-27 (observe-jq-parse-fix) | W3 残 | 中 | W3 不要判定検討中、不要なら低優先度に降格可 |
| task-28 (observe-subagent-stop-instrumentation) | Phase 2 残 | 中 | 既に Phase 命名を採用、Step 粒度のみ要確認 |

移行作業は task 着手前 (`/start-task <id>` 実行前後) の準備として実施。新構造へ書き換えても commit 履歴・既存 Phase / Wave での完了実績は temporal record として残す (削除しない)。
