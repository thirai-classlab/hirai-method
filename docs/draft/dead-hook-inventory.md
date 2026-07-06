<!--
task-21 W2.4 frontmatter (機械可読、draft-flow-guard.sh / harness-audit が読む):
approval_required: true
approved_at:
approved_by:
retroactive: false
-->
---
slug: dead-hook-inventory
title: 死蔵 hook 3 件の個別判定 + enforcement_matrix 登録 (slip-detector 温存 / asana-prompt toggle 新設 / mode-enforce 維持)
created_at: 2026-07-06
status: 📝 未承認
related: install-immediately-usable-redesign-20260618 §5 P2-4 (W1-1) / §11.3 R3
---

# 死蔵 hook 3 件の個別判定 + enforcement_matrix 登録 (P2-4 / W1-1)

**ステータス:** 📝 **draft（2026-07-06 起案、user 承認待ち）**
**起点:** master roadmap [install-immediately-usable-redesign-20260618](./install-immediately-usable-redesign-20260618.md) §5 P2-4 (batch planning 経路 B) + §11.3 R3 (task-97 の残 scope 前提)
**前提:**
- Phase 1 完遂 (task-85 で `--preset` opt-in + advisory `disabled_reason` 追記済、`harness-config.yml:479-544` に 8 guard 登録済 = draft/task/workflow/gateguard + review_required_{design,test,module,system})
- HOTFIX-1/2 で `harness-config.local.yml` 生成 + `hc-config.sh` local 統合完了
- `enforcement-mismatch-smoke.sh` (`.claude/tests/enforcement-mismatch-smoke.sh`) が matrix parse + docs_claim vs feature toggle 実値の mismatch 検出 SSoT

**関連 rule / fixture:**
- `.claude/CommonRules.md` § Design Constraints「enforcement は preset で明示制御 (task-70 Phase 2)」
- `.claude/hooks/dispatcher-manifest.tsv` (channel / feature_key SSoT)
- `.claude/hooks/session-start-wrapper.sh:39-50` (DEFAULT_HOOKS 一覧、mode-enforce + mode-asana-prompt 配線)

---

## §1. 背景 / 課題サマリ

master roadmap §5 P2-4 (W1-1) は「死蔵 hook 棚卸し (slip-detector / mode-asana-prompt / mode-enforce 個別判定)」として **I2 (Dispatcher-Only Hook) invariant の完全化** を目的とする。addendum §11.3 R3 で「P2-6 (#97) の残 scope は matrix 未登録 hook の追加登録 (3 件) + sessionstart 系検証拡張に限定、順序制約: #97 は #95 完了後に着手 (残 hook 集合が #95 で確定するため)」と明文化された。**本 task (#95) は #97 が拡張対象を確定するための前提として 3 hook を個別判定する。**

現状の 3 hook 別 status (evidence 実測):

| # | hook | 現状 | 実 fire 実績 |
|---|---|---|---|
| **H1** | `tool-call-slip-detector.sh` (Stop) | dispatcher-manifest 登録済 (`dispatcher-manifest.tsv:27` `Stop / 5 / feature_key=tool_call_slip_detect / advisory / 5s`)、feature toggle `feature_tool_call_slip_detect_enabled: false` (`harness-config.yml:375`、2026-06-01 誤検出 loop 調査で OFF)、**matrix 未登録** | bypass.log に **VIOLATION 15+ / ECC_TOOL_CALL_SLIP_OFF 5+ (2026-06-01)** = fire 実績あり、`feedback_multi_tool_block_serialization_failure` の唯一の機械検出器 |
| **H2** | `mode-asana-prompt.sh` (SessionStart) | session-start-wrapper `DEFAULT_HOOKS` 経由配線 (`session-start-wrapper.sh:47`)、**feature toggle 不在** (grep 0 hit `config-loader.sh` / `hc-config.sh`)、**matrix 未登録** | `mode.yml` `asana_enabled: true/false/unset` を `load_asana_enabled` (`lib/mode-loader.sh:50-75`) で読み、unset 時のみ system-reminder 注入 (通常 no-op)。log 出力なし = 実効性判定不能 |
| **H3** | `mode-enforce.sh` (SessionStart) | session-start-wrapper 経由配線 (`session-start-wrapper.sh:44`)、feature toggle `feature_loop_mode_enforcement_enabled: true` **loop-confirmation-detector / loop-auto-progress-reminder と共有** (`harness-config.yml:365`)、**matrix 未登録** | Loop モードのみ 1 行 pointer reminder を注入 (task-73 案 B)。共有 group 全体で bypass.log 35 fire (loop-confirmation-detector VIOLATION + loop-auto-progress-reminder) = **group 単位で fire 実績あり** |

**核心課題:**
1. **docs claim ↔ effective state の可視性欠落** — 3 hook いずれも `hc-config.sh --summary` の enforcement_matrix section に登場せず、consuming repo で「本 hook が生きているか死んでいるか」を CLI 一発で判定不能。docs / config drift の meta 検出器 (`enforcement-mismatch-smoke.sh`) からも対象外
2. **feature toggle 非対称 (H2)** — 3 hook 中 H2 のみ feature toggle 皆無。統一 pattern (yml key + config-loader default + `is_feature_enabled` check) 未達 = CommonRules § Design Constraints「機能 on/off は yml feature toggle で集中管理」違反
3. **H1 の意図的 OFF が構造上 unreachable** — feature toggle が false 固定で SSoT に advisory 中身が書けず、consuming repo が「なぜ OFF か」を CLI で辿れない
4. **#97 の scope 不安定** — H1-H3 の判定 (温存 / toggle 新設 / 維持) が未確定な間、P2-6 の「matrix 全 hook 拡張」対象集合が算定できない (addendum §11.3 R3 順序制約の根拠)

---

## §2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | **本採用**: H1 温存 + matrix 登録 (docs_claim=advisory、harness-dev disabled_reason 明記) / H2 `feature_asana_prompt_enabled` 新設 (mode.yml `asana_enabled` と直交、feature 3 点 set 適用) + matrix 登録 / H3 `feature_loop_mode_enforcement_enabled` に aggregate matrix 登録 (3 hook 共有 group) + 新 smoke `dead-hook-inventory-smoke.sh` | 1d | (1) 3 hook 全て CLI 可視化 (2) H2 の 3 点 set 完備で規範適合 (3) #97 の残 scope が確定 (4) H1 の disabled_reason が matrix SSoT に定着 (5) 既存 fire 実績 (H1 VIOLATION 15+ / group 35) を根拠に温存判断が smoke で machine-check される | (a) yml +40 行程度 (advisory 6 preset 期待 + disabled_reason) (b) H2 は 3 file 変更 (yml / config-loader / hook) |
| **B** | H1-H3 全 削除 (dead hook として撤去)、mode.yml `asana_enabled` prompt は他 hook (session-help-surface) に merge | 0.7d | code 削減、複雑度低下 | **却下**: (1) H1 は fire 実績 15+ で `feedback_multi_tool_block_serialization_failure` 唯一の機械検出器 = 死蔵ではない (2) H3 は Loop mode reminder の SSoT、削除で Loop 遵守事項 5 層強制機構 (`modes.md`) が 4 層に退化 (3) H2 削除で asana 未決の user prompt path が失われ、subscbase-api 型事案再発リスク |
| **C** | H1-H3 個別判定は同意、ただし matrix 登録は **P2-6 (#97) に一括委譲**、本 task は判定判断と `disabled_reason` 文言確定のみ | 0.4d | scope 極小 | **却下**: #97 の scope が確定しないまま残る (addendum R3 順序制約と自己矛盾)、advisory 追記自体は #97 で行うにせよ「判定 → 登録」の 2 step 分離が意味なく手戻り増加。addendum §11.3 R3 明示「#97 draft 起案は #95 完了後」= 登録 scope 内包が前提 |
| **D** | H2 だけ toggle 新設せず「常時 no-op path」に降格 (mode.yml `asana_enabled: unset` のみ発火の現状仕様を明文化して matrix advisory 登録) | 0.6d | H2 変更最小 | **却下**: 「機能 on/off は yml feature toggle で集中管理」規範に非適合。将来 `HC_FEATURE_ASANA_PROMPT_ENABLED=false` で個別無効化したい consuming repo が env override 経路を持てない |

→ **案 A を推奨**。理由: addendum §11.3 R3 の順序制約 (#97 前に #95 完了) を満たしつつ、3 hook の生死判定が matrix に SSoT 化され、#97 が「matrix 未登録 hook の残集合」を機械的に列挙可能になる唯一の案。

---

## §3. 採用案の詳細設計

### Goal (Task = Phase = 1 Goal)

`.claude/harness-config.yml` の `enforcement_matrix` に 3 新規 entry (`tool_call_slip_detect` / `asana_prompt` / `loop_mode_enforcement`) を追加、H2 用 feature toggle 3 点 set (`feature_asana_prompt_enabled`) を新設、`.claude/tests/dead-hook-inventory-smoke.sh` を新設し「3 hook 個別判定結果が matrix に登録され、fire 実績 log / feature toggle 現値 / 現 preset 期待値が整合する」ことを機械保証する。

### 3.1 matrix 追加 entry の詳細 (cross-file 契約 SSoT)

**SSoT 事前明示** (addendum §11.3 R5 準拠、id / symbol / API 名 / 所有者 file):

| 契約 id | symbol / key | 所有者 file | consumer file |
|---|---|---|---|
| C-M1 | `enforcement_matrix.tool_call_slip_detect` | `.claude/harness-config.yml:544-` | `hc-config.sh --summary` / `enforcement-mismatch-smoke.sh` / `dead-hook-inventory-smoke.sh` |
| C-M2 | `enforcement_matrix.asana_prompt` | 同上 | 同上 |
| C-M3 | `enforcement_matrix.loop_mode_enforcement` | 同上 | 同上 |
| C-T1 | `feature_asana_prompt_enabled` (yml key) | `.claude/harness-config.yml` §Feature Toggles | `mode-asana-prompt.sh` 冒頭 `is_feature_enabled asana_prompt` |
| C-T2 | `HC_FEATURE_ASANA_PROMPT_ENABLED` (env default) | `.claude/hooks/lib/config-loader.sh:~333` | 同上 |

#### 3.1.a `tool_call_slip_detect` matrix entry

```yaml
tool_call_slip_detect:
  feature_key: feature_tool_call_slip_detect_enabled
  docs_claim: advisory
  events: [Stop]
  presets: {advisory: false, team-default: true, strict: true, harness-dev: false}
  disabled_reason:
    # LOW-22 fix: summary 主張 + pointer 分離 (fire 実績数値は disabled_reason に埋め込まず追跡先を pointer 化)
    # bypass.log GC (P3-2 task-99 で 30 日 GC 実装予定) 後も原論拠が追跡可能な構造
    harness-dev: "誤検出ループが slip 体験の主因と判明 (詳細: `git log --all --grep=slip-detector` + docs/tasks/task-95-*.md §DoD 補足の fire 実績 table)、ハーネス自身の開発 turn で false-positive block が過剰"
    advisory: "advisory preset は warn 中心運用のため slip 自動 block は過剰 (詳細: docs/INVENTORY.md §hook 分類表)"
```

**根拠**: docs_claim は `.claude/hooks/tool-call-slip-detector.sh:29` および `development-process.md` § 「多数 fan-out」 が「事後検出は tool-call-slip-detector.sh (Stop hook) が... `{decision:block}` で次 turn 自己是正を注入」と説明 = **advisory** (BLOCK 主張ではなく `decision:block` は "次 turn 是正 context 注入" semantics)。fire 実績 15+ VIOLATION は消えていない事実として保存。

#### 3.1.b `asana_prompt` matrix entry

```yaml
asana_prompt:
  # advisory guard (preset 直交、asana 利用有無は project 属性で決定、MED-4 fix)
  # 全 preset true は「本質的に disable する場面なし」ではなく「project 単位で env override 運用」の意味
  feature_key: feature_asana_prompt_enabled
  docs_claim: advisory
  events: [SessionStart]
  presets: {advisory: true, team-default: true, strict: true, harness-dev: true}
  disabled_reason:
    # 現時点で全 preset true のため disabled_reason 不要 (enforcement-mismatch-smoke は全 preset true なら OK)
    # consuming repo で asana 排除運用は env `HC_FEATURE_ASANA_PROMPT_ENABLED=false` で無効化 (preset 変更不要)
```

**根拠**: hook は Loop / Normal 両モードで動き、`mode.yml asana_enabled=unset` の 1 セッション 1 回のみ system-reminder を出す設計 (`mode-asana-prompt.sh:33-58`)。asana 利用有無は project 属性 = preset とは直交 → 全 preset で ON default が自然。consuming repo で asana 完全排除したい場合は env `HC_FEATURE_ASANA_PROMPT_ENABLED=false` で無効化。

**MED-17 fix (docs_claim=advisory schema 拡張の verify + docs 反映)**: 既存 enforcement_matrix 8 guard (`harness-config.yml:479-543`) は全て `docs_claim: block` 明示のため、advisory guard の登録は既存 SSoT semantics を「block-only」→「block + advisory 併存」へ拡張する変更。`enforcement-mismatch-smoke.sh` Case 3 / Case 5 は `docs_claim=block` のみを判定対象とするため advisory guard は自動 pass (skip 相当) が正しい semantics = Step 3 (smoke) の DHI-6 で dogfood verify (asana_prompt entry を追記 → smoke 全 PASS で advisory skip 動作を機械検証)。**新 case 追加案 (DHI-7)**: 「advisory guard は disabled_reason 不要 = Case 6 で advisory 系列を明示 skip 対象と assert」を Step 3 smoke に追加。**docs 反映義務 (Step 5 に必須項目化)**: (a) `docs/INVENTORY.md` matrix guard 表に advisory guard 分類を新設、(b) `.claude/rules/workflow.md` preset aware 記述に「advisory guard は enforcement-mismatch-smoke 対象外」注記追加、(c) preset_orthogonal field 昇格 (task-70 領域) を §8 副産物 candidate に追加 entry。

#### 3.1.c `loop_mode_enforcement` matrix entry (aggregate = 3 hook 共有 group)

**採用判定 (task-97 §3 L143 の判定委譲を受けて本 draft = task-95 が確定)**: `docs/draft/enforcement-matrix-full-hook-expansion.md:143` (task-97 draft) は「`mode_enforce` の集合登録判定は task-95 が判定 (案 a 集合 1 entry / 案 b 個別 3 entry)」と明示委譲している。本 draft は **案 a (集合 1 entry + `hooks_covered` sub-field)** を採用する。理由: (1) `feature_loop_mode_enforcement_enabled` は 3 hook 共有 SSoT (現構造の写像) で drift 余地最小、(2) 個別 3 entry 化は同一 toggle を 3 度登録することになり `docs_claim` / `presets` の同期義務が 3 倍化、(3) fire 実績も group 単位 (bypass.log 35 fire を group aggregate で観察) で既に集約管理されている。

```yaml
loop_mode_enforcement:
  feature_key: feature_loop_mode_enforcement_enabled
  docs_claim: advisory
  events: [SessionStart, Stop, SubagentStop]
  hooks_covered: [mode-enforce, loop-confirmation-detector, loop-auto-progress-reminder]
  presets: {advisory: false, team-default: true, strict: true, harness-dev: true}
  disabled_reason:
    advisory: "advisory preset は個人実験 / PoC 用に Loop 遵守事項 reminder を最小化"
```

**根拠**: 3 hook が単一 feature key を共有する既存構造 (`harness-config.yml:365` comment + `mode-enforce.sh:11-15` + `loop-auto-progress-reminder.sh:33-36`) をそのまま matrix に写像。`hooks_covered` は既存 matrix schema に無い field だが nested parser で無視されるため後方互換 (`enforcement-mismatch-smoke.sh:63-71` の `_matrix_guards` awk が top-level guard 名のみ抽出、sub-field は本 smoke の判定に不使用)。表示補助として `hc-config.sh --summary` の将来拡張点。

**schema 拡張の副産物性 (task-70 領域)**: `hooks_covered` は task-70 (enforcement_matrix schema 定義元) が定めた 5 field (`feature_key` / `docs_claim` / `events` / `presets` / `disabled_reason`) 集合に含まれない **非公式 sub-field** である。現行 `enforcement-mismatch-smoke.sh:63-71` awk parser は top-level guard 名のみ抽出するため後方互換だが、将来 parser 拡張 (例: `em_field` が sub-field も parse するようになる) 時に「documented mismatch」semantics (docs_claim vs 実効値の乖離判定) と `hooks_covered` sub-field の相互作用が未定義になる。この schema 拡張の正式化 (top-level schema へ `hooks_covered` を optional field として昇格 + parser 契約明記) は本 draft の実装 scope 外 = **task-70 系列の別 task で追跡**する副産物 candidate として §8 に entry 追加する。task-97 側 (`enforcement-matrix-full-hook-expansion.md` §3) も本判定を受けて他 hook を集合登録する際に `hooks_covered` 記法を採用する場合は同 schema 拡張追跡 task の完了を前提とすること。

### 3.2 `feature_asana_prompt_enabled` 3 点 set (H2)

CommonRules § Design Constraints「新 hook / command 追加時は (1) yml に 1 key 追加 (2) hook 冒頭で feature check (3) env 上書きは `HC_FEATURE_XXX_ENABLED` で可能、の 3 点 set を必須」に完全準拠:

1. **yml key 追加** (`.claude/harness-config.yml:365-389` の Feature Toggles ブロック末尾):
   ```yaml
   feature_asana_prompt_enabled: true                # mode-asana-prompt (session start Asana 未決 hearing)
   ```

2. **config-loader.sh default** (`.claude/hooks/lib/config-loader.sh:342` 直後に追加):
   ```bash
   HC_FEATURE_ASANA_PROMPT_ENABLED="true"
   ```
   (export 群 `config-loader.sh:700-701` 相当行にも `HC_FEATURE_ASANA_PROMPT_ENABLED` 追記)

3. **hook 冒頭 check** (`.claude/hooks/mode-asana-prompt.sh:20` 前後、mode-loader source 前):
   ```bash
   # config-loader を先に load して is_feature_enabled を利用可能に
   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
   if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
     source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
   fi
   if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled asana_prompt; then
     exit 0
   fi
   ```

**fail-open 契約**: config-loader load 失敗時は `is_feature_enabled` unset → hook は現状動作 (asana 未決 hearing) を維持。set flags は `set -u` のみ (既存 file top と整合、subshell 化なし)。

### 3.3 新規 smoke `dead-hook-inventory-smoke.sh`

`.claude/tests/dead-hook-inventory-smoke.sh` を新設、`enforcement-mismatch-smoke.sh` の subshell isolation pattern (`set -uo pipefail` file top + case ごとに subshell) を踏襲。判定 case:

| case | 目的 | 検証手段 |
|---|---|---|
| **DHI-1** | 3 新 matrix entry の存在確認 | `awk '/^enforcement_matrix:/,/^[^ ]/' harness-config.yml \| grep -Ec '^  (tool_call_slip_detect\|asana_prompt\|loop_mode_enforcement):' == 3` |
| **DHI-2** | 3 entry の必須 field (`feature_key` / `docs_claim` / `events` / `presets`) を SSoT lib `enforcement-matrix-parse.sh` (`em_field`) で全件抽出 → 空文字禁止 | `em_field harness-config.yml tool_call_slip_detect feature_key` 等 12 呼出 (3 hook × 4 field) が非空 |
| **DHI-3** | `feature_asana_prompt_enabled` の 3 点 set (yml / config-loader / hook check) 全て grep 存在 | 3 grep が各 1 件以上 hit |
| **DHI-4** | H1 fire 実績確認 (bypass.log で `tool-call-slip-detector` VIOLATION が 1 件以上) | `grep -c 'tool-call-slip-detector.*VIOLATION' bypass.log >= 1` (log 不在時 skip、fail-open) |
| **DHI-5** | H3 group fire 実績確認 (`loop-confirmation-detector` OR `loop-auto-progress-reminder`) | 同上 log grep、1 件以上 |
| **DHI-6** | `enforcement-mismatch-smoke.sh` を invoke して regression 0 (既存 8 guard + 新 3 guard = 11 guard 全 PASS) | subprocess exit 0 |

**fail-open 契約**: bypass.log 不在時 (fresh install / GC 後) は case DHI-4 / DHI-5 を skip して PASS 扱い (log 不在 = fire 実績 0 は「まだ検証機会がない」であり dead-hook 判定材料にはならない、mutation probe 対象は #99 P3-2 で扱う)。

---

## §4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| matrix nested parser drift (`hooks_covered` sub-field を将来 parser が拒否 or「documented mismatch」semantics と相互作用) | L | M | 現行 `enforcement-mismatch-smoke.sh` の `_matrix_guards` は top-level のみ抽出 (実測 `:63-71`)、sub-field は無視される後方互換。**schema 拡張の正式化は task-70 領域** (task-70 = enforcement_matrix schema 定義元) のため、本 draft §8 副産物 candidate (c) に「`hooks_covered` optional field の top-level schema 昇格 + `enforcement-matrix-parse.sh` の parser 契約明記」を entry 化し、task-70 系列の別 task で追跡する。それまでは本 sub-field は非公式 sub-field として本 draft の実装専用に localize |
| H2 の 3 点 set 追加で `mode-asana-prompt.sh` の set flags が既存 caller に leak | L | M | 既存は `set -u` のみ (file top:16)。config-loader source は best-effort (`\|\| true`)、subshell 化不要。CLAUDE.md Critical Lessons HIGH 「file-top errexit 禁止」に既に準拠 |
| `enforcement-mismatch-smoke.sh` が新 3 guard を機械照合するとき advisory docs_claim を FAIL 判定 | M | H | smoke ロジックは既に `docs_claim=block` のみ FAIL 対象 (`enforcement-mismatch-smoke.sh:1-15` 目的節)。advisory guard は mismatch 検出対象外 → DHI-6 regression 0 で担保 |
| H1 disabled_reason に「fire 実績 15+」を書くと将来 log GC 後に文言 stale 化 | M | L | disabled_reason は「判断時点の理由」を書く契約 (既存 harness-dev reason も同様)。GC 後の再検証は #99 P3-2 (observability 30 日 GC) の scope |
| 3 hook が session-start-wrapper 並列実行下で新 feature check が遅延 | L | L | wrapper は per-hook timeout 5s (`session-start-wrapper.sh:60`)、config-loader source は < 100ms、余裕あり |

---

## §5. 完了条件 (DoD、全項目 検証コマンド付き)

- [ ] **DoD-1**: `enforcement_matrix` に 3 新 entry 存在 (§3.1.c 採用判定「案 a 集合 1 entry」前提の期待値 = 3。将来 task-70 系列で `hooks_covered` を top-level schema 化し個別 3 entry 化する場合は 5 に change する = schema 拡張追跡 task 側で更新)
  - 検証: `awk '/^enforcement_matrix:/,/^[^ ]/' .claude/harness-config.yml | grep -Ec '^  (tool_call_slip_detect|asana_prompt|loop_mode_enforcement):'` が **3**
- [ ] **DoD-2**: 3 新 entry の必須 field (`feature_key` / `docs_claim` / `events` / `presets`) が全て非空
  - 検証: `bash .claude/tests/dead-hook-inventory-smoke.sh` case DHI-2 が PASS
- [ ] **DoD-3**: `feature_asana_prompt_enabled` の 3 点 set 完備
  - 検証: `grep -c '^feature_asana_prompt_enabled:' .claude/harness-config.yml` が **1**
  - 検証: `grep -c '^HC_FEATURE_ASANA_PROMPT_ENABLED=' .claude/hooks/lib/config-loader.sh` が **1**
  - 検証: `grep -c 'is_feature_enabled asana_prompt' .claude/hooks/mode-asana-prompt.sh` が **1**
- [ ] **DoD-4**: `hc-config.sh --summary` に 3 新 guard 名が表示
  - 検証: `bash .claude/scripts/hc-config.sh --summary | grep -Ec '(tool_call_slip_detect|asana_prompt|loop_mode_enforcement)'` が **3 以上**
- [ ] **DoD-5**: 新 smoke 全 PASS
  - 検証: `bash .claude/tests/dead-hook-inventory-smoke.sh; echo $?` が **0** (6 case 全 PASS)
- [ ] **DoD-6**: 既存 `enforcement-mismatch-smoke.sh` regression 0
  - 検証: `bash .claude/tests/enforcement-mismatch-smoke.sh; echo $?` が **0**
- [ ] **DoD-7**: `run-all-smokes.sh` に新 smoke 登録 (parity カテゴリ) + 全体 regression 0
  - 検証: `bash .claude/tests/run-all-smokes.sh; echo $?` が **0**
- [ ] **DoD-8**: `HC_FEATURE_ASANA_PROMPT_ENABLED=false bash .claude/hooks/mode-asana-prompt.sh < /dev/null` が silent exit 0 (feature toggle 動作確認)
  - 検証: `HC_FEATURE_ASANA_PROMPT_ENABLED=false bash .claude/hooks/mode-asana-prompt.sh < /dev/null; echo $?` が **0** かつ stdout 空
- [ ] **DoD-9**: docs 反映 (`README.md` / `.claude/CommonRules.md` § Design Constraints の該当行 pointer 更新)
  - 検証: `grep -c 'dead-hook-inventory' README.md docs/INVENTORY.md 2>/dev/null` が **1 以上** (少なくとも 1 file で参照)

---

## §6. Step 分解 (採用 6 条準拠、1 Goal + N Steps)

> 採用 6 条 4 の最終 3 Steps 固定 = テスト設計レビュー / テスト合格 / リファクタリング。

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | `harness-config.yml` enforcement_matrix に 3 新 entry (tool_call_slip_detect / asana_prompt / loop_mode_enforcement) 追加 + 各 disabled_reason 記入 | 0.5h | — |
| 2 | 🔲 | `feature_asana_prompt_enabled` 3 点 set 実装 (yml key / config-loader default+export / hook 冒頭 check) | 0.5h | Step 1 |
| 3 | 🔲 | `.claude/tests/dead-hook-inventory-smoke.sh` 新設 (DHI-1〜6 の 6 case、`enforcement-mismatch-smoke.sh` の subshell isolation pattern 踏襲) | 1.0h | Step 1, 2 |
| 4 | 🔲 | `run-all-smokes.sh` に新 smoke 登録 (parity カテゴリ、`_get_smoke_category` L46-89 拡張) + `hc-config.sh --summary` に新 3 guard 表示確認 | 0.5h | Step 3 |
| 5 | 🔲 | docs 反映 (`README.md` / `docs/INVENTORY.md` に P2-4 完遂 pointer、`.claude/CommonRules.md` は該当なし = skip) | 0.3h | Step 4 |
| 6 | 🔲 | **(テスト設計レビュー)** reviewer 動的選定 `min ≤ N ≤ max` (`hc-config.sh --get review_min_count_test/review_max_count_test` で確認、`tdd-guide` / `test-automator` / `qa-expert` / `pr-test-analyzer` base + config-domain 加味)。**プロジェクト整合性 + 他 task 影響確認 必須** (workflow.md §「reviewer prompt 共通規約」5 項目、addendum R5 の 7 checklist を prompt に含める) | 0.5h | Step 5 |
| 7 | 🔲 | **(テスト合格)** 全 smoke PASS (DoD-2〜7 全項目 検証コマンド実行) | 0.5h | Step 6 |
| 8 | 🔲 | **(リファクタリング)** 3 観点 (持続可能性 / 汎用性 / 非冗長化) 判定。matrix entry の共通構造抽出余地 (advisory guard の default field 集約 lib) / smoke case DHI-2 の 12 field 抽出の loop 化 を検討。不要なら `skip: <reason>` 明示 | 0.3h | Step 7 |

**合計**: 4.1h (roadmap P2-4 見積 1 day 内)

---

## §7. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-07-06 | (pending) | draft 起案、user 承認待ち |

---

## §8. 関連

- master roadmap: [install-immediately-usable-redesign-20260618.md](./install-immediately-usable-redesign-20260618.md) §5 P2-4 / §11.3 R3
- addendum §11.3 R5 起案 checklist の反映箇所: 本 draft §3.1 cross-file 契約 SSoT table (契約 id 5 件) / §3.3 fail-open 契約 / §5 DoD 全項目検証 command / §6 docs 反映を Step 5 に明示
- 依存元 (task-88): PR #71 で SessionStart `hc-config.sh --summary` 全文注入完了 → 本 task 完了後、新 3 guard が summary に自動反映 (追加実装不要、DoD-4 で確認)
- 後続 (task-97 / P2-6): 本 task 完了後に「matrix 未登録 hook の残集合」が確定、#97 が全 hook 拡張へ着手 (addendum R3 順序制約)。**§3.1.c 採用判定 (案 a 集合 1 entry) は task-97 §3 L143 の判定委譲を受けての確定** — task-97 draft 側 (`enforcement-matrix-full-hook-expansion.md:143`) は本判定を Read して他 hook を集合登録する際も `hooks_covered` 記法を採用可能とする (schema 拡張追跡 task の完了を前提とすること)
- 副産物 candidate: 本 draft 実装中に (a) matrix advisory 共通 template lib 抽出候補 / (b) smoke DHI-4/5 の bypass.log path SSoT lib 化候補 / **(c) enforcement_matrix schema 拡張 (`hooks_covered` optional field の top-level schema 昇格 + `enforcement-matrix-parse.sh` の parser 契約明記、task-70 系列の別 task 起案候補、reviewer finding 由来)** が発生予測 → next-actions.md に entry 追加 (本 draft 承認後 main agent が実行)
