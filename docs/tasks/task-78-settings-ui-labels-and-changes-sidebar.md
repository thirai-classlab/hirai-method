---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #78: 設定画面 UX 強化 (key 日本語ラベル + 変更内容 右サイドバー、3 列 no-scroll)

> Status: **🔲 未着手** (draft 承認済、PR #59 merge で base 解消)
> 起案: 2026-06-03
> 関連: #76 (2分割UI), #77 (右ペイン key + ENUM_OPTIONS)
> 設計起源: [settings-ui-labels-and-changes-sidebar](../draft/settings-ui-labels-and-changes-sidebar.md) ✅承認済

## Task ゴール

設定画面で (1) 各 key が `key_name (日本語ラベル)` 形式で表示され、(2) 3 列目の右サイドバー「変更内容」が baseline↔draft 差分を `<日本語ラベル> (<key>): <old> → <new>` で live 表示し、(3) 3 列レイアウトでも viewport 100vh no-scroll を維持する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-76 | 2 分割 UI / no-scroll / baseline↔draft 差分算出 を踏襲・拡張 (2列→3列) | [task-76-hc-config-web-2pane-redesign.md](task-76-hc-config-web-2pane-redesign.md) |
| task-77 | metadata.sh / web-server.js / app.js を同じく編集済 (#59 merged)。最新 main から開始で衝突回避 | [task-77-git-integration-policy.md](task-77-git-integration-policy.md) |

## Task 作業概要

- metadata 5 列化 (`...<TAB>label_ja`) + 82 key に短い日本語ラベル + parser/`/api/keys` に label_ja
- 中央 accordion render を `key_name (日本語ラベル)` 形式 (label 空は key 名 fallback)
- 右サイドバー「変更内容」(3 列目): baseline↔draft 差分を `<label> (<key>): <old> → <new>` live 表示、変更なしは「変更なし」
- style.css 2 列→3 列 grid + no-scroll 100vh 維持 + 768px responsive

## Task 完了条件 (DoD)

draft §6 を SSoT。要点: metadata label_ja (82key) + /api/keys 返却 + key-parity 維持 / `key_name (label)` 表示 (fallback) / 右サイドバー live 差分表示 / 3 列 no-scroll (1280-1024 pageScrollable false) + 768 responsive / smoke 全 PASS + regression 0 / visual 合格 / reviewer approve。

## Task 概要欄 (list.md 用、3 要素規範)

設定の可読性と変更前確認のため、key を `key_name (日本語ラベル)` 表示にし 3 列目に「変更内容」右サイドバー (label: old→new) を新設する。完成すれば user が各設定の意味を日本語で把握でき、保存前にどの設定が何から何に変わるかを一覧で確認でき、3 列でも no-scroll を維持する。

## 設計

draft [settings-ui-labels-and-changes-sidebar](../draft/settings-ui-labels-and-changes-sidebar.md) §3 を SSoT (採用案 B、5 列 metadata、3 列 no-scroll)。

## TDD 戦略
- RED: label_ja in /api/keys / `key_name (label)` render / サイドバー差分表示 の smoke を先に
- GREEN: metadata→parser→render→sidebar→css 実装
- REFACTOR: 3 観点

## Step 計画

draft §「Step 計画」を SSoT。

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | ✅ | metadata 5列化 label_ja (84 key) + parser/`/api/keys` label_ja + smoke + tui-smoke 5列対応 (commit 済、84 行 NF≥5 確認) | — |
| 2 | 🔲 | 中央 accordion render `key_name (label_ja)` + 空 fallback (app.js) | 1 |
| 3 | 🔲 | 右サイドバー「変更内容」(app.js: 3列目 + baseline↔draft 差分 live) | 2 |
| 4 | 🔲 | style.css 2列→3列 grid + no-scroll 100vh + 768 responsive | 3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 min≤N≤max (軽め、user 承認済) | 4 |
| 6 | 🔲 | (テスト合格) smoke + visual (3列 no-scroll / 変更内容 live) | 5 |
| 7 | 🔲 | (リファクタリング) 3 観点 | 6 |

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `lib/hc-config-metadata.sh`, `lib/hc-config-web-server.js`(parser/api), `web-ui/{app.js,index.html,style.css}`, web-ui smoke |
| migration | なし |
| 互換性 | label_ja 空 fallback、/api/keys field 追加 (後方互換) |

## 再発防止
- app.js↔index.html id 契約は SSoT 事前明示 (memory feedback_parallel_subagent_cross_file_contract_drift)
- UI は smoke green でも render 不能ありえ visual が最終安全網 (採用 6 条 4)

## ステータスログ
| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-03 | 起案+承認 | draft 承認、PR #59 merge で base 解消、最新 main から着手 |

## 関連
- Draft: [settings-ui-labels-and-changes-sidebar](../draft/settings-ui-labels-and-changes-sidebar.md)
- 依存: #76, #77
