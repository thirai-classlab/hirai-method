#!/usr/bin/env python3
"""SWE-bench task patch を Docker sandbox で適用 + (任意で) FAIL_TO_PASS test 実行。

Phase C-1.5 拡張:
- apply_only=False の場合に FAIL_TO_PASS テストを軽量実行する path を追加。
  公式 swebench harness は per-instance Docker image (multi-GB / 数百種類) を引いてくるため
  cost / 時間が爆発する。ここでは「同じ swe-bench-sandbox image 内で repo を pip install し
  pytest <FAIL_TO_PASS testid>」する簡易実装で signal を取る。
- 公式 swebench harness 統合は score_with_official_harness() に分離。
  本番 (Phase C-2) で `--use-official-harness` を渡したときのみ呼び出す想定。
"""
from __future__ import annotations

import json
import shlex
import subprocess
import tempfile
import time
from dataclasses import dataclass, asdict, field
from pathlib import Path


@dataclass
class ScoreResult:
    task_id: str
    patch_generated: bool
    patch_applies: bool
    apply_error: str | None
    tests_run: bool
    tests_passed: int
    tests_failed: int
    test_log_excerpt: str
    duration_sec: float
    fail_to_pass_total: int = 0
    pass_to_pass_total: int = 0
    pass_to_pass_passed: int = 0

    def to_dict(self) -> dict:
        return asdict(self)


def _run(cmd: list[str], cwd: str | None = None, timeout: int = 60) -> tuple[int, str, str]:
    proc = subprocess.run(
        cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout
    )
    return proc.returncode, proc.stdout, proc.stderr


def _docker_run_script(image: str, script: str, mounts: dict[str, str], timeout: int = 600) -> tuple[int, str, str]:
    """1 ショットで bash -lc <script> を docker 実行。"""
    cmd = ["docker", "run", "--rm", "--network=bridge"]
    for h, c in mounts.items():
        cmd.extend(["-v", f"{h}:{c}"])
    cmd.extend(["-w", "/work", image, "bash", "-lc", script])
    return _run(cmd, timeout=timeout)


def score_task(
    task: dict,
    model_patch: str,
    image: str = "swe-bench-sandbox",
    apply_only: bool = True,
    timeout: int = 300,
) -> ScoreResult:
    """1 task を採点。apply_only=False のとき FAIL_TO_PASS test を実行。"""
    start = time.time()
    instance_id = task["instance_id"]
    repo = task["repo"]
    base_commit = task["base_commit"]

    if not model_patch.strip():
        return ScoreResult(
            task_id=instance_id,
            patch_generated=False,
            patch_applies=False,
            apply_error="empty patch",
            tests_run=False,
            tests_passed=0,
            tests_failed=0,
            test_log_excerpt="",
            duration_sec=time.time() - start,
        )

    fail_to_pass = task.get("FAIL_TO_PASS") or []
    pass_to_pass = task.get("PASS_TO_PASS") or []
    if isinstance(fail_to_pass, str):
        try:
            fail_to_pass = json.loads(fail_to_pass)
        except json.JSONDecodeError:
            fail_to_pass = [fail_to_pass]
    if isinstance(pass_to_pass, str):
        try:
            pass_to_pass = json.loads(pass_to_pass)
        except json.JSONDecodeError:
            pass_to_pass = [pass_to_pass]

    with tempfile.TemporaryDirectory(prefix="swebench-") as tmp:
        host_dir = Path(tmp)
        patch_path = host_dir / "model.patch"
        patch_path.write_text(model_patch, encoding="utf-8")

        # 1) clone + checkout + apply (single docker run)
        clone_apply = (
            f"set -e; "
            f"git clone --quiet --no-tags https://github.com/{repo}.git src && "
            f"cd src && git checkout --quiet {base_commit} && "
            f"git apply --check ../model.patch && git apply ../model.patch"
        )
        rc, out, err = _docker_run_script(
            image, clone_apply,
            mounts={str(host_dir): "/work"},
            timeout=180,
        )
        patch_applies = rc == 0
        apply_error = None if patch_applies else (err or out)[:500]

        if not patch_applies or apply_only:
            return ScoreResult(
                task_id=instance_id,
                patch_generated=True,
                patch_applies=patch_applies,
                apply_error=apply_error,
                tests_run=False,
                tests_passed=0,
                tests_failed=0,
                test_log_excerpt="",
                duration_sec=time.time() - start,
                fail_to_pass_total=len(fail_to_pass),
                pass_to_pass_total=len(pass_to_pass),
            )

        # 2) FAIL_TO_PASS テスト実行 (軽量: pip install -e . then pytest <ids>)
        return _run_tests_lightweight(
            instance_id, repo, base_commit, model_patch,
            fail_to_pass, pass_to_pass,
            image, host_dir, timeout, start,
        )


def _run_tests_lightweight(
    instance_id: str,
    repo: str,
    base_commit: str,
    model_patch: str,
    fail_to_pass: list[str],
    pass_to_pass: list[str],
    image: str,
    host_dir: Path,
    timeout: int,
    start: float,
) -> ScoreResult:
    """軽量 test 実行: 同じ sandbox 内で repo を install し pytest を呼ぶ。

    制約: 各 repo の依存解決が走るため初回 task は 5-15 分かかる。Phase C-1.5 dry-run で
    apply_only=True を維持し、本機能は --apply-only=false 時だけ動く。
    """
    f2p_args = " ".join(shlex.quote(t) for t in fail_to_pass[:20])  # safety cap
    p2p_args = " ".join(shlex.quote(t) for t in pass_to_pass[:10])

    test_script = (
        f"set -e; cd src; "
        # try pip install with multiple fallbacks
        f"(pip install --quiet -e . 2>/dev/null || "
        f" pip install --quiet . 2>/dev/null || "
        f" pip install --quiet -r requirements.txt 2>/dev/null || true); "
        f"echo '=== FAIL_TO_PASS ==='; "
        f"pytest -x --tb=short -q {f2p_args} 2>&1 | tail -200 || true; "
        f"echo '=== PASS_TO_PASS ==='; "
        f"pytest -x --tb=short -q {p2p_args} 2>&1 | tail -100 || true; "
    )
    rc, out, err = _docker_run_script(
        image, test_script,
        mounts={str(host_dir): "/work"},
        timeout=max(timeout, 900),
    )

    log = (out or "") + ("\n" + err if err else "")
    excerpt = log[-2000:]

    f2p_passed, f2p_failed = _parse_pytest_summary(_section(log, "=== FAIL_TO_PASS ===", "=== PASS_TO_PASS ==="))
    p2p_passed, _p2p_failed = _parse_pytest_summary(_section(log, "=== PASS_TO_PASS ===", None))

    return ScoreResult(
        task_id=instance_id,
        patch_generated=True,
        patch_applies=True,
        apply_error=None,
        tests_run=True,
        tests_passed=f2p_passed,
        tests_failed=f2p_failed,
        test_log_excerpt=excerpt,
        duration_sec=time.time() - start,
        fail_to_pass_total=len(fail_to_pass),
        pass_to_pass_total=len(pass_to_pass),
        pass_to_pass_passed=p2p_passed,
    )


def _section(log: str, start_marker: str, end_marker: str | None) -> str:
    a = log.find(start_marker)
    if a < 0:
        return ""
    a += len(start_marker)
    if end_marker is None:
        return log[a:]
    b = log.find(end_marker, a)
    return log[a:b] if b >= 0 else log[a:]


def _parse_pytest_summary(section: str) -> tuple[int, int]:
    """pytest -q 出力から passed / failed を抽出。"""
    if not section:
        return 0, 0
    import re
    passed = 0
    failed = 0
    # patterns like "5 passed", "3 failed", "1 error", "2 passed, 1 failed"
    for m in re.finditer(r"(\d+)\s+(passed|failed|error|errors)", section):
        n = int(m.group(1))
        kind = m.group(2)
        if kind == "passed":
            passed += n
        elif kind in ("failed", "error", "errors"):
            failed += n
    return passed, failed


# ============================================================================
# Official swebench harness integration (opt-in, Phase C-2)
# ============================================================================

def score_with_official_harness(
    predictions_jsonl: Path,
    instance_ids: list[str],
    run_id: str,
    workers: int = 2,
    timeout: int = 1800,
) -> dict:
    """公式 swebench harness を呼び `resolved` 判定を取る。

    predictions_jsonl は SWE-bench 標準形式:
      {"instance_id": "...", "model_name_or_path": "...", "model_patch": "..."}
    各行 1 task。

    出力: 公式 harness が生成する `<run_id>.<model>.json` を読み込み、
    {instance_id: resolved (bool)} の dict を返す。
    """
    try:
        from swebench.harness.run_evaluation import main as run_eval_main
    except ImportError as e:
        return {"error": f"swebench package not installed: {e}"}

    # 公式 main() は最後にレポート JSON を吐く。CWD に出る。
    try:
        run_eval_main(
            dataset_name="princeton-nlp/SWE-bench_Lite",
            split="test",
            instance_ids=instance_ids,
            predictions_path=str(predictions_jsonl),
            max_workers=workers,
            force_rebuild=False,
            cache_level="env",
            clean=False,
            open_file_limit=4096,
            run_id=run_id,
            timeout=timeout,
            namespace="swebench",  # public dockerhub namespace for prebuilt images
            rewrite_reports=False,
            modal=False,
            instance_image_tag="latest",
            env_image_tag="latest",
            report_dir=".",
        )
    except Exception as e:  # noqa: BLE001
        return {"error": f"official harness raised: {e}"}

    # find report json
    cwd = Path.cwd()
    reports = list(cwd.glob(f"*{run_id}*.json"))
    if not reports:
        return {"error": "no report json produced"}
    report = reports[0]
    try:
        data = json.loads(report.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as e:
        return {"error": f"report parse failed: {e}"}
    return {
        "report_file": str(report),
        "resolved_ids": data.get("resolved_ids", []),
        "unresolved_ids": data.get("unresolved_ids", []),
        "submitted_instances": data.get("submitted_instances", 0),
        "completed_instances": data.get("completed_instances", 0),
    }


if __name__ == "__main__":
    import sys
    print("scoring.py is a library; import score_task from runner.py", file=sys.stderr)
