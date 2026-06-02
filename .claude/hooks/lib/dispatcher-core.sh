#!/usr/bin/env bash
# dispatcher-core.sh — task-71 Step 4-6 (sourced lib)
#
# 役割:
#   event ごとの薄い wrapper (<event>-dispatcher.sh) から source され、
#   run_dispatch <event> <matcher> で manifest 駆動の子 hook 実行を担う。
#   現 settings.json の「event×matcher ごと複数 hook 独立起動」を
#   「1 dispatcher process が manifest を読み順に子を呼ぶ」に畳む。
#
# 設計 SSoT: /tmp/task71-dispatcher-architecture.md + /tmp/task71-merge-test-matrix.md (確定スキーマ)。
#
# bash flags の方針 (重要、feedback_set_e_in_sourced_libs 規範):
#   本 file は sourced lib のため file-top で `set -euo pipefail` を **使用しない**
#   (caller の shell options 汚染 / SIGPIPE→141 サイレント死 を防ぐ)。
#   実処理は run_dispatch() の関数本体 subshell `( ... )` 内でのみ strict mode を有効化する。
#
# 不変条件 (Step 4-6 spec §3 の 1-8、絶対遵守):
#   1. stdin replay     : payload を 1 度読み、各子に printf '%s' "$payload" | child で全文を渡す
#   2. order + first-block-wins : manifest order 昇順、最初に block した子で即 exit (残り未実行)
#   3. exit code 不変   : exit2 channel は子 rc(>=2) を伝播、stdout-block は exit 0 + decision JSON
#   4. stderr 保持      : exit2 blocker の人間向け理由 stderr を飲み込まない
#   5. feature gate     : disabled feature の子は continue (子 process を spawn しない)
#   6. observer fail-open : observe.sh 等は失敗しても dispatcher を止めない、原則無出力
#   7. hook_command 引数 : "delegation-guard.sh Edit" → bash <root>/.claude/hooks/delegation-guard.sh Edit
#   8. ../skills/... path : ".claude/hooks/" 相対 = <root>/.claude/skills/... を root から解決
#
# ── task-71 Fix-C: 公式スキーマ準拠の優先度付き event 別マージ (本 file の核心) ──
#
# 公式 複数 hook 統合優先順 (code.claude.com/docs/en/hooks、conf 0.96):
#   1. exit 2          (どれか 1 件) → 全体 block、他 output 全破棄、stderr→user (最優先)
#   2. continue:false  (どれか 1 件) → 全セッション停止 (+ stopReason)
#   3. decision/permissionDecision (event 別) → block/deny を最高 severity で採用 (+ reason)
#   4. additionalContext / systemMessage → 全 hook 分を連結
#   5. suppressOutput → どれか true なら true (OR)
#
# decision フィールドの event 別有効性 (M-INV-3 / M-INV-7):
#   - decision:"block" 有効: UserPromptSubmit / PostToolUse / Stop / SubagentStop
#   - PreToolUse: decision 無効 → hookSpecificOutput.permissionDecision (deny>ask>allow/defer)
#   - SessionStart: decision 無効 (観測のみ)
#   - block 検知: dispatcher は decision:"block" と permissionDecision:"deny" の両方を block 扱い
#     (旧 grep は decision:block のみ = deny の穴。stdout-block channel の早期 exit も両対応)
#
# plain text stdout の扱い (event 不問、behavior-preserving):
#   plain text を出す子 (system-reminder 等) は全 event で verbatim 連結して出力する。
#   plain のみなら verbatim 連結を stdout へ、JSON 混在時は systemMessage / additionalContext へ
#   畳む (混在で {..} + plain を出すと M-INV-1 を破るため正規化)。畳む先は event 別 (denylist):
#     - additionalContext 対応 event (= 非対応 denylist 以外の全 event:
#       PreToolUse / PostToolUse / PostToolBatch / UserPromptSubmit / SessionStart 等)
#       → hookSpecificOutput.additionalContext
#     - additionalContext 非対応 event (Stop / SubagentStop / Notification の 3 つのみ)
#       → systemMessage (top-level、全 event 対応)。hookSpecificOutput.additionalContext は
#         これら 3 event では invalid のため絶対に出さない (task-71 1eace29 回帰 fix)。
#   注意: PreToolUse / SessionStart は additionalContext 対応 (本番 task-rule-guard 等が依存)。
#   iter1 allowlist 案 ({UserPromptSubmit/PostToolUse/PostToolBatch} のみ対応) は両者を誤って
#   非対応に分類し本番 PreToolUse hook の additionalContext を systemMessage に化けさせたため反転。
#   旧 Fix-C の「不可視 event で plain drop」案は既存契約 (core / success-stdout smoke が
#   全 event で plain passthrough を前提) と衝突するため採用しない。契約維持のため verbatim を
#   保ち、JSON 混在時のみ event 別 route で正規化する。
#
# 最終 stdout 不変 (M-INV-1): 常に「空 / 単一 valid JSON / plain text のみ」。
#   生 JSON object 連結 (`{...}{...}`) を絶対に出さない。
#
# fail-safe: jq 失敗時も block 情報を絶対落とさない (exit2 は早期 exit 済、stdout-block の
#   block は jq に到達する前に early-exit。万一 merge が空を返したら block を持つ object を
#   単独出力、無ければ先頭の単一 object へ縮退、それも不能なら no-op 空)。
#
# bash 3.2 互換 (macOS)。jq 依存 (runtime、fail-safe 付き)。

# run_dispatch <event> <matcher>
#   event   : "PreToolUse" / "PostToolUse" / "Notification" / "Stop" /
#             "SubagentStop" / "SessionStart" / "UserPromptSubmit" (literal、wrapper が固定渡し)
#   matcher : tool matcher ("Edit|Write" / "*" 等)。matcher 無し event は空文字。
#
# stdin から tool payload JSON を 1 度読み、manifest の該当 row を順に処理する。
# 戻り値: 子が block したら exit code を伝播。非 block なら event 別 priority merge した
#         単一出力を stdout に出し exit 0。
run_dispatch() (
  set -uo pipefail

  _dc_event="${1:-}"
  _dc_matcher="${2:-}"

  # --- 1. root 解決 + lib source ---
  _dc_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  # project-root.sh / config-loader.sh は同 lib dir に在る
  # shellcheck source=project-root.sh
  . "$_dc_self_dir/project-root.sh"
  _dc_root="$(resolve_project_root)"
  # config-loader.sh は is_feature_enabled / HC_* を提供 (fail-open 設計)
  # shellcheck source=config-loader.sh
  . "$_dc_self_dir/config-loader.sh"

  _dc_manifest="$_dc_root/.claude/hooks/dispatcher-manifest.tsv"
  if [ ! -f "$_dc_manifest" ]; then
    # manifest 不在 = 何も配線されていない。fail-open で no-op exit 0。
    printf '[dispatcher-core] WARN: manifest not found: %s\n' "$_dc_manifest" >&2
    exit 0
  fi

  # --- 2. stdin (tool payload JSON) を 1 度だけ読む → 全子に replay ---
  # cat は EOF まで読む。payload 不在 (interactive 等) でも空文字で続行。
  _dc_payload="$(cat)"

  # --- 3. manifest から該当 row を order 昇順で抽出 ---
  # event 一致 かつ (matcher 空 OR matcher==row.matcher) で filter。
  # TSV を bash で split すると IFS=tab の連続 tab collapse で空 field がずれるため、
  # field 抽出は awk に一任する (連続 tab / 空 field を保持)。order でソート。
  # 出力行 format (区切りは制御文字 \034 = FS、word split 事故回避):
  #   order \034 hook_command \034 feature_key \034 channel
  _dc_rows="$(
    awk -F'\t' -v ev="$_dc_event" -v mt="$_dc_matcher" '
      NR == 1 { next }                       # header skip
      NF < 6  { next }                       # 不正行 skip
      $1 == "" { next }
      $1 != ev { next }                      # event 不一致 skip
      (mt == "" || $2 == mt) {               # matcher 空 = event 全体 / 一致のみ
        # order(\3) hook_command(\4) feature_key(\5) channel(\6)
        printf "%s\034%s\034%s\034%s\n", $3, $4, $5, $6
      }
    ' "$_dc_manifest" | sort -t "$(printf '\034')" -k1,1n
  )"

  # 該当 row 無し → no-op exit 0
  if [ -z "$_dc_rows" ]; then
    exit 0
  fi

  # --- 4. 各子を order 順に処理 ---
  # task-71 Fix-C: 非 block 集約は no-op を除外し、意味ある出力のみを蓄積する。
  #   _dc_jsonbuf : JSON object のみを \034 区切りで貯める buffer (merge path 用、manifest order)
  #   _dc_textbuf : 非 JSON (plain text) を \034 区切りで貯める buffer (可視 event の連結用)
  #   _dc_json_count / _dc_text_count : それぞれの件数
  _dc_jsonbuf=""
  _dc_textbuf=""
  _dc_json_count=0
  _dc_text_count=0
  _dc_GS="$(printf '\034')"
  _dc_errtmp="$(mktemp "${TMPDIR:-/tmp}/dispatcher-core.XXXXXX")" || _dc_errtmp=""

  # 意味ある出力 1 件を集約に取り込む helper。
  #   $1 = 子の raw stdout。trim して空 / "{}" は no-op として drop (集約しない)。
  #   JSON object は _dc_jsonbuf、非 JSON は _dc_textbuf へ分離して貯める。
  _dc_accumulate() {
    _acc_raw="$1"
    _acc_trim="$(printf '%s' "$_acc_raw" | tr -d '[:space:]')"
    # no-op (空 / 空白のみ / "{}") は集約しない (DoD「成功時 stdout 空」)
    if [ -z "$_acc_trim" ] || [ "$_acc_trim" = "{}" ]; then
      return 0
    fi
    if printf '%s' "$_acc_raw" | jq -e 'type == "object"' >/dev/null 2>&1; then
      if [ -z "$_dc_jsonbuf" ]; then
        _dc_jsonbuf="$_acc_raw"
      else
        _dc_jsonbuf="${_dc_jsonbuf}${_dc_GS}${_acc_raw}"
      fi
      _dc_json_count=$((_dc_json_count + 1))
    else
      if [ -z "$_dc_textbuf" ]; then
        _dc_textbuf="$_acc_raw"
      else
        _dc_textbuf="${_dc_textbuf}${_dc_GS}${_acc_raw}"
      fi
      _dc_text_count=$((_dc_text_count + 1))
    fi
  }

  # 子 hook 実行 helper: payload を replay し out を stdout、rc を返す。err は $_dc_errtmp へ。
  _dc_run_child() {
    # $1 = full hook path、$2 = (optional) hook arg
    if [ -n "$_dc_errtmp" ]; then
      if [ -n "${2:-}" ]; then
        printf '%s' "$_dc_payload" | bash "$1" "$2" 2>"$_dc_errtmp"
      else
        printf '%s' "$_dc_payload" | bash "$1" 2>"$_dc_errtmp"
      fi
    else
      if [ -n "${2:-}" ]; then
        printf '%s' "$_dc_payload" | bash "$1" "$2"
      else
        printf '%s' "$_dc_payload" | bash "$1"
      fi
    fi
  }

  # stdout-block channel の block 検知 (M-INV-7: decision:"block" と permissionDecision:"deny" 両方)。
  #   grep ベースで軽量に判定 (jq に頼らず fail-safe)。どちらか hit で block。
  _dc_is_block_stdout() {
    if printf '%s' "$1" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"'; then
      return 0
    fi
    if printf '%s' "$1" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
      return 0
    fi
    return 1
  }

  # IFS を \034 に固定して row を field 分解 (空 field 保持、word split 事故回避)
  _dc_FS="$(printf '\034')"
  while IFS="$_dc_FS" read -r _dc_order _dc_cmd _dc_feature _dc_channel; do
    [ -z "$_dc_cmd" ] && continue

    # --- 不変条件 5: feature gate (子 process を spawn する前に判定) ---
    if [ -n "$_dc_feature" ] && ! is_feature_enabled "$_dc_feature"; then
      continue
    fi

    # --- 不変条件 7,8: hook_command を path + arg(最大1) に分解、root から解決 ---
    # "delegation-guard.sh Edit" → script="delegation-guard.sh" arg="Edit"
    # "../skills/.../observe.sh"  → script=relative path、arg なし
    _dc_script="${_dc_cmd%% *}"             # 最初の space 前 = script (引数込み path も対応)
    if [ "$_dc_cmd" = "$_dc_script" ]; then
      _dc_arg=""
    else
      _dc_arg="${_dc_cmd#* }"               # 最初の space 後 = arg (引数は 1 個前提)
    fi
    _dc_hook_path="$_dc_root/.claude/hooks/$_dc_script"

    if [ ! -f "$_dc_hook_path" ]; then
      # 子 hook 不在は fail-open (observer 同様 dispatcher を止めない)
      printf '[dispatcher-core] WARN: hook not found: %s\n' "$_dc_hook_path" >&2
      continue
    fi

    # --- 子実行 (stdin replay、不変条件 1) ---
    _dc_out="$(_dc_run_child "$_dc_hook_path" "$_dc_arg")"
    _dc_rc=$?
    if [ -n "$_dc_errtmp" ] && [ -s "$_dc_errtmp" ]; then
      _dc_err="$(cat "$_dc_errtmp")"
    else
      _dc_err=""
    fi

    case "$_dc_channel" in
      exit2)
        # 不変条件 3: 子 rc >= 2 で即 block 伝播 (exit code 不変 + 不変条件 4 stderr 保持)
        if [ "$_dc_rc" -ge 2 ]; then
          [ -n "$_dc_out" ] && printf '%s' "$_dc_out"
          [ -n "$_dc_err" ] && printf '%s' "$_dc_err" >&2
          [ -n "$_dc_errtmp" ] && rm -f "$_dc_errtmp"
          exit "$_dc_rc"
        fi
        # block でなければ stderr のみ流す (出力は通常無し)
        [ -n "$_dc_err" ] && printf '%s' "$_dc_err" >&2
        ;;
      stdout-block)
        # 不変条件 2,3 + M-INV-7: decision:"block" / permissionDecision:"deny" を検出したら
        #   exit 0 + JSON 転送 + 後続未実行 (first-block-wins)。
        if _dc_is_block_stdout "$_dc_out"; then
          printf '%s' "$_dc_out"
          [ -n "$_dc_err" ] && printf '%s' "$_dc_err" >&2
          [ -n "$_dc_errtmp" ] && rm -f "$_dc_errtmp"
          exit 0
        fi
        # 非 block: no-op ({} / 空) は drop、意味ある出力のみ集約 (task-71 Fix-C)
        _dc_accumulate "$_dc_out"
        [ -n "$_dc_err" ] && printf '%s' "$_dc_err" >&2
        ;;
      advisory)
        # block しない。意味ある出力のみ集約、stderr は流す。
        _dc_accumulate "$_dc_out"
        [ -n "$_dc_err" ] && printf '%s' "$_dc_err" >&2
        ;;
      bootstrap)
        # SessionStart context 出力を保持 (意味ある出力のみ集約)。stderr も流す。
        _dc_accumulate "$_dc_out"
        [ -n "$_dc_err" ] && printf '%s' "$_dc_err" >&2
        ;;
      observer)
        # 不変条件 6: fail-open。stdout / stderr とも原則無視 (telemetry、observe.sh は無出力)。
        : # 何もしない (rc も無視)
        ;;
      *)
        # 未知 channel は安全側 (advisory 相当) で集約、止めない。
        _dc_accumulate "$_dc_out"
        [ -n "$_dc_err" ] && printf '%s' "$_dc_err" >&2
        ;;
    esac
  done <<EOF
$_dc_rows
EOF

  [ -n "$_dc_errtmp" ] && rm -f "$_dc_errtmp"

  # --- 5. 非 block 時の event 別 priority merge (task-71 Fix-C) ---
  # exit2 / stdout-block の block は上で early-exit 済。ここに来る出力は非 block のみ。
  # JSON 群 (_dc_jsonbuf) と plain text 群 (_dc_textbuf) を event 別方針で単一出力へ畳む。
  #
  # 方針 (確定スキーマ §event 別 merge):
  #   - JSON が無ければ plain 連結をそのまま stdout へ (event 不問、behavior-preserving)。
  #   - JSON があれば JSON merge を優先し、plain (additionalContext 候補) は event 別に畳む
  #     (混在で {..}{..} を出さない = M-INV-1)。判定は denylist (非対応 3 event のみ列挙):
  #       - additionalContext 対応 event (denylist 以外の全 event:
  #         PreToolUse / PostToolUse / PostToolBatch / UserPromptSubmit / SessionStart 等)
  #         → hookSpecificOutput.additionalContext へ畳む。
  #       - additionalContext 非対応 event (Stop / SubagentStop / Notification の 3 つのみ)
  #         → systemMessage へ route (top-level、全 event 対応)。これら 3 event で
  #           hookSpecificOutput.additionalContext を出すと invalid (task-71 1eace29 回帰) のため
  #           絶対に出さない。decision:block / permissionDecision は従来どおり保持。
  #
  # merge する制御フィールド (公式優先順、M-INV-2..6):
  #   continue:false (最優先) > decision:"block" / permissionDecision severity (deny>ask>allow/defer)
  #   > additionalContext / systemMessage 連結 > suppressOutput OR。

  _dc_no_json=0
  [ "$_dc_json_count" -eq 0 ] && _dc_no_json=1
  _dc_no_text=0
  [ "$_dc_text_count" -eq 0 ] && _dc_no_text=1

  # (a) 何も無い → 無出力 (DoD「成功時 stdout 空」)
  if [ "$_dc_no_json" -eq 1 ] && [ "$_dc_no_text" -eq 1 ]; then
    exit 0
  fi

  # (b) JSON 無し・plain のみ → plain を verbatim 連結して出力 (event 不問)。
  #   plain text の連結は単一 text value であり M-INV-1 (生 JSON 連結禁止) を破らない。
  #   既存契約 (core Case1/4/5/5b/7、success-stdout T5/T6/T7) は全 event で plain verbatim
  #   passthrough を前提とするため、event 可視性での drop は行わない (behavior-preserving)。
  #   蓄積は GS 区切りなので GS のみ除去して verbatim 連結 (区切り文字を挟まない、core Case1
  #   '<ctx-a><ctx-b>' と一致させる)。
  if [ "$_dc_no_json" -eq 1 ]; then
    printf '%s' "$_dc_textbuf" | tr -d "$_dc_GS"
    exit 0
  fi

  # (c) JSON あり (+ 任意 plain) → jq で event 別 priority merge して単一 object を emit。
  #   JSON が 1 件以上ある時点で出力は単一 JSON object へ正規化されるため、plain はそのまま
  #   出すと {..} + plain で M-INV-1 を破る。よって plain は event 別に additionalContext / systemMessage へ畳む (l.365-410 の denylist 参照: Stop/SubagentStop/Notification は additionalContext 非対応のため systemMessage、他 event は hookSpecificOutput.additionalContext)。
  _dc_merge_text=""
  if [ "$_dc_no_text" -eq 0 ]; then
    _dc_merge_text="$(printf '%s' "$_dc_textbuf" | tr -d "$_dc_GS")"
  fi

  _dc_merged="$(
    printf '%s' "$_dc_jsonbuf" \
      | tr "$_dc_GS" '\n' \
      | jq -s \
          --arg ev "$_dc_event" \
          --arg extratext "$_dc_merge_text" '
        # 入力: 各子 JSON object の配列。event 別 priority で単一 object に畳む。
        . as $objs

        # --- continue:false (最優先): どれか 1 件でも false なら最終 false (+ 最初の stopReason) ---
        | ([ $objs[] | select(.continue == false) ] | length > 0) as $halt
        | ([ $objs[] | select(.continue == false) | .stopReason // empty ][0]) as $stopReason

        # --- decision severity (UserPromptSubmit / PostToolUse / Stop / SubagentStop で有効) ---
        #   block > (approve/その他)。block の reason を保持。
        | ([ $objs[] | select(.decision == "block") ] | length > 0) as $decBlock
        | ([ $objs[] | select(.decision == "block") | .reason // empty
              | select(. != "") ] | join("\n")) as $decReason

        # --- permissionDecision severity (PreToolUse): deny > ask > allow/defer ---
        | [ $objs[] | .hookSpecificOutput.permissionDecision // empty
            | select(. != "") ] as $pds
        | (if   ($pds | index("deny"))  then "deny"
           elif ($pds | index("ask"))   then "ask"
           elif ($pds | index("allow")) then "allow"
           elif ($pds | index("defer")) then "defer"
           else null end) as $pd
        | ([ $objs[]
              | select((.hookSpecificOutput.permissionDecision // "") != "")
              | .hookSpecificOutput.permissionDecisionReason // empty
              | select(. != "") ] | join("\n")) as $pdReason

        # --- additionalContext 非対応 event 判定 (denylist、公式 snapshot 準拠) ---
        #   hookSpecificOutput.additionalContext を出せない event は {Stop, SubagentStop, Notification}
        #   のみ。他全 event (PreToolUse / PostToolUse / PostToolBatch / UserPromptSubmit /
        #   SessionStart 等) は additionalContext 対応 (本番 task-rule-guard.sh:191/211/231/256 /
        #   autonomous-action-guard.sh:239 / parallel-subagent-reminder.sh:347 の PreToolUse advisory
        #   additionalContext / SessionStart bootstrap context が依存。公式 snapshot
        #   claude-code-07-hooks/v3/snapshot.html L67/76 = PreToolUse、L139/147 = SessionStart 例)。
        #   非対応 event の場合のみ additionalContext 候補を systemMessage (全 event 対応の top-level)
        #   へ route する。allowlist 案 (iter1) は PreToolUse / SessionStart を誤って非対応に分類し
        #   本番 PreToolUse hook の additionalContext を systemMessage に化けさせる回帰を生むため不採用。
        # NOTE: 非対応 event 集合は claude-code-07-hooks/v3 snapshot 準拠。将来 Claude Code が Stop に additionalContext 対応した場合は本 denylist 見直し要。
        | (($ev == "Stop") or ($ev == "SubagentStop") or ($ev == "Notification")) as $acUnsupported

        # --- additionalContext 候補 全連結 (manifest order)。extratext (plain advisory) も末尾連結 ---
        | ([ $objs[]
              | (.hookSpecificOutput.additionalContext // .additionalContext // empty)
              | select(. != null and . != "") ]
            + (if ($extratext | length) > 0 then [$extratext] else [] end)) as $ctxs

        # --- systemMessage 全連結。additionalContext 非対応 event では ctx 群も systemMessage へ合流 ---
        | (([ $objs[] | .systemMessage // empty | select(. != "") ])
            + (if ($acUnsupported and ($ctxs | length) > 0) then $ctxs else [] end)
            | join("\n")) as $sysmsgs

        # --- suppressOutput OR ---
        | ([ $objs[] | select(.suppressOutput == true) ] | length > 0) as $suppress

        # --- 単一 object を組み立て ---
        | {}
          | (if $halt then (.continue = false
              | (if ($stopReason // "") != "" then .stopReason = $stopReason else . end))
             else . end)
          # additionalContext 対応 event ($acUnsupported == false) のみ
          # hookSpecificOutput.additionalContext に載せる。非対応 event (Stop/SubagentStop/
          # Notification) は上で $sysmsgs に合流済 (= systemMessage へ route)、ここでは出さない。
          | (if (($acUnsupported | not) and ($ctxs | length) > 0) then
               .hookSpecificOutput = { hookEventName: $ev,
                                       additionalContext: ($ctxs | join("\n")) }
             else . end)
          # permissionDecision (PreToolUse) を hookSpecificOutput に載せる
          | (if $pd != null then
               .hookSpecificOutput = ((.hookSpecificOutput // { hookEventName: $ev })
                 + { permissionDecision: $pd }
                 + (if ($pdReason // "") != "" then { permissionDecisionReason: $pdReason } else {} end))
             else . end)
          # decision:block (非 PreToolUse) を top-level に載せる
          | (if $decBlock then
               (.decision = "block"
                | (if ($decReason // "") != "" then .reason = $decReason else . end))
             else . end)
          | (if ($sysmsgs // "") != "" then .systemMessage = $sysmsgs else . end)
          | (if $suppress then .suppressOutput = true else . end)
      ' 2>/dev/null
  )"

  if [ -n "$_dc_merged" ] && printf '%s' "$_dc_merged" | jq -e . >/dev/null 2>&1; then
    printf '%s' "$_dc_merged"
    exit 0
  fi

  # --- fail-safe (jq 失敗): block 情報を絶対落とさない ---
  # block (decision:block / permissionDecision:deny) を持つ object があれば、それを単独で出す。
  # exit2 / stdout-block channel の block は既に early-exit 済なので通常ここには来ないが、
  # advisory 子が decision を持つ event / jq 不在環境での保険として最低限 block を保持する。
  _dc_first=""
  _dc_block_obj=""
  _dc_old_ifs="$IFS"
  IFS="$_dc_GS"
  for _dc_one in $_dc_jsonbuf; do
    [ -z "$_dc_one" ] && continue
    [ -z "$_dc_first" ] && _dc_first="$_dc_one"
    if printf '%s' "$_dc_one" | grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' \
       || printf '%s' "$_dc_one" | grep -q '"permissionDecision"[[:space:]]*:[[:space:]]*"deny"'; then
      _dc_block_obj="$_dc_one"
      break
    fi
  done
  IFS="$_dc_old_ifs"
  if [ -n "$_dc_block_obj" ]; then
    printf '%s' "$_dc_block_obj"
    exit 0
  fi
  # block 無し → 先頭の単一 object を出す (verbatim 連結より安全、M-INV-1 維持)
  if [ -n "$_dc_first" ]; then
    printf '%s' "$_dc_first"
    exit 0
  fi
  # JSON も無い (理論上到達しない) → 無出力
  exit 0
)
