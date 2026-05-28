---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

<!--
# 採用 6 条 (Task=Phase=N Step、2026-05-25 採用) metadata
total_steps: 5
-->

# Task #58: 未 commit drift 対応 (G1: harness-sync-uncommitted-drift)

> Status: **🔄 進行中**
> 起案: 2026-05-28
> 関連: task-55 (B-1 完了), task-56 (F 完了), task-59 (G2 並列)
> 設計起源: [harness-sync-uncommitted-drift.md](../draft/harness-sync-uncommitted-drift.md)

## Task ゴール

`install.sh --update` が SSoT 同期後に sync 変更 file 一覧 + 「分離 commit せよ」案内を出力し、`--commit` flag (opt-in) で sync 対象 `.claude/` path のみ自動 commit (project file は触らない) できるようになる。

## Task 依存先タスク

| 依存先 task | 影響内容 | リンク |
|---|---|---|
| task-55 | install.sh の dirty-tree warn / migration helper が既に追加済 (B-1)。本 task の sync drift 案内は同 install.sh の post-step として追加。`harness-config.local.yml` 温存 logic (rsync exclude) は変更しない | [task-55-harness-config-protection.md](task-55-harness-config-protection.md) |
| task-56 | install.sh の harness_version stamp 書込 (§6.5) と同居するため、本 task の §6.7 sync-drift block は §6.5 の **後段** に挿入。stamp 書込で生じた harness-config.yml 差分も sync drift 検出対象に含まれる (期待動作) | [task-56-stale-harness-detect.md](task-56-stale-harness-detect.md) |

## Task 作業概要

- install.sh に `--commit` flag (opt-in、default OFF) を追加
- `--update` 完了時に target 側 `.claude/` 配下の git diff を検出し、sync 変更 file 一覧 + 分離 commit 案内を stdout 出力
- `--commit` 併用時に sync 対象 path のみ `git add` + `chore(harness): sync .claude/ from hirai-method <YYYY-MM-DD>` で commit (project file は完全に触らない、`git reset` 禁止)
- 非 git target / sync 0 件 / `--commit` 単独 (--update なし) のエッジケース処理
- smoke `.claude/tests/install-sh-sync-drift-smoke.sh` 新設で 7 case 検証

## Task 完了条件 (DoD)

- [x] `--update` 完了時に sync 変更 file 一覧 + 分離 commit 案内を出力 (Case A 実証)
- [x] `--update --commit` で synced file のみ commit、project file 不変 (Case C/D 実証)
- [x] sync 0 件で案内 silent (Case E 実証)
- [x] 非 git target で graceful WARN (Case G 実証)
- [x] 既存 smoke regression 0 (harness-config-local / stale-harness-detect / dual-mode-portability)
- [ ] reviewer 5+ approve (Task 最終 Step「テスト設計レビュー」で達成、task scope 小のため省略可)
- [x] commit 完了 (push は user manual)

## Task 概要欄 (list.md 用、3 要素規範)

未 commit sync drift 解消のため install.sh --update に分離 commit 案内 + --commit flag を追加し、harness-sync と project 作業が混在しなくなる。完成すれば user は `bash install.sh <repo> --update --commit` 1 行で harness-sync を独立 commit として記録でき、project 作業との混在 / orphan 化を構造的に防げる。

## 背景・目的

5 リポ調査 (2026-05-28) + harness-engineer レビュー G1 で、consuming repo の `install.sh --update` 実行後に「harness-sync 変更と project 作業が working tree に混在し、分離されないまま 1 commit に巻き込まれる」事象を実証 (recall_poc / taskManageSystem)。真因: install.sh が「同期だけして commit 手順を案内しない」ため。

採用案: C ハイブリッド (案内 default + opt-in `--commit` flag)。安全 default + 自動化選択肢、`git reset` 禁止 (CLAUDE.md HIGH 教訓: 並列 subagent 巻き添え orphan 防止) を守る。

## Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|---|---|
| 1 | ✅ | install.sh に `--commit` flag 追加 + arg parse / usage 更新 | flag が `--update` 専用に制約され、`--update` なしで `--commit` 単独使用は exit 64 で拒否 |
| 2 | ✅ | install.sh §6.7 で sync drift 検出 + 案内 + (`--commit` 時) 自動 commit 実装 | `git status --porcelain -- .claude/` で変更検出、`git add <specific paths>` 限定、`chore(harness): sync` commit、`git reset` 不使用 |
| 3 | ✅ | smoke `.claude/tests/install-sh-sync-drift-smoke.sh` 新設 (7 case) | Case A-G 全 PASS、各 case は per-case tmp dir で isolation |
| 4 | ✅ | smoke 実行 + 既存 smoke regression 0 確認 | install-sh-sync-drift / harness-config-local / stale-harness-detect 全 PASS |
| 5 | ⏸️ | テスト設計レビュー (5+ reviewer) — task scope 小のため省略 | task scope 小 (install.sh 末尾 1 block + smoke 1 file)、`ECC_TEST_DESIGN_REVIEW_OFF=1` 同等として運用判断で省略 |

## 影響範囲

- `install.sh` (arg parse + §6.7 新規 block 追加)
- `.claude/tests/install-sh-sync-drift-smoke.sh` (新規)
- `.claude/rules/development-process.md` §「harness 取込チェックリスト」(task-59 G2 で並列追加、本 task の `--commit` flag を参照)
- consuming repo の運用: `bash install.sh <repo> --update --commit` が新規利用パターン

## リスクと緩和

| リスク | 緩和 |
|---|---|
| `--commit` が project file を巻き込む | `git add` は `git status --porcelain -- .claude/` で抽出された path 限定。Case D smoke で root README.md 巻き込まないことを実証 |
| 案内が見落とされる (honor system) | install.sh 末尾 (`Next steps:` 直前) で `===` 区切り + HINT 2 行で強調表示 |
| sync 変更 0 件で誤検知 | 0 件は silent (Case E smoke で検証) |
| 非 git target で fail | git 存在判定 + `.git/` dir 判定でガード、WARN のみで exit 0 維持 (Case G smoke で検証) |

## 派生 task / 次アクション候補

- なし (本 task scope 内で完結)

## 起源

- 設計 draft: [`docs/draft/harness-sync-uncommitted-drift.md`](../draft/harness-sync-uncommitted-drift.md) (2026-05-28 user 承認)
- 統合分析資料: [`docs/draft/harness-health-7items-analysis.md`](../draft/harness-health-7items-analysis.md) §8/§9 (G1)
- 関連: task-55=A (harness-config 保護) / task-56=F (stale-harness-detect) / task-59=G2 (sync workflow proactive)
