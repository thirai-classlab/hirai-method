<!--
approval_required: true
approved_at: 2026-06-04
approved_by: user
retroactive: false
-->

# Claude Code ステータスライン構築 (task-62)

**ステータス:** 🔲 **draft（2026-06-04 起案、user 承認待ち）**
**起点:** task-62 (📝、list.md row 62) 再開。user 仕様確定 (2026-06-04)
**前提:**
- Claude Code `statusLine` 機能 (settings.json) — stdin JSON で session 情報を受け取る
- research 確定 (claude-code-guide、conf 0.95-0.98、出典 https://code.claude.com/docs/en/statusline.md): `rate_limits.{five_hour,seven_day}.used_percentage` / `context_window.used_percentage` / `model.display_name` / `workspace.repo.*` が JSON で取得可
- settings.json は generated artifact (task-71、generate-settings.sh で再生成)

**関連 rule:**
- `.claude/rules/modes.md` (mode.yml = loop/normal)

---

## 1. 課題サマリ

task-62 は「表示内容 / 更新条件 / 視覚仕様は着手時に user と擦り合わせて確定」として 📝 保留だった。本 draft で user 擦り合わせ結果を確定し実装可能化する。

**確定仕様 (user 2026-06-04)**:
1. **表示項目 (全部)**: mode (loop/normal) / context 使用率 % / Claude 5h 制限残り % / 7d 制限残り % / git branch / model 名
2. **Web UI 導線**: ヒント表示 (案 A)。`.claude/...` から始まる起動コマンド表記
3. **複数行**表示
4. **スタイル**: ミニマルリッチ = **絵文字なし**、Claude Code 配色踏襲 (ANSI 色のみ)

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | 新 script `.claude/scripts/statusline.sh` (stdin JSON を jq で parse + mode.yml read) + settings.json に statusLine 配線 (generate-settings.sh 経由) | 1.5 | portable、generated artifact と整合 | jq 依存 |
| **B** | settings.json に inline shell one-liner | 0.5 | file 不要 | 複数行/色/fallback で破綻、保守不能 |

→ **案 A** 推奨 (script 化で複数行 + 色 + graceful fallback を保守可能に)。

---

## 3. 採用案の詳細設計

### 表示レイアウト (2 行、絵文字なし、ANSI 色)

```
<model> · <branch> · ctx <N>%
5h <N>% · 7d <N>% · <mode> · settings: .claude/scripts/hc-config.sh
```

例 (色は ANSI、ここでは text のみ):
```
Opus 4.8 · feat/task-78 · ctx 34%
5h 72% · 7d 55% · loop · settings: .claude/scripts/hc-config.sh
```

- **数値元**: ctx = `context_window.used_percentage` / 5h = `100 - rate_limits.five_hour.used_percentage` / 7d = `100 - rate_limits.seven_day.used_percentage` / model = `model.display_name` / branch = `workspace.repo.*` (or `git`) / mode = `$cwd/.claude/mode.yml` の `mode:` 値
- **色 (Claude Code 踏襲、ANSI のみ)**: 区切り `·` は dim。残り % は閾値で着色 (例: ≥50 緑系 / 20-49 黄系 / <20 赤系)。mode=loop は強調色、normal は dim
- **Web UI hint**: `settings: .claude/scripts/hc-config.sh` を dim text で表示 (クリック不可、user が打つ導線)

### graceful fallback (必須)
- `rate_limits` は **Pro/Max 限定 + 初回 API 応答後**に出現 → 不在時は `5h —` / `7d —` 表示 (空欄でなく `—`)
- jq 不在 → 最小限の plain 出力 (model + branch のみ) に降格、エラーで status 全体を壊さない
- mode.yml 不在 → `normal` 既定

### Step 計画 (採用 6 条準拠)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | **複数行 statusLine 描画の実機検証** (Claude Code が multi-line 出力を render するか確認) + `.claude/scripts/statusline.sh` 雛形 (stdin JSON echo) | 0.3h | — |
| 2 | 🔲 | statusline.sh 本実装: jq parse (model/ctx/rate_limits/branch) + mode.yml read + 2 行整形 + ANSI 色 + graceful fallback (rate_limits 不在 / jq 不在 / mode.yml 不在) | 0.6h | 1 |
| 3 | 🔲 | settings.json 配線: generate-settings.sh (or manifest) に `statusLine` block 追加 → 再生成 → 本 repo settings.json 反映。portable 性確認 | 0.4h | 2 |
| 4 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (min≤N≤max、`hc-config.sh --get review_max_count_test` 確認) | 0.3h | 3 |
| 5 | 🔲 | (テスト合格) smoke: sample JSON 投入で 2 行出力 / rate_limits 不在 fallback / jq 不在 fallback / mode loop·normal / 色 escape 含有。+ 実機 statusLine 目視確認 | 0.4h | 4 |
| 6 | 🔲 | (リファクタリング) 3 観点判定 or skip | 0.1h | 5 |

合計: 約 2.1h

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| Claude Code が複数行 statusLine を render しない | M | H | **Step 1 で実機検証**。不可なら 1 行 `·` 区切りに縮約 (user 再確認) |
| `rate_limits` が free tier / 起動直後に不在で表示崩れ | H | M | graceful fallback (`—` 表示)、空欄禁止 |
| jq 不在環境で status 全体が壊れる | M | M | jq 検出 → plain 降格、非ゼロ exit を出さない |
| settings.json は generated → 手編集が再生成で消える | M | M | generate-settings.sh 側に statusLine を組込 (Step 3)、手編集しない |

---

## 6. 完了条件（DoD）

- [ ] statusLine が 2 行で mode / ctx% / 5h% / 7d% / branch / model / settings hint を表示 (実機目視)
- [ ] rate_limits 不在時 `—` fallback (smoke 実測)
- [ ] jq 不在時 plain 降格で status 非破壊 (smoke 実測)
- [ ] 絵文字なし + ANSI 色のみ (Claude Code 踏襲)
- [ ] settings.json への配線が generate-settings.sh 再生成で再現 (portable)
- [ ] 既存 smoke regression 0、bash 3.2 互換

---

## 7. 工数見積

約 2.1h (Step 1 0.3 + 2 0.6 + 3 0.4 + 4 0.3 + 5 0.4 + 6 0.1)

---

## 8. レビューサイクル

| iter | 日付 | reviewer (起動数) | CRITICAL | HIGH | MEDIUM | LOW | 修正 commit | 状態 |
|:---:|---|---|:---:|:---:|:---:|:---:|---|---|
| 1 | — | (Task 最終 Step のテスト設計レビューで実施) | — | — | — | — | — | 未着手 |

---

## 9. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-06-04 | (待ち) | 仕様 4 点 user 確定済 (全項目 / hint `.claude/` 表記 / 複数行 / 絵文字なし Claude Code 踏襲)、draft 承認待ち |
| 2026-06-04 | user | **承認** (「両方承認」) → task-62 化 (既存 📝 行を活性化) |

---

## 10. 関連

- task-62 (list.md row 62)
- research: claude-code-guide 調査 (statusLine JSON / rate_limits / OSC8)
- `.claude/scripts/hc-config.sh` (Web UI 起動 = hint 先)
- `.claude/scripts/generate-settings.sh` (settings.json 生成、Step 3 配線先)
