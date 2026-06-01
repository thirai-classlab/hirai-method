> Layer A: [`self-improvement.md`](../../rules/self-improvement.md) §いつどの層を使うか（要約） | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# いつどの層を使うか 詳細 (Layer B)

```
タスク受領
  → L1 で合否基準を先に書く（/eval define）
  → L2 でループ実装（Sequential / Continuous PR / GAN）
  → L1 で合否確認（/eval check）

ファイルを編集/作成しようとした時
  → F1 GateGuard が初回 BLOCK（事実調査要求）
  → 要求された 4 事実を提示
  → 同ファイルへの retry は通過

破壊的 Bash（rm -rf / git reset --hard 等）
  → F1 GateGuard が初回 BLOCK
  → rollback 手順 + 影響範囲 + 逐語引用 を提示
  → retry で通過

PR 作成直前
  → F2 /verify で 6 phase 検証
  → READY なら commit/push

タスク失敗（同じ失敗3連 / context 肥大 / drift）
  → L5 で自己診断（/agent-introspect）
  → 教訓を L4 へ送る（/learn）

セッション終了
  → L4 が Hook 経由で自動観察済み
  → 余裕があれば /instinct-status 確認
  → /gate-status で何が cleared か確認

複数プロジェクトで同じ patten 反復
  → L4 で /promote project → global

大規模・並列必要
  → L3 Ralphinho（外部 plugin・このハーネスでは雛形のみ）
```
