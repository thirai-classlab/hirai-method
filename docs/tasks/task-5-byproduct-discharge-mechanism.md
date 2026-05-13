---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

# Task #5: 副産物 discharge 機構の本格実装

> Status: **🔄 進行中 (本セッションで W1+W3 着手中)**
> 起案: 2026-05-12
> 関連: next-actions.md registry (commit `e83a683`) + development-process.md 規範強化 (commit `0aa7fc4`)
> 設計起源: [byproduct-discharge-mechanism.md](../draft/byproduct-discharge-mechanism.md)

## 背景・目的

`docs/tasks/next-actions.md` (副産物 registry) は前ターンで導入したが、「自動 surface / `/finish-task` 時 BLOCK / draft 起こし誘導」がなく **人間の規律に依存**。user 指示「**hook で強制してくださいね**」に応えるため、機械的強制機構の完全実装が必要。

## 仕様

`docs/draft/byproduct-discharge-mechanism.md` §3 採用案 B (4 層強制) に準拠:
1. **SessionStart hook**: 未処理 entry を強制 surface
2. **Stop hook**: 🔴 未処理が残るセッション終了を BLOCK
3. **`/finish-task` 拡張 (workflow-guard.sh)**: 発生源 task の next-actions.md 関連 entry が未処理なら BLOCK
4. **`_TASK_TEMPLATE.md` 派生セクション**: task 実装中に発見した副産物を本セクションに必ず記入
5. **`/discharge-byproduct` command 新設**: entry → draft 移行 helper
6. **`.claude/rules/workflow.md` セクション追加**: 副産物 discharge 規範 SSoT

## Wave 構成

| Wave | 内容 | 工数 | 依存 |
|:---:|:---|---:|:---|
| W1 | `.claude/hooks/next-actions-surface.sh` (SessionStart) | 0.5h | — |
| W2 | `_TASK_TEMPLATE.md` に「派生 task / 次アクション候補」セクション追加 | 0.2h | — |
| W3 | `.claude/hooks/byproduct-discharge-guard.sh` (Stop, 🔴 BLOCK + bypass) | 0.5h | W1 |
| W4 | `.claude/commands/discharge-byproduct.md` 新設 | 0.3h | W3 |
| W5 | `.claude/rules/workflow.md` に「副産物 discharge」セクション追加 | 0.2h | W4 |
| W6 | smoke test `.claude/tests/next-actions-hooks-smoke.sh` (5 ケース) | 0.4h | W1, W3 |

合計工数: 2.1 h（本セッションで W1+W3+W6 着手中、subagent #12 動作中）

## 完了条件

- [ ] 4 hook/command/template/rule 統合
- [ ] smoke test 全 PASS
- [ ] `.claude/settings.json` の SessionStart + Stop に 2 hook 配線
- [ ] 次セッション開始時に next-actions.md 未処理 entry が `<system-reminder>` で自動 surface 確認

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/hooks/*.sh` x2 / `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` / `.claude/commands/discharge-byproduct.md` / `.claude/rules/workflow.md` / `.claude/tests/*.sh` |
| migration | なし |
| 環境変数 | bypass: `ECC_NEXT_ACTIONS_SURFACE_OFF=1` / `ECC_BYPASS_DISCHARGE_GUARD=1` |
| 互換性 | 既存 hook 配線に append、既存 task ファイル影響なし |

## 関連

- Draft: [byproduct-discharge-mechanism.md](../draft/byproduct-discharge-mechanism.md)
- 派生元: [next-actions.md](next-actions.md) entry #4
- 規範: [development-process.md](../../.claude/rules/development-process.md) (commit `0aa7fc4` で副産物即時 draft 義務追加)
- 関連 commit: `e83a683` (registry) / `0aa7fc4` (規範) / 本セッション末で subagent #12 commit
