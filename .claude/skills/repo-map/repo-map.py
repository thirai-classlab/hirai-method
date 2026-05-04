#!/usr/bin/env python3
"""
repo-map.py — Aider 風のリポジトリ全体シンボル抽出 CLI

リポ全体を走査し、主要な定義シンボル（class/def/export/function 等）だけを
抽出して LLM コンテキストに注入できる Markdown / YAML / JSON サマリを生成する。

設計:
  - 標準ライブラリのみ (Python 3.9+)
  - 依存ライブラリなし、ast / re / pathlib / fnmatch / json / argparse のみ
  - .gitignore を尊重 (ルートと配下の .gitignore を反映する簡易実装)
  - 重要度ランキングで上限 byte に truncate

使い方:
  python3 .claude/skills/repo-map/repo-map.py [path] [options]

Options:
  --max-bytes N        出力上限 byte (default: 50000)
  --format FORMAT      markdown | yaml | json (default: markdown)
  --language LANGS     カンマ区切り (default: python,typescript,javascript,bash)
  --include GLOB       追加で含める glob (繰り返し可)
  --exclude GLOB       追加で除外する glob (繰り返し可)
  --no-gitignore       .gitignore を読まない
  --debug              stderr にスキャン詳細出力

抽出シンボル:
  Python:     class / def / async def / 型エイリアス (X = Y[Z]/PEP 695 type)
  TS / JS:    export class/function/const/let/var, interface, type, enum, default
  Bash:       function 定義 (foo() / function foo / source/. )

Exit codes:
  0  成功
  2  指定 path が存在しない / 解析対象 0 件
"""
from __future__ import annotations

import argparse
import ast
import fnmatch
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Sequence


# ------------------------- 設定 -------------------------

DEFAULT_MAX_BYTES = 50_000
DEFAULT_LANGUAGES = ("python", "typescript", "javascript", "bash")

# 言語 → 拡張子
LANGUAGE_EXTENSIONS: dict[str, tuple[str, ...]] = {
    "python": (".py",),
    "typescript": (".ts", ".tsx", ".mts", ".cts"),
    "javascript": (".js", ".jsx", ".mjs", ".cjs"),
    "bash": (".sh", ".bash"),
}

# 既定で除外するディレクトリ (.gitignore に依らず常時)
HARD_EXCLUDED_DIRS = {
    "node_modules",
    ".venv",
    "venv",
    "env",
    ".env",
    "dist",
    "build",
    "out",
    ".next",
    ".turbo",
    "target",
    ".git",
    ".cache",
    "__pycache__",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
    ".tox",
    ".idea",
    ".vscode",
    "coverage",
    ".coverage",
    ".nyc_output",
    ".nuxt",
    ".svelte-kit",
    ".astro",
    ".parcel-cache",
}

# 既定で除外するファイル glob
HARD_EXCLUDED_GLOBS = (
    "*.min.js",
    "*.min.css",
    "*.map",
    "*.lock",
    "*-lock.json",
    "*.snap",
    "*.d.ts",
)

# シンボル種別 → 重要度の重み (高いほど優先)
KIND_WEIGHTS: dict[str, int] = {
    "class": 10,
    "interface": 9,
    "type": 7,
    "enum": 8,
    "function": 6,
    "method": 4,
    "const": 3,
    "type-alias": 5,
    "default-export": 9,
    "source": 1,
}


# ------------------------- データ -------------------------

@dataclass
class Symbol:
    name: str
    kind: str
    line: int
    exported: bool = False
    extra: str = ""

    def importance(self) -> int:
        base = KIND_WEIGHTS.get(self.kind, 1)
        if self.exported:
            base += 3
        if len(self.name) <= 1:
            base -= 2
        return base


@dataclass
class FileEntry:
    path: str  # repo root からの相対 path (POSIX)
    language: str
    symbols: list[Symbol] = field(default_factory=list)

    def importance(self) -> int:
        if not self.symbols:
            return 0
        total = sum(s.importance() for s in self.symbols)
        bonus = 0
        name = Path(self.path).name.lower()
        if name in ("__init__.py", "index.ts", "index.js", "main.py", "main.ts", "cli.py"):
            bonus += 5
        if "test" in name or "spec" in name:
            bonus -= 3
        return total + bonus


# ------------------------- .gitignore 簡易実装 -------------------------

class GitignoreMatcher:
    """ルート + 配下の .gitignore を集約した簡易マッチャ。"""

    def __init__(self, root: Path, enabled: bool = True) -> None:
        self.root = root
        self.enabled = enabled
        self._patterns: list[tuple[Path, str, bool, bool]] = []
        if enabled:
            self._load_all()

    def _load_all(self) -> None:
        for gi in self.root.rglob(".gitignore"):
            if any(p in HARD_EXCLUDED_DIRS for p in gi.relative_to(self.root).parts):
                continue
            self._load(gi)

    def _load(self, gi_path: Path) -> None:
        base = gi_path.parent
        try:
            text = gi_path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            return
        for raw in text.splitlines():
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            negate = line.startswith("!")
            if negate:
                line = line[1:]
            dir_only = line.endswith("/")
            line = line.rstrip("/")
            self._patterns.append((base, line, negate, dir_only))

    def is_ignored(self, abs_path: Path, is_dir: bool) -> bool:
        if not self.enabled or not self._patterns:
            return False
        try:
            abs_path.relative_to(self.root)
        except ValueError:
            return False
        ignored = False
        for base, pattern, negate, dir_only in self._patterns:
            if dir_only and not is_dir:
                continue
            try:
                rel_to_base = abs_path.relative_to(base).as_posix()
            except ValueError:
                continue
            if self._match(pattern, rel_to_base):
                ignored = not negate
        return ignored

    @staticmethod
    def _match(pattern: str, rel_to_base: str) -> bool:
        if pattern.startswith("/"):
            p = pattern.lstrip("/")
            return fnmatch.fnmatchcase(rel_to_base, p) or rel_to_base.startswith(p + "/")
        if "**" in pattern:
            regex = _gitignore_glob_to_regex(pattern)
            return bool(regex.match(rel_to_base)) or bool(regex.search(rel_to_base))
        if "/" in pattern:
            return (
                fnmatch.fnmatchcase(rel_to_base, pattern)
                or rel_to_base.startswith(pattern + "/")
            )
        return any(
            fnmatch.fnmatchcase(part, pattern) for part in rel_to_base.split("/")
        )


def _gitignore_glob_to_regex(pattern: str) -> "re.Pattern[str]":
    out: list[str] = []
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "*" and i + 1 < len(pattern) and pattern[i + 1] == "*":
            out.append(".*")
            i += 2
            if i < len(pattern) and pattern[i] == "/":
                i += 1
        elif c == "*":
            out.append("[^/]*")
            i += 1
        elif c == "?":
            out.append("[^/]")
            i += 1
        elif c in ".^$+(){}|\\":
            out.append("\\" + c)
            i += 1
        else:
            out.append(c)
            i += 1
    return re.compile("^" + "".join(out) + "$")


# ------------------------- 言語別 抽出 -------------------------

def language_of(path: Path, languages: set[str]) -> str | None:
    suffix = path.suffix.lower()
    for lang, exts in LANGUAGE_EXTENSIONS.items():
        if lang not in languages:
            continue
        if suffix in exts:
            return lang
    return None


def extract_symbols(path: Path, language: str, debug: bool = False) -> list[Symbol]:
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError as exc:
        if debug:
            print(f"[repo-map] read fail {path}: {exc}", file=sys.stderr)
        return []
    if language == "python":
        return _extract_python(text, path, debug)
    if language in ("typescript", "javascript"):
        return _extract_ts_js(text)
    if language == "bash":
        return _extract_bash(text)
    return []


# ---- Python ----

def _extract_python(text: str, path: Path, debug: bool) -> list[Symbol]:
    out: list[Symbol] = []
    try:
        tree = ast.parse(text)
    except SyntaxError:
        if debug:
            print(f"[repo-map] python parse fail: {path}", file=sys.stderr)
        return _python_fallback_regex(text)
    for node in tree.body:
        out.extend(_python_top_level(node))
    return out


def _python_top_level(node: ast.AST) -> list[Symbol]:
    out: list[Symbol] = []
    if isinstance(node, ast.ClassDef):
        line = node.lineno
        out.append(Symbol(name=node.name, kind="class", line=line, exported=not node.name.startswith("_")))
        for child in node.body:
            if isinstance(child, (ast.FunctionDef, ast.AsyncFunctionDef)):
                out.append(
                    Symbol(
                        name=f"{node.name}.{child.name}",
                        kind="method",
                        line=child.lineno,
                        exported=not child.name.startswith("_"),
                    )
                )
    elif isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
        out.append(
            Symbol(
                name=node.name,
                kind="function",
                line=node.lineno,
                exported=not node.name.startswith("_"),
            )
        )
    elif isinstance(node, ast.Assign):
        for target in node.targets:
            if isinstance(target, ast.Name):
                name = target.id
                if name.isupper() or (name[0].isupper() and not name.startswith("_")):
                    kind = "type-alias" if name[0].isupper() else "const"
                    out.append(Symbol(name=name, kind=kind, line=node.lineno, exported=not name.startswith("_")))
    elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
        name = node.target.id
        if name.isupper() or (name[0].isupper() and not name.startswith("_")):
            out.append(
                Symbol(name=name, kind="type-alias" if name[0].isupper() else "const",
                       line=node.lineno, exported=not name.startswith("_"))
            )
    type_alias_cls = getattr(ast, "TypeAlias", None)
    if type_alias_cls is not None and isinstance(node, type_alias_cls):
        target = node.name
        name = getattr(target, "id", str(target))
        out.append(Symbol(name=name, kind="type-alias", line=node.lineno, exported=not name.startswith("_")))
    return out


_PY_FALLBACK_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?:async\s+)?(?P<kind>def|class)\s+(?P<name>[A-Za-z_][A-Za-z0-9_]*)",
    re.MULTILINE,
)


def _python_fallback_regex(text: str) -> list[Symbol]:
    out: list[Symbol] = []
    for m in _PY_FALLBACK_RE.finditer(text):
        if m.group("indent"):
            continue
        kind = "class" if m.group("kind") == "class" else "function"
        name = m.group("name")
        out.append(
            Symbol(
                name=name,
                kind=kind,
                line=text.count("\n", 0, m.start()) + 1,
                exported=not name.startswith("_"),
            )
        )
    return out


# ---- TypeScript / JavaScript ----

_TS_PATTERNS: tuple[tuple[str, "re.Pattern[str]"], ...] = (
    (
        "default-export",
        re.compile(
            r"^export\s+default\s+(?:async\s+)?(?:function\s*\*?\s*([A-Za-z_$][A-Za-z0-9_$]*)?|class\s+([A-Za-z_$][A-Za-z0-9_$]*)?)",
            re.MULTILINE,
        ),
    ),
    (
        "interface",
        re.compile(
            r"^(export\s+)?interface\s+([A-Za-z_$][A-Za-z0-9_$]*)",
            re.MULTILINE,
        ),
    ),
    (
        "type",
        re.compile(
            r"^(export\s+)?type\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*[=<]",
            re.MULTILINE,
        ),
    ),
    (
        "enum",
        re.compile(
            r"^(export\s+)?(?:const\s+)?enum\s+([A-Za-z_$][A-Za-z0-9_$]*)",
            re.MULTILINE,
        ),
    ),
    (
        "class",
        re.compile(
            r"^(export\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][A-Za-z0-9_$]*)",
            re.MULTILINE,
        ),
    ),
    (
        "function",
        re.compile(
            r"^(export\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][A-Za-z0-9_$]*)",
            re.MULTILINE,
        ),
    ),
    (
        "const",
        re.compile(
            r"^(export\s+)?(?:const|let|var)\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*[:=]",
            re.MULTILINE,
        ),
    ),
)


def _extract_ts_js(text: str) -> list[Symbol]:
    out: list[Symbol] = []
    seen: set[tuple[str, int]] = set()
    for kind, pattern in _TS_PATTERNS:
        for m in pattern.finditer(text):
            groups = m.groups()
            if kind == "default-export":
                name = (groups[0] or groups[1] or "default").strip() if groups else "default"
                exported = True
            else:
                exported = bool(groups[0])
                name = (groups[1] or "").strip()
            if not name:
                continue
            line = text.count("\n", 0, m.start()) + 1
            key = (name, line)
            if key in seen:
                continue
            seen.add(key)
            if kind == "const" and name in {"from", "as", "of", "in"}:
                continue
            out.append(Symbol(name=name, kind=kind, line=line, exported=exported))
    return out


# ---- Bash ----

_BASH_FUNC_RE = re.compile(
    r"^(?:function\s+([A-Za-z_][A-Za-z0-9_]*)\s*(?:\(\s*\))?|([A-Za-z_][A-Za-z0-9_]*)\s*\(\s*\))\s*\{?",
    re.MULTILINE,
)
_BASH_SOURCE_RE = re.compile(r"^\s*(?:source|\.)\s+([^\s#]+)", re.MULTILINE)


def _extract_bash(text: str) -> list[Symbol]:
    out: list[Symbol] = []
    for m in _BASH_FUNC_RE.finditer(text):
        name = m.group(1) or m.group(2)
        if not name:
            continue
        line = text.count("\n", 0, m.start()) + 1
        out.append(Symbol(name=name, kind="function", line=line, exported=True))
    for m in _BASH_SOURCE_RE.finditer(text):
        target = m.group(1).strip().strip("\"'")
        line = text.count("\n", 0, m.start()) + 1
        out.append(Symbol(name=target, kind="source", line=line, exported=False))
    return out


# ------------------------- スキャン -------------------------

def scan_repo(
    root: Path,
    languages: set[str],
    extra_includes: Sequence[str],
    extra_excludes: Sequence[str],
    use_gitignore: bool,
    debug: bool,
) -> list[FileEntry]:
    matcher = GitignoreMatcher(root, enabled=use_gitignore)
    entries: list[FileEntry] = []
    for current_root, dirs, files in os.walk(root):
        cur_path = Path(current_root)
        dirs[:] = [
            d for d in dirs
            if d not in HARD_EXCLUDED_DIRS
            and not _is_extra_excluded(cur_path / d, root, extra_excludes)
            and not matcher.is_ignored(cur_path / d, is_dir=True)
        ]
        for fname in files:
            fpath = cur_path / fname
            if any(fnmatch.fnmatchcase(fname, g) for g in HARD_EXCLUDED_GLOBS):
                continue
            if _is_extra_excluded(fpath, root, extra_excludes):
                continue
            if matcher.is_ignored(fpath, is_dir=False):
                if not _matches_any(fpath, root, extra_includes):
                    continue
            lang = language_of(fpath, languages)
            if lang is None:
                continue
            symbols = extract_symbols(fpath, lang, debug=debug)
            if not symbols:
                continue
            try:
                rel = fpath.relative_to(root).as_posix()
            except ValueError:
                rel = str(fpath)
            entries.append(FileEntry(path=rel, language=lang, symbols=symbols))
    return entries


def _matches_any(path: Path, root: Path, globs: Sequence[str]) -> bool:
    if not globs:
        return False
    try:
        rel = path.relative_to(root).as_posix()
    except ValueError:
        rel = str(path)
    return any(fnmatch.fnmatchcase(rel, g) or fnmatch.fnmatchcase(path.name, g) for g in globs)


def _is_extra_excluded(path: Path, root: Path, excludes: Sequence[str]) -> bool:
    return _matches_any(path, root, excludes)


# ------------------------- ランキング & truncate -------------------------

def rank_and_truncate(
    entries: list[FileEntry], max_bytes: int, fmt: str
) -> tuple[list[FileEntry], int, int]:
    total_files = len(entries)
    total_symbols = sum(len(e.symbols) for e in entries)
    sorted_entries = sorted(entries, key=lambda e: e.importance(), reverse=True)
    picked: list[FileEntry] = []
    running = _format_overhead_bytes(fmt)
    for entry in sorted_entries:
        rendered = _render_entry(entry, fmt)
        size = len(rendered.encode("utf-8"))
        if running + size > max_bytes and picked:
            break
        picked.append(entry)
        running += size
    picked.sort(key=lambda e: e.path)
    return picked, total_files, total_symbols


def _format_overhead_bytes(fmt: str) -> int:
    return 600


# ------------------------- レンダリング -------------------------

def render(
    entries: list[FileEntry],
    fmt: str,
    root: Path,
    total_files: int,
    total_symbols: int,
    truncated: bool,
) -> str:
    if fmt == "json":
        return _render_json(entries, root, total_files, total_symbols, truncated)
    if fmt == "yaml":
        return _render_yaml(entries, root, total_files, total_symbols, truncated)
    return _render_markdown(entries, root, total_files, total_symbols, truncated)


def _render_entry(entry: FileEntry, fmt: str) -> str:
    if fmt == "json":
        return json.dumps(_entry_dict(entry), ensure_ascii=False) + ",\n"
    if fmt == "yaml":
        lines = [f"  - path: {entry.path}", f"    language: {entry.language}", "    symbols:"]
        for s in entry.symbols:
            lines.append(
                f"      - {{name: {_yaml_safe(s.name)}, kind: {s.kind}, line: {s.line}, exported: {str(s.exported).lower()}}}"
            )
        return "\n".join(lines) + "\n"
    out = [f"### `{entry.path}` ({entry.language})", ""]
    out.append("| Kind | Name | Line | Exported |")
    out.append("|------|------|-----:|:--------:|")
    for s in entry.symbols:
        out.append(f"| {s.kind} | `{s.name}` | {s.line} | {'Y' if s.exported else ' '} |")
    out.append("")
    return "\n".join(out) + "\n"


def _entry_dict(entry: FileEntry) -> dict:
    return {
        "path": entry.path,
        "language": entry.language,
        "symbols": [
            {"name": s.name, "kind": s.kind, "line": s.line, "exported": s.exported}
            for s in entry.symbols
        ],
    }


def _yaml_safe(value: str) -> str:
    if re.match(r"^[A-Za-z_][A-Za-z0-9_.\-]*$", value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def _render_markdown(
    entries: list[FileEntry], root: Path, total_files: int, total_symbols: int, truncated: bool
) -> str:
    header = [
        f"# Repo Map — `{root.name}`",
        "",
        f"- Files scanned: **{total_files}**",
        f"- Symbols extracted: **{total_symbols}**",
        f"- Files in this map: **{len(entries)}**",
        f"- Truncated: **{'yes' if truncated else 'no'}**",
        "",
        "Generated by `.claude/skills/repo-map/repo-map.py`.",
        "",
    ]
    body = [_render_entry(e, "markdown") for e in entries]
    return "\n".join(header) + "\n".join(body)


def _render_yaml(
    entries: list[FileEntry], root: Path, total_files: int, total_symbols: int, truncated: bool
) -> str:
    out = [
        f"repo: {root.name}",
        f"files_scanned: {total_files}",
        f"symbols_extracted: {total_symbols}",
        f"files_in_map: {len(entries)}",
        f"truncated: {'true' if truncated else 'false'}",
        "entries:",
    ]
    for e in entries:
        out.append(_render_entry(e, "yaml").rstrip("\n"))
    return "\n".join(out) + "\n"


def _render_json(
    entries: list[FileEntry], root: Path, total_files: int, total_symbols: int, truncated: bool
) -> str:
    payload = {
        "repo": root.name,
        "files_scanned": total_files,
        "symbols_extracted": total_symbols,
        "files_in_map": len(entries),
        "truncated": truncated,
        "entries": [_entry_dict(e) for e in entries],
    }
    return json.dumps(payload, ensure_ascii=False, indent=2) + "\n"


# ------------------------- main -------------------------

def parse_args(argv: Sequence[str]) -> argparse.Namespace:
    p = argparse.ArgumentParser(
        prog="repo-map",
        description="Aider 風のリポジトリ全体シンボル抽出 CLI",
    )
    p.add_argument("path", nargs="?", default=".", help="対象ルート (default: cwd)")
    p.add_argument("--max-bytes", type=int, default=DEFAULT_MAX_BYTES, help="出力上限 byte")
    p.add_argument(
        "--format",
        choices=("markdown", "yaml", "json"),
        default="markdown",
        help="出力形式 (default: markdown)",
    )
    p.add_argument(
        "--language",
        default=",".join(DEFAULT_LANGUAGES),
        help=f"カンマ区切り (default: {','.join(DEFAULT_LANGUAGES)})",
    )
    p.add_argument("--include", action="append", default=[], help="追加で含める glob")
    p.add_argument("--exclude", action="append", default=[], help="追加で除外する glob")
    p.add_argument("--no-gitignore", action="store_true", help=".gitignore を読まない")
    p.add_argument("--debug", action="store_true", help="stderr にスキャン詳細出力")
    return p.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv if argv is not None else sys.argv[1:])
    root = Path(args.path).resolve()
    if not root.exists() or not root.is_dir():
        print(f"[repo-map] path not found or not a dir: {root}", file=sys.stderr)
        return 2
    languages = {lang.strip().lower() for lang in args.language.split(",") if lang.strip()}
    unknown = languages - set(LANGUAGE_EXTENSIONS)
    if unknown:
        print(f"[repo-map] unknown languages: {sorted(unknown)}", file=sys.stderr)
        languages -= unknown
    if not languages:
        print("[repo-map] no valid languages specified", file=sys.stderr)
        return 2
    entries = scan_repo(
        root=root,
        languages=languages,
        extra_includes=args.include,
        extra_excludes=args.exclude,
        use_gitignore=not args.no_gitignore,
        debug=args.debug,
    )
    if not entries:
        print(f"[repo-map] no symbols extracted under {root}", file=sys.stderr)
        return 2
    picked, total_files, total_symbols = rank_and_truncate(entries, args.max_bytes, args.format)
    truncated = len(picked) < total_files
    out = render(picked, args.format, root, total_files, total_symbols, truncated)
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
