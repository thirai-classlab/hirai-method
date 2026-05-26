<!--
approved_at: 2026-05-26
retroactive: false
approved_by: user
-->

# CLAUDE.md 共通規範を `.claude/CommonRules.md` に切り出し + `@import` 構文採用

## §1 真因 (背景)

本 session task-40 + task-41 完遂後、採用 4 リポ (`classlab-weekly-news` / `develop/ClassLab/TEST` / `recall_poc` / `タスクマネジメント/taskManageSystem`) で `grep "loop-confirmation-detector" CLAUDE.md` = 0 hit を観測。本リポ commit `af410f2` で追加した CLAUDE.md L152 教訓が採用 repo に反映されていない。

### 真因 2 階層

1. **`install.sh --update` が CLAUDE.md を保護**: 各プロジェクト固有編集 (Tech Stack / Implementation Status 等) を保護するため上書き対象外。共通規範部分も同 file に混在しているため、規範補強が採用 repo に反映されない構造問題
2. **CLAUDE.md 内に共通規範 + project 固有規範が混在**: Development Policy / Autonomous Progression / Rules table / Design Constraints / Critical Operational Lessons (共通) + Tech Stack / User Context / Implementation Status (project 固有) が 1 file に同居

### user 質問起源

「Claude md に読ませる `.claude/CommonRules.md` を作成して claude.md にかならず CommonRules.md を参照するようにさせたとき、精度は変わりますか」(2026-05-26)
→ `@.claude/CommonRules.md` (Claude Code memory file import 構文) なら **精度同等 + 保守性向上** と回答、user 「着手」承認。

## §2 採用案比較

| 案 | 内容 | 評価 |
|---|---|---|
| A | 単純 link 参照 | AI 参照漏れで精度低下リスク |
| B | install.sh で CLAUDE.md merge logic 追加 | conflict リスク + 複雑化 |
| **C ハイブリッド** | `.claude/CommonRules.md` 切り出し + CLAUDE.md template `@import` 1 行 + install.sh は CommonRules.md 自動同期 | 精度劣化なし + 採用 4 リポ規範同期構造化 |

→ **C ハイブリッド** 採用。

## §3 採用案 (実装仕様)

### 3.1 切り出し対象 (CommonRules.md へ移動)

| section | 行範囲 | 性質 |
|---|---|---|
| Development Policy | L16-28 | 共通 |
| Autonomous Progression | L30-58 | 共通 |
| Rules table | L60-74 | 共通 |
| ハーネス組み込みスラッシュコマンド | L109-125 | 共通 |
| Design Constraints | L127-132 | 共通 |
| Critical Operational Lessons | L134-157 | 共通 |
| ハーネスドキュメント | L180-184 | 共通 |

### 3.2 残置対象 (CLAUDE.md 残し = project 固有)

| section | 行範囲 | 性質 |
|---|---|---|
| Overview / User Context / Tech Stack / Architecture / Implementation Status / Commands (dev/build/test) / Related Repos / Domain Knowledge / このテンプレートの使い方 | L6-14, L76-107, L159-178 | project 固有 |

### 3.3 CLAUDE.md template 冒頭 `@import` 追加

```markdown
# CLAUDE.md

> **共通規範**: 必ず `@.claude/CommonRules.md` を参照 (Claude Code が session 開始時に自動展開)。
> Development Policy / Autonomous Progression / Rules / Design Constraints / Critical Operational Lessons は CommonRules.md で集中管理。

@.claude/CommonRules.md
```

### 3.4 install.sh 修正 (subagent 調査結果反映)

調査結果 (subagent confidence 0.95):
- `--update` で `.claude/` 配下 rsync 対象 → `.claude/CommonRules.md` 自動 install 対象 (修正不要)
- CLAUDE.md は保護対象 (project 固有編集を維持)

→ install.sh は **修正不要**。新規 `.claude/CommonRules.md` を本リポに置けば自動同期。

### 3.5 採用 4 リポへの移行ガイド

採用 repo の CLAUDE.md には `@import` 1 行を user manual で追加が必要 (CLAUDE.md は保護対象、自動追加不可)。手順:

```bash
# 各 repo で:
cd <target_repo>
bash <hirai-method>/install.sh --update .   # CommonRules.md 自動 install

# CLAUDE.md L1 直後に手動追加:
# > **共通規範**: 必ず `@.claude/CommonRules.md` を参照
# > @.claude/CommonRules.md
```

## §4 TDD 戦略

### RED (smoke)

`.claude/tests/common-rules-import-smoke.sh` (7 case、iter2 拡張済):

- Case 1: CommonRules.md 存在 + 切り出し対象 7 section 全件 grep + 各 section sentinel keyword (14 keyword)
- Case 2: CLAUDE.md に `@.claude/CommonRules.md` が count==1 行存在 (重複検出)
- Case 3: CLAUDE.md に project 固有 section retain
- Case 4a: CLAUDE.md から共通規範 7 section 全件削除済 (7 keyword 全 grep)
- Case 4b: install.sh の rsync exclude pattern に CommonRules が含まれない (間接検証)
- Case 5: CLAUDE.md 行数 ≤ 120 (template として slim 維持)
- Case 6: CLAUDE.md の @import 行が L15 以内 (先頭近傍配置)

### GREEN

- `.claude/CommonRules.md` 新設
- `CLAUDE.md` slim 化 + `@import`

### REFACTOR

skip 想定 (機械的切り出し)。

## §5 Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | draft + task file + list.md row | 全 file 存在 |
| 2 | 🔲 | `.claude/CommonRules.md` 新設 | grep 7 section 全 hit |
| 3 | 🔲 | CLAUDE.md slim 化 + `@import` | grep project 固有 retain + `@import` 1 hit |
| 4 | 🔲 | smoke 新設 (4+ case) | smoke 全 PASS |
| 5 | 🔲 | (テスト設計レビュー) reviewer 3+ 並列、収束 CRITICAL+HIGH+MEDIUM=0 | iter 1+ 収束 |
| 6 | 🔲 | (テスト合格) smoke + grep 検証 | 検証全 PASS |
| 7 | 🔲 | (リファクタリング) 3 観点判定、skip 可 | skip 想定 |
| 8 | 🔲 | commit + push + PR create | PR URL 提示 |
| 9 | 🔲 | 4 リポ user manual install + CLAUDE.md `@import` 1 行追加案内 | install command 提示 |

## §6 DoD

- [ ] `.claude/CommonRules.md` 存在
- [ ] CLAUDE.md に `@.claude/CommonRules.md` 1 行追加
- [ ] CLAUDE.md slim 化 (約 185 行 → 約 60-80 行想定)
- [ ] smoke 4+ case PASS
- [ ] grep CommonRules.md 「Critical Operational Lessons」 1+ hit
- [ ] grep CLAUDE.md 「Tech Stack」 1+ hit
- [ ] reviewer 3+ 並列収束
- [ ] PR create + user merge 案内
- [ ] 4 リポ install + `@import` 追加案内

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル (新規) | `.claude/CommonRules.md` |
| ファイル (修正) | `CLAUDE.md` (slim 化 + `@import`) |
| ファイル (test) | `.claude/tests/common-rules-import-smoke.sh` |
| ファイル (task 管理) | `docs/tasks/list.md` / `docs/tasks/task-42-common-rules-extraction.md` |
| migration | なし |
| 環境変数 | なし |
| 互換性 | CLAUDE.md `@import` は Claude Code 標準機能。採用 4 リポは `@import` 1 行 user manual 追加が必要 |

## §8 レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| iter1 | qa-expert / tdd-guide / architect | 0 | 1 | 5 | 0 | 修正待ち |
| iter2 | — (smoke 拡張で自動修正) | 0 | 0 | 0 | 0 | 収束 → 承認待ち |

## §9 関連

- 起源: 採用 4 リポで CLAUDE.md 補強 0 hit 観測
- 関連 task: task-40 / task-41 (CLAUDE.md 補強反映漏れの典型例)
- user verbatim: 「精度は変わりますか」+ 「着手」(2026-05-26)
