#!/usr/bin/env python3
"""SWE-bench Lite task runner driver (Phase C-1.6 hybrid mode).

Phase C-1 dry-run の patch 適用率 40% (corrupt hunk header 失敗 60%) を whole-file
mode で 60% (3/3 generated→applied = 100%) まで改善した一方、大規模 file 全文出力で
claude が timeout する failure class が出現 (2/5)。

Phase C-1.6 で追加:

- --patch-mode hybrid
    Step A: whole-file mode を short timeout (--whole-file-timeout-sec, default 600s)
            で試行。
    Step B: timeout / empty patch なら unified-diff mode に fallback
            (timeout = 残予算 = per_task_timeout_sec - whole-file 経過時間, 最低 180s)。
    Step C: 成功した patch を採用。claude_meta.attempt_history に試行履歴を記録。

Phase C-1.5 から継続:
- --patch-mode {whole-file, unified-diff} 単独モードは引き続き利用可。
- --resume / --parallel / --cost-cap-usd / --save-raw / atomic write。

Usage (Phase C-1.6 dry-run):
    python3 runner.py --tasks tasks/lite-50.json --limit 5 \
        --patch-mode hybrid --per-task-timeout-sec 900 \
        --save-raw --cost-cap-usd 5.0 \
        --output results/dry-run-hybrid-2026-05-05.json
"""
from __future__ import annotations

import argparse
import concurrent.futures as cf
import difflib
import json
import os
import re
import shlex
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
from scoring import score_task  # noqa: E402


# === config loader (super lightweight YAML subset) ===
def _load_config() -> dict:
    cfg_path = ROOT / "config.yml"
    cfg: dict = {}
    if not cfg_path.exists():
        return cfg
    for raw in cfg_path.read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].rstrip()
        if not line or ":" not in line:
            continue
        k, _, v = line.partition(":")
        v = v.strip()
        if not v:
            continue
        if v.lower() in ("true", "false"):
            cfg[k.strip()] = v.lower() == "true"
        else:
            try:
                cfg[k.strip()] = float(v) if "." in v else int(v)
            except ValueError:
                cfg[k.strip()] = v
    return cfg


CFG = _load_config()


# ============================================================================
# Prompt builders
# ============================================================================

UNIFIED_DIFF_EXAMPLE = """\
diff --git a/src/example.py b/src/example.py
--- a/src/example.py
+++ b/src/example.py
@@ -10,7 +10,7 @@
 def calculate(x):
     # validate input
-    if x < 0:
+    if x <= 0:
         raise ValueError("x must be positive")
     return x * 2
"""


def _build_prompt_unified(task: dict) -> str:
    """強化版 unified-diff prompt。example diff + hunk header の厳格化指示。"""
    repo = task["repo"]
    base = task["base_commit"]
    problem = task["problem_statement"]
    hints = task.get("hints_text", "") or ""

    return f"""You are an expert software engineer solving a real GitHub issue from {repo}.

# Repository
- repo: https://github.com/{repo}
- base commit: {base}

# Issue / Problem statement
{problem}

# Hints (optional)
{hints[:2000] if hints else "(none)"}

# Your task
Produce a single unified diff (`diff --git ...`) that fixes this issue.
The diff MUST apply cleanly to the base commit with `git apply`.

# CRITICAL: hunk header rules
- Every hunk starts with `@@ -ORIG_LINE,ORIG_COUNT +NEW_LINE,NEW_COUNT @@`
- ORIG_LINE / NEW_LINE are 1-based line numbers in the ORIGINAL file at the
  start of the context shown in the hunk.
- ORIG_COUNT = number of lines in the hunk before changes (context + removed)
- NEW_COUNT  = number of lines in the hunk after changes (context + added)
- Include AT LEAST 3 lines of context above and below each change.
- DO NOT guess line numbers. If unsure, output an empty patch.

# Example (correct format)
```
{UNIFIED_DIFF_EXAMPLE}```

# Strict output requirements
- Output ONLY the unified diff, no prose, no markdown fences, no explanation.
- Modify only files necessary to fix the issue. Do NOT modify test files.
- If you cannot produce a confident fix, output an empty patch (just whitespace).
"""


def _build_prompt_whole_file(task: dict) -> str:
    """whole-file mode prompt。

    claude は「PATH: <relative path>」 + `<<<FILE_START>>>` ... `<<<FILE_END>>>`
    の形式で 1 つ以上の修正後ファイル全文を出力する。
    runner.py が repo を clone し difflib で正規 unified diff を生成。
    """
    repo = task["repo"]
    base = task["base_commit"]
    problem = task["problem_statement"]
    hints = task.get("hints_text", "") or ""

    return f"""You are an expert software engineer solving a real GitHub issue from {repo}.

# Repository
- repo: https://github.com/{repo}
- base commit: {base}

# Issue / Problem statement
{problem}

# Hints (optional)
{hints[:2000] if hints else "(none)"}

# Your task
Identify the file(s) that need to be modified and output the COMPLETE NEW
CONTENT of each file (the full file as it should look AFTER your fix).

# Output format (STRICT)
For each file you modify, output exactly this structure:

PATH: <relative/path/from/repo/root.py>
<<<FILE_START>>>
<the entire new content of the file, line by line>
<<<FILE_END>>>

# Rules
- Output paths relative to the repository root, NOT absolute paths.
- Include the FULL file content, not just the changed parts. The runner will
  diff your output against the base commit to produce the patch.
- Do NOT modify test files (anything matching `test_*.py`, `*_test.py`,
  `tests/**`, or with `test` in the path).
- Multiple files: repeat the PATH/FILE_START/FILE_END block for each file.
- Output NO prose, NO markdown fences, NO explanation. Only PATH/FILE blocks.
- If you cannot produce a confident fix, output exactly the literal string:
  NO_FIX
"""


# ============================================================================
# Diff extraction & generation
# ============================================================================

def _extract_unified_diff(claude_output: str) -> str:
    """unified-diff mode: claude 出力から diff 部分のみ抽出。"""
    m = re.search(r"```(?:diff|patch)?\s*\n(diff --git[\s\S]*?)```", claude_output)
    if m:
        return m.group(1).strip() + "\n"
    idx = claude_output.find("diff --git")
    if idx >= 0:
        return claude_output[idx:].strip() + "\n"
    return ""


_FILE_BLOCK_RE = re.compile(
    r"PATH:\s*(?P<path>[^\r\n]+)\s*\n<<<FILE_START>>>\s*\n(?P<content>.*?)\n<<<FILE_END>>>",
    re.DOTALL,
)


def _parse_whole_file_blocks(claude_output: str) -> list[tuple[str, str]]:
    """whole-file mode: claude 出力から (path, new_content) のリストを抽出。

    NO_FIX 単体の場合は空リスト。
    """
    if claude_output.strip() == "NO_FIX":
        return []
    out: list[tuple[str, str]] = []
    for m in _FILE_BLOCK_RE.finditer(claude_output):
        path = m.group("path").strip()
        # exclude absolute path / parent traversal
        if path.startswith("/") or ".." in path.split("/"):
            continue
        # exclude obvious test files (defense in depth; prompt も指示済)
        lower = path.lower()
        if (
            lower.startswith("tests/")
            or "/tests/" in lower
            or lower.endswith("_test.py")
            or "/test_" in lower
            or lower.startswith("test_")
        ):
            continue
        content = m.group("content")
        # ensure trailing newline
        if not content.endswith("\n"):
            content += "\n"
        out.append((path, content))
    return out


def _docker_get_file(image: str, repo: str, base_commit: str, rel_path: str, timeout: int = 90) -> tuple[bool, str]:
    """指定 repo@base_commit の rel_path の中身を取得 (docker 経由)。

    存在しない場合は ("", False) ではなく (True, "") を返し「新規作成」と区別する。
    成功時 (True, content)、git clone 失敗等は (False, error_msg)。
    """
    cmd = [
        "docker", "run", "--rm",
        image, "bash", "-lc",
        f"set -e; "
        f"git clone --quiet --no-tags --filter=blob:none https://github.com/{repo}.git /tmp/r && "
        f"cd /tmp/r && git checkout --quiet {base_commit} && "
        f"if [ -f {shlex.quote(rel_path)} ]; then cat {shlex.quote(rel_path)}; else echo __NEW_FILE__; fi",
    ]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, "timeout fetching file"
    if proc.returncode != 0:
        return False, f"git fetch failed: {(proc.stderr or proc.stdout)[:200]}"
    content = proc.stdout
    if content.strip() == "__NEW_FILE__":
        return True, ""
    return True, content


def _generate_unified_diff_from_files(
    files: list[tuple[str, str]],
    image: str,
    repo: str,
    base_commit: str,
) -> tuple[str, str | None]:
    """whole-file blocks から正規 unified diff を生成。

    各 file について: 元 content (docker 経由 git fetch) と new content を difflib で diff。
    返り値: (patch_text, error_or_None)
    """
    if not files:
        return "", "no file blocks parsed"

    parts: list[str] = []
    for rel_path, new_content in files:
        ok, original = _docker_get_file(image, repo, base_commit, rel_path)
        if not ok:
            return "", f"failed to fetch {rel_path}: {original}"

        is_new = original == ""

        old_lines = original.splitlines(keepends=True)
        new_lines = new_content.splitlines(keepends=True)
        # ensure final newline
        if old_lines and not old_lines[-1].endswith("\n"):
            old_lines[-1] += "\n"
        if new_lines and not new_lines[-1].endswith("\n"):
            new_lines[-1] += "\n"

        if old_lines == new_lines:
            # no change → skip
            continue

        # generate unified diff with `a/<path>` / `b/<path>` headers (git-style)
        diff_iter = difflib.unified_diff(
            old_lines,
            new_lines,
            fromfile=f"a/{rel_path}",
            tofile=f"b/{rel_path}",
            n=3,
        )
        diff_body = "".join(diff_iter)
        if not diff_body.strip():
            continue

        # prepend `diff --git` header
        header = f"diff --git a/{rel_path} b/{rel_path}\n"
        if is_new:
            header += "new file mode 100644\n"
        parts.append(header + diff_body)

    if not parts:
        return "", "no actual changes (output identical to base)"

    return "".join(parts), None


# ============================================================================
# Claude invocation
# ============================================================================

def _invoke_claude(prompt: str, model: str, max_budget_usd: float, timeout: int) -> tuple[str, dict]:
    """claude CLI -p で 1 タスクを解かせる。"""
    cmd = [
        "claude", "-p",
        "--model", model,
        "--output-format", "json",
        "--input-format", "text",
        "--max-budget-usd", str(max_budget_usd),
        "--no-session-persistence",
        "--permission-mode", "bypassPermissions",
        "--disallowedTools", "Bash,Edit,Write,Read,Grep,Glob,WebSearch,WebFetch,Task",
    ]
    env = os.environ.copy()

    try:
        proc = subprocess.run(
            cmd, input=prompt, capture_output=True, text=True, timeout=timeout, env=env,
        )
    except subprocess.TimeoutExpired:
        return "", {"error": "timeout", "cost_usd": 0.0}

    raw = proc.stdout or ""
    meta: dict = {"cost_usd": 0.0, "duration_ms": 0, "rc": proc.returncode}
    text_response = raw

    try:
        parsed = json.loads(raw)
        if isinstance(parsed, dict):
            text_response = parsed.get("result") or parsed.get("text") or raw
            usage = parsed.get("usage") or {}
            meta["cost_usd"] = float(parsed.get("total_cost_usd") or usage.get("total_cost_usd") or 0.0)
            meta["duration_ms"] = int(parsed.get("duration_ms") or 0)
    except json.JSONDecodeError:
        text_response = raw

    if proc.returncode != 0:
        meta["error"] = (proc.stderr or "")[:500]
    return text_response, meta


# ============================================================================
# Per-task worker
# ============================================================================

def _attempt_whole_file(
    task: dict, *, model: str, max_budget_usd: float, timeout: int, image: str,
) -> tuple[str, dict, str, str | None]:
    """Run whole-file mode once.

    Returns: (claude_text, meta, diff, diff_gen_error).
    """
    prompt = _build_prompt_whole_file(task)
    claude_text, meta = _invoke_claude(
        prompt, model=model, max_budget_usd=max_budget_usd, timeout=timeout,
    )
    files = _parse_whole_file_blocks(claude_text)
    if not files:
        return claude_text, meta, "", "no file blocks (or NO_FIX)"
    diff, gen_err = _generate_unified_diff_from_files(
        files, image=image, repo=task["repo"], base_commit=task["base_commit"],
    )
    return claude_text, meta, diff, gen_err


def _attempt_unified_diff(
    task: dict, *, model: str, max_budget_usd: float, timeout: int,
) -> tuple[str, dict, str, str | None]:
    """Run unified-diff mode once.

    Returns: (claude_text, meta, diff, diff_gen_error).
    """
    prompt = _build_prompt_unified(task)
    claude_text, meta = _invoke_claude(
        prompt, model=model, max_budget_usd=max_budget_usd, timeout=timeout,
    )
    diff = _extract_unified_diff(claude_text)
    err = None if diff.strip() else "no diff extracted"
    return claude_text, meta, diff, err


def _save_raw_safe(save_raw_dir: Path | None, instance_id: str, suffix: str, text: str) -> None:
    if save_raw_dir is None or not text:
        return
    try:
        save_raw_dir.mkdir(parents=True, exist_ok=True)
        (save_raw_dir / f"{instance_id}{suffix}").write_text(text, encoding="utf-8")
    except OSError:
        pass


# Hybrid mode: whole-file step A timeout (rest of budget goes to unified-diff fallback).
# Override via --whole-file-timeout-sec.
DEFAULT_WHOLE_FILE_TIMEOUT_SEC = 600
MIN_FALLBACK_TIMEOUT_SEC = 180


def _process_task(
    task: dict,
    *,
    model: str,
    patch_mode: str,
    per_task_cost_cap_usd: float,
    per_task_timeout_sec: int,
    apply_only: bool,
    image: str,
    save_raw_dir: Path | None,
    whole_file_timeout_sec: int = DEFAULT_WHOLE_FILE_TIMEOUT_SEC,
) -> dict:
    """1 task: prompt → claude → diff 生成 → score。result dict を返す。

    patch_mode:
      - whole-file:   1 attempt, whole-file mode
      - unified-diff: 1 attempt, unified-diff mode
      - hybrid:       Step A whole-file (timeout=min(whole_file_timeout_sec, per_task_timeout_sec))
                      → on empty/timeout: Step B unified-diff (remaining budget)
    """
    instance_id = task["instance_id"]

    attempt_history: list[dict] = []
    used_mode = patch_mode
    diff = ""
    diff_gen_error: str | None = None
    final_meta: dict = {"cost_usd": 0.0}
    final_claude_text = ""
    t0 = time.time()

    if patch_mode == "whole-file":
        claude_text, meta, diff, diff_gen_error = _attempt_whole_file(
            task, model=model,
            max_budget_usd=per_task_cost_cap_usd,
            timeout=per_task_timeout_sec,
            image=image,
        )
        final_meta = meta
        final_claude_text = claude_text
        attempt_history.append({
            "mode": "whole-file", "diff_chars": len(diff),
            "cost_usd": float(meta.get("cost_usd", 0.0)),
            "error": meta.get("error") or diff_gen_error,
        })
        _save_raw_safe(save_raw_dir, instance_id, ".whole-file.txt", claude_text)

    elif patch_mode == "unified-diff":
        claude_text, meta, diff, diff_gen_error = _attempt_unified_diff(
            task, model=model,
            max_budget_usd=per_task_cost_cap_usd,
            timeout=per_task_timeout_sec,
        )
        final_meta = meta
        final_claude_text = claude_text
        attempt_history.append({
            "mode": "unified-diff", "diff_chars": len(diff),
            "cost_usd": float(meta.get("cost_usd", 0.0)),
            "error": meta.get("error") or diff_gen_error,
        })
        _save_raw_safe(save_raw_dir, instance_id, ".unified-diff.txt", claude_text)

    elif patch_mode == "hybrid":
        # Step A: whole-file
        wf_timeout = min(whole_file_timeout_sec, per_task_timeout_sec)
        wf_text, wf_meta, wf_diff, wf_err = _attempt_whole_file(
            task, model=model,
            max_budget_usd=per_task_cost_cap_usd,
            timeout=wf_timeout,
            image=image,
        )
        wf_elapsed = time.time() - t0
        attempt_history.append({
            "mode": "whole-file", "diff_chars": len(wf_diff),
            "cost_usd": float(wf_meta.get("cost_usd", 0.0)),
            "elapsed_sec": round(wf_elapsed, 2),
            "error": wf_meta.get("error") or wf_err,
        })
        _save_raw_safe(save_raw_dir, instance_id, ".whole-file.txt", wf_text)

        if wf_diff.strip():
            # Step A succeeded; commit it.
            used_mode = "hybrid:whole-file"
            diff = wf_diff
            diff_gen_error = wf_err
            final_meta = wf_meta
            final_claude_text = wf_text
        else:
            # Step B: unified-diff fallback. Budget = remaining wall time, min 180s.
            remaining = per_task_timeout_sec - int(wf_elapsed)
            ud_timeout = max(remaining, MIN_FALLBACK_TIMEOUT_SEC)
            # Per-task cost cap subtracts what whole-file already burned.
            wf_cost = float(wf_meta.get("cost_usd", 0.0))
            ud_budget = max(per_task_cost_cap_usd - wf_cost, 0.10)
            ud_text, ud_meta, ud_diff, ud_err = _attempt_unified_diff(
                task, model=model,
                max_budget_usd=ud_budget,
                timeout=ud_timeout,
            )
            attempt_history.append({
                "mode": "unified-diff", "diff_chars": len(ud_diff),
                "cost_usd": float(ud_meta.get("cost_usd", 0.0)),
                "elapsed_sec": round(time.time() - t0 - wf_elapsed, 2),
                "error": ud_meta.get("error") or ud_err,
            })
            _save_raw_safe(save_raw_dir, instance_id, ".unified-diff.txt", ud_text)

            if ud_diff.strip():
                used_mode = "hybrid:unified-diff"
                diff = ud_diff
                diff_gen_error = ud_err
            else:
                used_mode = "hybrid:failed"
                diff = ""
                diff_gen_error = (
                    f"both attempts failed (whole-file: {wf_err or wf_meta.get('error')}; "
                    f"unified-diff: {ud_err or ud_meta.get('error')})"
                )

            # Aggregate meta (cost is sum of both attempts).
            final_meta = {
                "cost_usd": wf_cost + float(ud_meta.get("cost_usd", 0.0)),
                "duration_ms": int(wf_meta.get("duration_ms", 0)) + int(ud_meta.get("duration_ms", 0)),
                "rc": ud_meta.get("rc", wf_meta.get("rc")),
            }
            err_a = wf_meta.get("error")
            err_b = ud_meta.get("error")
            if err_a or err_b:
                final_meta["error"] = err_b or err_a
            final_claude_text = ud_text or wf_text

    else:
        raise ValueError(f"unknown patch_mode: {patch_mode}")

    invoke_dur = time.time() - t0
    final_meta["attempt_history"] = attempt_history

    # Save the final adopted patch for forensics.
    if save_raw_dir is not None:
        _save_raw_safe(save_raw_dir, instance_id, ".txt", final_claude_text)
        if diff:
            _save_raw_safe(save_raw_dir, instance_id, ".patch", diff)

    score = score_task(
        task, diff,
        image=image,
        apply_only=apply_only,
        timeout=per_task_timeout_sec,
    )

    return {
        "instance_id": instance_id,
        "repo": task["repo"],
        "model": model,
        "patch_mode": patch_mode,
        "used_mode": used_mode,
        "invoke_duration_sec": round(invoke_dur, 2),
        "claude_meta": final_meta,
        "diff_chars": len(diff),
        "diff_gen_error": diff_gen_error,
        "score": score.to_dict(),
    }


# ============================================================================
# Resume support
# ============================================================================

def _load_existing_results(path: Path) -> dict[str, dict]:
    """既存 results.json から instance_id -> result の dict を返す。"""
    if not path.exists():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    out: dict[str, dict] = {}
    for r in data.get("results", []):
        iid = r.get("instance_id")
        if iid:
            out[iid] = r
    return out


def _atomic_write(path: Path, payload: dict) -> None:
    """temp file → rename で原子的に書き込み。"""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=f".{path.name}.", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(payload, f, ensure_ascii=False, indent=2)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# ============================================================================
# main
# ============================================================================

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tasks", required=True)
    ap.add_argument("--limit", type=int, default=int(CFG.get("default_limit", 5)))
    ap.add_argument("--model", default=CFG.get("model", "claude-sonnet-4-6"))
    ap.add_argument("--output", required=True)
    ap.add_argument("--cost-cap-usd", type=float, default=float(CFG.get("cost_cap_usd", 5.0)))
    ap.add_argument("--per-task-cost-cap-usd", type=float, default=float(CFG.get("per_task_cost_cap_usd", 1.0)))
    ap.add_argument("--per-task-timeout-sec", type=int, default=int(CFG.get("per_task_timeout_sec", 300)))
    ap.add_argument("--apply-only", action="store_true", default=bool(CFG.get("apply_patch_only", True)))
    ap.add_argument("--image", default=CFG.get("docker_image", "swe-bench-sandbox"))
    ap.add_argument(
        "--patch-mode",
        choices=["whole-file", "unified-diff", "hybrid"],
        default=CFG.get("patch_mode", "whole-file"),
        help=(
            "whole-file: claude returns full file content, runner generates diff via difflib. "
            "unified-diff: claude writes the diff directly. "
            "hybrid: try whole-file first; on timeout/empty fall back to unified-diff (recommended)."
        ),
    )
    ap.add_argument(
        "--whole-file-timeout-sec", type=int,
        default=int(CFG.get("whole_file_timeout_sec", 600)),
        help="hybrid mode only: timeout for the whole-file step A (the rest of per-task budget goes to unified-diff fallback).",
    )
    ap.add_argument("--resume", type=str, default=None,
                    help="既存 results.json (--output と同じファイルでも別でも可) を読み完了 task をスキップ")
    ap.add_argument("--parallel", type=int, default=int(CFG.get("parallel", 1)),
                    help="同時実行数。1 で逐次。")
    ap.add_argument("--save-raw", action="store_true",
                    help="claude 生出力 / 生成 patch を results/raw/ に保存（forensic 用）")
    args = ap.parse_args()

    tasks_path = Path(args.tasks)
    if tasks_path.suffix == ".jsonl":
        with tasks_path.open("r", encoding="utf-8") as f:
            tasks = [json.loads(line) for line in f if line.strip()]
    else:
        tasks = json.loads(tasks_path.read_text(encoding="utf-8"))
    tasks = tasks[: args.limit]

    if not tasks:
        print("[error] no tasks loaded", file=sys.stderr)
        return 1

    out_path = Path(args.output)
    resume_path = Path(args.resume) if args.resume else out_path
    existing = _load_existing_results(resume_path) if (args.resume or out_path.exists()) else {}
    skipped_ids = set(existing.keys())

    todo = [t for t in tasks if t["instance_id"] not in skipped_ids]

    print(
        f"[start] runner: {len(tasks)} tasks total, {len(skipped_ids)} resumed, {len(todo)} to run | "
        f"model={args.model} mode={args.patch_mode} parallel={args.parallel} cap=${args.cost_cap_usd}",
        file=sys.stderr,
    )
    started_at = datetime.utcnow().isoformat() + "Z"

    raw_dir = out_path.parent / "raw" if args.save_raw else None

    # carry forward resumed results
    results: list[dict] = list(existing.values())
    cumulative_cost = sum(float(r.get("claude_meta", {}).get("cost_usd", 0.0)) for r in results)
    cap_hit = False

    def _flush() -> None:
        summary = _build_summary(
            tasks, results, started_at, args, cumulative_cost, cap_hit,
        )
        _atomic_write(out_path, {"summary": summary, "results": results})

    if args.parallel <= 1:
        # 逐次
        for i, task in enumerate(todo, start=1):
            iid = task["instance_id"]
            print(f"\n[task {i}/{len(todo)}] {iid}", file=sys.stderr)
            if cumulative_cost >= args.cost_cap_usd:
                cap_hit = True
                print(f"[cap-hit] cum=${cumulative_cost:.4f} >= cap=${args.cost_cap_usd}, stop", file=sys.stderr)
                break
            r = _process_task(
                task,
                model=args.model,
                patch_mode=args.patch_mode,
                per_task_cost_cap_usd=args.per_task_cost_cap_usd,
                per_task_timeout_sec=args.per_task_timeout_sec,
                apply_only=args.apply_only,
                image=args.image,
                save_raw_dir=raw_dir,
                whole_file_timeout_sec=args.whole_file_timeout_sec,
            )
            cumulative_cost += float(r["claude_meta"].get("cost_usd", 0.0))
            r["cumulative_cost_usd"] = round(cumulative_cost, 6)
            results.append(r)
            _flush()
            print(
                f"  -> applies={r['score']['patch_applies']} "
                f"cost=${r['claude_meta'].get('cost_usd', 0):.4f} "
                f"cum=${cumulative_cost:.4f} dur={r['invoke_duration_sec']}s",
                file=sys.stderr,
            )
    else:
        # 並列
        # 注意: cost cap は worker 完了時にチェック。in-flight は止められないが
        #       per-task cap で 1 task 上限はあり、worst case は parallel × per_task_cost_cap_usd オーバー。
        with cf.ProcessPoolExecutor(max_workers=args.parallel) as pool:
            future_to_task = {
                pool.submit(
                    _process_task,
                    t,
                    model=args.model,
                    patch_mode=args.patch_mode,
                    per_task_cost_cap_usd=args.per_task_cost_cap_usd,
                    per_task_timeout_sec=args.per_task_timeout_sec,
                    apply_only=args.apply_only,
                    image=args.image,
                    save_raw_dir=raw_dir,
                    whole_file_timeout_sec=args.whole_file_timeout_sec,
                ): t
                for t in todo
            }
            done_count = 0
            for fut in cf.as_completed(future_to_task):
                t = future_to_task[fut]
                done_count += 1
                try:
                    r = fut.result()
                except Exception as e:  # noqa: BLE001
                    r = {
                        "instance_id": t["instance_id"], "repo": t["repo"],
                        "model": args.model, "patch_mode": args.patch_mode,
                        "used_mode": args.patch_mode + ":exception",
                        "invoke_duration_sec": 0.0,
                        "claude_meta": {"cost_usd": 0.0, "error": str(e)[:300], "attempt_history": []},
                        "diff_chars": 0, "diff_gen_error": str(e)[:300],
                        "score": {
                            "task_id": t["instance_id"], "patch_generated": False,
                            "patch_applies": False, "apply_error": str(e)[:300],
                            "tests_run": False, "tests_passed": 0, "tests_failed": 0,
                            "test_log_excerpt": "", "duration_sec": 0.0,
                        },
                    }
                cumulative_cost += float(r.get("claude_meta", {}).get("cost_usd", 0.0))
                r["cumulative_cost_usd"] = round(cumulative_cost, 6)
                results.append(r)
                _flush()
                print(
                    f"[done {done_count}/{len(todo)}] {r['instance_id']} "
                    f"applies={r['score']['patch_applies']} "
                    f"cost=${r['claude_meta'].get('cost_usd', 0):.4f} cum=${cumulative_cost:.4f}",
                    file=sys.stderr,
                )
                if cumulative_cost >= args.cost_cap_usd:
                    cap_hit = True
                    print(f"[cap-hit] cum=${cumulative_cost:.4f} >= cap, cancelling pending futures", file=sys.stderr)
                    for f2 in future_to_task:
                        if not f2.done():
                            f2.cancel()
                    break

    _flush()
    print(f"\n[done] wrote {out_path}", file=sys.stderr)
    summary = _build_summary(tasks, results, started_at, args, cumulative_cost, cap_hit)
    print(
        f"[summary] applied={summary['patch_applied_count']}/{summary['tasks_run']} "
        f"({summary['applied_rate']:.0%}) cost=${summary['cumulative_cost_usd']}",
        file=sys.stderr,
    )
    return 0


def _build_summary(tasks, results, started_at, args, cumulative_cost, cap_hit):
    n_run = len(results)
    applied = sum(1 for r in results if r["score"].get("patch_applies"))
    resolved = sum(
        1 for r in results
        if r["score"].get("patch_applies") and r["score"].get("tests_run")
        and r["score"].get("tests_passed", 0) > 0 and r["score"].get("tests_failed", 0) == 0
    )

    # Mode breakdown for hybrid forensics.
    mode_breakdown: dict[str, dict[str, int]] = {}
    for r in results:
        used = r.get("used_mode") or r.get("patch_mode") or "unknown"
        slot = mode_breakdown.setdefault(used, {"selected": 0, "applied": 0})
        slot["selected"] += 1
        if r["score"].get("patch_applies"):
            slot["applied"] += 1

    # Aggregate fallback signal: count attempts per mode in attempt_history.
    attempt_counts: dict[str, int] = {}
    for r in results:
        for a in r.get("claude_meta", {}).get("attempt_history", []) or []:
            mode = a.get("mode", "unknown")
            attempt_counts[mode] = attempt_counts.get(mode, 0) + 1

    return {
        "started_at": started_at,
        "finished_at": datetime.utcnow().isoformat() + "Z",
        "model": args.model,
        "patch_mode": args.patch_mode,
        "whole_file_timeout_sec": getattr(args, "whole_file_timeout_sec", None),
        "per_task_timeout_sec": args.per_task_timeout_sec,
        "parallel": args.parallel,
        "tasks_total": len(tasks),
        "tasks_run": n_run,
        "patch_generated_count": sum(1 for r in results if r["score"].get("patch_generated")),
        "patch_applied_count": applied,
        "applied_rate": round(applied / n_run, 3) if n_run else 0.0,
        "resolved_count": resolved,
        "resolved_rate": round(resolved / n_run, 3) if n_run else 0.0,
        "cumulative_cost_usd": round(cumulative_cost, 6),
        "cost_cap_usd": args.cost_cap_usd,
        "cost_cap_hit": cap_hit,
        "apply_only": args.apply_only,
        "mode_breakdown": mode_breakdown,
        "attempt_counts": attempt_counts,
    }


if __name__ == "__main__":
    sys.exit(main())
