---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 4
-->

# Task #81: agent-router-suggest.sh を dispatcher 配線 (復活)

> Status: **🔄 進行中** (2026-06-06 draft 承認 = 案 A、実装着手)
> 起案: 2026-06-06
> 設計起源: [wire-agent-router-suggest](../draft/wire-agent-router-suggest.md) ✅承認済 (approved_at 2026-06-06)

## Task ゴール

dead hook `agent-router-suggest.sh` (task-71 移行取りこぼし) を `dispatcher-manifest.tsv` の UserPromptSubmit に配線し、feature toggle (`feature_agent_router_suggest_enabled`、default ON) + config-loader export + hook 冒頭 gate を備えた harness 規範準拠で復活させる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-71 | dispatcher 化で本 hook を manifest 未移植 → 本 task が配線復旧 | [task-71-settings-dispatcher-generation.md](task-71-settings-dispatcher-generation.md) |

## Task 作業概要

- dispatcher-manifest.tsv に 1 行追加 (`UserPromptSubmit / order 3 / agent-router-suggest.sh / agent_router_suggest / advisory / 5`)
- harness-config.yml に `feature_agent_router_suggest_enabled: true` + config-loader.sh FEATURE export 追記
- hook 冒頭に `is_feature_enabled agent_router_suggest` gate + 誤記述コメント訂正 + docs/AGENT-ROUTER.md 配線記述更新
- smoke: toggle ON/OFF の child spawn 差 + マッチ/非マッチ出力 + drift 0

## Task 完了条件 (DoD)

draft §6 を SSoT。要点: manifest 配線 / feature toggle + export + gate / toggle ON マッチで 1 行注入・OFF で no-op・非マッチで空 (smoke 実測) / 誤記述 + docs 訂正 / dispatcher-core・settings drift・既存 smoke regression 0 / bash 3.2 互換。

## Task 概要欄 (list.md 用、3 要素規範)

task-71 移行で取りこぼされた agent-router hint hook を復活させるため dispatcher-manifest に配線し feature toggle 付きで有効化する。完成すれば named agent 推薦 hint がマッチ時に注入され、各 repo は toggle で ON/OFF でき、dead code と誤記述コメントが解消する。

## 設計

draft [wire-agent-router-suggest](../draft/wire-agent-router-suggest.md) §3 を SSoT (案 A、条件付き出力 + feature toggle default ON)。

## Step 計画

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | manifest 配線 + feature toggle (default true) + config-loader export + hook gate + 誤記述/docs 訂正 | — |
| 2 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1 |
| 3 | 🔲 | (テスト合格) toggle ON/OFF + マッチ/非マッチ smoke + drift 0 + regression 0 | 2 |
| 4 | 🔲 | (リファクタリング) 3 観点 or skip | 3 |

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/dispatcher-manifest.tsv`, `.claude/harness-config.yml`, `.claude/hooks/lib/config-loader.sh`, `.claude/hooks/agent-router-suggest.sh`, `docs/AGENT-ROUTER.md`, smoke |
| migration | なし |
| 互換性 | feature toggle 追加 (既定 ON)、条件付き出力で無条件注入 0 維持、既存 dispatcher 非破壊 |

## 再発防止
- 新 hook 3 点セット (yml key + hook gate + env override) 準拠で配線
- 出力は条件付き維持 (context 削減方針との両立)

## ステータスログ
| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-06 | 起案+承認+着手 | hooks 監査で dead hook 発見 → user「A 配線復活」承認、実装着手 |

## 関連
- Draft: [wire-agent-router-suggest](../draft/wire-agent-router-suggest.md)
- 依存: #71
