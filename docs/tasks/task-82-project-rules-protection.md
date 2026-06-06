---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 5
-->

# Task #82: プロジェクトルール保護 (project-rules/ companion + @import)

> Status: **🔄 進行中** (2026-06-06 draft 承認、実装着手)
> 起案: 2026-06-06
> 設計起源: [project-rules-protection](../draft/project-rules-protection.md) ✅承認済 (approved_at 2026-06-06)

## Task ゴール

harness 7 rule (`.claude/rules/*.md`) を update で上書きしつつ project 固有 rule を保護するため、各 harness rule 末尾に `@../project-rules/<name>.md` import を追加し、`.claude/project-rules/<name>.md` companion (project 所有・update 免除) を導入する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| — | 依存なし。自動アップデート roadmap (【3】) の前提機能 (【1】) | — |

## Task 作業概要

- 7 harness rule 末尾に `@../project-rules/<name>.md` + 編集先 pointer 追記 (rules-details は触らない)
- `.claude/project-rules/<name>.md` 7 file 空テンプレ (header 付き) 作成
- install.sh: project-rules create-if-absent (既存 skip) + RSYNC_EXCLUDES に project-rules/ 追加
- README §project-rules 追記 (harness rule vs project rule 分離、編集指針)

## Task 完了条件 (DoD)

draft §6 を SSoT。要点: 7 rule に @import + pointer / project-rules 7 file 作成 / install create-if-absent・既存非上書き・rsync exclude (smoke 実測) / 既存 install smoke regression 0 / README 追記 / bash 3.2 互換。

## Task 概要欄 (list.md 用、3 要素規範)

update で project 固有 rule が消える問題を解消するため harness rule から @import する project-rules/ companion (update 免除) を導入する。完成すれば harness 共通 rule は update 追従しつつ project 固有 rule は永続保護され、7 harness file を触らず project-rules/ 編集で拡張・override でき、自動アップデート (【3】) の安全な前提が整う。

## 設計

draft [project-rules-protection](../draft/project-rules-protection.md) §3 を SSoT (harness-config.local.yml と同型の保護モデル、@import 結合)。

## Step 計画

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | 7 rule 末尾に @import + pointer / project-rules 7 file 空テンプレ作成 | — |
| 2 | 🔲 | install.sh project-rules create-if-absent + rsync exclude + summary / README §追記 | 1 |
| 3 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 2 |
| 4 | 🔲 | (テスト合格) @import/companion/create-if-absent/update 非上書き/rsync exclude smoke + regression 0 | 3 |
| 5 | 🔲 | (リファクタリング) 3 観点 or skip | 4 |

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/rules/*.md` (7、末尾 @import のみ), `.claude/project-rules/*.md` (新規 7), `install.sh`, `README.md`, smoke |
| migration | なし (consuming repo は次回 update で project-rules 自動作成) |
| 互換性 | @import は project-rules 不在でも無害 (空 import)、既存 rule 本体不変、install 既存挙動非破壊 |

## 再発防止
- @import 行は harness source の 7 file に含める (update 再配布で消えない)
- project-rules は rsync exclude + create-if-absent 二重保護

## ステータスログ
| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-06 | 起案+承認+着手 | user roadmap 【1】、@import 実現性 conf 0.97 確定、実装着手 |

## 関連
- Draft: [project-rules-protection](../draft/project-rules-protection.md)
- roadmap: 【2】npx 化 / 【3】自動アップデート (本 task は前提)
