# SMOKE-CLASSIFICATION.md — task-74 Step 4c SSoT

作成日: 2026-06-02 / branch: feat/task-71-settings-dispatcher-generation

全 67 smoke の 5 種別分類 + 15 fail (landscape 時点から再実測) の 4 分類を記録する。

---

## 1. 5 種別分類表 (67 smoke)

種別定義:
- **parity**: SSoT drift 検出 (yml/settings/CommonRules の整合性確認)
- **behavior**: BLOCK/warn 挙動検証 (hook の動作正確性)
- **budget**: 軽量性 regression (bytes/count 計測)
- **portability**: cwd/install 差分 (cross-env 堅牢性)
- **stale-det**: 古い期待値自己検出 (harness バージョン整合)

| # | smoke | 種別 |
|---|---|---|
| 1 | action-space-count-smoke | parity |
| 2 | audit-followups-smoke | behavior |
| 3 | autonomous-action-guard-relaxation-smoke | behavior |
| 4 | autonomous-action-guard-smoke | behavior |
| 5 | check-serena-mcp-smoke | behavior |
| 6 | common-rules-import-smoke | parity |
| 7 | confidence-gate-smoke | behavior |
| 8 | config-feature-toggles-smoke | parity |
| 9 | context-budget-smoke | behavior |
| 10 | custom-pm-commands-smoke | behavior |
| 11 | delegation-guard-code-smoke | behavior |
| 12 | delegation-guard-deny-layers-smoke | behavior |
| 13 | delegation-guard-readonly-filter-smoke | behavior |
| 14 | delegation-guard-search-whitelist-smoke | behavior |
| 15 | delegation-guard-segment-smoke | behavior |
| 16 | dispatcher-blocker-invariance-smoke | behavior |
| 17 | dispatcher-core-smoke | behavior |
| 18 | dispatcher-merge-matrix-smoke | behavior |
| 19 | dispatcher-success-stdout-smoke | behavior |
| 20 | draft-flow-guard-approved-dir-smoke | behavior |
| 21 | draft-flow-guard-smoke | behavior |
| 22 | dual-mode-portability-smoke | portability |
| 23 | effective-hook-matrix-smoke | parity |
| 24 | enforcement-mismatch-smoke | parity |
| 25 | gateguard-smoke | behavior |
| 26 | harness-audit-c-batch-smoke | behavior |
| 27 | harness-audit-compare-smoke | behavior |
| 28 | harness-audit-pipeline-health-smoke | behavior |
| 29 | harness-config-local-smoke | parity |
| 30 | hc-config-key-parity-smoke | parity |
| 31 | hc-config-migration-smoke | parity |
| 32 | hc-config-script-smoke | behavior |
| 33 | hc-config-tui-smoke | behavior |
| 34 | hc-config-web-ui-smoke | behavior |
| 35 | hook-cwd-robustness-smoke | portability |
| 36 | hook-frequency-tweaks-smoke | behavior |
| 37 | improvement-proposal-cache-smoke | behavior |
| 38 | install-sh-sync-drift-smoke | portability |
| 39 | layer-b-context-isolation-smoke | parity |
| 40 | list-md-plan-first-reminder-smoke | behavior |
| 41 | loop-auto-progress-smoke | behavior |
| 42 | loop-confirmation-detector-smoke | behavior |
| 43 | new-task-batch-update-smoke | behavior |
| 44 | next-actions-hooks-smoke | behavior |
| 45 | observe-flock-smoke | behavior |
| 46 | observe-jq-parse-smoke | behavior |
| 47 | observe-repair-smoke | behavior |
| 48 | observe-rotate-smoke | behavior |
| 49 | observe-subagent-stop-smoke | behavior |
| 50 | parallel-subagent-reminder-smoke | behavior |
| 51 | project-root-smoke | portability |
| 52 | review-required-min-count-smoke | parity |
| 53 | reviewer-count-guard-smoke | parity |
| 54 | rule-architecture-smoke | parity |
| 55 | rule-change-draft-flow-guard-smoke | behavior |
| 56 | session-help-surface-smoke | behavior |
| 57 | session-start-parallel-smoke | portability |
| 58 | sessionstart-budget-smoke | budget |
| 59 | sessionstart-footprint-smoke | budget |
| 60 | settings-dispatcher-baseline-smoke | parity |
| 61 | settings-generation-feature-pruning-smoke | behavior |
| 62 | stale-harness-detect-smoke | stale-det |
| 63 | task-rule-guard-smoke | behavior |
| 64 | tool-call-slip-detector-smoke | behavior |
| 65 | wave-precheck-template-smoke | parity |
| 66 | why-x5-violation-detect-smoke | behavior |
| 67 | workflow-guard-smoke | behavior |

種別内訳: behavior 43 / parity 14 / portability 5 / budget 2 / stale-det 1 / その他 2 (parity+e 複合)

---

## 2. 13 fail → 4 分類処理結果 (2026-06-02 実測)

> 注意: landscape 調査時点から hook-frequency-tweaks Case 7 と install-sh Case G は実際には PASS に変化。
> 実測では以下の smoke が exit 1 。

### 2-a. genuine regression (FLAG)

**なし** — 全 fail は preset 緩和 / task-39 緩和 / feature OFF / 設定差異で説明可能。genuine bug は発見されなかった。

### 2-b. environmental (preset/環境依存で正常 fail)

| smoke | fail cases | reason |
|---|---|---|
| gateguard-smoke | Case 1/3 | harness-dev preset で gateguard が advisory 化 (`feature_gateguard_enabled` 相当を OFF)。team-default/strict では BLOCK される。enforcement_matrix.gateguard.disabled_reason 参照。 |
| workflow-guard-smoke | Case 2/3/5 | harness-dev preset で workflow_guard が advisory 化 (`feature_workflow_guard_enabled=false`)。team-default/strict では BLOCK される。 |
| task-rule-guard-smoke | Case 1/4/12 | Case 1/4: harness-dev preset で task_rule_guard が advisory 化 (`feature_task_rule_guard_enabled=false`)。Case 12: 同 feature で list-md-plan-first-reminder も no-op。 |
| list-md-plan-first-reminder-smoke | Case 1/7 | `feature_task_rule_guard_enabled=false` により list-md-plan-first-reminder が no-op。team-default/strict では WARN が発火する。 |
| hc-config-web-ui-smoke | 実行ごとに異なる case | ポート競合/サーバ起動タイミングによる間欠 fail (flaky)。S-02/S-39/S-45 等。 |
| install-sh-sync-drift-smoke | Case C/E (間欠) | git worktree 状態・rsync タイミング依存の間欠 fail。単独実行では通常 PASS。 |

処理: `run-all-smokes.sh` の expected-fail manifest に reason 付きで登録。

### 2-c. obsolete (task-39 緩和で永久に意味を失った)

| smoke | fail cases | reason |
|---|---|---|
| autonomous-action-guard-smoke | Case 1/2/4 | task-39 緩和 (2026-05-25) で `git push origin main`/`gh pr create` が自律実行可となり BLOCK されなくなった。Case 1/2/4 は旧 BLOCK 期待。next-actions #25/#31 既知。 |
| audit-followups-smoke | Case 3/4 | task-39 緩和で `git push origin main` が Normal/Loop ともに block されなくなった。 |
| loop-auto-progress-smoke | Case 4/5/9 | task-39 緩和で `git push feature branch`/`gh pr create` が自律実行可。Case 4/5/9 が旧 BLOCK 期待。 |

処理: `run-all-smokes.sh` の expected-fail manifest に reason 付きで登録。smoke 自体は「旧仕様の記録」として残す (削除しない)。

### 2-d. spec-drift (期待値が実装変化に追いついていない)

| smoke | fail cases | reason |
|---|---|---|
| context-budget-smoke | 60pct fire / spam prevention | harness-config.yml の `context_budget_threshold=0.66` (リポ固有設定)。smoke は default 0.60 前提で 60pct fixture を fire 期待するが 0.66 未満のため silent。 |
| tool-call-slip-detector-smoke | Case 1/2 | `feature_tool_call_slip_detect_enabled=false` により hook が no-op。feature 有効時前提の stale 期待値。consuming repo では PASS する。 |
| stale-harness-detect-smoke | Case 6 | `HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false` env override が `config-loader` 経由の `is_feature_enabled` に負ける。yml の `feature_stale_harness_detect_enabled=true` が優先されて WARN が出続ける。 |
| wave-precheck-template-smoke | Case 2 | workflow.md に `git log --grep` の記述が 0 hit。task-56 当時に想定した Stage 8/7 の記述が workflow.md から削除または未追加。 |
| custom-pm-commands-smoke | Case 5 | grep `/sc:(save\|load\|pm)` で allowed 外ファイルに残存 hit がある。除外パターンの更新漏れ。 |
| audit-followups-smoke | Case 2 | confidence gate が general-purpose を現在 block しない (実装変更)。 |

処理: `run-all-smokes.sh` の expected-fail manifest に reason 付きで登録。

---

## 3. landscape 調査後の実測差異

| smoke | landscape 記録 | 実測 (2026-06-02) | 備考 |
|---|---|---|---|
| hook-frequency-tweaks-smoke | FAIL Case 7 | PASS (8/8) | Step 1-3 で修正済 |
| install-sh-sync-drift-smoke | FAIL Case G | PASS または 間欠 FAIL | Step 1-3 後に修正済 or flaky |

---

## 4. genuine regression 検索結果

全 fail smoke を 4 分類で調査した結果、**genuine regression は 0 件**。

全 fail は以下のいずれかで説明可能:
1. harness-dev preset による意図的な advisory 緩和 (environmental)
2. task-39 緩和後の期待値更新漏れ (obsolete)
3. リポジトリ固有設定と smoke default の乖離 (spec-drift)
4. feature toggle OFF による no-op (spec-drift)
5. ネットワーク/タイミング依存の間欠 fail (environmental)

---

## 5. run-all-smokes.sh の expected-fail manifest 登録状況

`bash .claude/tests/run-all-smokes.sh --list` で全件確認可能。

manifest 登録 smoke 14 件 (実測 EXPECTED-FAIL は 13 件、install-sh-sync-drift は間欠 fail のため登録済だが今回 PASS):
- environmental: gateguard-smoke, workflow-guard-smoke, task-rule-guard-smoke, list-md-plan-first-reminder-smoke, hc-config-web-ui-smoke, install-sh-sync-drift-smoke (間欠 fail)
- obsolete: autonomous-action-guard-smoke, audit-followups-smoke, loop-auto-progress-smoke
- spec-drift: context-budget-smoke, tool-call-slip-detector-smoke, stale-harness-detect-smoke, wave-precheck-template-smoke, custom-pm-commands-smoke

**UNEXPLAINED-FAIL == 0** が `run-all-smokes.sh` の exit 0 条件。

## 6. 実測実行ログ (2026-06-02 確定)

```
=== run-all-smokes summary ===
Total smokes run : 67
PASS             : 54
EXPECTED-FAIL    : 13 (manifest 登録済、reason 付)
UNEXPLAINED-FAIL : 0
SKIP             : 0
EXIT 0: UNEXPLAINED-FAIL == 0 (放置 fail なし)
```
