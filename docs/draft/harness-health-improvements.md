<!--
approval_required: true
approved_at:
approved_by:
retroactive: false
-->

# ハーネス健全性改善 (master roadmap)

**ステータス:** 🔲 **draft（2026-05-28 起案、user 承認待ち）**
**起点:** user 報告 3 問題 (tool call parse 失敗で停止 / hook 検知が過剰 / Grep が使えない)
**前提:**
- observe forensics 2 agent + settings 静的解析 + content-post SSoT 調査で原因特定済 (本 session)
- draft-flow-guard 緩和 (規範ファイル新規 Write block 撤廃) は問題 2 の先行 hot fix として task #3 で実施済 (本 roadmap 外)

---

## 1. 真因サマリ (実測)

| # | 問題 | 真因 | 根拠 |
|---|---|---|---|
| 1 | parse 失敗で停止 | context 肥大 (global `autoCompactEnabled: false` + paths-scoped rule の全文注入 + UserPromptSubmit raw max 41KB) で model の tool 生成が不安定化。別バグとして observe.sh の flock 無し並行 append で観察ログ 8 件 corruption | observe forensics conf 0.78 / settings 実読 |
| 2 | hook 検知が過剰 | 全 tool call に PreToolUse guard が直列実行 (Bash だけで 13,033 回 → 延べ 18 万回超)。体感過剰の主因は guard fan-out + 注入文肥大 (実 block は穏当、bypass.log 99 件)。draft-flow-guard の規範 Write block + frontmatter parser 不整合で詰みループも発生 (task #3 で先行解消) | observe forensics conf 0.82 / recall_poc ログ |
| 3 | Grep が使えない | FleetView クライアントが Grep/Glob tool を非提供 (標準 CLI は提供、過去 ログに 379/379 成功)。加えて bash grep も whitelist 外で二重に塞がる | observe forensics conf 0.75 / settings 実読 |

---

## 2. Task 計画 (採用 6 条準拠、batch 経路 B)

| id | slug | 何のため × 何をやる × 何ができる | 工数 | 依存 | 重要度 |
|---|---|---|---:|---|:---:|
| 50 | grep-whitelist-add | Grep 不在環境での検索手段確保のため bash-whitelist に grep/find/rg を追加し、FleetView でも Bash grep で検索できるようにする | 0.3h | — | 高(即効) |
| 51 | context-bloat-reduction | parse 失敗の根本対策のため autoCompact 方針 + paths-scoped rule の全文注入を要約+リンク化し、context 肥大を抑え tool 生成を安定化する | 2.0h | — | 高 |
| 53 | observe-sh-flock | 観察ログ corruption (L4 学習データ破損) 防止のため observe.sh の append に flock を導入し、並行 subagent 下でも record が壊れないようにする | 0.8h | — | 中 |
| 54 | content-post-portable-idempotent | skill 欠陥の全プロジェクト波及防止のため content-post を hirai-method へ移植 (portable 化) し、成功ログを publish ゲート外へ + content-hash 冪等化して --update 再実行で v 増殖しないようにする | 3.0h | — | 中 |

> 旧 task-52 (PreToolUse guard fan-out 削減、問題 2 の中核) は **draft-flow-guard の規範 Write block 撤廃 (task #3) で部分着手済**。残る fan-out 削減 (guard orchestrator 統合) は別途 task 化を検討 (本 roadmap では保留、効果観察後に起票)。

合計: 6.1h。全 task 独立 (依存なし)。

---

## 3. 各 Task 詳細

### task-50 (A): grep-whitelist-add
- **対象**: `.claude/bash-whitelist.txt` の PATH-RESTRICTED セクション
- **変更**: `^grep( |$)` `^find( |$)` `^rg( |$)` を追加 (read-only、path-leak ガードで src/tests/scripts 直接 inspect は別途 block 維持)
- **検証**: メインが `grep` 実行 → 通過、`grep src/foo.ts` → path-leak block を smoke 検証
- **note**: hot fix 級。bash-whitelist 追加は development-process.md「user レビュー → 追記」規範に従う

### task-51 (B): context-bloat-reduction
- **対象**: global `~/.claude/settings.json` の `autoCompactEnabled` (user 環境、要 user 判断) + paths-scoped rule file (`.claude/rules/*.md` の `paths:` frontmatter で全文注入される設計)
- **変更**: (1) autoCompact を true に戻すか user 確認 (意図的 OFF の可能性) (2) 巨大 rule (workflow.md 等) を「常時注入する要約 + 全文は必要時のみ参照」構造に再編し、docs/tasks/ Read 1 回で数千行注入される現状を軽減
- **検証**: rule 注入量の before/after 計測 (UserPromptSubmit raw size median)
- **note**: 規範変更を含むため個別 draft で詳細設計 + user 承認

### task-53 (C): observe-sh-flock
- **対象**: `.claude/skills/continuous-learning-v2/hooks/observe.sh` L211 `printf '%s\n' "$obs" >> observations.jsonl`
- **変更**: flock (or atomic-mkdir lock) で append を排他化。flock 不在環境 (macOS 標準 flock なし) は `mkdir` lock fallback
- **検証**: 並行 append smoke (N 並列で record 数一致 + corruption 0)
- **note**: subagent 委譲 staging 戦略

### task-54 (E): content-post-portable-idempotent
- **対象**: SSoT が zatsumu repo (`/Users/t.hirai/work/雑務/.claude/skills/content-post/`) にしか無い → hirai-method `.claude/skills/content-post/` へ移植
- **変更**: (1) zatsumu の source (scripts/ src/ SKILL.md package.json tsconfig.json 等、.env/node_modules/dist 除外) を hirai-method へ移植 (portable 化) (2) `scripts/stages/14-publish.ts` L71 の `[post] ok:` を `--update` 経路でも出力されるよう publish ゲート外へ (3) `src/posting/version-manager.ts` bumpVersion (L296-297 無条件+1) に content-hash 比較を入れ同一内容なら no-op
- **検証**: `--update` 単独実行で成功ログ出力 + 同一内容 5 回実行で v 増えない smoke
- **note**: 移植 = 単一リポ内 Write (staging 戦略で subagent 可)。配布は install.sh (user manual)。memory `feedback_harness_skill_project_independent` 起源

---

## 4. 実行順序

全 task 独立 (依存なし)。推奨優先順: **task-50 (即効) → task-53 (小 bug) → task-54 (skill 欠陥) → task-51 (context)**。task-50 のみ hot fix として先行実装可、他は個別 draft → 承認 → 実装。

---

## 5. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| task-51 autoCompact 有効化が user 運用意図に反する | M | M | user 確認必須 (意図的 OFF の可能性)、rule 注入軽量化のみ先行も可 |
| task-54 移植で zatsumu の .env / secret を巻き込む | L | H | include/exclude 境界を zatsumu .gitignore で精査、source のみ移植 |
| task-53 flock が macOS 標準で不在 | M | L | mkdir lock fallback で対応 |

---

## 6. 完了条件 (master roadmap レベル DoD)

- [ ] 4 task が list.md に 📝 先置き (batch 経路 B step 2)
- [ ] 各 task の個別 draft 起案 + user 承認 (task-50 は hot fix で簡略可)
- [ ] 各 task 実装 + smoke regression 0
- [ ] 問題 1/2/3 の改善が定量で確認 (context size / guard 起動数 / Grep 利用可否)
- [ ] SSoT 修正を install.sh --update で他リポへ配布 (user manual)

---

## 7. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-28 | user (修正方針承認) | A/B+D/C/E 全修正方針を承認 (「それ以外は問題ありません」)。batch 経路 B の list.md 先置きは別途確認 |

---

## 8. 関連

- memory: `feedback_harness_skill_project_independent` (E のプロジェクト非依存原則、本 session 起源)
- memory: `feedback_cross_repo_write_sandbox_block` (E の配布は install.sh user manual)
- 既存設計: `docs/draft/observe-jq-parse-fix.md` (observe.sh 過去の jq parse 修正、task-53 と関連)
- task #3: draft-flow-guard 規範 Write block 撤廃 (問題 2 先行 hot fix)
