# Self-Improvement & Factuality Layers

このハーネスは ECC（Everything Claude Code）由来の **5 層自己改善 + 事実検証 2 層** を完全模倣している。

詳細な使用規約は [`.claude/rules/self-improvement.md`](../.claude/rules/self-improvement.md) を参照。

## 階層

| 層 | 名称 | 改善対象 | 観察粒度 | 永続化先 |
|---|---|---|---|---|
| L1 | Eval-Driven Dev | 1 機能の正しさ | コミット | `.claude/evals/` |
| L2 | Continuous Loop / GAN | 1 タスクの品質 | 反復 | `feedback-NNN.md` |
| L3 | Ralphinho RFC-DAG | プロジェクト構造 | 作業ユニット | jj worktree |
| **L4** | **Continuous Learning v2.1** | **エージェントの行動** | **ツール呼び出し** | `~/.claude/homunculus/` |
| L5 | Introspection Debugging | エージェント自身 | 失敗パターン | introspection report |
| **F1** | **GateGuard** | **Edit/Write/Bash の事実性** | **初回ファイル/コマンド** | `.claude/.gateguard-state/` |
| **F2** | **Verification Loop** | **PR 直前の品質** | **6 phases** | `/verify` レポート |
| **F3** | **Confidence Gate** | **サブエージェント完了時の自己評価** | **SubagentStop hook** | `.claude/.confidence-gate-state/` |

## L4 が「核心」である理由

- **Hook で 100% 確実に観察**（v1 の Stop hook + skill 観察は確率的）
- **Atomic Instinct + 信頼度 0.3-0.9** の最小単位で蓄積
- **Project-scoped（v2.1 新機能）** で React / Python / Go プロジェクト間の混線を防止
- **/promote** で複数プロジェクトに通底するパターンのみ global へ昇格
- **/evolve** で関連 instinct クラスタを skill / command / agent に進化

### 動作前提

`settings.json` の PreToolUse / PostToolUse に `observe.sh` が wired 済み（matcher `*`）。
すべての tool call が `~/.claude/homunculus/projects/<hash>/observations.jsonl` に蓄積される。

- `git remote` URL の SHA-256 12 文字 hash を project ID として使うため、**同じリポなら異マシンでも同 ID**
- git 検出失敗時は `~/.claude/homunculus/observations.jsonl`（global fallback）
- `jq` / `git` が無くても crash しない（fail-open 設計）
- timeout 3 秒、典型 ≤100ms

## スラッシュコマンド早見

```
/eval define <feature>     # L1 合否基準を先に書く
/eval check <feature>      # L1 評価実行

/gan-design <prompt>       # L2+ Planner（仕様生成）
/gan-build <spec>          # L2+ Generator/Evaluator ループ

/instinct-status           # L4 学習済み instinct 一覧
/projects                  # L4 既知プロジェクト
/learn                     # L4 ヒューリスティック分析（Haiku 不要）
/evolve                    # L4 クラスタ → skill/command/agent 候補
/promote [id]              # L4 project → global 昇格
/instinct-export [opts]    # L4 export
/instinct-import <file>    # L4 import

/agent-introspect          # L5 失敗時の 4 フェーズ自己診断
```

## プライバシー

- 観察ログは送信されない（完全ローカル）
- export 可能なのは instinct のみ（生コード・会話は出ない）
- 何を export / promote するかはユーザーが完全制御
- v2.1 で project-scoped 化されているため、機微 pattern が他プロジェクトへ漏れない

---

## 事実検証レイヤー（F1 / F2）

### F1: GateGuard（事前ゲート）

PreToolUse hook（`.claude/hooks/gateguard.sh`）が以下を **初回遭遇時に BLOCK**:

| Gate | 対象 | 要求事実 |
|---|---|---|
| **Edit** | セッション中ファイル F の初回 Edit | importers / public API / data 構造 / user 逐語引用 |
| **Write** | セッション中ファイル F の初回 Write | callers / 重複確認(Glob) / data 構造 / user 逐語引用 |
| **Destructive Bash** | `rm -rf` / `git reset --hard` / `git push --force` / `git branch -D` / `drop table` / `truncate` / `supabase db reset` | 影響ファイル列挙 / rollback 1 行 / user 逐語引用 |

**動作**:
1. ❌ DENY — block で具体的事実要求を提示
2. 🔍 INVESTIGATE — agent が Grep / Read / Glob で調査
3. ✅ ALLOW — 同ファイル / 同コマンドの retry は state file（`.claude/.gateguard-state/`）で通過

**サブエージェント中は通過**（delegation-guard と同じ多段検出）。

**Bypass**:
- `ECC_GATEGUARD=off`（セッション全体）
- `/gate-bypass <file>`（1 ファイル分）
- `/gate-clear [file|all]`（リセット）

**効果**（ECC 実測）: ungated 6.75 → gated **9.0 / 10**（+2.25 ポイント）

### F2: Verification Loop（事後検証）

`/verify` で 6 phase 連続実行:

1. Build（`npm run build` / `pnpm build` / `cargo build`）
2. Type Check（`tsc --noEmit` / `pyright` / `mypy`）
3. Lint（`eslint` / `ruff` / `golangci-lint`）
4. Tests + Coverage（80% 目標）
5. Security（secret pattern / console.log 残留）
6. Diff Review（`git diff --stat`）

最終レポートで READY / NOT READY を判定。

### F3: Confidence Gate（事後ゲート — サブエージェント完了時）

SubagentStop hook (`.claude/hooks/confidence-gate.sh`) がサブエージェントの
完了 summary に `confidence: 0.X` を要求し、閾値（既定 0.6）未満で **block**。

| 観点 | 動作 |
|---|---|
| **対象** | Task tool で起動したサブエージェントの SubagentStop |
| **要求** | 最終 assistant text に `confidence: 0.X`（0.0〜1.0）を含めること |
| **閾値** | `confidence_threshold` （既定 0.6） |
| **未記載** | `confidence_required: true`（既定）なら block |
| **bypass** | `/gate-bypass confidence <reason>`（次回 1 回 PASS、bypass.log に記録） |
| **全 OFF** | `ECC_CONFIDENCE_GATE=off` または `HC_CONFIDENCE_REQUIRED=false` |
| **監査** | `/harness-audit` で累計 bypass 回数 + 直近 5 件 reason |

詳細: [`docs/CONFIDENCE-GATE.md`](CONFIDENCE-GATE.md)

### F1 / F2 / F3 早見

```
/gate-status                          # F1 cleared/pending 確認
/gate-clear [file|all]                # F1 リセット
/gate-bypass <file>                   # F1 pre-clear（事実調査済み申告）
/verify                               # F2 6 phase 事後検証
/gate-bypass confidence <reason>      # F3 次回 1 回 pass（bypass.log 記録）
```

### 試す

```bash
# L4 が観察したものを確認
python3 .claude/skills/continuous-learning-v2/instinct-cli.py status
python3 .claude/skills/continuous-learning-v2/instinct-cli.py projects
python3 .claude/skills/continuous-learning-v2/instinct-cli.py observe-analyze
```

---

## 観測と監査（W2 で追加）

### Failure-Loop Detection

`.claude/hooks/failure-loop-detect.sh` が PostToolUse(`*`) で同種エラー 3 連続を検出。
- `.claude/.failure-window/<session>.log` に記録
- 検出時は `additionalContext` で `/agent-introspect` を提案
- 成功時に window をリセット
- bypass: `ECC_FAILURE_LOOP=off`

### Harness Audit

`/harness-audit` でハーネス自身の健全性を実測値で出力。

```
/harness-audit                # 全カテゴリ
```

レポート内容:
- observations.jsonl 直近 100 件: tool 呼び出し / エラー率 / retry per tool
- `.claude/.gateguard-state/`: cleared file 数（=「初回事実調査を通過した」回数）
- `.claude/.taskguard-state/`: bypass 件数
- `.claude/.failure-window/`: 連続失敗ログ
- 各 hook の timeout 発生件数

「+2.25 ポイント」を**自リポ実測値**に置き換えるための入口。
