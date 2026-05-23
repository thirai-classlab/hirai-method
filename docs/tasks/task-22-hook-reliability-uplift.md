# Task #22: Hook Reliability Uplift — fail policy / jq guard / smoke / observe rotation

> Status: **draft (要承認)** | **🔲 未着手**
> 起案: 2026-05-23
> 関連: CLAUDE.md Critical Operational Lessons HIGH (set -e leak / 並列 subagent git 競合)
> 設計起源: [hook-reliability-uplift.md](../draft/hook-reliability-uplift.md)

## 背景・目的

2026-05-23 の網羅分析で 26 hooks に系統的な信頼性 / 性能課題が判明:
- 8 hooks が file-top `set -euo pipefail` で SIGPIPE → exit 141 サイレント死リスク
- 複数 hook が jq 使用しているのに guard なしで crash 可能
- smoke test 14 件 / 26 hooks = 50% coverage、主要 guard が test 不在
- observe.jsonl 17 MB 線形成長、rotation 不在
- improvement-proposal.sh 491 LOC が毎 SessionStart で fullscan

CLAUDE.md Critical Lessons の教訓 (set -e leak) を機械強制レベルに昇格し、運用品質を測定可能にする。

## 仕様 (要決定 → 決定済)

### Q1: 修正方針

→ **C ハイブリッド** 採用 (系統別 4 Wave、各 Wave は独立 rollback 可能)。

### Q2: set -e 撤去か subshell 関数化か

→ **set -uo pipefail (errexit 外す)** を default。複雑な処理を持つ hook (workflow-guard 等) は subshell 関数化 `do_work() ( set -euo pipefail; ... )` を選択肢として残す。

### Q3: observe.jsonl rotation の閾値

→ **30 日**。月次 archive `observations-YYYY-MM.jsonl.gz` に古い entry を移動。L4 学習は archive も走査可能に。

## 設計

詳細は [hook-reliability-uplift.md](../draft/hook-reliability-uplift.md) §3 参照。

### Wave 構成

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| W1 | 8 hooks の set policy 統一 | 0.5 |
| W2 | jq guard 追加 | 0.5 |
| W3 | 主要 guard 5 件 smoke test 追加 | 1.5 |
| W4 | observe.jsonl rotation 機構 | 0.7 |
| W5 | improvement-proposal cache | 0.3 |

合計 3.5 session。

## TDD 戦略

### RED

- `.claude/tests/set-policy-smoke.sh` — 全 hook を grep して file-top `set -euo pipefail` 不在を検証
- `.claude/tests/jq-guard-smoke.sh` — jq 使用 hook 全件の guard 存在検証
- `.claude/tests/gateguard-smoke.sh` `task-rule-guard-smoke.sh` `confidence-gate-smoke.sh` `autonomous-action-guard-smoke.sh` `draft-flow-guard-smoke.sh` (各 5-7 ケース)
- `.claude/tests/observe-rotate-smoke.sh` — rotation 動作検証

### GREEN

- 各 hook 修正 + 新 smoke 追加で全 PASS

### REFACTOR

- improvement-proposal.sh の集計処理を lib/proposal/*.sh に分割 (task #25 と合流可能)

## 派生 task / 次アクション候補

- task #25 (harness-foundation) の Sub-epic C (Refactor) と一部重複、合流実装で工数削減
- observe.jsonl rotation の archive 削除 policy は別 task (data retention 観点)

## 完了条件

- [ ] `set -euo pipefail` を file-top で使う hook が 0 件
- [ ] jq 使用 hook 全件 jq guard あり
- [ ] 主要 guard 5 件の smoke test 追加 (各 5-7 ケース PASS)
- [ ] observe-rotate.sh 動作確認 + サイズ削減実測
- [ ] improvement-proposal cache hit 率 > 80%
- [ ] 既存 14 smoke 全件 regression 0
