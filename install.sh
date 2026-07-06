#!/usr/bin/env bash
# 平井メソッド (hirai-method) — robust installer
#
# Usage:
#   ./install.sh <target-project-dir> [--update|--force|--overwrite-all] [--preset=<name>] [--lang=<id>] [--dry-run] [--no-mcp] [--mcp-servers=<csv>] [--no-docs] [--no-hooks] [--no-doctor]
#
# Modes (--update / --force / --overwrite-all are mutually exclusive):
#   (default)  : 新規 install。既存 .claude は .bak タイムスタンプ付きで退避、既存 CLAUDE.md は不可侵。
#                CLAUDE.md 不在時は project manifest 検出 → 言語別 template auto-fill で
#                CLAUDE.md を直接生成 (`<...>` placeholder 0、@.claude/CommonRules.md 参照済、task-89)。
#                .githooks/pre-commit + core.hooksPath 自動設定で fast smoke gate 有効化 (task-92、--no-hooks で opt-out)。
#   --update   : 既存 .claude/ を退避せず rsync で増分上書き。state dir / settings.local.json は保持。
#                CLAUDE.md / .mcp.json / .gitignore は触らない (既存保護)。
#                完了時に sync 変更 file 一覧 + 分離 commit 案内を出力 (task-58 G1)。
#   --commit   : (--update と併用、opt-in) sync 対象 .claude/ path のみ git add + chore(harness): sync で
#                自動 commit する。project file (root README.md 等) は触らない。git reset 禁止 (HIGH 教訓)。
#                非 git target なら commit skip + WARN (task-58 G1)。
#   --force    : 既存 .claude / CLAUDE.md を backup せず上書き。CLAUDE.md は auto-fill 生成物で上書き (task-89)。
#   --overwrite-all : (task-79) drift した target を SSoT へ強制リセットする全上書き mode。
#                既存 .claude/ を rsync で上書きするが **settings.local.json のみ** 温存し、それ以外
#                (settings.json / harness-config.local.yml / state dir 群 / worktrees) も source で上書き。
#                `--delete` は使わない (= 上書きのみ、target 独自 file は残す)。CLAUDE.md / .mcp.json /
#                .gitignore は --force 準拠。注意: target の local override は失われる (settings.local.json のみ残る)。
#   --dry-run  : 実行内容を表示するのみ (rsync -n + 各 cp / mkdir を echo)。
#   --no-mcp   : .mcp.json を配置しない (Serena 不要な project)。
#   --mcp-servers=<csv> : (task-90) 配布する MCP server を csv で選択
#                (default: serena,context7 = env placeholder 0 の minimal 2 server、
#                 特殊 token 'all' で従来全 7 server 配布 = 後方互換)。
#                選択可能: serena, context7, github, salesforce, agent-browser, asana-pat, slack。
#                --no-mcp との併用は exit 64。§3 配布 logic は Step 2 で jq filter 化予定。
#   --no-docs  : docs/tasks/, docs/draft/ の templates 配置を skip。
#   --no-hooks : (task-92) .githooks/pre-commit 配布 + core.hooksPath 自動設定を skip。
#                default で配布 + 設定。既存 .githooks/ は不可侵、fast smoke gate (< 3s) opt-out。
#   --preset=<name> : (task-85) §6.4 preset bootstrap で生成する harness-config.local.yml の
#                enforcement preset を指定 (advisory | team-default | strict | harness-dev、
#                default: team-default = HOTFIX-1 後方互換)。team-default/strict → 8 toggle true、
#                advisory/harness-dev → 8 toggle 明示 false。既存 local.yml 時は無視 (WARN + verbatim 保持)。
#   --lang=<id> : (task-89) CLAUDE.md auto-fill 対象言語を明示指定
#                (ts | py | go | rust | php | swift | generic、default: 未指定=manifest 検出で自動判定)。
#   --no-doctor : (task-87) install 末尾の self-doctor 検証 (setup issue 検出) を skip。
#                default で有効。dry-run 時は自動 skip (mutation 前の検証は無意味)。
#
# Exclude (state / user-local):
#   .gateguard-state/ .taskguard-state/ .confidence-gate-state/ .failure-window/
#   .agent-markers/ .context-budget-state/ .improvement-proposal-state/ .workflow-state/
#   settings.local.json settings.local.example.json bash-whitelist-requests/ worktrees/ project-rules/ (task-82, project-owned)
#
# Dependencies: rsync, bash 4+
#
# ============================================================
# WARNING: cross-repo execution restriction
# ============================================================
# This script is a cross-repo write operation
# (writes from this repo into an external target project directory).
# Claude Code agent context cannot execute this — sandbox + delegation-guard
# 二重制約 により cross-repo write は denied される。
#
# **user manual (terminal) 実行のみ可能** です。
# (agent / subagent / hook bypass env いずれも回避不可)
#
# 同様に `--update` / `--overwrite-all <target>` mode (既存 .claude/ への上書き) も
# user manual (terminal) 実行のみ可能 です。
#
# 詳細: .claude/rules/development-process.md §「cross-repo write 例外」を参照
# ============================================================

set -euo pipefail

# ============================================================
# arg parse
# ============================================================
TARGET=""
MODE="install"          # install / update / force / overwrite-all
DRY_RUN=false
WITH_MCP=true
MCP_SERVERS="serena,context7"    # (task-90) --mcp-servers csv default = env placeholder 0 minimal
MCP_SERVERS_SET=false             # true if --mcp-servers explicitly given (for --no-mcp conflict + Step 2 signal)
WITH_DOCS=true
WITH_HOOKS=true          # --no-hooks で false = .githooks/pre-commit 配布 + core.hooksPath 設定 skip (task-92 Step 2)
WITH_DOCTOR=true         # --no-doctor で false = install 末尾 self-doctor 検証 skip (task-87 Step 2)
COMMIT_AFTER_SYNC=false  # --commit flag (task-58 G1, opt-in for --update only)
PRESET="team-default"    # --preset default = HOTFIX-1 現行挙動維持 (後方互換、task-85)
PRESET_EXPLICIT=false    # --preset 明示指定の有無 (既存 local.yml / self-install 時の WARN 用)
LANG_OVERRIDE=""         # --lang override (空 = manifest 検出で自動判定、task-89)
LANG_EXPLICIT=false      # --lang 明示指定の有無 (echo 出力で "override" と "detected" を出し分け)

# M-1: detect conflicting mode flags. --update / --force / --overwrite-all each set
# MODE; specifying more than one (or repeating one) would silently last-wins into an
# unintended mode (e.g. --update --force → force rm -rf). Track whether MODE was
# already chosen and abort instead of guessing. (task-79: --overwrite-all joins the
# 3-way mutual exclusion.)
MODE_SET=false
for arg in "$@"; do
  case "$arg" in
    --update|--force|--overwrite-all)
      if $MODE_SET; then
        echo "[install] error: conflicting mode flags (--update / --force / --overwrite-all are mutually exclusive — give at most one)" >&2
        exit 64
      fi
      MODE_SET=true
      case "$arg" in
        --update)        MODE="update" ;;
        --force)         MODE="force" ;;
        --overwrite-all) MODE="overwrite-all" ;;
      esac
      ;;
    --commit)   COMMIT_AFTER_SYNC=true ;;
    --dry-run)  DRY_RUN=true  ;;
    --no-mcp)   WITH_MCP=false ;;
    --mcp-servers=*)
      # task-90 Step 1: 配布 MCP server を csv で選択。値検証はここでは format のみ
      # (空 csv / 空 token / token 形式 / 'all' 単独判定) を行う。source .mcp.json への
      # key 実在検証は Step 2 (jq 存在時のみ) 側が担当する (fail-open: jq 不在時 skip)。
      # --no-mcp との conflict は arg loop 後にまとめて検出する (--commit vs --update と同 pattern)。
      MCP_SERVERS="${arg#--mcp-servers=}"
      MCP_SERVERS_SET=true
      if [[ -z "$MCP_SERVERS" ]]; then
        echo "[install] error: --mcp-servers requires a non-empty csv (e.g. --mcp-servers=serena,context7 or --mcp-servers=all)" >&2
        exit 64
      fi
      # 事前検査: leading/trailing/duplicated comma を検出。bash `IFS=',' read -a` は
      # trailing 空 field を捨てる仕様のため、read 前に csv 生値でチェックしないと
      # 'serena,' が silent pass する (下 for loop の empty token check は leading/中間のみ捕捉)。
      if [[ "$MCP_SERVERS" == ,* || "$MCP_SERVERS" == *, || "$MCP_SERVERS" == *,,* ]]; then
        echo "[install] error: --mcp-servers csv has empty token (leading/trailing/duplicated comma)" >&2
        exit 64
      fi
      # token format 検証: 各 token は ^[A-Za-z0-9][A-Za-z0-9_-]*$。
      # 併せて 'all' は単独 token のみ許可 (all,serena → exit 64)。
      _has_all=false
      _has_other=false
      IFS=',' read -r -a _mcp_tokens <<< "$MCP_SERVERS"
      for _tok in "${_mcp_tokens[@]}"; do
        if [[ -z "$_tok" ]]; then
          echo "[install] error: --mcp-servers csv contains empty token (trailing/duplicated comma?)" >&2
          exit 64
        fi
        if [[ ! "$_tok" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
          echo "[install] error: --mcp-servers token '$_tok' has invalid format (allowed: [A-Za-z0-9][A-Za-z0-9_-]*)" >&2
          exit 64
        fi
        if [[ "$_tok" == "all" ]]; then
          _has_all=true
        else
          _has_other=true
        fi
      done
      if $_has_all && $_has_other; then
        echo "[install] error: --mcp-servers=all must be used alone (not combined with other server names)" >&2
        exit 64
      fi
      unset _mcp_tokens _tok _has_all _has_other
      ;;
    --no-docs)  WITH_DOCS=false ;;
    --no-hooks) WITH_HOOKS=false ;;
    --no-doctor) WITH_DOCTOR=false ;;
    --preset=*)
      PRESET="${arg#--preset=}"
      # allowed set は hc-config.sh _validate_default_preset と同一 4 値 (SSoT)。
      # drift は install-local-yml-smoke case M (静的比較) で機械検出する (task-85)。
      case "$PRESET" in
        advisory|team-default|strict|harness-dev) PRESET_EXPLICIT=true ;;
        *)
          echo "[install] error: invalid --preset '$PRESET' (must be one of: advisory, team-default, strict, harness-dev)" >&2
          exit 64
          ;;
      esac
      ;;
    --lang=*)
      # task-89: CLAUDE.md auto-fill 対象言語の明示指定。7 値 validation、
      # 不正値 exit 64。未指定時は detect_project_lang() が manifest から自動判定。
      LANG_OVERRIDE="${arg#--lang=}"
      case "$LANG_OVERRIDE" in
        ts|py|go|rust|php|swift|generic) LANG_EXPLICIT=true ;;
        *)
          echo "[install] error: invalid --lang '$LANG_OVERRIDE' (must be one of: ts, py, go, rust, php, swift, generic)" >&2
          exit 64
          ;;
      esac
      ;;
    -h|--help)
      # L-2: print the full header comment block including the cross-repo WARNING
      # (ends at the closing ===== of the WARNING box before `set -euo pipefail`;
      # task-79 added 4 mode-doc lines, task-85 added 4 --preset doc lines, task-89
      # rewrote (default) mode desc (+1 line) + added --lang doc (+2 lines), task-90
      # added 5 --mcp-servers doc lines, task-87 added 2 --no-doctor doc lines,
      # task-92 added 1 line to (default) desc + 2 --no-hooks doc lines
      # so the box now ends at line 65).
      sed -n '2,65p' "$0"
      exit 0
      ;;
    -*)
      echo "[install] unknown option: $arg" >&2
      exit 64
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$arg"
      else
        echo "[install] too many positional args: $arg" >&2
        exit 64
      fi
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "usage: ./install.sh <target-project-dir> [--update [--commit]|--force|--overwrite-all|--preset=<name>|--lang=<id>|--dry-run|--no-mcp|--mcp-servers=<csv>|--no-docs|--no-hooks|--no-doctor]" >&2
  exit 64
fi

# --commit は --update mode 専用 (task-58 G1)
if $COMMIT_AFTER_SYNC && [[ "$MODE" != "update" ]]; then
  echo "[install] error: --commit requires --update mode" >&2
  exit 64
fi

# --no-mcp と --mcp-servers の併用は conflict (task-90)
# 「全 skip」と「選択配布」は矛盾 → 明示併用は user 意図不明として fail-fast
# (--commit vs --update と同 pattern、last-wins による silent 事故を防ぐ)。
if ! $WITH_MCP && $MCP_SERVERS_SET; then
  echo "[install] error: --no-mcp and --mcp-servers cannot be used together" >&2
  exit 64
fi

if [[ ! -d "$TARGET" ]]; then
  echo "[install] error: '$TARGET' is not a directory" >&2
  exit 64
fi

# absolute paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$(cd "$TARGET" && pwd)"

if [[ "$SCRIPT_DIR" == "$TARGET" ]]; then
  echo "[install] error: target equals source ($SCRIPT_DIR). Run from harness repo, install into another dir." >&2
  exit 64
fi

if ! command -v rsync >/dev/null 2>&1; then
  echo "[install] error: rsync not found. Install rsync first (macOS: brew install rsync, Debian: apt install rsync)." >&2
  exit 69
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
echo "[install] source : $SCRIPT_DIR"
echo "[install] target : $TARGET"
echo "[install] mode   : $MODE  (dry-run=$DRY_RUN, with-mcp=$WITH_MCP, with-docs=$WITH_DOCS)"
echo ""

# ============================================================
# dirty-tree safety: --update / --force / --overwrite-all 前に target の未 commit 変更を warn
# (task-55: user 無警告で上書き rsync する事故を防ぐ。block ではなく warn のみ)
# (task-79: --overwrite-all は local override も上書きするため warn は特に重要)
# ============================================================
if [[ "$MODE" == "update" || "$MODE" == "force" || "$MODE" == "overwrite-all" ]] && ! $DRY_RUN; then
  if command -v git >/dev/null 2>&1 && [[ -d "$TARGET/.git" ]]; then
    DIRTY=$(cd "$TARGET" && git status --short 2>/dev/null | head -20)
    if [[ -n "$DIRTY" ]]; then
      echo "[install] WARN: target has uncommitted changes (showing up to 20 lines):"
      echo "$DIRTY" | sed 's/^/  /'
      echo "[install] WARN: rsync is about to overwrite .claude/ — review or commit/stash first."
      echo "[install] WARN: continuing in 3s (Ctrl-C to abort)..."
      sleep 3 || true
    fi
  fi
fi

# ============================================================
# migration helper: project 固有 override が SSoT yml に直接書かれている場合の案内
# (task-55: docs_approved_dir 等が SSoT yml に書かれていると --update で巻き戻る潜在事故。
#  自動移動はしない、案内のみ。違反が見つかったら user が手で local.yml へ移行する)
# (task-79: --overwrite-all は最も破壊的な mode (local override も上書き) なので、
#  SSoT drift 案内が出ない非対称を解消するため対象に含める。案内のみで自動移動はしない。)
# ============================================================
if [[ "$MODE" == "update" || "$MODE" == "force" || "$MODE" == "overwrite-all" ]] && ! $DRY_RUN; then
  TARGET_SSOT="$TARGET/.claude/harness-config.yml"
  SRC_SSOT="$SCRIPT_DIR/.claude/harness-config.yml"
  if [[ -f "$TARGET_SSOT" && -f "$SRC_SSOT" ]]; then
    # 比較対象 key (project 固有 override が起こりやすい代表例)
    for key in docs_approved_dir task_dir draft_dir protected_paths; do
      # `|| true` で fail-open: target yml に該当 key が不在で grep exit 1 → pipefail
      # で script abort する事故を防ぐ (task-42 後発見、2026-05-28、classlab-weekly-news
      # 同期失敗を契機)。key 不在は「project 固有 override なし」を意味するため、空文字で
      # 続行が正しい挙動 (該当 if 文は -n "$tgt_val" で空時 skip される)。
      tgt_val=$(grep -E "^${key}:" "$TARGET_SSOT" 2>/dev/null | head -1 | sed -E "s/^${key}:[[:space:]]*//; s/[[:space:]]*$//" || true)
      src_val=$(grep -E "^${key}:" "$SRC_SSOT" 2>/dev/null | head -1 | sed -E "s/^${key}:[[:space:]]*//; s/[[:space:]]*$//" || true)
      if [[ -n "$tgt_val" && "$tgt_val" != "$src_val" ]]; then
        echo "[install] MIGRATE: $TARGET_SSOT has project-specific '$key: $tgt_val' (SSoT default: '$src_val')."
        echo "[install] MIGRATE: --update will overwrite SSoT yml. Move this value to .claude/harness-config.local.yml to preserve it across updates."
      fi
    done
    unset key tgt_val src_val
  fi
  unset TARGET_SSOT SRC_SSOT
fi


# helper: run or echo (dry-run aware)
# H-1: array-based exec — no eval/word-split/glob re-expansion. Each arg passed
# verbatim, safe for paths containing spaces / quotes / $ / glob chars.
# dry-run prints %q-quoted form so the displayed command is copy-paste safe.
run() {
  if $DRY_RUN; then
    printf '[dry-run]'
    printf ' %q' "$@"
    echo
  else
    "$@"
  fi
}

# ============================================================
# CLAUDE.md auto-fill helpers (task-89、draft §3.1/3.2)
# ============================================================
# 3 関数で「manifest 検出 → field 抽出 → template token 置換」を担う。
# design SSoT: docs/draft/claude-md-auto-fill.md §3。placeholder `<...>` 0 化 (DoD)。
# fail-open 契約: 抽出失敗は TODO comment で埋め、render 失敗は呼び出し側 fallback で
# 旧挙動 (CLAUDE.md.template 配置) に落とす。set -e 下 die を避けるため grep/sed/node は
# すべて `|| true` ガード + 結果空判定。mktemp は X 末尾 + TMPDIR 尊重 (§6.4 先例踏襲)。

# detect_project_lang <target>
# TARGET 直下 depth 1 の manifest を優先順で検査、first-win で lang id を echo。
# LANG_OVERRIDE (--lang 明示) が空でなければ manifest 検出をスキップ。fallback は generic。
detect_project_lang() {
  local target="$1"
  if [[ -n "${LANG_OVERRIDE:-}" ]]; then
    echo "$LANG_OVERRIDE"
    return 0
  fi
  if   [[ -f "$target/package.json"    ]]; then echo "ts"
  elif [[ -f "$target/pyproject.toml"  ]]; then echo "py"
  elif [[ -f "$target/go.mod"          ]]; then echo "go"
  elif [[ -f "$target/Cargo.toml"      ]]; then echo "rust"
  elif [[ -f "$target/composer.json"   ]]; then echo "php"
  elif [[ -f "$target/Package.swift"   ]]; then echo "swift"
  else                                          echo "generic"
  fi
}

# extract_manifest_fields <lang> <target>
# 出力は関数スコープ変数 (bash local に格納後 caller が読む setter パターンでなく、
# global 変数 AF_* に代入する明示 out-param。呼び出し側は使用前に unset で洗浄する)。
#   AF_PROJECT_NAME    : `{{PROJECT_NAME}}` 置換値 (空なら basename fallback)
#   AF_RUNTIME_LINE    : `{{RUNTIME_LINE}}` 置換値 (空なら TODO comment fallback)
#   AF_FRAMEWORK_LINE  : `{{FRAMEWORK_LINE}}` 置換値 (whitelist hit 時 " (name, ...)" / 空可)
#   AF_COMMANDS_FILE   : `{{COMMANDS_BLOCK}}` 単独行 → multiline 差替に使う一時 file path
# 抽出失敗は TODO comment を埋めて continue (die しない)。node 不在 → grep-sed fallback (§6.6 先例)。
extract_manifest_fields() {
  local lang="$1"
  local target="$2"
  AF_PROJECT_NAME=""
  AF_RUNTIME_LINE=""
  AF_FRAMEWORK_LINE=""
  AF_COMMANDS_FILE=""

  # commands 一時 file (multiline sed r 用)。mktemp X 末尾必須 (BSD/macOS literal 名回避)、
  # || true で set -e 下 die 回避。取得失敗は fail-open で終了 → render 側で fallback。
  AF_COMMANDS_FILE="$(mktemp "${TMPDIR:-/tmp}/hirai-af-commands.XXXXXX" 2>/dev/null || true)"
  [[ -z "$AF_COMMANDS_FILE" ]] && return 0

  case "$lang" in
    ts)
      local pkg="$target/package.json"
      if [[ -f "$pkg" ]]; then
        # PROJECT_NAME: node → grep-sed fallback (§6.6 chain 踏襲、path は argv 経由で injection 回避)
        if command -v node >/dev/null 2>&1; then
          AF_PROJECT_NAME="$(node -e 'try{process.stdout.write(String(require(process.argv[1]).name||""))}catch(e){}' "$pkg" 2>/dev/null || true)"
        fi
        if [[ -z "$AF_PROJECT_NAME" ]]; then
          AF_PROJECT_NAME="$(grep -E '"name"[[:space:]]*:' "$pkg" 2>/dev/null | head -1 | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
        fi
        # RUNTIME: engines.node
        local node_engine=""
        if command -v node >/dev/null 2>&1; then
          node_engine="$(node -e 'try{const p=require(process.argv[1]);process.stdout.write(String((p.engines&&p.engines.node)||""))}catch(e){}' "$pkg" 2>/dev/null || true)"
        fi
        if [[ -z "$node_engine" ]]; then
          node_engine="$(grep -E '"node"[[:space:]]*:' "$pkg" 2>/dev/null | head -1 | sed -E 's/.*"node"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
        fi
        if [[ -n "$node_engine" ]]; then
          AF_RUNTIME_LINE="Node.js $node_engine"
        else
          AF_RUNTIME_LINE="<!-- TODO(auto-fill): 例 Node.js 22+ -->"
        fi
        # FRAMEWORK: whitelist (next|react|vue|express、draft §3.1)。
        # 「dependencies / devDependencies / peerDependencies の key 完全一致」に絞る:
        # jq あり → has($k) で決定論判定 / jq 不在 → `"react":` の JSON key literal
        # (word boundary `-w` は `-` を非 word 文字扱いのため react-router-dom /
        # vite-plugin-express / description 内 react-like を誤検知していた、2026-07-05
        # finding 2 対処)。jq / grep 双方 fail-open。
        local fw=""
        local f
        local hit
        for f in next react vue express; do
          hit=false
          if command -v jq >/dev/null 2>&1; then
            if jq -e --arg k "$f" \
                 '((.dependencies // {}) + (.devDependencies // {}) + (.peerDependencies // {})) | has($k)' \
                 "$pkg" >/dev/null 2>&1; then
              hit=true
            fi
          else
            # grep fallback: `"react":` の JSON key literal。閉じ引用符後 `:` 必須のため
            # `"react-router-dom":` は match しない (`react"` の直後は `-`)。
            if grep -qE "\"$f\"[[:space:]]*:" "$pkg" 2>/dev/null; then
              hit=true
            fi
          fi
          if $hit; then
            fw="${fw}${fw:+, }${f}"
          fi
        done
        if [[ -n "$fw" ]]; then
          AF_FRAMEWORK_LINE=" ($fw)"
        else
          AF_FRAMEWORK_LINE=""
        fi
        # COMMANDS: scripts.{dev,build,test,lint} 存在 key のみ `npm run <key>` 化 (draft §3.1)
        local emitted=0
        local s
        for s in dev build test lint; do
          if grep -qE "\"$s\"[[:space:]]*:" "$pkg" 2>/dev/null; then
            printf 'npm run %s\n' "$s" >> "$AF_COMMANDS_FILE" 2>/dev/null || true
            emitted=1
          fi
        done
        [[ $emitted -eq 0 ]] && printf '%s\n' "<!-- TODO(auto-fill): 例 npm run dev / build / test -->" >> "$AF_COMMANDS_FILE" 2>/dev/null || true
      fi
      ;;
    py)
      local pj="$target/pyproject.toml"
      if [[ -f "$pj" ]]; then
        # PROJECT_NAME: [project] name = "..." → [tool.poetry] name = "..."
        AF_PROJECT_NAME="$(grep -E '^[[:space:]]*name[[:space:]]*=' "$pj" 2>/dev/null | head -1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' || true)"
        # RUNTIME: requires-python
        local py_req=""
        py_req="$(grep -E '^[[:space:]]*requires-python[[:space:]]*=' "$pj" 2>/dev/null | head -1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' || true)"
        if [[ -n "$py_req" ]]; then
          AF_RUNTIME_LINE="Python $py_req"
        else
          AF_RUNTIME_LINE="<!-- TODO(auto-fill): 例 Python 3.12+ -->"
        fi
        # FRAMEWORK: whitelist (django|fastapi|flask)。dep-context に絞った pattern で
        # false positive (description / readme 文字列内の言及等) を回避 (2026-07-05 finding 2 対処):
        #   (1) toml table key: `^\s*fastapi\s*=`     (poetry / uv / setuptools `[project]`)
        #   (2) list string with version specifier:    `"fastapi>=..."` / `'fastapi==..'`
        #   (3) bare quoted name (稀、list entry):     `"fastapi"` / `'fastapi'`
        # 散文 (`"fastapi is great"`) は fastapi 直後が空白のため (1)-(3) いずれにも該当せず drop。
        # `-i` を維持し `Django` 等 capital 変種を許容 (現行挙動保存)。
        local fw=""
        local f
        for f in django fastapi flask; do
          if grep -qiE "(^[[:space:]]*$f[[:space:]]*=|[\"']$f[<>=~!\"'])" "$pj" 2>/dev/null; then
            fw="${fw}${fw:+, }${f}"
          fi
        done
        [[ -n "$fw" ]] && AF_FRAMEWORK_LINE=" ($fw)" || AF_FRAMEWORK_LINE=""
        # COMMANDS: 固定 (pytest + ruff)、draft §3.1
        printf '%s\n' "pytest" "ruff check ." >> "$AF_COMMANDS_FILE" 2>/dev/null || true
      fi
      ;;
    go)
      local gm="$target/go.mod"
      if [[ -f "$gm" ]]; then
        # PROJECT_NAME: module 行の値 (full path)。空でも sanity check で basename fallback。
        AF_PROJECT_NAME="$(grep -E '^module[[:space:]]+' "$gm" 2>/dev/null | head -1 | awk '{print $2}' || true)"
        # RUNTIME: go directive (最小 version、`go 1.22` 等)
        local go_dir=""
        go_dir="$(grep -E '^go[[:space:]]+' "$gm" 2>/dev/null | head -1 | awk '{print $2}' || true)"
        if [[ -n "$go_dir" ]]; then
          AF_RUNTIME_LINE="Go $go_dir"
        else
          AF_RUNTIME_LINE="<!-- TODO(auto-fill): 例 Go 1.22+ -->"
        fi
        AF_FRAMEWORK_LINE=""
        printf '%s\n' "go build ./..." "go test ./..." >> "$AF_COMMANDS_FILE" 2>/dev/null || true
      fi
      ;;
    rust)
      local ct="$target/Cargo.toml"
      if [[ -f "$ct" ]]; then
        # PROJECT_NAME: [package] name = "..." (workspace root は不在の場合あり、その時 basename fallback)
        AF_PROJECT_NAME="$(grep -E '^[[:space:]]*name[[:space:]]*=' "$ct" 2>/dev/null | head -1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' || true)"
        local edition=""
        edition="$(grep -E '^[[:space:]]*edition[[:space:]]*=' "$ct" 2>/dev/null | head -1 | sed -E 's/.*=[[:space:]]*"([^"]+)".*/\1/' || true)"
        if [[ -n "$edition" ]]; then
          AF_RUNTIME_LINE="edition = $edition"
        else
          AF_RUNTIME_LINE="<!-- TODO(auto-fill): 例 edition = 2021 / 2024 -->"
        fi
        AF_FRAMEWORK_LINE=""
        printf '%s\n' "cargo build" "cargo test" "cargo clippy" >> "$AF_COMMANDS_FILE" 2>/dev/null || true
      fi
      ;;
    php)
      local cj="$target/composer.json"
      if [[ -f "$cj" ]]; then
        # PROJECT_NAME: .name (node → grep-sed fallback、§6.6 pattern)
        if command -v node >/dev/null 2>&1; then
          AF_PROJECT_NAME="$(node -e 'try{process.stdout.write(String(require(process.argv[1]).name||""))}catch(e){}' "$cj" 2>/dev/null || true)"
        fi
        if [[ -z "$AF_PROJECT_NAME" ]]; then
          AF_PROJECT_NAME="$(grep -E '"name"[[:space:]]*:' "$cj" 2>/dev/null | head -1 | sed -E 's/.*"name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
        fi
        # RUNTIME: require.php ("php": "^8.2" 等)
        local php_ver=""
        php_ver="$(grep -E '"php"[[:space:]]*:' "$cj" 2>/dev/null | head -1 | sed -E 's/.*"php"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
        if [[ -n "$php_ver" ]]; then
          AF_RUNTIME_LINE="PHP $php_ver"
        else
          AF_RUNTIME_LINE="<!-- TODO(auto-fill): 例 PHP 8.2+ -->"
        fi
        AF_FRAMEWORK_LINE=""
        printf '%s\n' "composer install" "vendor/bin/phpunit" >> "$AF_COMMANDS_FILE" 2>/dev/null || true
      fi
      ;;
    swift)
      local ps="$target/Package.swift"
      if [[ -f "$ps" ]]; then
        # PROJECT_NAME: Package(name: "...") — 行頭が空白 + name: 開始のみ照合 (product/target の
        # `.executable(name: "...")` は行頭 . なので除外される)
        AF_PROJECT_NAME="$(grep -E '^[[:space:]]*name[[:space:]]*:[[:space:]]*"' "$ps" 2>/dev/null | head -1 | sed -E 's/.*name[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
        local sw_ver=""
        sw_ver="$(grep -E '^// swift-tools-version' "$ps" 2>/dev/null | head -1 | sed -E 's|.*swift-tools-version[:[:space:]]*([0-9.]+).*|\1|' || true)"
        if [[ -n "$sw_ver" ]]; then
          AF_RUNTIME_LINE="swift-tools-version $sw_ver"
        else
          AF_RUNTIME_LINE="<!-- TODO(auto-fill): 例 swift-tools-version 5.10 -->"
        fi
        AF_FRAMEWORK_LINE=""
        printf '%s\n' "swift build" "swift test" >> "$AF_COMMANDS_FILE" 2>/dev/null || true
      fi
      ;;
    generic|*)
      # 検出不能: basename + TODO で埋める (draft §3.1 row 7)
      AF_PROJECT_NAME="$(basename "$target")"
      AF_RUNTIME_LINE="<!-- TODO(auto-fill): 主要 runtime を記入 -->"
      AF_FRAMEWORK_LINE=""
      printf '%s\n' "<!-- TODO(auto-fill): 主要な dev / build / test コマンドを追記 -->" >> "$AF_COMMANDS_FILE" 2>/dev/null || true
      ;;
  esac

  # sanity: 空 / 改行含みは棄却 → basename fallback (draft §4 抽出値 sanity check)
  if [[ -z "$AF_PROJECT_NAME" || "$AF_PROJECT_NAME" == *$'\n'* ]]; then
    AF_PROJECT_NAME="$(basename "$target")"
  fi
  return 0
}

# render_claude_md <lang> <target> <template_dir> <dst>
# 成功 0 / 失敗 1 (呼び出し側で fallback = CLAUDE.md.template 配置に落とす)。
# sed 順序 (draft §3.2 SSoT): (1) {{COMMANDS_BLOCK}} 単独行 → r file + //d で multiline 差込
#                              (2) 残り 3 tokens を s|| 単純置換 (区切り | は path/version の / 衝突回避)
render_claude_md() {
  local lang="$1"
  local target="$2"
  local template_dir="$3"
  local dst="$4"
  local tmpl="$template_dir/CLAUDE.md.example.${lang}.md"

  # template 不在 → fail-open (呼び出し側 fallback)
  [[ -f "$tmpl" ]] || return 1

  extract_manifest_fields "$lang" "$target" || true
  # commands file が取得できなければ render 不能 (mktemp 失敗など、稀)
  if [[ -z "${AF_COMMANDS_FILE:-}" || ! -f "$AF_COMMANDS_FILE" ]]; then
    return 1
  fi

  local tmp_out=""
  tmp_out="$(mktemp "${TMPDIR:-/tmp}/hirai-af-out.XXXXXX" 2>/dev/null || true)"
  if [[ -z "$tmp_out" ]]; then
    rm -f "$AF_COMMANDS_FILE" 2>/dev/null || true
    return 1
  fi

  # sed 特殊文字 escape (置換右辺): \ | & を無害化。区切りは | を採用 (path / version の / 衝突回避)。
  # whitelist 抽出値の性質上、これらの文字が発生する確率は低いが defensive に処理する。
  local pn rl fl
  pn="$(printf '%s' "$AF_PROJECT_NAME"   | sed -e 's/[\\|&]/\\&/g' 2>/dev/null || printf '%s' "$AF_PROJECT_NAME")"
  rl="$(printf '%s' "$AF_RUNTIME_LINE"   | sed -e 's/[\\|&]/\\&/g' 2>/dev/null || printf '%s' "$AF_RUNTIME_LINE")"
  fl="$(printf '%s' "$AF_FRAMEWORK_LINE" | sed -e 's/[\\|&]/\\&/g' 2>/dev/null || printf '%s' "$AF_FRAMEWORK_LINE")"

  if sed -e "/^{{COMMANDS_BLOCK}}$/r $AF_COMMANDS_FILE" \
         -e "/^{{COMMANDS_BLOCK}}$/d" \
         -e "s|{{PROJECT_NAME}}|${pn}|g" \
         -e "s|{{RUNTIME_LINE}}|${rl}|g" \
         -e "s|{{FRAMEWORK_LINE}}|${fl}|g" \
         "$tmpl" > "$tmp_out" 2>/dev/null; then
    if mv "$tmp_out" "$dst" 2>/dev/null; then
      rm -f "$AF_COMMANDS_FILE" 2>/dev/null || true
      return 0
    fi
  fi
  rm -f "$tmp_out" "$AF_COMMANDS_FILE" 2>/dev/null || true
  return 1
}

# ============================================================
# rsync excludes (state / user-local)
# ============================================================
RSYNC_EXCLUDES=(
  --exclude=.gateguard-state/
  --exclude=.taskguard-state/
  --exclude=.confidence-gate-state/
  --exclude=.failure-window/
  --exclude=.agent-markers/
  --exclude=.context-budget-state/
  --exclude=.improvement-proposal-state/
  --exclude=.workflow-state/
  --exclude=settings.json
  --exclude=settings.local.json
  --exclude=settings.local.example.json
  --exclude=harness-config.local.yml
  --exclude=bash-whitelist-requests/
  --exclude=worktrees/
  --exclude=project-rules/
)

# RSYNC_EXCLUDES_MINIMAL (task-79、--overwrite-all 専用):
# 「全上書き」mode 用。machine-local な settings.local.json **のみ** を温存し、
# それ以外 (settings.json / harness-config.local.yml / state dir 群 / worktrees) は
# すべて source の状態で上書きする (drift した target を SSoT へ強制リセットする用途)。
# `--delete` は使わない (= 上書きのみ、target にしかない file は残す)。
RSYNC_EXCLUDES_MINIMAL=(
  --exclude=settings.local.json
  --exclude=project-rules/
)

# NOTE (task-82): `.claude/project-rules/<name>.md` は **project 所有** (consuming repo の
# harness rule override / 追補)。harness 7 rule (`.claude/rules/*.md`) から `@import` され、
# rsync で上書きすると project 固有編集が消失するため両 exclude set に project-rules/ を含める
# (overwrite-all でも project-rules は守る = project の override は drift リセット対象外)。
# 不在 target には下記「project-rules create-if-absent」block が空テンプレを配置する。

# NOTE (task-71 H2、2026-06-02): `settings.json` は exclude する。task-71 で settings.json は
# permissions verbatim 同梱の generated artifact (harness 本体は harness-dev preset の
# permissions + dispatcher 配線) になったため、rsync で配布すると consuming repo の repo 固有
# permissions / preset を上書きする回帰になる。dispatcher 機能本体 (wrapper 群 / manifest /
# generate-settings.sh / dispatcher-core.sh) は `.claude/` 配下なので引き続き配布される。
# consuming repo は `bash .claude/scripts/generate-settings.sh --out .claude/settings.json` で
# 自リポの permissions + 配布済 manifest から settings.json を再生成して dispatcher 配線を採用する。

# NOTE (task-51 A 案、2026-05-28): `.claude/rules-details/` (Layer B 詳細規範) は
# 意図的に exclude していない。Claude Code は `.claude/rules/` のみを startup 注入する
# (公式 doc: code.claude.com/docs/en/memory.md) ため、Layer B を別 dir に置くことで
# context bloat を回避する設計。rsync -a で `.claude/rules-details/` 配下も自動同期
# されるため 4 リポでも Layer A↔B link が保たれる。SSoT: `.claude/rules-details/README.md`。

# ============================================================
# 1. .claude/ install
# ============================================================
case "$MODE" in
  install)
    if [[ -d "$TARGET/.claude" ]]; then
      echo "[install] existing .claude detected → backup to .claude.bak.$STAMP"
      run mv "$TARGET/.claude" "$TARGET/.claude.bak.$STAMP"
    fi
    echo "[install] rsync .claude/ → $TARGET/.claude/"
    if $DRY_RUN; then
      rsync -an "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30
      echo "[dry-run] ... (truncated)"
    else
      rsync -a "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    fi
    ;;
  update)
    if [[ ! -d "$TARGET/.claude" ]]; then
      echo "[install] error: --update requires existing $TARGET/.claude. Use default mode for fresh install." >&2
      exit 64
    fi
    echo "[install] rsync (increment) .claude/ → $TARGET/.claude/  (preserving state dirs / settings.local.json)"
    if $DRY_RUN; then
      rsync -an "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30
      echo "[dry-run] ... (truncated)"
    else
      rsync -a "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    fi
    ;;
  force)
    if [[ -d "$TARGET/.claude" ]]; then
      echo "[install] WARN: --force will OVERWRITE existing .claude (no backup)"
      run rm -rf "$TARGET/.claude"
    fi
    echo "[install] rsync .claude/ → $TARGET/.claude/"
    if $DRY_RUN; then
      rsync -an "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30
    else
      rsync -a "${RSYNC_EXCLUDES[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    fi
    ;;
  overwrite-all)
    # task-79: 全上書き mode。settings.local.json のみ温存し、それ以外 (settings.json /
    # harness-config.local.yml / state dir / worktrees) も source で上書きする。
    # `--delete` は使わない → target にしかない file は残す (上書きのみ)。
    if [[ ! -d "$TARGET/.claude" ]]; then
      echo "[install] error: --overwrite-all requires existing $TARGET/.claude. Use default mode for fresh install." >&2
      exit 64
    fi
    echo "[install] WARN: --overwrite-all overwrites ALL local overrides (settings.json / harness-config.local.yml / state dirs)"
    echo "[install] WARN: only settings.local.json is preserved. No --delete (target-only files are kept)."
    echo "[install] rsync (overwrite-all) .claude/ → $TARGET/.claude/  (preserving settings.local.json only)"
    if $DRY_RUN; then
      # `| head -30` closes the pipe early; under set -euo pipefail rsync's SIGPIPE
      # (exit 141) would propagate and abort the script (CLAUDE.md HIGH lesson:
      # SIGPIPE → pipefail → errexit → silent death). `|| true` keeps dry-run preview
      # tolerant when the change set exceeds 30 lines (e.g. state dirs under overwrite-all).
      rsync -an "${RSYNC_EXCLUDES_MINIMAL[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/" | head -30 || true
      echo "[dry-run] ... (truncated)"
    else
      rsync -a "${RSYNC_EXCLUDES_MINIMAL[@]}" "$SCRIPT_DIR/.claude/" "$TARGET/.claude/"
    fi
    ;;
esac

# ============================================================
# 2. CLAUDE.md (task-89 auto-fill、既存 CLAUDE.md は default/update mode で不可侵)
# ============================================================
# 設計 SSoT: docs/draft/claude-md-auto-fill.md §3.3 mode × 既存 matrix。
# - install (default) + 既存不在 : auto-fill 生成 (`<...>` placeholder 0)
# - install (default) + 既存あり : 不可侵 (.bak 退避廃止 = subscbase-api 再発防止) + CommonRules HINT
# - update            + 既存不在 : 生成しない (現行維持) + 存在時は HINT のみ (read-only)
# - update            + 既存あり : 不可侵 + CommonRules HINT
# - force / overwrite-all       : auto-fill 生成 (backup なし、既存があれば上書き)
# - dry-run                     : 検出 echo のみ、file write 0 (run() helper と同じ dry-run 契約)
# - fail-open fallback          : template 不在 / render 失敗時は旧挙動 (CLAUDE.md.template 配置) + WARN
CLAUDE_MD_DST="$TARGET/CLAUDE.md"
TEMPLATE_DIR="$SCRIPT_DIR/.claude/templates"   # source 側 templates (rsync 順序非依存)

if [[ "$MODE" == "update" ]]; then
  # update mode は CLAUDE.md を生成/上書きしない (現行維持、draft §3.3)。
  # 既存 CLAUDE.md に @.claude/CommonRules.md 参照が不在なら HINT (自動編集は subscbase-api 再発防止で禁止)。
  echo "[install] (update mode) CLAUDE.md は触らない"
  if [[ -f "$CLAUDE_MD_DST" ]] && ! grep -q '@.claude/CommonRules.md' "$CLAUDE_MD_DST" 2>/dev/null; then
    echo "[install] HINT: $CLAUDE_MD_DST に \`@.claude/CommonRules.md\` 参照が不在 — 先頭に 1 行追加してください (共通規範 load 用)"
  fi
else
  # detect (dry-run でも echo)。--lang 明示なら override / 未指定なら detected
  DETECTED_LANG="$(detect_project_lang "$TARGET")"
  if $LANG_EXPLICIT; then
    echo "[install] CLAUDE.md auto-fill: lang=${DETECTED_LANG} (--lang override)"
  else
    echo "[install] CLAUDE.md auto-fill: lang=${DETECTED_LANG} (manifest 検出)"
  fi

  if [[ -f "$CLAUDE_MD_DST" ]]; then
    # 既存 CLAUDE.md あり
    if [[ "$MODE" == "force" || "$MODE" == "overwrite-all" ]]; then
      # --force / --overwrite-all: auto-fill で上書き (backup なし、既存挙動踏襲)
      if $DRY_RUN; then
        echo "[dry-run] generate CLAUDE.md (lang=${DETECTED_LANG}) — overwrite existing"
      else
        echo "[install] WARN: --$MODE overwriting $CLAUDE_MD_DST with auto-fill (no backup)"
        if render_claude_md "$DETECTED_LANG" "$TARGET" "$TEMPLATE_DIR" "$CLAUDE_MD_DST"; then
          echo "[install] CLAUDE.md 再生成 (auto-fill、lang=${DETECTED_LANG})"
        else
          echo "[install] WARN: auto-fill 失敗 → fallback (source CLAUDE.md → CLAUDE.md.template)" >&2
          cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md.template" 2>/dev/null || true
        fi
      fi
    else
      # default install + 既存 CLAUDE.md: 不可侵 (draft §3.3、.bak 退避廃止 = subscbase-api 再発防止)
      echo "[install] existing $CLAUDE_MD_DST 保護 (default mode は不可侵、.bak 退避廃止)"
      if ! grep -q '@.claude/CommonRules.md' "$CLAUDE_MD_DST" 2>/dev/null; then
        echo "[install] HINT: $CLAUDE_MD_DST に \`@.claude/CommonRules.md\` 参照が不在 — 先頭に 1 行追加してください (共通規範 load 用)"
      fi
    fi
  else
    # 既存 CLAUDE.md 不在: default / force / overwrite-all いずれも auto-fill 生成
    if $DRY_RUN; then
      echo "[dry-run] generate CLAUDE.md (lang=${DETECTED_LANG})"
    else
      if render_claude_md "$DETECTED_LANG" "$TARGET" "$TEMPLATE_DIR" "$CLAUDE_MD_DST"; then
        echo "[install] CLAUDE.md 生成 (auto-fill、lang=${DETECTED_LANG})"
      else
        echo "[install] WARN: auto-fill 失敗 → fallback (source CLAUDE.md → CLAUDE.md.template)" >&2
        cp "$SCRIPT_DIR/CLAUDE.md" "$TARGET/CLAUDE.md.template" 2>/dev/null || true
      fi
    fi
  fi
  unset DETECTED_LANG
fi
unset CLAUDE_MD_DST TEMPLATE_DIR

# ============================================================
# 3. .mcp.json (Serena MCP は /save-state /pm-start に必須、task-90 --mcp-servers filter 対応)
# ============================================================
# 設計 SSoT: docs/draft/mcp-json-minimal-default.md §3 Step 2。
# 挙動 matrix (WITH_MCP=true 時):
#   既存 .mcp.json あり     : keep-as-is 維持 (merge しない、冪等)。--mcp-servers 指定時は NOTE。
#   不在 + MCP_SERVERS=all  : source verbatim copy (従来動作 = 後方互換、jq 不要)。
#   不在 + subset + jq あり : jq filter で server 単位 select 生成。source に無い token は exit 64
#                             (typo fail-fast)。生成後 jq . で valid JSON validate + if-wrapper mv。
#                             filter 生成失敗は WARN + 全配布 fallback (fail-open)。
#   不在 + subset + jq 不在 : WARN + 全配布 fallback (機能優先、従来同等 regression 0)。
#   dry-run                 : file write 0 (echo のみ)。生成 branch も dry-run 分岐で run() 契約踏襲。
# fail-open 契約 (§6.3/6.4 先例踏襲): jq / mktemp / filter 失敗はすべて WARN + 全配布 fallback に落ちる。
# && list 終端 mv は set -euo pipefail 下で fail-open 契約を破って die するため if-wrapper 形を採用する
# (install.sh:1001 先例)。
if $WITH_MCP; then
  if [[ -f "$TARGET/.mcp.json" ]]; then
    echo "[install] existing .mcp.json detected → keep as-is (manual merge if you need harness defaults)"
    if $MCP_SERVERS_SET; then
      echo "[install] NOTE: --mcp-servers=$MCP_SERVERS は既存 .mcp.json には適用しない (manual merge が必要)"
    fi
  elif [[ "$MCP_SERVERS" == "all" ]]; then
    # 従来動作 (--mcp-servers=all は明示的後方互換オプション)
    echo "[install] copying .mcp.json → $TARGET/.mcp.json  (--mcp-servers=all: 全 server 配布)"
    run cp "$SCRIPT_DIR/.mcp.json" "$TARGET/.mcp.json"
  elif command -v jq >/dev/null 2>&1; then
    SOURCE_MCP="$SCRIPT_DIR/.mcp.json"
    # key 実在検証 (Step 1 item 5 が Step 2 で担当と明記した部分、draft §3 D5): source .mcp.json の
    # mcpServers keys と MCP_SERVERS の set-diff を jq で 1 回で計算。source に無い token が
    # 1 つでもあれば typo として exit 64 で fail-fast (jq 存在時のみ、jq 不在時は下記 else fallback)。
    # `|| true` は source .mcp.json が壊れているケースで空文字を返し、その場合は下の空判定で
    # 全配布 fallback へ落ちる (fail-open)。
    _mcp_missing="$(jq -r --arg csv "$MCP_SERVERS" '
      ($csv | split(",")) - (.mcpServers | keys) | .[]
    ' "$SOURCE_MCP" 2>/dev/null || true)"
    _mcp_source_keys="$(jq -r '.mcpServers | keys | join(",")' "$SOURCE_MCP" 2>/dev/null || true)"
    if [[ -z "$_mcp_source_keys" ]]; then
      # source .mcp.json が壊れている / jq が枝を舐められない → 全配布 fallback (fail-open)
      echo "[install] WARN: source .mcp.json の keys 取得失敗 → 全 server 配布 fallback" >&2
      run cp "$SOURCE_MCP" "$TARGET/.mcp.json"
    elif [[ -n "$_mcp_missing" ]]; then
      _mcp_first_missing="$(printf '%s\n' "$_mcp_missing" | head -1)"
      echo "[install] error: --mcp-servers token '$_mcp_first_missing' は source .mcp.json に存在しません (available: $_mcp_source_keys)" >&2
      exit 64
    elif $DRY_RUN; then
      # jq filter は stdout redirect を伴うため run() helper 非対応 → 明示 dry-run 分岐
      echo "[dry-run] generate .mcp.json (servers: $MCP_SERVERS) → $TARGET/.mcp.json"
    else
      # mktemp X 末尾 + TMPDIR 尊重 + || true (§6.4 先例踏襲、BSD/macOS literal 名 + set -e die 回避)
      TMP_MCP="$(mktemp "${TMPDIR:-/tmp}/hirai-mcp.XXXXXX" 2>/dev/null || true)"
      if [[ -z "$TMP_MCP" ]]; then
        echo "[install] WARN: mktemp 失敗 → 全 server 配布 fallback (fail-open、install 継続)" >&2
        run cp "$SOURCE_MCP" "$TARGET/.mcp.json"
      else
        # jq filter: source 全体を舐めて mcpServers を選択 keys のみで再構築。
        # index() は「配列に含まれるか」の判定 (null/数値のいずれかを返す) で、select は truthy のみ通す。
        jq --arg csv "$MCP_SERVERS" \
          '{mcpServers: (.mcpServers | with_entries(select(.key as $k | ($csv | split(",")) | index($k))))}' \
          "$SOURCE_MCP" > "$TMP_MCP" 2>/dev/null || true
        # if-wrapper 判定 (§6.4 先例): -s (非空) + jq . (valid JSON) + mv (原子的差替)。
        # いずれか fail で全配布 fallback (fail-open、install 継続)。
        if [[ -s "$TMP_MCP" ]] && jq . "$TMP_MCP" >/dev/null 2>&1 && mv "$TMP_MCP" "$TARGET/.mcp.json" 2>/dev/null; then
          echo "[install] .mcp.json 生成 (servers: $MCP_SERVERS)"
        else
          echo "[install] WARN: .mcp.json filter 生成失敗 → 全 server 配布 fallback (fail-open、install 継続)" >&2
          rm -f "$TMP_MCP" 2>/dev/null || true
          run cp "$SOURCE_MCP" "$TARGET/.mcp.json"
        fi
      fi
      unset TMP_MCP
    fi
    unset SOURCE_MCP _mcp_missing _mcp_source_keys _mcp_first_missing
  else
    # jq 不在: skip すると serena 不在で /save-state 系が壊れ機能 regression になるため、
    # 全配布 + WARN で機能優先 fallback (draft §3 D4)。従来同等動作 = regression 0、
    # noise (env placeholder 残存) は従来並みで新規発生ではない。
    echo "[install] WARN: jq 不在のため --mcp-servers 選択 skip → 全 server 配布 (従来動作)。手動選択は jq install 後に再実行してください" >&2
    run cp "$SCRIPT_DIR/.mcp.json" "$TARGET/.mcp.json"
  fi
else
  echo "[install] (--no-mcp) skip .mcp.json"
fi

# ============================================================
# 4. .gitignore (既存があれば merge、無ければ新規)
# ============================================================
if [[ -f "$TARGET/.gitignore" ]]; then
  # 既存に harness state 除外行が無ければ追記
  if grep -q '.claude/.gateguard-state' "$TARGET/.gitignore" 2>/dev/null; then
    echo "[install] $TARGET/.gitignore already contains harness state ignores → skip"
  else
    echo "[install] appending harness state ignores to existing $TARGET/.gitignore"
    if $DRY_RUN; then
      echo "[dry-run] cat >> $TARGET/.gitignore  (harness state block)"
    else
      cat >> "$TARGET/.gitignore" <<'GITIGNORE_HARNESS'

# === HIRAI Method harness state (auto-appended by install.sh) ===
.claude/.gateguard-state/
.claude/.taskguard-state/
.claude/.confidence-gate-state/
.claude/.failure-window/
.claude/.confidence-bypass.cleared
.claude/.confidence-bypass.log
.claude/.agent-markers/
.claude/.context-budget-state/
.claude/.improvement-proposal-state/
.claude/.workflow-state/
.claude/settings.local.json
.claude/settings.generated.preview.json
.claude/worktrees/
.claude/bash-whitelist-requests/
GITIGNORE_HARNESS
    fi
  fi
else
  echo "[install] copying .gitignore → $TARGET/.gitignore"
  run cp "$SCRIPT_DIR/.gitignore" "$TARGET/.gitignore"
fi

# ============================================================
# 5. docs/tasks/ docs/draft/ (templates から初期化、既存は保護)
# ============================================================
if $WITH_DOCS; then
  run mkdir -p "$TARGET/docs/tasks" "$TARGET/docs/draft"
  for f in list.md parking-lot.md _TASK_TEMPLATE.md; do
    src="$SCRIPT_DIR/.claude/templates/docs/tasks/$f"
    dst="$TARGET/docs/tasks/$f"
    if [[ -f "$dst" ]]; then
      echo "[install] $dst exists → skip"
    elif [[ -f "$src" ]]; then
      echo "[install] copy template $f → docs/tasks/"
      run cp "$src" "$dst"
    fi
  done
  src="$SCRIPT_DIR/.claude/templates/docs/draft/_DRAFT_TEMPLATE.md"
  dst="$TARGET/docs/draft/_DRAFT_TEMPLATE.md"
  if [[ -f "$dst" ]]; then
    echo "[install] $dst exists → skip"
  elif [[ -f "$src" ]]; then
    echo "[install] copy template _DRAFT_TEMPLATE.md → docs/draft/"
    run cp "$src" "$dst"
  fi
else
  echo "[install] (--no-docs) skip docs/tasks/ docs/draft/ templates"
fi

# ============================================================
# 5.5. project-rules/ create-if-absent (task-82、全 mode 共通、project 所有保護)
# ============================================================
# `.claude/project-rules/<name>.md` は consuming repo の harness rule override / 追補を書く
# **project 所有** file。harness 7 rule (`.claude/rules/*.md`) から `@import` され、harness
# rule の後に結合 load される。RSYNC_EXCLUDES / RSYNC_EXCLUDES_MINIMAL の `--exclude=project-rules/`
# により rsync では一切 touch しない (= 既存 project 編集を上書きしない、保護)。
# ここで「なければ空テンプレを配置・あれば skip」する冪等 cp で初回雛形を提供する
# (docs/tasks templates と同じ create-if-absent ロジック)。全 mode (install/update/force/
# overwrite-all) で適用 — project-rules は project 所有のため force/overwrite-all でも上書きしない。
PROJECT_RULES_SRC="$SCRIPT_DIR/.claude/project-rules"
PROJECT_RULES_DST="$TARGET/.claude/project-rules"
if [[ -d "$PROJECT_RULES_SRC" ]]; then
  run mkdir -p "$PROJECT_RULES_DST"
  for src in "$PROJECT_RULES_SRC"/*.md; do
    [[ -e "$src" ]] || continue   # nullglob 非依存 (no-match で literal glob を skip)
    base="$(basename "$src")"
    dst="$PROJECT_RULES_DST/$base"
    if [[ -f "$dst" ]]; then
      echo "[install] project-rules/$base exists → skip (project-owned, protected)"
    else
      echo "[install] copy project-rules template $base → .claude/project-rules/"
      run cp "$src" "$dst"
    fi
  done
  unset src base dst
fi
unset PROJECT_RULES_SRC PROJECT_RULES_DST

# ============================================================
# 6. hook 実行権限 (rsync -a で保持されるが、念のため)
# ============================================================
# L-4: chmod runs in ALL modes (install / update / force). The previous
# `if [[ "$MODE" != "update" ]] || true` was always true (dead condition); we want
# exec bits restored even on --update since rsync can drop them via staging, so the
# guard is removed and chmod is unconditional.
if $DRY_RUN; then
  echo "[dry-run] chmod +x .claude/hooks/*.sh .claude/scripts/*.{sh,py,mjs}"
else
  find "$TARGET/.claude/hooks" -maxdepth 2 -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true
  find "$TARGET/.claude/scripts" -type f \( -name '*.sh' -o -name '*.py' -o -name '*.mjs' \) -exec chmod +x {} + 2>/dev/null || true
fi

# ============================================================
# 6.3. settings.json 自動再生成 (statusLine / dispatcher 配線同期、task-80、task-92 §3.5 install seed 吸収)
# ============================================================
# task-71 H2 で settings.json は rsync exclude (repo 固有 permissions 保護) になったため、
# statusLine / dispatcher 配線が consuming repo に同期されない問題があった (user 報告)。
# sync mode (update / force / overwrite-all) で rsync 後に generate-settings.sh を自動実行し、
# 既存 settings.json の permissions を verbatim 保持したまま statusLine / dispatcher を再配線する。
# fail-open: jq 不在 / generate-settings.sh 不在 / 既存 settings.json 不在 / 再生成失敗は
# WARN or NOTE + skip で install 自体は継続する (permissions 喪失 / die を回避)。
# CLAUDE.md HIGH 教訓: 再生成は subshell ( cd ...; bash ... ) で実行し caller の shell flags
# (set -e 等) に影響させない。
# L-1 保険: subshell に HC_PROJECT_ROOT="$TARGET" を明示注入する。generate-settings.sh の
# resolve_project_root は HC_PROJECT_ROOT を最優先 key とするため、TARGET が git 未 init かつ
# 環境に CLAUDE_PROJECT_DIR が残っている場合でも ROOT が TARGET に固定される (取り違え防止)。
# 挙動不変: 通常 path も ROOT=TARGET のまま (cd "$TARGET" 後の git/pwd も TARGET を指す)。
# mode 別の permissions 帰結 (M-1、task-92 §3.5 で install mode 分岐追加):
#   install       : (task-92) 既存 settings.json 不在時に source から seed cp → generate-settings.sh
#                   再配線 (副産物 #78 sub-item 1、task-71 H2 permissions 保護と両立)。既存あれば触らない。
#   update       : 既存 settings.json の permissions を verbatim 保持して再配線。
#   force         : rm -rf .claude で破壊的リセット + settings.json は rsync exclude のため
#                   再生成時には既存不在 → fail-open skip (permissions 保持の前提は成立しない)。
#   overwrite-all : settings.json も source で上書き済のため、ここで保持される permissions は
#                   source 由来 (consuming repo の permissions は失われる = task-79 既定)。
if ! $DRY_RUN; then
  # task-92 §3.5 structural change: install mode (default) + 既存 settings.json 不在 → source seed cp。
  # source `.claude/settings.json` は rsync exclude (§L601) で target に届かないため cp 経由必須。
  # task-71 H2 との consistency: install mode は repo 固有 permissions が「無い」開始状態のため
  # source verbatim で seed → 続く generate-settings.sh 再配線は fail-open (jq 不在等は skip)。
  if [[ "$MODE" == "install" && ! -f "$TARGET/.claude/settings.json" ]]; then
    if [[ -f "$SCRIPT_DIR/.claude/settings.json" ]]; then
      if cp "$SCRIPT_DIR/.claude/settings.json" "$TARGET/.claude/settings.json" 2>/dev/null; then
        echo "[install] seeded settings.json from source (install mode、task-92 §3.5)"
      else
        echo "[install] WARN: settings.json seed 失敗 (install 継続、fail-open)" >&2
      fi
    fi
  fi
  # sync mode + install mode で seed 成功 (= settings.json 実在) の両方で generate-settings.sh を実行。
  # install mode + seed 失敗 (settings.json 不在) は下 elif [[ ! -f "$LIVE_SETTINGS" ]] で NOTE + skip。
  if [[ "$MODE" == "update" || "$MODE" == "force" || "$MODE" == "overwrite-all" || \
        ( "$MODE" == "install" && -f "$TARGET/.claude/settings.json" ) ]]; then
    GEN_SETTINGS="$TARGET/.claude/scripts/generate-settings.sh"
    LIVE_SETTINGS="$TARGET/.claude/settings.json"
    if ! command -v jq >/dev/null 2>&1; then
      echo "[install] WARN: jq 不在のため settings.json 自動再生成 skip。手動: bash .claude/scripts/generate-settings.sh --out .claude/settings.json" >&2
    elif [[ ! -f "$GEN_SETTINGS" ]]; then
      echo "[install] WARN: generate-settings.sh 不在、settings.json 自動再生成 skip" >&2
    elif [[ ! -f "$LIVE_SETTINGS" ]]; then
      echo "[install] NOTE: 既存 settings.json 不在のため自動再生成 skip (permissions 喪失回避)。新規は手動生成要" >&2
    else
      if ( cd "$TARGET" && HC_PROJECT_ROOT="$TARGET" bash .claude/scripts/generate-settings.sh --out .claude/settings.json ); then
        echo "[install] settings.json 再生成済 (statusLine / dispatcher 配線同期、permissions 保持)"
      else
        echo "[install] WARN: settings.json 自動再生成 失敗 (install は継続)。手動再生成を検討" >&2
      fi
    fi
    unset GEN_SETTINGS LIVE_SETTINGS
  fi
fi

# ============================================================
# 6.4. consuming repo preset bootstrap (HOTFIX-1 + task-85 --preset parameterize)
# ============================================================
# 設計根拠: docs/draft/install-immediately-usable-redesign-20260618.md §9.1 HOTFIX-1 / §4.1 対策 B
#           + docs/draft/install-preset-auto-switch.md §3 Step 1 (--preset opt-in、task-85)。
# SSoT harness-config.yml は default_preset: harness-dev を verbatim copy するため、
# consuming repo では主要 guard が全 disabled になる (subscbase-api 2026-06-18 実機事案)。
# default_preset 変更は feature_*_enabled / review_required_* に波及しない (R7) ため、
# local.yml への individual toggle 明示書込が必須。team-default が enforcement_matrix で
# 期待する 8 guard (feature 4 + review_required 4) を全て true 化しないと、
# enforcement-mismatch-smoke Case 3 が preset=team-default 下で UNDOCUMENTED mismatch
# を検出し FAIL する (matrix に team-default の disabled_reason は無い)。
# ここで harness-config.local.yml を
# create-if-absent 生成する (既存は verbatim 保持 = 冪等。本 file は RSYNC_EXCLUDES
# に含まれるため update/force の rsync でも消えない)。
# self-install (TARGET と SCRIPT_DIR の物理 path 一致、symlink 経由で L128 の
# 文字列比較をすり抜けた場合含む) は harness 自身の dogfood (harness-dev preset)
# を壊すため skip。fail-open: 生成失敗は WARN のみで install 継続 (die しない)。
# task-85: 生成内容は --preset=<name> で parameterize (team-default/strict → 8 toggle true、
# advisory/harness-dev → 8 toggle 明示 false = R7 対称性 + SSoT 将来値変更への pin)。
# default は team-default (HOTFIX-1 後方互換、install-local-yml-smoke Case A/B が regression 検証)。

# preset → guard toggle 値 mapping (task-85 Step 1)。
# enforcement_matrix の presets 行 ({advisory: false, team-default: true,
# strict: true, harness-dev: false}、8 guard 一様) と一致させる。乖離は
# install-local-yml-smoke case I/J (target で enforcement-mismatch-smoke 実走) が機械検出。
_preset_toggle_value() {
  case "$1" in
    team-default|strict)  echo "true"  ;;
    advisory|harness-dev) echo "false" ;;
  esac
}

if $DRY_RUN; then
  echo "[dry-run] would generate local.yml (preset: $PRESET)"
else
  LOCAL_YML="$TARGET/.claude/harness-config.local.yml"
  TARGET_PHYS="$(cd "$TARGET" 2>/dev/null && pwd -P || echo "$TARGET")"
  SOURCE_PHYS="$(cd "$SCRIPT_DIR" 2>/dev/null && pwd -P || echo "$SCRIPT_DIR")"
  if [[ "$TARGET_PHYS" == "$SOURCE_PHYS" ]]; then
    echo "[install] NOTE: self-install 検出 (target == harness repo 物理 path) → preset bootstrap skip (harness-dev dogfood 維持)" >&2
    if $PRESET_EXPLICIT; then
      echo "[install] NOTE: --preset=$PRESET は無視 (self-install は harness-dev dogfood 維持)" >&2
    fi
  elif [[ ! -d "$TARGET/.claude" ]]; then
    echo "[install] WARN: $TARGET/.claude 不在のため preset bootstrap skip" >&2
  elif [[ -f "$LOCAL_YML" ]]; then
    echo "[install] NOTE: harness-config.local.yml 既存 → 生成 skip (project 所有、verbatim 保持)"
    if $PRESET_EXPLICIT; then
      echo "[install] WARN: --preset=$PRESET は無視 (既存 local.yml 保持。変更は \$EDITOR .claude/harness-config.local.yml)" >&2
    fi
  else
    # mktemp の X 群は末尾必須 (BSD/macOS は非末尾 X を randomize せず literal 名を
    # 生成し、stale file 残存で以降 rc=1 になる)。set -e 下の非ガード代入は fail-open
    # 契約を破って die するため || true + 空判定で WARN + skip に落とす。TMPDIR 尊重。
    PRESET_TOGGLE="$(_preset_toggle_value "$PRESET")"
    TMP_LOCAL="$(mktemp "${TMPDIR:-/tmp}/harness-config-local.XXXXXX" 2>/dev/null || true)"
    # set -e 下でも heredoc / printf 書込失敗で die しないよう || true、成否は -s + grep で判定。
    # comment header は quoted heredoc 維持 (変数展開なし)、default_preset 行 + 8 toggle 行は
    # printf で追記 (quoted → unquoted heredoc 化による展開事故を回避、task-85 Step 1b)。
    if [[ -n "$TMP_LOCAL" ]]; then
      cat > "$TMP_LOCAL" 2>/dev/null <<'LOCAL_YML_EOF' || true
# === harness-config.local.yml (install.sh 自動生成、HOTFIX-1 + task-85 --preset) ===
# 本 file は project 所有: install.sh --update で上書きされない (rsync exclude)。
# 設計根拠: docs/draft/install-immediately-usable-redesign-20260618.md §9.1 / §4.1 対策 B
#           + docs/draft/install-preset-auto-switch.md (--preset parameterize)。
# SSoT harness-config.yml の default_preset: harness-dev は consuming repo では
# 主要 guard 全 disabled になるため、install 時指定 preset (--preset=<name>、
# default: team-default) へ上書きする。
# 注意 (R7): default_preset 変更は feature_*_enabled / review_required_* に波及
# しないため、下記 8 toggle (feature 4 + review_required 4) の individual 明示が
# 必須 (default_preset 行だけ残して toggle 行を消すと guard は無効のまま)。
# toggle 値は enforcement_matrix の presets 期待値 ({advisory: false,
# team-default: true, strict: true, harness-dev: false}) と一致させて生成する。
# 乖離すると enforcement-mismatch-smoke Case 3 が UNDOCUMENTED mismatch で FAIL する。
# preset / toggle を変えたい場合は本 file を編集する (SSoT harness-config.yml は
# 触らない — --update で SSoT 値が上書きされる)。
# advisory は個人実験 / PoC 用 (主要 guard warn 化)。通常運用は team-default を推奨。
LOCAL_YML_EOF
      printf '%s\n' \
        "default_preset: ${PRESET}" \
        "feature_task_rule_guard_enabled: ${PRESET_TOGGLE}" \
        "feature_draft_flow_guard_enabled: ${PRESET_TOGGLE}" \
        "feature_workflow_enforcement_enabled: ${PRESET_TOGGLE}" \
        "feature_gateguard_enabled: ${PRESET_TOGGLE}" \
        "review_required_design: ${PRESET_TOGGLE}" \
        "review_required_test: ${PRESET_TOGGLE}" \
        "review_required_module: ${PRESET_TOGGLE}" \
        "review_required_system: ${PRESET_TOGGLE}" \
        >> "$TMP_LOCAL" 2>/dev/null || true
    fi
    if [[ -s "$TMP_LOCAL" ]] && grep -q '^default_preset:' "$TMP_LOCAL" 2>/dev/null \
       && mv "$TMP_LOCAL" "$LOCAL_YML" 2>/dev/null; then
      echo "[install] harness-config.local.yml 生成 (default_preset: ${PRESET} + guard toggle 8 件 ${PRESET_TOGGLE})"
    else
      echo "[install] WARN: harness-config.local.yml 生成失敗 (install は継続)。手動作成を検討" >&2
      rm -f "$TMP_LOCAL" 2>/dev/null || true
    fi
  fi
  unset LOCAL_YML TARGET_PHYS SOURCE_PHYS TMP_LOCAL PRESET_TOGGLE
fi

# ============================================================
# 6.5. harness_version stamp 書込 (task-56 F)
# ============================================================
# stale-harness-detect.sh (SessionStart hook) が読む同期 stamp。
# `bash install.sh --update <repo>` 実行日 (UTC) を YYYY-MM-DD で
# target の harness-config.yml に書き込む (in-place、portable sed -i 互換)。
# 既存 `harness_version:` 行があれば差し替え、無ければ追記。
# fail-open: stamp 書込失敗は WARN のみで install 自体は継続。
if ! $DRY_RUN; then
  TARGET_HC="$TARGET/.claude/harness-config.yml"
  if [[ -f "$TARGET_HC" ]]; then
    NEW_STAMP="$(date -u +%Y-%m-%d)"
    if grep -qE '^harness_version:' "$TARGET_HC" 2>/dev/null; then
      # 既存 line を置換 (BSD sed / GNU sed 両対応: -i '' / -i バックアップ拡張子なし)
      # X 末尾 + || true ガード (§6.4 と同理由: BSD/macOS literal 名 + set -e die 回避)
      TMP_HC="$(mktemp "${TMPDIR:-/tmp}/harness-config.XXXXXX" 2>/dev/null || true)"
      sed -E "s|^harness_version:.*|harness_version: \"${NEW_STAMP}\"|" "$TARGET_HC" > "$TMP_HC" 2>/dev/null \
        && mv "$TMP_HC" "$TARGET_HC" \
        && echo "[install] harness_version stamp updated -> $NEW_STAMP" \
        || echo "[install] WARN: failed to update harness_version stamp (install continues)" >&2
      rm -f "$TMP_HC" 2>/dev/null || true
    else
      # 未設定なら top に append (insert at top of file)
      {
        echo "# === Harness Version Stamp (task-56 F, install.sh が書込) ==="
        echo "harness_version: \"${NEW_STAMP}\""
        echo ""
        cat "$TARGET_HC"
      } > "${TARGET_HC}.tmp" 2>/dev/null \
        && mv "${TARGET_HC}.tmp" "$TARGET_HC" \
        && echo "[install] harness_version stamp inserted -> $NEW_STAMP" \
        || echo "[install] WARN: failed to insert harness_version stamp (install continues)" >&2
    fi
    unset NEW_STAMP TMP_HC
  fi
  unset TARGET_HC
fi

# ============================================================
# 6.6. harness_npm_version stamp 書込 (task-84 Step 1)
# ============================================================
# stale-harness-detect.sh (SessionStart hook) が npm registry latest と
# semver 比較するための同期 stamp。install.sh 自身の package.json の
# `.version` (semver x.y.z) を target の harness-config.yml に書き込む。
# 既存 `harness_npm_version:` 行があれば差し替え、無ければ追記。
# 既存 date stamp (harness_version) とは独立に併存する。
# fail-safe: package.json 不在 / version 取得不能なら stamp を skip
#            (既存挙動を壊さない)。stamp 書込失敗は WARN のみで install 継続。
if ! $DRY_RUN; then
  TARGET_HC_NPM="$TARGET/.claude/harness-config.yml"
  SRC_PKG="$SCRIPT_DIR/package.json"
  NPM_VER=""
  if [[ -f "$SRC_PKG" ]]; then
    if command -v node >/dev/null 2>&1; then
      # L-2 (task-84 fix): path を JS 文字列へ直接埋め込まず argv 経由で渡す
      # (path injection 回避)。$SRC_PKG にメタ文字が含まれても安全。
      NPM_VER="$(node -e 'try{process.stdout.write(String(require(process.argv[1]).version||""))}catch(e){}' "$SRC_PKG" 2>/dev/null || true)"
    fi
    # node 不在 / 取得失敗時の fallback: grep/sed で "version": "x.y.z" を抽出
    if [[ -z "$NPM_VER" || "$NPM_VER" == "undefined" ]]; then
      NPM_VER="$(grep -E '"version"[[:space:]]*:' "$SRC_PKG" 2>/dev/null \
        | head -1 | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
    fi
  fi
  if [[ -f "$TARGET_HC_NPM" && -n "$NPM_VER" && "$NPM_VER" != "undefined" ]]; then
    if grep -qE '^harness_npm_version:' "$TARGET_HC_NPM" 2>/dev/null; then
      # X 末尾 + || true ガード (§6.4 と同理由: BSD/macOS literal 名 + set -e die 回避)
      TMP_HC_NPM="$(mktemp "${TMPDIR:-/tmp}/harness-config-npm.XXXXXX" 2>/dev/null || true)"
      sed -E "s|^harness_npm_version:.*|harness_npm_version: \"${NPM_VER}\"|" "$TARGET_HC_NPM" > "$TMP_HC_NPM" 2>/dev/null \
        && mv "$TMP_HC_NPM" "$TARGET_HC_NPM" \
        && echo "[install] harness_npm_version stamp updated -> $NPM_VER" \
        || echo "[install] WARN: failed to update harness_npm_version stamp (install continues)" >&2
      rm -f "$TMP_HC_NPM" 2>/dev/null || true
    else
      {
        echo "# === Harness NPM Version Stamp (task-84, install.sh が書込) ==="
        echo "harness_npm_version: \"${NPM_VER}\""
        echo ""
        cat "$TARGET_HC_NPM"
      } > "${TARGET_HC_NPM}.tmp" 2>/dev/null \
        && mv "${TARGET_HC_NPM}.tmp" "$TARGET_HC_NPM" \
        && echo "[install] harness_npm_version stamp inserted -> $NPM_VER" \
        || echo "[install] WARN: failed to insert harness_npm_version stamp (install continues)" >&2
    fi
  elif [[ -f "$TARGET_HC_NPM" ]]; then
    echo "[install] NOTE: package.json version 取得不能のため harness_npm_version stamp skip (fail-safe)" >&2
  fi
  unset TARGET_HC_NPM SRC_PKG NPM_VER TMP_HC_NPM
fi

# ============================================================
# 6.7. sync drift 案内 + --commit による分離 commit (task-58 G1)
# ============================================================
# install.sh --update が SSoT を同期した直後、target 側 .claude/ 配下の
# git diff を検出して user に「分離 commit せよ」案内 + 変更 file 一覧を出力。
# --commit flag 併用時のみ harness-sync 対象 path のみ git add + 単独 commit。
# project file (root README.md 等) は完全に触らない。git reset 禁止 (HIGH 教訓)。
# 設計: docs/draft/harness-sync-uncommitted-drift.md (採用案 C ハイブリッド)
if [[ "$MODE" == "update" ]] && ! $DRY_RUN; then
  if command -v git >/dev/null 2>&1 && [[ -d "$TARGET/.git" ]]; then
    # .claude/ 配下の変更 path を git status --porcelain で安全に列挙
    # (rename 検出は対象外、付属 path のみ抽出)
    SYNC_CHANGES=$(cd "$TARGET" && git status --porcelain -- .claude/ 2>/dev/null | awk '{
      # XY status (2 char) + space + path. rename は " -> " で arrow 後ろを採用
      sub(/^.. /, "")
      if (match($0, / -> /)) {
        print substr($0, RSTART + 4)
      } else {
        print
      }
    }')
    if [[ -n "$SYNC_CHANGES" ]]; then
      SYNC_COUNT=$(printf '%s\n' "$SYNC_CHANGES" | wc -l | tr -d ' ')
      echo ""
      echo "[install] === harness sync drift detected ==="
      echo "[install] ${SYNC_COUNT} file(s) under .claude/ changed by this --update:"
      printf '%s\n' "$SYNC_CHANGES" | sed 's/^/  - /'
      echo ""
      if $COMMIT_AFTER_SYNC; then
        # 安全な git add (specific paths only、CLAUDE.md HIGH 教訓: git reset 禁止)
        # path に space を含む場合に備えて while-read + git add 個別
        echo "[install] --commit: staging ${SYNC_COUNT} synced file(s) (project files untouched)"
        ADDED=0
        while IFS= read -r p; do
          [[ -z "$p" ]] && continue
          if (cd "$TARGET" && git add -- "$p" 2>/dev/null); then
            ADDED=$((ADDED + 1))
          else
            echo "[install] WARN: git add skipped: $p" >&2
          fi
        done <<<"$SYNC_CHANGES"
        if [[ "$ADDED" -gt 0 ]]; then
          # commit 対象が staging にあるか最終確認 (空 commit 防止)
          if (cd "$TARGET" && git diff --cached --quiet); then
            echo "[install] WARN: nothing staged after git add — skip commit" >&2
          else
            COMMIT_MSG="chore(harness): sync .claude/ from hirai-method $(date -u +%Y-%m-%d)"
            if (cd "$TARGET" && git commit -q -m "$COMMIT_MSG"); then
              COMMIT_SHA=$(cd "$TARGET" && git rev-parse --short HEAD)
              echo "[install] committed harness sync: ${COMMIT_SHA} (${ADDED} file(s))"
            else
              echo "[install] WARN: git commit failed (manual commit needed)" >&2
            fi
          fi
        else
          echo "[install] WARN: no files staged — skip commit" >&2
        fi
        unset ADDED COMMIT_MSG COMMIT_SHA
      else
        # default 案内 (honor system、user に分離 commit を促す)
        echo "[install] HINT: commit these as a SEPARATE commit, e.g.:"
        echo "  cd $TARGET"
        echo "  git add .claude/"
        echo "  git commit -m 'chore(harness): sync .claude/ from hirai-method'"
        echo "[install] HINT: or rerun with '--commit' to auto-commit harness sync only:"
        echo "  bash install.sh $TARGET --update --commit"
        echo "[install] NOTE: keeping harness-sync separate from project work helps revert / blame."
      fi
      unset SYNC_COUNT
    fi
    unset SYNC_CHANGES
  else
    if $COMMIT_AFTER_SYNC; then
      echo "[install] WARN: --commit requested but target is not a git repo — skip commit"
      echo "[install] HINT: initialize git first: cd $TARGET && git init"
    fi
  fi
fi

# ============================================================
# 6.8. .githooks/pre-commit 配布 + core.hooksPath idempotent 設定 (task-92 P2-1/I3)
# ============================================================
# 設計 SSoT: docs/draft/install-pre-commit-distribute.md §3.1 冪等性契約 7 件。
# consuming repo は install 直後の状態で commit 境界の quality gate (fast smoke curated set、
# 実測 < 3s) が有効化される。
#
# 冪等性契約 (draft §3.1):
#   1. 既存 <target>/.githooks/pre-commit → 上書きしない (project owns、WARN)
#   2. .githooks/ dir 内の他 hook (pre-push 等) → 触らない
#   3. core.hooksPath == .githooks → no-op + INFO
#   4. core.hooksPath == 別 path (例: .husky) → 上書きしない + WARN + hint
#   5. 非 git repo (.git 不在) → 配布のみ実施、git config skip + NOTE
#   6. --no-hooks → 配布 + git config を全 skip、既存も触らない
#   7. --dry-run → run() helper で file write / git config 実行を echo のみ
#
# 全 mode (install / update / force / overwrite-all) 共通で発火する
# (§6.7 sync drift のような --update 限定ではない、install 直後の commit 境界 gate 有効化のため)。
if $WITH_HOOKS; then
  PRE_COMMIT_SRC="$SCRIPT_DIR/.claude/templates/githooks/pre-commit"
  PRE_COMMIT_DST="$TARGET/.githooks/pre-commit"
  if [[ ! -f "$PRE_COMMIT_SRC" ]]; then
    echo "[install] NOTE: $PRE_COMMIT_SRC 不在 → pre-commit 配布 skip (未整備 harness)" >&2
  else
    # 1. .githooks/ dir 作成 (冪等、dry-run 契約は run() helper 経由)
    run mkdir -p "$TARGET/.githooks"
    # 2. pre-commit 配布 (契約 1: 既存は上書きしない、契約 2: 他 hook 非関与)
    if [[ -f "$PRE_COMMIT_DST" ]]; then
      echo "[install] $PRE_COMMIT_DST exists → skip (project-owned)"
    else
      echo "[install] copy pre-commit → $PRE_COMMIT_DST"
      if $DRY_RUN; then
        echo "[dry-run] cp $PRE_COMMIT_SRC $PRE_COMMIT_DST"
        echo "[dry-run] chmod 755 $PRE_COMMIT_DST"
      else
        # cp + chmod 755 を fail-open で連鎖 (§6.4 先例)、失敗は WARN のみで install 継続
        if cp "$PRE_COMMIT_SRC" "$PRE_COMMIT_DST" 2>/dev/null \
           && chmod 755 "$PRE_COMMIT_DST" 2>/dev/null; then
          echo "[install] pre-commit 配置 (mode 755、fast smoke gate)"
        else
          echo "[install] WARN: pre-commit 配布失敗 (install は継続、fail-open)" >&2
        fi
      fi
    fi
    # 3. core.hooksPath idempotent 設定 (契約 3/4/5)
    if [[ -d "$TARGET/.git" ]]; then
      # git config は sub-shell で target repo 内から実行 (submodule / worktree 混在時にも安全)。
      # `--get` が exit 1 (未設定) を返しても `|| true` で継続 (fail-open)。
      CURRENT_HOOKS_PATH="$(cd "$TARGET" && git config --get core.hooksPath 2>/dev/null || true)"
      if [[ -z "$CURRENT_HOOKS_PATH" ]]; then
        # 未設定 → 新規設定 (契約 5 の逆: git repo あり + hooksPath 未設定は自動 set OK)
        if $DRY_RUN; then
          echo "[dry-run] cd $TARGET && git config core.hooksPath .githooks"
        else
          if ( cd "$TARGET" && git config core.hooksPath .githooks 2>/dev/null ); then
            echo "[install] core.hooksPath = .githooks 設定"
          else
            echo "[install] WARN: git config core.hooksPath 設定失敗 (install は継続)" >&2
          fi
        fi
      elif [[ "$CURRENT_HOOKS_PATH" == ".githooks" ]]; then
        # 契約 3: 既に .githooks 設定済 → no-op + INFO
        echo "[install] INFO: core.hooksPath は既に .githooks (no-op)"
      else
        # 契約 4: 別 path (例: .husky) に設定済 → 上書きしない + WARN + hint
        echo "[install] WARN: core.hooksPath = '$CURRENT_HOOKS_PATH' に設定済 → 上書きしない" >&2
        echo "[install] HINT: 本 harness の pre-commit を使うには手動で: cd $TARGET && git config core.hooksPath .githooks"
      fi
      unset CURRENT_HOOKS_PATH
    else
      # 契約 5: 非 git repo → 配布のみ、git config skip + NOTE
      echo "[install] NOTE: $TARGET は git repo でない → git config skip"
      echo "[install] HINT: git init 後に手動で: cd $TARGET && git config core.hooksPath .githooks"
    fi
  fi
  unset PRE_COMMIT_SRC PRE_COMMIT_DST
else
  echo "[install] (--no-hooks) skip pre-commit 配布 + core.hooksPath 設定"
fi

# ============================================================
# 7. 検証 (config-loader 動作確認)
# ============================================================
if ! $DRY_RUN; then
  echo ""
  echo "[install] verifying config-loader.sh..."
  if ( cd "$TARGET" && bash -c 'source .claude/hooks/lib/config-loader.sh && [[ -n "$HC_PROTECTED_PATHS" ]] && [[ -n "$HC_TASK_DIR" ]]' ); then
    echo "[install] config-loader OK (HC_PROTECTED_PATHS / HC_TASK_DIR loaded)"
  else
    echo "[install] WARN: config-loader.sh did not export expected vars. Check $TARGET/.claude/harness-config.yml" >&2
  fi
fi

# ============================================================
# 7.5. self-doctor 検証 (install 直後の setup issue 0 化検証、task-87 Step 2)
# ============================================================
# §6.3-6.6 の全成果物生成 + §7 config-loader 検証の直後に、self-doctor.sh で
# D1-D8 の期待外 (WARN) / 期待値内 (INFO) を切り分けて報告する (draft §3.4)。
#
# fail-open 2 層 (draft §3.3):
#   - self-doctor.sh 単体: WARN ≥ 1 → exit 1 (smoke / CI から検出可能)
#   - install.sh 側: `|| true` で吸収し install は常に exit 0 (報告のみ)
#
# skip 条件:
#   - --no-doctor 明示指定 (WITH_DOCTOR=false)
#   - --dry-run (§6.3-6.6 の mutation 前は検証対象未生成のため無意味)
#   - script 不在 (旧 harness / 部分配布 target。silent NOTE + install 継続)
if $WITH_DOCTOR && ! $DRY_RUN; then
  if [[ -f "$TARGET/.claude/scripts/self-doctor.sh" ]]; then
    echo ""
    ( cd "$TARGET" && HC_PROJECT_ROOT="$TARGET" bash .claude/scripts/self-doctor.sh ) || true
  else
    echo "[install] NOTE: self-doctor.sh 不在、skip (task-87 未配布 target)" >&2
  fi
fi

# ============================================================
# 8. summary
# ============================================================
cat <<EOF

[install] DONE ($MODE mode).

Counts at target:
  agents:   $(find "$TARGET/.claude/agents" -maxdepth 2 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  skills:   $(find "$TARGET/.claude/skills" -maxdepth 2 -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  commands: $(find "$TARGET/.claude/commands" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  hooks:    $(find "$TARGET/.claude/hooks" -maxdepth 1 -name '*.sh' 2>/dev/null | wc -l | tr -d ' ')
  rules:    $(find "$TARGET/.claude/rules" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')

Next steps:
  1. cd $TARGET
  2. project 固有 override (docs_approved_dir / protected_paths 追加分 等) は
     \$EDITOR .claude/harness-config.local.yml     # ←ココに書く (install.sh --update で温存される)
     (SSoT .claude/harness-config.yml は触らない — --update で SSoT 値が上書きされる)
     (preset: ${PRESET} で local.yml 自動生成済 (不在時のみ、guard toggle 8 件 = feature 4 + review_required 4 を同時書込)。
      他 preset は install 時 --preset=<name> (advisory|team-default|strict|harness-dev)、
      生成後の変更は本 file を編集 → bash .claude/scripts/hc-config.sh --summary で effective 状態確認。
      advisory は PoC 用 = 主要 guard warn 化。通常運用は team-default を推奨)
  3. \$EDITOR .claude/bash-whitelist.txt           # 使う CLI (pnpm/poetry/cargo/...) を追記
  4. \$EDITOR CLAUDE.md   # <!-- TODO(auto-fill) --> comment を補完 (task-89 auto-fill 済、\`<...>\` placeholder 0)
  5. (recommended) git init                                  # observe.sh の project hash 検出を有効化
  6. Claude Code session 起動 → /init-tasks → /mode loop
  7. (option) bash .claude/scripts/self-doctor.sh    # 健全性 check (task-87)。issue があれば why/fix/silence 3 行を確認、install 直後は WARN 0 が正常
  8. pre-commit fast smoke (< 3s、bash .claude/scripts/hc-config.sh --set feature_pre_commit_smoke_enabled=false で opt-out、task-92 §6.8 で .githooks/pre-commit 配置済)

settings.json について (task-71 H2 / task-80):
  - settings.json 本体は rsync exclude (repo 固有 permissions / preset を守る)。
  - sync mode (--update / --force / --overwrite-all) では rsync 後に
    generate-settings.sh で settings.json を **自動再生成済** (statusLine / dispatcher 配線同期、
    permissions は verbatim 保持)。手動実行は不要 (失敗時のみ下記を手動実行):
      bash .claude/scripts/generate-settings.sh --out .claude/settings.json
  - mode 別の permissions 帰結 (意味が異なる):
      --update       : 既存 settings.json の permissions を verbatim 保持して再配線。
      --force         : .claude を破壊的リセット + settings.json は exclude のため再生成時は
                        既存不在 → fail-open skip (permissions 保持の前提は成立しない)。
      --overwrite-all : settings.json も source で上書き済のため、保持される permissions は
                        **source 由来** (consuming repo の permissions は失われる = task-79 既定)。
  - 自動再生成 skip 条件: jq 不在 / generate-settings.sh 不在 / 既存 settings.json 不在
    (いずれも WARN/NOTE + install 継続)。新規 install (default mode) は settings.json を
    配布しないため対象外。
  - 注意: 手編集した独自トップレベル key / 独自 hook は manifest 由来に置換され脱落する。
    独自 hook は dispatcher-manifest.tsv に登録すること (再生成で配線が保たれる)。

--overwrite-all について (task-79):
  - drift した target を SSoT へ強制リセットする全上書き mode。
  - settings.local.json **のみ** 温存し、それ以外 (settings.json / harness-config.local.yml /
    state dir 群 / worktrees) も source で上書きする = target の local override は失われる。
  - settings.json も上書きされるため、consuming repo は実行後
      bash .claude/scripts/generate-settings.sh --out .claude/settings.json
    で repo 固有 permissions から再生成すること (task-71 dispatcher 配線復元)。
  - --delete は使わないため target にしかない file は残る (上書きのみ)。
  - 用途は drift リセット専用。日常の harness 取込は --update を使うこと (local 設定を温存)。

MCP servers について (task-90):
  - --mcp-servers=<csv> で .mcp.json 配布 server を選択可能 (default: serena,context7 =
    env placeholder 0 の minimal 2 server、--mcp-servers=all で従来全 7 server 配布)。
    選択可能 server: serena, context7, github, salesforce, agent-browser, asana-pat, slack。
    --no-mcp との併用は exit 64。
  - 配布 logic (§3、fresh install 時のみ、既存 .mcp.json は常に keep-as-is):
      subset (default 含む) : jq filter で server 単位 select 生成。source に無い token は exit 64。
      all                  : source verbatim copy (従来動作)。
      jq 不在時             : WARN + 全 server 配布 fallback (機能優先、従来同等 regression 0)。
      filter 生成失敗時     : WARN + 全 server 配布 fallback (fail-open、install 継続)。
      dry-run              : echo のみ、file write 0 (--dry-run 契約)。
  - opt-in server 追加時の env 要件 (subset 選択時に手動 export 必須):
      github       : GITHUB_PAT
      salesforce   : SALESFORCE_CONNECTION_TYPE / USERNAME / PASSWORD / TOKEN / INSTANCE_URL
      asana-pat    : ASANA_PAT
      slack        : SLACK_MCP_XOXP_TOKEN / SLACK_MCP_ADD_MESSAGE_TOOL
      (serena / context7 / agent-browser は env 不要)

project-rules/ について (task-82):
  - .claude/project-rules/<name>.md は **project 所有** (update 免除)。harness 7 rule
    (.claude/rules/*.md) から @import され、harness rule の後に結合 load される。
  - harness rule の override / 追補はここに書く (7 harness rule 本体は触らない)。
    update/force/overwrite-all いずれの mode でも rsync exclude + create-if-absent で保護
    (なければ空テンプレ配置・あれば skip、既存編集は上書きされない)。

Override precedence (高 → 低):
  env(HC_*) > .claude/harness-config.local.yml > .claude/harness-config.yml (SSoT) > hardcoded default

Documentation:
  - README.md         (採用 5 ステップ)
  - docs/INVENTORY.md (全構成要素の Path 表)
  - docs/PORTABILITY.md (他リポへの移植仕様)
  - docs/SELF_IMPROVEMENT.md (F1-F3 + L1-L5)
EOF
