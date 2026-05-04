#!/usr/bin/env python3
"""agent-stocktake.py — `.claude/agents/` 配下のエージェント棚卸しレポート生成。

claude-code-harness の 144 agents（VoltAgent 由来 10 カテゴリ）について
- frontmatter (name / description / model / tools)
- 直近 N 日のサブエージェント起動回数（~/.claude/projects 走査）
- 機能カテゴリ・粒度（micro / medium / macro）の自動分類
- オーバーラップ候補（共通キーワード Jaccard）
- 削除候補フラグ（起動 0 + オーバーラップ + 適合度）

を集約して Markdown / JSON で出力する。読み取り専用・標準ライブラリのみ。

Usage:
    python3 .claude/scripts/agent-stocktake.py              # Markdown stdout
    python3 .claude/scripts/agent-stocktake.py --json       # JSON stdout
    python3 .claude/scripts/agent-stocktake.py --window=90  # 直近 N 日（default 90）
    python3 .claude/scripts/agent-stocktake.py --target=44  # 削除候補数の目安
    python3 .claude/scripts/agent-stocktake.py --out=path   # ファイル書き出し
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path.cwd()
AGENTS_DIR = ROOT / ".claude" / "agents"
HOMUNCULUS_ROOT = Path.home() / ".claude" / "homunculus"
TRANSCRIPTS_ROOT = Path.home() / ".claude" / "projects"

GRANULARITY_BY_MODEL = {
    "haiku": "micro",
    "sonnet": "medium",
    "opus": "macro",
}

FUNCTION_KEYWORDS: dict[str, list[str]] = {
    "design": ["design", "designer", "architect", "wireframe"],
    "implement": ["developer", "specialist", "engineer", "implementation"],
    "test": ["test", "qa", "tester", "automator"],
    "review": ["review", "reviewer", "audit", "auditor"],
    "security": ["security", "penetration", "compliance", "hardening", "vulnerab"],
    "infra": ["infra", "devops", "kubernetes", "terraform", "docker", "cloud", "deployment", "sre", "platform", "network"],
    "data": ["data", "ml", "ai", "machine-learning", "nlp", "llm", "prompt", "reinforcement"],
    "ops": ["incident", "ops", "responder", "monitor", "performance"],
    "orchestration": ["orchestrat", "coordinator", "distributor", "context-manager"],
    "research": ["research", "researcher", "analyst", "trend", "competitive", "market", "scientific"],
    "doc": ["documentation", "documenter", "readme", "writer", "technical-writer"],
    "language": ["python", "typescript", "javascript", "golang", "rust", "java", "kotlin", "swift", "php", "csharp", "dotnet", "powershell", "elixir", "react", "vue", "angular", "nextjs", "node", "rails", "django", "fastapi", "spring", "laravel", "symfony", "flutter", "expo", "cpp", "sql"],
    "business": ["product-manager", "business-analyst", "scrum", "customer", "sales", "legal", "license", "marketer", "wordpress"],
    "domain": ["blockchain", "fintech", "healthcare", "iot", "embedded", "game", "payment", "quant", "risk", "seo", "m365", "azure", "windows"],
    "tooling": ["dx", "build-engineer", "cli-developer", "tooling", "dependency", "git-workflow", "mcp", "modernizer", "refactor", "slack", "module-architect", "ui-architect"],
}

FRONTMATTER_RE = re.compile(r"^---\s*\n(.*?)\n---", re.DOTALL)
SUBAGENT_RE = re.compile(r'"subagent_type"\s*:\s*"([^"]+)"')

LOW_FIT_KEYWORDS = {
    "blockchain-developer", "fintech-engineer", "embedded-systems", "iot-engineer",
    "game-developer", "quant-analyst", "risk-manager",
    "ad-security-reviewer", "powershell-security-hardening", "powershell-5.1-expert",
    "powershell-7-expert", "powershell-module-architect", "powershell-ui-architect",
    "windows-infra-admin", "azure-infra-engineer", "m365-admin",
    "dotnet-framework-4.8-expert", "elixir-expert", "rails-expert", "symfony-specialist",
    "spring-boot-engineer", "java-architect", "csharp-developer", "dotnet-core-expert",
    "kotlin-specialist", "swift-expert", "expo-react-native-expert", "flutter-expert",
    "cpp-pro", "rust-engineer", "angular-architect", "vue-expert", "django-developer",
    "laravel-specialist", "fastapi-developer", "php-pro", "healthcare-admin",
    "scientific-literature-researcher", "reinforcement-learning-engineer",
    "chaos-engineer", "incident-responder", "devops-incident-responder",
    "terragrunt-expert",
}


def parse_frontmatter(text: str) -> dict:
    m = FRONTMATTER_RE.match(text)
    if not m:
        return {}
    out: dict = {}
    for raw in m.group(1).splitlines():
        line = raw.rstrip()
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        out[key] = value
    return out


def collect_agents() -> list[dict]:
    rows: list[dict] = []
    if not AGENTS_DIR.exists():
        return rows
    for f in sorted(AGENTS_DIR.rglob("*.md")):
        category = f.parent.name
        name = f.stem
        text = f.read_text(encoding="utf-8", errors="replace")
        fm = parse_frontmatter(text)
        rows.append({
            "name": fm.get("name") or name,
            "file_name": name,
            "category": category,
            "model": fm.get("model", "sonnet"),
            "tools": fm.get("tools", ""),
            "description": fm.get("description", ""),
            "path": str(f.relative_to(ROOT)),
            "desc_len": len(fm.get("description", "")),
        })
    return rows


def count_invocations(window_days: int) -> tuple[Counter, dict]:
    counter: Counter = Counter()
    stats = {
        "transcripts_scanned": 0,
        "homunculus_lines_scanned": 0,
        "subagent_total": 0,
        "window_start_iso": "",
    }
    window_start = datetime.now(timezone.utc) - timedelta(days=window_days)
    stats["window_start_iso"] = window_start.isoformat()

    if TRANSCRIPTS_ROOT.exists():
        for jsonl in TRANSCRIPTS_ROOT.glob("*/*.jsonl"):
            try:
                mtime = datetime.fromtimestamp(jsonl.stat().st_mtime, tz=timezone.utc)
            except OSError:
                continue
            if mtime < window_start:
                continue
            stats["transcripts_scanned"] += 1
            try:
                with jsonl.open("r", encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        for match in SUBAGENT_RE.findall(line):
                            counter[match] += 1
                            stats["subagent_total"] += 1
            except OSError:
                continue

    if HOMUNCULUS_ROOT.exists():
        for jsonl in HOMUNCULUS_ROOT.glob("projects/*/observations.jsonl"):
            try:
                with jsonl.open("r", encoding="utf-8", errors="replace") as fh:
                    for line in fh:
                        stats["homunculus_lines_scanned"] += 1
                        for match in SUBAGENT_RE.findall(line):
                            counter[match] += 1
                            stats["subagent_total"] += 1
            except OSError:
                continue

    return counter, stats


def infer_function_category(agent: dict) -> str:
    name_lower = agent["name"].lower()
    desc_lower = agent["description"].lower()
    haystack = f"{name_lower} {desc_lower}"
    scores: Counter = Counter()
    for cat, keywords in FUNCTION_KEYWORDS.items():
        for kw in keywords:
            if kw in haystack:
                scores[cat] += 1
    if not scores:
        return "other"
    return scores.most_common(1)[0][0]


def infer_granularity(agent: dict) -> str:
    model = (agent.get("model") or "").lower()
    base = GRANULARITY_BY_MODEL.get(model, "medium")
    if base == "medium" and agent["desc_len"] < 80:
        return "micro"
    if base == "medium" and agent["desc_len"] > 240:
        return "macro"
    return base


STOPWORDS = {
    "use", "this", "agent", "when", "you", "need", "to", "the", "and", "for",
    "with", "from", "across", "into", "that", "your", "their", "user", "users",
    "comprehensive", "system", "systems", "code", "based", "case", "cases",
    "expert", "specialist", "design", "implement", "tasks", "task",
}


def keywords_of(agent: dict) -> set[str]:
    text = f"{agent['name']} {agent['description']}".lower()
    tokens = re.findall(r"[a-z][a-z0-9\-]{2,}", text)
    return {t for t in tokens if t not in STOPWORDS}


def jaccard(a: set, b: set) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def find_overlaps(agents: list[dict], threshold: float = 0.32) -> list[tuple[str, str, float]]:
    keys = [keywords_of(a) for a in agents]
    pairs: list[tuple[str, str, float]] = []
    n = len(agents)
    for i in range(n):
        for j in range(i + 1, n):
            same_cat = agents[i]["category"] == agents[j]["category"]
            n1 = agents[i]["name"].split("-")
            n2 = agents[j]["name"].split("-")
            name_overlap = (n1[0] == n2[0]) or (n1[-1] == n2[-1])
            if not (same_cat or name_overlap):
                continue
            score = jaccard(keys[i], keys[j])
            if score >= threshold:
                pairs.append((agents[i]["name"], agents[j]["name"], round(score, 3)))
    pairs.sort(key=lambda p: -p[2])
    return pairs


def mark_deletion_candidates(
    agents: list[dict],
    invocations: Counter,
    overlaps: list[tuple[str, str, float]],
    target: int,
) -> list[dict]:
    overlap_count: Counter = Counter()
    for a, b, _ in overlaps:
        overlap_count[a] += 1
        overlap_count[b] += 1

    scored: list[tuple[float, str, list[str]]] = []
    for a in agents:
        reasons: list[str] = []
        score = 0.0
        invk = invocations.get(a["name"], 0) + invocations.get(a["file_name"], 0)
        a["invocations"] = invk
        if invk == 0:
            score += 1.0
            reasons.append("zero-invocations")
        if overlap_count[a["name"]] >= 2:
            score += 1.0
            reasons.append(f"overlap×{overlap_count[a['name']]}")
        elif overlap_count[a["name"]] == 1:
            score += 0.5
            reasons.append("overlap×1")
        if a["file_name"] in LOW_FIT_KEYWORDS:
            score += 1.0
            reasons.append("low-fit-domain")
        if a["file_name"] in {"code-reviewer", "debugger"}:
            score += 0.3
            reasons.append("near-builtin")
        scored.append((score, a["name"], reasons))

    scored.sort(key=lambda x: (-x[0], x[1]))
    delete_set: dict[str, list[str]] = {}
    for score, name, reasons in scored:
        if len(delete_set) >= target:
            break
        if score >= 1.0:
            delete_set[name] = reasons

    for a in agents:
        a["delete_flag"] = a["name"] in delete_set
        a["delete_reasons"] = delete_set.get(a["name"], [])
        a["overlap_count"] = overlap_count[a["name"]]

    return agents


def render_markdown(
    agents: list[dict],
    invocations: Counter,
    overlaps: list[tuple[str, str, float]],
    stats: dict,
    target: int,
) -> str:
    lines: list[str] = []

    delete_candidates = [a for a in agents if a["delete_flag"]]
    zero_invk = [a for a in agents if a["invocations"] == 0]
    by_category: dict[str, list[dict]] = defaultdict(list)
    for a in agents:
        by_category[a["category"]].append(a)

    lines.append("# Agent Stocktake — 2026-05-04")
    lines.append("")
    lines.append("> Auto-generated by `.claude/scripts/agent-stocktake.py`. 144 agents (VoltAgent/awesome-claude-code-subagents 由来) を対象に、")
    lines.append("> 起動実績・粒度・オーバーラップ・適合度を集計し、144→100 を目標に削除候補 44 件を提案する。")
    lines.append("")
    lines.append("## 1. サマリ")
    lines.append("")
    lines.append(f"- **対象 agent 総数**: {len(agents)}")
    lines.append(f"- **起動 0 件**: {len(zero_invk)} ({len(zero_invk)*100//max(len(agents),1)}%)")
    lines.append(f"- **オーバーラップ疑いペア**: {len(overlaps)}")
    lines.append(f"- **削除候補（target {target}）**: {len(delete_candidates)}")
    lines.append("")
    lines.append("### 集計データソース")
    lines.append("")
    lines.append(f"- transcripts (`~/.claude/projects/**/*.jsonl`) 走査: {stats['transcripts_scanned']} 件")
    lines.append(f"- homunculus observations 走査: {stats['homunculus_lines_scanned']} 行")
    lines.append(f"- 集計ウィンドウ開始: {stats['window_start_iso']}")
    lines.append(f"- 検出サブエージェント呼び出し総数: {stats['subagent_total']}")
    lines.append("")
    if stats["subagent_total"] == 0:
        lines.append("> **重要発見**: 直近ウィンドウ内で `Task(subagent_type=<name>)` 形式で起動された")
        lines.append("> 144 agents の **記録は 0 件**。built-in `general-purpose` / `Explore` / `Plan` のみが使われている。")
        lines.append("> → VoltAgent 由来 agents は事実上 dormant ライブラリ。30% 削減ではなく **大幅削減 + 用途明示** が現実的。")
        lines.append("")

    lines.append("## 2. カテゴリ別使用率")
    lines.append("")
    lines.append("| Category | 件数 | 起動 0 件 | 削除候補 | 主な機能カテゴリ |")
    lines.append("|---|---:|---:|---:|---|")
    for cat in sorted(by_category):
        items = by_category[cat]
        zero = sum(1 for a in items if a["invocations"] == 0)
        delc = sum(1 for a in items if a["delete_flag"])
        fcat = Counter(a.get("function_category", "other") for a in items).most_common(3)
        fcat_str = ", ".join(f"{k}×{v}" for k, v in fcat)
        lines.append(f"| `{cat}` | {len(items)} | {zero} | {delc} | {fcat_str} |")
    lines.append("")

    lines.append("## 3. 集計表（144 agents）")
    lines.append("")
    lines.append("| # | Category | Agent | Invk | Function | Granularity | Overlap | Delete |")
    lines.append("|---:|---|---|---:|---|---|---:|:---:|")
    for i, a in enumerate(sorted(agents, key=lambda x: (x["category"], x["name"])), 1):
        flag = "X" if a["delete_flag"] else ""
        lines.append(
            f"| {i} | `{a['category']}` | `{a['name']}` | {a['invocations']} | "
            f"{a.get('function_category','other')} | {a.get('granularity','medium')} | "
            f"{a['overlap_count']} | {flag} |"
        )
    lines.append("")

    lines.append("## 4. オーバーラップ疑いペア（Jaccard >= 0.32）")
    lines.append("")
    if not overlaps:
        lines.append("（該当なし）")
    else:
        lines.append("| Agent A | Agent B | Jaccard |")
        lines.append("|---|---|---:|")
        for a, b, score in overlaps[:60]:
            lines.append(f"| `{a}` | `{b}` | {score} |")
        if len(overlaps) > 60:
            lines.append("")
            lines.append(f"... 他 {len(overlaps) - 60} 件は `--json` で取得")
    lines.append("")

    lines.append(f"## 5. 削除候補リスト（target 144→{144-target}、{target} 件）")
    lines.append("")
    lines.append("| # | Agent | Category | Invk | Reasons |")
    lines.append("|---:|---|---|---:|---|")
    for i, a in enumerate(sorted(delete_candidates, key=lambda x: (x["category"], x["name"])), 1):
        reasons = " / ".join(a["delete_reasons"]) or "—"
        lines.append(f"| {i} | `{a['name']}` | `{a['category']}` | {a['invocations']} | {reasons} |")
    lines.append("")

    lines.append("## 6. 推奨アクション")
    lines.append("")
    lines.append("1. **未使用 Language specialists の整理**: 当プロジェクトの主要技術に近い 5〜7 件のみ残し、それ以外は archive 候補。")
    lines.append("2. **未使用領域の除外**: プロジェクトで使わないスタック（例: `powershell-*` `windows-*` `dotnet-*` `csharp-*` 等）は一括 archive 候補。")
    lines.append("3. **オーバーラップ統合**: `code-reviewer` × `architect-reviewer` × `qa-expert`、`security-auditor` × `penetration-tester` × `compliance-auditor` などはルーター 1 本に集約。")
    lines.append("4. **dormant 状態の根因対処**: subagent_type=`general-purpose` への流入を named agents に振り分ける Skill or Hook（`agent-router`）を別タスクで設計。")
    lines.append("5. **承認後の実作業**: `git mv .claude/agents/<cat>/<agent>.md docs/archive/agents/<cat>/<agent>.md` で履歴を残しつつ無効化。")
    lines.append("")

    return "\n".join(lines) + "\n"


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Agent stocktake report")
    parser.add_argument("--json", action="store_true", help="emit JSON instead of Markdown")
    parser.add_argument("--window", type=int, default=90, help="invocation window in days")
    parser.add_argument("--target", type=int, default=44, help="delete candidate target count")
    parser.add_argument("--out", type=str, default="", help="write to file (default stdout)")
    args = parser.parse_args(argv)

    if not AGENTS_DIR.exists():
        print(f"ERROR: agents dir not found: {AGENTS_DIR}", file=sys.stderr)
        return 2

    agents = collect_agents()
    if not agents:
        print("ERROR: no agents found", file=sys.stderr)
        return 2

    invocations, stats = count_invocations(args.window)
    for a in agents:
        a["function_category"] = infer_function_category(a)
        a["granularity"] = infer_granularity(a)
    overlaps = find_overlaps(agents)
    agents = mark_deletion_candidates(agents, invocations, overlaps, args.target)

    if args.json:
        payload = {
            "stats": stats,
            "agents": agents,
            "overlaps": [{"a": a, "b": b, "jaccard": s} for a, b, s in overlaps],
            "delete_candidates": [a["name"] for a in agents if a["delete_flag"]],
        }
        out = json.dumps(payload, indent=2, ensure_ascii=False)
    else:
        out = render_markdown(agents, invocations, overlaps, stats, args.target)

    if args.out:
        Path(args.out).write_text(out, encoding="utf-8")
    else:
        sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
