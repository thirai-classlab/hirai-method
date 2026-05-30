---
asana_url: ""
slack_urls: []
deadline: ""
requester: "takuma.hirai1@gmail.com"
---

<!--
# 採用 6 条 (Task=Phase=N Step、2026-05-25 採用) metadata
total_steps: 8
-->

# Task #64: reviewer 数 config 強制実装

> Status: **🔲 未着手**
> 起案: 2026-05-30
> 設計起源: [reviewer-count-enforcement.md](../draft/reviewer-count-enforcement.md) ✅承認済 (approved_at "2026-05-30" / approved_by "takuma.hirai1@gmail.com")

## Task ゴール

`.claude/harness-config.yml` の reviewer 制御値 (`review_*_count_*` / `review_required_*` / `review_iteration_max`) が **実際に reviewer 起動数を制御する**状態に置き換わる。`hc-config.sh --set review_max_count_test=3` → 次回 review で main が 3 以内に絞り、hook が超過時 warn する。値は `harness-config.local.yml` に移行して `install.sh --update` で温存。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-44 | config-yml Phase 1 (yml schema + config-loader.sh)。review_* key 定義 + `is_feature_enabled` 基盤を継承し、本 task で行末コメント strip 修正 + enforcement を追加 | [task-44-config-yml-phase1-schema-loader.md](task-44-config-yml-phase1-schema-loader.md) |
| task-45 | config-yml Phase 2 (hook feature check + review command yml 参照)。command Phase 0 記述を継承し、本 task で具体 `hc-config.sh --get` 実行手順に格上げ | [task-45-config-yml-phase2-hook-review-command.md](task-45-config-yml-phase2-hook-review-command.md) |
| task-55 | harness-config.local.yml override 導入。本 task で review_* を local.yml に移行 (--update-safe) | [task-55 (harness-config 保護)](list.md) |

## Task 作業概要

- `config-loader.sh` の単行 value parser に行末コメント strip を追加 (`HC_REVIEW_MAX_COUNT_TEST=10` clean export、`hc-config.sh _yml_get_raw` と挙動統一)
- `review_*` 系 key を `harness-config.local.yml` に移行 (値現状維持、--update 温存)
- 採用 6 条 4「reviewer 5+」を「`review_min_count_test`〜`review_max_count_test` 範囲で動的選定 + 起動前 `hc-config.sh --get` 確認」に書換、details.md drift 同期
- 4 command (test/design/module/system-review) の Phase 0 + 採用 6 条 4 に具体 `hc-config.sh --get review_max_count_<cat>` 実行手順追加
- PreToolUse(Agent) で同一 turn の review subagent 起動数をカウントし `review_max_count_*` 超過時 warn する hook 新設 (feature toggle + bypass)

## Task 完了条件 (DoD)

- [ ] `config-loader.sh` が `review_max_count_test` を clean 数値 (`10`、行末コメントなし) で export
- [ ] `review_*` が `harness-config.local.yml` に存在し `install.sh --update` で温存 (値現状維持)
- [ ] 採用 6 条 4 + 4 command Phase 0 に `hc-config.sh --get review_max_count_<cat>` 実行手順明記、「5+」青天井表現全廃
- [ ] PreToolUse(Agent) hook が reviewer 数 > `review_max_count_*` で warn 注入 (smoke 発火検証)、bypass env 動作
- [ ] feature toggle `feature_reviewer_count_guard_enabled` で OFF 可能
- [ ] `hc-config.sh --set review_max_count_test=3` → 次回 review で main が 3 以内 (honor + hook 二重)
- [ ] 既存 smoke 全 PASS (config-loader 経由の他 hook regression 0)
- [ ] reviewer 5+ 強制の旧記述が task-management.md / details.md / workflow.md から消える

## Task 概要欄 (list.md 用、3 要素規範)

reviewer 制御値が動作に影響しない「飾り」状態 (root cause: honor-system 不在 + 規範矛盾「5+」+ config-loader コメント汚染 + 値非永続) を解消するため、config-loader strip 修正 + local.yml 移行 + 採用 6 条 4「5+」撤廃 + command Phase 0 実行手順化 + PreToolUse(Agent) 強制 hook を実装する。完成すれば user が `hc-config.sh --set review_max_count_*` で設定した reviewer 数上限が honor step + hook の二重で実効化され、--update でも消えなくなる。

## Step 計画

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | config-loader 行末コメント strip 修正 + 既存 key regression smoke | 1.0h | — |
| 2 | 🔲 | review_* を harness-config.local.yml 移行 (値現状維持) + 優先順 fallback 確認 | 0.5h | Step 1 |
| 3 | 🔲 | 採用 6 条 4「5+」→ yml 範囲 規範修正 + details.md drift 同期 | 0.5h | — |
| 4 | 🔲 | command Phase 0 + 採用 6 条 4 に hc-config.sh --get 実行手順追加 (4 command + rule) | 0.5h | Step 3 |
| 5 | 🔲 | PreToolUse(Agent) reviewer 数上限 warn hook 新設 + feature toggle + smoke | 1.5h | Step 1 |
| 6 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (本 task 確定の yml 範囲に従う) + iter cycle | 0.5h | Step 5 |
| 7 | 🔲 | (テスト合格) 全 smoke + hook 発火検証 + config-loader regression 0 | 0.5h | Step 6 |
| 8 | 🔲 | (リファクタリング) 3 観点判定 | 0.25h | Step 7 |

合計: 約 4.5h

## 影響範囲

draft §11 affects_files 参照: `.claude/rules/{task-management,workflow}.md` + `rules-details/task-management.details.md` + `.claude/commands/{test-design,design-review,module-review,system-review}.md` + `.claude/hooks/{parallel-subagent-reminder.sh,lib/config-loader.sh}` + `.claude/harness-config{,.local}.yml`。

## 再発防止

config 値の「飾り化」(定義のみで consumer 不在) を防ぐため、新規 config 値追加時は「consumer (読んで動作制御する主体) + smoke (値変更で動作が変わる検証)」を同時に実装する規範を Step 3 で task-management.md or development-process.md に追記検討。

## 関連

- Draft: [reviewer-count-enforcement.md](../draft/reviewer-count-enforcement.md) ✅承認済
- 調査: subagent ae14acad6fe7ff3fc (2026-05-30、conf 0.9)
- 依存タスク: task-44/45 (config-yml Phase 1-2)、task-55 (local.yml override)
- 関連 rule: `.claude/rules/task-management.md` 採用 6 条 4 / `.claude/rules/workflow.md` 収束条件
