#!/usr/bin/env bash
# stale-harness-detect.sh — SessionStart hook (task-56 F)
#
# 役割:
#   consuming repo が `install.sh --update` を取り込まないまま旧 harness で稼働継続する事故を
#   SessionStart で検出し、WARN を `<system-reminder>` で stderr 注入する。
#   block しない (honor system、誤検知時の害を最小化)。
#
#   最新 repo (marker 全在 + harness_version 正常) では **0 byte 完全無音** (silent exit 0)。
#
# 検出ロジック (Phase 1):
#   1. marker file 欠落: `harness-config.yml` の `stale_harness_markers` (list) を読み、
#      `.claude/<path>` が存在しないものを WARN。
#   2. version key 欠落 / sanitize 不一致: `harness-config.yml` の `harness_version` を読み、
#      `YYYY-MM-DD` regex に合わない or 未設定なら `UNKNOWN` 表示で WARN。
#   3. 未来日付: harness_version > today (UTC) なら別 WARN「stamp 異常 (future)」。
#   日数比較 (古さ判定) は **Phase 2 延期**。
#
# fail-open 規範:
#   - config 不在 / parse fail / find 異常 / lock fail → silent pass (exit 0)
#   - feature toggle OFF → silent pass
#   - 重複 WARN 抑制: `.claude/.stale-harness-state/<sha>.fired` (同一 session marker)
#
# 環境変数:
#   HC_FEATURE_STALE_HARNESS_DETECT_ENABLED=false  ... 完全 OFF (bypass)
#   HC_STALE_HARNESS_DETECT_STATE_DIR              ... state dir 上書き (test isolation)
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
#   - task: docs/tasks/task-56-stale-harness-detection.md

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

_shd_main "$@"
exit 0
