<!--
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
approved_by: user
-->

# Task #43: 外部 library / framework 仕様確認に context7 を default 利用する規範

> Status: **🔄 closure 中** (Step 1-6 ✅ [Step 4/6 skip 明示] / Step 7 進行中 / Step 8 user manual 案内待ち)
> 起案: 2026-05-26
> 関連: task-42 (CLAUDE.md slim 化、PR #13 merge 済) + context7 MCP `.mcp.json` 追加 (PR #14 merge 済)
> 設計起源: [`docs/draft/research-reuse-context7-mandate.md`](../draft/research-reuse-context7-mandate.md)

## Step 進捗実測

| Step | Status | 結果 |
|:---:|:---:|:---|
| 1 | ✅ | draft + task file + list.md row 完成 (本 file + `docs/draft/research-reuse-context7-mandate.md` + list.md L96) |
| 2 | ✅ | development-process.md 新 §「研究と再利用」追加 (L35-65 相当、grep `context7` 7 hits) |
| 3 | ✅ | CommonRules.md Development Policy に context7 bullet 1 行追加 (grep `context7` 1 hit) |
| 4 | ✅ (skip 明示) | テスト設計レビュー skip 理由: 規範文書追記のみで reviewer 5+ 並列起動 overkill、内容は既存 user global rule (`~/.claude/rules/common/development-workflow.md` §0 Research & Reuse) と整合 |
| 5 | ✅ | grep 検証 3 件全 PASS: dev-process.md 7 hits / CommonRules.md 1 hit / draft `approved_at: 2026-05-26` 非空 + draft-flow-guard 通過実証 (本 Edit が block されず成功) |
| 6 | ✅ (skip 明示) | リファクタリング skip 理由: 規範文書追記のみで refactor 余地なし、既存 §「サブエージェント委譲」内の Web 調査 bullet と整合性維持 |
| 7 | 🔄 | commit + push + PR create (本 closure で実行) |
| 8 | 🔲 | 4 リポ user manual install 案内 (`bash install.sh --update <target>`、PR merge 後) |

## Task ゴール

採用 4 リポで AI が外部 library / framework 仕様確認に context7 MCP を default 利用するよう規範化する。完成すれば project 規範 SSoT として `.claude/rules/development-process.md` + `.claude/CommonRules.md` 経由で全採用先で一貫した行動を保証できる。

## Task 依存先タスク

- task-42 (CLAUDE.md slim 化、PR #13 merge 済) — CommonRules.md SSoT が前提
- task #context7-mcp-add (PR #14 merge 済) — `.mcp.json` の context7 entry が前提

## Task 作業概要

draft §3 採用案 C ハイブリッド:

- (a) development-process.md に新 § 「研究と再利用 (research-reuse)」追加 (詳細 fallback chain + 適用対象 + bypass)
- (b) CommonRules.md Development Policy に context7 1 行追加 (cross-ref)

## Task 完了条件 (DoD)

draft §6 参照 (7 項目)。

## Task 概要欄 (list.md 用)

採用 4 リポで AI が library doc lookup を context7 default で行うよう規範化する。development-process.md + CommonRules.md 両方に追記し、ハーネス採用先で AI 環境非依存で一貫した行動を保証する。

## Step 計画

draft §5 参照。

## 派生 task / 次アクション候補

なし。
