# SWE-bench Lite - claude-code-harness 接続

> **Phase C-1 (環境構築 + dry-run)**: SWE-bench Lite (Princeton NLP) を claude-code-harness の客観評価ベンチとして接続する第一歩。
> 起案: 2026-05-04 / Branch: `feat/harness-improvement-2026-05-04`

## 概要

[SWE-bench Lite](https://www.swebench.com/lite.html) は実在 OSS (Django, sympy, scikit-learn 等 12 リポ) の GitHub issue を解決するパッチを生成し、隠しテスト群を pass させるかで採点する 300 task の実タスクベンチ。OpenHands / SWE-agent / Aider が leaderboard 提出。

claude-code-harness は外部ベンチ未接続のため客観評価ができていなかった。本ディレクトリで:

1. SWE-bench Lite メタデータ取得 (HuggingFace dataset viewer API 経由・依存ゼロ)
2. Docker sandbox による task 隔離実行
3. Claude Code CLI (`-p` モード) を呼び出し patch 生成
4. patch 適用 + 公式テスト実行で採点
5. 結果を JSON で `results/` へ蓄積、`harness-audit.py --swe-bench` から参照可能

## ディレクトリ構成

```
swe-bench/
|-- README.md
|-- config.yml
|-- runner.py
|-- scoring.py
|-- docker/
|   |-- Dockerfile
|   `-- docker-compose.yml
|-- tasks/
|   |-- lite-300.jsonl       # 全 300 task メタデータ (fetch_tasks.py で取得)
|   |-- lite-50.json         # 50 task サブセット (dry-run / Phase C-2 用)
|   `-- fetch_tasks.py
`-- results/
    `-- dry-run-<date>.json
```

## Cost 見積 (dry-run / Phase C-2)

| Phase | task 数 | model | per task 上限 | 想定 cost | 想定時間 |
|---|---:|---|---:|---:|---:|
| C-1 dry-run | 5 | claude-sonnet-4-6 | $1.0 | <= $5 (cap) | ~25 min |
| C-2 本番 | 50 x F1/F2 4 組 = 200 | claude-sonnet-4-6 | $1.0 | $80-150 | 8-15 hr |
| C-2 上位 | 50 x claude-opus-4-7 | opus | $3.0 | +$150-250 | +5-8 hr |

cost cap は `config.yml` の `cost_cap_usd` で定義。超過時は task ループから break + 報告。

## 実行手順 (Phase C-1 dry-run)

```bash
cd .claude/skills/eval-harness/swe-bench

# 1. メタデータ取得 (依存ゼロ・標準 urllib のみ)
python3 tasks/fetch_tasks.py

# 2. Docker sandbox image build
docker build -t swe-bench-sandbox -f docker/Dockerfile .

# 3. dry-run (5 task)
ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY \
python3 runner.py --tasks tasks/lite-50.json --limit 5 \
  --output results/dry-run-$(date +%Y-%m-%d).json
```

## Phase C-1 vs C-2 スコープ

- **C-1 (本タスク)**: 環境構築 + 5 task dry-run のみ。コスト実測 -> C-2 規模見積を検証。
- **C-2 (user 承認後)**: 本番 50 task x F1/F2 on/off の 4 条件比較 = 200 task。harness の effective が定量化される。

## 重要事項

- **API key 取り扱い**: ハードコード厳禁。`ANTHROPIC_API_KEY` を環境変数で渡す。`runner.py` は env 経由でしか読まない。
- **Docker 隔離**: 各 task は独立 container で git clone + patch 適用 + test 実行。harness 本体への副作用ゼロ。
- **Cost 監視**: 各 task 終了時に `_track_cost()` で累計を出力、cap 超過で即 break。
- **公式 SWE-bench harness との差分**: Phase C-1 は公式 `swebench` package に依存しない簡易採点 (patch 適用成否 + FAIL_TO_PASS テスト pass 数)。Phase C-2 で公式 harness 統合を検討。

## 関連

- 上位 skill: [`../SKILL.md`](../SKILL.md) - Eval-Driven Development の基盤
- 本体 OSS: <https://github.com/princeton-nlp/SWE-bench>
- leaderboard: <https://www.swebench.com/lite.html>
