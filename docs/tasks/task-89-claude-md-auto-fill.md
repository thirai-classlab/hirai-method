---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 7
-->

# Task #89: CLAUDE.md auto-fill (project 検出 + 言語別 starter、placeholder 0 化、P1-5)

> Status: **🔄 進行中** (2026-07-05 着手、branch `feat/p1-wave3-claudemd-mcpjson`)
> 起案: 2026-07-05 / 承認: 2026-07-05 (AI 推奨どおり全判断点承認)
> 関連: Phase 1 (#85-#91)、master roadmap install-immediately-usable-redesign-20260618 §4.3 対策 A/C/§5 P1-5
> 設計起源: [claude-md-auto-fill.md](../draft/claude-md-auto-fill.md)

## Task ゴール

新規 install 直後に manifest 検出 (6 言語 + generic) → 言語別 starter template render で `<...>` placeholder 0 の CLAUDE.md が自動配置され、既存 CLAUDE.md は不可侵 (md5 不変 + .bak 非生成 + CommonRules 参照 HINT のみ) が成立する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-85 | install.sh 同域 (arg parse L68-106 / header / summary) 編集の序列化 (file 競合回避目的の soft 依存、設計上の機能依存はなし) | [task-85-install-preset-auto-switch.md](task-85-install-preset-auto-switch.md) |

## Task 作業概要

- 言語別 starter template 7 件新設 (`.claude/templates/CLAUDE.md.example.{ts,py,go,rust,php,swift,generic}.md`、`{{TOKEN}}` 4 種)
- install.sh に `detect_project_lang()` / `extract_manifest_fields()` / `render_claude_md()` + `--lang=<id>` arg
- 既存 CLAUDE.md 不可侵化 (.bak 退避廃止) + CommonRules 参照 HINT + docs 文言更新
- 新 smoke `install-claude-md-autofill-smoke.sh` (≥ 12 case)

## Task 完了条件 (DoD)

- [ ] placeholder 0: dummy package.json repo への install 後 `grep -c '\`<' CLAUDE.md` = 0
- [ ] `@.claude/CommonRules.md` 参照行が生成 CLAUDE.md に存在
- [ ] auto-fill 実質: manifest 由来値 (name / test command) が実際に埋まる
- [ ] 既存不可侵: default install 前後で md5 一致 + .bak 非生成 + HINT 行出力 (CommonRules 行不在時)
- [ ] `--dry-run` で CLAUDE.md 非生成
- [ ] 新 smoke 全 case (≥ 12) PASS + 既存 install 系 smoke 4 本 regression 0
- [ ] docs 反映 (install.sh header / summary / README / PORTABILITY)

## Task 概要欄 (list.md 用)

install 直後に placeholder 手動埋めが必要な矛盾 (R3) を解消するため、install.sh が manifest 6 種を検出し言語別 starter template を token render で CLAUDE.md として自動生成する (既存 CLAUDE.md は不可侵 + CommonRules 参照 HINT)。完成すれば install 直後に `<...>` placeholder 0 の即使える CLAUDE.md が配置され、subscbase-api 型の template 放置が構造再発しなくなる。

## Step 計画 (SSoT: draft §3 「Step 計画」)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | 言語別 starter template 7 件新設 (`{{TOKEN}}` 4 種形式) | 1.5h | — |
| 2 | 🔲 | install.sh 関数 3 本 + `--lang` arg parse + §2 block 差し替え | 2.5h | Step 1 |
| 3 | 🔲 | 既存 CLAUDE.md 不可侵化 + HINT + header/summary/README/PORTABILITY 文言更新 | 1.0h | Step 2 |
| 4 | 🔲 | smoke 新設 (≥ 12 case: 6 言語 / generic / 優先順 / --lang / 不可侵 / HINT / dry-run / fallback / update) | 1.5h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定、収束まで反復 | 0.5h | Step 4 |
| 6 | 🔲 | (テスト合格) 新 smoke 全 PASS + 既存 install 系 4 本 regression 0 | 0.5h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点 (§6.6 version 抽出 chain との関数共通化含む) or `skip: <reason>` | 0.5h | Step 6 |

合計: 8.0h (≒ roadmap P1-5 見積 1 day と整合)

> **注意**: install.sh header 行数変更時は install.sh:90 の `-h` sed 範囲を同 commit で更新 (task-79 前例)。着手順序列化 #85 → #89 → #90 (2026-07-05 横断レビュー M6)。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-05 | 起案 | draft 起こし (PR #69) |
| 2026-07-05 | 承認 | user 承認 (AI 推奨どおり: .bak 退避廃止 / 6 言語 + generic v1 / template 経路は fallback のみ / framework whitelist v1 最小)、list.md 🔲 化 |

## 派生 task / 次アクション候補

(発生時に必ず記入 — development-process.md §「副産物発生時の即時 draft 起こし義務」)

## 関連

- Draft: [claude-md-auto-fill.md](../draft/claude-md-auto-fill.md)
- 序列: #85 → #89 → #90 (install.sh 同域編集)
