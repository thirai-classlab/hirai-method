---
asana_url: ""
slack_urls: []
deadline: ""
requester: ""
---

# Task #13: Subagent `.claude/` 配下 permission denied 回避 staging 戦略の規範化

> Status: **✅ 完了 (2026-05-13)**
> 起案: 2026-05-13
> 完了: 2026-05-13 (commits `3423e40` W0 / `9473657` W1+W2 / `4a6f007` W3 + sync commit 続)
> 関連: #12 / Phase byproduct-discharge
> 設計起源: [`subagent-claude-permission-staging-doc.md`](../draft/subagent-claude-permission-staging-doc.md)

## 背景・目的

task #12 dual-mode-portability (commit `4ddf115`〜`93100a8`) で、general-purpose subagent (`run_in_background=true`) に `.claude/hooks/` `.claude/tests/` への Write/Edit/Bash heredoc redirect 操作を委譲したところ、Claude Code permission system が **denied** で block した。回避策として `/tmp` で Write → `mv` で install の **staging 戦略** を採用し、5 commit を完遂した。

本回避策が暗黙知のままだと、次回 subagent dispatch 時に prompt 明示を忘れ → 再 denied → 試行錯誤コスト発生 (task #12 で約 2-3 分の retry loss を観測) のリスクがある。`.claude/rules/development-process.md` §「サブエージェント委譲」配下に規範化することで、次回以降の subagent dispatch で必ず prompt に staging 明示される honor system を確立する。

副産物 entry: `docs/tasks/next-actions.md` entry #12 (🟡)、推奨処理 (a) 直接実行。

## 仕様（要決定 → 決定済）

### Q1: 規範化の強制レベル (honor / template / hook)

| 案 | 内容 | 評価 |
|---|---|---|
| **A** | rule 追記のみ (honor system) | ✅ 採用 — entry #12 推奨、karpathy Simplicity First、再発検出時に B/C 昇格判定 |
| B | rule + dispatch prompt template 新設 + command 自動参照 | YAGNI (entry 1 件のみで template 化は overkill) |
| C | rule + 専用 hook `subagent-staging-reminder.sh` で PreToolUse(Agent) 強制注入 | over-engineering (hook overhead + 誤発火で context 浪費) |

→ **A** 採用。再発検出時 (subagent dispatch staging 忘れが N=2 以上観測) に B/C 昇格判定。

### Q2: 規範文書の配置位置

`.claude/rules/development-process.md` §「サブエージェント委譲の必須要件 (背景起動 + 順序整合性)」直下 (§1〜§5 後、subagent 関連規範集中箇所)。draft §3 W1 で確定済。

### Q3: smoke / 自動テスト

なし。規範文書のみで code 変更なし、自動検証対象外。

## 設計

draft §3 採用。詳細は draft `docs/draft/subagent-claude-permission-staging-doc.md` §3 参照。

W1 で `.claude/rules/development-process.md` に追加する新セクション「サブエージェント `.claude/` 編集の staging 戦略 (必須)」は以下 4 サブセクションを含む:

1. **強制プロンプト雛型** — メインが subagent に `.claude/` 編集委譲時に Agent prompt へ明示する staging 手順 (3 step + Edit 変種)
2. **検出パターン** — subagent block / error 報告の 3 パターン (`Write` denied / `Edit` denied / `Bash` heredoc block) → 即時切替トリガ
3. **例外** — メイン直接 `.claude/` write は通過 / `worktree` isolation も同 permission policy 下 (確認済)
4. **起源** — task #12 + Serena memory `learning/solutions/subagent-claude-permission-staging` + next-actions entry #12 への traceability

W2 で同 file §関連 にも Serena memory リンクを追加 (W1 と同 commit 同梱可)。

W3 で `docs/tasks/next-actions.md` entry #12 処理結果列を `✅ → docs/draft/subagent-claude-permission-staging-doc.md → task #13 (2026-05-13)` に更新 (別 commit、`docs(tasks):` で sync)。

## TDD 戦略

### RED（先に追加するテスト）

なし。本 task は規範文書 (markdown rule file) のみで code 変更なし、自動テストの対象外。

代替検証: W1 完了後にメイン手動 grep で以下を確認:
- `.claude/rules/development-process.md` に新セクション header 存在
- 4 サブセクション header 存在
- §関連 (W2) に Serena memory `learning/solutions/subagent-claude-permission-staging` への参照存在

### GREEN（最小実装）

W1: `.claude/rules/development-process.md` Edit (`Edit` tool で `## サブエージェント委譲の必須要件` セクション末尾の直後に新セクションを挿入)

W2: 同 file §関連 セクションを Edit で 1 行追加

W3: `docs/tasks/next-actions.md` entry #12 行を Edit で処理結果列のみ更新

### REFACTOR

- §「サブエージェント委譲」「サブエージェント委譲の必須要件」「staging 戦略 (新)」の 3 セクション間で表現重複がないか確認
- staging プロンプト雛型と既存 §1 (run_in_background) §4 (TaskCreate 必須) §5 (Bash deny → subagent 委譲反射) との論理整合性確認

## Wave 構成

| Wave | 内容 | 工数 | 依存 | 状態 |
|:---:|:---|---:|:---|:---:|
| W0 | draft 承認反映 + task #13 spawn (3 file commit) | 0.1h | — | ✅ `3423e40` |
| W1 | `.claude/rules/development-process.md` に新セクション「サブエージェント `.claude/` 編集の staging 戦略 (必須)」追加 (5 サブセクション: 強制プロンプト雛型 / 検出パターン / 例外 / 起源 / 再発検出時の昇格判定) | 0.2h | W0 | ✅ `9473657` |
| W2 | §関連 Serena memory リンク — W1 §起源 sub-section に merge 充足、別 Edit 不要 | 0.05h | W1 | ✅ W1 commit に同梱 |
| W3 | `docs/tasks/next-actions.md` entry #12 処理結果列 sync | 0.05h | W1+W2 | ✅ `4a6f007` |

合計工数: 0.3h (= 約 18 分、実績 0.3h ジャスト)

## 完了条件

- [ ] `.claude/rules/development-process.md` に新セクション「サブエージェント `.claude/` 編集の staging 戦略 (必須)」が存在
- [ ] 強制プロンプト雛型 / 検出パターン / 例外 / 起源 の 4 サブセクションを含む
- [ ] §関連 に Serena memory `learning/solutions/subagent-claude-permission-staging` への参照
- [ ] `docs/tasks/next-actions.md` entry #12 処理結果列が「✅ → docs/draft/... → task #13」化
- [ ] commit 2 件 (W1+W2 同梱 `docs(rules):` / W3 sync `docs(tasks):`) が clean (Conventional Commits 形式)
- [ ] git log で commit hash 実証
- [ ] 既存 smoke regression 0 (code 変更なしのため期待値 9/9 + 9/9 + 6/6 + 6/6 + 4/4 全件 PASS 維持)

## 工数見積

合計 0.3h (約 18 分)。

内訳:
- W1 rule 追記: 出力 約 60 行 (subsection 4 つ) → 約 12 分
- W2 §関連 リンク: 1 行 → 約 3 分
- W3 next-actions.md sync: 表 1 行 update → 約 3 分

## 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル | `.claude/rules/development-process.md` (W1+W2) / `docs/tasks/next-actions.md` (W3) |
| migration | なし |
| 環境変数 | 追加なし |
| 互換性 | 完全互換 (規範文書のみ、code/hook 変更なし、既存 subagent dispatch flow に regression なし) |

## 再発防止

- 本 task 自体が「subagent permission denied の繰り返し試行錯誤」の再発防止策
- 規範化後も honor system のため明示忘れリスクは残存。再発検出時 (subagent dispatch staging 忘れが N=2 以上観測) に副産物 entry 起こし → 案 B (template 化) または C (hook 強制) へ昇格判定

## ステータスログ

| 日付 | 状態 | 備考 |
|---|---|---|
| 2026-05-13 | 起案 | 設計 draft 起こし `docs/draft/subagent-claude-permission-staging-doc.md` |
| 2026-05-13 | 承認 | user 「承認」逐語受領 (Loop モード)、`list.md` row 13 追加 |
| 2026-05-13 | 着手 | W0 commit `3423e40` (3 files: draft / task file / list.md) |
| 2026-05-13 | 完了 | W1+W2 commit `9473657` + W3 commit `4a6f007`、DoD 全項目実証 (新 section / 5 sub-sections / Serena memory link / next-actions ✅ 化 / 2 atomic commits / hash 実証) |

## 派生 task / 次アクション候補

### 義務 (development-process.md §「副産物発生時の即時 draft 起こし義務」準拠)

(本 task 実装中に発見した副産物を本セクションに必ず記入。`/finish-task` 時に全 entry が処理済であることを検証。)

(現時点 0 件、実装中に発見次第追記)

### 関連

- [`next-actions.md`](next-actions.md) — 本セクションと連動する registry
- [`.claude/rules/development-process.md`](../../.claude/rules/development-process.md) §「副産物発生時の即時 draft 起こし義務」

## 関連

- Draft: [`subagent-claude-permission-staging-doc.md`](../draft/subagent-claude-permission-staging-doc.md)
- 依存タスク: #12 (task-12-dual-mode-portability、staging 戦略の発見起源)
- 副産物 registry: [`next-actions.md`](next-actions.md) entry #12
- Serena memory: `learning/solutions/subagent-claude-permission-staging`
