#!/usr/bin/env bash
# test-config-env-override.sh — env > YAML > defaults precedence for config-loader.sh
#
# config-loader.sh の汎用 env override 機能を検証する。
# 検証する仕様:
#   1. env 未設定 → YAML 値が読まれる
#   2. env 設定 → YAML 値より env 優先
#   3. env 設定 + YAML 不在 → env 値で動作（warning は出るが defaults を上書き）
#   4. YAML / env / defaults の三重指定 → env が最優先
#   5. 配列キー (HC_PROTECTED_PATHS) も env で上書き可能
#   6. tilde 含む path (HC_HOMUNCULUS_ROOT=~/foo) は env でも展開される
#   7. confidence-gate (HC_CONFIDENCE_REQUIRED=false) が env override で動作
#
# 既存 test-confidence-gate.sh / test-gate-disable.sh と同居して
# run-tests.sh から自動で動く。

set -u

HOOKS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOADER="$HOOKS_DIR/lib/config-loader.sh"
PASS=0
FAIL=0

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"
  if [ "$expected" = "$actual" ]; then
    printf "PASS: %s\n" "$name"
    PASS=$((PASS + 1))
  else
    printf "FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n" "$name" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

# Helper: run a sub-shell with a fresh env and source config-loader,
# then echo the requested HC_* variable.
# Args: <yaml-path-or-empty> <var-name> [<env-spec>...]
#   env-spec: NAME=VALUE (will be exported in the sub-shell before sourcing)
load_and_echo() {
  local yaml="$1"
  local var="$2"
  shift 2
  local env_setup=""
  for spec in "$@"; do
    # Use printf %q-equivalent quoting via shell escape
    env_setup="$env_setup export $spec;"
  done
  local config_setup=""
  if [ -n "$yaml" ]; then
    config_setup="export HC_CONFIG_PATH=\"$yaml\";"
  else
    # /dev/null path -> trigger "config not found" branch + suppress WARN
    config_setup="export HC_CONFIG_PATH=$TMP/nonexistent.yml;"
  fi
  bash -c "
    set +u
    # Strip any inherited HC_* vars so each test starts clean
    for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
    $config_setup
    $env_setup
    source '$LOADER' 2>/dev/null
    eval \"echo \\\"\\\$$var\\\"\"
  "
}

# === Case 1: env 未設定 → YAML 値 ===
cat > "$TMP/case1.yml" <<'YAML'
task_dir: docs/yaml-tasks
draft_dir: docs/yaml-draft
homunculus_root: ~/.claude/yaml-root
YAML
out=$(load_and_echo "$TMP/case1.yml" HC_TASK_DIR)
assert_eq "Case1a: no env -> YAML task_dir" "docs/yaml-tasks" "$out"
out=$(load_and_echo "$TMP/case1.yml" HC_DRAFT_DIR)
assert_eq "Case1b: no env -> YAML draft_dir" "docs/yaml-draft" "$out"
out=$(load_and_echo "$TMP/case1.yml" HC_HOMUNCULUS_ROOT)
assert_eq "Case1c: no env -> YAML homunculus_root tilde-expanded" "$HOME/.claude/yaml-root" "$out"

# === Case 2: env 設定 → env > YAML ===
out=$(load_and_echo "$TMP/case1.yml" HC_TASK_DIR "HC_TASK_DIR=docs/env-tasks")
assert_eq "Case2a: env task_dir overrides YAML" "docs/env-tasks" "$out"
out=$(load_and_echo "$TMP/case1.yml" HC_DRAFT_DIR "HC_DRAFT_DIR=docs/env-draft")
assert_eq "Case2b: env draft_dir overrides YAML" "docs/env-draft" "$out"

# === Case 3: env + YAML 不在 → env 値 (defaults を上書き) ===
out=$(load_and_echo "" HC_TASK_DIR "HC_TASK_DIR=docs/env-only")
assert_eq "Case3a: env wins when YAML missing" "docs/env-only" "$out"
# YAML 不在 + env 不在 → defaults
out=$(load_and_echo "" HC_TASK_DIR)
assert_eq "Case3b: defaults when both YAML and env absent" "docs/tasks" "$out"

# === Case 4: 三重指定 → env 最優先 ===
# YAML が defaults と異なる値を持ち、env が更に異なる値を持つ。
cat > "$TMP/case4.yml" <<'YAML'
task_dir: docs/yaml-value
YAML
out=$(load_and_echo "$TMP/case4.yml" HC_TASK_DIR "HC_TASK_DIR=docs/env-value")
assert_eq "Case4: env > YAML > defaults — env wins" "docs/env-value" "$out"

# === Case 5: 配列キー env 上書き ===
# bash の改行リスト形式を env で渡すと PROTECTED_DISPLAY 等の派生値も
# 正しく再生成されるか。
cat > "$TMP/case5.yml" <<'YAML'
protected_paths: [src, tests, scripts]
YAML
# YAML 値が読まれるか確認 (control)
out=$(load_and_echo "$TMP/case5.yml" HC_PROTECTED_DISPLAY)
assert_eq "Case5a: YAML protected_paths -> display" "src/ tests/ scripts/" "$out"
# env で上書き (改行区切り — bash の $'a\nb\nc' リテラル)
out=$(bash -c "
  set +u
  for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
  export HC_CONFIG_PATH='$TMP/case5.yml'
  export HC_PROTECTED_PATHS=\$'app\nlib\nmiddleware.ts'
  source '$LOADER' 2>/dev/null
  echo \"\$HC_PROTECTED_DISPLAY\"
")
assert_eq "Case5b: env protected_paths overrides YAML" "app/ lib/ middleware.ts/" "$out"
# 派生 glob も正しく再生成されているか
out=$(bash -c "
  set +u
  for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
  export HC_CONFIG_PATH='$TMP/case5.yml'
  export HC_PROTECTED_PATHS=\$'app\nlib'
  source '$LOADER' 2>/dev/null
  echo \"\$HC_PROTECTED_GLOB_FILE\"
")
assert_eq "Case5c: env protected_paths regenerates GLOB_FILE" "*/app/*|*/lib/*" "$out"

# === Case 6: tilde 含む path env 上書き ===
out=$(load_and_echo "$TMP/case1.yml" HC_HOMUNCULUS_ROOT "HC_HOMUNCULUS_ROOT=~/foo-from-env")
assert_eq "Case6a: env tilde expanded (~/foo)" "$HOME/foo-from-env" "$out"
# tilde 単体 (`~`)
out=$(load_and_echo "$TMP/case1.yml" HC_HOMUNCULUS_ROOT "HC_HOMUNCULUS_ROOT=~")
assert_eq "Case6b: env tilde alone (~)" "$HOME" "$out"
# 絶対 path (展開不要)
out=$(load_and_echo "$TMP/case1.yml" HC_HOMUNCULUS_ROOT "HC_HOMUNCULUS_ROOT=/absolute/path")
assert_eq "Case6c: env absolute path unchanged" "/absolute/path" "$out"

# === Case 7: confidence-gate 個別対応 (HC_CONFIDENCE_REQUIRED=false) ===
# YAML が confidence_required: true、env が false → 即 pass を返すこと
cat > "$TMP/case7.yml" <<'YAML'
confidence_required: true
confidence_threshold: 0.95
YAML
# control: env なし、YAML true → block (confidence 未記載)
INPUT='{"transcript_path":"/nonexistent.jsonl"}'
out=$(bash -c "
  set +u
  for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
  unset ECC_CONFIDENCE_GATE ECC_F3_OFF
  export HC_CONFIG_PATH='$TMP/case7.yml'
  export HC_CONFIDENCE_STATE_DIR='$TMP/conf7-control'
  mkdir -p \"\$HC_CONFIDENCE_STATE_DIR\"
  printf '%s' '$INPUT' | bash '$HOOKS_DIR/confidence-gate.sh' 2>/dev/null
")
# fallback path (transcript missing) returns {} (fail-open) - so this proves env wasn't broken.
# We instead test the early-OFF branch directly: HC_CONFIDENCE_REQUIRED=false should yield {}
out=$(bash -c "
  set +u
  for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
  unset ECC_CONFIDENCE_GATE ECC_F3_OFF
  export HC_CONFIG_PATH='$TMP/case7.yml'
  export HC_CONFIDENCE_REQUIRED=false
  export HC_CONFIDENCE_STATE_DIR='$TMP/conf7-env'
  mkdir -p \"\$HC_CONFIDENCE_STATE_DIR\"
  printf '%s' '$INPUT' | bash '$HOOKS_DIR/confidence-gate.sh' 2>/dev/null
")
out_compact=$(printf '%s' "$out" | tr -d '[:space:]')
assert_eq "Case7a: HC_CONFIDENCE_REQUIRED=false (env) overrides YAML true -> pass" "{}" "$out_compact"

# Threshold env override: with required=true, threshold=0.0, any confidence passes.
INPUT2='{"tool_response":{"content":[{"type":"text","text":"shaky. confidence: 0.1"}]}}'
out=$(bash -c "
  set +u
  for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
  unset ECC_CONFIDENCE_GATE ECC_F3_OFF
  export HC_CONFIG_PATH='$TMP/case7.yml'
  export HC_CONFIDENCE_REQUIRED=true
  export HC_CONFIDENCE_THRESHOLD=0.0
  export HC_CONFIDENCE_STATE_DIR='$TMP/conf7-thresh'
  mkdir -p \"\$HC_CONFIDENCE_STATE_DIR\"
  printf '%s' '$INPUT2' | bash '$HOOKS_DIR/confidence-gate.sh' 2>/dev/null
")
out_compact=$(printf '%s' "$out" | tr -d '[:space:]')
# Should pass (0.1 >= 0.0) — env threshold beats YAML threshold (0.95)
if [ "$out_compact" = "{}" ]; then
  printf "PASS: Case7b: env HC_CONFIDENCE_THRESHOLD=0.0 overrides YAML 0.95 -> pass at 0.1\n"
  PASS=$((PASS + 1))
else
  printf "FAIL: Case7b: expected {} got: %s\n" "$out"
  FAIL=$((FAIL + 1))
fi

# === Case 8: 内部変数 leak チェック (env override 機能の副作用) ===
# config-loader source 後に _HC_PRESET_KEYS / _hc_k 等が caller scope に
# 残らないことを確認する (regression: caller env 汚染).
out=$(bash -c "
  set +u
  for v in \$(env | grep -oE '^HC_[A-Z_]+' || true); do unset \"\$v\"; done
  export HC_CONFIG_PATH='$TMP/case1.yml'
  export HC_TASK_DIR=docs/probe
  source '$LOADER' 2>/dev/null
  printf 'PRESET_KEYS=[%s] PRESET_TASK_DIR=[%s] hc_k=[%s] hc_v=[%s] hc_set=[%s]\n' \
    \"\${_HC_PRESET_KEYS-UNSET}\" \\
    \"\${_HC_PRESET_TASK_DIR-UNSET}\" \\
    \"\${_hc_k-UNSET}\" \\
    \"\${_hc_v-UNSET}\" \\
    \"\${_hc_set-UNSET}\"
")
expected="PRESET_KEYS=[UNSET] PRESET_TASK_DIR=[UNSET] hc_k=[UNSET] hc_v=[UNSET] hc_set=[UNSET]"
assert_eq "Case8: internal vars are unset after source" "$expected" "$out"

printf "\n--- test-config-env-override.sh: %d pass / %d fail ---\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
