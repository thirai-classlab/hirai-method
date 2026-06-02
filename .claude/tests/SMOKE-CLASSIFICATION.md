# SMOKE-CLASSIFICATION.md — task-74 Step 4c SSoT

作成日: 2026-06-02 / branch: feat/task-71-settings-dispatcher-generation
更新: 2026-06-02 iter-1 (review findings 反映、manifest-masking 解消)

全 67 smoke の 5 種別分類 + fail の分類を記録する。

> **iter-1 更新 (point-in-time)**: review 2 体が「manifest-everything は本来処理 (obsolete→skip / spec-drift→修正 / real bug→fix) を回避した shortcut」と指摘。
> iter-1 で 4 分類を **実処理** し、manifest を「environmental (preset 緩和) 5 + flaky (quarantine) 2」のみに縮小した。
> count は最新 run (2026-06-02) 時点の値。case 構成変更で変わるため point-in-time 値として扱う。

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

## 2. fail → 4 分類 + iter-1 実処理結果 (2026-06-02)

> iter-1: 各分類を「manifest 隠蔽」ではなく **本来処理** した結果を「処理」列に記録。
> environmental + flaky のみ manifest 登録、obsolete/spec-drift/real-bug は実処理で PASS 化。

### 2-a. genuine regression / real bug (FLAG)

| smoke | case | 内容 | iter-1 処理 |
|---|---|---|---|
| stale-harness-detect-smoke | Case 6 | **real bug**: `config-loader.sh` `_HC_KNOWN_KEYS` に `FEATURE_STALE_HARNESS_DETECT_ENABLED` が欠落 → `HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false` env override が yml `true` に上書きされ無効 (hook header / CommonRules bypass table の記述と矛盾)。 | **修正 1: production lib fix** — known-keys に key 追加。Case 6 PASS、manifest から削除。 |

> iter-1 以前は manifest に `[spec-drift]` として隠蔽されていたが、実体は env override が効かない real bug だった。

### 2-b. environmental (preset 緩和、恒久 expected → manifest 登録維持)

| smoke | fail cases | reason |
|---|---|---|
| gateguard-smoke | Case 1/3 | harness-dev preset で gateguard が advisory 化。team-default/strict では BLOCK。enforcement_matrix.gateguard.disabled_reason 参照。 |
| workflow-guard-smoke | Case 2/3/5 | harness-dev preset で workflow_guard が advisory 化 (`feature_workflow_guard_enabled=false`)。 |
| task-rule-guard-smoke | Case 1/4/12 | Case 1/4: task_rule_guard advisory 化。Case 12: 同 feature で list-md-plan-first-reminder も no-op。 |
| list-md-plan-first-reminder-smoke | Case 1/7 | `feature_task_rule_guard_enabled=false` により no-op。team-default/strict では WARN 発火。 |
| tool-call-slip-detector-smoke | Case 1/2 | `feature_tool_call_slip_detect_enabled=false` (誤検出ループ主因で 2026-06-01 意図的 OFF) により no-op。consuming repo (feature ON) では PASS。 |

処理: `run-all-smokes.sh` の expected-fail manifest に `[environmental]` reason 付きで **登録維持** (preset 設計上の正常 fail)。

### 2-c. obsolete (task-39 緩和で永久に意味を失った → case skip 化)

| smoke | obsolete cases | iter-1 処理 |
|---|---|---|
| autonomous-action-guard-smoke | Case 1/2/4 | **修正 2**: `# [OBSOLETE: task-39]` marker + 内部 skip (SKIP 計上、FAIL に数えない)。有効 Case 3 (vercel) / 5 (bypass.log) は実行継続。smoke exit 0、manifest から削除。 |
| audit-followups-smoke | Case 3/4 (obsolete) | **修正 2**: Case 3/4 (task-39 push) のみ obsolete skip。Case 1 (F3 fail-open) は実行継続。<br>**iter-2 MEDIUM-1 訂正**: Case 2 は obsolete ではなく **env-sensitive** だった (confidence-gate の block ロジックは task #9 `bb38bc9` 以降不変、harness-dev preset の `confidence_required: false` default で fail するだけ。context-budget Case 1 と同クラス)。誤った「confidence-gate impl change / obsolete」ラベルを除去し、`HC_CONFIDENCE_REQUIRED=true` (+ isolated `HC_CONFIDENCE_STATE_DIR`) を明示 set して **active assert** 化済 (missing confidence + general-purpose → BLOCK)。smoke exit 0、manifest から削除。 |
| loop-auto-progress-smoke | Case 4/5/9 | **修正 2**: task-39 push/pr 関連を skip。有効 Case 1/2/3/6/7/8 (reminder fire / vercel block / bypass.log / 素通し) は実行継続。smoke exit 0、manifest から削除。 |

### 2-d. spec-drift (期待値が実装変化に追いついていない → 決定論修正)

| smoke | fail cases | iter-1 処理 |
|---|---|---|
| context-budget-smoke | Case 1 / Case 6 (spam) | **修正 3**: Case 1/6 に `HC_CONTEXT_BUDGET_THRESHOLD=0.60` を明示 set (Case 10 env override パターン踏襲)。repo 0.66 依存を排除し決定論化。11/11 PASS、manifest から削除。 |
| wave-precheck-template-smoke | Case 2 | **修正 3**: `git log --grep` 記述が task-51 Layer A/B 再構造で Layer B (`14-stage.md`/`10-stage.md`) へ移動。Case 2 を Layer B file 参照 + Layer A pointer 確認に更新。4/4 PASS、manifest から削除。 |
| custom-pm-commands-smoke | Case 5 | **修正 3**: anchor bug (`^\./README\.md` は grep -rl の `./` なし出力に match せず bleed) を `(^\./)?` で prefix optional 化 + `rules-details/workflow/origin.md` を除外 list に追加。6/6 PASS、manifest から削除。 |

処理: 全 spec-drift を決定論修正で PASS 化、manifest から削除。

### limitation (fix 5、case 単位 parse 未実装)

現 `run-all-smokes.sh` は smoke 単位 (exit code) で EXPECTED-FAIL 判定する。manifest reason に列挙した "Case N/M" 以外が新たに fail しても、smoke 全体 exit 1 として同じ EXPECTED-FAIL に吸収され UNEXPLAINED にならない (検出力の盲点)。本来は列挙 case 以外の fail を UNEXPLAINED 扱いすべきだが、case 単位 parse は別 task。runner manifest 各 reason に注記済。

### flaky (quarantine、根本追跡対象 → manifest 登録 + next-actions 起票)

| smoke | flaky cases | root cause | 追跡 |
|---|---|---|---|
| hc-config-web-ui-smoke | S-02/S-39/S-45 等 (実行ごと変動) | port contention / サーバ起動タイミング。単独再実行では PASS する場合が多い。 | next-actions #72: web-ui port contention skip 強化 |
| install-sh-sync-drift-smoke | Case C/E (間欠) | git worktree 状態・rsync タイミング依存。単独実行では通常 PASS。 | next-actions #72: install-sync sequential 実行化 |

処理: `run-all-smokes.sh` manifest に `[flaky-quarantine]` reason で登録。environmental とは risk profile が異なる (恒久 expected ではなく一時的 quarantine)。next-actions #72 で root-cause investigation を起票。

---

## 3. landscape 調査後の実測差異

| smoke | landscape 記録 | 実測 (2026-06-02) | 備考 |
|---|---|---|---|
| hook-frequency-tweaks-smoke | FAIL Case 7 | PASS (8/8) | Step 1-3 で修正済 |
| install-sh-sync-drift-smoke | FAIL Case G | PASS または 間欠 FAIL | Step 1-3 後に修正済 or flaky |

---

## 4. genuine regression / real bug 検索結果

iter-1 で 4 分類を本来処理した結果:
1. **real bug 1 件発見・修正**: stale-harness-detect Case 6 が manifest `[spec-drift]` に隠蔽されていたが、実体は `config-loader.sh` の env override 欠落 = real bug。修正 1 で fix (production lib)。
2. harness-dev preset による意図的な advisory 緩和 (environmental) → manifest 登録維持
3. task-39 緩和後の期待値更新漏れ (obsolete) → case skip 化で実処理
4. リポジトリ固有設定と smoke default の乖離 (spec-drift) → 決定論修正で実処理
5. feature toggle OFF による no-op (tool-call-slip = environmental に再分類)
6. port contention / timing 依存の間欠 fail (flaky) → quarantine + next-actions #72 追跡

manifest-everything (review 指摘) を解消し、real bug を 1 件顕在化させた。

---

## 5. run-all-smokes.sh の expected-fail manifest 登録状況 (iter-1 縮小後)

`bash .claude/tests/run-all-smokes.sh --list` で全件確認可能。

manifest 登録 smoke **7 件** (iter-1 で 14 → 7 に縮小):
- **environmental (preset 緩和、恒久 expected) 5 件**: gateguard-smoke, workflow-guard-smoke, task-rule-guard-smoke, list-md-plan-first-reminder-smoke, tool-call-slip-detector-smoke
- **flaky (quarantine、next-actions #72 追跡) 2 件**: hc-config-web-ui-smoke, install-sh-sync-drift-smoke

iter-1 で manifest から削除 (本来処理で PASS 化) 7 件:
- real bug fix: stale-harness-detect-smoke (修正 1)
- obsolete skip: autonomous-action-guard-smoke, audit-followups-smoke, loop-auto-progress-smoke (修正 2)
- spec-drift 修正: context-budget-smoke, wave-precheck-template-smoke, custom-pm-commands-smoke (修正 3)

**UNEXPLAINED-FAIL == 0** が `run-all-smokes.sh` の exit 0 条件。

## 6. 実測実行ログ (2026-06-02 iter-1、point-in-time)

iter-1 修正後の `bash .claude/tests/run-all-smokes.sh` 実測値。
hc-config-web-ui-smoke は network bind 不可環境で SKIP される場合あり (実 count は環境依存)。

(実測 summary は task report に記載。EXPECTED-FAIL は environmental 5 + flaky 2 = 最大 7、
network SKIP / flaky 単独 PASS により実 count は変動。UNEXPLAINED-FAIL == 0 / EXIT 0 を維持。)
