---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 5
-->

# Task #80: install.sh settings.json 自動再生成 (default) + .gitignore state dir 追記

> Status: **✅ 完了** (2026-06-05、smoke 7/7 + regression 8/8+7/7、review approve + L-1/M-1/M-2 修正済)
> 起案: 2026-06-05
> 設計起源: [install-auto-regen-settings](../draft/install-auto-regen-settings.md) ✅承認済 (approved_at 2026-06-05)

## Task ゴール

`install.sh` の sync mode (update/force/overwrite-all) で rsync 後に `generate-settings.sh` を **default 自動実行**し、statusLine / dispatcher 配線を consuming repo に同期する (既存 permissions 保持・既存 settings.json 不在時は skip)。加えて `.claude/.gitignore` に runtime state dir 6 種を追記し `git add .claude` への混入を防ぐ。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-62 | statusLine 配線を generate-settings.sh に組込済 (本 task が install で同期) | [task-62-statusline-construction.md](task-62-statusline-construction.md) |
| task-71 | settings.json を generated artifact 化 + rsync exclude (本 task が再生成で配線同期) | [task-71-settings-dispatcher-generation.md](task-71-settings-dispatcher-generation.md) |
| task-79 | install mode (overwrite-all 含む) に自動再生成を組込 | [task-79-install-full-overwrite-mode.md](task-79-install-full-overwrite-mode.md) |

## Task 作業概要

- install.sh: rsync 後 (section 6 chmod と 6.5 stamp の間) に settings.json 自動再生成。条件 = MODE ∈ {update,force,overwrite-all} ∧ 非 dry-run ∧ jq あり ∧ generate-settings.sh 配布済 ∧ 既存 settings.json あり (不在 skip)。fail-open
- summary の手動 hint を「自動実行済 (失敗時のみ手動)」へ更新 + 独自 key/hook 脱落注記
- `.claude/.gitignore` に 6 行追記 (`.preset-history/` / `.reviewer-count-state/` / `.context-budget-state/` / `.workflow-state/` / `.task-screenshots/` / `.session-help-shown`)

## Task 完了条件 (DoD)

draft §6 を SSoT。要点: --update (既存 settings.json あり) で自動再生成 + statusLine block 含有 / permissions 保持 / settings.json 不在・jq 不在・dry-run で skip / .gitignore 6 entry / 既存 install smoke regression 0 / summary 更新 / bash 3.2 互換。

## Task 概要欄 (list.md 用、3 要素規範)

consuming repo で statusbar/配線が同期されない問題を解消するため install sync mode で settings.json を default 自動再生成し .gitignore に state dir を追記する。完成すれば install 後に手動 generate-settings なしで statusLine/dispatcher が反映され、permissions は保持され、git add .claude に transient state が混入しなくなる。

## 設計

draft [install-auto-regen-settings](../draft/install-auto-regen-settings.md) §3 を SSoT (案 B、自動再生成 + 安全条件 + .gitignore)。

## Step 計画

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | ✅ | install.sh 6.3 自動再生成組込 (条件 guard + subshell fail-open + HC_PROJECT_ROOT 注入 + summary 更新 + mode 別 permissions 注記) | — |
| 2 | ✅ | .claude/.gitignore に state dir 6 行追記 (comment 付き) | — |
| 3 | ✅ | (テスト設計レビュー) code-reviewer: CRIT/HIGH 0、M-1(overwrite-all doc)/M-2(force 実挙動)/L-1(ROOT 保険) approve → 修正反映 | 1,2 |
| 4 | ✅ | (テスト合格) regen-settings smoke 7/7 + regression overwrite-all 8/8 + sync-drift 7/7 PASS | 3 |
| 5 | ✅ | (リファクタリング) review 修正が兼務 (force 誤記訂正 / doc 整合)、追加 skip | 4 |

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `install.sh` (section 6 + summary), `.claude/.gitignore`, install smoke |
| migration | なし |
| 互換性 | 既存 install/update/force/overwrite-all 非破壊 (再生成は追加 step)、permissions 保持 |

## 再発防止
- 既存 settings.json 不在で die する generate-settings.sh の前提を条件 guard で回避
- 独自 hook は dispatcher-manifest 登録が正運用 (summary に明記)

## ステータスログ
| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-05 | 起案+承認+着手 | user「ステータスバー同期されてない」報告 → 案 B 選択承認、実装着手 |

## 関連
- Draft: [install-auto-regen-settings](../draft/install-auto-regen-settings.md)
- 依存: #62, #71, #79
