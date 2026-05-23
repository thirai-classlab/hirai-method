# recall_poc Recovery — git init / CLAUDE.md 改訂 / draft フロー復旧 / task 台帳初期化

**ステータス:** 🔲 **draft (2026-05-23 起案、user 承認待ち)**
**起点:** 2026-05-23 recall_poc 調査で 4 件の運用問題発覚 (git 未 init / CLAUDE.md draft フロー宣言外れ / docs/01-03 が docs/ 直下直接 Write / list.md 未着手)
**前提:**
- `draft-flow-guard.sh` (task-21 関連、commit `6ed9337`) 配備済
- `install.sh` (本 session で新設) で recall_poc に hook 同期済

**関連 fixture / rule:**
- `/Users/t.hirai/recall_poc/CLAUDE.md` (12464B、AI 自動生成版)
- `/Users/t.hirai/recall_poc/docs/{01_basic_design,02_screen_flow,03_feature_list}.md` (docs/ 直下直接置きの観察事案)
- `/Users/t.hirai/recall_poc/docs/draft/0[1-3]_*.md` (本 session で遡及作成済、内容改善必要)

---

## 1. 真因サマリ / 課題サマリ

2026-05-23 の調査で recall_poc に **4 件の運用復旧課題** が判明:

- **R-1 / C-7**: recall_poc が **git 未 init**。observe.sh の project_id 解決 (git remote → git toplevel → fallback) が機能せず、recall_poc 用 observation が hirai-method (project hash 9108e0c8f946) に混入。L4 学習 (instinct) が project 混線
- **R-2**: recall_poc/CLAUDE.md (12464B、AI 自動生成、5/23 01:24) が template の「設計→承認→タスク追加」フローを **独自構造に置換**。「自律実行可」リストに「承認済み設計書 (docs/01_basic_design.md / 02_screen_flow.md / 03_feature_list.md) に基づく実装」と書かれ、設計書が最初から docs/ 直下にある前提になっている
- **R-3**: 本 session で遡及作成した docs/draft/0[1-3]_*.md は元 file の内容を copy しただけで、「設計起源 / 意図 / 承認状態」frontmatter なし
- **R-4**: docs/tasks/list.md が template のまま (1891B)、設計 01-03 が task 化されていない

**真因**: 前 session の AI が template 通りに CLAUDE.md を生成せず、独自判断で draft フローを変形した。hook (`task-rule-guard.sh`) は docs/tasks/ のみ監視で docs/ 直下を許容するため、AI の独自判断を検知できなかった (本 session で `draft-flow-guard.sh` 新設で構造解消済、但し既存 file の遡及対処が必要)。

**副次**: recall_poc 独立 observation が蓄積されていないため、recall_poc 固有の instinct も学習されていない。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | 全 docs/01-03 を docs/draft/ に移動して draft フローからやり直し | 1.5 | 規範完全準拠 | 既存 file path が変わり追跡困難 |
| **B** | docs/01-03 を「承認済み」として docs/ に残し、frontmatter で approval state を明示 | 0.8 | 既存 file path 維持、追跡容易 | 規範違反の歴史を残す |
| **C ハイブリッド** | git init + CLAUDE.md 改訂 + 遡及 draft 整備 (B) + list.md 初期化 を並行 | 1.0 | 規範整合と path 維持の両立 | Wave 順序管理が必要 |

→ **C ハイブリッド** を推奨。docs/01-03 は「承認済み設計書」として残し、遡及 draft を「設計起源 + 承認履歴」として整備する。

---

## 3. 採用案の詳細設計

### Wave 分割

| Wave | 内容 | 工数 | 効果 |
|:---:|:---|---:|:---|
| W1 | recall_poc を `git init` + `.gitignore` 設定 (本 session の `.gitignore` を継承) | 0.1 | project_id 独立、observe.jsonl 混線解消 |
| W2 | CLAUDE.md template の Autonomous Progression を「draft フロー強制版」に rewrite + recall_poc/CLAUDE.md 再生成 | 0.4 | 次セッション AI が draft 経由を default | 
| W3 | docs/draft/0[1-3]_*.md に frontmatter (`approval_required: true / approved_at: 2026-05-23 / approved_by: user / retroactive: true`) 追記 | 0.2 | 遡及 draft の承認状態が機械可読 |
| W4 | docs/tasks/list.md 初期化 + 設計 01-03 から実装 task を分解して 5-10 task 行追加 | 0.3 | 実装フェーズ着手可能 |
| W5 | `/init-tasks` 相当の SessionStart 動作確認 + harness-audit で recall_poc 健全性レポート | 0.2 | 復旧検証 |

合計: 1.2 session

### W1 詳細 (git init)

#### スコープ
- 対象: `/Users/t.hirai/recall_poc/`

#### 変更内容
```bash
cd /Users/t.hirai/recall_poc
git init
# .gitignore は本 session install.sh で配置済
git add -A
git commit -m "chore: initial commit (HIRAI method harness installed 2026-05-23)"
```

#### テスト
- `git rev-parse --show-toplevel` で `/Users/t.hirai/recall_poc` を返すか
- observe.sh の project_id が hirai-method (9108e0c8f946) から分離されるか (新 session 起動後 1 ターンで確認)

### W2 詳細 (CLAUDE.md template 改訂 + recall_poc 再生成)

#### スコープ
- 対象: `/Users/t.hirai/work/hirai-method/CLAUDE.md` (template 本体) の Autonomous Progression セクション
- 対象: `/Users/t.hirai/recall_poc/CLAUDE.md` (recall_poc 用) 再生成

#### 変更内容 (template)
```markdown
### 自律実行可 (user 確認不要)
- 承認済み設計書 (`docs/draft/<slug>.md` に approved_at 記載済、または `docs/tasks/task-N-*.md`) に基づく実装
- (略)

### chat で必ず確認 (クリティカル)
- 設計文書 (要件 / 基本設計 / 詳細設計 / 機能一覧) の新規追加 ← **必ず docs/draft/ 経由で起こす、docs/ 直下への直接 Write は禁止 (draft-flow-guard.sh で BLOCK)**
- (略)
```

### W3 詳細 (遡及 draft の frontmatter 整備)

#### 変更内容
```markdown
---
approval_required: true
approved_at: 2026-05-23
approved_by: user (retroactive)
retroactive: true
original_path: docs/01_basic_design.md
retro_reason: 前 session 中の AI 独自判断で docs/draft/ を経由せず docs/ 直下に直接 Write されたため、本 session で遡及作成
---

<!-- 元 file の内容: -->
(以下、元 file の内容)
```

### W4 詳細 (list.md 初期化)

#### スコープ
- 対象: `/Users/t.hirai/recall_poc/docs/tasks/list.md`
- 設計 01-03 を読んで実装 task を 5-10 件に分解

#### テスト
- task-rule-guard.sh が `docs/tasks/task-1-*.md` 等の新規 Write を pass (対応 draft 不在で BLOCK しないか要検証 — recall_poc には draft が遡及作成済)

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| git init で巨大 file 混入 (.serena / observe-cache 等) | M | M | .gitignore を install.sh の `.gitignore` で網羅、`git status` で事前確認 |
| CLAUDE.md template 改訂が他 project (taskManageSystem / classlab-weekly-news) に影響 | L | M | template は hirai-method 本体のみ更新、各 project は install.sh --update で個別反映 |
| 遡及 draft の frontmatter が draft-flow-guard.sh の判定 logic に副作用 | L | L | draft-flow-guard.sh は file 存在のみ check、frontmatter は無視するため影響なし |

---

## 5. 移行計画

- [ ] W1: recall_poc git init + 初回 commit
- [ ] W2: CLAUDE.md template 改訂 (hirai-method 側) + recall_poc/CLAUDE.md 再生成
- [ ] W3: 3 件の遡及 draft に frontmatter 追記
- [ ] W4: list.md に実装 task 行追加 + 各 task ファイル生成
- [ ] W5: 新 session 起動 → /init-tasks → harness-audit で復旧確認

---

## 6. 完了条件 (DoD)

- [ ] recall_poc が独立 project hash で observation 記録される
- [ ] recall_poc/CLAUDE.md が draft フロー強制版に更新済
- [ ] docs/draft/0[1-3]_*.md に承認 frontmatter あり
- [ ] docs/tasks/list.md に実装 task 行が 5+ 件
- [ ] draft-flow-guard.sh が recall_poc で誤検知なく動作 (既存 file は通過、新規 docs/ 直下は BLOCK)

---

## 7. 工数見積

合計 1.2 session (W1 0.1 + W2 0.4 + W3 0.2 + W4 0.3 + W5 0.2)。

---

## 8. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-23 | user | (待ち) |

---

## 9. 関連

- 既存設計: `docs/draft/system-reminder-attention-fix.md` (Wave 2.5 で CLAUDE.md Autonomous Progression を改訂、本 task W2 と同根)
- 観察証拠: `/Users/t.hirai/recall_poc/docs/0[1-3]_*.md` (docs/ 直下直接 Write の typical 事案)
- 関連タスク: 本 draft = task-23 想定 / task-21 (system-reminder-attention-fix Wave 2.5) と部分重複
