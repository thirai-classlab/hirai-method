<!--
approval_required: true
approved_at: 2026-06-06
approved_by: user
retroactive: false
-->

# agent-router-suggest.sh を UserPromptSubmit dispatcher に配線 (復活)

**ステータス:** 🔲 **draft（2026-06-06 起案、user 承認済 = 案 A 選択）**
**起点:** hooks 未使用ファイル監査 (2026-06-06) で `agent-router-suggest.sh` が task-71 dispatcher 移行時に manifest 未移植で取り残された stale hook と判明 → user が「案 A: 配線して復活」選択
**前提:**
- task-71 で settings.json は generated artifact 化、hook は `dispatcher-manifest.tsv` 経由で event 別 dispatcher から呼ばれる
- 調査確定 (subagent conf 0.86): agent-router-suggest は **feature toggle 無し / 条件付き 1 行出力** (confidence≥0.5 マッチ時のみ、それ以外 stdout 空 + exit 0)、fail-open

**関連 rule:** CLAUDE.md Design Constraints (新 hook 3 点セット: yml key + hook 冒頭 feature check + env override) / context 削減方針 (`docs/draft/context-injection-inventory-reduction.md`)

---

## 1. 課題サマリ

`agent-router-suggest.sh` (named agent 推薦 hint を UserPromptSubmit で注入) は配線経路 (dispatcher-manifest / settings.json / wrapper) のいずれにも存在せず**実行されない dead hook**。冒頭コメントは「settings.json に配線済」と誤記。task-71 移行の取りこぼし。

**真因:** task-71 dispatcher 化で UserPromptSubmit hook を manifest へ移植する際、本 hook が漏れた。

---

## 2. 解決アプローチ (user 選択 = 案 A 配線復活)

| 案 | 内容 | 採否 |
|:---:|:---|:---:|
| **A** | **manifest に配線して復活** | **採用 (user 選択)** |
| B | dead code 削除 | 不採用 |
| C | 据え置き + 誤記述訂正のみ | 不採用 |

→ 案 A。ただし context 削減方針との両立のため **新 hook 3 点セット規範** (feature toggle + 冒頭 check + env override) で配線する。出力は元々条件付き 1 行なので無条件注入は増えない。

---

## 3. 採用案の詳細設計

### 配線仕様
- **manifest 1 行追加** (`.claude/hooks/dispatcher-manifest.tsv`、7 列 TAB 区切り):
  ```
  UserPromptSubmit		3	agent-router-suggest.sh	agent_router_suggest	advisory	5
  ```
  (matcher 空、order=3 = observe の後、channel=advisory で条件付き出力を additionalContext へ畳む、timeout 5)
- **feature toggle 追加**: `harness-config.yml` に `feature_agent_router_suggest_enabled: true` (**default ON** = 「復活」= 有効化。条件付き 1 行出力で低コストのため ON 妥当)。各 repo は `hc-config.sh --feature agent_router_suggest=false` で OFF 可
- **config-loader.sh の FEATURE export allowlist** に `FEATURE_AGENT_ROUTER_SUGGEST_ENABLED` を追記 (yml 値を HC_FEATURE_ env に反映、調査の唯一不確実点を実装で確定)
- **hook 冒頭に `is_feature_enabled agent_router_suggest` gate 追加** (false なら即 exit 0、3 点セット規範)
- **誤記述訂正**: hook 冒頭コメント「settings.json に配線済」→「dispatcher-manifest 経由配線 (feature_agent_router_suggest_enabled、default ON)」+ `docs/AGENT-ROUTER.md` の配線記述更新

### Step 計画 (採用 6 条準拠)

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | manifest 1 行追加 + harness-config.yml feature toggle (default true) + config-loader.sh FEATURE export 追記 + hook 冒頭 is_feature_enabled gate + 誤記述訂正 (hook コメント + docs/AGENT-ROUTER.md) | — |
| 2 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 1 |
| 3 | 🔲 | (テスト合格) smoke: toggle ON で child spawn + マッチ prompt で 1 行注入 / toggle OFF で no-op / 非マッチ prompt で空 / dispatcher-core 健全性 + settings drift 0。既存 regression 0 | 2 |
| 4 | 🔲 | (リファクタリング) 3 観点 or skip | 3 |

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| 毎ターン UserPromptSubmit 注入増 → context 削減方針と矛盾 | L | M | 出力は**条件付き** (confidence≥0.5 マッチ時のみ 1 行)。非マッチは空 = 無条件注入 0 を維持。feature toggle で OFF 可 |
| config-loader allowlist 漏れで toggle 無効 | M | M | Step 1 で FEATURE export 追記 + smoke で toggle ON/OFF の child spawn 差を実測 |
| python3 / router.py 不在環境で誤動作 | L | L | 既存 fail-open (不在で no-op exit 0) |

---

## 6. 完了条件（DoD）

- [ ] manifest に UserPromptSubmit order=3 で agent-router-suggest 配線
- [ ] feature toggle `feature_agent_router_suggest_enabled` (default true) + config-loader export + hook 冒頭 gate
- [ ] toggle ON + マッチ prompt → 1 行 hint 注入 (smoke 実測) / toggle OFF → no-op (smoke 実測) / 非マッチ → 空
- [ ] hook 誤記述コメント + docs/AGENT-ROUTER.md 配線記述 訂正
- [ ] dispatcher-core / settings drift / 既存 smoke regression 0、bash 3.2 互換

---

## 7. 工数見積
約 1.0h

---

## 8. レビューサイクル

| iter | 日付 | reviewer (起動数) | CRITICAL | HIGH | MEDIUM | LOW | 修正 commit | 状態 |
|:---:|---|---|:---:|:---:|:---:|:---:|---|---|
| 1 | — | (Task 最終 Step のテスト設計レビューで実施) | — | — | — | — | — | 未着手 |

---

## 9. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-06-06 | user | **承認** (hooks 監査 → 「A: 配線して復活」選択) → task-81 化 |

---

## 10. 関連
- `.claude/hooks/agent-router-suggest.sh` / `.claude/hooks/dispatcher-manifest.tsv` / `.claude/hooks/lib/config-loader.sh` / `.claude/harness-config.yml` / `docs/AGENT-ROUTER.md`
- task-71 (settings dispatcher 化、本 hook の取りこぼし元) / 調査: agent-router 配線設計 (subagent conf 0.86)
