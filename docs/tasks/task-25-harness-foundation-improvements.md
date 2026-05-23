# Task #25: Harness Foundation Improvements — performance / doc / refactor + drift 検出 のクラスタ

> Status: **draft (要承認)** | **🔲 未着手**
> 起案: 2026-05-23
> 関連: #22 (hook-reliability-uplift、本 task と独立並行可)
> 設計起源: [harness-foundation-improvements.md](../draft/harness-foundation-improvements.md)

## 背景・目的

2026-05-23 の網羅分析で MED 級 10 件の改善案件が判明。個別 task 化すると粒度が小さすぎるため、性質別に 1 epic にまとめる:

- Performance: P-2 (mermaid local install) / P-3 (SessionStart 並列化) / P-4 (observe sampling)
- Documentation: D-3 (CLAUDE.md placeholder) / Doc-2 (README rewrite) / Doc-3 (3 リポ diff レポート)
- Refactor & Drift: D-2 (大型 hook 分割) / D-1 (未着手 draft cleanup) / C-10 (settings.local drift) / C-9 (project_id fallback)

## 仕様 (要決定 → 決定済)

### Q1: 構造化方針

→ **C ハイブリッド** (性質別 3 サブ epic)。Sub-epic 単位で Wave 化、各 Wave 完了で個別 commit。

### Q2: observe.sh sampling は実装するか

→ **本 task では計測のみ、実装は別 task**。L4 学習の生データ source なので慎重判断。

### Q3: 大型 hook 分割の対象

→ improvement-proposal.sh (491 LOC) + delegation-guard.sh (400 LOC) + confidence-gate.sh (356 LOC) の 3 件。各 < 100 LOC の orchestrator + lib/*.sh に分割。

## 設計

詳細は [harness-foundation-improvements.md](../draft/harness-foundation-improvements.md) §3 参照。

### Wave 構成 (3 サブ epic)

#### Sub-epic A: Performance (1.0)
| Wave | 内容 | 工数 |
|:---:|:---|---:|
| A1 | mermaid local install 推奨 | 0.2 |
| A2 | SessionStart 並列化 | 0.5 |
| A3 | observe sampling 計測 (実装は別 task) | 0.3 |

#### Sub-epic B: Documentation (1.2)
| Wave | 内容 | 工数 |
|:---:|:---|---:|
| B1 | CLAUDE.md placeholder 削除 + 実 Lessons 化 | 0.2 |
| B2 | README install セクション rewrite (install.sh ベース) | 0.3 |
| B3 | `/harness-audit --compare <other-repo>` 新設 | 0.7 |

#### Sub-epic C: Refactor + Drift (2.1)
| Wave | 内容 | 工数 |
|:---:|:---|---:|
| C1 | 大型 3 hooks の lib 分割 | 1.2 |
| C2 | 未着手 draft 90 日超 list 機能 | 0.3 |
| C3 | settings.local.json drift check | 0.3 |
| C4 | observe.sh project_id fallback を `unknown-cwd-<hash>` に変更 | 0.3 |

合計 4.3 session。

## TDD 戦略

### RED

- 各 Wave 毎に対応 smoke (A2 並列化前後の SessionStart 時間 / B3 compare 出力 / C1 分割後の hook 動作 / C3 drift 検出 / C4 unknown-cwd 集計)

### GREEN

- behavior-preserving 必須、既存 smoke 全件 regression 0 確認

### REFACTOR

- C1 で抽出した lib/*.sh の共通化検討 (proposal/aggregate ↔ harness-audit の集計など)

## 派生 task / 次アクション候補

- A3 (observe sampling 計測) の結果次第で別 task (本実装)
- C1 (大型 hook 分割) の review 結果次第で第 2 ラウンド分割 (180 LOC 超の中堅 hook 対象)

## 完了条件

- [ ] check-md-mermaid.sh が local install で動作、README 案内あり
- [ ] SessionStart 時間 28s → 5-8s 短縮 (実測)
- [ ] CLAUDE.md placeholder 0 件
- [ ] README install.sh ベース
- [ ] `/harness-audit --compare` で 4 リポ diff
- [ ] 大型 3 hooks 各 < 100 LOC
- [ ] `/harness-audit` に未着手 draft 90 日超 list + drift check 表示
- [ ] observe.sh project_id fallback が `unknown-cwd-<hash>`
