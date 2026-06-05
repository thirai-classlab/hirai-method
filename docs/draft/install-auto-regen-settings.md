<!--
approval_required: true
approved_at: 2026-06-05
approved_by: user
retroactive: false
-->

# install.sh settings.json 自動再生成 (default) + .gitignore state dir 追記

**ステータス:** 🔲 **draft（2026-06-05 起案、user 承認済 = 案 B 選択）**
**起点:** user 報告 (2026-06-05)「インストーラーでステータスバー同期されてない」+ taskManageSystem install 時の `.gitignore` state 混入発見
**前提:**
- task-62 が statusLine 配線を `generate-settings.sh` に組込済 (生成 settings.json に statusLine block)
- task-71 H2 が `settings.json` を rsync exclude (repo 固有 permissions 保護)
- 調査確定 (subagent conf 0.92): generate-settings.sh は既存 settings.json の `.permissions` を verbatim 保持・statusLine 無条件出力・jq のみ依存・既存 settings.json 不在で die

**関連 rule:** `.claude/rules/development-process.md` §「harness 取込チェックリスト」

---

## 1. 課題サマリ

`install.sh --update` は `statusline.sh` 本体は配布するが、**statusLine 配線が入る settings.json は rsync exclude** のため反映されず、consuming repo は別途 `generate-settings.sh` 手動実行が必要 = statusbar が同期されない (user 報告)。

**副次**: harness `.claude/.gitignore` が runtime state dir 6 種 (`.preset-history/` / `.reviewer-count-state/` / `.context-budget-state/` / `.workflow-state/` / `.task-screenshots/` / `.session-help-shown`) を未列挙 → consuming repo で `git add .claude` すると transient state が混入 (taskManageSystem install 時に 3407→3156 file へ手動除外を要した)。

---

## 2. 解決アプローチ (user 選択 = 案 B default 化)

| 案 | 内容 | 採否 |
|:---:|:---|:---:|
| A | opt-in flag `--regen-settings` | 不採用 |
| **B** | **rsync 後に settings.json を default 自動再生成** | **採用 (user 選択)** |
| C | 改修せず手動運用 | 不採用 |

→ 案 B。手間ゼロで statusbar / dispatcher 配線が同期。permissions は verbatim 保持されるため task-71 H2 の懸念 (permissions 上書き) は起きない。**受容リスク**: settings.json に手編集した独自トップレベル key / 独自 hook は manifest 由来に置換される (user が B 選択時に受容)。

---

## 3. 採用案の詳細設計

### Step 計画 (採用 6 条準拠)

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | install.sh: rsync 後 (section 6 chmod と 6.5 stamp の間) に settings.json 自動再生成を組込。**条件**: MODE ∈ {update, force, overwrite-all} ∧ 非 dry-run ∧ `command -v jq` ∧ generate-settings.sh 配布済 ∧ **既存 settings.json あり** (不在は skip + hint で permissions 喪失/die 回避)。実行 `(cd "$TARGET" && bash .claude/scripts/generate-settings.sh --out .claude/settings.json)`、失敗は WARN のみ (fail-open)。summary の手動 hint を「自動実行済 (失敗時のみ手動)」へ更新 | 0.5h | — |
| 2 | 🔲 | `.claude/.gitignore` に 6 行追記 (`.preset-history/` / `.reviewer-count-state/` / `.context-budget-state/` / `.workflow-state/` / `.task-screenshots/` / `.session-help-shown`)。各行 comment 付き | 0.1h | — |
| 3 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (min≤N≤max) | 0.3h | 1,2 |
| 4 | 🔲 | (テスト合格) smoke: update で既存 settings.json ありなら再生成 + statusLine block 含有 / settings.json 不在は skip / dry-run は再生成しない / 既存 permissions 保持 / .gitignore に 6 entry。既存 install smoke regression 0。bash 3.2 互換 | 0.4h | 3 |
| 5 | 🔲 | (リファクタリング) 3 観点 or skip | 0.1h | 4 |

合計: 約 1.4h

### 自動再生成 ロジック (Step 1 詳細)
```
# section 6.x: settings.json 自動再生成 (statusLine / dispatcher 配線同期、task-80)
if [[ "$MODE" == "update" || "$MODE" == "force" || "$MODE" == "overwrite-all" ]] && ! $DRY_RUN; then
  gen="$TARGET/.claude/scripts/generate-settings.sh"
  live="$TARGET/.claude/settings.json"
  if ! command -v jq >/dev/null 2>&1; then
    echo "[install] WARN: jq 不在のため settings.json 自動再生成 skip。手動: bash .claude/scripts/generate-settings.sh --out .claude/settings.json" >&2
  elif [[ ! -f "$gen" ]]; then
    echo "[install] WARN: generate-settings.sh 不在、settings.json 自動再生成 skip" >&2
  elif [[ ! -f "$live" ]]; then
    echo "[install] NOTE: 既存 settings.json 不在のため自動再生成 skip (permissions 喪失回避)。新規は手動生成要" >&2
  else
    if ( cd "$TARGET" && bash .claude/scripts/generate-settings.sh --out .claude/settings.json ); then
      echo "[install] settings.json 再生成済 (statusLine / dispatcher 配線同期、permissions 保持)"
    else
      echo "[install] WARN: settings.json 自動再生成 失敗 (install は継続)。手動再生成を検討" >&2
    fi
  fi
fi
```

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| 手編集独自 key/hook の脱落 | M | M | **B 選択時に user 受容**。summary に「独自 hook は dispatcher-manifest に登録、独自 key は schema 外で脱落」を明記 |
| 既存 settings.json 不在で die/permissions 喪失 | L | H | 条件で skip + hint (実装済ガード) |
| jq 不在環境で install 失敗 | L | M | jq 不在は WARN + skip (fail-open、install 継続) |
| 再生成が sync drift 検出/`--commit` に乗る | — | — | 既存 section 6.7 git status が自動で拾う (期待挙動) |

---

## 6. 完了条件（DoD）

- [ ] `--update` (既存 settings.json あり) で settings.json が自動再生成され statusLine block を含む (smoke 実測)
- [ ] 既存 permissions が保持される (smoke 実測)
- [ ] 既存 settings.json 不在 / jq 不在 / dry-run で再生成 skip (smoke 実測)
- [ ] `.claude/.gitignore` に 6 state dir entry 追加
- [ ] 既存 install/update/force/overwrite-all smoke regression 0
- [ ] summary hint 更新 / bash 3.2 互換

---

## 7. 工数見積
約 1.4h

---

## 8. レビューサイクル

| iter | 日付 | reviewer (起動数) | CRITICAL | HIGH | MEDIUM | LOW | 修正 commit | 状態 |
|:---:|---|---|:---:|:---:|:---:|:---:|---|---|
| 1 | — | (Task 最終 Step のテスト設計レビューで実施) | — | — | — | — | — | 未着手 |

---

## 9. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-06-05 | user | **承認** (案 B 「settings.json 自動再生成 default 化」選択) → task-80 化 |

---

## 10. 関連
- `install.sh` (section 6 付近 + summary) / `.claude/.gitignore` / `.claude/scripts/generate-settings.sh`
- task-62 (statusLine 配線) / task-71 (settings.json generated) / task-79 (install mode)
- 調査: generate-settings 自動化可否 (subagent conf 0.92)
