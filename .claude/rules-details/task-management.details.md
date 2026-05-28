---
paths: []
related: task-management.md
---

# タスク管理ルール — 詳細版 (Layer B)

> Layer A: [`task-management.md`](../rules/task-management.md) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

本 file は Layer A の SSoT を補完する詳細解説。採用 6 条の OK/NG 例 / 必読義務の起源 / 既存 task 移行優先度 / UI 検出 future work / plan-first 機械検出 hook 仕様 / Hook 強制詳細 / 起源を含む。Read trigger 4 条件は Layer A 冒頭参照。

## 採用 6 条 詳細

### 改定理由 (3 問題、task-33 実例観測)

1. **粒度過剰**: task-33 が 5 Phase × 14 Step で deliverable として scope 過大
2. **status 不可視**: list.md row が task 単位のみ、Step status が IDE 視点で追跡不可
3. **概要欄混在**: list.md 概要列が task overview / step description 区別なく記載

### 条 2 詳細 (Task 必須項目 5 件)

「観察可能」とは PASS/FAIL or 数値 or before/after diff のように第三者が客観確認できる粒度を指す:

- OK 例: 「全テスト 92/92 PASS」「list.md に新 entry 1 行追加」「Layer A size 元 33K → 目標 ~10K」
- NG 例: 「動くようにする」「整理する」「適切に処理」(検証不能)

依存先タスクは「**`task-N1, task-N2` 形式で ID 列挙**」 + 各依存先について Task header section に **影響内容 (1-2 文) + 依存先 task.md へのリンク** を記載。

### 条 3 詳細 (Step 必須項目 4 件)

「test PASS」のような曖昧表現ではなく、再現可能な検証コマンドを書く:

- OK 例: 「`bash .claude/tests/foo-smoke.sh` exit 0」「`grep -c '...' file.md` で 2 件以上」
- NG 例: 「動作確認」「テスト OK」「正常終了」

### 条 4 詳細 (テスト設計レビュー)

**動的選定の判定ヒント** (固定 registry 不採用、case-by-case):

- **常時 base 候補**: tdd-guide / test-automator / qa-expert / pr-test-analyzer
- **UI 含む** → ui-designer / accessibility-tester / e2e-runner 加味
- **DB schema / migration** → database-reviewer / postgres-pro 加味
- **API 変更** → api-designer / api-documenter 加味
- **言語特定** → 言語別 reviewer (python-reviewer / typescript-reviewer / go-reviewer / rust-reviewer 等) 加味
- **security 影響** → security-reviewer / security-auditor 加味
- 上記から **5 件以上**を動的選定

**ビジュアル検証 (browser/web UI、E2E とは別レイヤ、2026-05-27 採用、draft `ui-visual-verification-mandate.md`)**:

- `agent-browser` skill (vercel/agent browser) で実際にブラウザ描画 → screenshot 取得 → 目視確認
- 主要 breakpoint (320/768/1024/1440 等) / 主要状態 (hover/focus/active/error 等) / 両 theme (あれば) を撮影
- レイアウト / 配色 / タイポグラフィ / 余白 / レスポンシブ が設計意図通りか確認 (可能なら before/after 比較)
- E2E (機能フロー動作) とは別の品質軸。**両方 PASS で初めて UI Task 完了**、E2E のみ / 型チェックのみでは完了宣言しない
- 非対話 / CI 環境は Playwright screenshot で代替可。honor-system (機械強制 hook なし)

**yml 値による制御 (task-44/45/46)**: reviewer 動的選定の下限 / 上限 / 反復は `harness-config.yml` の `review_min_count_test` (default 5) / `review_max_count_test` (default 10) / `review_iteration_max` (default 5) で集中制御 (`HC_REVIEW_*` env で override 可、`bash .claude/scripts/hc-config.sh --set review_min_count_test=3` で安全に変更可、atomic backup + type validation)。詳細は `docs/SELF_IMPROVEMENT.md` §「hc-config.sh による yml 編集」参照。

### 条 6 詳細 (list.md 表現規約)

**依存先列 format** (採用 6 条 2 連動): `task-N1, task-N2, task-N3` (カンマ区切り ID 列挙)、依存なしは `—` (long-dash) で空欄禁止。Task header section に各依存先について **影響内容 + リンク** 記載必須。

**OK/NG 例**:

- **OK 例 (Task 概要欄)**: 「recall_poc plan-first 不在事案の再発防止のため、task-management.md §plan-first を追加し batch planning 時の 📝 行先置きフロー 2 経路分岐を明文化する。完成すれば AI が batch planning 時に list.md plan-first 先置きを規範通り実行できるようになる。」
- **OK 例 (Step 概要欄)**: 「task-management.md §plan-first 新規 subsection 追加 (経路 A/B 分岐 + 凡例 📝 用途明文化)」
- **NG 例 (Task 概要欄)**: 「規範を追加」(目的 / 成果不明) / 「Phase 1 完了、Phase 2 進行中」(Step 状態を概要欄に書かない、それは Step Status 列の責務)
- **NG 例 (Step 概要欄)**: 「task-management.md §plan-first を追加することで AI が規範通り実行できるようになる」(Task 概要欄の規約を Step に流用しない、Step は work only)

### task-29 採用 5 条 supersede 経緯

task-29 採用 5 条 (`docs/draft/phase-step-task-structure.md`、2026-05-23 採用) は task → Phase → Step の 3 階層を規範化したが、task-33 実装で 5 Phase × 14 Step に肥大化し以下の問題を顕在化:

1. Phase 1 完遂時点での status 判定困難 (Phase 完了 = task 完了か Step 完了か曖昧)
2. Step status が IDE 視点で不可視 (list.md row が task 単位のみ)
3. 概要欄の Task / Step 区別なし

→ 2026-05-25 user 4 ターン連続承認で **Task = Phase = N Step (2 階層)** に圧縮し採用 6 条として規範化、task-29 採用 5 条を supersede。

## 開発開始時必読 詳細

### 起源

user 指示「list.md やタスク詳細へ後続のタスクへどう影響するのかを意識させるために list.md へ依存先タスク (table 列追加)、タスク詳細.md へどのように影響するのかとタスク.md へのリンクを表記すること。開発時はそれとリンク先を必ず読むこと」(2026-05-26)。

### 違反検出 (現状 honor system、将来機械強制化)

| 段階 | 検出方法 | 動作 |
|---|---|---|
| **現状 (2026-05-26〜)** | honor system | main agent が `/start-task` 直後に必読対象を Read する宣言 (Why × 5 で「依存先 task-N1 / N2 の影響を確認するため、それぞれの task.md + draft を Read する」と明示) |
| **将来 (案、別 task で起票)** | `task-rule-guard.sh` 拡張 | `/start-task <id>` 検出時に対象 task ファイル + 依存先 task ファイルが本 session で Read 済か判定、未 Read なら warn 注入 (block しない、honor system 維持で過剰防止) |

### 効果 (3 層 DAG)

- 後続タスクへの影響を **着手前に意識** することで、依存先の設計判断 / 完了状態を踏まえた実装が可能
- 「依存先 task は完了済と思い込み実装着手 → 実は ⏸️ 保留中で前提崩壊」のような事故を構造的に防止
- list.md 依存先列で **DAG 視覚化** + task.md 依存先 section で **影響内容明示** + 開始時必読義務で **実 Read 強制** の 3 層で依存関係の暗黙知化を防ぐ

## 既存 task 移行 詳細

### 移行優先度 (G2 → G3)

| task | 状態 | 優先度 | 備考 |
|---|---|---|---|
| **task-33 (list-md-plan-first-normative)** | 5 Phase 構造 (Phase 1 完遂、Phase 2 Step 2.2 まで) | **本 commit で即 restructure** | 本規範改定の起源、Wave C-1 で 5 task (33/34/35/36/37) に分割 |
| task-21 (system-reminder-attention) | W3 残 | **最優先** | 規範整備系で本規範の起源とも近い、整合性確保 |
| task-23 (recall-poc-recovery) | W4-W5 残 | 高 | 実装系、Wave 跨ぎの依存が多い |
| task-24 (taskmanagesystem-recovery) | W5 残 | 高 | 規範整備系、本 rule との整合性確保 |
| task-27 (observe-jq-parse-fix) | W3 残 | 中 | W3 不要判定検討中、不要なら低優先度に降格可 |
| task-28 (observe-subagent-stop-instrumentation) | Phase 2 残 | 中 | 既に Phase 命名を採用、Step 粒度のみ要確認 |

移行作業は task 着手前 (`/start-task <id>` 実行前後) の準備として実施。新構造へ書き換えても commit 履歴・既存 Phase / Wave での完了実績は temporal record として残す (削除しない)。

## UI 検出 詳細

### 機械強制 hook 案 (future work)

本規範採用フェーズでは規範のみ (honor system)。効果観察後に別 task で `task-rule-guard.sh` 拡張により Task 内容を parse → UI 判定 → E2E + ビジュアル検証 (採用 6 条 4、2026-05-27 採用) Step 存在検証を機械強制化する案を検討する (起案は `docs/draft/` 経由で別 task として起こす)。

過検知 (誤って UI と判定) は許容、見逃し (UI なのに非 UI 判定) は不可。

reviewer 確認推奨 (`/module-review` or `/system-review` 時に skip 妥当性をレビュー)。

## plan-first 詳細

### 経路 B 手順 詳細 (4 step)

1. **master roadmap で N 個 task を §plan で確定**: `docs/draft/00_master-roadmap.md` 等で計画段階の task list (id / slug / 概要 / 依存) を確定 + user 承認

2. **main agent が `list.md` に N 行 📝 batch 先置き**: 承認時点で list.md 末尾に N 行を **📝 設計（未承認）** status で append (main 直接 Edit、`task-rule-guard.sh` の exempt case で `list.md` 通過)。各行は draft link 付き。
   - **ID 払い出し手順**: list.md 既存最大 ID + 1 から連番で N 件割り当て (`grep -oE 'task-[0-9]+' docs/tasks/list.md | grep -oE '[0-9]+' | sort -n | tail -1` で最大値取得、+1 開始)。**結果が空 (list.md に `task-N` 行が 1 件も無い初期状態) の場合は ID=1 を初期値**とする (例: `next_id=$((${max:-0} + 1))` で max 空時 0 fallback、+1 で 1 開始)
   - **重複検知**: 同 ID が既存 (📝 / 🔲 / 🔄 / ✅ 問わず) なら BLOCK + user 通知
   - **Loop モード整合**: master roadmap §plan で user 承認済の N task を list.md に転記する **事務作業**なので、`modes.md` 遵守事項 2 例外条項「設計文書の新規追加」には該当せず、main 自律実行可。

3. **個別 draft 起案** (subagent 並列可): 各 task の draft (`docs/draft/<slug>.md`) を起案 → user 承認 → 経路 A step 4 へ

4. **`/new-task <id> <slug>` で 📝 → 🔲 update**: list.md の **同 ID かつ 同 slug** の既存 📝 行を **🔲 未着手** に status update (新規行 append しない、行重複なし)。`/new-task` 実装は list.md grep で既存 📝 行検出 (**ID + slug の AND 一致** 必須、ID 単独 / slug 単独 grep 禁止)。
   - **複数マッチ**: 同 ID + slug で 2 行以上 hit なら BLOCK + user 通知
   - **status conflict**: 同 ID で status が 📝 以外 (🔲 / 🔄 / ✅) で既存なら BLOCK + 重複 ID 修正案内

### 機械検出 hook 仕様 (task-33 Phase 3 + 4)

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

### 起源 (recall_poc plan-first 不在事案、2026-05-25)

- 2026-05-25 recall_poc で plan-first 不在事案発生 (26 task batch plan で list.md 空継続 + user 明示質問でようやく顕在化)
- user Post-Mortem 報告で真因 4 階層を特定:
  1. `/new-task` 1-task-at-a-time gate (経路 B 想定外の sequential 動作)
  2. 規範矛盾 (採用 6 条との整合性)
  3. 凡例 📝 用途未明文化 (single draft 中 vs batch plan 中の判別不可)
  4. AI 運用判断ミス (batch planning 経路 B の認識欠落)
- task-33 で案 C ハイブリッド (P1+P2+P3+P5、工数 2.5) 採用、規範修正 P1 が本 § に該当
- task-34 が `/new-task` 📝→🔲 update 動作、task-35 が SessionStart hook、task-36 が PreToolUse(Write `docs/draft/*.md`) warn 注入を担当

## Hook 強制 詳細

### 詳細シナリオ (PreToolUse、`task-rule-guard.sh`)

| シナリオ | 動作 | 備考 |
|---|---|---|
| `docs/tasks/task-<id>-<slug>.md` の Write、対応する `docs/draft/{<slug>.md, task-<slug>.md, <basename>}` が無い | **BLOCK** | 「先に `/new-draft` で設計を起こせ」と提示 |
| `docs/tasks/task-<id>-*.md` / `phase-<id>-*.md` の Write、同 `<id>` が既に存在 | **BLOCK** | 「別 ID を割り当てるか既存を Edit せよ」と提示 |
| `docs/tasks/` への命名規約外 Write (`task-` `phase-` で始まらない) | 警告 context 注入 (block しない) | 命名規約 hint |
| `docs/tasks/task-*.md` の **Edit** (既存編集) | context 注入 | 「list.md と同期更新せよ」 |
| `docs/tasks/parking-lot.md` の Edit | context 注入 | 必須 7 項目の hint |
| `list.md` `_TASK_TEMPLATE.md` `_DRAFT_TEMPLATE.md` の Edit/Write | exempt (素通り) | 台帳 / template は別系統 |
| サブエージェント実行中 | 全パス通過 | 多重ゲート防止 |

### subagent 通過理由

メイン専任の原則を機械強制するのは `delegation-guard.sh` (別 hook) の責務。`task-rule-guard.sh` は subagent context では全 path 通過し、メイン context での task ファイル創設 / 編集を主対象とする。

### 違反パターン例

- **設計 draft 不在のまま `/new-task` 強行** → BLOCK + 「`/new-draft <slug>` で設計を起こせ」案内
- **同 ID で別 slug を `/new-task`** → BLOCK + 既存 task.md path を案内
- **`docs/` 直下に直接設計書 Write** → `draft-flow-guard.sh` (別 hook) で BLOCK (本 hook 対象外)

## parking-lot 詳細

### 必須 7 項目 format

```markdown
### 🧊 <task 名>

- **起案日**: YYYY-MM-DD
- **保留日**: YYYY-MM-DD
- **保留理由**: <なぜ着手不可か>
- **設計書**: [docs/draft/<slug>.md](...) or [docs/<existing>.md](...)
- **実装状態**: <現状把握、partial 実装あれば link>
- **再検討トリガー**: <何が起きたら 🔍 に昇格するか>
- **代替現状**: <保留中の代替手段 or 影響範囲>
```

### 定期レビュー

🔍 entry は四半期 (3 ヶ月) ごとに見直し:

- 保留理由が消えていれば → `list.md` に新規 task として追加 (`/new-task`)、parking-lot.md から削除
- 未解消なら → 再検討トリガー / 代替現状を更新

❌ 不採用 entry は削除せず履歴として残す (過去意思決定のトレーサビリティ)。

## 起源

- **task-21 W1.7 (paths 廃止 → 常時参照格上げ)**: 2026-05-23、`paths: ["docs/tasks/**", "docs/draft/**"]` では当該 path を Read したターンしか context に load されず、設計→承認→タスク追加フローの認識が落ちる事案 (recall_poc/docs/01-03 が docs/ 直下に直接 Write された) 受けて常時参照化
- **task-26 W4 (SSoT 集約)**: 設計→承認→タスク追加フロー / メイン専任 / Parking Lot の SSoT を本 file に集約 (development-process.md / workflow.md から重複を吸収)
- **task-29 Phase 2+3 (採用 5 条規範化)**: 2026-05-23、`docs/draft/phase-step-task-structure.md` 起源、Phase→Step 2 階層構造を採用
- **採用 6 条規範化 (Task=Phase=N Step)**: 2026-05-25 採用、`docs/draft/task-equals-phase-step-status-list-normative.md` 起源、user 4 ターン連続承認、task-29 採用 5 条を supersede
- **task-33 (plan-first 規範化)**: 2026-05-25、recall_poc plan-first 不在事案後の規範修正、P1 (本 §plan-first) を担当
- **task-51 Step 3 (Layer A/B 2 層分割)**: 2026-05-28、context 過剰注入対策、self-improvement.md / development-process.md と同 format で分割

設計の起源と承認履歴は git log + `docs/draft/` 参照。
