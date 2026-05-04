#!/usr/bin/env python3
"""SWE-bench Lite メタデータを HuggingFace dataset viewer API 経由で取得。

依存ゼロ (urllib のみ)。300 task を 100 件ずつ 3 回叩いて lite-300.jsonl に保存し、
先頭 50 task を lite-50.json として subset 化する。

Usage:
    python3 tasks/fetch_tasks.py
    python3 tasks/fetch_tasks.py --refresh   # 既存ファイルを上書き
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://datasets-server.huggingface.co/rows"
DATASET = "princeton-nlp/SWE-bench_Lite"
PAGE_SIZE = 100
TOTAL = 300
TASKS_DIR = Path(__file__).resolve().parent
JSONL_PATH = TASKS_DIR / "lite-300.jsonl"
SUBSET_PATH = TASKS_DIR / "lite-50.json"
SUBSET_N = 50


def fetch_page(offset: int, length: int) -> list[dict]:
    qs = urllib.parse.urlencode(
        {
            "dataset": DATASET,
            "config": "default",
            "split": "test",
            "offset": offset,
            "length": length,
        }
    )
    url = f"{API}?{qs}"
    req = urllib.request.Request(url, headers={"User-Agent": "claude-code-harness/1.0"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        if resp.status != 200:
            raise RuntimeError(f"HTTP {resp.status} for {url}")
        return json.loads(resp.read().decode("utf-8"))["rows"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true")
    args = ap.parse_args()

    if JSONL_PATH.exists() and not args.refresh:
        print(f"[skip] {JSONL_PATH} already exists. use --refresh to overwrite.")
    else:
        all_rows: list[dict] = []
        for offset in range(0, TOTAL, PAGE_SIZE):
            print(f"[fetch] offset={offset} length={PAGE_SIZE}", file=sys.stderr)
            rows = fetch_page(offset, PAGE_SIZE)
            all_rows.extend(r["row"] for r in rows)
            time.sleep(0.5)  # be polite
        with JSONL_PATH.open("w", encoding="utf-8") as f:
            for r in all_rows:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print(f"[done] wrote {len(all_rows)} tasks to {JSONL_PATH}")

    # subset = 先頭 50 task (deterministic; 後で shuffle 戦略は別タスク)
    rows = []
    with JSONL_PATH.open("r", encoding="utf-8") as f:
        for i, line in enumerate(f):
            if i >= SUBSET_N:
                break
            rows.append(json.loads(line))
    SUBSET_PATH.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[done] wrote {len(rows)}-task subset to {SUBSET_PATH}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
