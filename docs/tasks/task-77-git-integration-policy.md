---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
total_steps: 8
-->

# Task #77: git 統合ポリシー設定 (mainline_branch + mainline_integration_policy 3 段階)

> Status: **✅ 完了** (2026-06-03、全 8 Step。設計レビュー 7体収束 + 実装 commit 6本 + Step6-fix、git-deny smoke 21/21・git-policy 5/5・web-ui S-52-54・run-all-smokes UNEXPLAINED-FAIL 0、UI visual 確認。push/PR は feature branch 自律、merge は user)
> 起案: 2026-06-03
> 関連: #70 (enforcement_matrix), git_workflow 飾り audit (2026-06-03)
> 設計起源: [git-integration-policy](../draft/git-integration-policy.md) ✅承認済 + 5体design-review収束

## Task ゴール

`mainline_branch` (本流可変) + `mainline_integration_policy` (3 段階: pr-required / local-merge / local-merge-push) を設定可能にし、AI が policy に従って「ローカル本流 merge まで」or「remote push まで」を自律実行する。remote 保護ブランチ (main/stg*/release/*) への push は安全弁を維持しつつ policy=local-merge-push 時のみ mainline push を許可。git_workflow 飾り軸を実体化。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-70 | enforcement preset (default_preset 4値) と本 policy (behavior policy) の体系分離。policy は enforcement_matrix 非対象と明確化 | [task-70-enforcement-matrix-preset.md](task-70-enforcement-matrix-preset.md) |

## Task 作業概要

- yml 2 key + metadata (`Gate/Confidence`) + config-loader `_HC_KNOWN_KEYS` + hc-config.sh enum validation + charset 制限
- `git-deny.sh` (`lib/delegation-guard/git-deny.sh`) check_protected_branch_push を順序付き 3 tier に改修 (stg*/release*/main 常時 / mainline policy 連動 / 他素通し、ECC bypass 不使用、fail-safe pr-required)
- modes.md 遵守事項 8 + finish-task/resume-state 完了フローを policy 分岐 + smoke→exit0→merge の機械的 gate に
- 10 named preset values に policy 追加 + web UI 右ペイン実 key 化 + 6 axes display-only SSoT
- smoke matrix (回帰/P1-P3/stg×3/rel×3/追従/不正値/存在/2-guard) + regression 0

## Task 完了条件 (DoD)

draft §6 を SSoT とする。要点: 3 policy の挙動 + stg/release/main 常時 block + release/* 新規実装 + fail-safe pr-required + auto-merge の smoke gate + 6 axes display-only + smoke matrix 全 cell PASS + run-all-smokes regression 0 + modes.md/README 反映 + reviewer approve。

## Task 概要欄 (list.md 用、3 要素規範)

push→merge の毎回停止を設定で制御するため、mainline_branch + mainline_integration_policy (3段階) を新設し git-deny を 3 tier 保護に改修する。完成すれば repo ごとに「PR必須 / ローカルmerge / ローカルmerge+push」を選べ、remote 保護ブランチ安全弁を保ちつつローカル統合の手間を AI に委譲でき、git_workflow 飾り軸も実体化する。

## 設計

draft [git-integration-policy](../draft/git-integration-policy.md) §3 全体を SSoT。採用案 B、保護 3 tier、policy=behavior policy (enforcement_matrix 非対象)。

## TDD 戦略
- RED: smoke matrix (draft Step7) を先に書き、現状 (release/* 未 block, policy 不在) で fail
- GREEN: yml/config-loader/git-deny/norm/preset/UI を実装し matrix PASS
- REFACTOR: 3 観点

## Step 計画

draft §「Step 計画」を SSoT とする (Step 1-8、各 Step の詳細 + Step7 smoke matrix は draft 参照)。

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | ✅ | yml 2key + metadata(Gate/Confidence) + config-loader `_HC_KNOWN_KEYS`/default/export + `_validate_mainline_{integration_policy,branch}` + charset regex。新 smoke 5/5、key-parity 維持、regression 0 | — |
| 2 | ✅ | git-deny.sh 3 tier (`_classify_push_target`、release/* arm, main 常時, mainline policy 連動, 両経路, ECC 不使用, fail-safe) commit 433a653、smoke 19/19 + deny-layers 48/48 regression 0 | 1 |
| 3 | ✅(no-op) | autonomous-action-guard 改修不要を確認 (task-39 で git push pattern 撤去済、push gate は git-deny.sh のみ、iter2 architect 確認) | 1 |
| 4 | ✅ | (規範変更) modes.md 遵守事項8 policy 3状態 + finish-task Phase4.5 + resume-state に smoke→exit0→merge gate (commit 済、run-all-smokes UNEXPLAINED-FAIL 0) | 1 |
| 5 | ✅ | 10 named preset values に policy + ENUM_OPTIONS + 6 axes display-only SSoT comment (commit 済、S-52/53/54、browser visual 確認 select 描画+custom化) | 1 |
| 6 | ✅ | (テスト設計レビュー) pr-test-analyzer 1体 → gap (存在確認 / refspec-omit block / 2-guard) を Step6-fix で解消、P1/P2/存在 behavioral は honor-system 境界明記。収束 | 5 |
| 7 | ✅ | (テスト合格) git-deny smoke 21/21 + git-policy 5/5 + web-ui S-52/53/54 + relaxation 12/12、run-all-smokes UNEXPLAINED-FAIL 0 (最終状態)、Step5 で UI visual 確認 (policy select 描画+custom化) | 6 |
| 8 | ✅(skip) | (リファクタリング) skip: git-deny は `_classify_push_target` helper で両経路統一済 (非冗長化) + config 駆動 (汎用性) + 既存 smoke 慣習踏襲 (持続可能性)、3 観点で追加対応不要 | 7 |

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/harness-config.yml`, `lib/config-loader.sh`, `lib/delegation-guard/git-deny.sh`, `hc-config.sh`, `lib/hc-config-metadata.sh`, `autonomous-action-guard.sh`(確認のみ), `modes.md`, `commands/finish-task.md`, `commands/resume-state.md`, `lib/hc-config-web-server.js`, web-ui, `README.md`, smoke |
| migration | なし (default pr-required = 現行維持) |
| 互換性 | default で後方互換、hardcode main→config 化は fallback で吸収 |

## 再発防止
- 設計の外部依存 (path/source 順序) は実装前 grep 確認 (memory feedback_design_external_dependency_verification、本 task では iter2 で git-deny path 誤記を修正済)
- config 値は定義+consumer+smoke 3 点セット (memory feedback_config_value_needs_consumer_and_smoke)

## ステータスログ
| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-06-03 | 起案+設計レビュー収束 | draft 承認 + 5体design-review iter1/iter2 収束 (CRIT/HIGH=0) |
| 2026-06-03 | 完了 | 全 8 Step。commit: be9115b(S1)/433a653(S2)/1d956c7(S5)/a2e1a20(S4)/Step6-fix。smoke 全 green、run-all UNEXPLAINED-FAIL 0、visual 確認。default pr-required=現行維持で後方互換 |

## 派生 task / 次アクション候補
- (🟢) 6 axes の去就 (撤去 or 恒久ラベル化) は別 task で判断 (draft §3.6)
- (🟢) stg*/release* の policy 化 (現状常時 block) は将来検討

## 関連
- Draft: [git-integration-policy](../draft/git-integration-policy.md)
- 依存: #70
