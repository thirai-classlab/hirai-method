# Portability — 別リポへの移植手順

> **TL;DR**: `.claude/harness-config.yml` 1 枚を編集すれば、3 つの guard hook + audit script の挙動が連動変化する。**ハードコード編集は不要**。

## アーキテクチャ

```
.claude/harness-config.yml   ← Single Source of Truth (人間が編集する唯一の設定)
        │
        ▼
.claude/hooks/lib/config-loader.sh   ← 純 bash YAML パーサ (外部依存ゼロ)
        │ 参照する HC_* 変数を export
        ▼
┌────────────────────────────────────┬──────────────────────────────────┐
│ guard hooks                        │ utility scripts                  │
├────────────────────────────────────┼──────────────────────────────────┤
│ delegation-guard.sh                │ scripts/init-tasks.sh            │
│ gateguard.sh                       │ scripts/harness-audit.py (Python │
│ task-rule-guard.sh                 │   側に独立した同等パーサを実装) │
│ failure-loop-detect.sh             │                                  │
│ agent-marker-set.sh                │                                  │
│ agent-marker-clear.sh              │                                  │
│ notify.sh / stop.sh                │                                  │
│ init-tasks-on-start.sh             │                                  │
└────────────────────────────────────┴──────────────────────────────────┘
```

## 設定キー一覧

`.claude/harness-config.yml` で定義可能なキー:

| キー | 既定値 | 用途 |
|---|---|---|
| `protected_paths` | `[src, tests, scripts]` | delegation-guard が「メインエージェント直接操作禁止」とみなすパス |
| `task_dir` | `docs/tasks` | task-rule-guard / delegation-guard / init-tasks の判定対象 |
| `draft_dir` | `docs/draft` | 同上 |
| `bash_whitelist_path` | `.claude/bash-whitelist.txt` | delegation-guard が読む allow-list ファイル |
| `gateguard_state_dir` | `.claude/.gateguard-state` | GateGuard cleared marker の保存先 |
| `taskguard_state_dir` | `.claude/.taskguard-state` | TaskGuard bypass marker の保存先 |
| `agent_marker_dir` | `.claude/.agent-markers` | サブエージェント実行中マーカー |
| `failure_window_dir` | `.claude/.failure-window` | failure-loop ウィンドウログ |
| `homunculus_root` | `~/.claude/homunculus` | continuous-learning v2.1 観察ログ root（tilde 展開対応） |
| `notify_sound` | `/System/Library/Sounds/Hero.aiff` | macOS 通知音 |
| `stop_sound` | `/System/Library/Sounds/Glass.aiff` | macOS セッション終了音 |

## 移植チェックリスト

新規リポに `.claude/` をコピーした後、以下を順に確認:

1. **保護パス**を対象リポのプロダクションコード配置に合わせる
   ```yaml
   # 例: Next.js App Router プロジェクト
   protected_paths: [app, lib, components, scripts]
   ```

2. **タスク管理ディレクトリ**を変える場合のみ編集
   ```yaml
   task_dir: app/tasks      # docs/tasks 以外を使うとき
   draft_dir: app/draft
   ```

3. **bash-whitelist** の置き場所を変える場合
   ```yaml
   bash_whitelist_path: tools/bash-whitelist.txt
   ```

4. **homunculus_root**（個人別観察ストレージ）はマシン共通でよい場合はそのまま

5. **通知音源**は非 macOS 環境では無視されるためそのままでよい

## パーサ仕様

`.claude/hooks/lib/config-loader.sh` は YAML フルスペックではなく**意図的に薄いサブセット**:

| サポート | 例 |
|---|---|
| ✅ フラット scalar | `key: value` / `key: "value"` |
| ✅ インライン配列 | `key: [a, b, c]` |
| ✅ 行頭コメント | `# 説明` |
| ✅ tilde 展開 | `~/.claude/homunculus` → `/Users/.../...` |
| ❌ ネスト | `parent:\n  child: value` |
| ❌ 複数行値 | `key: \|` / `key: >` |
| ❌ アンカー | `&anchor` / `*ref` |
| ❌ 行末コメント | `key: value # コメント` |

理由: bash 純実装で `yq`/`python`/`jq` 依存ゼロ。CI コンテナでも追加 install 不要。

## fail-open 設計

- `harness-config.yml` 不在 → stderr に WARN を 1 行出して、`config-loader.sh` 内のハードコード既定値で続行
- 個別キー欠如 → 既定値 fallback（hook が動作不能にならない）
- 無効な行 1 つ → その行のみスキップ、他のキーは正常に load

これにより、設定不備でセッションが完全停止することを防ぐ。

## 動作確認

設定を変更したら、以下のコマンドで実際に block 挙動が変わることを確認できる:

```bash
# config-loader が値を読めているか確認
bash -c 'source .claude/hooks/lib/config-loader.sh && echo "PROTECTED=$HC_PROTECTED_DISPLAY"'

# delegation-guard が新しい protected_paths を反映しているか確認
echo '{"tool_input":{"file_path":"/some/repo/<your-protected-path>/foo.ts"}}' \
  | bash .claude/hooks/delegation-guard.sh Edit
# → {"decision":"block",...} が返れば OK
```

## 設計上の注意

- **`.claude/rules/development-process.md`** の `paths:` frontmatter と本文中の "src/ tests/ scripts/" は **人間向けドキュメント**。hook の挙動には影響しないが、ルールテキストが現実と乖離するため別途編集を推奨
- **`.claude/skills/continuous-learning-v2/hooks/observe.sh`** は ECC 由来の独立スキルで `HOMUNCULUS_DIR` 環境変数のみを参照する（harness-config と一致させたい場合は環境変数で渡す）
- `.gitignore` で state dir 群（`.gateguard-state/` `.taskguard-state/` 等）を除外済み — `harness-config.yml` で配置を変えた場合は `.gitignore` も更新する


## Env override（プロジェクト切替 — 全キー対応）

`harness-config.yml` の全キーは `HC_<UPPER_SNAKE>` 形式の環境変数で上書きできる。
`config-loader.sh` が `env > YAML > defaults` の優先順で解決する。

これにより、**yaml を編集せずにプロジェクトごとに挙動を切り替えられる**。

### 上書き対象キー

| YAML キー | 環境変数 | 既定値 |
|---|---|---|
| `task_dir` | `HC_TASK_DIR` | `docs/tasks` |
| `draft_dir` | `HC_DRAFT_DIR` | `docs/draft` |
| `protected_paths` | `HC_PROTECTED_PATHS` | `src tests scripts` (改行区切り) |
| `bash_whitelist_path` | `HC_BASH_WHITELIST_PATH` | `.claude/bash-whitelist.txt` |
| `gateguard_state_dir` | `HC_GATEGUARD_STATE_DIR` | `.claude/.gateguard-state` |
| `taskguard_state_dir` | `HC_TASKGUARD_STATE_DIR` | `.claude/.taskguard-state` |
| `agent_marker_dir` | `HC_AGENT_MARKER_DIR` | `.claude/.agent-markers` |
| `failure_window_dir` | `HC_FAILURE_WINDOW_DIR` | `.claude/.failure-window` |
| `homunculus_root` | `HC_HOMUNCULUS_ROOT` | `~/.claude/homunculus` |
| `notify_sound` | `HC_NOTIFY_SOUND` | `/System/Library/Sounds/Hero.aiff` |
| `stop_sound` | `HC_STOP_SOUND` | `/System/Library/Sounds/Glass.aiff` |
| `confidence_threshold` | `HC_CONFIDENCE_THRESHOLD` | `0.6` |
| `confidence_required` | `HC_CONFIDENCE_REQUIRED` | `true` |
| `confidence_state_dir` | `HC_CONFIDENCE_STATE_DIR` | `.claude/.confidence-gate-state` |

### 設定例

#### shell rc (`~/.zshrc` / `~/.bashrc`)

```bash
# このマシンで開く全リポ共通の設定
export HC_HOMUNCULUS_ROOT=~/work/.homunculus
export HC_NOTIFY_SOUND=/System/Library/Sounds/Tink.aiff
```

#### `.env` + direnv (`.envrc`)

プロジェクト固有の env を `direnv allow` で自動読込する想定:

```bash
# .envrc (プロジェクトルート)
export HC_TASK_DIR=docs/tickets
export HC_DRAFT_DIR=docs/proposals
export HC_PROTECTED_PATHS=$'app\nlib\nmiddleware.ts'    # 改行区切り
```

#### 一時切替 (1 セッション)

```bash
# confidence-gate を 1 セッション分だけ disable
HC_CONFIDENCE_REQUIRED=false claude
```

### 配列値 (`HC_PROTECTED_PATHS`) の渡し方

YAML 側は `protected_paths: [a, b, c]` 形式だが、env 経由では bash の
`$'a\nb\nc'` リテラル (改行区切り) で渡す:

```bash
export HC_PROTECTED_PATHS=$'app\nlib\nscripts'
# 別解 (printf 経由): export HC_PROTECTED_PATHS=$(printf 'app\nlib\nscripts')
```

派生値 (`HC_PROTECTED_DISPLAY` / `HC_PROTECTED_GLOB_FILE` / `HC_PROTECTED_LEAK_REGEX`)
は env override 後に再生成されるため、env で渡しただけで全 guard hook が
新しい protected_paths を反映する。

### tilde 展開

env 経由で渡された値も `~` / `~/foo` は `$HOME` に展開される。
yaml と同じ仕様:

```bash
export HC_HOMUNCULUS_ROOT=~/foo    # $HOME/foo に展開される
```

### 動作確認

```bash
# env override が効いているか確認
HC_TASK_DIR=docs/foo bash -c '
  source .claude/hooks/lib/config-loader.sh
  echo "TASK_DIR=$HC_TASK_DIR"        # → docs/foo
'

# 派生値も再生成されているか
HC_PROTECTED_PATHS=$'app\nlib' bash -c '
  source .claude/hooks/lib/config-loader.sh
  echo "DISPLAY=$HC_PROTECTED_DISPLAY"   # → app/ lib/
  echo "GLOB=$HC_PROTECTED_GLOB_FILE"    # → */app/*|*/lib/*
'
```

### 設計上の注意

- env 値が **空文字列** で export されている場合 (`export HC_FOO=""`) は
  「空で上書きしたい」意図とみなし YAML より優先される。defaults に
  戻したいときは `unset HC_FOO` する。
- env override の対象キーは `config-loader.sh` 内の `_HC_KNOWN_KEYS`
  リストで定義されている。新規キーを追加した場合はリストにも追加すること
  (リスト未掲載のキーは YAML から動的に load されるが env override 不可)。
- bash 3.2 (macOS 標準) でも動作する。`declare -g` `${!var}` 等の
  bash 4+ 機能は使用していない。

## Env override（gate disable）

専用の env で個別 gate を一時 disable 可能（fail-open）:

| Env Var | 対象 | 用途 |
|---|---|---|
| `ECC_F1_OFF=1` | `gateguard.sh` (F1) | 事実材料強制 gate を skip |
| `ECC_F2_OFF=1` | `task-rule-guard.sh` (F2) | task naming / draft 一致 gate を skip |
| `ECC_F3_OFF=1` | `confidence-gate.sh` (F3) | subagent confidence 閾値 gate を skip |

主に SWE-bench grid evaluation で F1/F2 単独 / 組合せ効果を測定する目的（runner.py が `_combo_to_env()` で自動付与）。**本番運用では設定しないこと**。

セッション全体 OFF（既存）と並列に有効:

- 既存: `ECC_GATEGUARD=off` / `ECC_TASKGUARD=off` / `ECC_CONFIDENCE_GATE=off`
- 新規: `ECC_F1_OFF=1` / `ECC_F2_OFF=1` / `ECC_F3_OFF=1`

挙動: env set 時、hook 冒頭で `{"decision":"approve","reason":"F<n> ... disabled via ECC_F<n>_OFF"}` を返して即 exit 0。env 未設定なら従来ロジックに到達する（fail-open 設計）。

smoke test: `.claude/hooks/tests/run-tests.sh`

## 履歴

- 2026-05-04 初版（`feat/harness-improvement-2026-05-04`）。3 hook のハードコード `src/ tests/ scripts/` `docs/tasks/` `docs/draft/` `.claude/bash-whitelist.txt` `~/.claude/homunculus` を `harness-config.yml` に集約
