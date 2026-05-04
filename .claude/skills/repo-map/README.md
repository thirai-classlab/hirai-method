# repo-map — 詳細仕様

`SKILL.md` のリファレンス兼設計メモ。実装の意図 / 既知の制限 / 拡張余地を記録する。

## 目的

Aider の repo-map と同じ目的:

> Send LLMs a concise overview of every file in your repo, with the most important symbols highlighted, so they don't need to Read every file before making changes.

サブエージェント分業 + Hook 強制委譲のハーネスでは、メインエージェントから Read を奪っている。代わりに「マップ」を 1 度生成して渡せば、Read を温存しつつアーキテクチャ全体を共有できる。

## アーキテクチャ

```
repo-map.py
├── parse_args            argparse
├── scan_repo             os.walk + .gitignore + 言語判定
│   └── extract_symbols
│       ├── _extract_python   ast.parse → top-level class/def/type alias
│       ├── _extract_ts_js    regex 7 種 (default-export → const)
│       └── _extract_bash     regex (function 定義 + source)
├── rank_and_truncate     重要度ソート + 上限 byte で打ち切り
└── render                markdown / yaml / json
```

すべて stdlib のみ。Python 3.9+ で動作（PEP 695 `type` 文の検出は 3.12+ 限定で `getattr(ast, "TypeAlias", None)` ガード）。

## .gitignore 簡易実装

`GitignoreMatcher` は完全な git 互換ではないが、典型ユースケースを押さえる:

- ルート + 配下の `.gitignore` を rglob で集める
- パターンごとに `(base_dir, pattern, negate, dir_only)` を保持
- マッチング時は `base_dir` 相対パスで判定（git の挙動に合わせる）
- `**` は正規表現に変換（`fnmatch` は階層をまたがない）
- `!` negation で打ち消し可能

未対応:
- `.git/info/exclude`
- グローバル ignore (`core.excludesfile`)
- パターン中の文字クラス `[abc]` の完全互換（fnmatch に委譲）

## ランキングヒューリスティック

PageRank（Aider）まで踏み込まず、シンボル種別と命名で簡易スコアリング:

```python
KIND_WEIGHTS = {
    "class": 10, "interface": 9, "default-export": 9, "enum": 8,
    "type": 7, "function": 6, "type-alias": 5, "method": 4,
    "const": 3, "source": 1,
}
```

ファイル単位は:
```
score = sum(symbol_importance) + filename_bonus
        +5: index.ts, __init__.py, main.py, main.ts, cli.py
        -3: filename contains "test" or "spec"
```

シンボル単位は `KIND_WEIGHTS[kind] + (3 if exported else 0) - (2 if len(name) <= 1 else 0)`。

## 出力サイズ制御

`rank_and_truncate(entries, max_bytes, fmt)`:

1. 全エントリを importance 降順にソート
2. 1 件ずつ「採用後の合計 byte が上限を超えるか」を試算
3. 超えたら止め、採用済みエントリを path 順に並べ戻す（出力安定性）
4. 採用件数 < 全件数なら `truncated: true`

レンダリング時のオーバーヘッド（ヘッダ等）は概算 600 byte を最初に積んでいる。

## 拡張アイデア

| アイデア | 概要 | 難易度 |
|---|---|---|
| Go / Rust 対応 | regex 追加で `func` / `pub fn` / `struct` を拾う | Low |
| import グラフ | Python `import` を追ってモジュール参照表を出力 | Mid |
| 1 ファイル / シンボル単位の `--limit` | byte ではなく件数で truncate | Low |
| 差分マップ | `git diff` 範囲のシンボルだけ出す | Mid |
| stale token detector | `__init__.py` で再 export されてないシンボルを警告 | Mid |
| caching | mtime ベースのキャッシュで再実行高速化 | Mid |
| LSP 連携 | tree-sitter or pyright で精度を上げる | High（依存追加が必要） |

## なぜ Bash の `source` を拾うか

ハーネス内 hook（`.claude/hooks/*.sh`）が `source $(dirname ...)/lib/config-loader.sh` で共通ライブラリを取り込む構成のため。「どの hook がどの lib を依存しているか」を一覧できると、portability config の影響範囲調査に使える。

## 既知の誤検出

| ケース | 影響 | 対策 |
|---|---|---|
| TS で文字列内に `class Foo` | 誤検出 | 行頭 `^` 固定で軽減 |
| TS const の destructure (`const { a, b } = obj`) | 拾えない | 設計上スコープ外 |
| Python の `if TYPE_CHECKING:` 配下 | 通常の Assign として取る | 問題ない |
| Bash の関数内 `function inner()` | トップレベル扱いで取る | 大半の hook では実害なし |

## テスト方針

stdlib only でテストフレームワーク不要。手動検証の手順:

```bash
# 1. ハーネス自身に対して
python3 .claude/skills/repo-map/repo-map.py

# 2. サンプルが 50KB 以下か
python3 .claude/skills/repo-map/repo-map.py > /tmp/out.md && wc -c /tmp/out.md

# 3. 各形式
python3 .claude/skills/repo-map/repo-map.py --format json | python3 -m json.tool > /dev/null
python3 .claude/skills/repo-map/repo-map.py --format yaml | head -50

# 4. 言語フィルタ
python3 .claude/skills/repo-map/repo-map.py --language python
python3 .claude/skills/repo-map/repo-map.py --language bash
```

正式な pytest 化は `extract_symbols` のフィクスチャを揃えてから。現状は CLI として小さく完結しているため、出力 diff で十分。

## ライセンス / 由来

設計思想は Aider の repo-map に由来（https://aider.chat/docs/repomap.html）。実装は本リポ独自（tree-sitter 等の外部依存なし）。ハーネス内の他 skill と同じく `.claude/skills/` 配下に同梱して運用する。
