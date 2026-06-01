> Layer A: [`workflow.md`](../../rules/workflow.md) §workflow-guard.sh による強制機構 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# workflow-guard 強制機構 詳細 (Layer B)

`workflow-guard.sh` の発火タイミング・判定 A/B 概要・bypass は Layer A 参照。本 file は判定ロジックの詳細手順と state JSON schema field 表。

## 判定ロジック (構造化 JSON 解析、grep 依存禁止)

1. `tool_name == "Bash"` で `command` に `/finish-task <slug>` パターン (`^[a-z0-9][a-z0-9-]{2,48}$`) 検出
2. `.claude/.workflow-state/<slug>.json` 読み (不在なら旧 task 互換で silent pass)
3. `workflow_type` から stage 列を解決
4. **判定 A**: `current_stage` が stage 列の **最終要素** (new=`finish` / modify=`system-review`)
5. **判定 B**: `pending_findings.module_review` と `pending_findings.system_review` が **両方とも空配列**
6. A / B いずれか fail なら **exit 2 (BLOCK)** + stderr に「問題」「推奨アクション」「bypass 手順」出力

stage 名で判定する設計 (round-2 arch-rev H3 反映、step 番号や順序判定ではない)。

## state JSON schema

`.claude/.workflow-state/<slug>.json` 構造定義は [`SCHEMA.md`](../../.workflow-state/SCHEMA.md) が SSoT。主要 field:

| Field | 型 | 説明 |
|---|---|---|
| `slug` | string | 機能識別子。ファイル名と一致 |
| `workflow_type` | `"new" \| "modify"` | どちらの workflow か |
| `current_stage` | string | 現在進行中の stage 名 |
| `completed_stages` | string[] | 完了済 stage の配列 (順序保持) |
| `pending_findings` | object | `module_review` / `system_review` の未解決 findings 配列 |
| `skip_log` | object[] | skip された stage の audit |
| `created_at` / `updated_at` | ISO-8601 UTC | timestamp (秒精度、`Z` suffix) |

state JSON 本体 (`<slug>.json`) は `.gitignore` で除外、`SCHEMA.md` / `bypass.log` / `bypass.log.template` のみ git track。

## bypass.log 集計の補足

`harness-audit.py` の `bypass_log_summary()` が `.claude/.workflow-state/bypass.log` を集計し `/harness-audit` で最近 N 日の bypass を表示する。両系統 (env `ECC_WORKFLOW_GUARD_OFF` / config `HC_WORKFLOW_GUARD_ENABLED`) 併存は env と config から独立に bypass 可能とし、片方が誤って enabled なまま放置される事故を防ぐ設計 (round-2 sec-rev H3 反映)。
