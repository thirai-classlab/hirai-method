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

> Status: **🔲 未着手** (設計レビュー収束済 iter1 5体+iter2 2体、CRIT/HIGH=0)
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
| 1 | 🔲 | yml 2key + metadata(Gate/Confidence) + config-loader `_HC_KNOWN_KEYS` + hc-config validation + charset regex | — |
| 2 | 🔲 | git-deny.sh 3 tier 改修 (release/* 新規, main 常時, mainline policy 連動, 明示+省略経路, ECC bypass 不使用) | 1 |
| 3 | 🔲 | autonomous-action-guard 改修不要を確認 + コメント明記 (no-op) | 1 |
| 4 | 🔲 | (規範変更) modes.md 遵守事項8 policy 3状態 + finish-task/resume-state に smoke→exit0→merge gate + conflict/push拒否停止 | 1 |
| 5 | 🔲 | 10 named preset values に policy + web UI 右ペイン実key化 + 6 axes display-only SSoT | 1 |
| 6 | 🔲 | (テスト設計レビュー) reviewer 動的選定 min≤N≤max | 5 |
| 7 | 🔲 | (テスト合格) smoke matrix 全cell + run-all-smokes regression 0 | 6 |
| 8 | 🔲 | (リファクタリング) 3 観点 | 7 |

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

## 派生 task / 次アクション候補
- (🟢) 6 axes の去就 (撤去 or 恒久ラベル化) は別 task で判断 (draft §3.6)
- (🟢) stg*/release* の policy 化 (現状常時 block) は将来検討

## 関連
- Draft: [git-integration-policy](../draft/git-integration-policy.md)
- 依存: #70
