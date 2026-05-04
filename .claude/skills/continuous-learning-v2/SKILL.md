---
name: continuous-learning-v2
description: Instinct-based learning system that observes sessions via hooks, creates atomic instincts with confidence scoring, and evolves them into skills/commands/agents. v2.1 adds project-scoped instincts to prevent cross-project contamination. Replicated from ECC (Everything Claude Code).
origin: ECC
version: 2.1.0
---

# Continuous Learning v2.1 — Instinct-Based Architecture

ECC由来の自己改善層 **L4**。Claude Code セッションを Hook で 100% 確実に観察し、原子的な「instinct」を生成・スコアリング・進化させる。

## When to Activate

- Hook ベースの自動学習を立ち上げる
- 信頼度しきい値を調整する
- instinct ライブラリのレビュー・export/import
- instinct を skills/commands/agents に進化させる
- project-scoped と global の昇格管理

## Architecture

```
Session Activity
  │
  │ PreToolUse / PostToolUse hooks（100%確実）
  │ + プロジェクト検出（git remote / repo path）
  ▼
projects/<hash>/observations.jsonl
  │
  │ Background observer（Haiku, 5min間隔, ≥20件で起動）
  ▼
PATTERN DETECTION
  ├─ user corrections → instinct
  ├─ error resolutions → instinct
  └─ repeated workflows → instinct
  │
  ▼
projects/<hash>/instincts/personal/      ← project-scoped
~/.claude/homunculus/instincts/personal/ ← global
  │
  │ /evolve（クラスタ化）+ /promote（昇格）
  ▼
evolved/ → skills/, commands/, agents/
```

## File Layout

```
~/.claude/homunculus/
├── identity.json
├── projects.json                  # project hash → name/last_seen
├── observations.jsonl             # global fallback
├── instincts/
│   ├── personal/                  # global auto-learned
│   └── inherited/                 # global imported
├── evolved/
│   ├── agents/
│   ├── skills/
│   └── commands/
└── projects/
    └── <12char-hash>/
        ├── project.json
        ├── observations.jsonl
        ├── instincts/personal/
        ├── instincts/inherited/
        └── evolved/{skills,commands,agents}/
```

## Instinct Schema

```yaml
---
id: prefer-functional-style
trigger: "when writing new functions"
confidence: 0.7              # 0.3-0.9
domain: code-style           # code-style/testing/git/debugging/workflow/security
source: session-observation
scope: project               # project | global
project_id: a1b2c3d4e5f6
project_name: my-react-app
created_at: 2026-05-04T10:00:00Z
updated_at: 2026-05-04T11:00:00Z
evidence_count: 5
---

## Action
Use functional patterns over classes when appropriate.

## Evidence
- Observed 5 functional preferences
- User corrected class→functional on 2026-04-15
```

## Confidence Dynamics

| Score | Meaning | Behavior |
|---|---|---|
| 0.3 | Tentative | 提示するが強制せず |
| 0.5 | Moderate | 関連時のみ適用 |
| 0.7 | Strong | 自動適用承認 |
| 0.9 | Near-certain | コア行動 |

**Increase**: 同パターン再観察 / user 非否定 / 横断合意
**Decrease**: user 修正 / 長期未観察 / 矛盾観察

## Setup

### 1. Enable Observation Hooks

`.claude/settings.json` に以下を追加（既に統合済み）:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "bash .claude/skills/continuous-learning-v2/hooks/observe.sh",
        "timeout": 3
      }]
    }],
    "PostToolUse": [{
      "matcher": "*",
      "hooks": [{
        "type": "command",
        "command": "bash .claude/skills/continuous-learning-v2/hooks/observe.sh",
        "timeout": 3
      }]
    }]
  }
}
```

### 2. Initialize storage

初回 hook 実行時に自動作成される。手動なら:

```bash
mkdir -p ~/.claude/homunculus/{instincts/{personal,inherited},evolved/{agents,skills,commands},projects}
```

### 3. Use commands

```
/instinct-status     # project + global instincts 一覧
/projects            # 既知プロジェクトと instinct 数
/evolve              # クラスタ化 → skills/commands/agents 生成
/promote [id]        # project → global 昇格
/instinct-export     # JSON へ export
/instinct-import <file>
/learn               # 手動パターン抽出（v1 互換）
```

## Configuration

`config.json`:

```json
{
  "version": "2.1",
  "observer": {
    "enabled": false,
    "run_interval_minutes": 5,
    "min_observations_to_analyze": 20,
    "model": "claude-haiku-4-5-20251001"
  },
  "promotion": {
    "min_projects": 2,
    "min_avg_confidence": 0.8
  },
  "confidence": {
    "initial": 0.3,
    "increment_on_repeat": 0.1,
    "decrement_on_correction": 0.2,
    "decay_per_month_unseen": 0.1
  }
}
```

## Scope Decision

| パターン種別 | 推奨 scope | 例 |
|---|---|---|
| 言語/FW 規約 | project | "Use React hooks" |
| ファイル構造 | project | "Tests in __tests__/" |
| コードスタイル | project | "Functional preferred" |
| エラー処理戦略 | project | "Use Result type" |
| セキュリティ | global | "Validate user input" |
| 汎用ベストプラクティス | global | "Tests first" |
| ツール選択 | global | "Grep before Edit" |
| Git 慣習 | global | "Conventional commits" |

## Promotion (project → global)

**自動候補条件**:
- 同 instinct ID が **2+ プロジェクト**で観察
- 平均 confidence ≥ **0.8**

```bash
python3 .claude/skills/continuous-learning-v2/instinct-cli.py promote <id>
python3 .claude/skills/continuous-learning-v2/instinct-cli.py promote          # 全候補一括
python3 .claude/skills/continuous-learning-v2/instinct-cli.py promote --dry-run
```

## Privacy

- 観察記録は **完全ローカル**（送信なし）
- プロジェクト別に隔離（cross-project contamination なし）
- export 可能なのは **instinct のみ**（生観察ログは出ない）
- 昇格は手動承認、ユーザーが何を export するか完全制御

## Why Hooks vs Skills?

> v1 は skill 観察（50-80%確率発火）。v2 は hook 観察（100%確実）。

**結果**:
- すべての tool call が観察される
- パターン取りこぼしなし
- 学習が網羅的

## Files

- `hooks/observe.sh` — PreToolUse/PostToolUse hook（100%発火）
- `instinct-cli.py` — instinct 管理CLI（status/evolve/promote/etc）
- `config.json` — observer 設定

## Related Skills (5-Layer Self-Improvement)

| 層 | スキル | 役割 |
|---|---|---|
| L1 | `eval-harness` | 合否判定基盤（pass@k） |
| L2 | `continuous-agent-loop` | イテレーション改善（6 patterns） |
| L2+ | `gan-style-harness` | 品質特化（Planner/Gen/Eval） |
| **L4** | **`continuous-learning-v2`** | **本スキル — 経験蓄積** |
| L5 | `agent-introspection-debugging` | 失敗時自己診断 |

詳細: `.claude/rules/self-improvement.md`
