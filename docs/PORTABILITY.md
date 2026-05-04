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

## 履歴

- 2026-05-04 初版（`feat/harness-improvement-2026-05-04`）。3 hook のハードコード `src/ tests/ scripts/` `docs/tasks/` `docs/draft/` `.claude/bash-whitelist.txt` `~/.claude/homunculus` を `harness-config.yml` に集約
