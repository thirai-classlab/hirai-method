#!/usr/bin/env bash
# stale-harness-detect.sh — SessionStart hook (task-56 F)
#
# 役割:
#   consuming repo が `install.sh --update` を取り込まないまま旧 harness で稼働継続する事故を
#   SessionStart で検出し、WARN を `<system-reminder>` で stderr 注入する。
#   block しない (honor system、誤検知時の害を最小化)。
#
#   最新 repo (marker 全在 + harness_version 正常 + npm semver 同値) では
#   **0 byte 完全無音** (silent exit 0)。
#
# 検出ロジック (Phase 1 = marker/date 検出):
#   1. marker file 欠落: `harness-config.yml` の `stale_harness_markers` (list) を読み、
#      `.claude/<path>` が存在しないものを WARN。
#   2. version key 欠落 / sanitize 不一致: `harness-config.yml` の `harness_version` を読み、
#      `YYYY-MM-DD` regex に合わない or 未設定なら `UNKNOWN` 表示で WARN。
#   3. 未来日付: harness_version > today (UTC) なら別 WARN「stamp 異常 (future)」。
#
# 検出ロジック (task-84 = npm registry semver 比較、Phase 1 と独立に走る):
#   A. throttle: `.claude/.stale-harness-state/last-check` の mtime が
#      `stale_harness_check_interval_hours` (default 24) 以内なら registry を取得せず skip。
#   B. `harness_npm_version` stamp 読込 → 不在/不正なら fail-open silent (version 比較 skip、
#      marker 欠落検出は上記 Phase 1 が担当)。
#   C. registry latest 取得 (`HIRAI_METHOD_REGISTRY_BASE` + `/@takuma-hirai%2Fhirai-method/latest`、
#      timeout 短く)。失敗は fail-open silent + marker (last-check) 更新。
#   D. compareSemver(stamp, latest): latest > stamp → WARN「npx ... update」。それ以外 silent。
#      semver 比較は bin/cli.js の compareSemver を `node -e` 経由で再利用 (SSoT)、
#      cli.js / node 不在環境向けに hook 内 fallback semver 比較を持つ。
#   E. 全経路 fail-open + last-check marker 更新 (次回 throttle のため)。
#
# fail-open 規範:
#   - config 不在 / parse fail / find 異常 / lock fail / network 失敗 → silent pass (exit 0)
#   - feature toggle OFF → silent pass
#   - 重複 WARN 抑制 (marker/date): `.claude/.stale-harness-state/<sha>.fired` (同一 session marker)
#   - registry throttle: `.claude/.stale-harness-state/last-check` (mtime ベース、interval_hours)
#
# 環境変数:
#   HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false  ... 完全 OFF (bypass)
#   HC_STALE_HARNESS_DETECT_STATE_DIR              ... state dir 上書き (test isolation)
#   HC_STALE_HARNESS_CHECK_INTERVAL_HOURS          ... registry throttle 間隔 (default 24)
#   HIRAI_METHOD_REGISTRY_BASE                     ... registry base (default registry.npmjs.org、
#                                                     task-83 と共有、test 用 local http server)
#   CLAUDE_PROJECT_DIR                              ... Claude Code 注入の project root
#   HC_CONFIG_PATH                                  ... config-loader.sh 経路 (test override)
#
# Stdin:  SessionStart hook JSON (使わない)
# Stdout: 未使用
# Stderr: 条件成立時に <system-reminder> ブロック
# Exit:   常に 0 (fail-open)
#
# 制約:
#   file-top に `set -euo pipefail` を書かない (CLAUDE.md HIGH 教訓
#   feedback_set_e_in_sourced_libs)。実装本体は subshell 関数化で局所化する。
#
# 起源:
#   - 調査資料: docs/draft/harness-health-7items-analysis.md §3-F
#   - 設計 draft: docs/draft/stale-harness-detection.md (案 C ハイブリッド、§8.1 reviewer 反映)
#               + docs/draft/npx-auto-update.md §3 (task-84 registry 比較、案 A 準自動)
#   - task: docs/tasks/task-56-stale-harness-detection.md
#         + docs/tasks/task-84-npx-auto-update.md (Step 2-4)

set -u

# stdin 消費 (SessionStart hook JSON は使わない)
cat >/dev/null 2>&1 || true

# --- config 読み込み ---
# harness-config.yml を config-loader 経由で読み、HC_* env として export する。
# source 失敗時は || true で fail-open (caller への set flags leak を防止)。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/config-loader.sh
if [ -f "$SCRIPT_DIR/lib/config-loader.sh" ]; then
    # shellcheck disable=SC1091
    source "$SCRIPT_DIR/lib/config-loader.sh" 2>/dev/null || true
fi

# Feature toggle (config-loader source **後** に判定、規範通り)
if command -v is_feature_enabled >/dev/null 2>&1 && ! is_feature_enabled stale_harness_detect; then
    exit 0
fi

# Phase 2 で別 hook を統合する場合に備えた個別 enable も尊重 (env > yml)
if [ "${HC_FEATURE_STALE_HARNESS_DETECT_ENABLED:-true}" = "false" ]; then
    exit 0
fi

_shd_main() (
    set -uo pipefail

    # --- project root 解決 (list-md-plan-first-reminder.sh と同パターン) ---
    local repo_root
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
        repo_root="$CLAUDE_PROJECT_DIR"
    elif repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        :
    else
        repo_root="$(pwd)"
    fi

    # --- config path 解決 ---
    # config-loader が export した HC_CONFIG_PATH を default、test では override 可
    local config_path="${HC_CONFIG_PATH:-${repo_root}/.claude/harness-config.yml}"
    # 不在 → silent fail-open
    [ -f "$config_path" ] || exit 0

    # --- marker list 取得 ---
    # config-loader は stale_harness_markers を _HC_KNOWN_KEYS に未登録のため
    # HC_STALE_HARNESS_MARKERS env として export されないこともある。
    # ここでは config 直 grep で取得して bash 配列パースする (依存削減)。
    # config-loader が前段で yml を eval していれば `${HC_STALE_HARNESS_MARKERS:-}` も拾えるが、
    # safety のため直接 yml を読む経路を採る。
    local markers_raw
    markers_raw=$(grep -E '^stale_harness_markers:' "$config_path" 2>/dev/null | head -1 | sed -E 's/^stale_harness_markers:[[:space:]]*//; s/^[[:space:]]*//; s/[[:space:]]*$//')

    # 空 / 未設定 / `[]` → silent fail-open
    [ -n "$markers_raw" ] || exit 0
    case "$markers_raw" in
        '[]'|'[ ]') exit 0 ;;
    esac

    # `[a, b, c]` 形式の解体
    local inner
    inner="${markers_raw#\[}"
    inner="${inner%\]}"
    inner=$(printf '%s' "$inner" | tr ',' '\n')

    # bash 3.2 + set -u 互換: 配列は newline-separated 文字列 (空配列の unbound 回避)
    local missing_list=""
    local missing_count=0
    local m m_trim m_full
    while IFS= read -r m; do
        # 前後空白 + クォート strip
        m_trim="${m#"${m%%[![:space:]]*}"}"
        m_trim="${m_trim%"${m_trim##*[![:space:]]}"}"
        case "$m_trim" in
            \"*\") m_trim="${m_trim#\"}"; m_trim="${m_trim%\"}" ;;
            \'*\') m_trim="${m_trim#\'}"; m_trim="${m_trim%\'}" ;;
        esac
        [ -n "$m_trim" ] || continue
        m_full="${repo_root}/.claude/${m_trim}"
        if [ ! -e "$m_full" ]; then
            if [ -z "$missing_list" ]; then
                missing_list="$m_trim"
            else
                missing_list="${missing_list}, ${m_trim}"
            fi
            missing_count=$((missing_count + 1))
        fi
    done <<< "$inner"

    # --- harness_version 取得 + sanitize ---
    local version_raw
    version_raw=$(grep -E '^harness_version:' "$config_path" 2>/dev/null | head -1 | sed -E 's/^harness_version:[[:space:]]*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    # outer quote strip
    case "$version_raw" in
        \"*\") version_raw="${version_raw#\"}"; version_raw="${version_raw%\"}" ;;
        \'*\') version_raw="${version_raw#\'}"; version_raw="${version_raw%\'}" ;;
    esac

    # sanitize: YYYY-MM-DD 不一致 (空文字含む) → UNKNOWN 表示
    local version_safe="UNKNOWN"
    local version_valid=false
    if printf '%s' "$version_raw" | LC_ALL=C grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
        version_safe="$version_raw"
        version_valid=true
    fi

    # --- 未来日付検出 ---
    local future_stamp=false
    if [ "$version_valid" = "true" ]; then
        local today
        today=$(date -u +%Y-%m-%d 2>/dev/null || echo "")
        # 単純な辞書比較で OK (YYYY-MM-DD format は辞書順 = 時系列順)
        if [ -n "$today" ] && [ "$version_safe" \> "$today" ]; then
            future_stamp=true
        fi
    fi

    # --- 早期 return: WARN 不要なケース ---
    # marker 全在 + version 正常 (today 以前 valid) → silent
    if [ "$missing_count" -eq 0 ] && [ "$version_valid" = "true" ] && [ "$future_stamp" = "false" ]; then
        exit 0
    fi

    # --- 重複 WARN 抑制 (state file) ---
    local state_dir="${HC_STALE_HARNESS_DETECT_STATE_DIR:-${repo_root}/.claude/.stale-harness-state}"
    mkdir -p "$state_dir" 2>/dev/null || exit 0  # 作れないなら silent fail-open

    # sha key: config path + version_safe + missing count で十分 unique
    # (sha512sum / shasum / md5 のいずれかを使う、無ければ単純連結 fallback)
    local sha_key
    sha_key=$(printf '%s|%s|%d' "$config_path" "$version_safe" "$missing_count")
    local sha_hash
    if command -v shasum >/dev/null 2>&1; then
        sha_hash=$(printf '%s' "$sha_key" | shasum 2>/dev/null | awk '{print $1}')
    elif command -v sha256sum >/dev/null 2>&1; then
        sha_hash=$(printf '%s' "$sha_key" | sha256sum 2>/dev/null | awk '{print $1}')
    else
        # 単純 fallback (衝突確率高いが silent fail-open より優先)
        sha_hash=$(printf '%s' "$sha_key" | od -An -c | tr -d ' \n' | head -c 32)
    fi
    [ -n "$sha_hash" ] || sha_hash="default"

    local fired_marker="${state_dir}/${sha_hash}.fired"
    if [ -f "$fired_marker" ]; then
        exit 0  # 同一 session で既に WARN 済 → silent
    fi
    : > "$fired_marker" 2>/dev/null || true  # 作成失敗しても続行 (fail-open)

    # --- WARN 構築 ---
    # printf format の先頭 `-` を避けるため、全行を `%s\n` 経由で渡す。
    # (`printf '- foo\n'` は bash 3.2 builtin が `-` をオプション扱いして失敗するケースがある)
    {
        printf '\n'
        printf '%s\n' '<system-reminder>'
        printf '%s\n' '[stale harness] consuming repo の harness が古い可能性を検出しました:'
        printf '%s\n' "- harness_version: ${version_safe}"
        if [ "$missing_count" -gt 0 ]; then
            printf '%s\n' "- 主要 marker file 欠落 (${missing_count} 件): ${missing_list}"
        fi
        if [ "$version_valid" = "false" ]; then
            printf '%s\n' '- harness_version stamp が YYYY-MM-DD 形式ではありません (yml 未設定 or 破損)。'
        fi
        if [ "$future_stamp" = "true" ]; then
            printf '%s\n' '- WARN: future stamp 異常 — harness_version が今日 (UTC) より未来の日付です (yml stamp が誤書込み or clock skew)。'
        fi
        printf '\n'
        printf '%s\n' '対処: 採用元 hirai-method repo で `bash install.sh --update <この repo の絶対 path>` を terminal で実行し、最新 harness を取り込んでください (cross-repo write は agent 経路 deny、user manual 必須)。'
        printf '%s\n' 'bypass: HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false または harness-config.yml feature_stale_harness_detect_enabled: false'
        printf '%s\n' '規範: .claude/rules/development-process.md §「cross-repo write 例外」/ docs/draft/stale-harness-detection.md'
        printf '%s\n' '</system-reminder>'
    } >&2

    exit 0
)

# =====================================================================
# task-84: npm registry semver 比較 (Phase 1 marker/date 検出とは独立に走る)
# =====================================================================
# 動作仕様 (契約 §「動作仕様」A-E):
#   A. throttle (last-check mtime vs interval_hours) で registry 取得を抑制
#   B. harness_npm_version stamp 読込 (不在/不正は fail-open silent)
#   C. registry latest 取得 (HIRAI_METHOD_REGISTRY_BASE 尊重、timeout 短)
#   D. compareSemver(stamp, latest): latest > stamp → WARN
#   E. 全経路 fail-open + last-check marker 更新
#
# semver 比較は bin/cli.js の compareSemver を再利用 (SSoT)、node/cli.js 不在は
# hook 内 fallback (major.minor.patch 数値分割) を使う。

# _shd_semver_fallback <a> <b> — return 階層: a>b → echo 1 / a<b → echo -1 / a==b → echo 0
#   不正値は echo "" (空 = 比較不能)。cli.js parseSemver と同等 (prerelease/build 無視)。
_shd_semver_fallback() {
    _shd_sf_a="$1"; _shd_sf_b="$2"
    # core 抽出 (先頭 v 除去、+build / -prerelease 切り捨て)
    _shd_sf_a="${_shd_sf_a#v}"; _shd_sf_a="${_shd_sf_a%%+*}"; _shd_sf_a="${_shd_sf_a%%-*}"
    _shd_sf_b="${_shd_sf_b#v}"; _shd_sf_b="${_shd_sf_b%%+*}"; _shd_sf_b="${_shd_sf_b%%-*}"
    # L2 (task-84 fix): cli.js parseSemver は core が 4+ segment なら null を返す。
    #   fallback も 4 桁以上 (`a.b.c.d`) を比較不能 (空) として reject し挙動を揃える。
    case "$_shd_sf_a" in *.*.*.*) printf ''; return 0 ;; esac
    case "$_shd_sf_b" in *.*.*.*) printf ''; return 0 ;; esac
    _shd_sf_i=0
    while [ "$_shd_sf_i" -lt 3 ]; do
        _shd_sf_ai="${_shd_sf_a%%.*}"; _shd_sf_bi="${_shd_sf_b%%.*}"
        # segment 不足は 0 補完
        [ -n "$_shd_sf_ai" ] || _shd_sf_ai=0
        [ -n "$_shd_sf_bi" ] || _shd_sf_bi=0
        # 純数字以外は比較不能
        case "$_shd_sf_ai" in ''|*[!0-9]*) printf ''; return 0 ;; esac
        case "$_shd_sf_bi" in ''|*[!0-9]*) printf ''; return 0 ;; esac
        if [ "$_shd_sf_ai" -gt "$_shd_sf_bi" ]; then printf '1'; return 0; fi
        if [ "$_shd_sf_ai" -lt "$_shd_sf_bi" ]; then printf -- '-1'; return 0; fi
        # 次 segment へ (`.` が無ければ "" に)
        case "$_shd_sf_a" in *.*) _shd_sf_a="${_shd_sf_a#*.}" ;; *) _shd_sf_a="" ;; esac
        case "$_shd_sf_b" in *.*) _shd_sf_b="${_shd_sf_b#*.}" ;; *) _shd_sf_b="" ;; esac
        _shd_sf_i=$((_shd_sf_i + 1))
    done
    printf '0'
    return 0
}

# _shd_compare_semver <a> <b> — cli.js compareSemver 優先、不在時 fallback
#   echo: 1 / -1 / 0 / "" (比較不能)
_shd_compare_semver() {
    _shd_cs_a="$1"; _shd_cs_b="$2"; _shd_cs_cli="$3"
    _shd_cs_out=""
    if [ -n "$_shd_cs_cli" ] && [ -f "$_shd_cs_cli" ] && command -v node >/dev/null 2>&1; then
        # cli.js 再利用 (SSoT)。引数は argv 経由で渡し shell 展開を回避。
        _shd_cs_out=$(node -e '
            try {
              var m = require(process.argv[1]);
              var r = m.compareSemver(process.argv[2], process.argv[3]);
              process.stdout.write(r === null || r === undefined ? "" : String(r));
            } catch (e) { process.stdout.write(""); }
        ' "$_shd_cs_cli" "$_shd_cs_a" "$_shd_cs_b" 2>/dev/null || true)
    fi
    # cli.js 経路が空 (node 不在 / require 失敗 / 比較不能) なら fallback
    if [ -z "$_shd_cs_out" ]; then
        _shd_cs_out=$(_shd_semver_fallback "$_shd_cs_a" "$_shd_cs_b")
    fi
    printf '%s' "$_shd_cs_out"
}

_shd_registry_check() (
    set -uo pipefail

    # --- project root 解決 (Phase 1 と同パターン) ---
    local repo_root
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
        repo_root="$CLAUDE_PROJECT_DIR"
    elif repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        :
    else
        repo_root="$(pwd)"
    fi

    local config_path="${HC_CONFIG_PATH:-${repo_root}/.claude/harness-config.yml}"
    [ -f "$config_path" ] || exit 0

    # --- A. throttle ---
    local state_dir="${HC_STALE_HARNESS_DETECT_STATE_DIR:-${repo_root}/.claude/.stale-harness-state}"
    local last_check="${state_dir}/last-check"
    local interval_hours="${HC_STALE_HARNESS_CHECK_INTERVAL_HOURS:-24}"
    case "$interval_hours" in ''|*[!0-9]*) interval_hours=24 ;; esac

    if [ -f "$last_check" ]; then
        local now mtime age_sec interval_sec
        now=$(date +%s 2>/dev/null || echo "")
        # mtime 取得: GNU (stat -c) 先 / BSD (stat -f) fallback、失敗は空。
        # M1 (task-84 fix): GNU stat は `-f` を「filesystem 情報」と誤解釈し
        # mtime を返さない (Linux で throttle 失効)。GNU を先に試し、
        # macOS/BSD では `-c` が err → `-f %m` で fallback する。
        mtime=$(stat -c %Y "$last_check" 2>/dev/null || stat -f %m "$last_check" 2>/dev/null || echo "")
        if [ -n "$now" ] && [ -n "$mtime" ]; then
            age_sec=$((now - mtime))
            interval_sec=$((interval_hours * 3600))
            # interval 未満なら skip (registry 取得しない)
            if [ "$age_sec" -ge 0 ] && [ "$age_sec" -lt "$interval_sec" ]; then
                exit 0
            fi
        fi
    fi

    # --- B. harness_npm_version stamp 読込 ---
    local stamp_raw
    stamp_raw=$(grep -E '^harness_npm_version:' "$config_path" 2>/dev/null | head -1 | sed -E 's/^harness_npm_version:[[:space:]]*//; s/^[[:space:]]*//; s/[[:space:]]*$//')
    case "$stamp_raw" in
        \"*\") stamp_raw="${stamp_raw#\"}"; stamp_raw="${stamp_raw%\"}" ;;
        \'*\') stamp_raw="${stamp_raw#\'}"; stamp_raw="${stamp_raw%\'}" ;;
    esac
    # semver (x.y.z core、最大 3 segment) でなければ version 比較不能 → fail-open silent。
    # M-1/L4 (task-84 fix): 末尾 `$` を付け anchored 一致にする。`$` 無しだと
    # `1.2.3.4` や `1.2-junk` 等の 4+ segment / 末尾ゴミを前方一致で誤受理し、
    # fallback semver (3 segment core 比較) との乖離を生む。
    if ! printf '%s' "$stamp_raw" | LC_ALL=C grep -qE '^v?[0-9]+(\.[0-9]+){0,2}$'; then
        exit 0
    fi

    # 以降 registry 取得を試みるため、結果に関わらず last-check を更新する
    # (失敗しても throttle を効かせ、毎 session の network 取得を防ぐ)。
    mkdir -p "$state_dir" 2>/dev/null || exit 0  # 作れないなら silent fail-open (throttle 不能)
    : > "$last_check" 2>/dev/null || true

    # --- C. registry latest 取得 ---
    # cli.js と同じ encode (`@takuma-hirai/hirai-method` → `@takuma-hirai%2Fhirai-method`)。
    local reg_base="${HIRAI_METHOD_REGISTRY_BASE:-https://registry.npmjs.org}"
    # 末尾 / 除去 (二重 // 回避)
    reg_base="${reg_base%/}"
    local url="${reg_base}/@takuma-hirai%2Fhirai-method/latest"

    # L-1 (task-84 fix、optional): test 以外 (state dir override 不使用) で registry が
    #   非 https の場合のみ WARN 1 行。test (local http server + state dir override) は壊さない。
    if [ -z "${HC_STALE_HARNESS_DETECT_STATE_DIR:-}" ]; then
        case "$reg_base" in
            https://*) : ;;
            *) printf '%s\n' '[stale-harness-detect] WARN: HIRAI_METHOD_REGISTRY_BASE が非 https です。registry 取得を平文で行います (中間者リスク)。' >&2 ;;
        esac
    fi

    # M-2 (SSRF 防止): wget は redirect を 0 に固定 (`--max-redirect=0`)。
    #   curl は `-L` を付けないため既定で redirect 追従しない。
    # L-3 (response size 上限): curl `--max-filesize`、wget `--quota` で 64 KiB に制限し
    #   過大 response (DoS / メモリ枯渇) を防ぐ。registry latest JSON は十分小さい。
    local body=""
    if command -v curl >/dev/null 2>&1; then
        body=$(curl -fsS --max-time 4 --max-filesize 65536 "$url" 2>/dev/null || true)
    elif command -v wget >/dev/null 2>&1; then
        body=$(wget -q -T 4 --max-redirect=0 --quota=65536 -O - "$url" 2>/dev/null || true)
    fi
    # network 失敗 / 空応答 → fail-open silent (last-check は更新済)
    [ -n "$body" ] || exit 0

    # latest version 抽出 ("version":"x.y.z")。grep/sed のみ (jq 非依存)。
    local latest
    latest=$(printf '%s' "$body" | LC_ALL=C grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')
    [ -n "$latest" ] || exit 0

    # --- D. compareSemver ---
    local cli_path="${repo_root}/bin/cli.js"
    local cmp
    cmp=$(_shd_compare_semver "$latest" "$stamp_raw" "$cli_path")
    # 比較不能 (空) → fail-open silent
    [ -n "$cmp" ] || exit 0
    # latest > stamp のときのみ WARN (cmp == 1)
    [ "$cmp" = "1" ] || exit 0

    # --- WARN 構築 (契約 §「WARN メッセージ」厳守) ---
    {
        printf '\n'
        printf '%s\n' '<system-reminder>'
        printf '%s\n' "[stale-harness-detect] 新版 ${latest} あり (現 ${stamp_raw})。次で更新: npx @takuma-hirai/hirai-method@latest update ${repo_root}"
        printf '%s\n' 'block しません (honor system、WARN のみ)。cross-repo write は user manual / terminal 実行が必要です。'
        printf '%s\n' 'bypass: HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false または harness-config.yml feature_stale_harness_detect_enabled: false'
        printf '%s\n' '規範: .claude/rules/development-process.md §harness 取込チェックリスト / docs/draft/npx-auto-update.md'
        printf '%s\n' '</system-reminder>'
    } >&2

    exit 0
)

_shd_main "$@"
_shd_registry_check "$@"
exit 0
