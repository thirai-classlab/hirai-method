> Layer A: [`workflow.md`](../../rules/workflow.md) §draft-flow-guard.sh による docs/ 直下 block | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# draft-flow-guard 緩和履歴 (Layer B)

`draft-flow-guard.sh` の監視対象 path / bypass 経路本体は Layer A 参照。本 file は 2026-05-28 緩和 (旧 task-40 拡張撤廃) の経緯と緩和後 hook 役割。

## 2026-05-28 緩和 (task-40 拡張の撤廃)

旧 task-40 拡張 (2026-05-26) は `.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/docs/**/*.md` への **新規 Write** も draft 承認 (`approved_at` / `retroactive`) 不在で BLOCK していた。

user 指示「既存 rules file の Edit は PASS (新規 Write のみ BLOCK) → 書き込みも許容してください」により、これらの規範文書 path は **新規 Write / 既存 Edit とも PASS** に緩和。本 hook はもはや `.claude/rules/` / `.claude/commands/` / `.claude/templates/docs/` を一切監視しない。frontmatter parser (`extract_frontmatter_value` / `verify_draft_status`) + 新 path pattern 判定 + retroactive 厳格化ロジックは hook から削除済。

## 規範変更時の hook 役割 (緩和後)

| シナリオ | 動作 |
|---|---|
| `.claude/rules/<basename>.md` / `.claude/commands/<basename>.md` / `.claude/templates/docs/**/<basename>.md` の **新規 Write / 既存 Edit** | **PASS (Edit 同様、2026-05-28 user 指示で緩和)** — 旧 task-40 拡張 (draft 承認不在で BLOCK) を撤廃 |
| `docs/` 直下の既存 file の Edit | **PASS** — 新規 Write のみ block 対象 (`if [ -f "$file_path" ]; then exit 0; fi`) |
| `docs/` 直下への新規設計文書 Write、対応 draft 不在 | **BLOCK** — 「先に `/new-draft <slug>` で設計を起こせ」(元機能、不変) |

## 規範変更の honor system 降格

機械強制 BLOCK は本緩和で解消されたため、規範変更の draft 経由フローは **honor system に降格**:
- `.claude/rules/*.md` / `.claude/commands/*.md` / `.claude/templates/docs/**/*.md` への新規 Write / 既存 Edit は user 確認必須 / 設計→承認フロー推奨 (規律として残す方針)
- `docs/` 直下の設計文書 block は維持 (機械強制 BLOCK)

## 起源

- 2026-05-26 task-40 で `.claude/rules/*.md` 等の規範文書も draft 経由必須化 (機械強制 BLOCK)、設計起源: `docs/draft/task-mgmt-rules-with-draft-flow-enforcement.md`
- 2026-05-28 緩和: user 直接指示「既存 rules file の Edit は PASS (新規 Write のみ BLOCK) → 書き込みも許容してください」で task-40 拡張部分 (規範文書 path の新規 Write block) を撤廃
- 関連: [`task-management.md`](../../rules/task-management.md) §「設計→承認→タスク追加フロー」/ [`modes.md`](../../rules/modes.md) 遵守事項 2 例外条項「規範変更」
