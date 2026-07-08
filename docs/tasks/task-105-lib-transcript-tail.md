---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 6
-->

# Task #105: lib/transcript-tail.sh (Stop hook transcript 解析)

> Status: **🔲 未着手**
> 起案: 2026-07-08 (Grand Summary SSoT 直行方式、user 承認済)
> 関連: Grand Summary 2026-06-10 §6.3 W1-3
> 設計起源: [Grand Summary](https://mdv.sandboxes.jp/docs/hirai-method-harness-grand-summary-20260610) §6.3

## Task ゴール

`.claude/hooks/lib/transcript-tail.sh` 新設 (Stop hook が transcript の最終 assistant text を効率的に取得する API)。tool-call-slip-detector.sh / loop-confirmation-detector.sh 等の Stop hook が各自 grep/tail で transcript_path 読取していた重複ロジックを lib 経由に統一。完成すれば Stop hook 追加時に transcript 読取 pattern が再利用可能になる。conf 0.78 🟡 (Grand Summary §6.3 判断)。

## Task 依存先タスク

依存なし (— 依存なし)

## Task 作業概要

- `.claude/hooks/lib/transcript-tail.sh` 新設 (`tail_last_assistant_text` / `tail_last_user_prompt` / `tail_recent_events N` の 3 API、subshell 関数化、jq fallback、fail-open)
- 既存 Stop hook (tool-call-slip-detector.sh / loop-confirmation-detector.sh / byproduct-discharge-guard.sh 該当箇所) を lib source + API 呼出に置換
- 新規 smoke `.claude/tests/lib-transcript-tail-smoke.sh` 4 case (A-D)

## Task 完了条件 (DoD)

- [ ] `.claude/hooks/lib/transcript-tail.sh` 存在 + 3 API 定義: `source ...; declare -f tail_last_assistant_text tail_last_user_prompt tail_recent_events | wc -l >= 3`
- [ ] 主要 Stop hook 2-3 個が lib 経由に置換: `grep -l 'lib/transcript-tail.sh' .claude/hooks/*.sh | wc -l >= 2`
- [ ] `lib-transcript-tail-smoke.sh` 4/4 PASS
- [ ] Wave 1-5 全 smoke regression 0
- [ ] docs 反映: `docs/INVENTORY.md`
- [ ] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

Stop hook が transcript 読取ロジックを各自実装していて重複している問題を解消するため lib/transcript-tail.sh を新設し 3 API (最終 assistant text / 最終 user prompt / recent events) で統一する。完成すれば Stop hook 追加時に transcript 読取 pattern が再利用可能になり silent failure 追跡や slip detection の実装コストが下がる。

## Step 計画 (Grand Summary §6.3)

| Step | Status | 作業概要 | 工数 |
|:---:|:---:|:---|---:|
| 1 | 🔲 | `lib/transcript-tail.sh` 新設 (3 API、jq fallback、subshell 関数化) | 3h |
| 2 | 🔲 | 主要 Stop hook 2-3 個を lib source 経由に置換 | 2h |
| 3 | 🔲 | 新 smoke `lib-transcript-tail-smoke.sh` 4 case + run-all-smokes 登録 | 2h |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1.5h |
| 5 | 🔲 | (テスト合格) 全 smoke PASS + Stop hook regression 0 | 1h |
| 6 | 🔲 | (リファクタリング) 3 観点判定 or skip | 0.5h |

合計: 10h ≒ 1.3 day (Grand Summary S 見積)

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-07-08 | 起案 + タスク化 | Grand Summary §6.3 W1-3、conf 0.78 🟡、docs/tasks/task-105-*.md 生成 |

## 関連

- Grand Summary §6.3 W1-3
