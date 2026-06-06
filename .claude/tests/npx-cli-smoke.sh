#!/usr/bin/env bash
# .claude/tests/npx-cli-smoke.sh — task-83 Step 7 smoke test (25+ cases)
#
# 目的: bin/cli.js + package.json + .npmignore の実装検証
#       (task-83 fix round 1: CRIT-1/1b/2 HIGH-1/2/3/4 MED-2/5/6 追加)
#
# 実行:
#   bash .claude/tests/npx-cli-smoke.sh
#
# 終了コード:
#   0 = 全 PASS
#   1 = 1 件以上 FAIL
#
# 重要制約:
#   file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範)
#   bash 3.2 互換 (macOS bash 3.2 対応、declare -A 禁止)
#   PASS/FAIL counter 方式 (subshell 関数化で局所 set -euo pipefail)

set -u

# ============================================================
# 初期化
# ============================================================
# SCRIPT_DIR から 2 階層上が REPO_ROOT (tests/ → .claude/ → repo root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0
FAIL=0
WARN_COUNT=0

# クリーンアップ対象 (追加ケース用)
_TMPDIR_EXTRA=""
_HTTP_SERVER_PID=""

# ============================================================
# クリーンアップ (EXIT / INT / TERM で確実実行)
# ============================================================
_cleanup_all() {
  if [ -n "${_HTTP_SERVER_PID:-}" ] && kill -0 "$_HTTP_SERVER_PID" 2>/dev/null; then
    kill "$_HTTP_SERVER_PID" 2>/dev/null || true
  fi
  if [ -n "${_TMPDIR_EXTRA:-}" ] && [ -d "$_TMPDIR_EXTRA" ]; then
    rm -rf "$_TMPDIR_EXTRA"
  fi
}
trap _cleanup_all EXIT INT TERM

# ============================================================
# ヘルパー関数
# ============================================================
pass() {
  PASS=$((PASS + 1))
  printf "  PASS  %s\n" "$1"
}

fail() {
  FAIL=$((FAIL + 1))
  printf "  FAIL  %s\n" "$1"
  if [ -n "${2:-}" ]; then
    printf "        detail: %s\n" "$2"
  fi
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf "  WARN  %s\n" "$1"
}

section() {
  printf "\n[%s]\n" "$1"
}

# grep -c は macOS で改行を含む場合があるため tr で除去するユーティリティ
grep_count() {
  # usage: grep_count <pattern> <input_var>
  # 標準入力から grep -c を実行して改行を除去した整数を返す
  printf '%s' "$1" | grep -c "$2" 2>/dev/null | tr -d ' \n' || printf '0'
}

# ============================================================
# テスト実行
# ============================================================
printf "=== npx-cli-smoke.sh (task-83 Step 7) ===\n"
printf "REPO_ROOT: %s\n" "$REPO_ROOT"

cd "$REPO_ROOT" || { echo "FATAL: cd $REPO_ROOT failed"; exit 1; }

# ============================================================
# Case 1: package.json 妥当性
# ============================================================
section "Case 1: package.json 妥当性"
if node -e "require('./package.json')" 2>/dev/null; then
  pass "node -e require('./package.json') 成功"
else
  fail "package.json が node で require できない"
fi

# ============================================================
# Case 2: package.json field 検証
# ============================================================
section "Case 2: package.json field"

# .name == "@takuma-hirai/hirai-method"
PKG_NAME="$(node -p "require('./package.json').name" 2>/dev/null || echo '')"
if [ "$PKG_NAME" = "@takuma-hirai/hirai-method" ]; then
  pass ".name == '@takuma-hirai/hirai-method'"
else
  fail ".name が期待値と異なる" "actual: $PKG_NAME"
fi

# .bin.hirai-method == "bin/cli.js"
BIN_FIELD="$(node -p "require('./package.json').bin['hirai-method']" 2>/dev/null || echo '')"
if [ "$BIN_FIELD" = "bin/cli.js" ]; then
  pass ".bin['hirai-method'] == 'bin/cli.js'"
else
  fail ".bin['hirai-method'] が期待値と異なる" "actual: $BIN_FIELD"
fi

# .publishConfig.access == "public"
PUB_ACCESS="$(node -p "require('./package.json').publishConfig.access" 2>/dev/null || echo '')"
if [ "$PUB_ACCESS" = "public" ]; then
  pass ".publishConfig.access == 'public'"
else
  fail ".publishConfig.access が期待値と異なる" "actual: $PUB_ACCESS"
fi

# .version が semver 正規表現 ^[0-9]+\.[0-9]+\.[0-9]+$
PKG_VER="$(node -p "require('./package.json').version" 2>/dev/null || echo '')"
if echo "$PKG_VER" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  pass ".version が semver 形式: $PKG_VER"
else
  fail ".version が semver 形式でない" "actual: $PKG_VER"
fi

# ============================================================
# Case 3: files allowlist — .claude/ / install.sh / bin/ を含む
# ============================================================
section "Case 3: files allowlist"

FILES_HAS_CLAUDE="$(node -p "require('./package.json').files.includes('.claude/')" 2>/dev/null || echo 'false')"
if [ "$FILES_HAS_CLAUDE" = "true" ]; then
  pass ".files に '.claude/' を含む"
else
  fail ".files に '.claude/' が含まれない"
fi

FILES_HAS_INSTALL="$(node -p "require('./package.json').files.includes('install.sh')" 2>/dev/null || echo 'false')"
if [ "$FILES_HAS_INSTALL" = "true" ]; then
  pass ".files に 'install.sh' を含む"
else
  fail ".files に 'install.sh' が含まれない"
fi

FILES_HAS_BIN="$(node -p "require('./package.json').files.includes('bin/')" 2>/dev/null || echo 'false')"
if [ "$FILES_HAS_BIN" = "true" ]; then
  pass ".files に 'bin/' を含む"
else
  fail ".files に 'bin/' が含まれない"
fi

# ============================================================
# Case 4: .npmignore 存在 + content-post 除外行
# ============================================================
section "Case 4: .npmignore 存在 + content-post 除外行"

if [ -f ".npmignore" ]; then
  pass ".npmignore が存在する"
else
  fail ".npmignore が存在しない"
fi

if grep -q "content-post" ".npmignore" 2>/dev/null; then
  pass ".npmignore に content-post を含む行がある"
else
  fail ".npmignore に content-post を含む行がない"
fi

# ============================================================
# Case 5: bin/cli.js shebang
# ============================================================
section "Case 5: bin/cli.js shebang"

SHEBANG="$(head -1 bin/cli.js 2>/dev/null || echo '')"
if [ "$SHEBANG" = "#!/usr/bin/env node" ]; then
  pass "bin/cli.js 1 行目が '#!/usr/bin/env node'"
else
  fail "bin/cli.js shebang が期待値と異なる" "actual: $SHEBANG"
fi

# ============================================================
# Case 6: bin/cli.js 実行 bit
# ============================================================
section "Case 6: bin/cli.js 実行 bit"

if [ -x "bin/cli.js" ]; then
  pass "bin/cli.js に実行 bit がある (-x)"
else
  fail "bin/cli.js に実行 bit がない"
fi

# ============================================================
# Case 7: bin/cli.js syntax check
# ============================================================
section "Case 7: bin/cli.js syntax (node --check)"

if node --check bin/cli.js 2>/dev/null; then
  pass "node --check bin/cli.js 成功"
else
  fail "node --check bin/cli.js 失敗 (syntax error)"
fi

# ============================================================
# Case 8: --version (MED-2 修正: || echo '' 削除により exit code を正確に取得)
# ============================================================
section "Case 8: --version"

VERSION_OUT="$(node bin/cli.js --version 2>/dev/null)"
VERSION_EXIT=$?
if [ $VERSION_EXIT -eq 0 ] && echo "$VERSION_OUT" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  pass "--version が semver 出力 & exit 0: $VERSION_OUT"
else
  fail "--version が期待値と異なる" "exit=$VERSION_EXIT output=$VERSION_OUT"
fi

# ============================================================
# Case 9: --help
# ============================================================
section "Case 9: --help"

HELP_OUT="$(node bin/cli.js --help 2>/dev/null)"
HELP_EXIT=$?
if [ $HELP_EXIT -ne 0 ]; then
  fail "--help が exit 0 でない" "exit=$HELP_EXIT"
else
  # check / install / update を全て含む
  HELP_HAS_CHECK="$(echo "$HELP_OUT" | grep -c "check" 2>/dev/null | tr -d ' \n')"
  HELP_HAS_INSTALL="$(echo "$HELP_OUT" | grep -c "install" 2>/dev/null | tr -d ' \n')"
  HELP_HAS_UPDATE="$(echo "$HELP_OUT" | grep -c "update" 2>/dev/null | tr -d ' \n')"
  if [ "${HELP_HAS_CHECK:-0}" -gt 0 ] && [ "${HELP_HAS_INSTALL:-0}" -gt 0 ] && [ "${HELP_HAS_UPDATE:-0}" -gt 0 ]; then
    pass "--help exit 0 & check/install/update を含む"
  else
    fail "--help 出力に check/install/update のいずれかが欠ける" \
         "check=$HELP_HAS_CHECK install=$HELP_HAS_INSTALL update=$HELP_HAS_UPDATE"
  fi
fi

# ============================================================
# Case 10: unknown subcommand → exit 1
# ============================================================
section "Case 10: unknown subcommand"

node bin/cli.js bogus >/dev/null 2>&1
BOGUS_EXIT=$?
if [ $BOGUS_EXIT -eq 1 ]; then
  pass "unknown subcommand 'bogus' が exit 1"
else
  fail "unknown subcommand の exit code が期待値と異なる" "expected=1 actual=$BOGUS_EXIT"
fi

# ============================================================
# Case 11: install 引数なし → exit 1
# ============================================================
section "Case 11: install 引数なし"

node bin/cli.js install >/dev/null 2>&1
INSTALL_NO_DIR_EXIT=$?
if [ $INSTALL_NO_DIR_EXIT -eq 1 ]; then
  pass "install 引数なしが exit 1"
else
  fail "install 引数なしの exit code が期待値と異なる" "expected=1 actual=$INSTALL_NO_DIR_EXIT"
fi

# ============================================================
# Case 12: check fail-open (未 publish / network error でも exit 0)
# ============================================================
section "Case 12: check fail-open"

# npm registry へのアクセスが 404 / network error でも fail-open = exit 0 であることを確認。
# ここでは HTTPS_PROXY に無効なアドレスを設定して network error を強制し fail-open を検証する。
CHECK_OUT="$(HTTPS_PROXY="http://127.0.0.1:19999" node bin/cli.js check 2>&1)"
CHECK_EXIT=$?
if [ $CHECK_EXIT -eq 0 ]; then
  pass "check が network error でも fail-open (exit 0)"
else
  fail "check が network error 時に exit 0 にならない" "exit=$CHECK_EXIT"
fi

# ============================================================
# Case 13: npm pack 同梱 — content-post 生成物 0
# ============================================================
section "Case 13: npm pack 同梱 — content-post 生成物 0"

PACK_OUT="$(npm pack --dry-run 2>&1)"
PACK_EXIT=$?
if [ $PACK_EXIT -ne 0 ]; then
  fail "npm pack --dry-run が失敗" "exit=$PACK_EXIT"
else
  CONTENT_POST_COUNT="$(echo "$PACK_OUT" | grep -E "content-post/(drafts|contents_manage/images)" 2>/dev/null | wc -l | tr -d ' \n')"
  CONTENT_POST_COUNT="${CONTENT_POST_COUNT:-0}"
  if [ "$CONTENT_POST_COUNT" -eq 0 ]; then
    pass "npm pack に content-post 生成物が含まれない (count=0)"
  else
    fail "npm pack に content-post 生成物が混入している" "count=$CONTENT_POST_COUNT"
  fi
fi

# ============================================================
# Case 14: npm pack 同梱 — bin/cli.js 含む
# ============================================================
section "Case 14: npm pack 同梱 — bin/cli.js 含む"

# PACK_OUT は Case 13 で取得済み
BIN_IN_PACK="$(echo "$PACK_OUT" | grep -c "bin/cli.js" 2>/dev/null | tr -d ' \n')"
BIN_IN_PACK="${BIN_IN_PACK:-0}"
if [ "$BIN_IN_PACK" -gt 0 ]; then
  pass "npm pack に bin/cli.js が含まれる"
else
  fail "npm pack に bin/cli.js が含まれない"
fi

# ============================================================
# Case 15: install 実配布 (integration)
# ============================================================
section "Case 15: install 実配布 (integration)"

TMPDIR_INSTALL="$(mktemp -d)"
if [ -z "$TMPDIR_INSTALL" ] || [ ! -d "$TMPDIR_INSTALL" ]; then
  fail "mktemp -d が失敗 (tmpdir 作成不能)"
else
  # rsync 存在確認
  if ! command -v rsync >/dev/null 2>&1; then
    warn "rsync が見つからないため Case 15 を SKIP (WARN 扱い)"
    fail "rsync が存在しない (この repo では rsync 必須)" "command -v rsync failed"
  else
    INSTALL_OUT="$(node bin/cli.js install "$TMPDIR_INSTALL" 2>&1)"
    INSTALL_EXIT=$?
    if [ $INSTALL_EXIT -ne 0 ]; then
      fail "node bin/cli.js install <tmpdir> が非 0 exit" "exit=$INSTALL_EXIT output=$INSTALL_OUT"
    elif [ -d "$TMPDIR_INSTALL/.claude" ]; then
      if [ -f "$TMPDIR_INSTALL/.claude/CommonRules.md" ]; then
        pass "install 後に <tmpdir>/.claude/CommonRules.md が生成された"
      else
        fail "install 後に <tmpdir>/.claude/CommonRules.md が存在しない" \
             "ls: $(ls "$TMPDIR_INSTALL/.claude/" 2>&1 | head -5)"
      fi
    else
      fail "install 後に <tmpdir>/.claude/ が生成されない"
    fi
  fi
  rm -rf "$TMPDIR_INSTALL"
fi

# ============================================================
# Case CRIT-1: semver 単体テスト (parseSemver / compareSemver require export)
# ============================================================
section "Case CRIT-1: semver 単体 (require export)"

# require.main ガードにより CLI 実行されない (require 時は export のみ提供)
REQUIRE_TEST="$(node -e "const m=require('./bin/cli.js'); process.stdout.write(typeof m.parseSemver + ':' + typeof m.compareSemver + '\n');" 2>/dev/null)"
REQUIRE_EXIT=$?
if [ $REQUIRE_EXIT -eq 0 ] && [ "$REQUIRE_TEST" = "function:function" ]; then
  pass "require('./bin/cli.js') で parseSemver / compareSemver が export されている"
else
  fail "require('./bin/cli.js') export が期待値と異なる" "exit=$REQUIRE_EXIT out=$REQUIRE_TEST"
fi

# sub-case: require 時に CLI が実行されない (stdout/stderr に出力なし)
NO_CLI_RUN="$(node -e "require('./bin/cli.js');" 2>&1)"
NO_CLI_EXIT=$?
if [ $NO_CLI_EXIT -eq 0 ] && [ -z "$NO_CLI_RUN" ]; then
  pass "require('./bin/cli.js') 時に CLI が実行されない (出力なし)"
else
  fail "require('./bin/cli.js') 時に CLI 実行が発生した可能性" "exit=$NO_CLI_EXIT out=$NO_CLI_RUN"
fi

# compareSemver: 1.0.1 > 1.0.0 = 1
CMP_1="$(node -e "const {compareSemver}=require('./bin/cli.js'); process.stdout.write(String(compareSemver('1.0.1','1.0.0'))+'\n');" 2>/dev/null)"
if [ "$CMP_1" = "1" ]; then
  pass "compareSemver('1.0.1','1.0.0') == 1"
else
  fail "compareSemver('1.0.1','1.0.0') 期待値 1 != actual $CMP_1"
fi

# compareSemver: 1.0.0 == 1.0.0 = 0
CMP_2="$(node -e "const {compareSemver}=require('./bin/cli.js'); process.stdout.write(String(compareSemver('1.0.0','1.0.0'))+'\n');" 2>/dev/null)"
if [ "$CMP_2" = "0" ]; then
  pass "compareSemver('1.0.0','1.0.0') == 0"
else
  fail "compareSemver('1.0.0','1.0.0') 期待値 0 != actual $CMP_2"
fi

# compareSemver: 0.9.9 < 1.0.0 = -1
CMP_3="$(node -e "const {compareSemver}=require('./bin/cli.js'); process.stdout.write(String(compareSemver('0.9.9','1.0.0'))+'\n');" 2>/dev/null)"
if [ "$CMP_3" = "-1" ]; then
  pass "compareSemver('0.9.9','1.0.0') == -1"
else
  fail "compareSemver('0.9.9','1.0.0') 期待値 -1 != actual $CMP_3"
fi

# compareSemver: v1.0.0 == 1.0.0 = 0 (v prefix strip)
CMP_4="$(node -e "const {compareSemver}=require('./bin/cli.js'); process.stdout.write(String(compareSemver('v1.0.0','1.0.0'))+'\n');" 2>/dev/null)"
if [ "$CMP_4" = "0" ]; then
  pass "compareSemver('v1.0.0','1.0.0') == 0 (v prefix strip)"
else
  fail "compareSemver('v1.0.0','1.0.0') 期待値 0 != actual $CMP_4"
fi

# compareSemver: 1.0.0-rc1 == 1.0.0 = 0 (prerelease 無視)
CMP_5="$(node -e "const {compareSemver}=require('./bin/cli.js'); process.stdout.write(String(compareSemver('1.0.0-rc1','1.0.0'))+'\n');" 2>/dev/null)"
if [ "$CMP_5" = "0" ]; then
  pass "compareSemver('1.0.0-rc1','1.0.0') == 0 (prerelease 無視)"
else
  fail "compareSemver('1.0.0-rc1','1.0.0') 期待値 0 != actual $CMP_5"
fi

# parseSemver: '2.x.0' → null (非数値 segment は null)
PARSE_1="$(node -e "const {parseSemver}=require('./bin/cli.js'); const r=parseSemver('2.x.0'); process.stdout.write(String(r)+'\n');" 2>/dev/null)"
if [ "$PARSE_1" = "null" ]; then
  pass "parseSemver('2.x.0') == null"
else
  fail "parseSemver('2.x.0') 期待値 null != actual '$PARSE_1'"
fi

# parseSemver: '1.2.3.4' → null (4 segments は null)
PARSE_2="$(node -e "const {parseSemver}=require('./bin/cli.js'); const r=parseSemver('1.2.3.4'); process.stdout.write(String(r)+'\n');" 2>/dev/null)"
if [ "$PARSE_2" = "null" ]; then
  pass "parseSemver('1.2.3.4') == null"
else
  fail "parseSemver('1.2.3.4') 期待値 null != actual '$PARSE_2'"
fi

# parseSemver: 'invalid' → null
PARSE_3="$(node -e "const {parseSemver}=require('./bin/cli.js'); const r=parseSemver('invalid'); process.stdout.write(String(r)+'\n');" 2>/dev/null)"
if [ "$PARSE_3" = "null" ]; then
  pass "parseSemver('invalid') == null"
else
  fail "parseSemver('invalid') 期待値 null != actual '$PARSE_3'"
fi

# ============================================================
# Case CRIT-1b: check dispatch (local node http server)
# ============================================================
section "Case CRIT-1b: check dispatch (local http server)"

# 空きポートを動的取得 (port contention 回避)
HTTP_PORT="$(node -e "const net=require('net');const s=net.createServer();s.listen(0,'127.0.0.1',function(){const p=s.address().port;s.close(function(){process.stdout.write(String(p)+'\n')})});" 2>/dev/null || echo 18327)"
HTTP_PORT="${HTTP_PORT:-18327}"
_TMPDIR_EXTRA="$(mktemp -d /tmp/cli-smoke-XXXXX)"

# (a) latest > local → stdout に "新版" または "update" を含む
_HTTP_SERVER_PID=""
node -e "require('http').createServer(function(q,s){s.setHeader('content-type','application/json');s.end(JSON.stringify({version:'9.9.9'}))}).listen($HTTP_PORT,'127.0.0.1')" &
_HTTP_SERVER_PID=$!

# http server 起動待ち (最大 2 秒 / 0.2 秒間隔で retry)
_server_ready=0
for _i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.2
  if node -e "require('http').get('http://127.0.0.1:$HTTP_PORT/',function(r){process.exit(r.statusCode===200?0:1)}).on('error',function(){process.exit(1)})" 2>/dev/null; then
    _server_ready=1
    break
  fi
done

if [ "${_server_ready:-0}" -ne 1 ]; then
  fail "CRIT-1b (a): local http server 起動失敗 (port=$HTTP_PORT)"
else
  CHECK_STALE_OUT="$(HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:$HTTP_PORT" node bin/cli.js check 2>&1)"
  CHECK_STALE_EXIT=$?
  if [ $CHECK_STALE_EXIT -eq 0 ] && echo "$CHECK_STALE_OUT" | grep -qiE '新版|update'; then
    pass "CRIT-1b (a): latest=9.9.9 > local → '新版' or 'update' を stdout に含む"
  else
    fail "CRIT-1b (a): latest>local の check dispatch が期待値と異なる" \
         "exit=$CHECK_STALE_EXIT out=$CHECK_STALE_OUT"
  fi
fi

# server を kill して up-to-date テスト用に再起動
if [ -n "${_HTTP_SERVER_PID:-}" ] && kill -0 "$_HTTP_SERVER_PID" 2>/dev/null; then
  kill "$_HTTP_SERVER_PID" 2>/dev/null || true
  _HTTP_SERVER_PID=""
fi
sleep 0.3

# (b) latest == local → "up to date" を含む
LOCAL_VER="$(node -p "require('./package.json').version" 2>/dev/null || echo '0.0.0')"
node -e "require('http').createServer(function(q,s){s.setHeader('content-type','application/json');s.end(JSON.stringify({version:'$LOCAL_VER'}))}).listen($HTTP_PORT,'127.0.0.1')" &
_HTTP_SERVER_PID=$!

_server_ready=0
for _i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.2
  if node -e "require('http').get('http://127.0.0.1:$HTTP_PORT/',function(r){process.exit(r.statusCode===200?0:1)}).on('error',function(){process.exit(1)})" 2>/dev/null; then
    _server_ready=1
    break
  fi
done

if [ "${_server_ready:-0}" -ne 1 ]; then
  fail "CRIT-1b (b): local http server (up-to-date) 起動失敗 (port=$HTTP_PORT)"
else
  CHECK_UPTODATE_OUT="$(HIRAI_METHOD_REGISTRY_BASE="http://127.0.0.1:$HTTP_PORT" node bin/cli.js check 2>&1)"
  CHECK_UPTODATE_EXIT=$?
  if [ $CHECK_UPTODATE_EXIT -eq 0 ] && echo "$CHECK_UPTODATE_OUT" | grep -qi "up to date"; then
    pass "CRIT-1b (b): latest==local → 'up to date' を stdout に含む"
  else
    fail "CRIT-1b (b): up-to-date check dispatch が期待値と異なる" \
         "exit=$CHECK_UPTODATE_EXIT out=$CHECK_UPTODATE_OUT"
  fi
fi

# server kill
if [ -n "${_HTTP_SERVER_PID:-}" ] && kill -0 "$_HTTP_SERVER_PID" 2>/dev/null; then
  kill "$_HTTP_SERVER_PID" 2>/dev/null || true
  _HTTP_SERVER_PID=""
fi

# ============================================================
# Case CRIT-2: update integration (install → update)
# ============================================================
section "Case CRIT-2: update integration (install → update)"

TMPDIR_UPDATE="$(mktemp -d /tmp/cli-smoke-update-XXXXX)"
if [ -z "$TMPDIR_UPDATE" ] || [ ! -d "$TMPDIR_UPDATE" ]; then
  fail "CRIT-2: mktemp -d 失敗"
else
  # install
  INSTALL_OUT2="$(node bin/cli.js install "$TMPDIR_UPDATE" 2>&1)"
  INSTALL_EXIT2=$?
  if [ $INSTALL_EXIT2 -ne 0 ]; then
    fail "CRIT-2: install が非 0 exit" "exit=$INSTALL_EXIT2"
  else
    # update
    UPDATE_OUT="$(node bin/cli.js update "$TMPDIR_UPDATE" 2>&1)"
    UPDATE_EXIT=$?
    if [ $UPDATE_EXIT -ne 0 ]; then
      fail "CRIT-2: update が非 0 exit" "exit=$UPDATE_EXIT"
    elif [ -f "$TMPDIR_UPDATE/.claude/CommonRules.md" ]; then
      pass "CRIT-2: install → update 後に .claude/CommonRules.md が存在 (exit 0)"
    else
      fail "CRIT-2: update 後 .claude/CommonRules.md が存在しない"
    fi
  fi
  rm -rf "$TMPDIR_UPDATE"
fi

# ============================================================
# Case HIGH-1: rsync 不在 precheck
# ============================================================
section "Case HIGH-1: rsync 不在 precheck"

NODE_BIN="$(command -v node 2>/dev/null || echo '')"
NODE_DIR="$(dirname "$NODE_BIN" 2>/dev/null || echo '')"
if [ -z "$NODE_DIR" ] || [ ! -d "$NODE_DIR" ]; then
  fail "HIGH-1: node のパスが取得できない (skip)"
else
  TMPDIR_NORSYNC="$(mktemp -d /tmp/cli-smoke-norsync-XXXXX)"
  # PATH を /bin + NODE_DIR のみにすることで rsync (/usr/bin/rsync) を隠す
  # (bash は /bin にある、node は NODE_DIR にある)
  NORSYNC_OUT="$(PATH="/bin:$NODE_DIR" node bin/cli.js install "$TMPDIR_NORSYNC" 2>&1)"
  NORSYNC_EXIT=$?
  NORSYNC_RSYNC_MENTION="$(echo "$NORSYNC_OUT" | grep -ci "rsync" 2>/dev/null | tr -d ' \n')"
  NORSYNC_RSYNC_MENTION="${NORSYNC_RSYNC_MENTION:-0}"
  if [ $NORSYNC_EXIT -eq 1 ] && [ "$NORSYNC_RSYNC_MENTION" -gt 0 ]; then
    pass "HIGH-1: rsync 不在時に exit 1 + stderr に 'rsync' 言及"
  else
    fail "HIGH-1: rsync 不在 precheck が期待値と異なる" \
         "exit=$NORSYNC_EXIT rsync_mention=$NORSYNC_RSYNC_MENTION"
  fi
  rm -rf "$TMPDIR_NORSYNC"
fi

# ============================================================
# Case HIGH-2: 不明 flag と passthrough flag
# ============================================================
section "Case HIGH-2: flag 検証"

# --bogus は exit 1
TMPDIR_FLAG="$(mktemp -d /tmp/cli-smoke-flag-XXXXX)"
node bin/cli.js install --bogus "$TMPDIR_FLAG" >/dev/null 2>&1
BOGUS_FLAG_EXIT=$?
if [ $BOGUS_FLAG_EXIT -eq 1 ]; then
  pass "HIGH-2: --bogus flag → exit 1"
else
  fail "HIGH-2: --bogus flag が exit 1 でない" "actual exit=$BOGUS_FLAG_EXIT"
fi
rm -rf "$TMPDIR_FLAG"

# --no-mcp は passthrough (exit != 1 が期待: install.sh が実行されれば 0)
TMPDIR_NOMCP="$(mktemp -d /tmp/cli-smoke-nomcp-XXXXX)"
node bin/cli.js install --no-mcp "$TMPDIR_NOMCP" >/dev/null 2>&1
NOMCP_EXIT=$?
if [ $NOMCP_EXIT -ne 1 ]; then
  pass "HIGH-2: --no-mcp は passthrough (exit $NOMCP_EXIT != 1)"
else
  fail "HIGH-2: --no-mcp が誤って exit 1 を返した"
fi
rm -rf "$TMPDIR_NOMCP"

# ============================================================
# Case HIGH-3: HIRAI_METHOD_INSTALL_SH で exit 42 透過
# ============================================================
section "Case HIGH-3: HIRAI_METHOD_INSTALL_SH exit code 透過"

DUMMY_INSTALL_SH="$(mktemp /tmp/dummy-install-XXXXX.sh)"
printf '%s\n' '#!/bin/bash' 'exit 42' > "$DUMMY_INSTALL_SH"
chmod +x "$DUMMY_INSTALL_SH"
TMPDIR_HIGH3="$(mktemp -d /tmp/cli-smoke-high3-XXXXX)"

HIRAI_METHOD_INSTALL_SH="$DUMMY_INSTALL_SH" node bin/cli.js install "$TMPDIR_HIGH3" >/dev/null 2>&1
HIGH3_EXIT=$?

if [ $HIGH3_EXIT -eq 42 ]; then
  pass "HIGH-3: HIRAI_METHOD_INSTALL_SH=<exit 42> で cli.js が exit 42 を透過"
else
  fail "HIGH-3: exit code 透過が期待値と異なる" "expected=42 actual=$HIGH3_EXIT"
fi
rm -rf "$DUMMY_INSTALL_SH" "$TMPDIR_HIGH3"

# ============================================================
# Case HIGH-4: npm pack に transient ファイルが含まれない
# ============================================================
section "Case HIGH-4: npm pack — transient 除外"

# PACK_OUT は Case 13 で取得済み (npm pack --dry-run)
# transient 対象: docs/draft/ / docs/tasks/ (templates/ を除く) / .workflow-state/
TRANSIENT_COUNT="$(echo "$PACK_OUT" | grep -E "docs/draft/|docs/tasks/|\.workflow-state/" 2>/dev/null | grep -v "templates/" | wc -l | tr -d ' \n')"
TRANSIENT_COUNT="${TRANSIENT_COUNT:-0}"
if [ "$TRANSIENT_COUNT" -eq 0 ]; then
  pass "HIGH-4: npm pack に transient (docs/draft/ docs/tasks/ .workflow-state/) が含まれない"
else
  fail "HIGH-4: npm pack に transient ファイルが混入" "count=$TRANSIENT_COUNT"
fi

# ============================================================
# Case MED-5: update 引数なし → exit 1
# ============================================================
section "Case MED-5: update 引数なし"

node bin/cli.js update >/dev/null 2>&1
UPDATE_NO_DIR_EXIT=$?
if [ $UPDATE_NO_DIR_EXIT -eq 1 ]; then
  pass "MED-5: update 引数なし → exit 1"
else
  fail "MED-5: update 引数なしの exit code が期待値と異なる" "expected=1 actual=$UPDATE_NO_DIR_EXIT"
fi

# ============================================================
# Case MED-6: npm pack に CLAUDE.md / install.sh / .claude/CommonRules.md を含む
# ============================================================
section "Case MED-6: npm pack — 必須ファイル同梱"

# PACK_OUT は Case 13 で取得済み
PACK_HAS_CLAUDE_MD="$(echo "$PACK_OUT" | grep -c "CLAUDE.md" 2>/dev/null | tr -d ' \n')"
PACK_HAS_CLAUDE_MD="${PACK_HAS_CLAUDE_MD:-0}"
if [ "$PACK_HAS_CLAUDE_MD" -gt 0 ]; then
  pass "MED-6: npm pack に CLAUDE.md が含まれる"
else
  fail "MED-6: npm pack に CLAUDE.md が含まれない"
fi

PACK_HAS_INSTALL_SH="$(echo "$PACK_OUT" | grep -c "install.sh" 2>/dev/null | tr -d ' \n')"
PACK_HAS_INSTALL_SH="${PACK_HAS_INSTALL_SH:-0}"
if [ "$PACK_HAS_INSTALL_SH" -gt 0 ]; then
  pass "MED-6: npm pack に install.sh が含まれる"
else
  fail "MED-6: npm pack に install.sh が含まれない"
fi

PACK_HAS_COMMONRULES="$(echo "$PACK_OUT" | grep -c "CommonRules.md" 2>/dev/null | tr -d ' \n')"
PACK_HAS_COMMONRULES="${PACK_HAS_COMMONRULES:-0}"
if [ "$PACK_HAS_COMMONRULES" -gt 0 ]; then
  pass "MED-6: npm pack に .claude/CommonRules.md が含まれる"
else
  fail "MED-6: npm pack に .claude/CommonRules.md が含まれない"
fi

# ============================================================
# 集計
# ============================================================
TOTAL=$((PASS + FAIL))
printf "\n=== 結果 ===\n"
printf "PASS: %d / %d\n" "$PASS" "$TOTAL"
printf "FAIL: %d\n" "$FAIL"
if [ $WARN_COUNT -gt 0 ]; then
  printf "WARN: %d\n" "$WARN_COUNT"
fi

if [ $FAIL -eq 0 ]; then
  printf "\nAll %d cases PASSED.\n" "$PASS"
  exit 0
else
  printf "\n%d case(s) FAILED.\n" "$FAIL"
  exit 1
fi
