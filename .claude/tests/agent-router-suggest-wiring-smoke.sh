#!/usr/bin/env bash
# agent-router-suggest-wiring-smoke.sh — task-81
#
# 目的:
#   dead hook agent-router-suggest.sh の dispatcher 配線復活 (task-81) を検証する。
#   manifest 行存在 / feature toggle ON-OFF の child spawn 差 / マッチ・非マッチ prompt の
#   出力差 / settings drift 0 を実 (live) artifact に対して read-only で検証する。
#
# 検証する DoD (docs/draft/wire-agent-router-suggest.md §6):
#   1. manifest に UserPromptSubmit agent-router-suggest 行が存在 (7 列 TAB)
#   2. config-loader が HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED を export (yml true → env)
#   3. toggle ON + マッチ prompt (security) → hook 単体で 1 行 hint 出力
#   4. toggle ON + マッチ prompt → dispatcher 経由で hint が additionalContext 相当で出力
#   5. toggle OFF (env) + マッチ prompt → hook 単体 no-op (空 exit 0)
#   6. toggle OFF (env) + マッチ prompt → dispatcher 経由で child spawn されず空出力
#   7. 非マッチ prompt (雑談) → 空出力 exit 0
#   8. 空 prompt → 空出力 exit 0
#   9. settings drift 0 (generate-settings.sh --check、dispatcher 方式で hooks block 不変)
#
# 実行:    bash .claude/tests/agent-router-suggest-wiring-smoke.sh
# 終了:    0 = 全 case PASS / 1 = 1 件以上 FAIL
#
# 前提: python3 不在環境では hook は fail-open で常に空出力になるため、router 依存 case
#       (3,4,7) は skip 扱い (SKIP として PASS にカウント、wiring 自体は検証できる)。
#
# recon 規約: file-top `set -u`、隔離 tmp dir + trap cleanup (EXIT INT TERM)、run_case + PASS/FAIL summary。
# bash 3.2 互換 (macOS)。

set -u

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOOK="$REPO_ROOT/.claude/hooks/agent-router-suggest.sh"
DISPATCHER="$REPO_ROOT/.claude/hooks/user-prompt-submit-dispatcher.sh"
MANIFEST="$REPO_ROOT/.claude/hooks/dispatcher-manifest.tsv"
CONFIG_LOADER="$REPO_ROOT/.claude/hooks/lib/config-loader.sh"
GEN_SETTINGS="$REPO_ROOT/.claude/scripts/generate-settings.sh"

TMPBASE="$(mktemp -d "${TMPDIR:-/tmp}/agent-router-wiring-smoke.XXXXXX")"
trap 'rm -rf "$TMPBASE"' EXIT INT TERM

PASS=0
FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS: %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL: %s\n' "$1"; }

# matching prompt (router が high-confidence で security-auditor を返す)
MATCH_PROMPT='{"prompt":"please do a security review for sql injection vulnerabilities in the auth module"}'
# 非マッチ prompt (雑談)
NOMATCH_PROMPT='{"prompt":"hello how are you today thanks a lot"}'
EMPTY_PROMPT='{"prompt":""}'

HAS_PY=0
command -v python3 >/dev/null 2>&1 && HAS_PY=1

# ---------------------------------------------------------------------------
# Case 1: manifest に UserPromptSubmit agent-router-suggest.sh 行が存在 (7 列 TAB)
# ---------------------------------------------------------------------------
row="$(awk -F'\t' '$1=="UserPromptSubmit" && $4=="agent-router-suggest.sh" {print; exit}' "$MANIFEST")"
if [ -n "$row" ]; then
  nf="$(printf '%s' "$row" | awk -F'\t' '{print NF}')"
  feat="$(printf '%s' "$row" | awk -F'\t' '{print $5}')"
  chan="$(printf '%s' "$row" | awk -F'\t' '{print $6}')"
  if [ "$nf" -eq 7 ] && [ "$feat" = "agent_router_suggest" ] && [ "$chan" = "advisory" ]; then
    ok "Case1 manifest 行存在 (7 列 / feature_key=agent_router_suggest / channel=advisory)"
  else
    bad "Case1 manifest 行 列数/値 不正: NF=$nf feat=$feat chan=$chan"
  fi
else
  bad "Case1 manifest に UserPromptSubmit agent-router-suggest.sh 行が無い"
fi

# ---------------------------------------------------------------------------
# Case 2: config-loader が HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED を export (yml true)
# ---------------------------------------------------------------------------
val="$(bash -c "cd '$REPO_ROOT'; source '$CONFIG_LOADER' 2>/dev/null; printf '%s' \"\${HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED:-UNSET}\"")"
if [ "$val" = "true" ]; then
  ok "Case2 config-loader export: HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED=true (yml 反映)"
else
  bad "Case2 config-loader export 値=[$val] (expected true)"
fi

# is_feature_enabled が agent_router_suggest を ON 判定するか
ife_on="$(bash -c "cd '$REPO_ROOT'; source '$CONFIG_LOADER' 2>/dev/null; is_feature_enabled agent_router_suggest && echo ON || echo OFF")"
if [ "$ife_on" = "ON" ]; then
  ok "Case2b is_feature_enabled agent_router_suggest = ON (default)"
else
  bad "Case2b is_feature_enabled agent_router_suggest = $ife_on (expected ON)"
fi

# env override false が勝つか
ife_off="$(cd "$REPO_ROOT"; HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED=false bash -c "source '$CONFIG_LOADER' 2>/dev/null; is_feature_enabled agent_router_suggest && echo ON || echo OFF")"
if [ "$ife_off" = "OFF" ]; then
  ok "Case2c env override HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED=false → OFF"
else
  bad "Case2c env override false → $ife_off (expected OFF)"
fi

# ---------------------------------------------------------------------------
# Case 3: toggle ON + マッチ prompt → hook 単体で 1 行 hint 出力 (python3 必須)
# ---------------------------------------------------------------------------
if [ "$HAS_PY" -eq 1 ]; then
  out="$(cd "$REPO_ROOT"; printf '%s' "$MATCH_PROMPT" | bash "$HOOK" 2>/dev/null)"; rc=$?
  lines="$(printf '%s' "$out" | grep -c . )"
  if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q '\[agent-router suggestion\]' && [ "$lines" -le 1 ]; then
    ok "Case3 hook 単体 ON+マッチ: 1 行 hint 出力 (rc=0)"
  else
    bad "Case3 hook 単体 ON+マッチ: rc=$rc lines=$lines out=[$out]"
  fi
else
  ok "Case3 SKIP (python3 不在、router 依存) — wiring は Case1/2 で検証済"
fi

# ---------------------------------------------------------------------------
# Case 4: toggle ON + マッチ prompt → dispatcher 経由で hint 出力 (child spawn 実証)
# ---------------------------------------------------------------------------
if [ "$HAS_PY" -eq 1 ]; then
  dout="$(cd "$REPO_ROOT"; printf '%s' "$MATCH_PROMPT" | bash "$DISPATCHER" 2>/dev/null)"; drc=$?
  if [ "$drc" -eq 0 ] && printf '%s' "$dout" | grep -q '\[agent-router suggestion\]'; then
    ok "Case4 dispatcher ON+マッチ: child spawn され hint 出力 (rc=0)"
  else
    bad "Case4 dispatcher ON+マッチ: rc=$drc out=[$dout]"
  fi
else
  ok "Case4 SKIP (python3 不在)"
fi

# ---------------------------------------------------------------------------
# Case 5: toggle OFF (env) + マッチ prompt → hook 単体 no-op (空 exit 0)
# ---------------------------------------------------------------------------
out="$(cd "$REPO_ROOT"; printf '%s' "$MATCH_PROMPT" | HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED=false bash "$HOOK" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "Case5 hook 単体 OFF: 空出力 exit 0 (no-op)"
else
  bad "Case5 hook 単体 OFF: rc=$rc out=[$out]"
fi

# ---------------------------------------------------------------------------
# Case 6: toggle OFF (env) + マッチ prompt → dispatcher 経由で child spawn されず空出力
# ---------------------------------------------------------------------------
dout="$(cd "$REPO_ROOT"; printf '%s' "$MATCH_PROMPT" | HC_FEATURE_AGENT_ROUTER_SUGGEST_ENABLED=false bash "$DISPATCHER" 2>/dev/null)"; drc=$?
# dispatcher は feature gate で child を spawn しない。他 advisory 子 (context-budget) は
# Normal モードで no-op のため、agent-router の hint が出ないことを検証する。
if [ "$drc" -eq 0 ] && ! printf '%s' "$dout" | grep -q '\[agent-router suggestion\]'; then
  ok "Case6 dispatcher OFF: agent-router child gated out (hint 不在、rc=0)"
else
  bad "Case6 dispatcher OFF: rc=$drc out=[$dout] (hint が出てしまった)"
fi

# ---------------------------------------------------------------------------
# Case 7: 非マッチ prompt (雑談) → 空出力 exit 0
# ---------------------------------------------------------------------------
if [ "$HAS_PY" -eq 1 ]; then
  out="$(cd "$REPO_ROOT"; printf '%s' "$NOMATCH_PROMPT" | bash "$HOOK" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && ! printf '%s' "$out" | grep -q '\[agent-router suggestion\]'; then
    ok "Case7 非マッチ prompt: hint 不在 exit 0"
  else
    bad "Case7 非マッチ prompt: rc=$rc out=[$out]"
  fi
else
  ok "Case7 SKIP (python3 不在)"
fi

# ---------------------------------------------------------------------------
# Case 8: 空 prompt → 空出力 exit 0 (router を呼ぶ前に early-exit)
# ---------------------------------------------------------------------------
out="$(cd "$REPO_ROOT"; printf '%s' "$EMPTY_PROMPT" | bash "$HOOK" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "Case8 空 prompt: 空出力 exit 0"
else
  bad "Case8 空 prompt: rc=$rc out=[$out]"
fi

# ---------------------------------------------------------------------------
# Case 9: settings drift 0 (dispatcher 方式で hooks block 不変)
# ---------------------------------------------------------------------------
if [ -f "$GEN_SETTINGS" ]; then
  if (cd "$REPO_ROOT"; bash "$GEN_SETTINGS" --check) >/dev/null 2>&1; then
    ok "Case9 generate-settings.sh --check: drift 無し"
  else
    bad "Case9 generate-settings.sh --check: drift 検出 (manifest 行追加で settings 再生成が必要か)"
  fi
else
  bad "Case9 generate-settings.sh 不在: $GEN_SETTINGS"
fi

# ---------------------------------------------------------------------------
echo "== result: PASS=$PASS FAIL=$FAIL =="
[ "$FAIL" -eq 0 ]
