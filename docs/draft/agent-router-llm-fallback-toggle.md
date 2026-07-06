<!--
task-21 W2.4 frontmatter (機械可読、draft-flow-guard.sh / harness-audit が読む):
approval_required: true
approved_at:
approved_by:
retroactive: false
-->
---
slug: agent-router-llm-fallback-toggle
title: agent-router LLM fallback default OFF + yml toggle 明示化 (P2-5/W1-5、I7 triplet 遵守)
created_at: 2026-07-06
status: 📝 未承認
related: install-immediately-usable-redesign-20260618 §5 P2-5 (task #96) / §11.3 R5 起案 checklist / §11.3 R2 fast/full smoke 分類 / I7 Config-Consumer-Smoke Triplet
---

# agent-router LLM fallback default OFF + yml toggle 明示化 (P2-5/W1-5)

**ステータス:** 📝 **draft (2026-07-06 起案、user 承認待ち)**
**起点:** master roadmap [install-immediately-usable-redesign-20260618](./install-immediately-usable-redesign-20260618.md) §5 Phase 2 P2-5 (list.md #96) + §3 invariant I7 (Config-Consumer-Smoke Triplet) の Phase 2 定着
**前提 (完了済、本 draft の scope 外):**
- **task-81 (agent-router-suggest 配線復活)**: `.claude/hooks/agent-router-suggest.sh` が dispatcher-manifest.tsv 38 行目 (`UserPromptSubmit / order 3 / feature_key=agent_router_suggest / channel=advisory / timeout=5`) で配線済。feature toggle `feature_agent_router_suggest_enabled` は `.claude/harness-config.yml:388` で SSoT、`.claude/hooks/lib/config-loader.sh:342` で default `true` 定義、`is_feature_enabled agent_router_suggest` (hook 冒頭 L49) で gate 済
- **既存 LLM fallback 実装**: `.claude/skills/agent-router/router.py` L62-67 (`DEFAULT_LLM_THRESHOLD=0.5` / `DEFAULT_LLM_BUDGET_USD=0.05` = per-call cost cap) + L985-1028 argparse で 6 env var (`AGENT_ROUTER_LLM_FALLBACK` / `_THRESHOLD` / `_MODEL` / `_TIMEOUT` / `_MAX_ATTEMPTS` / `_BUDGET_USD`) 受領。hook (`agent-router-suggest.sh` L80-88) は `AGENT_ROUTER_LLM_*` env を **hook 内で明示 forward / export / unset せず**、`python3 "${ROUTER_PY}" "${ROUTER_ARGS[@]}"` 起動時に **bash 標準の parent env 継承**で router.py が受領する (hook 自身は `ROUTER_ARGS=(--stdin --no-record)` のみ組立、L82-84 コメントは「hook is just passing env through subprocess」の意味で明示コード無し = 継承依拠)
- 既存 smoke: `.claude/tests/agent-router-suggest-wiring-smoke.sh` (188 行、9 case、wiring / feature toggle ON-OFF / prompt マッチ差 を検証、**LLM fallback 経路は未検証**)

**関連 rule:**
- master roadmap §3 I7 (yml key 追加は consumer + smoke を同 commit で揃える)
- master roadmap §11.3 R5 (Phase 2 draft 起案 checklist 7 項目)
- master roadmap §11.3 R2 (Phase 1 新設 smoke の fast/full × 5 category 分類)
- master roadmap §11.3 R6 (Phase 2 DAG: #96 → task-86 依存 / #97 は #95 依存)
- [`.claude/rules/task-management.md`](../../.claude/rules/task-management.md) §「開発開始時の必読義務」
- [`feedback_config_value_needs_consumer_and_smoke.md`](~/.claude/projects/-Users-t-hirai-work-hirai-method/memory/feedback_config_value_needs_consumer_and_smoke.md) (I7 起源)

---

## 1. 真因サマリ / 課題サマリ

agent-router の LLM fallback は現状「**env `AGENT_ROUTER_LLM_FALLBACK=on` が明示的に set された時のみ ON**」の env-only opt-in。実効値は `router.py:994` の `_env_truthy` 判定に閉じており、以下の 3 点で invariant I7 (Config-Consumer-Smoke Triplet、roadmap §3.1) を満たさない:

| # | 課題 | 現状証拠 |
|---|---|---|
| **C1** | **yml SSoT 不在**: LLM fallback の on/off・budget・threshold は `harness-config.yml` に 1 key も宣言されておらず、env でしか制御できない (`grep -n 'agent_router_llm' .claude/harness-config.yml` = 0 hit)。consuming repo は「LLM fallback がそもそも存在すること」を認知しづらく `hc-config.sh --list` にも現れない | `.claude/harness-config.yml:388` (`feature_agent_router_suggest_enabled` のみ、LLM fallback 系 0 key) |
| **C2** | **budget/threshold の default が hook 側 hardcode**: `router.py:62-67` の `DEFAULT_LLM_THRESHOLD=0.5` / `DEFAULT_LLM_BUDGET_USD=0.05` は `.py` 内 constant のみで、config-loader export に無く `hc-config.sh --get` 不能。project 単位で調整するには `.py` を直接編集するか各 hook 起動時に env を毎回 set する必要 | `router.py:62-67`、`config-loader.sh:342` (`HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED` のみ) |
| **C3** | **smoke 未整備**: 既存 `agent-router-suggest-wiring-smoke.sh` は wiring / feature toggle ON-OFF を検証するが、**LLM fallback default OFF / opt-in ON / budget 超過 / threshold 動作 / env 互換** は 1 case も無い。**I7 triplet の "smoke" 要素が欠落**、Phase 1 で確立した「consumer + smoke を同 task で揃える」規範 ([[feedback_config_value_needs_consumer_and_smoke]]) を Phase 2 で dogfood できていない | `.claude/tests/agent-router-suggest-wiring-smoke.sh:47-50` (LLM 関連 case 不在) |

**核心論点 (C0)**: 「LLM fallback をどう明示するか」に **3 方向** の選択肢がある。(a) env-only 維持で規範 rule に「default OFF」と書くだけ (case-C2 未解消)、(b) **yml SSoT + env 互換層** (推奨、下記 §2 案 B)、(c) yml SSoT + env 廃止 (breaking change)。roadmap §11.3 R5 checklist と I7 は (b) を強く示唆する。

**§11.3 R2 の smoke 分類反映**: 本 task で新設する `agent-router-llm-fallback-smoke.sh` は **behavior / fast** に分類 (grep + hook 単体起動 + env 差分の < 3 秒 smoke)。roadmap §11.3 R2 の Phase 1 新設 smoke 表に整合。

**§11.3 R5 checklist (Phase 2 起案 checklist)**: 本 draft は 7 項目を以下で満たす:
1. draft 引用は行番号を最小限に留め、grep 済 (`config-loader.sh:342` / `router.py:62-67, 985-1028` / `harness-config.yml:388` / `dispatcher-manifest.tsv:38`)
2. 並列 subagent 前提なし (単一 file 群の順次編集、§4.3 共有契約 table は yml key 名の SSoT 表として §4.1 に配置)
3. hook / lib の fail-open 契約を §4.5 に明記 (env 未 set → 既存 hardcode default / router.py fail-open exit 2 継承)
4. §6 DoD の全項目に検証コマンド併記
5. 依存記載は §7 Step で強度付き (`task-86` = **hard** dep = `hc-config.sh --get` 経由の局所読み込みに local.yml 反映が前提)
6. frontmatter の承認 field は先頭 HTML comment 1 箇所 SSoT、本文 §8 は frontmatter 参照 pointer 化 (7 draft 統一、addendum §11.3 R5 checklist f 項)
7. docs 反映 step (`docs/INVENTORY.md` yml key 表 / `harness-config.yml` inline comment / `.claude/rules/development-process.md` §「サブエージェント委譲」reviewer 制御 table 側の drift 確認) を §7 Step 4 に必須項目化

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | env-only 維持 + `.claude/rules/` に「LLM fallback は env `AGENT_ROUTER_LLM_FALLBACK=on` で opt-in、default OFF」と規範文書化のみ | 0.2d | 実装ゼロ | **却下**: I7 (consumer + smoke) 未達、`hc-config.sh --list` に現れず、budget/threshold の project 単位調整も `.py` 編集必要。roadmap §5 P2-5「yml toggle 明示化」の scope を満たさない |
| **B** | **yml 3 key 明示化 + hc-config-metadata TSV 登録 + hook を is_feature_enabled 参照に refactor + env 互換層維持 + I7 triplet smoke 新設** | 1.0d | (1) I7 triplet 完全遵守 (yml + consumer + smoke)、(2) env 既存動作を破壊せず (env set があれば env 優先)、(3) `hc-config.sh --get/--set` で project 調整可、(4) `--summary` で effective state 可視化 | inline comment + metadata TSV + smoke 3 point を同時更新する必要 (drift 余地) |
| **C** | yml SSoT + env 廃止 (breaking change) | 0.7d | SSoT 1 本化 | **却下**: 既存 `AGENT_ROUTER_LLM_*` env を使う CI / hook が存在した場合 (task-81 wiring 過去 commit 参照) silent break、opt-in feature を強制的に SSoT 化するのは roadmap §4.5 「BLOCK 教育 3 点提示」の教訓 (段階移行) と不整合 |
| **D** | 案 B の縮小版: **feature toggle 1 key のみ追加**、budget/threshold は env のみ据え置き | 0.5d | 最小変更 | **却下**: roadmap §5 P2-5 「3 key を yml 明示化」を満たさない、budget/threshold の default 値が SSoT 化されないため hc-config-metadata TSV 未登録 = `hc-config.sh --list` の対称性欠 |

**→ 案 B を推奨**。理由: I7 triplet 完全遵守 + env 互換層維持 + 3 key SSoT 化を単一 task で完結できる唯一の案。default `feature_agent_router_llm_fallback_enabled: false` (default OFF、opt-in) は roadmap §5 P2-5 の task 名 (「LLM fallback default OFF」) と一致。

---

## 3. 採用案の詳細設計 (yml SSoT + env 互換層)

### 3.1 追加する 3 yml key (SSoT: `.claude/harness-config.yml`)

| key | default | 意味 | consumer |
|---|---|---|---|
| `feature_agent_router_llm_fallback_enabled` | `false` | LLM fallback 機能全体の on/off (`agent_router_suggest` の子 toggle。親 toggle OFF なら本 key に関わらず LLM 呼出なし) | `.claude/hooks/agent-router-suggest.sh` (`is_feature_enabled agent_router_llm_fallback` で gate → true なら `AGENT_ROUTER_LLM_FALLBACK=on` を router に export) |
| `agent_router_llm_budget_usd_per_day` | `0.1` | **1 日あたり (UTC day)** の cost 累積上限 (USD)。超過検出時は当日 fallback を強制 disable + WARN 1 行注入 (**新規セマンティクス**) | 同 hook 内で `.claude/.workflow-state/agent-router-llm-budget/<YYYY-MM-DD>.usd` に累積、既存 `AGENT_ROUTER_LLM_BUDGET_USD` (per-call cap = router.py 側 `--max-budget-usd`) は **保持** (per-day と per-call 併存、per-call は router 側の既存 fail-safe) |
| `agent_router_llm_similarity_threshold` | `0.7` | keyword confidence が本値 **未満** の時のみ LLM fallback を発火 (default 0.7 に引き上げ = fallback 発火頻度を絞る、cost 保護) | 同 hook 内で `AGENT_ROUTER_LLM_THRESHOLD` env を上書き export (env 未 set の時のみ)、router.py L1000-1005 の default 0.5 を実行時 override |

**cross-file 契約 SSoT (§11.3 R5 checklist 2 対応、単一 task だが drift 予防で明示)**:
| symbol | 所有者 file | 型 | 参照者 |
|---|---|---|---|
| `feature_agent_router_llm_fallback_enabled` | `.claude/harness-config.yml` | bool literal | `config-loader.sh` (HC_ export) / `agent-router-suggest.sh` (`is_feature_enabled`) / metadata TSV / smoke |
| `agent_router_llm_budget_usd_per_day` | 同上 | float literal (0.0-∞) | 同上 |
| `agent_router_llm_similarity_threshold` | 同上 | float literal (0.0-1.0) | 同上 |

### 3.2 hc-config-metadata.sh TSV 登録 (SSoT: `.claude/scripts/lib/hc-config-metadata.sh`)

TSV `_hc_metadata_table` heredoc (L46-135) の末尾直前に 3 行追加。区切りは TAB、5 field (`key<TAB>category<TAB>description<TAB>effect<TAB>label_ja`):

| key | category | description | effect | label_ja |
|---|---|---|---|---|
| `feature_agent_router_llm_fallback_enabled` | `feature_toggle` | agent-router-suggest.sh の LLM fallback 子 toggle (keyword confidence が threshold 未満で router.py に `--use-llm-fallback` を渡すか) | false にすると LLM fallback が完全停止し keyword 結果のみで hint 判定される (cost 0 化)。true にすると threshold 未満で LLM 呼出が発生 | LLMフォールバック有効化 |
| `agent_router_llm_budget_usd_per_day` | `Gate/Confidence` | LLM fallback の 1 日あたり (UTC day) の cost 累積上限 (USD)。超過検出時は当日 fallback を強制 disable | 増やすと 1 日あたりの LLM 呼出許容量が増え hint 発火頻度が上がる。減らすと当日の早期 disable が発火し hint が抑制される | LLM日次予算USD |
| `agent_router_llm_similarity_threshold` | `Gate/Confidence` | keyword confidence が本値未満の時のみ LLM fallback を発火 (0.0-1.0、上げると発火頻度低下・cost 低下) | 上げると LLM fallback 発火が絞られ hint が保守的になる。下げると発火頻度が上がり cost が増える | LLM発火しきい値 |

### 3.3 `.claude/hooks/agent-router-suggest.sh` refactor (env 互換層維持)

現状 L80-88 は bash 標準の env 継承 (parent hook env → python3 subprocess) に依拠している。以下の順序で書き換え、**env 制御は `export <name>=<value>` の 1 mechanism に固定**する (`unset` は禁止 = 後述、inline `NAME=value cmd` 前置きも禁止 = router.py 起動時の可読性 + 意図の一貫性)。

**env 制御 mechanism の 3 択のうち採用 = `export`、却下理由の table**:

| mechanism | 例 | 採用可否 | 理由 |
|---|---|---|---|
| **`export <NAME>=<value>`** (採用) | `export AGENT_ROUTER_LLM_FALLBACK=on` | ✅ | (a) hook subprocess 内で subshell 抜けまで有効、(b) child python3 に確実に継承、(c) `unset` と違い明示的な意図 (on/off) が読める |
| `unset <NAME>` | `unset AGENT_ROUTER_LLM_FALLBACK` | ❌ | disable 時に「env 未 set 状態に戻す」意図となるが、router.py 内 `_env_truthy` 判定は「未 set = OFF」と「値 `off` = OFF」を同一視するため機能同値だが、**同 hook 内で複数箇所 disable/enable を切り替えたい場合に「未 set 状態」を維持できず**曖昧化する (§3.5 fail-open の巻き戻り経路と区別不能) |
| inline env prefix | `AGENT_ROUTER_LLM_FALLBACK=on python3 ...` | ❌ | 単一 python3 起動限定なら OK だが、本 hook では **前後の budget append** (§3.3 step 5) や `THRESHOLD` export と組み合わせて **前後行の意図の一貫性**が損なわれる (一部行のみ inline は grep しにくい) |

1. hook 冒頭 (L49 `is_feature_enabled agent_router_suggest` gate の直後、`THRESHOLD` 初期化前) に **子 toggle gate + env 互換層** を挿入。決定木は以下の 4 分岐で網羅:

    | yml (`HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED`) | env `AGENT_ROUTER_LLM_FALLBACK` の状態 | hook のアクション |
    |---|---|---|
    | `false` (default) | 未 set | (何もしない、router.py 側で default OFF = 現行動作) |
    | `false` | 明示 set 済 (`on` / `1` / `true` / `off` / 空文字を含む any) | `export` **せず** env を保持、stderr に WARN 1 行 (`[agent-router] WARN: yml=false but env AGENT_ROUTER_LLM_FALLBACK=<value> takes precedence (env 互換層)`) |
    | `true` | 未 set | `export AGENT_ROUTER_LLM_FALLBACK=on` (yml 意図を child に伝達) |
    | `true` | 明示 set 済 | `export` **せず** env を保持 (env 優先、既に user が明示的に上書きしている意図を尊重、WARN なし) |

    「env 明示 set 済」の判定は bash `${AGENT_ROUTER_LLM_FALLBACK+x}` (set済なら `x`、未 set なら空文字) で行う (値の空/非空ではなく **変数の宣言有無**を判定、`unset` 状態と `=""` 状態を厳密に区別)。

2. `AGENT_ROUTER_LLM_THRESHOLD` env 未 set (`${AGENT_ROUTER_LLM_THRESHOLD+x}` == 空) かつ **子 toggle 最終状態が ON** (= 上記 1 の結果 env = `on`/`1`/`true`/`yes`) → `export AGENT_ROUTER_LLM_THRESHOLD="${HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD}"` (config-loader export 由来の default 0.7 or local.yml override 値)。env 既 set は上書きせず (env 優先、既存動作維持)

3. **budget 累積 check**: **子 toggle 最終状態が ON** かつ `HC_AGENT_ROUTER_LLM_BUDGET_USD_PER_DAY` > 0 → `.claude/.workflow-state/agent-router-llm-budget/<UTC-YYYY-MM-DD>.usd` を読み、累積が上限超過なら **`export AGENT_ROUTER_LLM_FALLBACK=off`** で router.py 側 fallback を強制無効化 + WARN 1 行 stderr (`[agent-router] WARN: daily budget $<used>/$<limit> exceeded, LLM fallback disabled for today`)。fail-open で hook 自体は継続 (exit 0)、hint は keyword のみになる。**注意**: ここは env の user 明示 set の有無に関わらず「budget 超過は cost 保護のため yml < env より上位」= budget check の結果は必ず env を上書きする (§3.5 fail-open と直交する cost gate)

4. router.py 実行 (L88 の `python3 "${ROUTER_PY}" "${ROUTER_ARGS[@]}"`) → 実行後、返却 JSON に `llm_used: true` が含まれる場合、上記 budget file の同 UTC 日 file に **推定 cost** (router.py が返す `cost_usd` field、無ければ `AGENT_ROUTER_LLM_BUDGET_USD` per-call cap を上限 proxy として使用) を 1 行 append。集計は bash 3.2 互換 (`printf '%s\n'` で append、`awk -F: '{sum+=$1} END{print sum}'` で合計)

5. **hook 自身が subprocess で起動される** ため、上記 `export` は hook プロセス終了で自動的に消失する (parent shell = Claude Code 本体 shell への leak なし、subshell 化 `( export ...; python3 ... )` は不要)。ただし **hook 内で `source` される scripts (config-loader.sh 等) が同じ env を上書きする可能性**があるため、`export` は上記 4 step の logical order を厳守 (config-loader source は L45-48 で既に完了、その後に本 §3.3 の step 1-4 が入る前提)

### 3.4 config-loader.sh export 追加 (SSoT: `.claude/hooks/lib/config-loader.sh`)

L342 の `HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED="true"` 直後に 3 行追加 (default 定義):
```bash
HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED="false"
HC_AGENT_ROUTER_LLM_BUDGET_USD_PER_DAY="0.1"
HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD="0.7"
```
L700 付近の `export` 群にも同 3 変数を追加 (対称性、既存 pattern に整合)。

### 3.5 fail-open 契約 (§11.3 R5 checklist 3 対応、必須明記)

- **HC_ 未 export 時** (config-loader.sh source 失敗など): hook は既存 hardcode default (`AGENT_ROUTER_LLM_THRESHOLD=0.5` = router.py 側 default) を使用、hook 自体は exit 0 継続 (=既存動作)
- **budget file 破損 / 読み取り失敗**: hook は budget check を skip し WARN 1 行、hook 自体は exit 0 継続 (`export AGENT_ROUTER_LLM_FALLBACK=off` は実行せず、env の現状維持で router.py に委譲)
- **router.py exit 2 (internal error)**: 既存の `|| echo '{"fallback": true}'` (hook L88) で fail-open 維持、hint 出力なし exit 0
- **子 toggle ON かつ env `AGENT_ROUTER_LLM_FALLBACK=off` 明示 set**: env 優先 (§3.3 step 1 の 4 分岐 table の 4 行目に該当)、hook 側で `export` せず (env 互換の逆側 = opt-out env)
- **env leak 防止契約**: hook は subprocess として起動されるため、hook 内 `export` は hook プロセス終了で自動的に消失する (parent Claude Code shell への leak なし)。subshell 化 (`( export ...; python3 ... )`) は不要。ただし将来 hook が他 script を source する構造に変更される場合は subshell 化契約を再検討

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| yml default (`false`) を無視して既存 env で LLM 呼出継続 → user 意図と不一致 | M | M | 子 toggle 実装で「env 明示 set 有無」を判定 (`${AGENT_ROUTER_LLM_FALLBACK+x}`)、env 有りは WARN で通知 (§3.3 step 1 の 4 分岐 table 2 行目)。stderr WARN で気づける |
| hook 内 `export` が parent shell (Claude Code 本体 shell) を汚染 | L | L | hook は subprocess として起動されるため env leak しない構造 (§3.5 「env leak 防止契約」)、subshell 化 (`( export ...; python3 ... )`) は不要。smoke Case で「hook 実行前後の env 差分 == 0」を assertion 追加 |
| env 制御 mechanism (`export` / `unset` / inline) の drift による semantics 変質 | L | M | §3.3 頭で 3 択 table を明示 (採用 = `export` 1 種)、reviewer prompt で「unset / inline への drift 検出」を必須項目化。実装時 diff で `unset AGENT_ROUTER_LLM_` grep 0 hit を Step 3 smoke で assertion |
| budget 累積 file 破損 → 誤って早期 disable | L | M | fail-open (§3.5) で budget skip 継続、smoke case 4 で破損 file 再現テスト |
| default threshold 0.5 → 0.7 の変更で既存 hint 頻度が変わる (behavior regression) | M | L | roadmap §5 P2-5 が「default OFF」を明記、default OFF なら threshold 変更は user が opt-in した時のみ影響。既存 env `AGENT_ROUTER_LLM_THRESHOLD` set 済 project は既存値優先で無影響 |
| per-day budget 集計 file の並列書込み race + 破損 line による over/under-counting (MED-16 fix) | L | L | (a) fail-open は `awk 'NF>0 && $1 ~ /^[0-9.]+$/ {sum+=$1} END{print sum}'` で valid line filter に強化 (empty / non-numeric line silent skip = under-counting drift 抑制)、(b) 並列書込み race は「over-count 側のみ許容契約」を明示 (先着 drop の可能性は残るが cost 保護側で safe)、Case で monotone increase を assert (append 前後で累積が単調非減少)、(c) 将来 flock 化は Phase 3 で検討 |
| smoke 環境で python3 不在 → wiring smoke と同様 skip 扱い (MED-16 fix: skip 範囲の絞り込み) | L | L | 既存 `agent-router-suggest-wiring-smoke.sh:52-53` の `HAS_PY` pattern を踏襲、SKIP としてカウント。**ただし Case 3 (budget 超過 disable) / Case 4 (threshold override) / Case 5 (env 互換) は python3 不在でも hook stderr 検証で assertion 独立成立するため skip 対象外 = Case 1 (env forward) / Case 2 (opt-in ON) のみ python3 依存 SKIP** |
| 本 budget file (`.claude/.workflow-state/agent-router-llm-budget/*.usd`) の GC 責務が未定義 (MED-7 fix) | M | L | **本 file は task-99 (P3-2 lib/observability.sh + 30 日 GC + fire 0 回 hook 棚卸し) の observability GC 対象に含む契約**を本 draft §関連 (§9) の task-99 pointer に明示。task-99 draft 起案時に本 file path を lib/observability.sh の GC 対象 file list に append する運用義務を追跡 (副産物 candidate として next-actions.md に entry 追加、本 task 完遂時に main agent が実行)。Phase 3 完了までは無限増加 (< 1KB/日 × 30 日 = < 30KB) で無害 |

---

## 5. 移行計画

- [ ] Step 1 (SSoT 追加): yml 3 key + inline comment + config-loader export + metadata TSV 追記 の 4 file 同時 commit (drift 予防)
- [ ] Step 2 (consumer refactor): `agent-router-suggest.sh` 子 toggle gate + budget 累積 + threshold override 実装
- [ ] Step 3 (smoke): `agent-router-llm-fallback-smoke.sh` 新設 + `run-all-smokes.sh` category 表 (behavior / fast) 登録
- [ ] Step 4 (docs 反映): `harness-config.yml` inline comment 3 行 + `docs/INVENTORY.md` yml key 表更新 (存在時) + `.claude/rules/development-process.md` の関連参照 drift 確認
- [ ] Step 5-7 (テスト設計レビュー / テスト合格 / リファクタリング、採用 6 条 4 固定)

**feature flag 段階 rollout**: default `false` (OFF) で release、consuming repo は `harness-config.local.yml` で opt-in。監視は `.claude/.workflow-state/agent-router-llm-budget/*.usd` の累積 file と smoke 実走で行う。

---

## 6. 完了条件 (DoD、全項目に検証コマンド付与)

- [ ] `feature_agent_router_llm_fallback_enabled: false` が yml SSoT に存在 → `grep -c '^feature_agent_router_llm_fallback_enabled:' .claude/harness-config.yml == 1`
- [ ] `agent_router_llm_budget_usd_per_day: 0.1` が yml SSoT に存在 → `grep -c '^agent_router_llm_budget_usd_per_day:' .claude/harness-config.yml == 1`
- [ ] `agent_router_llm_similarity_threshold: 0.7` が yml SSoT に存在 → `grep -c '^agent_router_llm_similarity_threshold:' .claude/harness-config.yml == 1`
- [ ] `hc-config.sh --get feature_agent_router_llm_fallback_enabled == false` → `bash .claude/scripts/hc-config.sh --get feature_agent_router_llm_fallback_enabled` の stdout が `false`
- [ ] `hc-config.sh --get agent_router_llm_budget_usd_per_day == 0.1` → 同上コマンドで `0.1`
- [ ] `hc-config.sh --get agent_router_llm_similarity_threshold == 0.7` → 同上コマンドで `0.7`
- [ ] hc-config-metadata.sh に 3 key の TSV 行が存在 (5 field、TAB 区切り) → `bash -c 'source .claude/scripts/lib/hc-config-metadata.sh; hc_metadata_category feature_agent_router_llm_fallback_enabled' == 'feature_toggle'` + 他 2 key で `Gate/Confidence`
- [ ] hook が子 toggle OFF (default) 時に env `AGENT_ROUTER_LLM_FALLBACK` を上書きしない (env 未 set) → `printf '{"prompt":"security review"}' | bash .claude/hooks/agent-router-suggest.sh` は既存 wiring smoke Case 3 の hint を継続出力 (`llm-selector confirmed` label 不在)
- [ ] hook が子 toggle ON (env `HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED=true`) 時に `AGENT_ROUTER_LLM_FALLBACK=on` を export → 新 smoke Case 2 で router.py が `--use-llm-fallback` mode で起動 (mock で検証)
- [ ] budget 累積 file 超過時に fallback 強制 disable + WARN 1 行 → 新 smoke Case 3 で `.claude/.workflow-state/agent-router-llm-budget/<today>.usd` に 0.11 を書いた後 hook 起動で stderr に `budget exceeded` 相当 WARN
- [ ] `AGENT_ROUTER_LLM_THRESHOLD` env が未 set かつ子 toggle ON 時に `HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD=0.7` を export → 新 smoke Case 4 で hook 実行時の router.py stdin に `--llm-threshold 0.7` 相当引数が渡る
- [ ] 既存 `AGENT_ROUTER_LLM_FALLBACK` env 明示 set 時は env 優先 (WARN 1 行 stderr) → 新 smoke Case 5 で `AGENT_ROUTER_LLM_FALLBACK=on HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED=false` の混在で env 有効
- [ ] env 制御 mechanism drift 検出: hook 実装内で `unset AGENT_ROUTER_LLM_` grep 0 hit + inline env prefix (`AGENT_ROUTER_LLM_FALLBACK=on python3`) 0 hit → `grep -cE '^\s*unset\s+AGENT_ROUTER_LLM' .claude/hooks/agent-router-suggest.sh == 0` + `grep -cE 'AGENT_ROUTER_LLM_[A-Z_]+=[^ ]+ python3' .claude/hooks/agent-router-suggest.sh == 0`
- [ ] hook 実行前後の parent shell env 差分 == 0 (leak なし) → 新 smoke Case 6 で `env_before=$(env|sort); bash .claude/hooks/agent-router-suggest.sh <<<'{}'; env_after=$(env|sort); diff <(printf '%s' "$env_before") <(printf '%s' "$env_after") == empty`
- [ ] 新 smoke 全 case PASS → `bash .claude/tests/agent-router-llm-fallback-smoke.sh` exit 0 + `PASS >= 5 / FAIL == 0`
- [ ] 既存 wiring smoke 全 case 継続 PASS (regression 0) → `bash .claude/tests/agent-router-suggest-wiring-smoke.sh` exit 0
- [ ] run-all-smokes.sh 全 category 統合 PASS → `bash .claude/tests/run-all-smokes.sh` exit 0 (新 smoke が behavior/fast に分類済)
- [ ] enforcement-mismatch-smoke で新 key の docs/config mismatch 0 → `bash .claude/tests/enforcement-mismatch-smoke.sh` exit 0
- [ ] hc-config-key-parity-smoke で metadata TSV drift 0 → `bash .claude/tests/hc-config-key-parity-smoke.sh` exit 0
- [ ] docs 反映: `.claude/harness-config.yml` の 3 key 直上に inline comment (default + effect 1 行) → `grep -B1 '^feature_agent_router_llm_fallback_enabled:' .claude/harness-config.yml | head -1` が `#` で始まる
- [ ] **LOW-23 fix (docs 反映 drift 検証追加)**: (a) `.claude/rules/development-process.md` 全文 grep で `agent_router_llm` mention 0 hit なら skip、1+ hit なら update 契約明示 → `grep -c 'agent_router_llm' .claude/rules/development-process.md` が 0 or (update 後) ≥ 1、(b) CommonRules.md § Design Constraints「機能 on/off は yml feature toggle で集中管理」規範への準拠 grep → `grep -c '3 点 set' .claude/CommonRules.md` >= 1 (既存規範が本 task 3 key 対象と読める本文が存在)、(c) `hc-config.sh --list` に 3 key が discoverable → `bash .claude/scripts/hc-config.sh --list 2>&1 | grep -cE 'agent_router_llm_(fallback_enabled\|budget_usd_per_day\|similarity_threshold)'` == 3 (dogfood)

---

## 7. Step 分解 (採用 6 条準拠、1 Goal + N Steps、最終 3 Steps 固定)

**Goal**: agent-router LLM fallback を yml 3 key (feature toggle + budget + threshold) で明示化し、default OFF + env 互換層 + I7 triplet 全遵守 (yml + consumer + smoke) を完成させる。

| Step | Status | 作業概要 | 工数 | 依存 |
|:---:|:---:|:---|---:|:---|
| 1 | 🔲 | SSoT 4 file 同時追加 (harness-config.yml 3 key + inline comment / config-loader.sh 3 default export / metadata TSV 3 行 / .claude/harness-config.local.yml 参考 comment) | 0.5h | task-86 (hc-config.sh local.yml 統合) **hard** — `hc-config.sh --get` の解決順序に local override が必須 |
| 2 | 🔲 | consumer refactor: `agent-router-suggest.sh` に子 toggle gate + budget 累積 (UTC-day file) + threshold override + env 互換層 (env 明示 set 時 WARN) を実装 (Step 3.3 step 1-4 順) | 1.5h | Step 1 |
| 3 | 🔲 | 新 smoke `.claude/tests/agent-router-llm-fallback-smoke.sh` 新設 (bash 3.2 互換、既存 wiring smoke pattern 踏襲、6+ case: default OFF / opt-in ON / budget 超過 / threshold override / env 互換 / env leak 0 & mechanism drift 検出) + `run-all-smokes.sh` L46-89 `_get_smoke_category` の behavior 分岐に登録 (§11.3 R2 fast/full 分類: behavior/fast) | 1.5h | Step 2 |
| 4 | 🔲 | docs 反映: harness-config.yml inline comment 3 行 / docs/INVENTORY.md yml key 表 (存在時) / .claude/rules/development-process.md「サブエージェント委譲」の drift 確認 (agent-router-suggest 記載箇所 grep で ≥ 1 hit ある場合のみ update、無ければ skip: 記載変化なし) | 0.5h | Step 3 |
| 5 | 🔲 | (テスト設計レビュー) reviewer 動的選定 (`min ≤ N ≤ max`、`tdd-guide` + `test-automator` + `qa-expert` + `pr-test-analyzer` + LLM API/config 系 domain-specific)、CRITICAL/HIGH/MEDIUM 0 まで反復 (上限 `review_iteration_max`)、bypass `ECC_TEST_DESIGN_REVIEW_OFF=1` | 1.0h | Step 4 |
| 6 | 🔲 | (テスト合格) UI 変更なし → unit/integration smoke で PASS 判定 (§6 DoD 全項目)、既存 smoke regression 0 (`bash .claude/tests/run-all-smokes.sh` exit 0) | 0.5h | Step 5 |
| 7 | 🔲 | (リファクタリング) 3 観点 (持続可能性: budget file schema の将来変更耐性 / 汎用性: 他 LLM 系 hook への横展開余地 / 非冗長化: config-loader.sh + metadata TSV 記法の DRY)、不要なら `skip: <reason>` 明示 | 0.5h | Step 6 |

**合計工数見積**: 6.0h (0.75 day、Step 5 の iter 上限で ±1.5h 変動可)。

**依存整合性 (§11.3 R6 対応)**:
- **task-86 (P1-2、hard)**: `hc-config.sh --get feature_agent_router_llm_fallback_enabled` の解決順序 (env > local.yml > yml > default) が local.yml 統合済である前提。既に PR #70 で merge 済 (roadmap §11.1 の task-86)
- **task-95 (P2-4 死蔵 hook 棚卸し、soft)**: 依存なし (agent-router-suggest は task-81 で復活配線済、死蔵ではない)
- **task-97 (P2-6 enforcement_matrix 拡張)**: 逆方向依存 (roadmap §11.3 R6)、#97 は #95 完了後に着手 = 本 task の後続で matrix に 3 key 登録

---

## 8. 承認履歴

frontmatter (file 冒頭) の承認 field を SSoT とする。以下 table は監査補助 pointer:

| 日付 | 承認者 | 結果 |
|---|---|---|
| YYYY-MM-DD | user | 承認 → `/new-task 96 agent-router-llm-fallback-toggle` で task-96-agent-router-llm-fallback-toggle.md 生成 + list.md #96 行 📝 → 🔲 update |

---

## 9. 関連

- 上位 roadmap: [install-immediately-usable-redesign-20260618.md](./install-immediately-usable-redesign-20260618.md) §5 P2-5 (task #96) / §3 I7 (triplet) / §11.3 R2 (smoke 分類) / §11.3 R5 (checklist) / §11.3 R6 (DAG)
- 前提 task (完了済): task-81 (agent-router-suggest 配線復活、PR merge 済) / task-86 (hc-config.sh local.yml 統合、PR #70) / task-88 (SessionStart --summary 全文注入、PR #71)
- 関連 hook / lib:
  - `.claude/hooks/agent-router-suggest.sh` (consumer、L49 feature gate + L82-84 env forward)
  - `.claude/skills/agent-router/router.py` (L62-67 default constants / L985-1028 argparse)
  - `.claude/hooks/lib/config-loader.sh` (L342 SSoT default / L700-... export block)
  - `.claude/scripts/lib/hc-config-metadata.sh` (L46-135 TSV table)
  - `.claude/hooks/dispatcher-manifest.tsv` (L38 UserPromptSubmit 配線、変更不要)
- 関連 smoke:
  - `.claude/tests/agent-router-suggest-wiring-smoke.sh` (既存、regression 0 維持対象)
  - `.claude/tests/run-all-smokes.sh` (L46-89 category 分岐、`behavior` 分岐に本 smoke 追加)
  - `.claude/tests/enforcement-mismatch-smoke.sh` / `hc-config-key-parity-smoke.sh` (drift 検出)
- 関連 memory: [[feedback_config_value_needs_consumer_and_smoke]] (I7 起源) / [[feedback_parallel_subagent_cross_file_contract_drift]] (§4.1 契約 SSoT の起源)
