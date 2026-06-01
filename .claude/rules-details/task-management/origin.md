> Layer A: [`task-management.md`](../../rules/task-management.md) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 起源 (Layer B)

- **task-21 W1.7 (paths 廃止 → 常時参照格上げ)**: 2026-05-23、`paths: ["docs/tasks/**", "docs/draft/**"]` では当該 path を Read したターンしか context に load されず、設計→承認→タスク追加フローの認識が落ちる事案 (recall_poc/docs/01-03 が docs/ 直下に直接 Write された) 受けて常時参照化
- **task-26 W4 (SSoT 集約)**: 設計→承認→タスク追加フロー / メイン専任 / Parking Lot の SSoT を本 file に集約 (development-process.md / workflow.md から重複を吸収)
- **task-29 Phase 2+3 (採用 5 条規範化)**: 2026-05-23、`docs/draft/phase-step-task-structure.md` 起源、Phase→Step 2 階層構造を採用
- **採用 6 条規範化 (Task=Phase=N Step)**: 2026-05-25 採用、`docs/draft/task-equals-phase-step-status-list-normative.md` 起源、user 4 ターン連続承認、task-29 採用 5 条を supersede
- **task-33 (plan-first 規範化)**: 2026-05-25、recall_poc plan-first 不在事案後の規範修正、P1 (本 §plan-first) を担当
- **task-51 Step 3 (Layer A/B 2 層分割)**: 2026-05-28、context 過剰注入対策、self-improvement.md / development-process.md と同 format で分割

設計の起源と承認履歴は git log + `docs/draft/` 参照。
