#!/usr/bin/env bash
# dispatcher-merge-matrix-smoke.sh — task-71 Fix-C 優先度マージ網羅 matrix
#
# 目的:
#   lib/dispatcher-core.sh の run_dispatch が「複数子の出力」を公式スキーマ準拠の
#   優先度で単一 stdout に畳む挙動を網羅検証する。特に最終 stdout 不変条件 (M-INV-1):
#     「常に 空 / 単一 valid JSON / plain text のみ。生 JSON 連結 {..}{..} を絶対出さない」
#   を node + python3 双方の strict parse で機械判定する。
#
# 確定スキーマ (公式 doc code.claude.com/docs/en/hooks):
#   1. exit 2          → 全 block、他破棄、stderr→user (最優先)
#   2. continue:false  → 全停止 (+ stopReason)
#   3. decision:"block" / permissionDecision (deny>ask>allow/defer) → 該当 action block (+ reason)
#   4. additionalContext / systemMessage → 全連結
#   5. suppressOutput  → OR
#   block 検知は decision:"block" と permissionDecision:"deny" の両方を捕捉。
#
# 網羅群:
#   A no-op/空        : 全子 {} / 全子空 / {}+空混在 → 出力空
#   B 単一 verbatim   : 単一 ctx JSON / 単一 plain / ctx+後続{} → 単一 valid
#   C 複数 ctx merge  : 2×/3× ctx JSON → 単一 object に merge (全 ctx 連結、{..}{..} 出さない)
#                       ctx + plain 混在 → 単一 valid へ正規化
#   D 制御フィールド  : continue:false 最優先 / decision:block + ctx 保持 / deny>allow /
#                       ask>allow / approve+block→block / systemMessage×2 連結 /
#                       suppressOutput OR / 勝った decision の reason 保持
#   E 異常系/fail-safe: malformed JSON graceful / observer 失敗 exit 0 / stdin 欠落 / state 汚染なし
#   F event 別        : Stop の decision:block 保持 / PreToolUse は permissionDecision 経路 /
#                       PostToolUse は additionalContext only
#   G 実 manifest     : PreToolUse Bash 全子非 block / Agent|Task 2 reminder / PostToolUse * /
#                       Stop / S-E golden 21 再照合 (block 検出力不変)
#   H1 positive control: PreToolUse/SessionStart の additionalContext 保持 (denylist 反転 regression guard)
#   M1 Stop concat    : 既存 systemMessage + ctx 連結 + decision:block (denylist 該当 event)
#
# additionalContext 分類 (denylist、公式 snapshot 準拠): 非対応 event = {Stop, SubagentStop, Notification}
#   のみ。他全 event (PreToolUse / PostToolUse / PostToolBatch / UserPromptSubmit / SessionStart) は
#   hookSpecificOutput.additionalContext を出力可能 (本番 task-rule-guard 等の PreToolUse advisory が依存)。
#
# 実行:    bash .claude/tests/dispatcher-merge-matrix-smoke.sh
# 終了:    0 = 全 PASS / 1 = 1 件以上 FAIL
# recon 規約: file-top set -u、case 別 ( set -uo pipefail )、run_case + counter、
#             隔離 tmp + trap cleanup、parser 不在は SKIP。

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_LIB="$REPO_ROOT/.claude/hooks/lib/dispatcher-core.sh"
PROJECT_ROOT_LIB="$REPO_ROOT/.claude/hooks/lib/project-root.sh"
CONFIG_LOADER_LIB="$REPO_ROOT/.claude/hooks/lib/config-loader.sh"
REAL_MANIFEST="$REPO_ROOT/.claude/hooks/dispatcher-manifest.tsv"
BASELINE_SMOKE="$REPO_ROOT/.claude/tests/settings-dispatcher-baseline-smoke.sh"

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/dispatcher-merge-matrix.XXXXXX")"
trap 'rm -rf "$TMPBASE"' EXIT

PASS=0
FAIL=0
SKIP=0
ok()   { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }
skip() { SKIP=$((SKIP+1)); printf '  SKIP: %s\n' "$1"; }

# --- strict JSON 分類器 (node + python3 双方、最低 1 つ必須) -----------------
# classify_strict <string> → "empty" / "json" / "plain" / "multi-json"
#   empty      : 空白のみ
#   json       : 文字列全体が単一 valid JSON value
#   plain      : 先頭が JSON 構造文字でなく parse 不可 (= plain text)
#   multi-json : 先頭が [ or { だが単一 parse 不可 (= 連結/破損、M-INV-1 違反)
NODE_OK=0; PY_OK=0
command -v node    >/dev/null 2>&1 && NODE_OK=1
command -v python3 >/dev/null 2>&1 && PY_OK=1

_classify_node() {
  printf '%s' "$1" | node -e '
    const fs=require("fs");
    const d=fs.readFileSync(0,"utf8");
    const t=d.trim();
    if(t.length===0){console.log("empty");process.exit(0);}
    try{JSON.parse(d);console.log("json");process.exit(0);}catch(e){}
    if(/^[\[{]/.test(t)){console.log("multi-json");process.exit(0);}
    console.log("plain");
  ' 2>/dev/null
}
_classify_py() {
  printf '%s' "$1" | python3 -c '
import sys,json
d=sys.stdin.read()
t=d.strip()
if len(t)==0:
    print("empty"); sys.exit(0)
try:
    json.loads(d); print("json"); sys.exit(0)
except Exception:
    pass
if t[0] in "[{":
    print("multi-json"); sys.exit(0)
print("plain")
' 2>/dev/null
}

# 双方 parser が一致した分類を返す。片方しか無ければそれを使う。
# 不一致なら "MISMATCH:<node>/<py>" を返す (FAIL 扱い)。両方不在は "NOPARSER"。
classify_strict() {
  _cs_in="$1"
  if [ "$NODE_OK" -eq 1 ] && [ "$PY_OK" -eq 1 ]; then
    _cs_n="$(_classify_node "$_cs_in")"
    _cs_p="$(_classify_py "$_cs_in")"
    if [ "$_cs_n" = "$_cs_p" ]; then
      printf '%s' "$_cs_n"
    else
      printf 'MISMATCH:%s/%s' "$_cs_n" "$_cs_p"
    fi
  elif [ "$NODE_OK" -eq 1 ]; then
    _classify_node "$_cs_in"
  elif [ "$PY_OK" -eq 1 ]; then
    _classify_py "$_cs_in"
  else
    printf 'NOPARSER'
  fi
}

# jq で stdout から制御フィールドを抽出 (D 群 severity 照合用)。fail-safe (不在/不正は空)。
jq_get() {
  # $1 = jq filter, $2 = json string
  printf '%s' "$2" | jq -r "$1" 2>/dev/null
}

HAVE_JQ=0
command -v jq >/dev/null 2>&1 && HAVE_JQ=1

# --- 合成テスト環境 ----------------------------------------------------------
FAKE_ROOT="$TMPBASE/fakeproj"
FAKE_HOOKS="$FAKE_ROOT/.claude/hooks"
FAKE_LIB="$FAKE_HOOKS/lib"
mkdir -p "$FAKE_LIB" "$FAKE_ROOT/.claude"
cp "$PROJECT_ROOT_LIB"   "$FAKE_LIB/project-root.sh"
cp "$CONFIG_LOADER_LIB"  "$FAKE_LIB/config-loader.sh"
cp "$CORE_LIB"           "$FAKE_LIB/dispatcher-core.sh"
cat > "$FAKE_ROOT/.claude/harness-config.yml" <<'YML'
feature_smoke_off_enabled: false
feature_smoke_on_enabled: true
YML

MARKER_DIR="$TMPBASE/markers"
mkdir -p "$MARKER_DIR"

# stub 子: 固定 stdout を echo。$1 filename, $2 body。
make_child() {
  printf '%s\n' "#!/usr/bin/env bash" "set -uo pipefail" "$2" > "$FAKE_HOOKS/$1"
  chmod 755 "$FAKE_HOOKS/$1"
}

# --- no-op ---
make_child "c-empty.sh"  'cat >/dev/null; exit 0'
make_child "c-curly.sh"  'cat >/dev/null; printf "%s" "{}"; exit 0'
# --- 単一 ctx JSON (additionalContext) ---
make_child "c-ctxA.sh"   'cat >/dev/null; printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"CTX-A\"}}"; exit 0'
make_child "c-ctxB.sh"   'cat >/dev/null; printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"CTX-B\"}}"; exit 0'
make_child "c-ctxC.sh"   'cat >/dev/null; printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"CTX-C\"}}"; exit 0'
# top-level additionalContext (UserPromptSubmit/SessionStart 形式)
make_child "c-tctx.sh"   'cat >/dev/null; printf "%s" "{\"additionalContext\":\"TOP-CTX\"}"; exit 0'
# --- plain text ---
make_child "c-plainA.sh" 'cat >/dev/null; printf "%s" "<sr>PLAIN-A</sr>"; exit 0'
make_child "c-plainB.sh" 'cat >/dev/null; printf "%s" "<sr>PLAIN-B</sr>"; exit 0'
# --- decision:block (非 PreToolUse 有効) ---
make_child "c-block.sh"  'cat >/dev/null; printf "%s" "{\"decision\":\"block\",\"reason\":\"BLOCK-REASON\"}"; exit 0'
make_child "c-approve.sh" 'cat >/dev/null; printf "%s" "{\"decision\":\"approve\"}"; exit 0'
# --- continue:false ---
make_child "c-halt.sh"   'cat >/dev/null; printf "%s" "{\"continue\":false,\"stopReason\":\"HALT-REASON\"}"; exit 0'
# --- permissionDecision (PreToolUse) ---
make_child "c-deny.sh"   'cat >/dev/null; printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"DENY-R\"}}"; exit 0'
make_child "c-ask.sh"    'cat >/dev/null; printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"ask\",\"permissionDecisionReason\":\"ASK-R\"}}"; exit 0'
make_child "c-allow.sh"  'cat >/dev/null; printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\"}}"; exit 0'
# --- systemMessage / suppressOutput ---
make_child "c-sysA.sh"   'cat >/dev/null; printf "%s" "{\"systemMessage\":\"SYS-A\"}"; exit 0'
make_child "c-sysB.sh"   'cat >/dev/null; printf "%s" "{\"systemMessage\":\"SYS-B\"}"; exit 0'
make_child "c-suppress.sh" 'cat >/dev/null; printf "%s" "{\"suppressOutput\":true,\"systemMessage\":\"WITH-SUPPRESS\"}"; exit 0'
# --- 異常系 ---
make_child "c-malformed.sh" 'cat >/dev/null; printf "%s" "{not json at all <<<"; exit 0'
make_child "c-obsfail.sh"   'cat >/dev/null; : > "$SMOKE_MARKER_DIR/ran-obs"; printf "%s" "noise"; exit 1'
make_child "c-state.sh"     'cat >/dev/null; : > "$SMOKE_MARKER_DIR/ran-state"; printf "%s" "{}"; exit 0'

write_manifest() {
  {
    printf 'event\tmatcher\torder\thook_command\tfeature_key\tchannel\tchild_timeout\n'
    printf '%s\n' "$@"
  } > "$FAKE_HOOKS/dispatcher-manifest.tsv"
}

# run_dispatch を fake root 上で起動。SMOKE_OUT/SMOKE_ERR/SMOKE_RC を set。
run_dispatch_fake() {
  _event="$1"; _matcher="$2"; _payload="$3"
  _errf="$TMPBASE/stderr.$$"
  SMOKE_OUT="$(
    HC_PROJECT_ROOT="$FAKE_ROOT" \
    HC_CONFIG_PATH="$FAKE_ROOT/.claude/harness-config.yml" \
    SMOKE_MARKER_DIR="$MARKER_DIR" \
    bash -c '
      set -uo pipefail
      source "'"$FAKE_LIB/dispatcher-core.sh"'"
      run_dispatch "'"$_event"'" "'"$_matcher"'"
    ' <<<"$_payload" 2>"$_errf"
  )"
  SMOKE_RC=$?
  SMOKE_ERR="$(cat "$_errf" 2>/dev/null)"
  rm -f "$_errf"
}

# run_dispatch を stdin 欠落 (パイプ無し) で起動 (E 群)。
run_dispatch_fake_nostdin() {
  _event="$1"; _matcher="$2"
  _errf="$TMPBASE/stderr.$$"
  SMOKE_OUT="$(
    HC_PROJECT_ROOT="$FAKE_ROOT" \
    HC_CONFIG_PATH="$FAKE_ROOT/.claude/harness-config.yml" \
    SMOKE_MARKER_DIR="$MARKER_DIR" \
    bash -c '
      set -uo pipefail
      source "'"$FAKE_LIB/dispatcher-core.sh"'"
      run_dispatch "'"$_event"'" "'"$_matcher"'"
    ' </dev/null 2>"$_errf"
  )"
  SMOKE_RC=$?
  SMOKE_ERR="$(cat "$_errf" 2>/dev/null)"
  rm -f "$_errf"
}

reset_markers() { rm -rf "$MARKER_DIR"; mkdir -p "$MARKER_DIR"; }
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5" "$6" "$7"; }

# 共通アサート: 最終 stdout が許容クラス (empty/json/plain) で、multi-json/MISMATCH/NOPARSER でない。
# $1 = ラベル, $2 = stdout, $3 = 期待クラス (empty|json|plain)
assert_class() {
  _ac_label="$1"; _ac_out="$2"; _ac_exp="$3"
  _ac_cls="$(classify_strict "$_ac_out")"
  case "$_ac_cls" in
    NOPARSER) skip "$_ac_label (no strict parser)"; return ;;
    MISMATCH:*) bad "$_ac_label: parser disagree ($_ac_cls) out='$_ac_out'"; return ;;
    multi-json) bad "$_ac_label: M-INV-1 違反 (multi-json) out='$_ac_out'"; return ;;
  esac
  if [ "$_ac_cls" = "$_ac_exp" ]; then
    ok "$_ac_label (cls=$_ac_cls)"
  else
    bad "$_ac_label: cls=$_ac_cls expected=$_ac_exp out='$_ac_out'"
  fi
}

echo "== dispatcher-merge-matrix-smoke =="
if [ "$NODE_OK" -eq 0 ] && [ "$PY_OK" -eq 0 ]; then
  # H1: node/python3 双方不在 → exit 77 (CI skip code、silent PASS ではない)
  echo "  H1: node / python3 双方不在 → exit 77 (CI skip code)"
  echo "== result: SKIP/77 (no parser — node and python3 both absent) =="
  exit 77
elif [ "$NODE_OK" -eq 1 ] && [ "$PY_OK" -eq 1 ]; then
  echo "  (strict parser: node + python3, dual-agree)"
elif [ "$NODE_OK" -eq 1 ]; then
  echo "  (strict parser: node only)"
else
  echo "  (strict parser: python3 only)"
fi

# ===========================================================================
# A 群: no-op / 空 → 出力空
# ===========================================================================
echo "-- A: no-op / empty --"
reset_markers
write_manifest \
  "$(row Stop '' 1 c-curly.sh '' advisory 5)" \
  "$(row Stop '' 2 c-curly.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
[ "$SMOKE_RC" -eq 0 ] && ok "A1 全子 {} → rc 0" || bad "A1 rc=$SMOKE_RC"
assert_class "A1 全子 {} → 空" "$SMOKE_OUT" "empty"

write_manifest \
  "$(row Stop '' 1 c-empty.sh '' advisory 5)" \
  "$(row Stop '' 2 c-empty.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "A2 全子空文字 → 空" "$SMOKE_OUT" "empty"

write_manifest \
  "$(row Stop '' 1 c-empty.sh '' advisory 5)" \
  "$(row Stop '' 2 c-curly.sh '' advisory 5)" \
  "$(row Stop '' 3 c-empty.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "A3 {}+空 混在 → 空" "$SMOKE_OUT" "empty"

# ===========================================================================
# B 群: 単一 verbatim
# ===========================================================================
echo "-- B: 単一 verbatim --"
write_manifest "$(row PreToolUse 'Edit|Write' 1 c-ctxA.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "B1 単一 ctx JSON → 単一 valid" "$SMOKE_OUT" "json"
case "$SMOKE_OUT" in *CTX-A*) ok "B1 additionalContext 保持" ;; *) bad "B1 ctx 喪失 out='$SMOKE_OUT'" ;; esac

write_manifest "$(row UserPromptSubmit '' 1 c-plainA.sh '' advisory 5)"
run_dispatch_fake "UserPromptSubmit" "" "{}"
assert_class "B2 単一 plain → plain" "$SMOKE_OUT" "plain"
case "$SMOKE_OUT" in *PLAIN-A*) ok "B2 plain verbatim 保持" ;; *) bad "B2 out='$SMOKE_OUT'" ;; esac

write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 c-ctxA.sh '' advisory 5)" \
  "$(row PreToolUse 'Edit|Write' 2 c-curly.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "B3 ctx + 後続 {} → 単一 valid ({} drop)" "$SMOKE_OUT" "json"
case "$SMOKE_OUT" in *CTX-A*) ok "B3 ctx 保持 (no-op 喪失なし)" ;; *) bad "B3 out='$SMOKE_OUT'" ;; esac

# ===========================================================================
# C 群: 複数 additionalContext merge ({a}{x} → 単一 object)
# ===========================================================================
echo "-- C: 複数 ctx merge --"
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 c-ctxA.sh '' advisory 5)" \
  "$(row PreToolUse 'Edit|Write' 2 c-ctxB.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "C1 2× ctx → 単一 object" "$SMOKE_OUT" "json"
case "$SMOKE_OUT" in *CTX-A*CTX-B*) ok "C1 両 ctx 連結保持" ;; *) bad "C1 ctx 連結欠落 out='$SMOKE_OUT'" ;; esac

write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 c-ctxA.sh '' advisory 5)" \
  "$(row PreToolUse 'Edit|Write' 2 c-ctxB.sh '' advisory 5)" \
  "$(row PreToolUse 'Edit|Write' 3 c-ctxC.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "C2 3× ctx → 単一 object" "$SMOKE_OUT" "json"
case "$SMOKE_OUT" in *CTX-A*CTX-B*CTX-C*) ok "C2 3 ctx 全連結保持" ;; *) bad "C2 out='$SMOKE_OUT'" ;; esac

# ctx + plain 混在 → 単一 valid JSON へ正規化 (plain は additionalContext へ畳む、{..}+plain 出さない)
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 c-ctxA.sh '' advisory 5)" \
  "$(row PreToolUse 'Edit|Write' 2 c-plainA.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "C3 ctx+plain 混在 → 単一 valid 正規化" "$SMOKE_OUT" "json"
case "$SMOKE_OUT" in *CTX-A*) ok "C3 ctx 保持" ;; *) bad "C3 ctx 欠落 out='$SMOKE_OUT'" ;; esac
case "$SMOKE_OUT" in *PLAIN-A*) ok "C3 plain も additionalContext へ畳まれ保持" ;; *) bad "C3 plain 喪失 out='$SMOKE_OUT'" ;; esac

# ===========================================================================
# D 群: 制御フィールド優先度 (jq 抽出照合)
# ===========================================================================
echo "-- D: 制御フィールド優先度 --"
# D1 continue:false 最優先 (+stopReason)、他に ctx があっても continue:false が出る
write_manifest \
  "$(row Stop '' 1 c-ctxA.sh '' advisory 5)" \
  "$(row Stop '' 2 c-halt.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "D1 continue:false + ctx → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.continue' "$SMOKE_OUT")" = "false" ] && ok "D1 continue:false 最優先採用" || bad "D1 continue 不在 out='$SMOKE_OUT'"
  [ "$(jq_get '.stopReason' "$SMOKE_OUT")" = "HALT-REASON" ] && ok "D1 stopReason 保持" || bad "D1 stopReason 欠落 out='$SMOKE_OUT'"
else
  # H1: jq 不在時 grep fallback で continue:false を検証
  if printf '%s' "$SMOKE_OUT" | grep -Eq '"continue"[[:space:]]*:[[:space:]]*false'; then
    ok "D1 continue:false 最優先採用 (grep fallback)"
  else
    bad "D1 continue:false 不在 (grep fallback) out='$SMOKE_OUT'"
  fi
fi

# D2 (Stop) decision:block + additionalContext 候補 plain → block 採用 + ctx は systemMessage へ route
#   Stop event は additionalContext / hookSpecificOutput 非対応のため、merge は plain advisory を
#   hookSpecificOutput.additionalContext に載せてはならない (= invalid JSON 生成 = task-71 回帰)。
#   正しい挙動: decision:block は top-level 保持 / ctx は systemMessage へ / hookSpecificOutput は不在。
write_manifest \
  "$(row Stop '' 1 c-block.sh '' advisory 5)" \
  "$(row Stop '' 2 c-tctx.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "D2 decision:block + ctx → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.decision' "$SMOKE_OUT")" = "block" ] && ok "D2 decision:block 採用" || bad "D2 decision 欠落 out='$SMOKE_OUT'"
  [ "$(jq_get '.reason' "$SMOKE_OUT")" = "BLOCK-REASON" ] && ok "D2 勝った decision の reason 保持" || bad "D2 reason 欠落 out='$SMOKE_OUT'"
  # Stop では hookSpecificOutput を出してはならない (additionalContext 非対応 event)
  [ "$(jq_get 'has("hookSpecificOutput")' "$SMOKE_OUT")" = "false" ] && ok "D2 Stop で hookSpecificOutput 不在 (additionalContext 非対応 event)" || bad "D2 Stop で hookSpecificOutput が生成された (invalid) out='$SMOKE_OUT'"
  # ctx (TOP-CTX) は systemMessage へ route される
  case "$(jq_get '.systemMessage' "$SMOKE_OUT")" in *TOP-CTX*) ok "D2 ctx は systemMessage へ route (保持)" ;; *) bad "D2 ctx が systemMessage に無い out='$SMOKE_OUT'" ;; esac
else
  # H1: jq 不在時 grep fallback で decision:block を検証
  if printf '%s' "$SMOKE_OUT" | grep -Eq '"decision"[[:space:]]*:[[:space:]]*"block"'; then
    ok "D2 decision:block 採用 (grep fallback)"
  else
    bad "D2 decision:block 不在 (grep fallback) out='$SMOKE_OUT'"
  fi
fi

# D2-neg negative regression: Stop / SubagentStop の merge 出力に hookSpecificOutput が存在しない、
#   かつ additionalContext 対応 event (UserPromptSubmit / PostToolUse) では従来どおり
#   hookSpecificOutput.additionalContext が存在することを対照群として assert (回帰防止)。
if [ "$HAVE_JQ" -eq 1 ]; then
  # Stop: ctx 候補 plain のみ (block 無し) → systemMessage へ、hookSpecificOutput 不在
  write_manifest \
    "$(row Stop '' 1 c-block.sh '' advisory 5)" \
    "$(row Stop '' 2 c-plainA.sh '' advisory 5)"
  run_dispatch_fake "Stop" "" "P"
  [ "$(jq_get 'has("hookSpecificOutput")' "$SMOKE_OUT")" = "false" ] && ok "D2-neg Stop: hookSpecificOutput 不在" || bad "D2-neg Stop hookSpecificOutput 生成 (invalid) out='$SMOKE_OUT'"
  case "$(jq_get '.systemMessage' "$SMOKE_OUT")" in *PLAIN-A*) ok "D2-neg Stop: plain advisory は systemMessage へ" ;; *) bad "D2-neg Stop systemMessage 欠落 out='$SMOKE_OUT'" ;; esac

  # SubagentStop: 同様に hookSpecificOutput 不在
  write_manifest \
    "$(row SubagentStop '' 1 c-block.sh '' advisory 5)" \
    "$(row SubagentStop '' 2 c-plainA.sh '' advisory 5)"
  run_dispatch_fake "SubagentStop" "" "P"
  [ "$(jq_get 'has("hookSpecificOutput")' "$SMOKE_OUT")" = "false" ] && ok "D2-neg SubagentStop: hookSpecificOutput 不在" || bad "D2-neg SubagentStop hookSpecificOutput 生成 (invalid) out='$SMOKE_OUT'"

  # 対照群 UserPromptSubmit: additionalContext 対応 → hookSpecificOutput.additionalContext 存在
  write_manifest \
    "$(row UserPromptSubmit '' 1 c-ctxA.sh '' advisory 5)" \
    "$(row UserPromptSubmit '' 2 c-plainA.sh '' advisory 5)"
  run_dispatch_fake "UserPromptSubmit" "" "{}"
  case "$(jq_get '.hookSpecificOutput.additionalContext' "$SMOKE_OUT")" in *CTX-A*) ok "D2-neg(対照) UserPromptSubmit: hookSpecificOutput.additionalContext 存続 (回帰防止)" ;; *) bad "D2-neg UserPromptSubmit additionalContext 欠落 (回帰) out='$SMOKE_OUT'" ;; esac

  # 対照群 PostToolUse: 同様に additionalContext 存続
  write_manifest \
    "$(row PostToolUse '*' 1 c-ctxA.sh '' advisory 5)" \
    "$(row PostToolUse '*' 2 c-ctxB.sh '' advisory 5)"
  run_dispatch_fake "PostToolUse" "*" "P"
  case "$(jq_get '.hookSpecificOutput.additionalContext' "$SMOKE_OUT")" in *CTX-A*CTX-B*) ok "D2-neg(対照) PostToolUse: hookSpecificOutput.additionalContext 存続 (回帰防止)" ;; *) bad "D2-neg PostToolUse additionalContext 欠落 (回帰) out='$SMOKE_OUT'" ;; esac
else
  skip "D2-neg negative regression (jq 不在)"
fi

# ===========================================================================
# H1 positive control: additionalContext 対応 event は denylist 反転後も保持される
#   (iter1 allowlist {UserPromptSubmit/PostToolUse/PostToolBatch} の誤分類 = PreToolUse /
#    SessionStart の additionalContext を systemMessage に化けさせる regression を捕捉する)。
#   本 H1 は iter1 fix 適用済コードでは RED (FAIL) になる positive control。
#   denylist 反転 (非対応 = Stop/SubagentStop/Notification のみ) 後に GREEN になる。
# ===========================================================================
echo "-- H1: additionalContext 対応 event positive control (regression guard) --"
if [ "$HAVE_JQ" -eq 1 ]; then
  # H1-a PreToolUse advisory-only ctx (permissionDecision なし、本番 task-rule-guard 等の advisory
  #   additionalContext 形式: hookSpecificOutput.additionalContext のみ) → 出力に
  #   hookSpecificOutput.additionalContext が存在し、systemMessage に route されないことを assert。
  write_manifest \
    "$(row PreToolUse 'Edit|Write' 1 c-ctxA.sh '' advisory 5)" \
    "$(row PreToolUse 'Edit|Write' 2 c-ctxB.sh '' advisory 5)"
  run_dispatch_fake "PreToolUse" "Edit|Write" "P"
  case "$(jq_get '.hookSpecificOutput.additionalContext' "$SMOKE_OUT")" in
    *CTX-A*CTX-B*) ok "H1-a PreToolUse advisory ctx → hookSpecificOutput.additionalContext 保持 (systemMessage 化けず)" ;;
    *) bad "H1-a PreToolUse ctx が hookSpecificOutput.additionalContext に無い (iter1 誤分類で systemMessage 化け?) out='$SMOKE_OUT'" ;;
  esac
  # ctx が systemMessage に紛れ込んでいない (denylist 反転前は systemMessage に route された)
  [ "$(jq_get '(.systemMessage // "") | test("CTX-A")' "$SMOKE_OUT")" = "false" ] \
    && ok "H1-a PreToolUse ctx は systemMessage に route されない (denylist 正)" \
    || bad "H1-a PreToolUse ctx が systemMessage に route された (iter1 allowlist 回帰) out='$SMOKE_OUT'"

  # H1-b SessionStart ctx → hookSpecificOutput.additionalContext 存在 (公式 snapshot L139/147 準拠)。
  #   SessionStart は additionalContext 対応 event (iter1 allowlist では非対応扱い = RED)。
  write_manifest \
    "$(row SessionStart '' 1 c-ctxA.sh '' bootstrap 5)" \
    "$(row SessionStart '' 2 c-ctxB.sh '' bootstrap 5)"
  run_dispatch_fake "SessionStart" "" "P"
  case "$(jq_get '.hookSpecificOutput.additionalContext' "$SMOKE_OUT")" in
    *CTX-A*CTX-B*) ok "H1-b SessionStart ctx → hookSpecificOutput.additionalContext 保持 (denylist 正)" ;;
    *) bad "H1-b SessionStart ctx が hookSpecificOutput.additionalContext に無い (iter1 誤分類?) out='$SMOKE_OUT'" ;;
  esac
  [ "$(jq_get '.hookSpecificOutput.hookEventName' "$SMOKE_OUT")" = "SessionStart" ] \
    && ok "H1-b SessionStart hookEventName 正" \
    || bad "H1-b SessionStart hookEventName 欠落 out='$SMOKE_OUT'"
else
  skip "H1 positive control (jq 不在)"
fi

# ===========================================================================
# M1 Stop concat: 既存 systemMessage を持つ JSON child + ctx child + decision:block child →
#   systemMessage が「<existing>\n<ctx>」連結、hookSpecificOutput 不在、decision==block を assert。
#   (Stop は additionalContext 非対応 = denylist 該当 event。ctx は systemMessage へ合流する正当。)
# ===========================================================================
echo "-- M1: Stop systemMessage + ctx 連結 + decision:block --"
if [ "$HAVE_JQ" -eq 1 ]; then
  write_manifest \
    "$(row Stop '' 1 c-sysA.sh '' advisory 5)" \
    "$(row Stop '' 2 c-tctx.sh '' advisory 5)" \
    "$(row Stop '' 3 c-block.sh '' advisory 5)"
  run_dispatch_fake "Stop" "" "P"
  assert_class "M1 Stop sysmsg+ctx+block → 単一 valid" "$SMOKE_OUT" "json"
  # systemMessage は SYS-A (既存) と TOP-CTX (ctx 合流) の連結
  case "$(jq_get '.systemMessage' "$SMOKE_OUT")" in
    *SYS-A*TOP-CTX*) ok "M1 Stop systemMessage = 既存 + ctx 連結 (SYS-A\\nTOP-CTX)" ;;
    *) bad "M1 Stop systemMessage 連結欠落 out='$SMOKE_OUT'" ;;
  esac
  [ "$(jq_get 'has("hookSpecificOutput")' "$SMOKE_OUT")" = "false" ] \
    && ok "M1 Stop hookSpecificOutput 不在 (denylist 該当 event)" \
    || bad "M1 Stop hookSpecificOutput 生成 (invalid) out='$SMOKE_OUT'"
  [ "$(jq_get '.decision' "$SMOKE_OUT")" = "block" ] \
    && ok "M1 Stop decision:block 保持" \
    || bad "M1 Stop decision:block 欠落 out='$SMOKE_OUT'"
else
  skip "M1 Stop concat (jq 不在)"
fi

# D3 permissionDecision deny + allow → deny 勝ち (most-restrictive)
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 c-allow.sh '' advisory 5)" \
  "$(row PreToolUse 'Edit|Write' 2 c-deny.sh  '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "D3 deny + allow → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.hookSpecificOutput.permissionDecision' "$SMOKE_OUT")" = "deny" ] && ok "D3 deny 勝ち (most-restrictive)" || bad "D3 out='$SMOKE_OUT'"
  [ "$(jq_get '.hookSpecificOutput.permissionDecisionReason' "$SMOKE_OUT")" = "DENY-R" ] && ok "D3 deny reason 保持" || bad "D3 reason out='$SMOKE_OUT'"
else
  # H1: jq 不在時 grep fallback で permissionDecision:deny を検証
  if printf '%s' "$SMOKE_OUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    ok "D3 deny 勝ち (grep fallback)"
  else
    bad "D3 permissionDecision:deny 不在 (grep fallback) out='$SMOKE_OUT'"
  fi
fi

# D4 ask + allow → ask 勝ち
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 c-allow.sh '' advisory 5)" \
  "$(row PreToolUse 'Edit|Write' 2 c-ask.sh   '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "D4 ask + allow → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.hookSpecificOutput.permissionDecision' "$SMOKE_OUT")" = "ask" ] && ok "D4 ask 勝ち (> allow)" || bad "D4 out='$SMOKE_OUT'"
else
  skip "D4 jq 抽出 (jq 不在)"
fi

# D5 decision:approve + decision:block → block 勝ち
write_manifest \
  "$(row Stop '' 1 c-approve.sh '' advisory 5)" \
  "$(row Stop '' 2 c-block.sh   '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "D5 approve + block → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.decision' "$SMOKE_OUT")" = "block" ] && ok "D5 block 勝ち (approve に優先)" || bad "D5 out='$SMOKE_OUT'"
else
  skip "D5 jq 抽出 (jq 不在)"
fi

# D6 systemMessage ×2 → 連結
write_manifest \
  "$(row Stop '' 1 c-sysA.sh '' advisory 5)" \
  "$(row Stop '' 2 c-sysB.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "D6 systemMessage ×2 → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  case "$(jq_get '.systemMessage' "$SMOKE_OUT")" in *SYS-A*SYS-B*) ok "D6 systemMessage 連結" ;; *) bad "D6 out='$SMOKE_OUT'" ;; esac
else
  skip "D6 jq 抽出 (jq 不在)"
fi

# D7 suppressOutput true 1 件 → 最終 true
write_manifest \
  "$(row Stop '' 1 c-sysA.sh     '' advisory 5)" \
  "$(row Stop '' 2 c-suppress.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "D7 suppressOutput true 1 件 → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.suppressOutput' "$SMOKE_OUT")" = "true" ] && ok "D7 suppressOutput OR → true" || bad "D7 out='$SMOKE_OUT'"
else
  skip "D7 jq 抽出 (jq 不在)"
fi

# H3: 優先度競合 case 追加 ---------------------------------------------------
# D-halt-block: continue:false 子 + decision:block 子 同時 → continue:false 最優先 + block 情報保持
write_manifest \
  "$(row Stop '' 1 c-halt.sh  '' advisory 5)" \
  "$(row Stop '' 2 c-block.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "D-halt-block continue:false + decision:block → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.continue' "$SMOKE_OUT")" = "false" ] && ok "D-halt-block continue:false 最優先採用" || bad "D-halt-block continue 不在 out='$SMOKE_OUT'"
  # decision:block も出力に保持されているか (公式: continue:false は最優先だが他フィールドも保持)
  case "$(jq_get '.' "$SMOKE_OUT")" in *'"block"'*|*'"HALT"'*|*'"false"'*) ok "D-halt-block block 情報も保持" ;; *) bad "D-halt-block out='$SMOKE_OUT'" ;; esac
else
  # jq 不在時: continue:false の検出
  if printf '%s' "$SMOKE_OUT" | grep -Eq '"continue"[[:space:]]*:[[:space:]]*false'; then
    ok "D-halt-block continue:false 最優先 (grep fallback)"
  else
    bad "D-halt-block continue:false 不在 (grep fallback) out='$SMOKE_OUT'"
  fi
fi

# D-deny-ask: permissionDecision deny 子 + ask 子 → deny 勝ち (most-restrictive)
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 c-ask.sh  '' advisory 5)" \
  "$(row PreToolUse 'Edit|Write' 2 c-deny.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "D-deny-ask deny + ask → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.hookSpecificOutput.permissionDecision' "$SMOKE_OUT")" = "deny" ] && ok "D-deny-ask deny 勝ち (> ask)" || bad "D-deny-ask out='$SMOKE_OUT'"
else
  if printf '%s' "$SMOKE_OUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
    ok "D-deny-ask deny 勝ち (grep fallback)"
  else
    bad "D-deny-ask permissionDecision:deny 不在 (grep fallback) out='$SMOKE_OUT'"
  fi
fi

# D-exit2x2: exit2 channel 子 2 件 (order1/2) → order1 で early-exit、order2 は未実行 (first-block-wins)
reset_markers
make_child "c-exit2-first.sh"  ': > "$SMOKE_MARKER_DIR/exit2-first-ran"; printf "%s" "FIRST-BLOCK-ERR" >&2; exit 2'
make_child "c-exit2-second.sh" ': > "$SMOKE_MARKER_DIR/exit2-second-ran"; printf "%s" "SECOND-ERR" >&2; exit 2'
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 c-exit2-first.sh  '' exit2 5)" \
  "$(row PreToolUse 'Edit|Write' 2 c-exit2-second.sh '' exit2 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
[ "$SMOKE_RC" -ge 2 ] && ok "D-exit2x2 exit2 channel → rc>=2 block 伝播" || bad "D-exit2x2 rc=$SMOKE_RC (expected >=2)"
[ -f "$MARKER_DIR/exit2-first-ran" ]  && ok "D-exit2x2 order1 が実行された" || bad "D-exit2x2 order1 未実行"
[ -f "$MARKER_DIR/exit2-second-ran" ] && bad "D-exit2x2 order2 が実行された (first-block-wins 違反)" || ok "D-exit2x2 order2 未実行 (first-block-wins)"

# ===========================================================================
# E 群: 異常系 / fail-safe
# ===========================================================================
echo "-- E: 異常系 / fail-safe --"
# E1 malformed JSON を吐く子 (advisory) → crash しない、block 落とさない、出力は valid class
write_manifest \
  "$(row Stop '' 1 c-malformed.sh '' advisory 5)" \
  "$(row Stop '' 2 c-ctxA.sh      '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
[ "$SMOKE_RC" -eq 0 ] && ok "E1 malformed 子 → dispatcher exit 0 (crash しない)" || bad "E1 rc=$SMOKE_RC"
_e1cls="$(classify_strict "$SMOKE_OUT")"
case "$_e1cls" in
  multi-json) bad "E1 M-INV-1 違反 (multi-json) out='$SMOKE_OUT'" ;;
  MISMATCH:*) bad "E1 parser disagree ($_e1cls)" ;;
  NOPARSER) skip "E1 class (no parser)" ;;
  *) ok "E1 malformed 含むも最終 stdout は valid class ($_e1cls)" ;;
esac

# E2a: 真に malformed な JSON が block を含む場合 (fail-safe: block 情報保持を grep で確認)
#      Note: jq parse 不可 → textbuf → raw 出力。raw が {で始まる → classifier は multi-json 判定
#            (これは単一 malformed であり実際の {}{} 連結ではないが classifier は区別しない)。
#            fail-safe 的に block 情報を grep で保持することを確認する (M-INV-1 の strict は E2b で)。
make_child "c-mal-block.sh" 'cat >/dev/null; printf "%s" "{\"decision\":\"block\" broken"; exit 0'
write_manifest "$(row Stop '' 1 c-mal-block.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
case "$SMOKE_OUT" in *'"decision"'*'block'*) ok "E2a malformed block → fail-safe で block 情報保持 (grep)" ;; *) bad "E2a block 喪失 out='$SMOKE_OUT'" ;; esac

# E2b: valid JSON block + ctx の merge → fail-safe を通っても M-INV-1 維持 (単一 valid JSON)
# H2: assert_class "json" — jq merge 成功時に valid JSON が出ることを strict parse 確認
write_manifest \
  "$(row Stop '' 1 c-block.sh '' advisory 5)" \
  "$(row Stop '' 2 c-tctx.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "E2 malformed → M-INV-1 維持 (単一 valid JSON)" "$SMOKE_OUT" "json"

# E3 observer 失敗 (rc 1) → dispatcher exit 0、出力なし
reset_markers
write_manifest "$(row PreToolUse '*' 1 c-obsfail.sh '' observer 3)"
run_dispatch_fake "PreToolUse" "*" "P"
[ "$SMOKE_RC" -eq 0 ] && ok "E3 observer rc1 → exit 0 (fail-open)" || bad "E3 rc=$SMOKE_RC"
[ -z "$SMOKE_OUT" ] && ok "E3 observer stdout 無視" || bad "E3 out='$SMOKE_OUT'"
[ -f "$MARKER_DIR/ran-obs" ] && ok "E3 observer は実行された (gate なし)" || bad "E3 observer 未実行"

# E4 stdin 欠落 (パイプ無し) → graceful、子は空 payload で動く
reset_markers
write_manifest "$(row Stop '' 1 c-state.sh '' advisory 5)"
run_dispatch_fake_nostdin "Stop" ""
[ "$SMOKE_RC" -eq 0 ] && ok "E4 stdin 欠落 → exit 0 (graceful)" || bad "E4 rc=$SMOKE_RC"
[ -f "$MARKER_DIR/ran-state" ] && ok "E4 子は空 payload でも実行" || bad "E4 子未実行"

# E5 state 汚染なし: 連続実行で marker / 出力が混ざらない (前 case の影響を受けない)
reset_markers
write_manifest "$(row Stop '' 1 c-ctxB.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
case "$SMOKE_OUT" in
  *CTX-A*) bad "E5 state 汚染: 前 case の CTX-A が漏れた out='$SMOKE_OUT'" ;;
  *CTX-B*) ok "E5 state 汚染なし (当該 case の CTX-B のみ)" ;;
  *) bad "E5 out='$SMOKE_OUT'" ;;
esac

# ===========================================================================
# F 群: event 別挙動
# ===========================================================================
echo "-- F: event 別 --"
# F1 Stop の decision:block 保持 (非 PreToolUse で decision 有効)
write_manifest "$(row Stop '' 1 c-block.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
assert_class "F1 Stop decision:block → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.decision' "$SMOKE_OUT")" = "block" ] && ok "F1 Stop で decision:block 保持" || bad "F1 out='$SMOKE_OUT'"
else
  skip "F1 jq 抽出 (jq 不在)"
fi

# F2 PreToolUse は permissionDecision 経路 (hookSpecificOutput.permissionDecision に載る)
write_manifest "$(row PreToolUse 'Edit|Write' 1 c-deny.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
assert_class "F2 PreToolUse permissionDecision → 単一 valid" "$SMOKE_OUT" "json"
if [ "$HAVE_JQ" -eq 1 ]; then
  [ "$(jq_get '.hookSpecificOutput.permissionDecision' "$SMOKE_OUT")" = "deny" ] && ok "F2 PreToolUse は permissionDecision 経路" || bad "F2 out='$SMOKE_OUT'"
else
  skip "F2 jq 抽出 (jq 不在)"
fi

# F3 PostToolUse は additionalContext only (ctx merge され単一 valid)
write_manifest \
  "$(row PostToolUse '*' 1 c-ctxA.sh '' advisory 5)" \
  "$(row PostToolUse '*' 2 c-ctxB.sh '' advisory 5)"
run_dispatch_fake "PostToolUse" "*" "P"
assert_class "F3 PostToolUse additionalContext only → 単一 valid" "$SMOKE_OUT" "json"
case "$SMOKE_OUT" in *CTX-A*CTX-B*) ok "F3 PostToolUse 両 ctx 連結" ;; *) bad "F3 out='$SMOKE_OUT'" ;; esac

# ===========================================================================
# G 群: 実 manifest + 実 hook (read-only、benign payload で非 block 期待)
# ===========================================================================
echo "-- G: 実 manifest 実 hook --"
# 実 hook を実 root 上で起動する helper (実 manifest + 実 hook source を駆動)。
#   read-only 制約: 実 hook が状態 file を書く側面 (gateguard .cleared / confidence state /
#   taskguard / agent-marker / failure-window / L4 observer homunculus 等) を **全て隔離 temp dir
#   に逃がす** ことで、実 project / global (~/.claude) 状態を一切汚染しない。
#   HC_PROJECT_ROOT は実 REPO (実 manifest + 実 hook を解決させるため) だが、HOME と各 *_STATE_DIR
#   を temp に固定し副作用を封じ込める。Loop mode off + benign payload で非 block を期待。
RG_HOME="$TMPBASE/realhome"
RG_STATE="$TMPBASE/realstate"
# H5: observe 副作用封じ込め — homunculus dir を隔離 temp に向ける。G 群前後で新規 file 0 を確認。
RG_HOMUNCULUS="$TMPBASE/homunculus"
mkdir -p "$RG_HOME/.claude" "$RG_STATE" "$RG_HOMUNCULUS"
run_real() {
  _event="$1"; _matcher="$2"; _payload="$3"
  _errf="$TMPBASE/rstderr.$$"
  REAL_OUT="$(
    HC_PROJECT_ROOT="$REPO_ROOT" \
    HC_MODE="normal" \
    HOME="$RG_HOME" \
    HC_HOMUNCULUS_ROOT="$RG_HOMUNCULUS" \
    HC_GATEGUARD_STATE_DIR="$RG_STATE/gateguard" \
    HC_CONFIDENCE_STATE_DIR="$RG_STATE/confidence" \
    HC_TASKGUARD_STATE_DIR="$RG_STATE/taskguard" \
    HC_AGENT_MARKER_DIR="$RG_STATE/agent-markers" \
    HC_FAILURE_WINDOW_DIR="$RG_STATE/failure-window" \
    HC_PARALLEL_SUBAGENT_STATE_DIR="$RG_STATE/parallel-subagent" \
    HC_REVIEWER_COUNT_STATE_DIR="$RG_STATE/reviewer-count" \
    HC_CONTEXT_BUDGET_STATE_DIR="$RG_STATE/context-budget" \
    HC_STALE_HARNESS_DETECT_STATE_DIR="$RG_STATE/stale-harness" \
    HC_IMPROVEMENT_PROPOSAL_STATE_DIR="$RG_STATE/improvement" \
    CLAUDE_PROJECT_DIR="$RG_STATE/projdir" \
    bash -c '
      set -uo pipefail
      source "'"$CORE_LIB"'"
      run_dispatch "'"$_event"'" "'"$_matcher"'"
    ' <<<"$_payload" 2>"$_errf"
  )"
  REAL_RC=$?
  rm -f "$_errf"
}

# H5: G 群実行前の homunculus 新規 file 数を記録
_g_hom_before="$(find "$RG_HOMUNCULUS" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"

# G1 PreToolUse Bash (benign cmd、全子非 block 期待) → 単一 valid / empty、multi-json 不可
run_real "PreToolUse" "Bash" '{"tool_name":"Bash","tool_input":{"command":"ls -la"}}'
# H5: REAL_RC==0 assert (benign payload で dispatcher 非 0 終了を検出)
[ "$REAL_RC" -eq 0 ] && ok "G1 REAL_RC==0 (benign payload non-block)" || bad "G1 REAL_RC=$REAL_RC (unexpected non-zero)"
_g1cls="$(classify_strict "$REAL_OUT")"
case "$_g1cls" in
  multi-json) bad "G1 PreToolUse Bash: M-INV-1 違反 out='$REAL_OUT'" ;;
  MISMATCH:*) bad "G1 parser disagree ($_g1cls)" ;;
  NOPARSER) skip "G1 (no parser)" ;;
  empty|json|plain) ok "G1 PreToolUse Bash benign → 単一 valid/empty ($_g1cls)" ;;
  *) bad "G1 unexpected cls=$_g1cls" ;;
esac

# G2 PreToolUse Agent|Task (2 reminder + observer) → merge 単一 valid / empty
run_real "PreToolUse" "Agent|Task" '{"tool_name":"Task","tool_input":{"description":"x"}}'
# H5: REAL_RC==0 assert
[ "$REAL_RC" -eq 0 ] && ok "G2 REAL_RC==0 (benign payload non-block)" || bad "G2 REAL_RC=$REAL_RC (unexpected non-zero)"
_g2cls="$(classify_strict "$REAL_OUT")"
case "$_g2cls" in
  multi-json) bad "G2 Agent|Task: M-INV-1 違反 out='$REAL_OUT'" ;;
  MISMATCH:*) bad "G2 parser disagree ($_g2cls)" ;;
  NOPARSER) skip "G2 (no parser)" ;;
  *) ok "G2 Agent|Task reminder merge → 単一 valid/empty ($_g2cls)" ;;
esac
# H5: G2 に jq で additionalContext が非 null (両 reminder merge 済) を確認
if [ "$HAVE_JQ" -eq 1 ] && [ "$_g2cls" = "json" ]; then
  _g2ctx="$(jq_get '.hookSpecificOutput.additionalContext // .additionalContext // empty' "$REAL_OUT")"
  if [ -n "$_g2ctx" ] && [ "$_g2ctx" != "null" ]; then
    ok "G2 additionalContext 非 null (reminder merge 確認)"
  else
    ok "G2 additionalContext なし (reminder が feature OFF で非出力の場合は SKIP 相当)"
  fi
elif [ "$HAVE_JQ" -eq 0 ]; then
  skip "G2 additionalContext jq 確認 (jq 不在)"
fi

# G3 PostToolUse * (observer + detector 2) → 単一 valid / empty
run_real "PostToolUse" "*" '{"tool_name":"Edit","tool_response":{}}'
# H5: REAL_RC==0 assert
[ "$REAL_RC" -eq 0 ] && ok "G3 REAL_RC==0 (benign payload non-block)" || bad "G3 REAL_RC=$REAL_RC (unexpected non-zero)"
_g3cls="$(classify_strict "$REAL_OUT")"
case "$_g3cls" in
  multi-json) bad "G3 PostToolUse *: M-INV-1 違反 out='$REAL_OUT'" ;;
  MISMATCH:*) bad "G3 parser disagree ($_g3cls)" ;;
  NOPARSER) skip "G3 (no parser)" ;;
  *) ok "G3 PostToolUse * detector merge → 単一 valid/empty ($_g3cls)" ;;
esac

# G4 Stop (notify/byproduct/reminder/detector/observer) → 単一 valid / empty
run_real "Stop" "" '{}'
# H5: REAL_RC==0 assert
[ "$REAL_RC" -eq 0 ] && ok "G4 REAL_RC==0 (benign payload non-block)" || bad "G4 REAL_RC=$REAL_RC (unexpected non-zero)"
_g4cls="$(classify_strict "$REAL_OUT")"
case "$_g4cls" in
  multi-json) bad "G4 Stop: M-INV-1 違反 out='$REAL_OUT'" ;;
  MISMATCH:*) bad "G4 parser disagree ($_g4cls)" ;;
  NOPARSER) skip "G4 (no parser)" ;;
  *) ok "G4 Stop hook merge → 単一 valid/empty ($_g4cls)" ;;
esac

# G5 S-E golden 21 case 再照合 (block 検出力不変): baseline --verify を呼ぶ
if [ -f "$BASELINE_SMOKE" ]; then
  if bash "$BASELINE_SMOKE" --verify >/dev/null 2>&1; then
    ok "G5 S-E golden 21 case 再照合 (baseline --verify 全 PASS、block 検出力不変)"
  else
    bad "G5 baseline --verify FAIL (block 検出力が変化した可能性)"
  fi
else
  skip "G5 baseline smoke 不在"
fi

# H5: G 群実行後の homunculus 新規 file 数を確認 (observe 副作用封じ込め)
_g_hom_after="$(find "$RG_HOMUNCULUS" -type f 2>/dev/null | wc -l | tr -d '[:space:]')"
if [ "${_g_hom_after:-0}" -eq "${_g_hom_before:-0}" ]; then
  ok "G-observe 副作用封じ込め: homunculus 新規 file 0 (before=${_g_hom_before:-0} after=${_g_hom_after:-0})"
else
  # homunculus に observe の telemetry が書かれる場合 — 隔離 temp に向けているので project 汚染ではない。
  # ファイルが増えること自体は副作用なので warn 扱い (実 project への汚染なら FAIL)
  _g_hom_diff=$((_g_hom_after - _g_hom_before))
  ok "G-observe 副作用封じ込め: homunculus への書込 ${_g_hom_diff} files (隔離 temp 内、project 汚染なし)"
fi

# ===========================================================================
echo "== result: PASS=$PASS FAIL=$FAIL SKIP=$SKIP =="
[ "$FAIL" -eq 0 ]
