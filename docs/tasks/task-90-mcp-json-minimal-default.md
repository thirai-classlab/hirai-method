---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #90: .mcp.json 配布 minimal default + opt-in flag (`--mcp-servers=<csv>`、P1-6)

> Status: **🔲 未着手**
> 起案: 2026-07-05 / 承認: 2026-07-05 (AI 推奨どおり全判断点承認)
> 関連: Phase 1 (#85-#91)、master roadmap install-immediately-usable-redesign-20260618 §4.4 対策 A/§5 P1-6
> 設計起源: [mcp-json-minimal-default.md](../draft/mcp-json-minimal-default.md)

## Task ゴール

`bash install.sh <target>` 直後の .mcp.json が env placeholder 0 の minimal 2 server (serena + context7) になり、`--mcp-servers=<csv>` / `all` で選択配布できる (既存 .mcp.json は keep-as-is、jq 不在は全配布 fallback)。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-85 | install.sh 同域 (arg parse / header / summary) 編集の序列化 (file 競合回避目的の soft 依存)。旧 list.md 依存 task-87 は誤方向のため削除 — /doctor 連動 (D5/D7) は本 draft が走査契約を定義し #87 が実装する | [task-85-install-preset-auto-switch.md](task-85-install-preset-auto-switch.md) |

## Task 作業概要

- install.sh arg parse に `--mcp-servers=<csv>` (検証 + `--no-mcp` conflict exit 64、特殊 token `all`)
- §3 配布 logic の csv filter 化 (jq filter、jq 不在は WARN + 全配布 fallback、dry-run / summary 対応)
- 新 smoke `install-mcp-servers-smoke.sh` 10 case + run-all-smokes 登録 + docs 反映

## Task 完了条件 (DoD)

- [ ] fresh install 直後の .mcp.json server keys = `context7` + `serena` の 2 行のみ
- [ ] 同 target: `grep -c '\${' .mcp.json || true` = 0 (env placeholder 0)
- [ ] `--mcp-servers=all` で key set が source と一致 (jq -S diff 空)
- [ ] `--mcp-servers=serena,typo` → exit 64
- [ ] 新 smoke 10/10 PASS + 既存 install 系 smoke regression 0
- [ ] run-all-smokes に portability カテゴリで登録済
- [ ] docs 反映 (`grep -c 'mcp-servers' install.sh README.md` ≥ 各 1)

## Task 概要欄 (list.md 用)

不要 MCP server の env 不在 warning で /doctor が騒がしくなる問題 (R5) を解消するため、install.sh に `--mcp-servers=<csv>` を追加し serena,context7 minimal default で配布する (jq 不在は全配布 fallback、asana 連動 strip は follow-up 化)。完成すれば install 直後の MCP env warning 発生源が 0 になり、必要な server のみ opt-in 配布できる。

## Step 計画 (SSoT: draft §3 「Step 計画」+ Step N 詳細)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | install.sh arg parse 拡張 (`--mcp-servers=<csv>` + 検証 + `--no-mcp` conflict) | 0.5h | — |
| 2 | 🔲 | §3 配布 logic の csv filter 化 (jq filter / all / fallback / dry-run / summary、§6.4 先例の if-wrapper + mktemp X 末尾) | 1.5h | Step 1 |
| 3 | 🔲 | smoke 新設 (10 case) + run-all-smokes 登録 + docs 反映 | 1.0h | Step 2 |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 0.5h | Step 3 |
| 5 | 🔲 | (テスト合格) 新 smoke 10/10 + 既存 install 系 regression 0 | 0.5h | Step 4 |
| 6 | 🔲 | (リファクタリング) 3 観点判定 or `skip: <reason>` | 0.3h | Step 5 |

合計: 約 4.3h (roadmap P1-6 見積 0.5 day と整合)

> **注意**: install.sh header 行数変更時は install.sh:90 の `-h` sed 範囲を同 commit で更新。着手順序列化 #85 → #89 → #90 (2026-07-05 横断レビュー M6)。

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-05 | 起案 | draft 起こし (PR #69、依存方向三重矛盾 [HIGH] + 擬似コード fail-open 3 点 [L6] 修正済) |
| 2026-07-05 | 承認 | user 承認 (AI 推奨どおり: minimal default breaking 承認 / asana strip follow-up 化 / jq 不在は全配布)、list.md 🔲 化 + 依存先 task-87 → task-85 修正 |

## 派生 task / 次アクション候補

- [ ] (🟢) `/mode asana on` 時の asana entry 追加導線 (roadmap §4.4 対策 C の後継) — 本 task 完了時に next-actions.md へ entry 追加判断

## 関連

- Draft: [mcp-json-minimal-default.md](../draft/mcp-json-minimal-default.md)
- 走査契約連携: #87 (D5/D7 実装側)。序列: #85 → #89 → #90
