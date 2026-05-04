#!/usr/bin/env python3
"""
instinct-cli.py — Continuous Learning v2.1 management CLI

Subcommands:
  status         project + global instincts 一覧
  projects       既知プロジェクト一覧
  evolve         関連 instinct クラスタ → skill/command/agent 候補
  promote        project → global 昇格
  export         instinct を JSON/YAML へ
  import         instinct を読み込み
  observe-analyze  観察ログから instinct 候補を抽出（Haiku 不要のヒューリスティック版）

設計:
  - 標準ライブラリのみ（外部依存なし、Python 3.10+）
  - YAML フロントマター + Markdown 本文の instinct 形式
  - HOMUNCULUS_DIR 環境変数で保存先を上書き可
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

HOMUNCULUS_DIR = Path(os.environ.get("HOMUNCULUS_DIR", str(Path.home() / ".claude" / "homunculus")))


# ---------- helpers ----------

def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ensure_dirs() -> None:
    for sub in ("instincts/personal", "instincts/inherited",
                "evolved/skills", "evolved/commands", "evolved/agents", "projects"):
        (HOMUNCULUS_DIR / sub).mkdir(parents=True, exist_ok=True)


def read_instinct(path: Path) -> dict | None:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return None
    m = re.match(r"^---\n(.*?)\n---\n(.*)$", text, re.DOTALL)
    if not m:
        return None
    fm_raw, body = m.groups()
    meta: dict = {}
    for line in fm_raw.splitlines():
        if ":" in line:
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip().strip('"').strip("'")
    if "confidence" in meta:
        try:
            meta["confidence"] = float(meta["confidence"])
        except ValueError:
            meta["confidence"] = 0.3
    if "evidence_count" in meta:
        try:
            meta["evidence_count"] = int(meta["evidence_count"])
        except ValueError:
            meta["evidence_count"] = 1
    meta["body"] = body.strip()
    meta["_path"] = str(path)
    return meta


def write_instinct(path: Path, meta: dict) -> None:
    body = meta.pop("body", "")
    path_str = meta.pop("_path", None)
    keys_order = [
        "id", "trigger", "confidence", "domain", "source", "scope",
        "project_id", "project_name", "created_at", "updated_at", "evidence_count",
    ]
    fm_lines = ["---"]
    for k in keys_order:
        if k in meta:
            v = meta[k]
            if isinstance(v, float):
                fm_lines.append(f"{k}: {v:.2f}")
            else:
                fm_lines.append(f"{k}: {v}")
    fm_lines.append("---")
    fm_lines.append("")
    fm_lines.append(body or "")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(fm_lines) + "\n", encoding="utf-8")


def list_instincts(scope: str | None = None, project_id: str | None = None) -> list[dict]:
    out: list[dict] = []
    if scope in (None, "global"):
        for sub in ("instincts/personal", "instincts/inherited"):
            d = HOMUNCULUS_DIR / sub
            if d.exists():
                for f in sorted(d.glob("*.yaml")) + sorted(d.glob("*.md")):
                    inst = read_instinct(f)
                    if inst:
                        inst.setdefault("scope", "global")
                        out.append(inst)
    if scope in (None, "project"):
        proj_root = HOMUNCULUS_DIR / "projects"
        if proj_root.exists():
            for pdir in sorted(proj_root.iterdir()):
                if not pdir.is_dir():
                    continue
                if project_id and pdir.name != project_id:
                    continue
                for sub in ("instincts/personal", "instincts/inherited"):
                    d = pdir / sub
                    if d.exists():
                        for f in sorted(d.glob("*.yaml")) + sorted(d.glob("*.md")):
                            inst = read_instinct(f)
                            if inst:
                                inst.setdefault("scope", "project")
                                inst.setdefault("project_id", pdir.name)
                                out.append(inst)
    return out


def load_projects_registry() -> dict:
    f = HOMUNCULUS_DIR / "projects.json"
    if not f.exists():
        return {}
    try:
        return json.loads(f.read_text(encoding="utf-8"))
    except Exception:
        return {}


# ---------- commands ----------

def cmd_status(args: argparse.Namespace) -> int:
    insts = list_instincts()
    if not insts:
        print("(no instincts yet — observe more sessions or run /learn)")
        return 0

    by_scope: dict[str, list[dict]] = defaultdict(list)
    for i in insts:
        by_scope[i.get("scope", "global")].append(i)

    for scope in ("global", "project"):
        items = by_scope.get(scope, [])
        if not items:
            continue
        print(f"\n=== {scope.upper()} ({len(items)}) ===")
        for i in sorted(items, key=lambda x: -x.get("confidence", 0)):
            conf = i.get("confidence", 0)
            bar = "█" * int(conf * 10) + "░" * (10 - int(conf * 10))
            pid = i.get("project_id", "")
            pname = i.get("project_name", "")
            proj = f" [{pname or pid[:6]}]" if scope == "project" else ""
            print(f"  {bar} {conf:.2f}  {i.get('id', '?'):<35} ({i.get('domain', '?')}){proj}")
    return 0


def cmd_projects(args: argparse.Namespace) -> int:
    reg = load_projects_registry()
    if not reg:
        print("(no projects observed yet)")
        return 0

    print(f"{'HASH':<14} {'NAME':<30} {'INSTINCTS':>10} {'LAST_SEEN':<22}")
    print("-" * 80)
    for pid, info in sorted(reg.items(), key=lambda x: x[1].get("last_seen", ""), reverse=True):
        n = len(list_instincts(scope="project", project_id=pid))
        print(f"{pid:<14} {(info.get('name') or '?'):<30} {n:>10} {info.get('last_seen', '?'):<22}")
    return 0


def cmd_evolve(args: argparse.Namespace) -> int:
    """Cluster related instincts and suggest skill/command/agent generation."""
    insts = list_instincts()
    if len(insts) < 3:
        print("(need at least 3 instincts to cluster)")
        return 0

    clusters: dict[str, list[dict]] = defaultdict(list)
    for i in insts:
        clusters[i.get("domain", "unknown")].append(i)

    print("=== Evolution Candidates ===\n")
    for domain, items in clusters.items():
        if len(items) < 2:
            continue
        avg_conf = sum(x.get("confidence", 0) for x in items) / len(items)
        print(f"[{domain}] {len(items)} instincts, avg conf {avg_conf:.2f}")
        for i in items:
            print(f"  - {i.get('id', '?')} ({i.get('confidence', 0):.2f})")
        if avg_conf >= 0.7:
            kind = "skill" if len(items) >= 4 else "command"
            target = HOMUNCULUS_DIR / "evolved" / f"{kind}s" / f"{domain}-cluster.md"
            print(f"  → 推奨: {kind} を生成 → {target}")
        print()

    print("\n手動生成: instinct ID を ./instinct-cli.py export し、Claude に skill/command 化を依頼。")
    return 0


def cmd_promote(args: argparse.Namespace) -> int:
    insts = list_instincts(scope="project")
    if not insts:
        print("(no project-scoped instincts)")
        return 0

    by_id: dict[str, list[dict]] = defaultdict(list)
    for i in insts:
        by_id[i.get("id", "")].append(i)

    candidates: list[tuple[str, list[dict], float]] = []
    for iid, group in by_id.items():
        if not iid:
            continue
        if len(group) < 2:
            continue
        avg_conf = sum(g.get("confidence", 0) for g in group) / len(group)
        if avg_conf >= 0.8:
            candidates.append((iid, group, avg_conf))

    if args.target:
        candidates = [c for c in candidates if c[0] == args.target]

    if not candidates:
        print("(no promotion candidates — need same id in 2+ projects with avg conf ≥0.8)")
        return 0

    print(f"=== Promotion Candidates ({len(candidates)}) ===\n")
    for iid, group, avg in candidates:
        print(f"  {iid}  avg={avg:.2f}  projects={len(group)}")
        if args.dry_run:
            continue
        # 最高 confidence の instinct を global へコピー
        best = max(group, key=lambda x: x.get("confidence", 0))
        global_path = HOMUNCULUS_DIR / "instincts" / "personal" / f"{iid}.md"
        meta = dict(best)
        meta["scope"] = "global"
        meta.pop("project_id", None)
        meta.pop("project_name", None)
        meta["updated_at"] = now_iso()
        write_instinct(global_path, meta)
        print(f"    → promoted to {global_path}")

    if args.dry_run:
        print("\n(dry-run — no changes written)")
    return 0


def cmd_export(args: argparse.Namespace) -> int:
    insts = list_instincts(scope=args.scope, project_id=args.project_id)
    if args.domain:
        insts = [i for i in insts if i.get("domain") == args.domain]
    out = {
        "version": "2.1",
        "exported_at": now_iso(),
        "count": len(insts),
        "instincts": [{k: v for k, v in i.items() if not k.startswith("_")} for i in insts],
    }
    text = json.dumps(out, indent=2, ensure_ascii=False)
    if args.output:
        Path(args.output).write_text(text, encoding="utf-8")
        print(f"exported {len(insts)} instincts → {args.output}")
    else:
        print(text)
    return 0


def cmd_import(args: argparse.Namespace) -> int:
    f = Path(args.file)
    if not f.exists():
        print(f"file not found: {f}", file=sys.stderr)
        return 2
    try:
        data = json.loads(f.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"failed to parse JSON: {e}", file=sys.stderr)
        return 2

    target_scope = args.scope or "global"
    target_dir = HOMUNCULUS_DIR / "instincts" / "inherited"
    if target_scope == "project":
        if not args.project_id:
            print("--project-id required when --scope project", file=sys.stderr)
            return 2
        target_dir = HOMUNCULUS_DIR / "projects" / args.project_id / "instincts" / "inherited"

    target_dir.mkdir(parents=True, exist_ok=True)

    n = 0
    for inst in data.get("instincts", []):
        iid = inst.get("id")
        if not iid:
            continue
        meta = dict(inst)
        meta["source"] = "imported"
        meta["scope"] = target_scope
        meta["updated_at"] = now_iso()
        write_instinct(target_dir / f"{iid}.md", meta)
        n += 1
    print(f"imported {n} instincts → {target_dir}")
    return 0


def cmd_observe_analyze(args: argparse.Namespace) -> int:
    """軽量ヒューリスティック分析: observations.jsonl からパターン候補を抽出。

    本格実装は Haiku を呼ぶ background observer に委ねるが、
    Haiku が無い環境でも instinct 候補を出すための簡易版。
    """
    project_id = args.project_id
    if project_id:
        obs_file = HOMUNCULUS_DIR / "projects" / project_id / "observations.jsonl"
    else:
        obs_file = HOMUNCULUS_DIR / "observations.jsonl"

    if not obs_file.exists():
        print(f"observations file not found: {obs_file}")
        return 0

    tool_seq: list[str] = []
    tool_count: Counter = Counter()
    with obs_file.open(encoding="utf-8") as f:
        for line in f:
            try:
                rec = json.loads(line)
            except Exception:
                continue
            tool = rec.get("tool", "")
            if tool:
                tool_seq.append(tool)
                tool_count[tool] += 1

    if not tool_seq:
        print("(no tool calls observed)")
        return 0

    print(f"=== Observation Summary ({len(tool_seq)} tool calls) ===\n")
    print("Top tools:")
    for tool, n in tool_count.most_common(10):
        print(f"  {tool:<20} {n:>5}")

    # 連続パターン検出（bigram）
    bigrams = Counter()
    for a, b in zip(tool_seq, tool_seq[1:]):
        bigrams[(a, b)] += 1
    print("\nFrequent tool bigrams (≥3):")
    for (a, b), n in bigrams.most_common(10):
        if n >= 3:
            print(f"  {a:<15} → {b:<15} ×{n}")

    print("\n→ これらを基に instinct を手動作成するか、Haiku observer を有効化してください。")
    return 0


# ---------- main ----------

def main() -> int:
    ensure_dirs()
    p = argparse.ArgumentParser(prog="instinct-cli")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("status", help="show all instincts").set_defaults(func=cmd_status)
    sub.add_parser("projects", help="list known projects").set_defaults(func=cmd_projects)
    sub.add_parser("evolve", help="cluster instincts and suggest evolution").set_defaults(func=cmd_evolve)

    sp = sub.add_parser("promote", help="promote project instinct to global")
    sp.add_argument("target", nargs="?", help="instinct id (omit for all candidates)")
    sp.add_argument("--dry-run", action="store_true")
    sp.set_defaults(func=cmd_promote)

    sp = sub.add_parser("export", help="export instincts as JSON")
    sp.add_argument("--scope", choices=["global", "project"])
    sp.add_argument("--project-id")
    sp.add_argument("--domain")
    sp.add_argument("--output", "-o")
    sp.set_defaults(func=cmd_export)

    sp = sub.add_parser("import", help="import instincts from JSON")
    sp.add_argument("file")
    sp.add_argument("--scope", choices=["global", "project"], default="global")
    sp.add_argument("--project-id")
    sp.set_defaults(func=cmd_import)

    sp = sub.add_parser("observe-analyze", help="heuristic pattern extraction")
    sp.add_argument("--project-id")
    sp.set_defaults(func=cmd_observe_analyze)

    args = p.parse_args()
    try:
        return args.func(args) or 0
    except KeyboardInterrupt:
        return 130
    except Exception as e:
        print(f"error: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
