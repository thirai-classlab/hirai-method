#!/usr/bin/env bash
# agent-router-llm-fallback-smoke.sh — task #96 P2-5 Step 2
#
# 目的:
#   agent-router-suggest.sh の LLM fallback 子 toggle (task #96 Step 1) を検証する。
#   検証対象は draft `docs/draft/agent-router-llm-fallback-toggle.md` §4 の 10 case
#   (default OFF / opt-in / budget 超過 / threshold override / env 互換 / budget file
#   初回 / budget 累積 / subshell env leak 0 / hc-config.sh --get / --set 反映)。
#
# 前提:
#   Step 1 (hook 実装) 完了 = .claude/hooks/agent-router-suggest.sh に
#     - _llm_yml_on / _llm_env_set / _llm_effective_on 4 分岐 env 互換層
#     - budget dir/file 集計 + 超過時 WARN + 強制 disable
#     - subshell 化 `( export ...; python3 ... )` で env leak 0
#     - budget append (llm_used=true かつ llm_cost_usd>0 のとき)
#   が実装済 (10377 bytes、755、bash -n PASS 済)。
#
#   YmlIntegration phase (Wave 1 集約 subagent) 完了で:
#     - .claude/harness-config.yml に 3 key 追加
#         feature_agent_router_llm_fallback_enabled: false
#         agent_router_llm_budget_usd_per_day: 0.1
#         agent_router_llm_similarity_threshold: 0.7
#     - .claude/hooks/lib/config-loader.sh に HC_ default 3 個 + export 追加
#     - .claude/scripts/lib/hc-config-metadata.sh に TSV 3 行追加
#   が入る想定。本 smoke は 3 key 未追加の transitional state でも
#   graceful SKIP + PASS カウントで通過するよう設計 (I7 triplet の途中状態を吸収)。
#
# 検証する DoD (draft §6):
#   ARF-1: default OFF (feature 空 = false) で LLM path 未通過 (hint 出るが llm-selector 不在)
#   ARF-2: opt-in (HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED=true) で LLM path 有効
#   ARF-3: budget 超過 (事前に budget file に threshold 超え append) で強制 disable + WARN
#   ARF-4: similarity_threshold 未満で LLM fallback 発火 (HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD
#          が env として export される、subshell 内での挙動を hook のエコー stderr で間接検証)
#   ARF-5: env 互換層 (AGENT_ROUTER_LLM_FALLBACK=on だけ設定、yml false でも env 優先で on + WARN 1 行)
#   ARF-6: budget file が存在しない state (初回起動) で正常動作 (dir 未存在 → mkdir、fail-open)
#   ARF-7: budget accumulator (2 回起動で累積 file 行数 = 実 llm_used 回数分だけ増える、
#          今回は python3 mock 不能環境が多いため file の read/append 契約のみ検証)
#   ARF-8: subshell 化検証 (hook 実行後 parent shell の AGENT_ROUTER_LLM_FALLBACK / _THRESHOLD 汚染 0)
#   ARF-9: hc-config.sh --get で 3 key 値取得 (yml 追加後は raw 値、transitional は SKIP)
#   ARF-10: --set で feature toggle 変更後の hook 挙動反映 (tmp yml copy で SSoT 保護、
#           transitional は SKIP)
#
# 実行:    bash .claude/tests/agent-router-llm-fallback-smoke.sh
# 終了:    0 = 全 case PASS or SKIP / 1 = 1 件以上 FAIL
#
# 制約:
#   - file-top `set -u` のみ (feedback_set_e_in_sourced_libs 規範、errexit 外し)
#   - bash 3.2 互換 (declare -A 不使用、case 文ベース)
#   - 隔離 tmp dir + trap cleanup (EXIT INT TERM)
#   - fail-open: python3 不在時は LLM 呼出 case (ARF-2/ARF-4/ARF-7) を SKIP
#   - budget file の実 path は本物の .claude/.workflow-state/agent-router-llm-budget/ を
#     使わず、hook を BUDGET_DIR override 経由で分離する。ただし現 Step 1 hook は
#     `$SCRIPT_DIR/../.workflow-state/agent-router-llm-budget` を hardcode しているため、
#     smoke は事前に既存 file を退避し、終了時に復元する ($BUDGET_BACKUP)。
#   - 大部分の case は hook 直接起動 + stderr WARN grep + budget file grep で assert
#     (router.py 実 LLM 呼出 mock は本 smoke の scope 外、fast smoke 契約)。

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/agent-router-suggest.sh"
CONFIG_YML="$REPO_ROOT/.claude/harness-config.yml"
HC_CONFIG_SH="$REPO_ROOT/.claude/scripts/hc-config.sh"
BUDGET_DIR="$REPO_ROOT/.claude/.workflow-state/agent-router-llm-budget"

# tmp workspace
TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/agent-router-llm-fallback-smoke.XXXXXX")"

# budget dir 退避 (smoke で file を書くため既存 state を保護)
BUDGET_BACKUP=""
if [ -d "$BUDGET_DIR" ]; then
  BUDGET_BACKUP="$TMPBASE/budget-backup"
  cp -R "$BUDGET_DIR" "$BUDGET_BACKUP" 2>/dev/null || true
fi

cleanup() {
  # budget dir 復元 (smoke 実行で作成した file を除去し、元の state に戻す)
  rm -rf "$BUDGET_DIR" 2>/dev/null || true
  if [ -n "$BUDGET_BACKUP" ] && [ -d "$BUDGET_BACKUP" ]; then
    mkdir -p "$(dirname "$BUDGET_DIR")" 2>/dev/null || true
    cp -R "$BUDGET_BACKUP" "$BUDGET_DIR" 2>/dev/null || true
  fi
  rm -rf "$TMPBASE" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

PASS=0
FAIL=0
SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP: %s\n' "$1"; }

MATCH_PROMPT='{"prompt":"please do a security review for sql injection vulnerabilities in the auth module"}'
EMPTY_PROMPT='{"prompt":""}'

HAS_PY=0
command -v python3 >/dev/null 2>&1 && HAS_PY=1

# ---------------------------------------------------------------------------
# SKIP-MAJOR guard (task #96 iter fix D、Wave 1 review):
#   ARF-1/2/3/4/6/7/8/13 の 8 case が python3 に依存する (hook が prompt parse 前に
#   exit するため hook 本体の LLM path assertion 不能)。python3 不在環境では大半の
#   case が silently skip され「大半の case は skip されているのに result: PASS」を
#   誤って通す危険がある。冒頭で明示的に SKIP-MAJOR marker を出し、CI / operator が
#   「python3 不在 = smoke は inconclusive」を判定できるようにする。
#   Static drift check (ARF-11 / ARF-12) と config-only case (ARF-5 / ARF-9 / ARF-10)
#   は python3 不要のため引き続き実行される。
# ---------------------------------------------------------------------------
if [ "$HAS_PY" -eq 0 ]; then
  echo "SKIP-MAJOR: python3 not available; 8 of 13 cases will skip (ARF-1/2/3/4/6/7/8/13); treating result as inconclusive"
  echo "SKIP-MAJOR:   static-only cases still run: ARF-11 / ARF-12"
  echo "SKIP-MAJOR:   config-only cases still run: ARF-5 / ARF-9 / ARF-10"
fi

TODAY_UTC="$(date -u +%Y-%m-%d 2>/dev/null || echo unknown)"
BUDGET_FILE="$BUDGET_DIR/$TODAY_UTC.usd"

# ---------------------------------------------------------------------------
# tmp local yml (opt-in state 再現用、task #96 iter fix)
#
# 背景: HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED=true env は config-loader.sh の
#   Step 2 defaults で overwrite され Step 4 restore 対象外 (_HC_KNOWN_KEYS 不在) の
#   ため env 経由での opt-in 再現ができない (Step 1b snapshot は yml→env 上書きは
#   守るが、defaults→env 上書きは restore しない = 別 bug、本 smoke scope 外)。
#   HC_LOCAL_CONFIG_PATH は local.yml 経路として先に読まれ、値解決順 env>local.yml>
#   SSoT>defaults を確実に成立させる。
#
# LOCAL_YML_OPT_IN: 3 key ON (opt-in state) を再現、budget 0.1 / threshold 0.7
# LOCAL_YML_THRESHOLD_LOW: threshold=0.3 版 (ARF-4 用)
# LOCAL_YML_BUDGET_HIGH: budget=999 版 (ARF-6/7 accumulator 経路用)
# ---------------------------------------------------------------------------
LOCAL_YML_OPT_IN="$TMPBASE/local-optin.yml"
cat > "$LOCAL_YML_OPT_IN" <<EOF
feature_agent_router_llm_fallback_enabled: true
agent_router_llm_budget_usd_per_day: 0.1
agent_router_llm_similarity_threshold: 0.7
EOF

LOCAL_YML_THRESHOLD_LOW="$TMPBASE/local-thresh-low.yml"
cat > "$LOCAL_YML_THRESHOLD_LOW" <<EOF
feature_agent_router_llm_fallback_enabled: true
agent_router_llm_budget_usd_per_day: 0.1
agent_router_llm_similarity_threshold: 0.3
EOF

LOCAL_YML_BUDGET_HIGH="$TMPBASE/local-budget-high.yml"
cat > "$LOCAL_YML_BUDGET_HIGH" <<EOF
feature_agent_router_llm_fallback_enabled: true
agent_router_llm_budget_usd_per_day: 999
agent_router_llm_similarity_threshold: 0.7
EOF

# yml=false 明示版 (ARF-1 default OFF 再現用)
LOCAL_YML_OFF="$TMPBASE/local-off.yml"
cat > "$LOCAL_YML_OFF" <<EOF
feature_agent_router_llm_fallback_enabled: false
EOF

# hook 実行前に budget dir を毎回 clean にするヘルパー
_clean_budget() {
  rm -rf "$BUDGET_DIR" 2>/dev/null || true
}

# grep -c の "no match → stdout '0' + exit 1" pitfall を吸収する helper。
# `|| :` で exit 0 化、tr で改行除去、空文字は "0" default。
# $1: pattern (extended regex)、$2: file
_grep_count() {
  local pattern="$1" file="$2" n
  n=$(grep -Ec "$pattern" "$file" 2>/dev/null || :)
  n=$(printf '%s' "$n" | tr -d '[:space:]')
  printf '%s' "${n:-0}"
}

# yml に指定 key が存在するか (transitional state 検出用)
# $1: key
_yml_has_key() {
  awk -v k="$1" '
    /^[[:space:]]*#/ {next}
    {
      # k: value 形式 (空白 / タブ許容)
      if (match($0, "^[[:space:]]*" k "[[:space:]]*:")) { found=1; exit }
    }
    END { exit found ? 0 : 1 }
  ' "$CONFIG_YML" 2>/dev/null
}

# ---------------------------------------------------------------------------
# ARF-1: default OFF (yml=false + env 未 set) → LLM path 通過なし
#   yml transitional 状態 (key 不在) では is_feature_enabled は空文字→enabled 扱い (backward
#   compat) になるため、本 case は HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED=false を
#   明示注入 (task-rule-guard-smoke 型 pattern) して yml=false state を再現する。
#   hook 直接起動で WARN 不在 + budget file 未生成 (opt-in path 未通過) を assert。
# ---------------------------------------------------------------------------
_clean_budget
out_err=$(mktemp "$TMPBASE/arf1-err.XXXXXX")
if [ "$HAS_PY" -eq 1 ]; then
  # unset AGENT_ROUTER_LLM_FALLBACK して env 未 set 状態を保証
  # tmp local yml で yml=false を明示 (SSoT yml がすでに false でも smoke 独立性のため)
  (
    unset AGENT_ROUTER_LLM_FALLBACK 2>/dev/null || true
    cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
      HC_LOCAL_CONFIG_PATH="$LOCAL_YML_OFF" \
      bash "$HOOK" >/dev/null 2>"$out_err"
  )
  rc=$?
  # WARN 1 行不在 (yml=false + env 未 set は静か)
  warn_hit=$(_grep_count 'takes precedence|budget.*exceeded' "$out_err")
  # budget file 未生成 (opt-in 経路未通過)
  if [ "$rc" -eq 0 ] && [ "$warn_hit" -eq 0 ] && [ ! -f "$BUDGET_FILE" ]; then
    ok "ARF-1 default OFF (yml=false + env 未 set): WARN 不在 / budget file 未生成 / rc=0"
  else
    bad "ARF-1 default OFF: rc=$rc warn_hit=$warn_hit budget_file=$([ -f "$BUDGET_FILE" ] && echo present || echo absent)"
  fi
else
  skip "ARF-1 default OFF: python3 不在 (hook が prompt parse 前に exit → assertion 空回り)"
fi

# ---------------------------------------------------------------------------
# ARF-2: opt-in (HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED=true) で LLM path 経路有効
#   yml=true + env 未 set → hook 内 _llm_fallback_export="on" が subshell に export される。
#   subshell 化されているため hook 外の env は汚染されないが、hook 内 stderr / rc で
#   opt-in path 通過を検証する。
#   ★ iter fix (task #96 CRIT #2): rc=0 / env leak 0 / WARN 不在 の 3 条件は fail-open な
#      hook では trivially 満たされるため opt-in wiring の実成立を判定できない (mutation
#      L68 `_llm_yml_on=1` を 0 に、L174 export を no-op に改変しても PASS のまま)。
#      HC_AGENT_ROUTER_DEBUG_ENV=1 で subshell 内 export 直前の effective 値を stderr に
#      dump させ、`subshell AGENT_ROUTER_LLM_FALLBACK=on` の 1 行を直接 grep することで
#      export の実成立を assertion する (tautology 無し)。
# ---------------------------------------------------------------------------
_clean_budget
out_err=$(mktemp "$TMPBASE/arf2-err.XXXXXX")
if [ "$HAS_PY" -eq 1 ]; then
  # env 未 set 状態を parent shell 側で保証
  before_env=$(env | grep '^AGENT_ROUTER_LLM_' | sort)
  (
    unset AGENT_ROUTER_LLM_FALLBACK 2>/dev/null || true
    cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
      HC_LOCAL_CONFIG_PATH="$LOCAL_YML_OPT_IN" \
      HC_AGENT_ROUTER_DEBUG_ENV=1 \
      bash "$HOOK" >/dev/null 2>"$out_err"
  )
  rc=$?
  after_env=$(env | grep '^AGENT_ROUTER_LLM_' | sort)
  # env 汚染 0 (subshell 化) — process 境界により trivially 満たされるが keep for signal
  env_diff=$(diff <(printf '%s' "$before_env") <(printf '%s' "$after_env") 2>/dev/null | wc -l | tr -d ' ')
  # WARN 不在 (env 互換 WARN 不在、budget 超過 WARN 不在)
  warn_hit=$(_grep_count 'takes precedence|budget.*exceeded' "$out_err")
  # ★ 核心 assertion: debug dump で subshell 内 export の実成立を直接検証
  debug_on=$(_grep_count 'subshell AGENT_ROUTER_LLM_FALLBACK=on' "$out_err")
  if [ "$rc" -eq 0 ] && [ "$env_diff" = "0" ] && [ "$warn_hit" -eq 0 ] && [ "$debug_on" = "1" ]; then
    ok "ARF-2 opt-in (yml=true + env 未 set): rc=0 / env leak 0 / WARN 不在 / debug dump で subshell export=on 実成立"
  else
    bad "ARF-2 opt-in: rc=$rc env_diff=$env_diff warn_hit=$warn_hit debug_on=$debug_on (expected debug_on=1) err=$(head -3 "$out_err" | tr '\n' ' ')"
  fi
else
  skip "ARF-2 opt-in: python3 不在 (router.py 経由の LLM path 未検証)"
fi

# ---------------------------------------------------------------------------
# ARF-3: budget 超過 → 強制 disable + WARN
#   事前に BUDGET_FILE に 0.15 (limit 0.1 超え) を書き、hook 起動で stderr WARN
#   `budget.*exceeded` を検出する。
#   ★ iter fix (task #96 CRIT #3): WARN 有無だけでは cost 保護契約
#      (draft §3.3 step 3「cost gate は env priority より上位」= _llm_fallback_export="off"
#      による強制 OFF) が担保されない (mutation L127 `_llm_fallback_export="off"` を no-op に
#      改変しても WARN 有無は変わらず PASS のまま = 課金流出 CRIT を smoke が掴めない)。
#      env AGENT_ROUTER_LLM_FALLBACK=on を明示 opt-in した状態で budget 超過を発生させ、
#      HC_AGENT_ROUTER_DEBUG_BUDGET=1 で `fallback_export=off` を、
#      HC_AGENT_ROUTER_DEBUG_ENV=1 で subshell 内 `AGENT_ROUTER_LLM_FALLBACK=off` を
#      直接 grep することで強制 disable の実成立を assertion する。
# ---------------------------------------------------------------------------
_clean_budget
mkdir -p "$BUDGET_DIR" 2>/dev/null || true
printf '0.15\n' > "$BUDGET_FILE"
out_err=$(mktemp "$TMPBASE/arf3-err.XXXXXX")
if [ "$HAS_PY" -eq 1 ]; then
  (
    # 敢えて env AGENT_ROUTER_LLM_FALLBACK=on で明示 opt-in する: budget 超過が env 優先を
    # 上回って強制 OFF する契約 (cost 保護核心) の検証は、この "env=on でも off に潰れる"
    # 経路を通す必要があるため。
    export AGENT_ROUTER_LLM_FALLBACK=on
    cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
      HC_LOCAL_CONFIG_PATH="$LOCAL_YML_OPT_IN" \
      HC_AGENT_ROUTER_DEBUG_BUDGET=1 \
      HC_AGENT_ROUTER_DEBUG_ENV=1 \
      bash "$HOOK" >/dev/null 2>"$out_err"
  )
  rc=$?
  # WARN 1 行 `budget ... exceeded` を検出
  warn_hit=$(_grep_count 'budget.*exceeded|LLM fallback disabled for today' "$out_err")
  # ★ 核心 assertion 1: budget debug で fallback_export=off (強制 OFF の実成立)
  debug_off=$(_grep_count 'budget_used=.* limit=.* effective_on=0 fallback_export=off' "$out_err")
  # ★ 核心 assertion 2: env debug で subshell 内 AGENT_ROUTER_LLM_FALLBACK=off が実 export される
  #    (env AGENT_ROUTER_LLM_FALLBACK=on だが budget 超過で off に潰れる、cost 保護核心)
  debug_subshell_off=$(_grep_count 'subshell AGENT_ROUTER_LLM_FALLBACK=off' "$out_err")
  if [ "$rc" -eq 0 ] && [ "$warn_hit" -ge 1 ] && [ "$debug_off" = "1" ] && [ "$debug_subshell_off" = "1" ]; then
    ok "ARF-3 budget 超過 (0.15 >= 0.1、env=on): WARN 1 行 / fallback_export=off / subshell env=off (cost 保護実成立)"
  else
    bad "ARF-3 budget 超過: rc=$rc warn_hit=$warn_hit debug_off=$debug_off debug_subshell_off=$debug_subshell_off (expected 1,1,1) err=$(head -5 "$out_err" | tr '\n' ' ')"
  fi
else
  skip "ARF-3 budget 超過: python3 不在 (hook 早期 exit で budget check 未到達)"
fi
_clean_budget

# ---------------------------------------------------------------------------
# ARF-4: similarity_threshold 未満で LLM fallback 発火 (env export 挙動確認)
#   yml=true + env 未 set + HC_AGENT_ROUTER_LLM_SIMILARITY_THRESHOLD=0.3 の状態で、
#   hook 内 _llm_threshold_export="0.3" となり、subshell 内で AGENT_ROUTER_LLM_THRESHOLD=0.3
#   が export される。
#   ★ iter fix: rc / env leak / WARN の 3 条件だけでは threshold 経路の実成立を判定できない
#      ため、HC_AGENT_ROUTER_DEBUG_ENV=1 で subshell 内 `AGENT_ROUTER_LLM_THRESHOLD=0.3`
#      を直接 grep する。
# ---------------------------------------------------------------------------
_clean_budget
out_err=$(mktemp "$TMPBASE/arf4-err.XXXXXX")
if [ "$HAS_PY" -eq 1 ]; then
  before_env=$(env | grep '^AGENT_ROUTER_LLM_' | sort)
  (
    unset AGENT_ROUTER_LLM_FALLBACK AGENT_ROUTER_LLM_THRESHOLD 2>/dev/null || true
    cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
      HC_LOCAL_CONFIG_PATH="$LOCAL_YML_THRESHOLD_LOW" \
      HC_AGENT_ROUTER_DEBUG_ENV=1 \
      bash "$HOOK" >/dev/null 2>"$out_err"
  )
  rc=$?
  after_env=$(env | grep '^AGENT_ROUTER_LLM_' | sort)
  env_diff=$(diff <(printf '%s' "$before_env") <(printf '%s' "$after_env") 2>/dev/null | wc -l | tr -d ' ')
  warn_hit=$(_grep_count 'takes precedence|budget.*exceeded' "$out_err")
  # ★ 核心: subshell 内で AGENT_ROUTER_LLM_THRESHOLD=0.3 が実 export される (drift 検出)
  debug_threshold=$(_grep_count 'subshell AGENT_ROUTER_LLM_FALLBACK=on AGENT_ROUTER_LLM_THRESHOLD=0.3' "$out_err")
  if [ "$rc" -eq 0 ] && [ "$env_diff" = "0" ] && [ "$warn_hit" -eq 0 ] && [ "$debug_threshold" = "1" ]; then
    ok "ARF-4 threshold override (HC_..._THRESHOLD=0.3): rc=0 / env leak 0 / WARN 不在 / subshell env で fallback=on + threshold=0.3 実成立"
  else
    bad "ARF-4 threshold override: rc=$rc env_diff=$env_diff warn_hit=$warn_hit debug_threshold=$debug_threshold err=$(head -3 "$out_err" | tr '\n' ' ')"
  fi
else
  skip "ARF-4 threshold override: python3 不在"
fi

# ---------------------------------------------------------------------------
# ARF-5: env 互換層 (AGENT_ROUTER_LLM_FALLBACK=on + yml=false) → env 優先 + WARN 1 行
#   yml=false + env set の 4 分岐で唯一 WARN を出す組み合わせ。stderr grep で
#   `takes precedence (env 互換層)` を 1 行検出する。python3 不在でも hook 冒頭の
#   4 分岐 block は到達するが、prompt parse 前 exit の場合 stderr は出るので
#   HAS_PY を問わず assertion 可能。
# ---------------------------------------------------------------------------
_clean_budget
out_err=$(mktemp "$TMPBASE/arf5-err.XXXXXX")
(
  cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
    HC_LOCAL_CONFIG_PATH="$LOCAL_YML_OFF" \
    AGENT_ROUTER_LLM_FALLBACK=on \
    bash "$HOOK" >/dev/null 2>"$out_err"
)
rc=$?
warn_line=$(_grep_count 'takes precedence' "$out_err")
if [ "$rc" -eq 0 ] && [ "$warn_line" = "1" ]; then
  ok "ARF-5 env 互換層 (yml=false + env=on): WARN 1 行出力 / rc=0"
else
  bad "ARF-5 env 互換層: rc=$rc warn_line=$warn_line err=$(head -3 "$out_err" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# ARF-6: budget file が存在しない (初回起動) state で正常動作
#   BUDGET_DIR ごと未存在の状態で hook 起動 → dir 未存在 / file 未存在でも
#   fail-open で hook rc=0、budget check block を通過。python3 不在の場合は
#   hook が prompt parse 前 exit するため HAS_PY=1 必須。
# ---------------------------------------------------------------------------
_clean_budget
out_err=$(mktemp "$TMPBASE/arf6-err.XXXXXX")
if [ "$HAS_PY" -eq 1 ]; then
  (
    unset AGENT_ROUTER_LLM_FALLBACK 2>/dev/null || true
    cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
      HC_LOCAL_CONFIG_PATH="$LOCAL_YML_OPT_IN" \
      bash "$HOOK" >/dev/null 2>"$out_err"
  )
  rc=$?
  # budget 超過 WARN が出ていない = 初回 (used=0 < limit=0.1)、fail-open で継続
  warn_hit=$(_grep_count 'budget.*exceeded' "$out_err")
  if [ "$rc" -eq 0 ] && [ "$warn_hit" -eq 0 ]; then
    ok "ARF-6 budget file 初回 (dir 未存在): rc=0 / WARN 不在 / fail-open"
  else
    bad "ARF-6 budget file 初回: rc=$rc warn_hit=$warn_hit"
  fi
else
  skip "ARF-6 budget file 初回: python3 不在"
fi

# ---------------------------------------------------------------------------
# ARF-7: budget accumulator (契約検証)
#   hook が llm_used=true JSON を返す条件下でのみ file append する。python3
#   実 LLM 呼出は fast smoke の scope 外 (network 依存 / cost 発生)。
#   ★ iter fix (task #96 HIGH #4): 旧実装は smoke 内で hook の awk 式を複製して
#      混在 file の合計を計算していたため tautological (hook 側 awk 式が壊れても smoke は
#      通る)。HC_AGENT_ROUTER_DEBUG_BUDGET=1 で hook 自身が算出した `_budget_used` 値を
#      stderr に dump させ、混在 file (数値 3 + garbage 1 + 空 1) に対し hook が
#      `budget_used=0.100000` を返すことを直接 grep することで、hook 側 awk 式の drift を
#      smoke が検出できる構造に変更。
# ---------------------------------------------------------------------------
_clean_budget
mkdir -p "$BUDGET_DIR" 2>/dev/null || true
# 混在 file (数値 + garbage) を作り、hook 側 awk filter が数値のみ拾うことを検証。
# 意図的に awk が leading-digit を numeric 解釈できる garbage (`42abc`) を入れる:
#   strict filter (`^[0-9]+(\.[0-9]+)?$`) → skip → sum=0.10
#   loose  filter (`{sum+=$1}`)          → 42 に coerce → sum=42.10
# こうすることで strict/loose の drift を確実に検出する (garbage-line だけだと awk は
# leading-non-digit を 0 に coerce するため sum は変化せず mutation を捕捉できない)。
{
  printf '0.03\n'
  printf '0.05\n'
  printf '42abc\n'
  printf 'garbage-line\n'
  printf '\n'
  printf '0.02\n'
} > "$BUDGET_FILE"
out_err=$(mktemp "$TMPBASE/arf7-err.XXXXXX")
if [ "$HAS_PY" -eq 1 ]; then
  (
    unset AGENT_ROUTER_LLM_FALLBACK 2>/dev/null || true
    # limit を巨大値 (999) にして budget 超過に落ちないようにし、accumulator 経路のみを走らせる。
    # feature yml=true でないと budget check block に到達しないため opt-in。
    cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
      HC_LOCAL_CONFIG_PATH="$LOCAL_YML_BUDGET_HIGH" \
      HC_AGENT_ROUTER_DEBUG_BUDGET=1 \
      bash "$HOOK" >/dev/null 2>"$out_err"
  )
  rc=$?
  # hook 自身の awk filter で 0.03 + 0.05 + 0.02 = 0.10 (6 桁 float format = 0.100000)
  # を dump しているはず。前方一致 grep で drift 検出。
  debug_used_ok=$(_grep_count 'budget_used=0\.100000 limit=999' "$out_err")
  if [ "$rc" -eq 0 ] && [ "$debug_used_ok" = "1" ]; then
    ok "ARF-7 budget accumulator: hook 側 awk filter が 混在 file (数値 3 + garbage 2 (42abc / garbage-line) + 空 1) から 0.100000 抽出 (hook 直接検証、tautology 無し、mutation 42abc で strict/loose drift 捕捉)"
  else
    bad "ARF-7 budget accumulator: rc=$rc debug_used_ok=$debug_used_ok err=$(head -3 "$out_err" | tr '\n' ' ')"
  fi
else
  skip "ARF-7 budget accumulator: python3 不在 (hook 早期 exit で budget check 未到達)"
fi
_clean_budget

# ---------------------------------------------------------------------------
# ARF-8: subshell 化検証 (parent shell env leak 0)
#
# ★ HONEST LIMITATION (task #96 CRIT #1):
#   本 case の parent shell env leak 検証は、hook が `bash "$HOOK"` = 新規子プロセスで
#   起動されるため process 境界越しに env が既に隔離されており、hook 内 `( ... )` の
#   subshell paren を削除しても本 assertion は PASS のままとなる (mutation L172/L180
#   subshell paren 削除で PASS)。つまり本 case は "subshell paren の有無" ではなく
#   "process 境界による安全性" を検証している (defense-in-depth の一部)。
#
#   subshell paren の実効成立は ARF-2 (opt-in wiring)、ARF-3 (budget 強制 disable)、
#   ARF-4 (threshold override) の HC_AGENT_ROUTER_DEBUG_ENV=1 経路で間接的に担保する:
#   subshell 内でのみ有効な export が debug dump に現れることは、export が subshell
#   scope に閉じ込められている事の必要条件 (subshell paren を削除すると export が
#   hook proc 本体に leak し、次回起動時に stale 値が見える可能性は smoke 実行モデル
#   では検出不能)。
#
#   将来的な強化案 (副産物 candidate): (a) hook を `source` で smoke shell 内に走らせる
#   別 case を追加し、内側 `( export ... )` が省かれた場合に smoke 側 env が汚染される
#   事を assert、(b) hook 内 subshell 実行後に parent hook proc 側で `env | grep
#   AGENT_ROUTER_LLM_` を stderr dump する追加 debug 経路。draft §3.3 補遺 or 別 task に
#   ticket 化する。
# ---------------------------------------------------------------------------
_clean_budget
if [ "$HAS_PY" -eq 1 ]; then
  # subshell 内で hook 起動、外側で env 状態を検査
  before_set_1="${AGENT_ROUTER_LLM_FALLBACK+set}"
  before_set_2="${AGENT_ROUTER_LLM_THRESHOLD+set}"
  (
    unset AGENT_ROUTER_LLM_FALLBACK AGENT_ROUTER_LLM_THRESHOLD 2>/dev/null || true
    cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
      HC_LOCAL_CONFIG_PATH="$LOCAL_YML_OPT_IN" \
      bash "$HOOK" >/dev/null 2>/dev/null
  )
  rc=$?
  after_set_1="${AGENT_ROUTER_LLM_FALLBACK+set}"
  after_set_2="${AGENT_ROUTER_LLM_THRESHOLD+set}"
  # parent shell の 2 変数状態が hook 実行前後で同一 (unset なら unset のまま)
  # 注: process 境界により trivially 成立、subshell paren の有無は捕捉しない (上記 LIMITATION 参照)
  if [ "$rc" -eq 0 ] && [ "$before_set_1" = "$after_set_1" ] && [ "$before_set_2" = "$after_set_2" ]; then
    ok "ARF-8 process 境界による env leak 0 (defense-in-depth、subshell paren 検証は ARF-2/3/4 の debug dump 経路で間接担保)"
  else
    bad "ARF-8 process 境界: rc=$rc before_1=$before_set_1 after_1=$after_set_1 before_2=$before_set_2 after_2=$after_set_2"
  fi
else
  skip "ARF-8 process 境界: python3 不在 (hook 早期 exit で subshell 到達不能)"
fi

# ---------------------------------------------------------------------------
# ARF-9: hc-config.sh --get で 3 key 値取得
#   YmlIntegration 完了後は 3 key が yml に存在するため raw 値が返る。
#   transitional 状態 (yml key 不在) では --get は "key not found" (rc=1) になるため、
#   yml に該当 key が存在するかを事前に判定し、不在なら SKIP + reason 出力。
#   hc-config.sh は `--config <path>` CLI arg で SSoT yml 分離可能 (env HC_CONFIG_PATH は
#   `--config` の代替にならない、L2382 で DEFAULT_CONFIG が優先される仕様、L2368/2371 で
#   `--config` のみ CONFIG_PATH に反映される)。本 case は live yml を直接読むため
#   `--config` は不要 (SSoT が実 config になっている想定)。
# ---------------------------------------------------------------------------
if [ ! -f "$HC_CONFIG_SH" ]; then
  bad "ARF-9 hc-config.sh 不在: $HC_CONFIG_SH"
elif _yml_has_key feature_agent_router_llm_fallback_enabled; then
  # yml に 3 key があるはず (YmlIntegration 完了後)
  v1=$(bash "$HC_CONFIG_SH" --get feature_agent_router_llm_fallback_enabled 2>/dev/null | tr -d '[:space:]')
  v2=$(bash "$HC_CONFIG_SH" --get agent_router_llm_budget_usd_per_day 2>/dev/null | tr -d '[:space:]')
  v3=$(bash "$HC_CONFIG_SH" --get agent_router_llm_similarity_threshold 2>/dev/null | tr -d '[:space:]')
  # default 値の期待: false / 0.1 / 0.7 (draft §4.1 A) SSoT)
  if [ "$v1" = "false" ] && [ "$v2" = "0.1" ] && [ "$v3" = "0.7" ]; then
    ok "ARF-9 hc-config.sh --get: 3 key default 値 (false / 0.1 / 0.7) を返す"
  else
    bad "ARF-9 hc-config.sh --get: v1=[$v1] v2=[$v2] v3=[$v3] (expected false / 0.1 / 0.7)"
  fi
else
  skip "ARF-9 hc-config.sh --get: yml に feature_agent_router_llm_fallback_enabled 不在 (YmlIntegration 未完 = transitional state、Wave 1 集約 subagent 完了で PASS 化予定)"
fi

# ---------------------------------------------------------------------------
# ARF-10: --set で feature toggle 変更後の値反映
#   yml に 3 key が存在する前提で、tmp yml copy に --set → 変更後の yml を
#   `--config <path>` CLI arg で hc-config.sh に渡し、live SSoT を書き換えず opt-in 状態が
#   反映されるか検証。yml 未追加時は SKIP。
#   注意: hc-config.sh は `--config` CLI arg で SSoT 分離可能 (HC_CONFIG_PATH env は無視、
#   L2382 で DEFAULT_CONFIG が優先される)。
# ---------------------------------------------------------------------------
if [ ! -f "$HC_CONFIG_SH" ]; then
  bad "ARF-10 hc-config.sh 不在: $HC_CONFIG_SH"
elif _yml_has_key feature_agent_router_llm_fallback_enabled; then
  # tmp yml copy を作り、SSoT (repo yml) を保護
  tmp_yml="$TMPBASE/harness-config.yml"
  cp "$CONFIG_YML" "$tmp_yml"
  # --set / --get 双方に --config <tmp_yml> を渡して SSoT 分離。
  # hc-config.sh の _validate_config_path は REPO_ROOT / /tmp/ 配下のみ許可し、
  # macOS の $TMPDIR (/var/folders/...) は外部扱い → HC_ALLOW_EXTERNAL_CONFIG=1 で bypass
  # (F-04 tdd 由来の test isolation only bypass、正当な用途)。
  set_out=$(HC_ALLOW_EXTERNAL_CONFIG=1 bash "$HC_CONFIG_SH" --config "$tmp_yml" --set feature_agent_router_llm_fallback_enabled=true 2>&1)
  set_rc=$?
  # 変更後 tmp yml から get
  post_val=$(HC_ALLOW_EXTERNAL_CONFIG=1 bash "$HC_CONFIG_SH" --config "$tmp_yml" --get feature_agent_router_llm_fallback_enabled 2>/dev/null | tr -d '[:space:]')
  # live SSoT が汚染されていない (repo yml が読取専用扱い) を diff で確認
  live_still_false=""
  if _yml_has_key feature_agent_router_llm_fallback_enabled; then
    live_v=$(bash "$HC_CONFIG_SH" --get feature_agent_router_llm_fallback_enabled 2>/dev/null | tr -d '[:space:]')
    [ "$live_v" = "false" ] && live_still_false="yes"
  fi
  if [ "$set_rc" -eq 0 ] && [ "$post_val" = "true" ] && [ "$live_still_false" = "yes" ]; then
    ok "ARF-10 --set feature=true → --get で true 反映 (tmp yml copy 経由、SSoT 保護 OK)"
  else
    bad "ARF-10 --set/--get: set_rc=$set_rc post_val=[$post_val] live_still_false=[$live_still_false] set_out=$(printf '%s' "$set_out" | head -2 | tr '\n' ' ')"
  fi
else
  skip "ARF-10 --set: yml に feature_agent_router_llm_fallback_enabled 不在 (transitional state、YmlIntegration 完了で PASS 化予定)"
fi

# ---------------------------------------------------------------------------
# ARF-11: static drift check — `unset AGENT_ROUTER_LLM_*` は hook に存在しない
#   env 制御 mechanism は "export のみ" (drift 予防で 1 mechanism 固定、
#   hook file-header L30 に明記) の契約を静的検証する。
#   `unset` line が混入した場合、subshell 内で env が既に消えている状態で python3 起動
#   となり router.py 側の env 継承契約が壊れるため CRITICAL。python3 不要 (grep のみ)。
# ---------------------------------------------------------------------------
_arf11_n=$(grep -cE '^[[:space:]]*unset[[:space:]]+AGENT_ROUTER_LLM' "$HOOK" 2>/dev/null || :)
_arf11_n=$(printf '%s' "$_arf11_n" | tr -d '[:space:]')
_arf11_n="${_arf11_n:-0}"
if [ "$_arf11_n" -eq 0 ]; then
  ok "ARF-11 static drift check: hook に 'unset AGENT_ROUTER_LLM_*' line 0 (export-only 契約)"
else
  bad "ARF-11 static drift check: hook に 'unset AGENT_ROUTER_LLM_*' line $_arf11_n 検出 (export-only 契約違反)"
fi

# ---------------------------------------------------------------------------
# ARF-12: static drift check — inline env prefix `AGENT_ROUTER_LLM_XXX=val python3` 不在
#   env 反映は "explicit subshell `( export ...; python3 ... )` のみ" 契約
#   (hook file-header L32 に明記) の静的検証。inline prefix が混入すると env 供給
#   mechanism が 2 系統に増え subshell isolation 契約と drift する。python3 不要。
# ---------------------------------------------------------------------------
_arf12_n=$(grep -cE 'AGENT_ROUTER_LLM_[A-Z_]+=[^ ]+ python3' "$HOOK" 2>/dev/null || :)
_arf12_n=$(printf '%s' "$_arf12_n" | tr -d '[:space:]')
_arf12_n="${_arf12_n:-0}"
if [ "$_arf12_n" -eq 0 ]; then
  ok "ARF-12 static drift check: hook に 'AGENT_ROUTER_LLM_*=val python3' inline env prefix 0 (subshell-only 契約)"
else
  bad "ARF-12 static drift check: hook に inline env prefix line $_arf12_n 検出 (subshell-only 契約違反)"
fi

# ---------------------------------------------------------------------------
# ARF-13: parent-child toggle interaction
#   parent (feature_agent_router_suggest_enabled) を env で false + child
#   (feature_agent_router_llm_fallback_enabled) を env で true → hook 冒頭で
#   parent gate により即 exit 0、child toggle は評価されない。
#   assertion: rc=0 / stdout 空 (hint 注入なし) / stderr に debug dump 不在
#   (subshell に到達していない証拠、HC_AGENT_ROUTER_DEBUG_ENV=1 を渡しても dump なし)。
# ---------------------------------------------------------------------------
_clean_budget
out_out=$(mktemp "$TMPBASE/arf13-out.XXXXXX")
out_err=$(mktemp "$TMPBASE/arf13-err.XXXXXX")
if [ "$HAS_PY" -eq 1 ]; then
  (
    unset AGENT_ROUTER_LLM_FALLBACK 2>/dev/null || true
    cd "$REPO_ROOT" && printf '%s' "$MATCH_PROMPT" | \
      HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED=false \
      HC_FEATURE_AGENT_ROUTER_LLM_FALLBACK_ENABLED=true \
      HC_LOCAL_CONFIG_PATH="$LOCAL_YML_OPT_IN" \
      HC_AGENT_ROUTER_DEBUG_ENV=1 \
      HC_AGENT_ROUTER_DEBUG_BUDGET=1 \
      bash "$HOOK" >"$out_out" 2>"$out_err"
  )
  rc=$?
  # stdout 空 (hint 注入なし)
  stdout_bytes=$(wc -c < "$out_out" | tr -d ' ')
  # stderr に subshell debug dump が現れない (parent gate で exit 済、subshell 未到達)
  # WARN も出ない (env 互換層 WARN / budget WARN いずれも child evaluate 前に exit)
  debug_dump_n=$(_grep_count 'subshell AGENT_ROUTER_LLM_FALLBACK=' "$out_err")
  budget_dump_n=$(_grep_count 'budget_used=' "$out_err")
  if [ "$rc" -eq 0 ] && [ "$stdout_bytes" = "0" ] && [ "$debug_dump_n" = "0" ] && [ "$budget_dump_n" = "0" ]; then
    ok "ARF-13 parent OFF + child ON: parent gate で即 exit 0 / stdout 空 / subshell 未到達 (child inert)"
  else
    bad "ARF-13 parent-child toggle: rc=$rc stdout_bytes=$stdout_bytes debug_dump_n=$debug_dump_n budget_dump_n=$budget_dump_n err=$(head -3 "$out_err" | tr '\n' ' ')"
  fi
else
  skip "ARF-13 parent-child toggle: python3 不在 (hook 早期 exit で assertion 空回り)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "== result: PASS=$PASS FAIL=$FAIL SKIP=$SKIP =="
[ "$FAIL" -eq 0 ]
