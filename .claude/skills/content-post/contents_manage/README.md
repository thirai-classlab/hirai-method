# contents_manage — コンテンツバージョン管理

## 目的

1. **バージョン管理**: 全コンテンツ (tech_article / weekly_issue / knowledge) のソース markdown + スナップショット HTML をローカルファイルで世代管理する
2. **DB 上書き防止**: `post.ts --update` 実行時に DB の現状を必ず退避してから UPDATE を実行する (fail-safe)
3. **公開状況管理**: 各 slug の「現在公開されているバージョン」をローカルで把握する
4. **Roll-back**: 任意の過去バージョンに戻せる

## ディレクトリ構造

```
contents_manage/
├── README.md                                # 本ファイル
├── images/                                  # 全画像の Single Source of Truth
│   ├── {sha256}.{ext}                       # 画像本体 (content hash 命名で重複排除)
│   └── ...
└── contents/
    └── {slug}/
        ├── meta.json                        # 公開状況 + バージョン履歴
        └── v{N}/                            # バージョン番号 (1 から連番)
            ├── post.md                      # 投稿用 markdown (single source of truth)
            ├── snapshot.html                # 当該版を post した直後の DB body の写し (roll-back 用)
            └── snapshot-before-update.html  # --update 前の DB body の退避 (次バージョン作成時)
```

## meta.json スキーマ

```json
{
  "slug": "example-slug",
  "kind": "tech_article | weekly_issue | knowledge",
  "title": "記事タイトル",
  "current_version": 2,
  "published_version": 1,
  "published_at": "2026-04-26T15:52:40Z",
  "versions": [
    {
      "v": 1,
      "created_at": "2026-04-26T02:55:00Z",
      "author": "first post",
      "snapshot_taken": true,
      "note": "初回投稿"
    },
    {
      "v": 2,
      "created_at": "2026-04-27T01:00:00Z",
      "author": "post.ts --update",
      "snapshot_taken": true,
      "note": "auto-created by post.ts --update"
    }
  ]
}
```

### フィールド定義

| フィールド | 型 | 説明 |
|---|---|---|
| `slug` | string | DB の slug と一致 |
| `kind` | string | `tech_article` / `weekly_issue` / `knowledge` |
| `title` | string | DB の title |
| `current_version` | number | 最新バージョン番号 |
| `published_version` | number | 現在本番に公開されているバージョン |
| `published_at` | string (ISO8601) | DB の published_at |
| `versions` | array | バージョン履歴 |
| `versions[].v` | number | バージョン番号 |
| `versions[].created_at` | string (ISO8601) | 作成日時 |
| `versions[].author` | string | 作成者 / 操作 |
| `versions[].snapshot_taken` | boolean | DB スナップショットを取得済みか |
| `versions[].note` | string (optional) | 補足メモ |

## ワークフロー

### 新規投稿 (`post.ts --file path/to/draft.md`)

1. 投稿前: `contents/{slug}/v1/post.md` にコピー
2. `post.ts` が DB INSERT
3. INSERT 完了後: DB の body を `contents/{slug}/v1/snapshot.html` に書き戻し
4. `meta.json` に v1 + published_version=1 を記録

### 既存記事更新 (`post.ts --file path --update --slug X`)

1. **必須前処理**: DB の現状 body を取得
2. **必須**: `contents/{slug}/v{N+1}/snapshot-before-update.html` に退避 (上書き防止)
   - この退避が失敗した場合、post.ts は中断し DB 書き込みは発生しない
3. 渡された markdown を `contents/{slug}/v{N+1}/post.md` にコピー
4. `post.ts` が DB UPDATE
5. UPDATE 後: DB の新 body を `contents/{slug}/v{N+1}/snapshot.html` に保存
6. `meta.json` 更新 (current_version + 1, published_version=新版)

### Roll-back (`scripts/rollback.ts --slug X --to-version N`)

1. `contents/{slug}/vN/snapshot.html` を読む
2. DB body を直接 UPDATE (markdown 再処理せず HTML をそのまま書き戻し)
3. `meta.json` の published_version を N に更新

### --update で `--file` を省略した場合

`post.ts` は `contents/{slug}/v{current_version}/post.md` を自動的に読み込む。
contents_manage に該当ファイルが存在しない場合はエラー終了。

## 注意事項

- **version ディレクトリは削除しない**: アーカイブ性保持のため、過去バージョンは永続保管する
- **meta.json は手書きしない**: 必ずスクリプト (`scripts/seed-contents-manage.ts` や `src/posting/version-manager.ts`) 経由で生成する (フォーマット統一)
- **images/ は git LFS 対象候補**: 画像が増えたら `git lfs track "contents_manage/images/*"` を検討する
- **contents_manage/ は git で管理**: 別マシン共有 + git history が二重バックアップになる

## バージョン命名規則

- バージョン番号は 1 から始まる連番 (`v1`, `v2`, `v3`, ...)
- バージョン番号は絶対に再利用しない
- ディレクトリ名は `v{N}` (ゼロパディングなし)
