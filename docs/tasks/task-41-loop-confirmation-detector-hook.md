<!--
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
retroactive: true
approved_by: user
-->

# Task #41: Loop モード確認質問検出 hook (loop-confirmation-detector) 新設

> Status: **✅ 完了** (Step 1-10 全 ✅、iter1-3 reviewer 9 並列、収束 CRITICAL+HIGH+MEDIUM=0)
> 起案: 2026-05-26
> 関連: #40 (draft-flow-guard.sh 拡張、retroactive 方式の起源) / `mode-enforce.sh` (UserPromptSubmit、本 hook と相補)
> 設計起源: [`docs/draft/loop-confirmation-detector-hook.md`](../draft/loop-confirmation-detector-hook.md)

## Task ゴール

Loop モード稼働中の main agent が確認質問 (「進めてもよいですか?」「OK ですか?」「お待ちします」等) を発した場合、Stop hook が AI 最終 message を regex 検出 → `<system-reminder>` 強制注入で次 turn の自律是正を促す。

## Task 依存先タスク

— (依存なし、#40 の retroactive 方式は参照のみ)

## Task 作業概要

draft §3 採用案 C ハイブリッド (Stop hook + 規範補強 + smoke + dogfooding):

- (a) Stop hook 新設 (`.claude/hooks/loop-confirmation-detector.sh`)
- (b) settings.json Stop hook 配線
- (c) harness-config.yml + config-loader.sh SSoT 追加
- (d) smoke 新設 (8+ case)
- (e) modes.md 遵守事項 2 補強
- (f) CLAUDE.md Critical Lessons 新 entry

## Task 完了条件 (DoD)

- [ ] `.claude/hooks/loop-confirmation-detector.sh` 存在 + `bash -n` syntax OK
- [ ] `.claude/settings.json` Stop hook entry 存在
- [ ] `.claude/harness-config.yml` に `loop_confirmation_detection_enabled` + `loop_confirmation_patterns` 追加
- [ ] smoke 全 PASS (8+ case)
- [ ] grep `loop-confirmation-detector` `.claude/rules/modes.md` 1+ hit
- [ ] grep `loop-confirmation-detector` `CLAUDE.md` 1+ hit
- [ ] reviewer 3+ 並列 CRITICAL+HIGH+MEDIUM=0 収束 (上限 5 回)
- [ ] PR create + user merge 案内
- [ ] 3 リポ install command 提示

## Task 概要欄 (list.md 用)

Loop モード違反 (確認質問) を機械強制防止するため、Stop hook で AI 最終 message を regex 検出 → `<system-reminder>` 強制注入する仕組みを新設し 3 リポに展開する。完成すれば AI が Loop モードで「進めてよいですか」等を発しても次 turn で自律是正に切替えられる。

## Step 計画

draft §5 参照。Step 1-10、Step 6 はテスト設計レビュー (reviewer 3+ 並列、収束 CRITICAL+HIGH+MEDIUM=0)、Step 8 リファクタリング、Step 9 commit + push + PR、Step 10 install 案内。

## 派生 task / 次アクション候補

なし (本 session 違反は本 task で直接管理)。
