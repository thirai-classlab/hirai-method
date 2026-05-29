<!--
approval_required: true
approved_at: 2026-05-29
approved_by: user
retroactive: false
-->

# hc-config TUI 真の 2 階層 Navigation

**ステータス:** ✅ **draft 承認済（2026-05-28 起案 → 2026-05-29 user 承認、3 確認ポイントは採用案 default で進行）**
**起点:** task-48 §3.3 設計乖離の follow-up（user 手動検証で「2 階層 menu まだ無い」と発見）
**前提:**
- task-48 完了済（`_cmd_interactive_tui` / `_tui_render` / `_tui_order_keys_by_category` 実装済）
- `.claude/scripts/hc-config.sh` L1160-L1425 が現 TUI 実装 SSoT

**関連 fixture / rule:**
- `.claude/scripts/hc-config.sh`
- `.claude/lib/hc-config-metadata.sh`
- `.claude/tests/hc-config-tui-smoke.sh`
- `docs/draft/hc-config-interactive-tui.md` §3.3（設計元）

---

## 1. 起源と課題サマリ

task-48 の TUI 実装（`.claude/scripts/hc-config.sh` L1160-L1425）は、`docs/draft/hc-config-interactive-tui.md` §3.3 が定義した「**category 一覧 menu → key 一覧 menu**」の 2 階層 navigation を実現できなかった。実際の実装は category 見出し区切り行（`=== feature_toggle (21 keys) ===`）を挿入した **1 階層 flat list** に妥協 closure された。

user が手動検証で乖離を発見し、follow-up 設計として本 draft を起案する。

**現状の限界:** 全 74 key を 1 画面に表示するため、↑/↓ スクロール量が多く目的の key へ到達するのに時間がかかる。category 境界の区切り行は視覚ノイズにはなっているが操作の起点にはなっていない。

**真因:** state machine が `key_menu` 1 状態のみで設計され、`category_menu` 状態が存在しなかった。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A (現状維持)** | 1 階層 flat list のまま | 0 | 追加実装ゼロ | 74 key スクロール問題が残る、設計乖離継続 |
| **B (2 階層 state machine)** | `category_menu` → `key_menu` → `effect_edit` 3 state | 0.5h | 設計乖離解消 / 6 category で先に絞り込みできる / UX 向上 | bash state machine 複雑化 / sel 位置記憶の portability |
| **C (fzf 外部依存)** | fzf を使って 2 階層 filter | 0.3h | 実装量が少ない | fzf 非インストール環境で動かない / 外部依存 |

→ **案 B** を採用。理由: fzf 非依存で bash 3.2 互換を維持でき、設計 §3.3 への整合を回復できる。

---

## 3. 採用案の詳細設計

### 3.1 state machine（3 state）

```
┌──────────────────────────────────────────────────────────┐
│  state: category_menu                                    │
│  ↑/↓: category 選択   Enter: → key_menu   q: quit       │
└─────────────────────────┬────────────────────────────────┘
                          │ Enter
                          ▼
┌──────────────────────────────────────────────────────────┐
│  state: key_menu                                         │
│  ↑/↓: key 選択   Enter: → effect_edit   ESC/LEFT: back  │
│  q: quit                                                 │
└─────────────────────────┬────────────────────────────────┘
                          │ Enter
                          ▼
┌──────────────────────────────────────────────────────────┐
│  state: effect_edit                                      │
│  effect panel 表示 → 新値入力 → cmd_set                  │
│  完了 or skip → key_menu に戻る                          │
└──────────────────────────────────────────────────────────┘
```

遷移まとめ:
- `category_menu` --Enter--> `key_menu`（選択 category 配下の key 一覧）
- `key_menu` --Enter--> `effect_edit`（選択 key の編集）
- `effect_edit` 完了/skip --> `key_menu`（自動戻り）
- `key_menu` --ESC/LEFT--> `category_menu`
- 任意 state --q--> quit

### 3.2 描画モデル

**category_menu 画面:**
```
=== hc-config TUI ===  (↑/↓ 選択, Enter 決定, q 終了)

> 保護パス           (3 keys)
  ファイル配置        (4 keys)
  state_dir          (9 keys)
  Gate/Confidence    (18 keys)
  feature_toggle     (21 keys)
  reviewer_control   (20 keys)
```

**key_menu 画面（feature_toggle 選択後）:**
```
=== hc-config TUI ===  category: feature_toggle  (ESC: 戻る, q 終了)

  feature_stale_harness_detect_enabled
  feature_context_budget_enabled
> feature_loop_auto_progress_enabled
  ...（21 keys）

---------------------------------------------------------------
key     : feature_loop_auto_progress_enabled
説明    : Loop モード自動進行 reminder フック
型      : boolean
現在値  : true
default : true
変更効果: false にすると UserPromptSubmit reminder が no-op になる
```

### 3.3 sel 位置記憶（bash 3.2 互換、scalar var 6+1 個）

category sel は `_tui_cat_sel`（0-based）1 変数。
各 category 配下の key sel は category 名ごとの scalar:

```bash
_tui_key_sel_0=0   # 保護パス
_tui_key_sel_1=0   # ファイル配置
_tui_key_sel_2=0   # state_dir
_tui_key_sel_3=0   # Gate/Confidence
_tui_key_sel_4=0   # feature_toggle
_tui_key_sel_5=0   # reviewer_control
```

`eval` で category index から変数名を合成してアクセス（bash 3.2 互換、連想配列禁止）:

```bash
eval "_tui_key_sel_${cat_idx}=\${new_key_sel}"
eval "cur_key_sel=\${_tui_key_sel_${cat_idx}}"
```

`declare -g` は使用しない（bash 3.2 で未サポート）。

### 3.4 TTY fallback（現状維持）

```bash
cmd_interactive() {
  if [ -t 0 ] && [ -t 1 ] && [ "${HC_HC_CONFIG_FORCE_NUMERIC:-}" != "1" ]; then
    _cmd_interactive_tui        # 2 階層 TUI（本 draft 実装後）
  else
    _cmd_interactive_numeric    # 番号選択（現状維持）
  fi
}
```

### 3.5 1 階層 flat fallback（新規 env）

```bash
HC_HC_CONFIG_FLAT_NAVIGATION=true  # 既存 1 階層実装にフォールバック
```

`_cmd_interactive_tui` 冒頭で check:

```bash
if [ "${HC_HC_CONFIG_FLAT_NAVIGATION:-}" = "true" ]; then
  _cmd_interactive_tui_flat   # 旧 1 階層実装（関数名変更して保持）
  return $?
fi
```

### 3.6 修正スコープ

**修正ファイル:** `.claude/scripts/hc-config.sh` のみ（推定 100-200 LOC 修正）

主要変更:
1. `_cmd_interactive_tui` を state machine ループに書き換え（現 L1370-L1413）
2. `_tui_render` を 3 variants に分割: `_tui_render_category_menu` / `_tui_render_key_menu` / `_tui_render_effect_panel`（現 L1314-L1321 は 1 variants のみ）
3. 旧 `_cmd_interactive_tui` 実体を `_cmd_interactive_tui_flat` に rename して保持
4. sel 位置記憶変数を関数スコープで管理（関数 top で初期化）

---

## 4. 不採用案

**案 A（1 階層 flat 維持）:** 74 key スクロール問題が残存し、設計 §3.3 への乖離が継続する。UX 改善なしで follow-up の意味がない。不採用。

**案 C（fzf 外部依存）:** fzf が標準インストールされていない環境では動作しない。harness の portable 設計方針（`.claude/` 単独で portable、外部 binary 依存最小化）に反する。不採用。

---

## 5. Step 計画（採用 6 条準拠、Phase 中間階層廃止）

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | 旧 `_cmd_interactive_tui` を `_cmd_interactive_tui_flat` に rename + flat fallback env 対応追加 | 0.2h | — |
| 2 | 🔲 | `_tui_render_category_menu` 実装（6 category 一覧、sel ハイライト） | 0.3h | Step 1 |
| 3 | 🔲 | `_tui_render_key_menu` 実装（category 配下 key 一覧 + effect panel） | 0.3h | Step 2 |
| 4 | 🔲 | `_cmd_interactive_tui` を 3-state machine ループに書き換え（sel 位置記憶 scalar 6+1 変数） | 0.4h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー) 5+ reviewer 動的選定 | 0.5h | Step 4 |
| 6 | 🔲 | (テスト合格) smoke 拡張 + 手動 TTY 検証 + 既存 smoke regression 0 確認 | 0.4h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点（持続可能性 / 汎用性 / 非冗長化）判定 | 0.2h | Step 6 |

合計: 約 2.3h

---

## 6. 完了条件（DoD）

- [ ] `hc-config.sh interactive` を TTY で実行すると category 一覧が表示される（6 category）
- [ ] ↑/↓ で category が選択でき、Enter で当該 category 配下の key 一覧に遷移する
- [ ] key 一覧で ↑/↓ 選択 → Enter で effect panel 表示 + 新値入力 → cmd_set が実行される
- [ ] key 一覧で ESC または LEFT を押すと category 一覧に戻る（sel 位置保持）
- [ ] category 選択を変えて再入しても、それぞれの category 内の sel が記憶されている
- [ ] `HC_HC_CONFIG_FLAT_NAVIGATION=true` で旧 1 階層実装が起動される（regression なし）
- [ ] 非 TTY（pipe）環境では番号選択に降格する（既存 smoke Case 5 引き続き PASS）
- [ ] `.claude/tests/hc-config-tui-smoke.sh` の全 case が PASS
- [ ] bash 3.2（macOS 標準）で矢印キー TUI が動作する（`declare -g` / 連想配列を使用しない）

---

## 7. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| bash 3.2 での eval + scalar var 動作差異 | M | H | Step 4 実装時に macOS bash 3.2 で実測検証、`declare -g` 不使用を静的確認 |
| state machine 複雑化でキー入力ハンドリングが肥大化 | M | M | 各 state のハンドラを独立関数に分割（`_tui_handle_category_key` / `_tui_handle_key_key`）、関数 50 行以内ルール厳守 |
| sel 位置記憶が category rename 時に無効化 | L | L | category は 6 固定（index 0-5、enum 的扱い）、動的 enumerate は将来工数で対応 |
| 旧 flat 実装 rename で既存 smoke が壊れる | M | H | Step 1 で rename 後すぐに全 smoke 実行して確認、`HC_HC_CONFIG_FLAT_NAVIGATION=true` で確認 |

---

## 8. 影響範囲

- **修正ファイル（1 件）:** `.claude/scripts/hc-config.sh`（推定 +100-200 LOC、L1160-L1425 書き換え）
- **新規 env:** `HC_HC_CONFIG_FLAT_NAVIGATION`（`true` で旧 1 階層）
- **不変:** `.claude/lib/hc-config-metadata.sh`、`harness-config.yml`、smoke 既存 case のインターフェース
- **smoke 拡張（Step 6）:** `hc-config-tui-smoke.sh` に category navigation 確認 case 追加（非 TTY pipe 経由 fake sequence は困難なため、unit 関数テスト方式）

---

## 9. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-28 | — | 起案（user 承認待ち） |
| 2026-05-29 | user | 承認（3 確認ポイントは採用案 default で進行: sel 記憶 = eval scalar 7 var / 旧 flat = rename 保持 + env fallback / smoke = unit 関数テスト方式） |

---

## 10. 関連

- 設計元: [`docs/draft/hc-config-interactive-tui.md`](hc-config-interactive-tui.md) §3.3（2 階層 navigation 原設計）
- 実装先: [`.claude/scripts/hc-config.sh`](../../.claude/scripts/hc-config.sh) L1160-L1425
- metadata: `.claude/lib/hc-config-metadata.sh`
- smoke: `.claude/tests/hc-config-tui-smoke.sh`
- 関連タスク: task-48（TUI 化）、task-49（`--list` 説明列拡張）
