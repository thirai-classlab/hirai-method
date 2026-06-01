> Layer A: [`workflow.md`](../../rules/workflow.md) §関連ルール / skill (代表) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 関連 skill 完全 (Layer B)

Layer A の関連ルール / skill (代表) を補完する完全 list。各 stage との連携先 skill を網羅。

## 直接関連

- `salesforce-e2e-testing` — Wave / Phase 完了時の E2E シナリオ設計 (Stage 13 `scenario-test` / Stage 9 `full-test` で参照)
- `karpathy-guidelines` — surgical changes 原則 (`/module-review` / `/system-review` の behavior-preserving 原則と整合)

## 補助関連

- `tdd-workflow` — Stage 8 `tdd` の RED → GREEN → REFACTOR ループ規範
- `eval-harness` (L1) — Stage 10 `local-test` の pass@k metrics 連携
- `verification-loop` (F2) — Stage 14 `finish` 直前の 6 phase 検証
- `gateguard` (F1) — Stage 8 `tdd` 中の Edit/Write 事前事実検証

## audit 系

- `harness-audit.py` の `bypass_log_summary()` / `fmt_bypass_log()` — `/harness-audit` での bypass 集計
- `.claude/.workflow-state/SCHEMA.md` — workflow-guard.sh が参照する JSON 仕様 SSoT
