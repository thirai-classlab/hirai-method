# Task #21: System-Reminder Attention Dilution + Loop モードと draft フロー相反 修正

> Status: **draft (要承認)** | **🔲 未着手**
> 起案: 2026-05-23
> 関連: 設計起源 — 2026-05-23 user 観察 (3 リポ比較で classlab-weekly-news の方が体感正確)、user 指摘 (hook タイミング再考)
> 設計起源: [system-reminder-attention-fix.md](../draft/system-reminder-attention-fix.md)

## 背景・目的

hirai-method / recall_poc / taskManageSystem では UserPromptSubmit に毎ターン 4 つの `<system-reminder>` が注入され、合計 ~5 KB の規範注入が attention dilution を起こす。結果として `task-management.md` (paths 条件付き受動 load) が認識落ちし、設計→承認→タスク追加フローが skip される (recall_poc/docs/01-03 が docs/ 直下に直接 Write された事案)。

加えて Loop モード遵守事項 2 (中間確認禁止) と task-management.md (承認必須) が instruction conflict を起こしている。

本 task で Wave 0 (hook タイミング根本再配置) + Wave 1 (頻度間引き) + Wave 2 (modes.md 例外条項 + draft-flow-guard.sh 配備済) + Wave 3 (eval 検証) を実装する。

## 仕様 (要決定 → 決定済)

### Q1: タイミング再配置 vs 頻度間引きの優先順

→ **Wave 0 (タイミング再配置) を最優先**。Wave 1 (mod N 間引き) は Wave 0 で吸収可能な部分を SUPERSEDED マーク。

### Q2: draft-flow-guard.sh の対象 path

→ **docs/ 直下 (深さ 1) のみ**。docs/draft/ docs/tasks/ 配下と深さ 2 以上、既存 file 編集、非 .md は対象外。本 session で commit `6ed9337` 配備済。

### Q3: eval 採用判定基準

→ pass@3 ≥ 0.95 (capability) + pass^3 = 1.00 (regression) + `<system-reminder>` 注入数 4 → 0 + handoff latency 秒オーダー。

## 設計

詳細は [system-reminder-attention-fix.md](../draft/system-reminder-attention-fix.md) §3 参照。

### Wave 構成

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| W0.1 | loop-auto-progress-reminder.sh: UserPromptSubmit → SubagentStop + Stop | 0.5 |
| W0.2 | mode-enforce.sh: 毎ターン → SessionStart 1 度 + 違反検出時のみ | 0.5 |
| W0.3 | why-x5-reminder.sh: 毎ターン → SessionStart + 違反検出 hook 新設 | 0.7 |
| W1.4-1.8 | context-budget / next-actions-surface / session-help-surface / task-management 常時参照化 / improvement-proposal cache | 1.0 |
| W2.1 | modes.md 遵守事項 2 に「設計承認は禁止対象外」例外条項追記 | 0.3 |
| W2.2 | task-management.md に「Loop モードでも draft フロー免除されない」明記 | 0.2 |
| W2.4 | _DRAFT_TEMPLATE.md に approval_required frontmatter 導入 | 0.3 |
| W2.5 | CLAUDE.md template Autonomous Progression rewrite | 0.4 |
| W3.1 | before 計測 (capability eval `task-management-recognition`) | 0.5 |
| W3.2 | after 計測 + regression eval | 0.5 |
| W3.3 | 採用判定 + recall_poc / taskManageSystem / classlab-weekly-news に install.sh --update 反映 | 0.3 |

合計 6.2 session。

## TDD 戦略

### RED (先に追加するテスト)

- `.claude/tests/loop-auto-progress-smoke.sh` 拡張 — W0.1 後の SubagentStop 発火検証 (5 ケース追加)
- `.claude/tests/mode-enforce-smoke.sh` 新設 — W0.2 後の「1 度のみ + 違反時再注入」検証
- `.claude/tests/why-x5-violation-detect-smoke.sh` 新設 — W0.3 の新 hook 検証
- `.claude/evals/system-reminder-attention.md` — capability eval 定義

### GREEN (最小実装)

- 各 W0.x hook の settings.json 配線変更 (event 移動)
- W2.4 frontmatter 追加 + draft-flow-guard.sh で frontmatter 読み拡張
- W2.5 CLAUDE.md template の Autonomous Progression を rewrite

### REFACTOR

- W0.2 / W0.3 で違反検出 hook の共通化検討 (新 lib/violation-detect.sh)

## 派生 task / 次アクション候補

- task #21 完了後、recall_poc 復旧 (task #23) と taskManageSystem 復旧 (task #24) の W2 (CLAUDE.md 改訂) と統合実装すれば工数削減可能
- Wave 0 で SubagentStop hook に移動した際、既存 confidence-gate.sh との同時発火順序を要検証

## 完了条件

- [ ] Wave 0/1/2/3 全実装
- [ ] eval before/after 比較で 4 採用判定基準すべて満たす
- [ ] recall_poc / taskManageSystem / classlab-weekly-news で同期反映
- [ ] CLAUDE.md Critical Operational Lessons に「system-reminder attention dilution 解消」を 1 件追加
