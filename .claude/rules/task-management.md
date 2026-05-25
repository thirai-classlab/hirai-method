<!--
task-21 W1.7: paths 条件付き受動 load を廃止し、常時参照 rule に格上げ。
理由: paths: ["docs/tasks/**", "docs/draft/**"] では当該 path を Read した
ターンしか context に load されず、設計→承認→タスク追加フローの認識が
落ちる事案 (recall_poc/docs/01-03 が docs/ 直下に直接 Write された)。
CLAUDE.md の Rules table で「(常時参照)」として明示し、毎セッション AI が
本 rule を読む状態にする。

task-26 W4: 設計→承認→タスク追加フロー / メイン専任 / Parking Lot の
SSoT として確立 (development-process.md / workflow.md から重複を本 file に
集約)。

task-29 Phase 2+3 (2026-05-23): Phase→Step 2 階層タスク構造規範 +
既存 task 移行ガイド + UI 変更検出基準を新設。設計起源は
docs/draft/phase-step-task-structure.md (user 承認 2026-05-23)。
-->

# タスク管理ルール

## メインエージェント専任（必須）

タスク管理はメインエージェントのみが行う。サブエージェントにタスク管理を委譲してはならない。

- `docs/tasks/list.md` のステータス更新 → メインが必ず実行
- 個別タスクファイルの作成・更新 → メインが必ず実行
- サブエージェント起動前にタスクを「進行中」に更新
- サブエージェント完了後にタスクを「完了」に更新

## タスク構造規範 (Phase→Step 強制)

**起源**: `docs/draft/phase-step-task-structure.md` (user 承認 2026-05-23、task-29 Phase 2 で本規範化)。これまでの「Wave / フェーズ自由構成」を廃し、**Phase→Step の 2 階層構造**を必須とする。

### 採用 5 条

1. **Phase→Step 2 階層必須 (最小 1 Phase + 1 Step)** — task ファイルは少なくとも 1 つの Phase と、その Phase 内に 1 つ以上の Step を持つ。Phase / Step 以外の独自階層 (Wave / Sub-Phase / Stage 等) は禁止。Wave という名称を使っていた既存 task は次回着手時に Phase→Step へ再構造化する (後述「既存 task 移行ガイド」参照)。

2. **Phase 必須項目: ゴール (1 文、観察可能) + 作業概要 (箇条書き 3-5 件)** — Phase 見出し直下に「ゴール: <1 文、観察可能な事実 or 数値>」と「作業概要: <3-5 件の箇条書き>」を記載する。「観察可能」とは PASS/FAIL or 数値 or before/after diff のように第三者が客観確認できる粒度を指す (例: 「全テスト 92/92 PASS」「list.md に新 entry 1 行追加」)。

3. **Step 必須項目: 内容 (1-2 文) + 完了条件 (定量 or 観察可能な事実)** — Step 見出し直下に「内容: <1-2 文で何をやるか>」と「完了条件: <定量値 or grep -q exit 0 等の機械検証可能な事実>」を記載する。「test PASS」のような曖昧表現ではなく、「`bash .claude/tests/foo-smoke.sh` exit 0」のように再現可能な検証コマンドを書く。

4. **Phase 最終 Step = テスト設計レビュー → テスト合格 → リファクタリング (3 段必須)**
   - **テスト設計レビュー Step**:
     - メインエージェントがテスト設計内容 (TDD 戦略 § + 各 Phase 内 Step 完了条件) を分析し、**適切な reviewer 5+ subagent を動的選定**して並列起動 (run_in_background: true 必須)
     - **動的選定の判定ヒント** (固定 registry 不採用、case-by-case):
       - **常時 base 候補**: tdd-guide / test-automator / qa-expert / pr-test-analyzer
       - **UI 含む** → ui-designer / accessibility-tester / e2e-runner 加味
       - **DB schema / migration** → database-reviewer / postgres-pro 加味
       - **API 変更** → api-designer / api-documenter 加味
       - **言語特定** → 言語別 reviewer (python-reviewer / typescript-reviewer / go-reviewer / rust-reviewer 等) 加味
       - **security 影響** → security-reviewer / security-auditor 加味
       - 上記から **5 件以上**を動的選定
     - 各 reviewer の修正提案を集約 → テスト設計に反映 → 再度 5+ reviewer 並列起動
     - **収束条件**: 全 reviewer が approve / no objection (修正提案 0 件)
     - **反復上限**: 5 回 (超過時 user escalation、bypass: `ECC_TEST_DESIGN_REVIEW_OFF=1` セッション全体)
   - **テスト合格 Step**:
     - レビューで合意したテスト設計に従いテスト実行
     - UI 含む Phase → **E2E 必須** (Playwright / 同等)
     - UI 変更なし Phase → unit / integration test PASS で OK
   - **リファクタリング Step**:
     - 持続可能性 / 汎用性 / 非冗長化 の 3 観点 (`/module-review` 同期)
     - 不要なら `skip: <reason>` 明示記録 (例: `skip: 単純な文字列追加で refactor 余地なし`)

5. **小タスク許容: 1 Phase + 1 Step OK** — hot fix / typo 修正 / config 1 行追加 等の小タスクでは「1 Phase + 1 Step (内容 + 完了条件)」で OK。条 4 の「最終 2 Step」は本ケースでは「1 Step 内に test 検証と refactor 判定を併記」で代替可。

### bypass

| 経路 | env | スコープ | 痕跡 |
|---|---|---|---|
| Phase→Step 強制無効化 | `ECC_PHASE_STEP_STRUCTURE_OFF=1` | 1 セッション | `.claude/.workflow-state/bypass.log` に append (hot fix 用) |
| テスト設計レビュー (採用 5 条 4 第 1 段) 無効化 | `ECC_TEST_DESIGN_REVIEW_OFF=1` | 1 セッション | `.claude/.workflow-state/bypass.log` に append (反復 5 回上限超過時の user escalation 後の継続用) |

honor system: bypass 時は理由を CLAUDE.md or `docs/tasks/<task-N>.md` の該当 entry に記録すること。機械強制 hook (`task-rule-guard.sh` 拡張で Phase 内容解析) は本規範採用フェーズでは未実装、効果観察後に別 task で検討する。

## 既存 task 移行ガイド

**適用範囲**: 本規範採用 (2026-05-23) **以降** に新規作成される task のみ Phase→Step 形式を必須とする。それ以前に作成された task は段階的に移行する。

### 既存 task の扱い

- **completed (task-1〜task-20 + task-22 / 25 / 26)**: 移行不要、Wave 構成のまま履歴として保持
- **active 進行中 (task-21 / 23 / 24 / 27 / 28)**: 次回着手時に Phase→Step 形式に **再構造化を推奨** (強制ではない、honor system)

### 移行優先度

| task | 状態 | 優先度 | 備考 |
|---|---|---|---|
| task-21 (system-reminder-attention) | W3 残 | **最優先** | 規範整備系で本規範の起源とも近い、整合性確保 |
| task-23 (recall-poc-recovery) | W4-W5 残 | 高 | 実装系、Wave 跨ぎの依存が多い |
| task-24 (taskmanagesystem-recovery) | W5 残 | 高 | 規範整備系、本 rule との整合性確保 |
| task-27 (observe-jq-parse-fix) | W3 残 | 中 | W3 不要判定検討中、不要なら低優先度に降格可 |
| task-28 (observe-subagent-stop-instrumentation) | Phase 2 残 | 中 | 既に Phase 命名を採用、Step 粒度のみ要確認 |

移行作業は task 着手前 (`/start-task <id>` 実行前後) の準備として実施。Phase→Step 形式に書き換えても commit 履歴・既存 Wave での完了実績は temporal record として残す (削除しない)。

## UI 変更検出基準

**目的**: 採用 5 条の条 4「UI 含 Phase は E2E 必須」を発動する判定基準を明文化。本規範採用フェーズでは **手動運用** とし、機械強制 hook は効果観察後に別 task で検討。

### 判定基準 (OR 条件、過検知許容)

以下のいずれかに該当する file が Phase 内の変更対象に含まれる場合、その Phase は **UI 変更を含む**と判定:

- **拡張子**: `*.tsx` / `*.jsx` / `*.vue` / `*.svelte` / `*.html` / `*.css` / `*.scss` / `*.sass` / `*.less`
- **path** (lowercase 案): `src/components/**` / `src/pages/**` / `src/app/**` / `apps/**/components/**` / `apps/**/pages/**` / `components/**`

過検知 (誤って UI と判定) は許容、見逃し (UI なのに非 UI 判定) は不可。

### 検出方法 (手動運用)

```bash
git diff --name-only <base>...HEAD | grep -E '\.(tsx|jsx|vue|svelte|html|css|scss|sass|less)$|^(src|apps/[^/]+)/(components|pages|app)/|^components/'
```

の結果が 1 件以上なら UI 変更を含む Phase と判定。Phase の最終 Step に E2E test 完了条件を必須化する。

### 手動 skip format

「UI 変更だが view 影響なし」(CSS 内変数 rename のみ / 未参照 component 削除 等) の例外時、Step 完了条件に以下のように明示:

```
完了条件: skip: UI 変更だが view 影響なし (CSS 変数 rename のみ、レンダリング結果同一)
```

reviewer 確認推奨 (`/module-review` or `/system-review` 時に skip 妥当性をレビュー)。

### 機械強制 hook 案 (future work)

本規範採用フェーズでは規範のみ (honor system)。効果観察後に別 task で `task-rule-guard.sh` 拡張により Phase 内容を parse → UI 判定 → E2E Step 存在検証を機械強制化する案を検討する (起案は `docs/draft/` 経由で別 task として起こす)。

## 設計→承認→タスク追加フロー（必須）

**設計なしのタスク追加は禁止**。下記 4 ステップを厳守:

> **Loop モードでも本フローは免除されない** (task-21 W2.2)。`modes.md` 遵守事項 2「中間確認の停止」の禁止対象は **戦術判断のみ** で、設計文書の新規追加 / 仕様変更 / 戦略的判断 は引き続き user 承認必須 (例外条項あり、`modes.md` 遵守事項 2 参照)。Loop モードで「設計→承認」ステップを skip して `docs/` 直下に直接設計書を Write する行為は規範違反、`draft-flow-guard.sh` (commit `6ed9337`) が機械強制で BLOCK する。

1. **テンプレ初期化**（初回のみ・自動）: SessionStart hook で `docs/tasks/list.md` `parking-lot.md` `_TASK_TEMPLATE.md` および `docs/draft/_DRAFT_TEMPLATE.md` がテンプレートから自動生成される。明示実行は `/init-tasks`
2. **設計起こし**: `/new-draft <slug>` で `docs/draft/<slug>.md` を `_DRAFT_TEMPLATE.md` から生成 → §1〜9 を埋める
3. **承認依頼**: ユーザーにレビュー・承認を依頼。承認履歴を draft の §8 に記録 (Loop モードでも必須、戦略判断は例外条項対象)
4. **タスク化**: 承認後に `/new-task <id> <slug>` を実行 — 以下が **同時に** 行われる:
   - `docs/tasks/task-<id>-<slug>.md` を `_TASK_TEMPLATE.md` から生成
   - `docs/tasks/list.md` に `🔲 未着手` 行を追加 (📝 行が既存なら 🔲 update、不在なら新規 append。詳細は「plan-first 行先置きフロー (batch planning)」§ 参照)
   - draft は `docs/draft/<slug>.md` に保存（履歴として残す）

### plan-first 行先置きフロー (batch planning) — 2 経路分岐 (task-33 規範化、2026-05-25)

**設計→承認→タスク追加フロー**は **2 経路** に分岐する。task の発生源 (単発 vs batch planning) で使い分け、batch 計画下での list.md 進捗 visibility を確保する。

#### 経路 A (単発、既存フロー、default)

上記 4 step を順次実行 — 1 task ずつ draft 起案 → user 承認 → `/new-task` で 1 行 append。hot fix / 1 機能 / 副産物 entry 由来など、batch 計画前提のない task に適用。

#### 経路 B (batch planning) — 新規

**master roadmap で N 個の task を計画段階で先に並べる**用途。`/new-task` の sequential 動作が想定外なため、以下 4 step で plan-first を強制する:

1. **master roadmap (or 高 level 計画 doc) で N 個の task を §plan で確定**: `docs/draft/00_master-roadmap.md` 等で計画段階の task list (id / slug / 概要 / 依存) を確定 + user 承認
2. **main agent が `list.md` に N 行 📝 batch 先置き**: 承認時点で list.md 末尾に N 行を **📝 設計（未承認）** status で append (main 直接 Edit、`task-rule-guard.sh` Hook 強制表 line 220 で `list.md` は **既存 exempt** として定義済、本 § で追加 exempt 実装は不要。task-rule-guard.sh の参照: `.claude/hooks/task-rule-guard.sh` L117-127)。各行は draft link 付き。
   - **ID 払い出し手順**: list.md 既存最大 ID + 1 から連番で N 件割り当て (`grep -oE 'task-[0-9]+' docs/tasks/list.md | grep -oE '[0-9]+' | sort -n | tail -1` で最大値取得、+1 開始)
   - **重複検知**: 同 ID が既存 (📝 / 🔲 / 🔄 / ✅ 問わず) なら BLOCK + user 通知 (誤連番 / 別 task 起案 conflict の可能性)
   - **目的**: IDE で開いた user が batch 計画全体を即可視
   - **Loop モード整合**: 本動作は master roadmap §plan で user 承認済の N task を list.md に転記する **事務作業** なので、`modes.md` 遵守事項 2 例外条項「設計文書の新規追加」には該当せず、main 自律実行可。
3. **個別 draft 起案** (subagent 並列可): 各 task の draft (`docs/draft/<slug>.md`) を起案 → user 承認 → 経路 A step 4 へ
4. **`/new-task <id> <slug>` で 📝 → 🔲 update**: list.md の 同 ID (or 同 slug) 既存 📝 行を **🔲 未着手** に status update (新規行 append しない、行重複なし)。`/new-task` 実装は list.md grep で既存 📝 行検出 (**ID + slug の AND 一致** 必須、slug 単独 grep 禁止) → 不在なら append (経路 A 動作)、既存なら update (経路 B 動作)。
   - **複数マッチ**: 同 ID + slug で 2 行以上 hit なら BLOCK + user 通知
   - **status conflict**: 同 ID で status が 📝 以外 (🔲 / 🔄 / ✅) で既存なら BLOCK + 重複 ID 修正案内
   - **⚠️ Phase 2 依存**: 本動作 (📝 既存行を 🔲 update) は task-33 Phase 2 で `/new-task` 実装更新後に有効化。Phase 1 完了時点 (本 commit) では `/new-task` は同 ID 既存行を BLOCK する (既存仕様、`.claude/commands/new-task.md` Phase 1 step 3)。Phase 1 単体運用時は経路 B step 2 後に main 直接 Edit で 📝 → 🔲 update せよ。
   <!-- smoke-anchor: new-task-update-or-append -->
   <!-- Phase 2 smoke `new-task-batch-update-smoke.sh` が「update_or_append_task_row」logic を検証 -->

#### 凡例 📝 の用途明文化

`docs/tasks/list.md` 凡例の `📝 設計（未承認）` は **2 用途** をカバーする:

| 用途 | 状態 | 出典 |
|---|---|---|
| **(1) draft 起案中 / user 承認待ち** | 単発 task の draft 起案後、`/new-task` 前の中間状態 (経路 A 中間) | 既存運用 |
| **(2) batch plan の計画段階先置き** | master roadmap で承認された task 群を list.md に N 行先置き、個別 draft 起案待ち / 承認待ち (経路 B 中間) | task-33 規範化 (2026-05-25) |

両用途で `/new-task` 実行時に 🔲 に update される。

#### 経路 B 適用判定

**判定タイミング**: user が 3 件以上の task を一括計画する意思を表明した時点で main agent が判定 → user 承認 → step 1 着手。`/new-draft <slug>` 実行直前に判定し直す必要なし。

以下のいずれかなら **経路 B** を選択:

| 判定基準 | hook 検出可能性 |
|---|---|
| master roadmap (or 同等の高 level 計画 doc) で **N ≥ 3 個の task を一括計画** (N の定義: 計画 doc の §plan / §10 等で **ID 列挙された task 数**、draft 起案済か否かは問わない) | (a) Phase 3 SessionStart hook で `draft ≥ 3 ∧ task 行 == 0` を検出 |
| 全 task の draft 起案 + user 承認 + `/new-task` 完了まで複数セッション跨る見込み (IDE 視点での progress visibility が必要) | (b) honor system (main agent 判断、機械検出不可) |
| task 間に強い順序依存 / Phase 区分があり、全体像を user が IDE で随時確認したい | (b) honor system (main agent 判断、機械検出不可) |

それ以外は **経路 A** が default。判定は main agent が user 承認時に確認、迷ったら user に問い合わせ。

#### 機械検出 (task-33 Phase 3 + 4)

- **SessionStart hook**: `docs/draft/*.md` ≥ 3 件 ∧ `list.md` task エントリ行 == 0 を検出 → `<system-reminder>` で「経路 B 適用検討」を強制注入。
  - **task エントリ行 判定基準**: `grep -cE '^\| [0-9]' docs/tasks/list.md` の結果が 0 (行頭 `| <id> |` パターン、📝 / 🔲 / 🔄 / ✅ すべて含む)
  - **draft カウント基準**: `find docs/draft -name "*.md" -not -name "_*" | wc -l` (アンダースコア prefix の template 除外)
  - **bypass**: `HC_LIST_PLAN_FIRST_REMINDER_ENABLED=false`
- **PreToolUse(Write `docs/draft/<slug>.md`)**: 新規 draft Write が発生した時点で、`list.md` に対応 slug の 📝 行が不在なら warn context 注入 (block しない、honor system)。
  - **検出 path**: `task-rule-guard.sh` の既存 PreToolUse(Edit/Write) hook を拡張、tool_input.file_path が `docs/draft/*.md` pattern に match する場合に slug 抽出 + list.md grep
  - **slug マッチ**: 厳密一致 (kebab-case slug)、複数マッチ時は最初の 1 件のみ参照
  - **理由**: Bash slash command (`/new-draft <slug>`) は task-rule-guard.sh の現アーキ (Edit/Write tool のみ処理) で intercept 不可、Write tool 経由で代替 (R-03 finding 反映)

詳細は task-33 Phase 3 / 4 を参照。

#### 起源

- 2026-05-25 recall_poc で plan-first 不在事案発生 (26 task batch plan で list.md 空継続 + user 明示質問でようやく顕在化)
- user Post-Mortem 報告で真因 4 階層 (1) `/new-task` 1-task-at-a-time gate (2) 規範矛盾 (3) 凡例 📝 用途未明文化 (4) AI 運用判断ミス を特定
- task-33 で案 C ハイブリッド (P1+P2+P3+P5、工数 2.5) 採用、本セクションは P1 (規範修正) に該当

### テンプレートの場所

- `.claude/templates/docs/tasks/list.md` — タスク台帳ひな型（凡例・依存関係図・更新ルール込み）
- `.claude/templates/docs/tasks/parking-lot.md` — 保留タスクひな型（必須 7 項目フォーマット込み）
- `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` — 個別タスクひな型（背景 / 仕様 / 設計 / TDD / Phase→Step / 完了条件 / 影響範囲）
- `.claude/templates/docs/draft/_DRAFT_TEMPLATE.md` — 設計 draft ひな型（真因 / 案比較 / Phase→Step / リスク / DoD / 承認履歴）

### 自動生成のセーフティ

- **冪等**: 既存ファイルは絶対に上書きしない（`/init-tasks --force` のみ例外）
- **ID 重複検知**: `/new-task` は同 ID が既に存在する場合中断
- **設計欠落検知**: `/new-task` は対応 draft が無い場合中断（`--no-draft` で hot fix の例外）
- **fail-open**: SessionStart hook 失敗時もセッション継続

### Hook による強制（コマンド経由でなくても発動）

`.claude/hooks/task-rule-guard.sh` が PreToolUse で以下を **block** で強制する:

| シナリオ | 動作 |
|---|---|
| `docs/tasks/task-<id>-<slug>.md` の Write、対応する `docs/draft/{<slug>.md, task-<slug>.md, <basename>}` が無い | **BLOCK** — 「先に `/new-draft` で設計を起こせ」と提示 |
| `docs/tasks/task-<id>-*.md` / `phase-<id>-*.md` の Write、同 `<id>` が既に存在 | **BLOCK** — 「別 ID を割り当てるか既存を Edit せよ」と提示 |
| `docs/tasks/` への命名規約外 Write（`task-` `phase-` で始まらない） | 警告 context 注入（block しない） |
| `docs/tasks/task-*.md` の **Edit**（既存編集） | 「list.md と同期更新せよ」context 注入 |
| `docs/tasks/parking-lot.md` の Edit | 必須 7 項目の hint context 注入 |
| `list.md` `_TASK_TEMPLATE.md` `_DRAFT_TEMPLATE.md` の Edit/Write | exempt（素通り） |
| サブエージェント実行中 | 全パス通過（多重ゲート防止） |

### Bypass

| 方法 | 用途 |
|---|---|
| `ECC_TASKGUARD=off` | セッション全体で OFF |
| `/task-bypass <slug>` | 1 ファイル分 pre-clear（`.claude/.taskguard-state/<slug>.cleared`） |
| `/task-bypass --clear-all` | 全 marker 削除 |

honor system: bypass の根拠は CLAUDE.md / docs/tasks/ の該当エントリに記録すること。

## チェックリスト

タスクを追加する際は以下を確認:

- [ ] `docs/draft/` に設計ドキュメントが存在するか
- [ ] ユーザーの承認を得たか
- [ ] `docs/tasks/list.md` の一覧テーブルを更新したか
- [ ] 個別タスクファイル（詳細リンク）を作成したか
- [ ] 設計ドキュメントへのリンクを含めたか
- [ ] task ファイルが Phase→Step 構造で記述されているか (採用 5 条準拠)

## 承認されていない設計

- 未承認の設計は常に `docs/draft/` に置く
- 承認済みの設計のみ `docs/tasks/` にリンクできる

## Parking Lot（今後検討タスク）

着手不可の保留タスクは [`docs/tasks/parking-lot.md`](../../docs/tasks/parking-lot.md) で管理する。テンプレは `.claude/templates/docs/tasks/parking-lot.md`。

**Parking Lot 運用ルール:**

- **追加条件**: 既存設計書（`docs/` 配下）または `docs/draft/` の承認済み設計へのリンクが必須。設計なし追加は禁止（通常タスクと同じ）
- **必須項目 7 つ**: 起案日 / 保留日 / 保留理由 / 設計書 / 実装状態 / 再検討トリガー / 代替現状
- **ステータス**: 🧊 保留 / 🔍 再検討予定 / ❌ 不採用
- **移行**: 再検討トリガー成立時に `parking-lot.md` から削除し、`list.md` に新規タスクとして追加（通常フロー = `/new-task`）
- **定期レビュー**: 🔍 エントリは四半期ごとに見直し。保留理由が消えていれば移行、未解消なら更新
- **不採用**: ❌ エントリは削除せず履歴として残す（過去意思決定のトレーサビリティ）

**`list.md` からの参照**: `list.md` 冒頭に parking-lot.md へのリンクを明記し、全タスク台帳として発見可能にする。

## タスク管理の関連コマンド

| コマンド | 役割 |
|---|---|
| `/init-tasks` | 台帳テンプレ初期化（SessionStart hook で自動実行） |
| `/new-draft <slug>` | 設計 draft 起こし（`_DRAFT_TEMPLATE.md` から） |
| `/new-task <id> <slug>` | 設計承認後にタスク化（`_TASK_TEMPLATE.md` から）+ list.md 行追加 |
| `/start-task <id>` | 着手（branch 切替 + status 同期） |
| `/finish-task <id>` | 完了（build/test/docs 検証 + done 化 + commit 提案） |
| `/task-bypass <slug>` | task-rule-guard を 1 ファイル分 bypass（hot fix 用） |
