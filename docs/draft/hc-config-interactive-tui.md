<!--
approved_at: 2026-05-27
retroactive: false
approved_by: user
-->

# hc-config.sh 矢印キー TUI 化 + key metadata (説明 + 変更効果) 表示

> **発生源**: user 直接指示 2026-05-27「`.claude/scripts/hc-config.sh` を GWS CLI のようにインタラクティブにしてください。あとキーの一覧が何のキーなのか変えるとどうなるのか出力する必要があります」
> **前提 task**: task-46 (config-yml Phase 3、hc-config.sh 新設、PR #20 merged)
> **設計方針確定**: AskUserQuestion 2026-05-27 — UI 方式「矢印キー TUI」+ 説明表示「対話時 + --list 両方」

## §1 真因

task-46 で新設した `hc-config.sh` (1112 LOC、74 key 対応) は以下の UX 課題を持つ:

1. **対話 menu が番号選択のみ**: `cmd_interactive` は `read -r choice` の単行 text input で 5 選択肢を番号入力。gcloud / gh CLI のような ↑↓ ナビゲーション体験がない。
2. **key の意味が不明**: `--list` は KEY / CURRENT / DEFAULT / TYPE の 4 列のみ。各 key が「何のキーなのか (説明)」「変更するとどう動作が変わるか (効果)」が表示されず、user が yml を理解せず編集するリスク。
3. **inline comment が活用されていない**: harness-config.yml の inline comment 密度は 47% (35/74 key、特に feature_* / review_* / confidence_* は 100%) だが、hc-config.sh はこれを説明として表示に使っていない。

## §2 採用案

**矢印キー TUI (pure bash raw terminal) + key metadata 表示 (対話時 + --list 両方)** を採用 (AskUserQuestion で user 確定)。

調査 (subagent aef203d58008a374f confidence 0.85) で判明した制約を踏まえ、以下の段階的構成:

| layer | 内容 |
|---|---|
| metadata source | inline comment 抽出 (35 key) + metadata table hardcode (38 key) のハイブリッド |
| TUI menu | 矢印キー (↑↓ + Enter) ナビゲーション + 説明 pane、**非 TTY 時は現行番号選択に自動 fallback** |
| metadata display | 対話時の「effect panel」(key 選択後に説明 + 型 + default + 変更効果) + `--list` 説明列拡張 |

## §3 採用案 (実装仕様)

### 3.1 key metadata ソース (`.claude/scripts/lib/hc-config-metadata.sh` 新設)

74 key 全てに `{description, effect}` metadata を定義。ソースは 2 系統のハイブリッド:

- **inline comment 抽出 (35 key)**: harness-config.yml の `key: value  # comment` の comment 部を description として regex 抽出 (既存資産活用、DRY)
- **metadata table hardcode (残り 39 key + 効果補完)**: inline comment にない key (protected_paths / state_dir / task_dir 等) + 全 key の「変更時の効果 (effect)」を `lib/hc-config-metadata.sh` に集約

format (associative array or CSV、bash 3.2 互換のため CSV here-doc 推奨):

```
# KEY|category|description|effect
feature_notify_enabled|feature|macOS 通知音 (stop / notify hook)|false -> セッション完了音が鳴らない
review_iteration_max|reviewer|レビュー反復上限 (採用 6 条 4)|小さくすると reviewer cycle が早期打ち切り、大きくすると収束まで反復増
protected_paths|protected|メインからの直接 Edit/Write を block する path|追加すると該当 path が main 直接編集禁止に、削除すると委譲ガード解除
...(74 key)
```

`hc-config.sh` は本 metadata を source して description / effect を取得する。**metadata 完全性は smoke で強制** (全 74 key に description + effect 必須)。

### 3.2 category グルーピング (6 分類)

調査の実測グルーピングを採用:

| category | keys | 例 |
|---|---|---|
| 保護パス | 3 | protected_paths / protected_paths_code / code_file_extensions |
| ファイル配置 | 4 | task_dir / draft_dir / bash_whitelist_path / docs_approved_dir |
| state_dir | 9 | gateguard_state_dir / taskguard_state_dir / 等 |
| Gate/Confidence | 18 | confidence_threshold / confidence_required / context_budget_threshold / 等 |
| feature toggle | 21 | feature_*_enabled |
| reviewer control | 20 | review_min_count_* / review_max_count_* / review_iteration_max / 等 |

TUI / --list でこの category 別にグルーピング表示。

### 3.3 矢印キー TUI 実装 (`cmd_interactive` 拡張)

- **キー入力**: `read -rsn1 key` で 1 文字 capture。ESC (`\x1b`) 検出時に続く `[A` (↑) / `[B` (↓) / `[C` (→) / `[D` (←) を decode。Enter (空 or `\n`) で決定、`q` で quit。
- **描画**: category 一覧 -> key 一覧 (選択行を `>` + reverse video ハイライト) -> 下部に effect panel (選択中 key の 説明 + 型 + current + default + 変更効果)。`tput cup` / ANSI escape で再描画。
- **編集フロー**: key 選択 (Enter) -> effect panel で影響確認 -> 新値入力 -> 確認 (`変更後の効果: ...  続行? [y/N]`) -> `cmd_set` (atomic backup 付き)。
- **bash 3.2 互換**: `declare -g` / `${var^^}` 等 bash 4+ 機能を避け、`tr` / `case` で代替。

### 3.4 TTY fallback (必須)

```bash
if [ -t 0 ] && [ -t 1 ]; then
    _cmd_interactive_tui      # 矢印キー TUI
else
    _cmd_interactive_numeric  # 現行番号選択 (task-46 実装を維持)
fi
```

非 TTY 環境 (Claude Code session 内 / pipe / CI) では raw terminal 制御が効かないため、現行の番号選択 menu に自動降格。`HC_HC_CONFIG_FORCE_NUMERIC=1` で強制番号選択も可。

### 3.5 `--list` 説明列拡張

- default: KEY / CURRENT / TYPE / 説明 の 4 列 (DEFAULT 列を説明に置換、`--list --show-default` で DEFAULT 復活)
- `--list --verbose`: KEY / CURRENT / DEFAULT / TYPE / 説明 / 変更効果 の 6 列 (category 別グルーピング)
- category 見出しを挿入 (`=== feature toggle (21 keys) ===` 等)

## §4 TDD 戦略

### RED (先に smoke 新設)

`.claude/tests/hc-config-tui-smoke.sh` 新設:
- Case 1: metadata 完全性 (全 74 key に description + effect が存在、`--validate-metadata` 相当)
- Case 2: category グルーピング (6 category 全 key が分類済、未分類 key 0)
- Case 3: `--list` 説明列拡張 (説明列が表示される)
- Case 4: `--list --verbose` 6 列 (変更効果列が表示される)
- Case 5: TTY fallback (非 TTY = pipe 経由で番号選択 menu に降格、`printf 'q\n' | hc-config.sh` が番号 menu を出す)
- Case 6: `HC_HC_CONFIG_FORCE_NUMERIC=1` で強制番号選択
- Case 7: inline comment 抽出 (harness-config.yml の comment が description として取得される)

### GREEN

- `lib/hc-config-metadata.sh` 実装 (74 key metadata)
- `hc-config.sh` 拡張 (TUI + fallback + --list 説明列)

### REFACTOR

- TUI 描画ロジックを関数分割 (描画 / 入力 decode / effect panel / fallback)
- 全関数 ≤ 50 LOC 維持 (task-46 Step 6 で達成した基準を維持)

### 矢印キー TUI の検証方針 (制約明記)

矢印キー TUI 描画自体は **TTY 必須で自動 smoke 困難**。以下で対処:
- **自動 smoke**: metadata 完全性 + --list 説明列 + TTY fallback path (非 TTY 降格) を検証 (TUI を通らない経路)
- **手動検証**: 実 terminal で ↑↓ ナビゲーション + effect panel + 編集フローを user / 開発者が確認 (DoD に手動検証項目を明記)
- **expect script (option)**: pty wrapper + expect で ↑↓ key simulate は Phase 2 / 別途 (本 task では honor system 手動検証)

## §5 Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | smoke `hc-config-tui-smoke.sh` 新設 (7 cases、TDD RED) | impl 不在で 7/7 FAIL (EXPECTED FAIL marker) |
| 2 | 🔲 | `lib/hc-config-metadata.sh` 新設 (74 key の description + effect、inline comment 抽出 + hardcode) | 全 74 key に metadata、Case 1/2/7 PASS |
| 3 | 🔲 | `hc-config.sh` 拡張 (矢印キー TUI + TTY fallback + --list 説明列) | Case 3-6 PASS、TTY fallback 動作 |
| 4 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 (tdd-guide / test-automator / qa-expert / code-reviewer + ui-designer [TUI UX] + pr-test-analyzer) | iter 5 上限内収束 (CRIT+HIGH+MED=0) |
| 5 | 🔲 | (テスト合格) 全 smoke 統合 + 既存 regression 0 + 手動 TUI 検証 | 新 7 case + 既存 smoke 全 PASS + 手動 ↑↓ 確認 |
| 6 | 🔲 | (リファクタリング) TUI 描画関数分割、全関数 ≤ 50 LOC、3 観点判定 | refactor 実施 or skip 明示 |

## §6 DoD

- [ ] `lib/hc-config-metadata.sh` 新設 (74 key 全てに description + effect)
- [ ] 矢印キー TUI (↑↓ ナビ + Enter 決定 + effect panel + 編集フロー)
- [ ] TTY fallback (非 TTY で番号選択に自動降格、`HC_HC_CONFIG_FORCE_NUMERIC=1` 強制)
- [ ] `--list` 説明列拡張 + `--list --verbose` 6 列 (category グルーピング)
- [ ] smoke `hc-config-tui-smoke.sh` 7 cases PASS
- [ ] 既存 smoke regression 0 (hc-config-script-smoke 21/21 維持 + 既存 37 smoke)
- [ ] 手動 TUI 検証 (実 terminal で ↑↓ + effect panel + 編集動作確認)
- [ ] reviewer iter 5 上限内収束
- [ ] commit + push + PR create (feature branch、task #39 緩和で自律実行可)
- [ ] 4 リポ install 案内 (user manual)

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| 新規 file | `docs/draft/hc-config-interactive-tui.md` / `docs/tasks/task-48-*.md` / `.claude/scripts/lib/hc-config-metadata.sh` / `.claude/tests/hc-config-tui-smoke.sh` |
| 修正 file | `.claude/scripts/hc-config.sh` (cmd_interactive 拡張 + --list 拡張) |
| migration | なし |
| 環境変数 | `HC_HC_CONFIG_FORCE_NUMERIC` 新規追加 (強制番号選択) |
| 互換性 | 既存 CLI args 10 種不変、対話 menu は TTY 時 TUI / 非 TTY 時現行番号選択で後方互換維持。task-46 の 21 smoke は全て非 TTY (pipe) なので fallback path で PASS 継続 |

## §8 レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 | tdd-guide / test-automator / qa-expert / code-reviewer + ui-designer (TUI UX) + pr-test-analyzer (全 6、median confidence 0.87) | 3 | 13 | 10 | 8 | 修正中 → iter2 |
| iter2 | 同 6 reviewer (median confidence 0.82-0.93) | 2 | 0 | ~6 | 多数 | 修正中 → iter3 |
| iter3 (予定) | 同 6 reviewer | TBD | TBD | TBD | TBD | 修正反映後 re-review |

### iter2 結果

- **iter1 CRIT3 + HIGH13 は全 reviewer で全解消確認** (stty raw mode / Case6 env / required_env CSV tab 化 / category グルーピング / effect 再掲 / 非 TTY 案内 等)
- **新規 CRITICAL 2 (code-reviewer が bash 3.2 実機 repro で発見)**: iter2 修正で混入した `local`+command-substitution 漏洩バグ。`_tui_order_keys_by_category` (ループ内 `local kc; kc=$(...)` が cmdsubst 出力を関数 stdout に漏洩 → 戻り 147 行中 73 行ゴミ) + `_tui_render` (同種で `cat_count=`/`kc=` 22 行が端末描画混入) → **TUI が macOS bash 3.2 で起動直後機能不全**。smoke 14/14 は seam の存在確認のみで stdout purity 未検証のため見逃し。他 5 reviewer (approve or smoke MED のみ) が見落とした致命 bug を code-reviewer の深い repro が発見 (memory `feedback_code_reviewer_deep_test_advantage` 実証)
- **新規 MED ~6 (全て smoke 品質 / コメント / description、production core 外)**: Case 9 `|| true` 偽 PASS + test 名乖離 / Case 14 重複 key append で invalid yaml / script-smoke Case 1 が新 --list format 非感応 / Case 11・7 コメント不足 / Ctrl-C 復元 Phase2 defer 明記 / --list 80桁はみ出し / reviewer_control description 情報密度
- iter3 で CRITICAL 2 (local 宣言ループ外移動) + smoke purity 回帰ガード + MED 群を修正

### iter1 CRITICAL 3 件 (必須修正)

1. **TUI が bash 3.2 (macOS 標準) で非動作**: `read -t 0.01` が `invalid timeout specification` + stty raw mode 不在で矢印キーが全て QUIT に化ける (code-reviewer / qa-expert)
2. **smoke Case 6 env passing bug**: `HC_..=1 printf | bash` で env が printf にしか効かず bash に伝わらない偽陽性 (test-automator / code-reviewer / qa-expert / pr-test-analyzer / tdd-guide の 5 者一致)
3. **`required_env` metadata の CSV `|` 破壊**: description 内 `(NAME|severity|purpose 形式)` の `|` が field 境界を破壊し description 途中切れ + effect に断片 (pr-test-analyzer)

### iter1 HIGH 主要 (必須修正)

stty raw mode 設定/復元 + trap / 新値入力時 canonical 復帰 / TUI category グルーピング欠如 (draft §3.3 設計乖離) / effect panel が Enter 後消失 / 非 TTY fallback UX 断絶 / [y/N]=N rollback 未検証 / 空 yml --list 未検証 / Case 5/6 symbol grep 依存で振る舞い未検証 / Case 7 tautology (動的抽出 regression 不検出) / TUI 本体自動テスト皆無 / Case 1 assertion 弱さ (非空のみ) / key 数双方向検証欠如 / 73→74 文書不整合 (docs 側で修正済)

ui-designer 追加理由: 矢印キー TUI の UX (ハイライト / effect panel レイアウト / 操作性) を専門観点でレビュー。

## §9 関連

- 前提 task: task-46 (config-yml Phase 3、hc-config.sh 新設)
- 設計調査: subagent aef203d58008a374f (confidence 0.85、74 key / inline comment 47% / 既存 raw terminal 0 件)
- UI 方針確定: AskUserQuestion 2026-05-27 (矢印キー TUI + 対話/--list 両方)
- 関連 memory: [[python3-pyyaml-detection-alias-trap]] (hc-config.sh の python 検出と同じ subprocess context 留意)

## §10 着手前 user 承認

**✅ 承認済 (2026-05-27、user「問題ありません。」)** — 確認 3 点すべて OK:
1. **TUI scope**: 矢印キー TUI を本 task に統合 (TUI 描画は手動検証、自動 smoke は非 TTY fallback + metadata 中心) — 承認
2. **metadata 工数**: 74 key 全てに「説明 + 変更効果」定義 (inline comment 35 + hardcode 38) — 承認
3. **--list 既定列変更**: `--list` 既定を説明列に置換 + `--list --show-default` で従来列復活 — 承認

`/new-task 48 hc-config-interactive-tui` で task 化済、実装着手。
