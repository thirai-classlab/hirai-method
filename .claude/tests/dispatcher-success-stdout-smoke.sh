#!/usr/bin/env bash
# dispatcher-success-stdout-smoke.sh — task-71 Fix-A (H1) strict-JSON success-stdout smoke
#
# 目的 (盲点封鎖):
#   dispatcher 非 block (成功) 時の stdout が常に「空 OR 単一 valid JSON OR plain text」で
#   あり、`{}{}{}` / `{...}{}` / `{...}{...}` のような複数連結 JSON object でないことを
#   node か python の strict parse で機械検証する。
#   旧 dispatcher-core.sh は非 block 子の `{}` (no-op decision JSON) を無条件連結し、
#   team-default/strict preset (複数 stdout-block hook 有効) で `{}{}{}` を生成 →
#   JSON.parse REJECT、autonomous-action-guard の additionalContext 喪失を招いていた。
#   Fix-A は no-op を drop、複数 meaningful JSON を additionalContext merge で単一 object に畳む。
#
# 検証ケース:
#   T1 全子 no-op ({})            → dispatcher stdout 空 (DoD「成功時 stdout 空」)
#   T2 単一 meaningful JSON       → 単一 valid JSON (verbatim)、strict parse OK
#   T3 autonomous-context + 後続 {} → additionalContext 保持 + 単一 valid JSON (no-op 喪失なし)
#   T4 複数 meaningful JSON 連結   → 単一 valid JSON に merge (両 additionalContext 保持)
#   T5 plain text (system-reminder) → 非 JSON だが strict「単一 value」OK (verbatim plain)
#   T6 plain + {} no-op           → plain のみ残り verbatim (no-op drop)
#   T7 plain 2 件                 → verbatim 連結 (plain text 群、Case 1 互換)
#
# strict parse: node か python3 のどちらか available な方で「文字列全体が単一 JSON value か」
#   を判定。plain text (JSON でない) は「JSON ではない単一 text」として許容 (複数 JSON 連結のみ NG)。
#
# 実行: bash .claude/tests/dispatcher-success-stdout-smoke.sh
# 終了: 0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# recon 規約: file-top set -u、隔離 tmp dir + trap cleanup、PASS/FAIL カウント。bash 3.2 互換。

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_LIB="$REPO_ROOT/.claude/hooks/lib/dispatcher-core.sh"
PROJECT_ROOT_LIB="$REPO_ROOT/.claude/hooks/lib/project-root.sh"
CONFIG_LOADER_LIB="$REPO_ROOT/.claude/hooks/lib/config-loader.sh"

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/dispatcher-success-stdout-smoke.XXXXXX")"
trap 'rm -rf "$TMPBASE"' EXIT

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }

# --- strict JSON parser 選定 -------------------------------------------------
# 戻り値:
#   classify_stdout <string>  → "empty" / "json" / "plain" / "multi-json"
#     empty      : 空白のみ
#     json       : 文字列全体が単一 valid JSON value
#     plain      : JSON ではない (= plain text、単一 text とみなす)
#     multi-json : 複数の JSON value 連結 (`{}{}` 等) = 不正
PARSER=""
if command -v node >/dev/null 2>&1; then
  PARSER="node"
elif command -v python3 >/dev/null 2>&1; then
  PARSER="python3"
elif command -v python >/dev/null 2>&1; then
  PARSER="python"
fi
# H1: node/python3 双方不在なら exit 77 (skip code) で終了し CI が「未実行」と区別できるようにする
# (silent exit 0 PASS をやめる — CI 側で 77 は skip として扱う)
NODE_H1=0; PY3_H1=0
command -v node    >/dev/null 2>&1 && NODE_H1=1
command -v python3 >/dev/null 2>&1 && PY3_H1=1

classify_stdout() {
  _s="$1"
  _trim="$(printf '%s' "$_s" | tr -d '[:space:]')"
  if [ -z "$_trim" ]; then
    printf 'empty'
    return 0
  fi
  case "$PARSER" in
    node)
      printf '%s' "$_s" | node -e '
        const fs = require("fs");
        const data = fs.readFileSync(0, "utf8");
        // 単一 JSON value か判定
        try { JSON.parse(data); console.log("json"); process.exit(0); } catch (e) {}
        // 複数連結 JSON object 検出: 連続する }{ で split し各片が JSON object なら multi-json
        const m = data.match(/\}\s*\{/);
        if (m) {
          // 1 個目が { で始まり } を含むなら JSON 連結とみなす
          if (/^\s*[\[{]/.test(data)) { console.log("multi-json"); process.exit(0); }
        }
        // JSON で始まるのに parse 失敗 = 不正 JSON 連結扱い
        if (/^\s*[\[{]/.test(data)) {
          // 先頭が { だが単一 parse 不可 → 連結 or 破損 → multi-json として NG 扱い
          console.log("multi-json"); process.exit(0);
        }
        console.log("plain");
      '
      ;;
    python3|python)
      printf '%s' "$_s" | "$PARSER" -c '
import sys, json
data = sys.stdin.read()
s = data.strip()
try:
    json.loads(data)
    print("json"); sys.exit(0)
except Exception:
    pass
# JSON で始まるのに single-parse 不可 → 連結 / 破損 → multi-json (NG)
if s[:1] in "{[":
    print("multi-json"); sys.exit(0)
print("plain")
'
      ;;
    *)
      printf 'no-parser'
      ;;
  esac
}

# --- 合成テスト環境 (core-smoke と同 pattern) --------------------------------
FAKE_ROOT="$TMPBASE/fakeproj"
FAKE_HOOKS="$FAKE_ROOT/.claude/hooks"
FAKE_LIB="$FAKE_HOOKS/lib"
mkdir -p "$FAKE_LIB" "$FAKE_ROOT/.claude"
cp "$PROJECT_ROOT_LIB"   "$FAKE_LIB/project-root.sh"
cp "$CONFIG_LOADER_LIB"  "$FAKE_LIB/config-loader.sh"
cp "$CORE_LIB"           "$FAKE_LIB/dispatcher-core.sh"
cat > "$FAKE_ROOT/.claude/harness-config.yml" <<'YML'
feature_smoke_on_enabled: true
YML

make_child() {
  printf '%s\n' "#!/usr/bin/env bash" "set -uo pipefail" "$2" > "$FAKE_HOOKS/$1"
  chmod 755 "$FAKE_HOOKS/$1"
}

# no-op 子: {} を出す (no-op decision JSON)
make_child "child-noop.sh"   'cat >/dev/null; printf "{}"; exit 0'
make_child "child-noop2.sh"  'cat >/dev/null; printf "{}"; exit 0'
# meaningful JSON 子 (additionalContext) — autonomous-action-guard 非 block 相当
make_child "child-ctx-a.sh"  'cat >/dev/null; printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"CTX-ALPHA\"}}"; exit 0'
make_child "child-ctx-b.sh"  'cat >/dev/null; printf "%s" "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"additionalContext\":\"CTX-BRAVO\"}}"; exit 0'
# plain text (system-reminder) 子 — why-x5 / context-budget 相当
make_child "child-plain-a.sh" 'cat >/dev/null; printf "%s" "<system-reminder>PLAIN-ONE</system-reminder>"; exit 0'
make_child "child-plain-b.sh" 'cat >/dev/null; printf "%s" "<system-reminder>PLAIN-TWO</system-reminder>"; exit 0'

write_manifest() {
  {
    printf 'event\tmatcher\torder\thook_command\tfeature_key\tchannel\tchild_timeout\n'
    printf '%s\n' "$@"
  } > "$FAKE_HOOKS/dispatcher-manifest.tsv"
}

# stdout / rc を capture
run_dispatch_fake() {
  _event="$1"; _matcher="$2"; _payload="$3"
  _errf="$TMPBASE/stderr.$$"
  SMOKE_OUT="$(
    HC_PROJECT_ROOT="$FAKE_ROOT" \
    HC_CONFIG_PATH="$FAKE_ROOT/.claude/harness-config.yml" \
    bash -c '
      set -uo pipefail
      source "'"$FAKE_LIB/dispatcher-core.sh"'"
      run_dispatch "'"$_event"'" "'"$_matcher"'"
    ' <<<"$_payload" 2>"$_errf"
  )"
  SMOKE_RC=$?
  rm -f "$_errf"
}

row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5" "$6" "$7"; }

echo "== dispatcher-success-stdout-smoke =="
if [ -z "$PARSER" ]; then
  echo "  H1: node / python3 双方不在 → exit 77 (CI skip code、silent PASS ではない)"
  echo "== result: SKIP/77 (no parser — node and python3 both absent) =="
  exit 77
fi
echo "  (strict parser: $PARSER)"

# ---------------------------------------------------------------------------
# T1: 全子 no-op ({}) → dispatcher stdout 空 (DoD「成功時 stdout 空」)
#     team-default 相当: 同 matcher に複数 stdout-block hook を有効化し全て非 block。
# ---------------------------------------------------------------------------
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 child-noop.sh  '' stdout-block 5)" \
  "$(row PreToolUse 'Edit|Write' 2 child-noop2.sh '' stdout-block 5)" \
  "$(row PreToolUse 'Edit|Write' 3 child-noop.sh  '' stdout-block 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" '{"tool_name":"Edit"}'
cls="$(classify_stdout "$SMOKE_OUT")"
if [ "$SMOKE_RC" -eq 0 ] && [ "$cls" = "empty" ]; then
  ok "T1 全子 no-op {} → stdout 空 (DoD) rc=0"
else
  bad "T1 expected empty/rc0, got cls=$cls rc=$SMOKE_RC out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# T2: 単一 meaningful JSON → 単一 valid JSON (verbatim)
# ---------------------------------------------------------------------------
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 child-noop.sh  '' stdout-block 5)" \
  "$(row PreToolUse 'Edit|Write' 2 child-ctx-a.sh '' stdout-block 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" '{"tool_name":"Edit"}'
cls="$(classify_stdout "$SMOKE_OUT")"
case "$SMOKE_OUT" in
  *CTX-ALPHA*) has_ctx=1 ;;
  *) has_ctx=0 ;;
esac
if [ "$cls" = "json" ] && [ "$has_ctx" -eq 1 ]; then
  ok "T2 単一 meaningful JSON → 単一 valid JSON + additionalContext 保持"
else
  bad "T2 expected json+CTX-ALPHA, got cls=$cls out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# T3: autonomous additionalContext + 後続 {} → additionalContext 保持 + 単一 valid JSON
#     (旧バグ: {...}{} で additionalContext 喪失 / 不正 JSON)
# ---------------------------------------------------------------------------
write_manifest \
  "$(row PreToolUse 'Bash' 1 child-ctx-a.sh '' stdout-block 5)" \
  "$(row PreToolUse 'Bash' 2 child-noop.sh  '' stdout-block 5)" \
  "$(row PreToolUse 'Bash' 3 child-noop2.sh '' stdout-block 5)"
run_dispatch_fake "PreToolUse" "Bash" '{"tool_name":"Bash"}'
cls="$(classify_stdout "$SMOKE_OUT")"
case "$SMOKE_OUT" in *CTX-ALPHA*) has_ctx=1 ;; *) has_ctx=0 ;; esac
if [ "$cls" = "json" ] && [ "$has_ctx" -eq 1 ]; then
  ok "T3 ctx + 後続 {} → 単一 valid JSON + additionalContext 保持 (no-op 喪失なし)"
else
  bad "T3 expected json+CTX-ALPHA (no {} concat), got cls=$cls out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# T4: 複数 meaningful JSON 連結 → 単一 valid JSON に merge (両 additionalContext 保持)
#     (PreToolUse Agent|Task: parallel-subagent-reminder + reviewer-count-guard 相当)
# ---------------------------------------------------------------------------
write_manifest \
  "$(row PreToolUse 'Agent|Task' 1 child-ctx-a.sh '' advisory 5)" \
  "$(row PreToolUse 'Agent|Task' 2 child-ctx-b.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Agent|Task" '{"tool_name":"Task"}'
cls="$(classify_stdout "$SMOKE_OUT")"
case "$SMOKE_OUT" in *CTX-ALPHA*CTX-BRAVO*|*CTX-BRAVO*CTX-ALPHA*) has_both=1 ;; *) has_both=0 ;; esac
if [ "$cls" = "json" ] && [ "$has_both" -eq 1 ]; then
  ok "T4 複数 meaningful JSON → 単一 valid JSON に merge (両 additionalContext 保持)"
else
  bad "T4 expected single json with both ctx, got cls=$cls out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# T5: plain text (system-reminder) → 非 JSON 単一 text (multi-json でない)
# ---------------------------------------------------------------------------
write_manifest \
  "$(row UserPromptSubmit '' 1 child-plain-a.sh '' advisory 5)"
run_dispatch_fake "UserPromptSubmit" "" '{}'
cls="$(classify_stdout "$SMOKE_OUT")"
case "$SMOKE_OUT" in *PLAIN-ONE*) has_p=1 ;; *) has_p=0 ;; esac
if [ "$cls" = "plain" ] && [ "$has_p" -eq 1 ]; then
  ok "T5 単一 plain text → plain (非 multi-json)、verbatim 保持"
else
  bad "T5 expected plain+PLAIN-ONE, got cls=$cls out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# T6: plain + {} no-op → plain のみ残り verbatim (no-op drop、混在で multi-json 化しない)
# ---------------------------------------------------------------------------
write_manifest \
  "$(row PostToolUse '*' 1 child-plain-a.sh '' advisory 5)" \
  "$(row PostToolUse '*' 2 child-noop.sh    '' advisory 5)"
run_dispatch_fake "PostToolUse" "*" '{}'
cls="$(classify_stdout "$SMOKE_OUT")"
case "$SMOKE_OUT" in *PLAIN-ONE*) has_p=1 ;; *) has_p=0 ;; esac
case "$SMOKE_OUT" in *'{}'*) has_noop=1 ;; *) has_noop=0 ;; esac
if [ "$cls" = "plain" ] && [ "$has_p" -eq 1 ] && [ "$has_noop" -eq 0 ]; then
  ok "T6 plain + {} → plain のみ verbatim (no-op {} drop)"
else
  bad "T6 expected plain w/o {}, got cls=$cls noop=$has_noop out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# T7: plain 2 件 → verbatim 連結 (plain text 群、既存 Case 1 互換、multi-json でない)
# ---------------------------------------------------------------------------
write_manifest \
  "$(row Stop '' 1 child-plain-a.sh '' advisory 5)" \
  "$(row Stop '' 2 child-plain-b.sh '' advisory 5)"
run_dispatch_fake "Stop" "" '{}'
cls="$(classify_stdout "$SMOKE_OUT")"
case "$SMOKE_OUT" in *PLAIN-ONE*PLAIN-TWO*) has_both=1 ;; *) has_both=0 ;; esac
if [ "$cls" = "plain" ] && [ "$has_both" -eq 1 ]; then
  ok "T7 plain 2 件 → verbatim 連結 (plain text 群、非 multi-json)"
else
  bad "T7 expected plain w/ both reminders, got cls=$cls out='$SMOKE_OUT'"
fi

echo "== result: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ]
