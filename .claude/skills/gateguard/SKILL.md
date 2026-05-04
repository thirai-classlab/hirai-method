---
name: gateguard
description: Fact-forcing PreToolUse gate that blocks Edit/Write/destructive Bash on first encounter and demands concrete evidence (importers, public APIs, data schema, verbatim user instruction) before allowing retry. Replicated from ECC. Measured +2.25 quality points vs ungated.
origin: ECC
---

# GateGuard — Fact-Forcing Gate

ECC の事実検証層の中核。Edit / Write / 破壊的 Bash を**初回遭遇時にブロック**し、具体的な事実調査を要求してから許可する PreToolUse hook。

> 哲学: **self-evaluation（"are you sure?"）では達成できない awareness を、調査自体が生む**。
> A/B 実測で **+2.25 / 10 ポイント** の品質改善（ungated 6.75 → gated 9.0）。

## When to Activate

- Edit / Write / 破壊的 Bash を伴うすべての作業
- 特に複数ファイルへの影響が想定される変更
- DB マイグレーション・データ削除・force push 等の不可逆操作
- 信頼度の低い AI セッションでの安全網

## What Gets Gated

| Gate | 発火タイミング | 要求する事実 |
|---|---|---|
| **Edit / MultiEdit** | セッション中 ファイル F の **初回 Edit** | ① F を import/require している全ファイル（Grep）<br>② 影響を受ける public function/class<br>③ データ構造（フィールド名・date 形式、値は redact）<br>④ user 指示の **逐語引用** |
| **Write**（新規） | セッション中 ファイル F の **初回 Write** | ① どのファイル/行が呼ぶか<br>② Glob で重複用途のファイルが無いことの確認<br>③ データ構造<br>④ user 指示の逐語引用 |
| **Destructive Bash** | `rm -rf` / `git reset --hard` / `git push --force` / `git branch -D` / `drop table` / `truncate` 等 | ① 影響ファイル/データ全列挙<br>② 1 行 rollback 手順<br>③ user 指示の逐語引用 |

## 3 段階ゲート

```
1. ❌ DENY    — block で具体的な事実要求を提示
2. 🔍 INVESTIGATE — agent が Grep/Read/Glob で事実収集
3. ✅ ALLOW   — 同ファイル/同コマンドの retry は通る（state file で記録）
```

## State Tracking

`.claude/.gateguard-state/<file-hash>.cleared` を作成して再発火を抑止する。
セッション間で永続するため、リセットは `/gate-clear` で行う。

ファイルパスを SHA-256 12文字 hash 化することで、長いパスでもファイル名衝突を回避。

## Bypass Mechanism

| 方法 | 用途 |
|---|---|
| `ECC_GATEGUARD=off` env var | セッション全体で無効化 |
| `/gate-bypass <file>` | 特定ファイルのみ pre-clear（事実収集済みと申告） |
| `/gate-clear` / `/gate-clear all` | 状態をリセット |
| `.gateguard.yml` の `ignore_paths` | 設定ファイル等を恒久除外 |

## Subagent Pass-through

サブエージェント（Agent tool 経由）実行中は GateGuard は通過する。理由:
- サブエージェントは目的特化で動く
- メインエージェントが Agent 起動時点で「この調査を委譲」と意図している
- 二重ゲートで動作不能になるのを防ぐ

検出方法: `delegation-guard.sh` と同じ多段検出（CLAUDE_HARNESS_ROLE / agent_type フィールド / `.claude/.agent-markers/*.lock`）。

## Effectiveness（A/B 実測）

| タスク | Gated | Ungated | 差 |
|---|---:|---:|---:|
| Analytics module | 8.0 | 6.5 | +1.5 |
| Webhook validator | 10.0 | 7.0 | +3.0 |
| **平均** | **9.0** | **6.75** | **+2.25** |

## Files

- `hooks/gateguard.sh`（このスキル外、`.claude/hooks/` に配置）
- `.gateguard.yml`（このディレクトリ） — gate 対象 / 除外パス設定

## Slash Commands

- `/gate-status` — 現在の cleared 状態と pending を一覧
- `/gate-clear [file|all]` — state リセット
- `/gate-bypass <file>` — 1 ファイル分だけ pre-clear

## Integration

| 層 | 関係 |
|---|---|
| **L1** Eval Harness | gate を抜けた変更を最終検証 |
| **L4** Continuous Learning | gate が要求した「事実型」を instinct DB に蓄積 |
| **L5** Introspection | gate 発火履歴を debug 入力として使う |

## Anti-Patterns

- ❌ `ECC_GATEGUARD=off` を常用する（gate の意義を失う）
- ❌ user 指示の逐語引用を捏造する
- ❌ 1 ファイルに複数の独立変更を詰め込む（gate が 1 度しか発火せず、後続変更が無検証になる）

## Related

- ECC 元実装: `affaan-m/everything-claude-code/skills/gateguard/`
- skill: `.claude/skills/verification-loop/SKILL.md`（事後検証側のペア）
- rule: `.claude/rules/self-improvement.md`（事実性レイヤーの位置づけ）
