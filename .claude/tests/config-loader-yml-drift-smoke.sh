#!/usr/bin/env bash
# .claude/tests/config-loader-yml-drift-smoke.sh — task-106 W1-4 Step 2
#
# 目的:
#   `.claude/hooks/lib/config-loader.sh` の HC_* default 値 と
#   `.claude/harness-config.yml` の同名 key value の drift を機械検出する。
#
#   Step 1 (task-106) で既知の HC_CONTEXT_BUDGET_THRESHOLD (loader 0.60 vs yml 0.66)
#   drift を fix し、全 HC_* default vs yml value の全数 audit + fix を完遂した後の
#   regression 検出 smoke。以後 default 追加時に drift が発生すれば FAIL する。
#
# Cases:
#   Case A: default parity — config-loader.sh source 後の全 HC_* default 値と、
#           hc-config.sh --get <key> で得られる yml 値が (normalize 後) 一致する。
#   Case B: env override — HC_CONTEXT_BUDGET_THRESHOLD=0.42 env で source 時、
#           効果値が 0.42 になる (env > yml > default の優先順)。
#   Case C: helper mode (--check-drift) — machine-readable drift report。
#           drift 発見時 stderr に `key=<name> default=<v1> yml=<v2>` 出力 + exit 1、
#           drift 0 で exit 0。fail-open 設計 (hook からは BLOCK しない、regression 検出用)。
#           人工 drift 注入 sanity は LOADER env override 経由で本 smoke 自身の
#           --check-drift path を再実行して検証する (inline 再実装なし、SSoT 一元化)。
#
# SSoT 範囲 (task-106 W1-4 iter round-1 MED-7 反映):
#   本 smoke は `loader default ↔ SSoT yml (.claude/harness-config.yml)` の対称性のみ検証。
#   `.claude/harness-config.local.yml` (Step 3.5 で SSoT より優先 load) は runtime asymmetry
#   として別 scope で扱う。Case A の sanity (`hc-config --get`) は memory index
#   [[feedback_hc_config_cli_runtime_local_yml_asymmetry]] の通り local.yml 未対応の既知 gap を
#   吸っている前提 (project が local.yml 経由で意図的 override した key の runtime 実効値は
#   本 smoke の scope 外)。drift 検出の目的はあくまで「Step 2 defaults が SSoT に追随」の
#   規範保守で、runtime 実効値 (env > local.yml > SSoT > default) の全 tier 検証ではない。
#
# 設計原則:
#   - subshell 関数化 ( set -uo pipefail; ... ) で各 case を隔離
#     (feedback_set_e_in_sourced_libs 規範)
#   - inline array `[a, b, c]` vs `\n` 区切り list は同値 normalize (JSON 化 comparable tuple)
#   - `$HOME` vs `~` は tilde 展開後同値 normalize
#   - 意図的空 default (_HC_KNOWN_KEYS に含まれ、yml で nested / commented out) は
#     exception list で明示 exclude
#   - `set | grep '^HC_'` で全 HC_* 取得 (未来の新規 HC_FEATURE_* 追加も検出可)
#   - LOADER / YML は env override 可能 (Case C の人工 drift 注入で tmp loader path を差し込む)
#
# 起源: docs/tasks/task-106-context-budget-drift-fix.md Step 2
#        + iter round-1 findings fix (CRIT/HIGH/MED 12 件)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# LOADER / YML は env override 可能 (Case C の人工 drift 注入で使う。round-1 MED-3/HIGH-1 対応)
LOADER="${LOADER:-${REPO_ROOT}/.claude/hooks/lib/config-loader.sh}"
YML="${YML:-${REPO_ROOT}/.claude/harness-config.yml}"
HC_CONFIG_SCRIPT="${REPO_ROOT}/.claude/scripts/hc-config.sh"

# --check-drift helper mode で使う際の最低 extract count (round-1 MED-4 対応)
# 現在 105 records 抽出可能、marker 変更で 0 落ちを検出するため 50 を最低閾値とする。
# 追加 default が今後増える一方な想定なので、この閾値は "regression 検出の bottom line"
# として機能する (SSoT の default 総数が半減する事態は通常起き得ないため 50 で十分)。
_MIN_EXTRACTED_DEFAULTS=50

# ============================================================
# fixture pre-flight (round-1 MED-9 対応)
# LOADER / YML / HC_CONFIG_SCRIPT の欠損 / 読取不可時は即 exit 2 (silent PASS 防止)
# --check-drift helper mode 分岐前に評価するため top-level に置く。
# ============================================================
for _f in "$LOADER" "$YML" "$HC_CONFIG_SCRIPT"; do
  if [ ! -f "$_f" ] || [ ! -r "$_f" ]; then
    printf 'ERROR: required fixture missing or unreadable: %s\n' "$_f" >&2
    exit 2
  fi
done
unset _f

# ============================================================
# helper: 意図的空 default の exception list
# ============================================================
# 下記 key は config-loader.sh で意図的に空 default を持ち、yml では nested / commented out /
# advanced-only な扱いのため drift 扱いしない。追加時は必ずこの list に登録する。
_is_exception_key() {
  case "$1" in
    HC_AGENT_TYPE_KEYWORD_MAPPING) return 0 ;;   # hook 内 hardcode default 採用、advanced env override 専用
    HC_LOOP_CONFIRMATION_PATTERNS) return 0 ;;   # yml commented out (default 使用)、advanced env override 専用
    HC_PARALLEL_SUBAGENT_STATE_DIR) return 0 ;;  # hook 内 fallback 採用、test isolation 用のみ
    HC_ENFORCEMENT_MATRIX) return 0 ;;           # yml nested block、flat parser で "" になる意図設計
    HC_REQUIRED_ENV) return 0 ;;                 # yml empty [] と loader "" は functionally 同値 (parse で ""化)
    *) return 1 ;;
  esac
}

# ============================================================
# helper: value normalize (config-loader semantics 相当)
# 入力:  raw 文字列 (loader default or yml raw)
# 出力:  normalize 済 string (list なら CSV、tilde 展開済)
# ============================================================
_normalize_value() {
  local v="$1"
  # trim
  v="${v#"${v%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  # inline array `[a, b, c]` → sorted-preserving CSV
  case "$v" in
    \[*\])
      local inner="${v#\[}"
      inner="${inner%\]}"
      local out=""
      local IFS_SAVE="$IFS"
      IFS=','
      local item
      for item in $inner; do
        # trim
        item="${item#"${item%%[![:space:]]*}"}"
        item="${item%"${item##*[![:space:]]}"}"
        # strip inner quotes
        case "$item" in
          \"*\") item="${item#\"}"; item="${item%\"}" ;;
          \'*\') item="${item#\'}"; item="${item%\'}" ;;
        esac
        if [ -n "$item" ]; then
          if [ -z "$out" ]; then out="$item"; else out="$out,$item"; fi
        fi
      done
      IFS="$IFS_SAVE"
      printf 'LIST:%s' "$out"
      return 0
      ;;
  esac
  # \n-separated list (loader $'a\nb\nc' expansion)
  case "$v" in
    *$'\n'*)
      local out=""
      local line
      while IFS= read -r line; do
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"
        if [ -n "$line" ]; then
          if [ -z "$out" ]; then out="$line"; else out="$out,$line"; fi
        fi
      done <<< "$v"
      printf 'LIST:%s' "$out"
      return 0
      ;;
  esac
  # scalar: strip outer quotes + tilde/$HOME expand
  case "$v" in
    \"*\") v="${v#\"}"; v="${v%\"}" ;;
    \'*\') v="${v#\'}"; v="${v%\'}" ;;
  esac
  case "$v" in
    "~")    v="$HOME" ;;
    "~/"*)  v="$HOME/${v#"~/"}" ;;
    "\$HOME") v="$HOME" ;;
    "\$HOME/"*) v="$HOME/${v#"\$HOME/"}" ;;
  esac
  printf 'SCALAR:%s' "$v"
}

# ============================================================
# helper: 全 HC_* default を config-loader.sh から抽出
#
# 設計:
#   loader を source すると Step 3 で yml 値が上書きされ、runtime 値と
#   Step 2 defaults の分離ができない。よって Step 2 defaults セクション
#   (`# --- Step 2: 既定値` ~ `# --- 値整形 helper` の間) を直接 grep 抽出する。
#
#   抽出だけを目的とした sandbox source (Step 3 抑止) も検討したが、runtime 依存を
#   避け source 静的解析で完結させる方針が maintain しやすい (script structure が
#   変わっても marker comment を追えば済む)。
#
# 出力: 各行 "HC_KEY=<value>" (loader 記述そのまま、$'...' 内 \n は literal で保持)
# ============================================================
_extract_loader_defaults() {
  awk '
    /# --- Step 2: 既定値/ { in_step2 = 1; next }
    /# --- 値整形 helper/ { in_step2 = 0 }
    in_step2 && /^HC_[A-Z0-9_]+=/ {
      # split at first `=`
      idx = index($0, "=")
      key = substr($0, 1, idx - 1)
      val = substr($0, idx + 1)
      # strip trailing inline comment (naive: 前後 double-quote value は skip 判定省略、
      # 実運用の defaults section では quote 内 # 使用なし)
      if (substr(val, 1, 1) != "\"" && substr(val, 1, 2) != "$\x27") {
        c = index(val, "#")
        if (c > 0) val = substr(val, 1, c - 1)
      }
      # trim trailing spaces
      sub(/[[:space:]]+$/, "", val)
      # strip outer double quotes: "value" → value
      if (substr(val, 1, 1) == "\"" && substr(val, length(val), 1) == "\"") {
        val = substr(val, 2, length(val) - 2)
      }
      # strip $\x27...\x27 form: $\x27a\nb\nc\x27 → a\nb\nc (literal)
      # ($\x27 = $'\'', ANSI-C bash escape)
      else if (substr(val, 1, 2) == "$\x27" && substr(val, length(val), 1) == "\x27") {
        inner = substr(val, 3, length(val) - 3)
        # convert \n escape to actual newline
        gsub(/\\n/, "\n", inner)
        val = inner
      }
      printf "%s=%s\x1c", key, val  # \x1c (FS) を record separator に使う (\n は list value 内に含まれ得るため)
    }
  ' "$LOADER"
}

# ============================================================
# helper: yml top-level key の raw 値を抽出
#
# 実装 note (round-1 MED-8 対応):
#   本 helper は config-loader.sh `_hc_strip_inline_comment` (task-64 Step 1) の
#   ロジックを inline mirror する。canonical 実装は 2 path:
#     - .claude/hooks/lib/config-loader.sh L503-522 (`_hc_strip_inline_comment`)
#     - .claude/scripts/hc-config.sh (`_yml_get_raw` 内、同一ロジック)
#   本 smoke は独立実行性 (config-loader を source すると Step 3 で HC_* が env に流出、
#   subshell 隔離しても yml 副読ロード相当のオーバヘッドが乗る) を優先し inline mirror する。
#   canonical のいずれかを変更する際は、本 helper (_yml_raw_value 内) も同時更新すること。
#   同期漏れ検出は `.claude/tests/hc-config-key-parity-smoke.sh` (別 test) が
#   raw value 経由の全 key 一致で間接的にカバーする。
#
# 出力: key に対応する yml raw 値 (未定義なら空文字)
# ============================================================
_yml_raw_value() {
  local key="$1"
  local raw
  # top-level (先頭インデント無し) のみ抽出
  raw=$(grep -E "^${key}:" "$YML" 2>/dev/null | head -n 1 | sed -E "s/^${key}:[[:space:]]*//")
  [ -z "$raw" ] && { printf ''; return 0; }
  # 前後空白 trim (canonical `_hc_val` trim ロジック相当)
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  # canonical `_hc_strip_inline_comment` ロジック mirror:
  #   1) 前後 `"..."` (double-quote) 判定 → quote 解除 + \\ / \" unescape のみ (comment strip skip)
  #   2) それ以外 → 最初の `#` 以降を strip + trailing 空白再 trim
  if [ "${#raw}" -ge 2 ] && [ "${raw:0:1}" = '"' ] && [ "${raw: -1}" = '"' ]; then
    raw="${raw#\"}"
    raw="${raw%\"}"
    raw="${raw//\\\\/\\}"
    raw="${raw//\\\"/\"}"
    printf '%s' "$raw"
    return 0
  fi
  raw="${raw%%#*}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  printf '%s' "$raw"
}

# ============================================================
# helper: yml top-level key が存在するか (nested 除く)
# ============================================================
_yml_has_key() {
  grep -qE "^${1}:" "$YML" 2>/dev/null
}

# ============================================================
# main drift detection (Case A + Case C 共通ロジック)
# 出力:
#   stdout: 各 drift 行 "key=<name> default=<loader> yml=<yml>"
#   return: 0 = drift 0 件、1 = drift ≥1 件、2 = extract 失敗 (marker 変更等)
# ============================================================
_detect_drifts() {
  local defaults
  defaults=$(_extract_loader_defaults) || return 2
  # marker 破損時の silent 0-drift PASS 防止 (round-1 MED-4 対応)
  local extracted_count
  extracted_count=$(printf '%s' "$defaults" | tr -cd $'\x1c' | wc -c | tr -d ' ')
  if [ "${extracted_count:-0}" -lt "$_MIN_EXTRACTED_DEFAULTS" ]; then
    printf 'ERROR: too few defaults extracted (%d < %d), check section markers `# --- Step 2: 既定値` / `# --- 値整形 helper` in %s\n' \
      "${extracted_count:-0}" "$_MIN_EXTRACTED_DEFAULTS" "$LOADER" >&2
    return 2
  fi
  local record hc_key hc_val yml_key yml_val n_loader n_yml
  # \x1c 区切りで record loop (\n は list value 内に含まれる可能性ありのため使えない)
  # `printf '%s' | while` で末尾 \n 混入を防ぐ (herestring `<<<` は暗黙 \n 付与、
  # round-1 MED-6 対応。現状は空 record skip で吸収してるが末尾 \x1c 依存を明示化)。
  #
  # 注意: `|` pipe で subshell 化するため、ループ内変数は outer scope に伝搬しない。
  # よってループ内で drift lines を stdout に流し、外側で非空判定する形に変更。
  local drift_lines
  drift_lines=$(printf '%s' "$defaults" | while IFS= read -r -d $'\x1c' record; do
    [ -z "$record" ] && continue
    # split at first `=`
    hc_key="${record%%=*}"
    hc_val="${record#*=}"
    # exception list skip
    if _is_exception_key "$hc_key"; then
      continue
    fi
    # yml key = HC_ 除去 + lowercase
    yml_key=$(printf '%s' "${hc_key#HC_}" | tr '[:upper:]' '[:lower:]')
    if ! _yml_has_key "$yml_key"; then
      # yml に無い key (loader-only): 「非対称」だが drift 扱いしない (Step 2 defaults 側 SSoT)
      continue
    fi
    yml_val=$(_yml_raw_value "$yml_key")
    n_loader=$(_normalize_value "$hc_val")
    n_yml=$(_normalize_value "$yml_val")
    if [ "$n_loader" != "$n_yml" ]; then
      # 表示時は \n を `|` に escape (人間可読、report をログに載せる用途)
      local disp_loader disp_yml
      disp_loader=$(printf '%s' "$hc_val" | tr '\n' '|')
      disp_yml=$(printf '%s' "$yml_val" | tr '\n' '|')
      printf 'key=%s default=%s yml=%s\n' "$hc_key" "$disp_loader" "$disp_yml"
    fi
  done)
  if [ -n "$drift_lines" ]; then
    printf '%s\n' "$drift_lines"
    return 1
  fi
  # drift_count は subshell 化した while ループでは outer scope に伝搬しないため、
  # 検出は drift_lines の非空判定で行う (round-1 MED-6 対応の副産物)。
  return 0
}

# ============================================================
# helper mode: --check-drift で呼ばれた時は _detect_drifts の結果を stderr に流して exit
# fail-open: hook から呼んでも process を BLOCK しない (regression 検出専用、smoke 用)
# ============================================================
if [ "${1:-}" = "--check-drift" ]; then
  drifts=$(_detect_drifts)
  drifts_rc=$?
  if [ "$drifts_rc" -eq 2 ]; then
    # extract failure (marker 破損等) は明確に exit 2
    exit 2
  fi
  if [ -n "$drifts" ]; then
    printf '%s\n' "$drifts" >&2
    exit 1
  fi
  exit 0
fi

# ============================================================
# Test runner
# ============================================================
PASS=0
FAIL=0
FAILED_CASES=""

_record() {
  local result="$1" case_id="$2" desc="$3"
  if [ "$result" = "PASS" ]; then
    printf '  PASS  Case %s: %s\n' "$case_id" "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL  Case %s: %s\n' "$case_id" "$desc"
    FAIL=$((FAIL + 1))
    FAILED_CASES="${FAILED_CASES} ${case_id}"
  fi
}

# ============================================================
# Case A: default parity
#   config-loader.sh source 後の HC_* と hc-config.sh --get <key> の一致
#   (yml raw と loader default の normalize 済比較。_detect_drifts と同ロジックだが
#    hc-config.sh --get を追加 sanity check として使う)
# ============================================================
_case_a() (
  set -uo pipefail
  local drifts rc
  drifts=$(_detect_drifts)
  rc=$?
  if [ "$rc" -eq 2 ]; then
    printf 'Case A: extract 失敗 (marker 破損等、ERROR は上記 stderr 参照)\n' >&2
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    printf 'Case A: drift detected:\n%s\n' "$drifts" >&2
    return 1
  fi
  # sanity: config-loader source 後の HC_CONTEXT_BUDGET_THRESHOLD が hc-config --get と一致
  # (memory index [[feedback_hc_config_cli_runtime_local_yml_asymmetry]] の通り local.yml 未対応
  #  の既知 gap を吸っている前提。本 smoke は SSoT yml scope のみを対象、local.yml 経由 override
  #  key の runtime 実効値検証は別 scope。)
  local eff runtime_val
  eff=$(bash "$HC_CONFIG_SCRIPT" --get context_budget_threshold 2>/dev/null | head -n1)
  runtime_val=$(env -i HOME="$HOME" PATH="$PATH" bash -c "source '$LOADER' >/dev/null 2>&1; printf '%s' \"\$HC_CONTEXT_BUDGET_THRESHOLD\"")
  if [ "$eff" != "$runtime_val" ]; then
    printf 'Case A: sanity fail: hc-config --get=%s runtime=%s\n' "$eff" "$runtime_val" >&2
    return 1
  fi
  printf 'Case A: drift 0 件、runtime HC_CONTEXT_BUDGET_THRESHOLD=%s matches hc-config --get\n' "$runtime_val" >&2
  return 0
)

# ============================================================
# Case B: env override — env > yml > default 優先順
# ============================================================
_case_b() (
  set -uo pipefail
  local actual
  actual=$(HC_CONTEXT_BUDGET_THRESHOLD=0.42 bash -c "source '$LOADER' >/dev/null 2>&1; printf '%s' \"\$HC_CONTEXT_BUDGET_THRESHOLD\"")
  if [ "$actual" != "0.42" ]; then
    printf 'Case B: env override 失敗 expected=0.42 actual=%s\n' "$actual" >&2
    return 1
  fi
  printf 'Case B: HC_CONTEXT_BUDGET_THRESHOLD=0.42 env override 通過\n' >&2
  return 0
)

# ============================================================
# Case C: helper mode (--check-drift) semantics
#   drift 0 → exit 0
#   人工 drift 注入 (tmp loader) → 本 smoke 自身の --check-drift を LOADER env override
#     で再実行 → exit 1 + stderr に machine-readable key=... 出力
#
# round-1 findings 対応 (MED-1/MED-2/MED-3/MED-5/HIGH-1/HIGH-2/MED-9/SC2097 等):
#   - inline bash 再実装を廃止し、本 smoke 自身の --check-drift path を再実行することで
#     本体 _detect_drifts / _normalize_value / _extract_loader_defaults の全連携を検証する
#   - LOADER / YML は env override 経由で渡す (script 冒頭 `${LOADER:-...}` で受ける)
#   - mktemp は BSD 互換 `mktemp -t <prefix>.XXXXXX` (macOS 対応)
#   - trap で INT/TERM/EXIT でも tmp file cleanup 保証
#   - sed pattern は値非依存 `HC_CONTEXT_BUDGET_THRESHOLD="[^"]*"` で SSoT 値変更耐性化
#   - 置換成功を grep で assert (silent no-op fall-through 検出)
#   - cp / sed の失敗を明示 || return
# ============================================================
_case_c() (
  set -uo pipefail
  # 現状 drift 0 のはずなので --check-drift = exit 0
  local out rc
  out=$(bash "${SCRIPT_DIR}/config-loader-yml-drift-smoke.sh" --check-drift 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    printf 'Case C: --check-drift 期待 exit 0 だが rc=%d\n%s\n' "$rc" "$out" >&2
    return 1
  fi

  # 人工 drift 注入 sanity
  local tmp_loader
  tmp_loader=$(mktemp -t config-loader-drift-test.XXXXXX) || {
    printf 'Case C: mktemp fail\n' >&2
    return 1
  }
  # cleanup 保証 (Ctrl-C / trap 中断でも残骸 0)
  trap 'rm -f "$tmp_loader" "${tmp_loader}.bak" 2>/dev/null || true' EXIT INT TERM

  cp "$LOADER" "$tmp_loader" || {
    printf 'Case C: cp fail (LOADER=%s)\n' "$LOADER" >&2
    return 1
  }
  # 意図的 drift: HC_CONTEXT_BUDGET_THRESHOLD を 0.99 に変える
  # 値非依存 pattern (SSoT の 0.66 が将来 0.70 等に変わっても追随、round-1 HIGH-2 対応)
  sed -i.bak -E 's|^HC_CONTEXT_BUDGET_THRESHOLD="[^"]*"|HC_CONTEXT_BUDGET_THRESHOLD="0.99"|' "$tmp_loader" || {
    printf 'Case C: sed fail\n' >&2
    return 1
  }
  rm -f "${tmp_loader}.bak"
  # 置換成功を assert (silent no-op fall-through 検出、round-1 HIGH-2 対応)
  if ! grep -q '^HC_CONTEXT_BUDGET_THRESHOLD="0.99"' "$tmp_loader"; then
    printf 'Case C: 人工 drift 注入失敗 (sed pattern miss、loader 側 HC_CONTEXT_BUDGET_THRESHOLD 記述が変わった可能性)\n' >&2
    return 1
  fi

  # 本 smoke 自身の --check-drift を LOADER env override で再実行 (round-1 MED-1/MED-3/MED-5 対応)
  # env prefix は export で child bash に伝搬させる (SC2097/SC2098 回避、round-1 MED-11 対応)
  local drift_out drift_rc
  drift_out=$(LOADER="$tmp_loader" YML="$YML" bash "${SCRIPT_DIR}/config-loader-yml-drift-smoke.sh" --check-drift 2>&1)
  drift_rc=$?

  if [ "$drift_rc" -eq 0 ]; then
    printf 'Case C: 人工 drift 注入 sanity fail: drift 検出できず (rc=0)\n%s\n' "$drift_out" >&2
    return 1
  fi
  if [ "$drift_rc" -eq 2 ]; then
    printf 'Case C: 人工 drift 注入 sanity fail: extract 失敗 (rc=2)\n%s\n' "$drift_out" >&2
    return 1
  fi
  if ! printf '%s' "$drift_out" | grep -q 'key=HC_CONTEXT_BUDGET_THRESHOLD'; then
    printf 'Case C: machine-readable format 不備: expected key=HC_CONTEXT_BUDGET_THRESHOLD in stderr\n%s\n' "$drift_out" >&2
    return 1
  fi
  printf 'Case C: --check-drift exit 0 (drift 0)、人工注入で exit 1 + machine-readable format 動作 (本 smoke --check-drift path 再実行経由)\n' >&2
  return 0
)

# ============================================================
# Run
# ============================================================
printf '=== config-loader yml drift smoke (task-106 W1-4 Step 2) ===\n'

if _case_a 2>&1; then _record PASS A "全 HC_* default vs yml value の drift 0 件"; else _record FAIL A "全 HC_* default vs yml value の drift 0 件"; fi
if _case_b 2>&1; then _record PASS B "env override (HC_CONTEXT_BUDGET_THRESHOLD=0.42) 優先順"; else _record FAIL B "env override (HC_CONTEXT_BUDGET_THRESHOLD=0.42) 優先順"; fi
if _case_c 2>&1; then _record PASS C "--check-drift helper mode の machine-readable format"; else _record FAIL C "--check-drift helper mode の machine-readable format"; fi

printf '\n=== Result: %d PASS, %d FAIL ===\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'FAILED cases:%s\n' "$FAILED_CASES" >&2
  exit 1
fi
exit 0
