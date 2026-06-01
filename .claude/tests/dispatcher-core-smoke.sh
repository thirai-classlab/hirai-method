#!/usr/bin/env bash
# dispatcher-core-smoke.sh — task-71 Step 4-6 unit smoke for lib/dispatcher-core.sh
#
# 目的:
#   run_dispatch の各 channel + 不変条件 (Step 4-6 spec §3 の 1-8) を
#   合成 manifest (fixture) + 合成 payload + stub 子 hook で検証する。
#   さらに live (実) manifest に対する read-only 健全性 check を 1 case 持つ。
#
# 検証する不変条件:
#   1. stdin replay        : 2 子が同 payload を受け取る
#   2. order + first-block : exit2 子で即 exit、後続子は未実行 (marker 不在で実証)
#   3. exit code 不変      : exit2 → exit 2 / stdout-block(block) → exit 0 + JSON
#   4. stderr 保持         : exit2 blocker の stderr が dispatcher stderr に出る
#   5. feature gate        : disabled feature の子は spawn されない (marker 不在で実証)
#   6. observer fail-open  : observer 子が rc 1 で死んでも dispatcher exit 0
#   7,8 は実 manifest 健全性 case で path 解決 (引数込み / ../skills/) を間接検証
#
# 実行:    bash .claude/tests/dispatcher-core-smoke.sh
# 終了:    0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# recon 規約: file-top `set -u`、case 別 `( set -uo pipefail )`、run_case + PASS/FAIL、
#             隔離 tmp dir + trap cleanup。

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CORE_LIB="$REPO_ROOT/.claude/hooks/lib/dispatcher-core.sh"
PROJECT_ROOT_LIB="$REPO_ROOT/.claude/hooks/lib/project-root.sh"
CONFIG_LOADER_LIB="$REPO_ROOT/.claude/hooks/lib/config-loader.sh"
REAL_MANIFEST="$REPO_ROOT/.claude/hooks/dispatcher-manifest.tsv"

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/dispatcher-core-smoke.XXXXXX")"
trap 'rm -rf "$TMPBASE"' EXIT

PASS=0
FAIL=0

ok()   { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }

# --- 合成テスト環境構築 ------------------------------------------------------
# 隔離 root に lib (project-root/config-loader/dispatcher-core) + stub 子 + 合成 manifest を置く。
# HC_PROJECT_ROOT で resolve_project_root を fake root に固定する。
FAKE_ROOT="$TMPBASE/fakeproj"
FAKE_HOOKS="$FAKE_ROOT/.claude/hooks"
FAKE_LIB="$FAKE_HOOKS/lib"
mkdir -p "$FAKE_LIB"
cp "$PROJECT_ROOT_LIB" "$FAKE_LIB/project-root.sh"
cp "$CONFIG_LOADER_LIB" "$FAKE_LIB/config-loader.sh"
cp "$CORE_LIB" "$FAKE_LIB/dispatcher-core.sh"
# harness-config.yml は無くても config-loader は fail-open で defaults を使う。
# feature gate test 用に最小 yml を置く (feature_smoke_off_enabled: false)。
mkdir -p "$FAKE_ROOT/.claude"
cat > "$FAKE_ROOT/.claude/harness-config.yml" <<'YML'
feature_smoke_off_enabled: false
feature_smoke_on_enabled: true
YML

MARKER_DIR="$TMPBASE/markers"
mkdir -p "$MARKER_DIR"

# stub 子 hook 群 (全て FAKE_HOOKS 配下)。各々 marker を残し payload を記録する。
# $MARKER_DIR は env で渡す (子は bash 起動で env 継承)。
make_child() {
  # $1 = filename (under FAKE_HOOKS), $2 = body
  printf '%s\n' "#!/usr/bin/env bash" "set -uo pipefail" "$2" > "$FAKE_HOOKS/$1"
  chmod 755 "$FAKE_HOOKS/$1"
}

# 子: marker を作り stdin payload を marker file に記録、stdout に context、exit 0
make_child "child-advisory-a.sh" '
payload="$(cat)"
printf "%s" "$payload" > "$SMOKE_MARKER_DIR/payload-a"
: > "$SMOKE_MARKER_DIR/ran-advisory-a"
printf "<ctx-a>"
exit 0'
make_child "child-advisory-b.sh" '
payload="$(cat)"
printf "%s" "$payload" > "$SMOKE_MARKER_DIR/payload-b"
: > "$SMOKE_MARKER_DIR/ran-advisory-b"
printf "<ctx-b>"
exit 0'
# exit2 blocker: stderr に理由、exit 2
make_child "child-exit2.sh" '
cat >/dev/null
printf "human-readable-block-reason\n" >&2
exit 2'
# stdout-block 子: decision block JSON を stdout、exit 0
make_child "child-stdout-block.sh" '
cat >/dev/null
: > "$SMOKE_MARKER_DIR/ran-stdout-block"
printf "{\"decision\":\"block\",\"reason\":\"nope\"}"
exit 0'
# stdout-block 子 (非 block): decision allow、context 出力
make_child "child-stdout-allow.sh" '
cat >/dev/null
printf "<allow-ctx>"
exit 0'
# 後続子 (block 後に走ってはいけない)
make_child "child-after.sh" '
cat >/dev/null
: > "$SMOKE_MARKER_DIR/ran-after"
exit 0'
# feature-gated 子 (disabled feature) — 走ったら marker を残す (走ってはいけない)
make_child "child-gated.sh" '
cat >/dev/null
: > "$SMOKE_MARKER_DIR/ran-gated"
exit 0'
# observer 子: rc 1 で死ぬ (fail-open 検証)、走った marker は残す
make_child "child-observer-fail.sh" '
cat >/dev/null
: > "$SMOKE_MARKER_DIR/ran-observer"
printf "should-be-ignored"
exit 1'
# stdout-block deny 子: permissionDecision:deny JSON を stdout、exit 0 (C3 用)
make_child "child-deny.sh" '
cat >/dev/null
: > "$SMOKE_MARKER_DIR/ran-deny"
printf "{\"hookSpecificOutput\":{\"permissionDecision\":\"deny\",\"permissionDecisionReason\":\"test-deny\"}}"
exit 0'
# exit2 error (rc=1): block でない error → fail-open 検証用
make_child "child-exit1.sh" '
cat >/dev/null
: > "$SMOKE_MARKER_DIR/ran-exit1"
printf "non-block-error\n" >&2
exit 1'
# wildcard-target 子: * matcher で実行されることを確認する
make_child "child-wildcard-target.sh" '
cat >/dev/null
: > "$SMOKE_MARKER_DIR/ran-wildcard-target"
printf "<wildcard-hit>"
exit 0'

# 合成 manifest を書く helper (header 行 + 与えた data 行)
write_manifest() {
  {
    printf 'event\tmatcher\torder\thook_command\tfeature_key\tchannel\tchild_timeout\n'
    printf '%s\n' "$@"
  } > "$FAKE_HOOKS/dispatcher-manifest.tsv"
}

# dispatcher を fake root 上で起動する helper。
# stdout を capture、stderr を別 file、exit code を返す。
# 引数: $1=event $2=matcher $3=payload。出力は global SMOKE_OUT / SMOKE_ERR / SMOKE_RC。
run_dispatch_fake() {
  local event="$1" matcher="$2" payload="$3"
  local errf="$TMPBASE/stderr.$$"
  SMOKE_OUT="$(
    HC_PROJECT_ROOT="$FAKE_ROOT" \
    HC_CONFIG_PATH="$FAKE_ROOT/.claude/harness-config.yml" \
    SMOKE_MARKER_DIR="$MARKER_DIR" \
    bash -c '
      set -uo pipefail
      source "'"$FAKE_LIB/dispatcher-core.sh"'"
      run_dispatch "'"$event"'" "'"$matcher"'"
    ' <<<"$payload" 2>"$errf"
  )"
  SMOKE_RC=$?
  SMOKE_ERR="$(cat "$errf" 2>/dev/null)"
  rm -f "$errf"
}

reset_markers() { rm -rf "$MARKER_DIR"; mkdir -p "$MARKER_DIR"; }

echo "== dispatcher-core-smoke =="

# tab 区切りの data 行を安全に作る行構築 helper (空 matcher / feature も保持)
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$1" "$2" "$3" "$4" "$5" "$6" "$7"; }

# ---------------------------------------------------------------------------
# Case 1: advisory 2 子 → 連結出力 + exit 0 + stdin replay (両子が同 payload)
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row Stop '' 1 child-advisory-a.sh '' advisory 5)" \
  "$(row Stop '' 2 child-advisory-b.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "PAYLOAD-123"
if [ "$SMOKE_RC" -eq 0 ] && [ "$SMOKE_OUT" = "<ctx-a><ctx-b>" ]; then
  ok "Case1 advisory: 連結出力 '<ctx-a><ctx-b>' + exit 0"
else
  bad "Case1 advisory: rc=$SMOKE_RC out='$SMOKE_OUT' (expected '<ctx-a><ctx-b>' rc 0)"
fi
# 不変条件 1: stdin replay (両子が同 payload を受信)
if [ "$(cat "$MARKER_DIR/payload-a" 2>/dev/null)" = "PAYLOAD-123" ] \
  && [ "$(cat "$MARKER_DIR/payload-b" 2>/dev/null)" = "PAYLOAD-123" ]; then
  ok "Case1 stdin replay: 2 子が同 payload を受け取る (不変条件 1)"
else
  bad "Case1 stdin replay: a='$(cat "$MARKER_DIR/payload-a" 2>/dev/null)' b='$(cat "$MARKER_DIR/payload-b" 2>/dev/null)'"
fi

# ---------------------------------------------------------------------------
# Case 2: exit2 子 → dispatcher exit 2 + stderr 保持 + 後続子未実行
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row Stop '' 1 child-exit2.sh '' exit2 5)" \
  "$(row Stop '' 2 child-after.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
if [ "$SMOKE_RC" -eq 2 ]; then
  ok "Case2 exit2: dispatcher exit 2 伝播 (不変条件 3)"
else
  bad "Case2 exit2: rc=$SMOKE_RC (expected 2)"
fi
case "$SMOKE_ERR" in
  *human-readable-block-reason*) ok "Case2 stderr 保持: blocker stderr が伝播 (不変条件 4)" ;;
  *) bad "Case2 stderr 保持: stderr='$SMOKE_ERR'" ;;
esac
if [ ! -f "$MARKER_DIR/ran-after" ]; then
  ok "Case2 first-block-wins: 後続子は未実行 (不変条件 2)"
else
  bad "Case2 first-block-wins: 後続子 child-after.sh が実行された"
fi

# ---------------------------------------------------------------------------
# Case 3: stdout-block 子が block → exit 0 + decision JSON 転送 + 後続未実行
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 child-stdout-block.sh '' stdout-block 5)" \
  "$(row PreToolUse 'Edit|Write' 2 child-after.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
if [ "$SMOKE_RC" -eq 0 ]; then
  ok "Case3 stdout-block: exit 0 (不変条件 3)"
else
  bad "Case3 stdout-block: rc=$SMOKE_RC (expected 0)"
fi
case "$SMOKE_OUT" in
  *'"decision":"block"'*) ok "Case3 stdout-block: decision JSON 転送" ;;
  *) bad "Case3 stdout-block: out='$SMOKE_OUT'" ;;
esac
if [ ! -f "$MARKER_DIR/ran-after" ]; then
  ok "Case3 first-block-wins: 後続子未実行 (不変条件 2)"
else
  bad "Case3 first-block-wins: 後続子が実行された"
fi

# ---------------------------------------------------------------------------
# Case 4: stdout-block 子が非 block (allow) → context 集約 + exit 0
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 child-stdout-allow.sh '' stdout-block 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
if [ "$SMOKE_RC" -eq 0 ] && [ "$SMOKE_OUT" = "<allow-ctx>" ]; then
  ok "Case4 stdout-block(allow): context 集約 '<allow-ctx>' + exit 0"
else
  bad "Case4 stdout-block(allow): rc=$SMOKE_RC out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# Case 5: feature OFF 子 → spawn されず skip (marker 不在で実証、不変条件 5)
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row Stop '' 1 child-gated.sh smoke_off advisory 5)" \
  "$(row Stop '' 2 child-advisory-a.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
if [ ! -f "$MARKER_DIR/ran-gated" ]; then
  ok "Case5 feature gate: disabled feature の子は spawn されない (不変条件 5)"
else
  bad "Case5 feature gate: child-gated.sh が実行された (feature OFF のはず)"
fi
# 後続 (feature 無指定) は走る
if [ -f "$MARKER_DIR/ran-advisory-a" ] && [ "$SMOKE_OUT" = "<ctx-a>" ]; then
  ok "Case5 feature gate: 非 gated 後続子は通常実行"
else
  bad "Case5 feature gate: 後続子 out='$SMOKE_OUT' ran=$([ -f "$MARKER_DIR/ran-advisory-a" ] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# Case 5b: feature ON 子 → 実行される (gate が常時 false でないことの対照)
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row Stop '' 1 child-advisory-a.sh smoke_on advisory 5)"
run_dispatch_fake "Stop" "" "P"
if [ -f "$MARKER_DIR/ran-advisory-a" ] && [ "$SMOKE_OUT" = "<ctx-a>" ]; then
  ok "Case5b feature gate: enabled feature の子は実行される"
else
  bad "Case5b feature gate: enabled 子が走らなかった out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# Case 6: observer 子が rc 1 で死ぬ → dispatcher exit 0 (fail-open、不変条件 6)
#          observer の stdout は無視される
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row PreToolUse '*' 1 child-observer-fail.sh '' observer 3)"
run_dispatch_fake "PreToolUse" "*" "P"
if [ "$SMOKE_RC" -eq 0 ]; then
  ok "Case6 observer fail-open: 子 rc 1 でも dispatcher exit 0 (不変条件 6)"
else
  bad "Case6 observer fail-open: rc=$SMOKE_RC (expected 0)"
fi
if [ -z "$SMOKE_OUT" ]; then
  ok "Case6 observer: stdout 無視 (原則無出力)"
else
  bad "Case6 observer: 予期せぬ出力 out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# Case 7: matcher filter — 該当 matcher のみ実行 (別 matcher 行は無視)
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row PreToolUse 'Read' 1 child-advisory-a.sh '' advisory 5)" \
  "$(row PreToolUse 'Bash' 1 child-advisory-b.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Read" "P"
if [ "$SMOKE_OUT" = "<ctx-a>" ] && [ ! -f "$MARKER_DIR/ran-advisory-b" ]; then
  ok "Case7 matcher filter: matcher=Read のみ実行、Bash 行は無視"
else
  bad "Case7 matcher filter: out='$SMOKE_OUT' ran-b=$([ -f "$MARKER_DIR/ran-advisory-b" ] && echo yes || echo no)"
fi

# ---------------------------------------------------------------------------
# Case 8: 実 manifest 健全性 (read-only):
#   - 全 hook_command path 実在 + channel 既知値 (既存)
#   - child_timeout (col7) が正整数 (schema 強化)
#   - order (col3) が整数 + 同 (event,matcher) 内重複なし (schema 強化)
# ---------------------------------------------------------------------------
( set -uo pipefail
  known_channels=" exit2 stdout-block advisory observer bootstrap "
  bad_path=0
  bad_chan=0
  bad_timeout=0
  bad_order=0

  # bash IFS=tab read は連続タブ (空 field) を collapse し列がずれるため、
  # field 抽出は awk に一任 (dispatcher-core と同方針)。出力区切りは \034。
  while IFS="$(printf '\034')" read -r cmd chan; do
    [ -z "$cmd" ] && continue
    # hook path 実在 (引数を除いた script 名のみ、../skills/ も REPO/.claude/hooks/ 相対で解決)
    script="${cmd%% *}"
    if [ ! -f "$REPO_ROOT/.claude/hooks/$script" ]; then
      printf '    [path] missing: %s (cmd: %s)\n' "$script" "$cmd" >&2
      bad_path=$((bad_path+1))
    fi
    # channel 既知値
    case "$known_channels" in
      *" $chan "*) ;;
      *) printf '    [channel] unknown: %s (cmd: %s)\n' "$chan" "$cmd" >&2
         bad_chan=$((bad_chan+1)) ;;
    esac
  done <<EOF
$(awk -F'\t' 'NR>1 && NF>=6 && $1!="" { printf "%s\034%s\n", $4, $6 }' "$REAL_MANIFEST")
EOF

  # child_timeout (col7) 正整数 validation
  while IFS="$(printf '\034')" read -r timeout; do
    [ -z "$timeout" ] && continue
    case "$timeout" in
      ''|*[!0-9]*) printf '    [timeout] non-positive-integer: %s\n' "$timeout" >&2
                   bad_timeout=$((bad_timeout+1)) ;;
      0) printf '    [timeout] must be >= 1: %s\n' "$timeout" >&2
         bad_timeout=$((bad_timeout+1)) ;;
    esac
  done <<EOF
$(awk -F'\t' 'NR>1 && NF>=7 && $1!="" { printf "%s\n", $7 }' "$REAL_MANIFEST")
EOF

  # order (col3) 整数 + 同 (event,matcher) 内重複なし validation
  # awk で (event,matcher,order) の triple を出力し、重複を検出する
  while IFS="$(printf '\034')" read -r ev mt ord; do
    [ -z "$ord" ] && continue
    case "$ord" in
      ''|*[!0-9]*) printf '    [order] non-integer: event=%s matcher=%s order=%s\n' "$ev" "$mt" "$ord" >&2
                   bad_order=$((bad_order+1)) ;;
    esac
  done <<EOF
$(awk -F'\t' 'NR>1 && NF>=3 && $1!="" { printf "%s\034%s\034%s\n", $1, $2, $3 }' "$REAL_MANIFEST")
EOF

  # 重複 order check: 同 (event,matcher) で同じ order 値が複数存在しないか
  dup_count=$(awk -F'\t' 'NR>1 && NF>=3 && $1!="" { print $1"\t"$2"\t"$3 }' "$REAL_MANIFEST" \
    | sort | uniq -d | wc -l | tr -d '[:space:]')
  if [ "${dup_count:-0}" -gt 0 ]; then
    printf '    [order] duplicate (event,matcher,order) found: %d\n' "$dup_count" >&2
    bad_order=$((bad_order+1))
  fi

  [ "$bad_path" -eq 0 ] && [ "$bad_chan" -eq 0 ] && [ "$bad_timeout" -eq 0 ] && [ "$bad_order" -eq 0 ]
)
if [ $? -eq 0 ]; then
  ok "Case8 実 manifest 健全性: path 実在 + channel + timeout 正整数 + order 重複なし (read-only)"
else
  bad "Case8 実 manifest 健全性: 不正 row あり (path/channel/timeout/order)"
fi

# ---------------------------------------------------------------------------
# Case 9 (C3): deny stub の stdout-block early-exit
#   child-deny.sh (permissionDecision:deny, order=1) → early-exit、child-after.sh 未実行
#   最終 stdout が deny JSON を保持
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row PreToolUse 'Edit|Write' 1 child-deny.sh '' stdout-block 5)" \
  "$(row PreToolUse 'Edit|Write' 2 child-after.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "Edit|Write" "P"
if [ "$SMOKE_RC" -eq 0 ]; then
  ok "Case9 deny early-exit: exit 0 (stdout-block channel 不変条件 3)"
else
  bad "Case9 deny early-exit: rc=$SMOKE_RC (expected 0)"
fi
if printf '%s' "$SMOKE_OUT" | grep -Eq '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
  ok "Case9 deny early-exit: permissionDecision:deny JSON 転送"
else
  bad "Case9 deny early-exit: deny not found in out='$SMOKE_OUT'"
fi
if [ ! -f "$MARKER_DIR/ran-after" ]; then
  ok "Case9 deny early-exit: first-block-wins 後続子未実行 (不変条件 2)"
else
  bad "Case9 deny early-exit: 後続子 child-after.sh が実行された"
fi

# ---------------------------------------------------------------------------
# Case 10: wildcard `*` matcher dispatch
#   合成 manifest に PreToolUse * 1 child-wildcard-target.sh advisory
#   run_dispatch "PreToolUse" "*" で * 行が実行される (marker + 出力)
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row PreToolUse '*' 1 child-wildcard-target.sh '' advisory 5)"
run_dispatch_fake "PreToolUse" "*" "P"
if [ -f "$MARKER_DIR/ran-wildcard-target" ] && [ "$SMOKE_OUT" = "<wildcard-hit>" ]; then
  ok "Case10 wildcard '*' matcher: * 行が dispatcher で実行される"
else
  bad "Case10 wildcard '*' matcher: marker=$([ -f "$MARKER_DIR/ran-wildcard-target" ] && echo yes || echo no) out='$SMOKE_OUT'"
fi

# ---------------------------------------------------------------------------
# Case 11: exit2 channel 子が rc=1 (block でない error) → fail-open (exit 0、後続継続)
# ---------------------------------------------------------------------------
reset_markers
write_manifest \
  "$(row Stop '' 1 child-exit1.sh '' exit2 5)" \
  "$(row Stop '' 2 child-advisory-a.sh '' advisory 5)"
run_dispatch_fake "Stop" "" "P"
if [ "$SMOKE_RC" -eq 0 ]; then
  ok "Case11 exit2 rc=1 fail-open: 子 rc=1 は block でないため dispatcher exit 0"
else
  bad "Case11 exit2 rc=1 fail-open: rc=$SMOKE_RC (expected 0, rc=1 should not block)"
fi
if [ -f "$MARKER_DIR/ran-advisory-a" ]; then
  ok "Case11 exit2 rc=1 fail-open: 後続子は継続実行"
else
  bad "Case11 exit2 rc=1 fail-open: 後続子が実行されなかった"
fi

# ---------------------------------------------------------------------------
echo "== result: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ]
