# Task #21: System-Reminder Attention Dilution + Loop モードと draft フロー相反 修正

> Status: **🔄 進行中 (~80%)** (W0 + W1.4-1.6 + W1.7 + W2.1-W2.5 + W3 Phase A+B+C 完了、W3 capability/regression 実行 + 採用判定残)
> 起案: 2026-05-23
> 関連: 設計起源 — 2026-05-23 user 観察 (3 リポ比較で classlab-weekly-news の方が体感正確)、user 指摘 (hook タイミング再考)
> 設計起源: [system-reminder-attention-fix.md](../draft/system-reminder-attention-fix.md)

## 進捗ログ (2026-05-23)

### W1.4-1.6 完遂 (commit `14586e5`、subagent adec02cc57179e123 confidence 0.9)

- W1.4 `.claude/hooks/context-budget.sh`: 60% 未満で完全 silent kill switch を early-exit + コメント明示化、`HC_CONTEXT_BUDGET_SILENT_BELOW_THRESHOLD=false` で debug 出力 revert 可
- W1.5 `.claude/hooks/next-actions-surface.sh`: 🔴 entry 0 件で完全 silent (🟡/🟢 のみは default 抑止)、`HC_NEXT_ACTIONS_SURFACE_RED_ONLY=false` で旧挙動 revert 可
- W1.6 `.claude/hooks/session-help-surface.sh`: 初回 session のみ表示、`.claude/.session-help-shown` marker で再表示抑止、`HC_SESSION_HELP_FORCE=1` / `HC_SESSION_HELP_FIRST_ONLY=false` で override 可
- 新 `.claude/tests/hook-frequency-tweaks-smoke.sh` 8 cases PASS + 既存 smoke 3 件 regression 0 (context-budget 11/11 + session-help-surface 7/7 + next-actions-hooks 10/10、合計 36/36)

### W3 Phase A+B audit 完遂 (subagent a4c9b91ed72f90dcb confidence 0.75)

**Phase A 注入数 audit (構造的計測、git show で W0 前 settings.json 取得 → 現 settings.json 比較)**:
- **before (W0 commit `8397d65` 前)**: UserPromptSubmit hook **4 個** (unconditional 2: why-x5-reminder + mode-enforce、conditional 2: context-budget + loop-auto-progress-reminder)
- **after (現在 post W0.1-W0.3)**: UserPromptSubmit hook **1 個** (conditional 1: context-budget threshold-only、unconditional 0)
- **採用判定基準 3 (注入数 4 → 0 削減)**: **達成** (unconditional 注入 2 → 0、常時 inline 注入は完全消滅)

**Phase B handoff latency 計測**:
- `observe.sh` の event 列に `SubagentStop` 0 件 / 6594 records (matcher 未配線)、true handoff latency 直接計測不可
- 代理計測 `PostToolUse(Agent)` → 次 main `PreToolUse`: **median 36.00 秒** (n=19 events、2026-05-23 post-W0)、p25=22s / p75=61s / min=7s / max=81s
- **採用判定基準 4 (秒オーダー)**: 上界 36 秒で **間接達成**、真値は別途 `SubagentStop` matcher で observe.sh を拡張後に再測必要

### W3 Phase C eval files 完遂 (commit `af5fa6e`)

- `.claude/evals/system-reminder-attention.md` (capability eval、124 lines、draft §3 W3.1 SSoT 準拠、10 prompts + code-based grader + pass@k targets)
- `.claude/evals/loop-mode-autonomy.md` (regression eval、122 lines、draft §3 W3.2 SSoT 準拠、4 regression tests + baseline 観察 + handoff latency 副次指標)

### 残作業

- W3 capability eval 実行: 10 prompts × 3 trials = 30 runs で `pass@3 ≥ 0.95` 確認
- W3 regression eval 実行: 4 tests × 3 trials = 12 runs で `pass^3 = 1.00` 維持確認
- W3 採用判定: 4 基準 (capability pass@3 / regression pass^3 / 注入数 / latency) 全達成判定
- observe.sh `SubagentStop` matcher 拡張 (Phase B 真値計測のため、別 task 化検討)
- 採用後の 3 リポ反映 (本 session 既に user manual で 1 度実施済、再反映要否は採用判定後決定)

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
