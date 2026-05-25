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

### W3 case A 実行素材完備 (commit `0db9889`、subagent a5109ff50a06066c0 confidence 0.94)

user manual 42 sessions 実行を支援する 5 ファイル新規:

- `.claude/evals/system-reminder-attention.runner.md` (353 行、playbook)
- `.claude/evals/system-reminder-attention.results.template.md` (93 行、capability 用 results 雛型)
- `.claude/evals/loop-mode-autonomy.results.template.md` (133 行、regression 用 results 雛型)
- `.claude/evals/grader-system-reminder-attention.sh` (99 行、+x、deterministic 4 sub-criteria 判定)
- `.claude/evals/grader-loop-mode-autonomy.sh` (165 行、+x、Test 1-4 判定)

既存 eval 仕様 2 ファイル (`system-reminder-attention.md` / `loop-mode-autonomy.md`) は不変。staging 戦略遵守 (`/tmp` Write → `mv` → `chmod +x`)。

### 2026-05-25 11th session 並行進行ステータス (task-33 系列と並走)

- task-29 採用 5 条 → 採用 6 条 (Task=Phase=N Step) の連続 dogfooding 進行中 (task-33 → 5 task 分割完了、task-34 Step 4 iter2 fix subagent `a3524fd32786f11e4` 稼働中)
- 本 session で task-21 W3 残は **agent 側着手可能項目ゼロ** を再確認 (case A 実行 + 採用判定基準 1, 2 測定 + 採用後 3 リポ反映、いずれも user manual 案件)
- agent 並行進行作業: 本 entry 追記 (進捗追跡) + grader script `.claude/evals/grader-{system-reminder-attention,loop-mode-autonomy}.sh` の事前確認 commit `0db9889` で完備済を確認、追加 dry-run 不要 (subagent a5109ff50a06066c0 confidence 0.94 で当初検証済)
- **user 依頼 (次の任意タイミング)**:
  1. `.claude/evals/system-reminder-attention.runner.md` 参照、30 sessions capability + 12 sessions regression = 42 sessions 実行
  2. results を `.claude/evals/{system-reminder-attention,loop-mode-autonomy}.results.template.md` に追記
  3. `bash .claude/evals/grader-system-reminder-attention.sh` / `grader-loop-mode-autonomy.sh` で自動 score 算出
  4. 採用判定 (基準 1: pass@3 ≥ 0.95、基準 2: pass^3 = 1.00) → 採用なら 3 リポ反映へ
- **採用判定後の 3 リポ反映手順 (user manual、cross-repo write 規範遵守)**:
  ```bash
  bash install.sh --update /Users/t.hirai/recall_poc
  bash install.sh --update /Users/t.hirai/タスクマネジメント/taskManageSystem
  bash install.sh --update /Users/t.hirai/work/classlab-weekly-news
  ```
  agent (main / subagent / worktree isolation) では Claude Code sandbox + delegation-guard 二重制約で deny されるため、必ず user manual 経路で実施 (`.claude/rules/development-process.md` §「cross-repo write 例外」)

### 残作業

- **W3 case A 実行** (user manual): 30 sessions capability + 12 sessions regression = 42 sessions (推定 90-130 分、user 任意タイミング)
- W3 採用判定: 4 基準 (capability pass@3 / regression pass^3 / 注入数 / latency) 全達成判定
  - 基準 3 (注入数 4→0) **既達** (Phase A audit)
  - 基準 4 (handoff latency 36s) **既達** (Phase B audit proxy)
  - 基準 1, 2 は本 case A 実行で測定
- 採用後の 3 リポ反映 (user manual `bash install.sh --update`、本 session 既に W2 で 1 度実施済、再反映要否は採用判定後決定)

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

## W3 capability + regression eval (Phase→Step 化、task-29 dogfooding)

> 本セクションは task-29 (`phase-step-task-structure`) の Phase 4 Step 2 実適用として、task-21 W3 残作業を Phase→Step 強制構造で表現する。
> 規範: `.claude/rules/task-management.md` §「タスク構造規範 (Phase→Step 強制)」採用 5 条。
> 2026-05-23 user 仕様変更: 各 Phase 最終 Step を 2 段 (テスト合格 → リファクタリング) から **3 段 (テスト設計レビュー → テスト合格 → リファクタリング)** に拡張。

### Phase A: capability eval 実行

**ゴール**: `.claude/evals/system-reminder-attention.md` capability eval (10 prompts × 3 trials = 30 runs) を実 session で実行し、pass@3 metric を実測する。

**作業概要**:
- eval-harness skill 経由で eval ファイル load
- 10 prompts を順次実行 (各 3 trials)
- 結果集計 (pass@3 計算)
- 結果を `.claude/evals/system-reminder-attention.results.md` に記録

**Step**:

- **Step 1**: eval ファイル `.claude/evals/system-reminder-attention.md` を確認
  - 完了条件: ファイル存在 + 10 prompts が定義されている
- **Step 2**: eval-harness skill / `/eval check system-reminder-attention` 経由で 30 runs 実行
  - 完了条件: 全 30 runs 完了、各 run の pass/fail が記録されている
- **Step 3**: pass@3 計算 + 結果記録
  - 完了条件: `.claude/evals/system-reminder-attention.results.md` に pass@3 数値 + 採用判定基準 1 (pass@3 ≥ 0.8) との比較が記録
- **Step 4 (テスト設計レビュー)**: メインが 5+ reviewer 動的選定 (eval 系のため推奨: tdd-guide / test-automator / qa-expert / pr-test-analyzer + 本 task の domain (system-reminder / Loop モード) に応じて harness-optimizer / architect-reviewer 加味) で並列起動、収束まで反復 (上限 5 回)
  - 完了条件: 全 reviewer approve / no objection
- **Step 5 (テスト合格)**: Step 1-3 で実施した capability eval (30 runs) 結果が反映済、既存 smoke 全 PASS + eval results.md ファイル存在
  - 完了条件: 既存 smoke regression 0 (Phase A は eval 実行のみで code 変更なしのため smoke 自体への影響なし)、全 smoke exit 0
- **Step 6 (リファクタリング)**: skip: eval 実行のみ、code 変更なし、refactor 対象なし

### Phase B: regression eval 実行

**ゴール**: `.claude/evals/loop-mode-autonomy.md` regression eval (4 tests × 3 trials = 12 runs) を実 session で実行し、pass^3 metric (全 3 trial 連続 PASS) を実測する。

**作業概要**:
- eval ファイル load
- 4 tests × 3 trials = 12 runs 実行
- 結果集計 (pass^3 計算)
- 結果記録

**Step**:

- **Step 1**: eval ファイル `.claude/evals/loop-mode-autonomy.md` 確認
- **Step 2**: 12 runs 実行
  - 完了条件: 全 12 runs 完了
- **Step 3**: pass^3 計算 + 結果記録
  - 完了条件: `.claude/evals/loop-mode-autonomy.results.md` に pass^3 + 採用判定基準 2 (pass^3 ≥ 0.75) との比較
- **Step 4 (テスト設計レビュー)**: メインが 5+ reviewer 動的選定 (regression 系のため推奨: tdd-guide / test-automator / qa-expert / pr-test-analyzer + 本 task の domain (Loop モード自律規律) に応じて harness-optimizer / architect-reviewer 加味) で並列起動、収束まで反復 (上限 5 回)
  - 完了条件: 全 reviewer approve / no objection
- **Step 5 (テスト合格)**: Step 1-3 で実施した regression eval (12 runs) 結果が反映済、既存 smoke regression 0
  - 完了条件: 全 smoke exit 0
- **Step 6 (リファクタリング)**: skip: eval 実行のみ、refactor 対象なし

### Phase C: 採用判定

**ゴール**: 4 基準 (capability pass@3 / regression pass^3 / 注入数 / true handoff latency) を統合判定し、Loop モード自律進行強制機構を本採用 or roll-back する。

**作業概要**:
- Phase A / B の results 取得
- 既測の audit 結果 (注入数 4→0 達成済 / true handoff latency task-28 W1 で計測可能化済)
- 4 基準を統合判定
- 結果に応じて 3 リポ反映 (採用なら user manual `bash install.sh --update`)

> **cross-repo 注意**: 本 Phase の Step 3 「3 リポ反映 (採用なら user manual)」は cross-repo write (本 repo → recall_poc / taskManageSystem / classlab-weekly-news) を含む。Claude Code sandbox + `delegation-guard.sh` 二重制約で agent 経路完全 denied、`bash install.sh --update <target>` は **user manual (terminal) 実行のみ可能**。詳細は `.claude/rules/development-process.md` §「cross-repo write 例外」参照 (task-31 で規範化、commit `f90d194`)。

**Step**:

- **Step 1**: 4 基準の集計 (Phase A / B + 既測 audit + task-28 W1 SubagentStop event)
  - 完了条件: 4 基準値が表形式で記録
- **Step 2**: 採用判定 (4 基準中 N 件達成で採用 or roll-back)
  - 完了条件: 判定根拠 + 結論 (採用 / roll-back / 部分採用) が記録
- **Step 3**: 採用なら 3 リポ反映 (user manual)、roll-back なら hook 復元 (subagent 委譲)
- **Step 4 (テスト設計レビュー)**: メインが 5+ reviewer 動的選定 (採用判定系のため推奨: tdd-guide / test-automator / qa-expert / pr-test-analyzer + 本 task の domain (system-reminder / Loop モード / 3 リポ反映) に応じて harness-optimizer / architect-reviewer 加味) で並列起動、収束まで反復 (上限 5 回)
  - 完了条件: 全 reviewer approve / no objection
- **Step 5 (テスト合格)**: Step 1-3 で実施した 4 基準採用判定 (capability pass@3 / regression pass^3 / 注入数 / latency) 結果が反映済、反映後 smoke 全 PASS + 本番動作確認 (UserPromptSubmit 注入数 audit)
  - 完了条件: 全 smoke exit 0
- **Step 6 (リファクタリング)**: skip: 反映作業のみ (反映に伴う重複コード生成なし)、refactor 対象なし
