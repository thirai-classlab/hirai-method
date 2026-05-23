# Task #26: Delegation Code Enforcement — `.claude/hooks/` `.claude/skills/` `.claude/scripts/` の直接 Edit を hook 強制 + 規範 DRY 化

> Status: **draft (要承認)** | **🔲 未着手**
> 起案: 2026-05-23
> 関連: 規範違反 commit `6ed9337` `6561475` `17c493e` (本 session メイン直接編集)
> 設計起源: [delegation-code-enforcement.md](../draft/delegation-code-enforcement.md)

## 背景・目的

2026-05-23 user 明示指摘「なぜ基本原則に従ってサブエージェントに移譲しないのですか?」を契機に、規範と機械強制の乖離が判明。

`development-process.md` で「コード実装は subagent 委譲」と規範化されているが、`delegation-guard.sh` の `protected_paths` は src/ tests/ scripts/ のみで `.claude/hooks/` 等のコード実装領域を block していない。結果、メインが `.claude/hooks/*.sh` を直接編集できてしまい、本 session で 9 件の規範違反 (3 commits) が発生した。

加えて、規範文書 4 file (`development-process.md` `task-management.md` `workflow.md` `modes.md`) で「サブエージェント委譲」「メイン専任」「設計→承認」が重複記載され、context 複雑化 + 認識落ちを誘発している。

本 task で hook 強制 + 規範 DRY 化を実装し、根本解決する。

## 仕様 (要決定 → 決定済)

### Q1: 強制 hook の実装方針

→ **C ハイブリッド** 採用: `delegation-guard.sh` を拡張 (新 hook 分離ではなく)。harness-config.yml に `protected_paths_code` + `code_file_extensions` 新キー導入、config 化で SSoT 整合性 + 精密判定。

### Q2: 規範 DRY 化の集約先

→ 各規範ごとに SSoT 1 file 決定: 委譲は development-process.md / メイン専任 + 設計→承認 は task-management.md / Loop モード は modes.md。他 file は 1 行 link で参照。

### Q3: bypass 機構

→ `ECC_ALLOW_MAIN_CODE_EDIT=1` (1 セッション、bypass.log 記録)。緊急時の hot-fix 用、honor system で根拠を CLAUDE.md or docs/tasks/ に記録。

## 設計

詳細は [delegation-code-enforcement.md](../draft/delegation-code-enforcement.md) §3 参照。

### Wave 構成

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| W1 | harness-config.yml に `protected_paths_code` + `code_file_extensions` 追加 | 0.2 |
| W2 | delegation-guard.sh 拡張 (Edit/Write 時の code 配下 + 拡張子 判定で block) | 0.5 |
| W3 | delegation-guard-code-smoke.sh 新設 (5-7 ケース) | 0.5 |
| W4 | 規範 4 file の重複セクション統合 (DRY 化) | 0.7 |
| W5 | CLAUDE.md / development-process.md に明示 + Critical Lessons 1 件追加 | 0.3 |
| W6 | 3 リポに install.sh --update 反映 | 0.2 |

合計 2.4 session。

## TDD 戦略

### RED

- `.claude/tests/delegation-guard-code-smoke.sh` 新設、5-7 ケース:
  - メインで `.claude/hooks/foo.sh` Write → BLOCK 期待
  - subagent で同 Write → PASS 期待
  - メインで `.claude/rules/foo.md` Write → PASS 期待
  - メインで `.claude/harness-config.yml` Edit → PASS 期待
  - メインで `.claude/mode.yml` Edit → PASS 期待
  - bypass env でメイン Write → PASS + bypass.log 記録
  - メインで `.claude/skills/foo/script.py` Write → BLOCK 期待

### GREEN

- W1 + W2 を subagent 委譲で実装 (**本 task 自身が dogfooding**: 委譲漏れ防止の hook を委譲で実装する)
- W3 smoke を subagent 経由で生成

### REFACTOR

- W4 規範 DRY 化を subagent 委譲、各統合先 file の構造を整理

## 派生 task / 次アクション候補

- 本 task 完了後、過去の規範違反 (本 session の 3 commits) が今後発生しないことを 1 週間運用で確認
- DRY 化で削除する重複セクションが他文書から参照されていれば link 修正

## 完了条件

- [ ] メイン直接で `.claude/hooks/foo.sh` Write が BLOCK
- [ ] subagent 経由で同 Write が PASS
- [ ] `.claude/rules/*.md` `.claude/harness-config.yml` 等は引き続きメイン可
- [ ] 規範 4 file の重複が SSoT 1 箇所に集約
- [ ] CLAUDE.md Critical Lessons に本 session 違反事例 1 件追加
- [ ] 既存 smoke 全件 regression 0
- [ ] 3 リポ (recall_poc / taskManageSystem / classlab-weekly-news) に反映
