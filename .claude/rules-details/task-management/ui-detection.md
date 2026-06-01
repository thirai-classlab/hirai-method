> Layer A: [`task-management.md`](../../rules/task-management.md) §UI 変更検出基準 | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# UI 検出 詳細 (Layer B)

## 機械強制 hook 案 (future work)

本規範採用フェーズでは規範のみ (honor system)。効果観察後に別 task で `task-rule-guard.sh` 拡張により Task 内容を parse → UI 判定 → E2E + ビジュアル検証 (採用 6 条 4、2026-05-27 採用) Step 存在検証を機械強制化する案を検討する (起案は `docs/draft/` 経由で別 task として起こす)。

過検知 (誤って UI と判定) は許容、見逃し (UI なのに非 UI 判定) は不可。

reviewer 確認推奨 (`/module-review` or `/system-review` 時に skip 妥当性をレビュー)。
