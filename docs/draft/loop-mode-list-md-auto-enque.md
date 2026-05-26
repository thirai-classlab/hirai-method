<!--
approved_at: 2026-05-27
retroactive: false
approved_by: thirai@classlab.co.jp
-->

# Loop モード Phase 6 拡張: list.md task 自動 enque + 閾値到達自動 /save-state

## §1 真因 (背景)

`/resume-state loop` 起動時、Phase 6 自律実行は `session/context` の「次セッション着手手順」を完遂したら停止し、新 task の発見 / enque は行わない設計。user 期待 (「タスクリストから可能な限り進めて」「閾値到達か続行不可で自動 save-state」) と乖離。

### user 質問起源

「ループモードはタスクリストから可能な限り進めて欲しい。閾値到達か続行が不可になった時に自動的に save-state」(2026-05-27、user 直接指示)。

### 現 Phase 6 仕様の制約 (`.claude/commands/resume-state.md`)

- step 3: `session/context` の「次セッション着手手順」を解析 + 自律実行可項目順次実行
- step 4: user 確認必須項目で stop
- step 5: 全項目完遂で「待機中の user 確認項目」提示後 stop
- step 6 (Phase 7): context 閾値到達で `/save-state` + session 終了

問題:
1. step 3 で `session/context` 由来の task しか enque されない、list.md の 🔲 未着手 task は対象外
2. step 5 で task 全完遂後、新 task 着手なし
3. context 閾値到達時の `/save-state` は規範記載済だが実行 trigger が AI 判断に依存 (= 自動化が弱い)

## §2 採用案

| 案 | 内容 | 評価 |
|---|---|---|
| A | resume-state.md Phase 6 step 3 拡張のみ (list.md 🔄 + 🔲 自動 enque) | 軽量、ただし stop 条件と auto save-state は別途実装必要 |
| B | A + Phase 7 自動 /save-state を Phase 6 stop 条件統合 | stop 条件統一、user 期待と一致 |
| **C ハイブリッド (推奨)** | A + B + modes.md 遵守事項 9 新設 (Loop モード = list.md 全 task 連続自律実行を明文化) | 仕様 + 規範同期、SSoT 化 |

→ **C ハイブリッド** 採用。

## §3 採用案 (実装仕様)

### 3.1 resume-state.md Phase 6 改修

新 step 3 logic:

```
3. 自律実行可項目を順次実行 (新):

   3a. session/context の「次セッション着手手順」を最優先 enque (既存)
   3b. 3a 完了後、docs/tasks/list.md から status 🔄 進行中 の task を 1 件選択し、各 Step を順次着手
   3c. 進行中 task の Step 完遂後、status 🔲 未着手 の task から依存解決順で 1 件選択し、着手
       - 依存解決: list.md「依存先タスク」列の ID 列挙を参照、依存先が全て ✅ 完了なら着手可
       - draft 承認確認: 各 task の設計 draft で `approved_at:` 非空を必須 (= user 承認済のみ自律着手、設計新規追加は modes.md 遵守事項 2 例外条項のため自律 enque 不可)
   3d. 各 task の DoD 達成で status ✅ 完了 + commit + push + PR (task #39 緩和)
   3e. 全 task ✅ 完了 or 全 🔲 task が user 確認必須 (例: draft 不在 / approved_at 空) なら step 6 (stop) へ
```

stop 条件統合 (新):

```
4. user 確認必須項目で stop (既存):
   - modes.md 遵守事項 2 例外条項到達で stop
   - 提示後 user 待機

5. 続行不可 stop (新):
   - 同一 error 3 回連続失敗
   - subagent の「要判断」報告
   - security-reviewer CRITICAL
   - 致命的 error (権限拒否 / 復旧不能 / データ破壊リスク)

6. context 閾値到達 stop (Phase 7 統合):
   - tier 80 (`context_budget_threshold` 越え + 上位 tier) 到達で **強制 stop**
   - 自動 /save-state 実行
   - 次 session 案内: 「新 session で `/resume-state loop` で継続。残 task: <id 列挙>」

7. stop 時自動 /save-state (新):
   - 上記 4 / 5 / 6 のいずれかで stop 時、即時 `/save-state` 実行
   - session/context に「Loop モード自律実行で <stop 理由> 到達、次 session で `/resume-state loop` で継続。残 task: <id 列挙>」を記録
   - stdout に再開コマンド提示
```

### 3.2 modes.md 規範補強

`遵守事項 9` 新設:

> 9. **Loop モード = list.md 全 task 連続自律実行** (必須): `/resume-state loop` 起動時、`session/context` 着手手順完遂後も `docs/tasks/list.md` の **🔄 進行中 + 🔲 未着手** task を依存解決順で自動 enque + 着手する。draft `approved_at:` 非空 (= user 承認済) task のみ自律着手可、draft 不在 / 未承認 task は user 確認必須項目として stop。停止条件 3 つ:
>    - context 閾値到達 (tier 80 以上で強制 /save-state)
>    - 続行不可 (同一 error 3 連続失敗 / 致命的 error / security CRITICAL)
>    - user 明示停止 (`stop` / 「止めて」等)
>
>    停止時は **自動 /save-state** + 「新 session で `/resume-state loop` で継続」案内。

### 3.3 既存 hook との整合

- `context-budget.sh` (UserPromptSubmit): tier 60/80/95 警告は既存維持、tier 80 警告時に Phase 6 step 6 が trigger
- `autonomous-action-guard.sh` (PreToolUse Bash): 11 カテゴリ自律禁止規制継続、Phase 6 自律実行も本 hook で block される (= main/stg push / gh pr merge / 本番 deploy 等は user 承認待ち、stop 4 該当)

### 3.4 list.md 依存解決ロジック (Phase 6 step 3c の詳細)

```
擬似コード:
  list_md_tasks = parse list.md (id, status, dependencies)
  for task in list_md_tasks:
    if task.status == "🔄":          # 進行中 task 最優先
      execute_task_steps(task)
      task.status = "✅"
      commit + push + PR
  for task in list_md_tasks (依存解決順):
    if task.status == "🔲":
      if all_dependencies_completed(task):
        if draft_approved(task):    # approved_at 非空必須
          execute_task_steps(task)
          task.status = "✅"
          commit + push + PR
        else:
          stop_reason = "draft not approved"
          break
      else:
        skip (依存先未完了)
  if all_tasks_completed:
    stop_reason = "all tasks done"
```

## §4 TDD 戦略

### smoke 新設 (1 件)

`.claude/tests/loop-mode-auto-enque-smoke.sh` (~8 case):

| Case | 内容 | 期待 |
|---|---|---|
| 1 | list.md に 🔲 未着手 task 1 件 + draft approved_at 非空 → 自動 enque | task status ✅ になる + commit/PR |
| 2 | list.md に 🔲 未着手 task 1 件 + draft approved_at 空 → stop | stop_reason = "draft not approved" |
| 3 | list.md に 🔄 進行中 task 1 件 → 最優先着手 | 🔄 task 完遂後に 🔲 task へ移行 |
| 4 | 依存関係 (task A → B、A 未完) → B skip | A 完了まで B 着手しない |
| 5 | context 閾値 tier 80 到達 → 強制 /save-state | session/context 更新 + stop |
| 6 | 全 task ✅ 完了 → all done stop | session/context に「全 task 完了」記録 |
| 7 | 同一 error 3 連続失敗 → 続行不可 stop | stop_reason = "error loop" |
| 8 | user 明示停止 → stop | session/context に user stop 記録 |

ただし smoke は **環境模倣が困難** (session/context + list.md + context 閾値の組合せ test)、本 task では integration test として手動検証 + 規範文書整合性 grep 検証に絞る。

### 検証手段

1. `grep -c "list.md" .claude/commands/resume-state.md` ≥ 3 hit (Phase 6 新 step 3 + 関連 link)
2. `grep -c "遵守事項 9" .claude/rules/modes.md` ≥ 1 hit (新規追加)
3. `grep -c "自動.*save-state" .claude/commands/resume-state.md` ≥ 1 hit (Phase 6 step 7)
4. `grep -c "依存解決" .claude/commands/resume-state.md` ≥ 1 hit (step 3c)

## §5 Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | draft + task file + list.md row + user 承認 | 全 file 存在、`approved_at` 非空 |
| 2 | 🔲 | `.claude/commands/resume-state.md` Phase 6 改修 (step 3 拡張 + stop 条件統合 + auto save-state) | grep 検証 3 件 PASS |
| 3 | 🔲 | `.claude/rules/modes.md` 遵守事項 9 新設 | grep 検証 1 件 PASS |
| 4 | 🔲 | (テスト設計レビュー skip 明示) 規範文書 + command spec 改修のみ、smoke 環境模倣困難で integration test 不可、grep 検証で代替 | skip 理由を Step 内で明示 |
| 5 | 🔲 | (テスト合格) grep 検証 4 件全 PASS + 既存 smoke regression 0 | 既存 100+ smoke PASS 維持 |
| 6 | 🔲 | (リファクタリング) skip 明示: 規範文書 + spec 改修のみで refactor 余地なし | skip 理由を Step 内で明示 |
| 7 | 🔲 | commit + push + PR create | PR URL 提示 |
| 8 | 🔲 | 4 リポ user manual install 案内 | install command 提示 |

**総工数推定**: 3-4h、**本セッション後段 or 次セッションで完遂可能**。

## §6 DoD

- [ ] `docs/draft/loop-mode-list-md-auto-enque.md` 存在 + `approved_at` 非空
- [ ] `.claude/commands/resume-state.md` Phase 6 改修 (list.md 自動 enque + stop 条件統合 + auto save-state)
- [ ] `.claude/rules/modes.md` 遵守事項 9 新設 (Loop モード = list.md 全 task 連続自律実行)
- [ ] grep 検証 4 件全 PASS
- [ ] 既存 100+ smoke regression 0
- [ ] PR create + user merge 案内
- [ ] 4 リポ user manual install 案内

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル (新規) | `docs/draft/loop-mode-list-md-auto-enque.md` / `docs/tasks/task-47-loop-mode-list-md-auto-enque.md` |
| ファイル (修正) | `.claude/commands/resume-state.md` (Phase 6 + 7 統合改修) / `.claude/rules/modes.md` (遵守事項 9 新設) / `docs/tasks/list.md` (task-47 row 追加) |
| ファイル (test) | なし (smoke 環境模倣困難で integration test 不可、grep + 既存 smoke regression で代替) |
| migration | なし |
| 環境変数 | なし |
| 互換性 | 既存 `/resume-state` (引数なし) 動作不変、`/resume-state loop` のみ新 behavior |

## §8 レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 (skip 明示) | — | — | — | — | — | 規範文書 + command spec 改修のみで reviewer 5+ 並列起動 overkill、modes.md 既存遵守事項 1-8 との整合性は user 承認で担保 |

## §9 関連

- 起源: 2026-05-27 user 直接指示「ループモードはタスクリストから可能な限り進めて欲しい + 閾値到達か続行不可で自動 save-state」
- 前提 task: task-42 (CLAUDE.md slim 化) + task-43 (research-reuse) + task-39 (autonomous-action-guard 緩和)
- 影響 task: 本 draft 反映後の **全 Loop モード起動** で list.md 自動 enque 動作、task-44/45/46 (config-yml-feature-toggles-and-editor) も新仕様下で自動着手される
- 関連 hook: `context-budget.sh` (tier 80 trigger) / `autonomous-action-guard.sh` (11 カテゴリ block) / `loop-confirmation-detector.sh` (確認質問 detect)
- 関連 memory: 本仕様 change を反映後、`session/context` の「次セッション着手手順」記載粒度が変化 (= 短くて済む、list.md が SSoT)

## §10 着手前 user 承認事項

1. **scope 確認**: 本 draft で resume-state.md Phase 6 + modes.md 遵守事項 9 の 2 file 修正で進めるか
2. **stop 条件確認**: §3.1 step 4-7 の 4 stop 条件 (user 確認 / 続行不可 / context 閾値 / user 明示停止) で OK か
3. **依存解決ロジック確認**: §3.4 の list.md 依存解決 logic で OK か (draft `approved_at:` 非空のみ自律着手、依存先全 ✅ 完了で着手可)
4. **次 task 起動順**: 本 task と task-44 (yml 拡張) のどちらを先に着手するか? 推奨: **本 task 先行** (新 Loop モード仕様下で task-44 を進めれば自己改善的に list.md 自動 enque が機能)
