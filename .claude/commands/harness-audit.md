---
description: ハーネス自身の健全性を実測値で出力（observations / GateGuard / TaskGuard / failure-window から完成率・リトライ率・ブロック頻度・active loop を集計）
---

# /harness-audit

`./claude-code-harness` の健全性レポートを実測値で出力する。「+2.25/10」のような外部引用値を**自リポ実測値**に置き換えるための入口。

## 何を出すか

- **観察ログ**（`~/.claude/homunculus/projects/<hash>/observations.jsonl`）から:
  - 直近 N 件の tool 呼び出し総数 / エラー率 / timeout 検出
  - tool 別 retry 率（top 10）
- **GateGuard state**（`.claude/.gateguard-state/`）:
  - cleared 件数を edit / write / bash に分類
- **TaskGuard bypass**（`.claude/.taskguard-state/`）:
  - slug 別 bypass 件数（記録漏れチェック）
- **Failure-loop window**（`.claude/.failure-window/`）:
  - session 別の連続失敗件数 / **active loop** 検出
- **Health バッジ**: 🟢 / 🟡 / 🔴

## 実行

```bash
python3 .claude/scripts/harness-audit.py
```

オプション:

- `--json` — JSON 出力（CI / 後段処理向け）
- `--window=N` — 観察ログの集計件数（default 100）
- `--compare PATH` — 他リポの `.claude/` と structural diff を取る（task-25 B3、複数指定可）
- `--compare-format {summary,detail,json}` — `--compare` の出力 format（default: `summary`）
- `--compare-include {hooks,rules,skills,commands,templates,settings,all}` — 比較対象 category 絞り込み（default: `all`、複数指定可）
- `--compare-source PATH` — `--compare` の source root（default: cwd）

## クロスリポ drift 検出 (`--compare`, task-25 B3)

複数リポ (hirai-method / recall_poc / classlab-weekly-news 等) で `.claude/` ハーネスが drift していないかを構造的に検出する。

### 比較指標

- **file presence diff**: 一方にあって他方にない file 一覧 (path 単位)
- **content diff**: 両方にある file の sha256 hash 比較、不一致なら「drift あり」mark + size delta / mtime delta 付き
- **clean**: 両方に存在 + hash 一致の file 一覧

### 無視 path (runtime-only)

`.claude/.workflow-state/<slug>.json` / `.claude/.gateguard-state/*.cleared` / `.claude/.taskguard-state/*` / `.claude/.failure-window/*` / `.claude/.confidence-gate-state/*` / `.claude/.session-help-shown` / `.claude/.compaction-state/` / `.claude/logs/` / `.DS_Store` は default で除外。ただし `SCHEMA.md` / `bypass.log.template` / `.gitignore` は track 対象として比較される。

### 実行例

```bash
# 単一リポ比較
python3 .claude/scripts/harness-audit.py --compare /Users/t.hirai/recall_poc

# 複数リポを並列比較
python3 .claude/scripts/harness-audit.py \
    --compare /Users/t.hirai/recall_poc \
    --compare /Users/t.hirai/classlab-weekly-news

# 全 file path を列挙 (大規模 drift 用)
python3 .claude/scripts/harness-audit.py --compare /path/to/other-repo --compare-format detail

# hooks/rules のみ比較
python3 .claude/scripts/harness-audit.py --compare /path/to/other-repo \
    --compare-include hooks --compare-include rules

# CI / 後段処理向け JSON
python3 .claude/scripts/harness-audit.py --compare /path/to/other-repo --compare-format json
```

### 出力例 (summary mode)

```
[harness-audit --compare]
Source: /Users/t.hirai/work/hirai-method/.claude (X files, Y KB)
Target: /Users/t.hirai/recall_poc/.claude (Z files, W KB)
Includes: all

## Missing in target (source only): N files
  - .claude/hooks/draft-flow-guard.sh
  - .claude/evals/system-reminder-attention.md
  ...

## Missing in source (target only): M files
  - .claude/<recall_poc specific>

## Content drift (same path, different hash): K files
  - .claude/rules/task-management.md (source: X B / target: Y B / size delta: +10B / mtime delta: 3d)
  ...

## Summary
  - install.sh --update sync 推奨 file 数: N (missing in target が新規追加対象)
  - 真の drift (両 repo で独立進化): K (要 manual review)
  - clean: P files (両 repo identical)
```

### 終了コード

- `0` — 比較成功 (drift 件数に関わらず)
- `2` — `--compare` 引数 path 不在 / source `.claude/` 不在 / argparse error

## メインエージェントの動作

1. `python3 .claude/scripts/harness-audit.py` を実行（whitelist 許可済 prefix）
2. 標準出力をそのままユーザーに返す
3. **active failure loop** が検出された場合は、続けて `/agent-introspect` の起動を提案
4. **TaskGuard bypass** が 0 でない場合は、bypass 根拠が `CLAUDE.md` / `docs/tasks/` に記録されているか確認するよう促す

## 出力例

```
# Harness Audit Report
_generated: 2026-05-04T16:30:00_

## 観察ログ (observations.jsonl)
- source: `~/.claude/homunculus/projects/abc123/observations.jsonl`
- window: 直近 100 件
- total events: 87
- errors: 12（error rate 13.8%）
- timeouts: 2

### tool 別 (top 10)
  - `Bash`: 42 calls / 5 errors (12%)
  - `Edit`: 18 calls / 3 errors (17%)
  - `Read`: 27 calls / 4 errors (15%)

## GateGuard state (F1)
- cleared: 7 files
  - edit: 4 / write: 2 / bash: 1

## TaskGuard bypass (タスク管理)
- cleared: 0 files

## Failure-loop window (W2.1)
- active loops: 0

## Health
- 🟡 moderate error rate
```

## Bypass / 注意

- 観察ログは `~/.claude/homunculus/projects/<hash>/` 配下。`git remote` 未設定の場合は global fallback を読む。
- スクリプトは標準ライブラリのみ（外部依存なし）。
- 集計は read-only。state を改変しない。
- 実測値が「+2.25/10」より高いか低いかを記録するには、`--json` を `tee` して時系列保存することを推奨:
  ```
  python3 .claude/scripts/harness-audit.py --json > ~/.claude/audit-history/$(date +%Y-%m-%d).json
  ```
