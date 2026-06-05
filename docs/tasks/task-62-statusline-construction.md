---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #62: Claude Code ステータスライン構築

> Status: **✅ 完了** (2026-06-04、smoke 17/17 + regression、review HIGH 2/MED 1/LOW 2 修正済。live 複数行目視は user 確認可)
> 起案: 2026-06-04 (task-62 は元 📝 保留、本日 user 擦り合わせで仕様確定)
> 設計起源: [statusline-construction](../draft/statusline-construction.md) ✅承認済 (approved_at 2026-06-04)

## Task ゴール

Claude Code の `statusLine` 機能で、2 行・絵文字なし・ANSI 色 (Claude Code 踏襲) のステータスラインを構築し、mode / context% / Claude 5h・7d 制限残り% / git branch / model / Web UI 起動ヒント (`.claude/scripts/hc-config.sh`) を表示する。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| — | 依存なし (statusLine は独立機能) | — |

## Task 作業概要

- `.claude/scripts/statusline.sh` 新設: stdin JSON を jq parse + `.claude/mode.yml` read + 2 行整形 + ANSI 色 + graceful fallback
- 数値元: ctx=`context_window.used_percentage` / 5h・7d=`100 - rate_limits.*.used_percentage` (Pro/Max 限定→不在時 `—`) / model=`model.display_name` / branch=`workspace.repo.*` / mode=mode.yml
- settings.json 配線を generate-settings.sh に組込 (portable)
- 絵文字なし、ANSI 色のみ (残り% 閾値着色 / 区切り dim)

## Task 完了条件 (DoD)

draft §6 を SSoT。要点: 2 行表示 (mode/ctx/5h/7d/branch/model/hint) 実機目視 / rate_limits 不在 `—` fallback / jq 不在 plain 降格非破壊 / 絵文字なし ANSI のみ / generate-settings.sh 再生成で再現 (portable) / 既存 smoke regression 0 / bash 3.2 互換。

## Task 概要欄 (list.md 用、3 要素規範)

作業効率と利用状況把握のため、Claude Code statusLine で mode/context%/Claude 利用制限残り%/branch/model/設定 UI ヒントを 2 行表示する。完成すれば常時 context と週間/時間制限の残量を視認でき、現在の動作モードと branch を把握でき、設定変更 Web UI の起動コマンドを常に確認できる。

## 設計

draft [statusline-construction](../draft/statusline-construction.md) §3 を SSoT (採用案 A、2 行 ANSI、graceful fallback)。

## Step 計画

draft §「Step 計画」を SSoT。

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | ✅ | 複数行 statusLine render 確認 + statusline.sh 雛形 | — |
| 2 | ✅ | statusline.sh 本実装 (jq parse + mode.yml + 2 行 + ANSI 色 + fallback) + clamp 0-100 + git -C cwd 一貫 (review HIGH 修正) | 1 |
| 3 | ✅ | settings.json 配線 (generate-settings.sh L126 statusLine 組込 + 再生成、--check OK portable) | 2 |
| 4 | ✅ | (テスト設計レビュー) code-reviewer: HIGH 2 (clamp/branch) + MED 1 + LOW 2 検出 → 修正反映、approve | 3 |
| 5 | ✅ | (テスト合格) statusline-smoke 17/17 + regression 30/30 PASS。live 複数行目視は user 確認可 (配線済) | 4 |
| 6 | ✅ | (リファクタリング) review 修正 (clamp/git -C/dim hint/comment) が refactor 兼務、追加 skip | 5 |

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/scripts/statusline.sh` (新規), `.claude/scripts/generate-settings.sh` (statusLine 配線), 生成 settings.json |
| migration | なし |
| 互換性 | jq/rate_limits/mode.yml 不在 graceful fallback、既存 settings 非破壊 |

## 再発防止

- rate_limits は Pro/Max 限定 + 初回 API 応答後出現 → 空欄禁止 `—` fallback
- settings.json は generated → 手編集せず generate-settings.sh 経由 ([[feedback_design_external_dependency_verification]])

## ステータスログ
| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-04 | 起案+承認+着手 | 元 📝 保留を user 擦り合わせで仕様確定、draft 承認、実装着手 |

## 関連
- Draft: [statusline-construction](../draft/statusline-construction.md)
- research: claude-code-guide (statusLine JSON / rate_limits / OSC8)
