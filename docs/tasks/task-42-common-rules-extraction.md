<!--
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
approved_by: user
-->

# Task #42: CLAUDE.md 共通規範を `.claude/CommonRules.md` に切り出し + `@import` 構文採用

> Status: **✅ 完了** (Step 1-9 ✅、closure commit `fb227a1`、smoke 7/7 PASS + DoD grep 3 件 PASS、iter3 strict 0-finding 収束)
> 起案: 2026-05-26
> 完了: 2026-05-26
> 関連: task-40 / task-41 (CLAUDE.md 補強反映漏れの典型例)
> 設計起源: [`docs/draft/common-rules-extraction.md`](../draft/common-rules-extraction.md)

## Task ゴール

採用 4 リポで CLAUDE.md 補強反映漏れが発生する構造問題を解消するため、共通規範を `.claude/CommonRules.md` に切り出し、CLAUDE.md template には `@import` 1 行で参照させる。完成すれば本リポでの規範追加が `bash install.sh --update <target>` で 4 リポに自動同期される (CLAUDE.md は project 固有編集を保護維持)。

## Task 依存先タスク

— (依存なし)

## Task 作業概要

draft §3 採用案 C ハイブリッド:

- (a) `.claude/CommonRules.md` 新設 (7 section 集約)
- (b) CLAUDE.md slim 化 (project 固有のみ + `@.claude/CommonRules.md` 1 行)
- (c) smoke 新設 (4+ case)

## Task 完了条件 (DoD)

draft §6 参照 (9 項目)。

## Task 概要欄 (list.md 用)

採用 4 リポでの CLAUDE.md 補強反映漏れ構造問題を解消するため、共通規範を `.claude/CommonRules.md` に切り出し CLAUDE.md template に `@import` 1 行を追加する。完成すれば本リポでの規範追加が `install.sh --update` で 4 リポに自動同期される。

## Step 計画

draft §5 参照。

## 派生 task / 次アクション候補

なし。
