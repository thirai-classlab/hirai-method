> Layer A: [`task-management.md`](../../rules/task-management.md) §設計→承認→タスク追加フロー / plan-first | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# plan-first 詳細 (Layer B)

## 経路 B 手順 詳細 (4 step)

1. **master roadmap で N 個 task を §plan で確定**: `docs/draft/00_master-roadmap.md` 等で計画段階の task list (id / slug / 概要 / 依存) を確定 + user 承認

2. **main agent が `list.md` に N 行 📝 batch 先置き**: 承認時点で list.md 末尾に N 行を **📝 設計（未承認）** status で append (main 直接 Edit、`task-rule-guard.sh` の exempt case で `list.md` 通過)。各行は draft link 付き。
   - **ID 払い出し手順**: list.md 既存最大 ID + 1 から連番で N 件割り当て (`grep -oE 'task-[0-9]+' docs/tasks/list.md | grep -oE '[0-9]+' | sort -n | tail -1` で最大値取得、+1 開始)。**結果が空 (list.md に `task-N` 行が 1 件も無い初期状態) の場合は ID=1 を初期値**とする (例: `next_id=$((${max:-0} + 1))` で max 空時 0 fallback、+1 で 1 開始)
   - **重複検知**: 同 ID が既存 (📝 / 🔲 / 🔄 / ✅ 問わず) なら BLOCK + user 通知
   - **Loop モード整合**: master roadmap §plan で user 承認済の N task を list.md に転記する **事務作業**なので、`modes.md` 遵守事項 2 例外条項「設計文書の新規追加」には該当せず、main 自律実行可。

3. **個別 draft 起案** (subagent 並列可): 各 task の draft (`docs/draft/<slug>.md`) を起案 → user 承認 → 経路 A step 4 へ

4. **`/new-task <id> <slug>` で 📝 → 🔲 update**: list.md の **同 ID かつ 同 slug** の既存 📝 行を **🔲 未着手** に status update (新規行 append しない、行重複なし)。`/new-task` 実装は list.md grep で既存 📝 行検出 (**ID + slug の AND 一致** 必須、ID 単独 / slug 単独 grep 禁止)。
   - **複数マッチ**: 同 ID + slug で 2 行以上 hit なら BLOCK + user 通知
   - **status conflict**: 同 ID で status が 📝 以外 (🔲 / 🔄 / ✅) で既存なら BLOCK + 重複 ID 修正案内

## 機械検出 hook 仕様 (task-33 Phase 3 + 4)

- **SessionStart hook** (`list-plan-first-reminder.sh`):
  - **task エントリ行 判定基準**: `grep -cE '^\| [0-9]' docs/tasks/list.md` の結果が 0 (行頭 `| <id> |` パターン、📝 / 🔲 / 🔄 / ✅ すべて含む)
  - **draft カウント基準**: `find docs/draft -name "*.md" -not -name "_*" | wc -l` (アンダースコア prefix の template 除外)
  - **トリガー**: `docs/draft/*.md` ≥ 3 件 ∧ `list.md` task エントリ行 == 0 → `<system-reminder>` で「経路 B 適用検討」を強制注入
  - **bypass**: `HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false`

- **PreToolUse(Write `docs/draft/<slug>.md`)** (`task-rule-guard.sh` 拡張):
  - 新規 draft Write が発生した時点で、`list.md` に対応 slug の 📝 行が不在なら warn context 注入 (block しない、honor system)
  - **検出 path**: tool_input.file_path が `docs/draft/*.md` pattern に match する場合に slug 抽出 + list.md grep
  - **⚠️ フィルタ順序注意 (Phase 4 実装者向け)**: 既存 hook は L106-111 で `task_glob="*/${HC_TASK_DIR}/*"` ( = `*/docs/tasks/*`) に match しない path を early `exit 0` する。`docs/draft/*.md` はこのフィルタを通過しないため、新ロジックは **L106 以前** に draft path 判定を挿入する (or 既存フィルタ後の early-exit を draft path の場合 skip する分岐を加える) 必要がある。L111 以降に追記しても到達不能で warn 一切発火しない無音障害になる
  - **slug マッチ**: 厳密一致 (kebab-case slug)、複数マッチ時は最初の 1 件のみ参照
  - **理由**: Bash slash command (`/new-draft <slug>`) は task-rule-guard.sh の現アーキ (Edit/Write tool のみ処理) で intercept 不可、Write tool 経由で代替 (R-03 finding 反映)

## 起源 (recall_poc plan-first 不在事案、2026-05-25)

- 2026-05-25 recall_poc で plan-first 不在事案発生 (26 task batch plan で list.md 空継続 + user 明示質問でようやく顕在化)
- user Post-Mortem 報告で真因 4 階層を特定:
  1. `/new-task` 1-task-at-a-time gate (経路 B 想定外の sequential 動作)
  2. 規範矛盾 (採用 6 条との整合性)
  3. 凡例 📝 用途未明文化 (single draft 中 vs batch plan 中の判別不可)
  4. AI 運用判断ミス (batch planning 経路 B の認識欠落)
- task-33 で案 C ハイブリッド (P1+P2+P3+P5、工数 2.5) 採用、規範修正 P1 が本 § に該当
- task-34 が `/new-task` 📝→🔲 update 動作、task-35 が SessionStart hook、task-36 が PreToolUse(Write `docs/draft/*.md`) warn 注入を担当
