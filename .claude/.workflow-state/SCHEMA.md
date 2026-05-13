# Workflow State Schema

`workflow-guard.sh` が参照する session-local state ファイルの schema 定義。

## ファイル

```
.claude/.workflow-state/<slug>.json
```

`<slug>` は `/new-feature <slug>` または `/modify-feature <slug>` で指定された
kebab-case の機能識別子（例: `loop-mode`, `proxy-rate-limit`）。
1 機能 1 ファイル、session を跨いで保持される。

## フィールド一覧

| Field | Type | 説明 |
|---|---|---|
| `slug` | `string` | 機能の kebab-case 識別子。ファイル名と一致。 |
| `workflow_type` | `"new" \| "modify"` | `/new-feature` で起こされた新規機能か、`/modify-feature` で起こされた既存機能修正か。 |
| `current_stage` | `string` | 現在進行中の workflow stage 名（`harness-config.yml` の `workflow_stages_new` / `workflow_stages_modify` のキー名）。 |
| `completed_stages` | `string[]` | 完了済 stage の配列。順序は完了順。 |
| `pending_findings` | `object` | レビュー stage で出された未解決の findings（後述）。 |
| `skip_log` | `object[]` | ユーザ承認によって skip された stage の audit ログ（後述）。 |
| `created_at` | `string` (ISO-8601) | state ファイル作成時刻。例: `2026-05-12T14:30:00Z`。 |
| `updated_at` | `string` (ISO-8601) | 最終更新時刻。stage 遷移や finding 追加で更新。 |

### `pending_findings`

レビュー stage（`module_review`, `system_review`）で発見された未解決の指摘事項。
各カテゴリは finding object の配列。

```
{
  "module_review": [<finding>, ...],
  "system_review": [<finding>, ...]
}
```

#### Finding object

| Field | Type | 説明 |
|---|---|---|
| `id` | `string` | finding の一意 ID（例: `MR-001`, `SR-003`）。 |
| `severity` | `"CRITICAL" \| "HIGH" \| "MEDIUM" \| "LOW"` | 重要度。`CRITICAL` / `HIGH` が残っている間は次 stage へ進めない。 |
| `summary` | `string` | 指摘内容の 1〜2 文要約。 |

### `skip_log`

`/task-bypass` 等で stage を skip した際の audit エントリ。

| Field | Type | 説明 |
|---|---|---|
| `stage` | `string` | skip された stage 名。 |
| `reason` | `string` | ユーザが提示した skip 理由。 |
| `user_approved_at` | `string` (ISO-8601) | ユーザ承認時刻。 |

## Timestamp 規約

全 timestamp は **ISO-8601 UTC** 表記、秒精度、`Z` suffix。
例: `2026-05-12T14:30:00Z`

## Sample JSON

```json
{
  "slug": "loop-mode",
  "workflow_type": "new",
  "current_stage": "module_review",
  "completed_stages": [
    "draft",
    "design_review",
    "test_design",
    "tdd_red",
    "tdd_green"
  ],
  "pending_findings": {
    "module_review": [
      {
        "id": "MR-001",
        "severity": "HIGH",
        "summary": "mode-loader.sh の YAML parse が env override 未対応"
      },
      {
        "id": "MR-002",
        "severity": "MEDIUM",
        "summary": "context-budget.sh の閾値 hardcode を harness-config から読む"
      }
    ],
    "system_review": []
  },
  "skip_log": [
    {
      "stage": "test_design",
      "reason": "既存テスト設計を流用、新規テスト観点なし",
      "user_approved_at": "2026-05-12T11:15:00Z"
    }
  ],
  "created_at": "2026-05-12T09:00:00Z",
  "updated_at": "2026-05-12T14:30:00Z"
}
```

---

**注意:** このファイルは git track 対象。実 state JSON (`<slug>.json`) は `.gitignore` で除外される。
