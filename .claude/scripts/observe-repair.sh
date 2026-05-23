#!/usr/bin/env bash
# observe-repair.sh — Repair pre-W1 invalid records in observations.jsonl.
#
# 役割:
#   ~/.claude/homunculus/projects/<hash>/observations.jsonl を走査し、
#   jq-invalid 行 (literal control char で JSON parse fail) を識別して
#   修復可能なら raw field を `fromjson?` 経路で再解釈 + control char escape して
#   in-place rewrite する。修復不能行は `_invalid: true` + `_repaired_at: <ts>` marker を
#   付けて audit trail として残す (情報損失を回避)。
#
# 設計起源:
#   docs/draft/observe-jq-parse-fix.md §3 W2 (2026-05-23)
#
# 前提:
#   W1 (commit c25f3ee) で observe.sh は --rawfile + fromjson? 経路に修正済。
#   W1 以降の records は jq-valid 100%。本 script は pre-W1 期間 (~11 日間
#   5/12-5/23) の蓄積された 56% invalid records (3916/7048) を救出する。
#
# 起動経路:
#   - 手動: bash .claude/scripts/observe-repair.sh --dry-run
#   - 手動: bash .claude/scripts/observe-repair.sh --in-place
#   - 将来: harness-audit subcommand --repair-observations
#
# 引数:
#   --dry-run                修復対象行を識別 + summary 出力のみ、jsonl 不変更
#   --in-place               修復 record で in-place rewrite (default で --backup 併用)
#   --backup                 backup file (observations.jsonl.bak-<ts>) を生成
#   --target <jsonl-path>    修復対象 jsonl path
#                            (default: ~/.claude/homunculus/**/observations.jsonl を find で探索)
#   --target-dir <path>      base dir override (default: ~/.claude/homunculus)
#                            (smoke test 隔離用、live dir を汚染しないため)
#   -h, --help               このヘルプ
#
# Exit code:
#   0 = success
#   1 = invalid arg / fatal error
#   2 = target jsonl not found
#   3 = lock 取得失敗 (active session 中の skip)
#
# 重要制約:
#   - file-top に set -euo pipefail を書かない (CLAUDE.md Critical Lessons HIGH 準拠)
#   - command -v jq guard
#   - active session の同時 write を防ぐため lock (mkdir lock) 経由で排他
#   - atomic mv で in-place rewrite (途中 crash でも本体破損なし)
#   - 修復不能行は破棄せず `_invalid: true` marker で残す (audit trail)

set -uo pipefail

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
}

# ===== arg parse =====
DRY_RUN=0
IN_PLACE=0
BACKUP=0
TARGET_FILE=""
TARGET_DIR_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --in-place)
      IN_PLACE=1
      BACKUP=1  # in-place は default で backup 併用
      shift
      ;;
    --backup)
      BACKUP=1
      shift
      ;;
    --target)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf '[observe-repair] ERROR: --target requires a value\n' >&2
        exit 1
      fi
      TARGET_FILE="$2"
      shift 2
      ;;
    --target-dir)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf '[observe-repair] ERROR: --target-dir requires a value\n' >&2
        exit 1
      fi
      TARGET_DIR_OVERRIDE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf '[observe-repair] ERROR: unknown arg: %s\n' "$1" >&2
      exit 1
      ;;
  esac
done

# ===== runtime dependency guard =====
if ! command -v jq >/dev/null 2>&1; then
  printf '[observe-repair] ERROR: jq not found in PATH\n' >&2
  exit 1
fi

# default mode: dry-run (destructive op を accidental に起動しない)
if [ "$DRY_RUN" -eq 0 ] && [ "$IN_PLACE" -eq 0 ]; then
  DRY_RUN=1
  printf '[observe-repair] no --dry-run / --in-place specified, defaulting to --dry-run\n' >&2
fi

# ===== target file 解決 =====
BASE_DIR="${TARGET_DIR_OVERRIDE:-${HOME}/.claude/homunculus}"

resolve_targets() {
  if [ -n "$TARGET_FILE" ]; then
    if [ ! -f "$TARGET_FILE" ]; then
      printf '[observe-repair] ERROR: --target file not found: %s\n' "$TARGET_FILE" >&2
      exit 2
    fi
    printf '%s\n' "$TARGET_FILE"
    return 0
  fi

  if [ ! -d "$BASE_DIR" ]; then
    printf '[observe-repair] ERROR: base dir not found: %s\n' "$BASE_DIR" >&2
    exit 2
  fi

  # ~/.claude/homunculus/{observations.jsonl, projects/*/observations.jsonl}
  find "$BASE_DIR" -name 'observations.jsonl' -type f 2>/dev/null | sort
}

TARGETS=$(resolve_targets)

if [ -z "$TARGETS" ]; then
  printf '[observe-repair] ERROR: no observations.jsonl found under %s\n' "$BASE_DIR" >&2
  exit 2
fi

# ===== lock 機構 (mkdir lock、active session との race 回避) =====
# 各 target ごとに observations.jsonl.lock dir を作成、削除責任は acquire 側
acquire_lock() {
  local target="$1"
  local lock="${target}.lock"
  if mkdir "$lock" 2>/dev/null; then
    return 0
  fi
  return 1
}

release_lock() {
  local target="$1"
  local lock="${target}.lock"
  rmdir "$lock" 2>/dev/null || true
}

# ===== 修復 logic =====
# 1 jsonl file を処理し、修復 record を tmp に書き出して atomic mv で in-place rewrite
# stdout に summary を出す: TOTAL=N VALID=N INVALID=N REPAIRED=N UNREPAIRABLE=N
#
# 重要: bash の `while read` は physical newline で split するが、pre-W1 invalid
# records は literal control char (実 newline) を含むため 1 logical record が
# 2+ physical lines に分かれる。bash で処理すると 1 record の前半・後半が
# 別 line として識別され、両方とも invalid 判定になる double-count bug を生む。
# よって全体を Python の json.JSONDecoder.raw_decode loop で 1 record ずつ
# 取り出すアプローチを採用する (jq では literal control char で parse fail
# するため使えない)。
process_file() {
  local target="$1"
  local mode="$2"   # "dry-run" or "in-place"

  if ! command -v python3 >/dev/null 2>&1; then
    printf '[observe-repair] ERROR: python3 required for repair logic\n' >&2
    return 1
  fi

  local tmp_out
  tmp_out=$(mktemp /tmp/observe-repair.XXXXXX) || {
    printf '[observe-repair] ERROR: mktemp failed for %s\n' "$target" >&2
    return 1
  }

  local repair_ts
  repair_ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  # Python で 1 file 全体を処理する。
  # 戦略:
  #   1. file 全体を bytes として読み、UTF-8 で safe decode
  #   2. json.JSONDecoder().raw_decode() を loop で呼び、1 record ずつ取り出す
  #   3. decode 成功 record はそのまま採用、ただし元の physical 表現に
  #      literal control char (改行) が含まれていたら「修復扱い」とし
  #      _repaired_at marker を付ける (本来は escape 済の \n になるべき)
  #   4. decode fail 区間は invalid marker (_invalid:true) を生成して残す
  #   5. 結果は JSON Lines として tmp_out に書く
  #   6. SUMMARY line を最終行に "##SUMMARY total=N valid=N invalid=N repaired=N unrepairable=N" として stdout に出す
  local stats
  stats=$(REPAIR_TS="$repair_ts" TARGET="$target" TMP_OUT="$tmp_out" python3 - <<'PYEOF'
import json
import os
import sys

target = os.environ["TARGET"]
tmp_out = os.environ["TMP_OUT"]
repair_ts = os.environ["REPAIR_TS"]

with open(target, "rb") as fh:
    raw_bytes = fh.read()

# UTF-8 で safe decode (broken UTF-8 sequence は replace)
text = raw_bytes.decode("utf-8", errors="replace")

decoder = json.JSONDecoder(strict=False)  # strict=False で control char 許容

total = 0
valid = 0
repaired = 0
unrepairable = 0
# valid と repaired の合計が「元の logical record 数」だが、
# bash 側の "invalid" は repaired + unrepairable と定義する
# (= 「strict JSON として fail だが修復試行された record の数」)

out_lines = []

i = 0
n = len(text)

while i < n:
    # 改行のみ / whitespace のみ を skip
    while i < n and text[i] in (" ", "\t", "\n", "\r"):
        i += 1
    if i >= n:
        break

    start = i
    try:
        obj, end_idx = decoder.raw_decode(text, idx=i)
        total += 1
        # この record が strict JSON だったか判定:
        # 元 substring に literal control char (0x00-0x1F、ただし
        # JSON allowed whitespace を除く: 0x09 tab / 0x0A LF / 0x0D CR)
        # を含むか
        substr = text[start:end_idx]
        # strict JSON 違反 = control char in JSON value (string 内)
        # チェック: substr 内に literal LF / CR / TAB / その他 control char
        # の出現位置で「string literal の中」にあるかは複雑。
        # 簡便: substr に 0x0A / 0x0D / 0x09 含むなら repaired と判定
        # (= W1 以前の literal newline-containing record)
        has_ctrl = any(c in substr for c in ("\n", "\r", "\t"))
        if isinstance(obj, dict):
            if has_ctrl:
                # 修復扱い: literal control char が含まれていたが
                # strict=False decoder で読めた → escape 済の re-emit
                obj["_repaired_at"] = repair_ts
                out_lines.append(json.dumps(obj, ensure_ascii=False, separators=(",", ":")))
                repaired += 1
                valid += 0  # repaired は valid に含めない (区別表示)
            else:
                # 既に strict JSON valid
                out_lines.append(json.dumps(obj, ensure_ascii=False, separators=(",", ":")))
                valid += 1
        else:
            # object 以外 (array 等) → そのまま採用、count は valid
            out_lines.append(json.dumps(obj, ensure_ascii=False, separators=(",", ":")))
            valid += 1
        i = end_idx
    except json.JSONDecodeError as e:
        # decode fail: 次の "{" まで skip して再試行
        # decode 不能区間を 1 件の unrepairable record として記録
        next_brace = text.find("{", i + 1)
        if next_brace == -1:
            # 末尾まで unparse: 残全部を 1 件として記録
            failed_region = text[i:n]
            i = n
        else:
            failed_region = text[i:next_brace]
            i = next_brace

        total += 1
        unrepairable += 1
        marker = {
            "_invalid": True,
            "_repaired_at": repair_ts,
            "_original_line": failed_region.rstrip("\n"),
            "_decode_error": str(e),
        }
        out_lines.append(json.dumps(marker, ensure_ascii=False, separators=(",", ":")))

# 書き出し
with open(tmp_out, "w", encoding="utf-8") as fh:
    for line in out_lines:
        fh.write(line + "\n")

# bash 側集計のため invalid = repaired + unrepairable
invalid = repaired + unrepairable
sys.stdout.write(f"TOTAL={total} VALID={valid} INVALID={invalid} REPAIRED={repaired} UNREPAIRABLE={unrepairable}\n")
PYEOF
  )
  local py_rc=$?

  if [ "$py_rc" -ne 0 ]; then
    printf '[observe-repair] ERROR: python processing failed for %s (rc=%d)\n' "$target" "$py_rc" >&2
    rm -f "$tmp_out"
    return 1
  fi

  # in-place rewrite (mode == in-place のみ)
  if [ "$mode" = "in-place" ]; then
    if [ "$BACKUP" -eq 1 ]; then
      local bak_ts
      bak_ts=$(date -u +%Y%m%dT%H%M%SZ)
      local bak="${target}.bak-${bak_ts}"
      if ! cp "$target" "$bak"; then
        printf '[observe-repair] ERROR: backup failed: %s\n' "$bak" >&2
        rm -f "$tmp_out"
        return 1
      fi
      printf '[observe-repair]   backup: %s\n' "$bak"
    fi
    # atomic mv
    if ! mv "$tmp_out" "$target"; then
      printf '[observe-repair] ERROR: atomic mv failed for: %s\n' "$target" >&2
      rm -f "$tmp_out"
      return 1
    fi
  else
    # dry-run: tmp は廃棄
    rm -f "$tmp_out"
  fi

  # summary を stdout に出す (Python が既に format 済)
  printf '%s' "$stats"
  return 0
}

# ===== main loop =====
MODE="dry-run"
if [ "$IN_PLACE" -eq 1 ]; then
  MODE="in-place"
fi

printf '[observe-repair] mode: %s\n' "$MODE"
printf '[observe-repair] base dir: %s\n' "$BASE_DIR"

GRAND_TOTAL=0
GRAND_VALID=0
GRAND_INVALID=0
GRAND_REPAIRED=0
GRAND_UNREPAIRABLE=0
SKIPPED_FILES=0

# IFS=newline で TARGETS を loop
OLD_IFS="$IFS"
IFS=$'\n'
for tgt in $TARGETS; do
  IFS="$OLD_IFS"
  printf '[observe-repair] target: %s\n' "$tgt"

  # lock 取得 (active session との race 回避)
  if [ "$MODE" = "in-place" ]; then
    if ! acquire_lock "$tgt"; then
      printf '[observe-repair]   SKIP: lock exists (active session?), skipping: %s.lock\n' "$tgt" >&2
      SKIPPED_FILES=$((SKIPPED_FILES + 1))
      IFS=$'\n'
      continue
    fi
  fi

  result=$(process_file "$tgt" "$MODE")
  rc=$?

  if [ "$MODE" = "in-place" ]; then
    release_lock "$tgt"
  fi

  if [ "$rc" -ne 0 ]; then
    printf '[observe-repair]   ERROR processing %s\n' "$tgt" >&2
    IFS=$'\n'
    continue
  fi

  # parse summary (Python が "TOTAL=N VALID=N INVALID=N REPAIRED=N UNREPAIRABLE=N" の単一行で出力)
  # awk -F= は 1 line input では行マッチが field 抽出にならないため、
  # space-separated key=value を 1 個ずつ awk で抽出する
  extract_kv() {
    local key="$1"
    local input="$2"
    # space split + key= で始まる token から value を取り出す
    printf '%s' "$input" | awk -v k="$key" '
      {
        for (i = 1; i <= NF; i++) {
          if (index($i, k "=") == 1) {
            sub(k "=", "", $i)
            print $i
            exit
          }
        }
      }
    '
  }
  t=$(extract_kv TOTAL "$result")
  v=$(extract_kv VALID "$result")
  i=$(extract_kv INVALID "$result")
  r=$(extract_kv REPAIRED "$result")
  u=$(extract_kv UNREPAIRABLE "$result")

  printf '[observe-repair]   total=%s valid=%s invalid=%s repaired=%s unrepairable=%s\n' \
    "$t" "$v" "$i" "$r" "$u"

  GRAND_TOTAL=$((GRAND_TOTAL + t))
  GRAND_VALID=$((GRAND_VALID + v))
  GRAND_INVALID=$((GRAND_INVALID + i))
  GRAND_REPAIRED=$((GRAND_REPAIRED + r))
  GRAND_UNREPAIRABLE=$((GRAND_UNREPAIRABLE + u))

  IFS=$'\n'
done
IFS="$OLD_IFS"

printf '\n[observe-repair] ===== Summary =====\n'
printf '[observe-repair] files processed: %d\n' "$(printf '%s\n' "$TARGETS" | wc -l | awk '{print $1}')"
if [ "$SKIPPED_FILES" -gt 0 ]; then
  printf '[observe-repair] files skipped (locked): %d\n' "$SKIPPED_FILES"
fi
printf '[observe-repair] total records: %d\n' "$GRAND_TOTAL"
printf '[observe-repair] already valid: %d\n' "$GRAND_VALID"
printf '[observe-repair] invalid (pre-W1): %d\n' "$GRAND_INVALID"
printf '[observe-repair] repaired: %d\n' "$GRAND_REPAIRED"
printf '[observe-repair] unrepairable (marked): %d\n' "$GRAND_UNREPAIRABLE"

if [ "$MODE" = "dry-run" ]; then
  printf '[observe-repair] dry-run: no file changes applied (use --in-place to rewrite)\n'
fi

exit 0
