---
name: repo-map
description: Aider 風のリポジトリ全体シンボル抽出。Python / TypeScript / JavaScript / Bash の主要定義（class/def/export/function/interface/type 等）だけを抽出し、Markdown / YAML / JSON で 50KB 以下の俯瞰サマリを生成する。Read を多発させずにリポ全体構造を把握したい時に使う。
---

# repo-map — Aider 風のリポジトリシンボル抽出

[Aider repo-map](https://aider.chat/docs/repomap.html) と同じ発想で、リポ全体を 1 ファイル分の context に圧縮する CLI。Read で何十ファイルも開かずに「どこに何があるか」を把握できる。

## When to Activate

- 新規リポ / 不慣れなリポを最初に把握したい
- 「この機能を実装した関数はどこ？」を Grep より粗く / 速く調べたい
- サブエージェントを起動する前に context として全体マップを渡したい
- Read 回数が context window を圧迫し始めている
- アーキテクチャレビュー / dead code 候補の洗い出し

## Run

```bash
python3 .claude/skills/repo-map/repo-map.py [path] [options]
```

例:

```bash
# カレントを Markdown で（既定）
python3 .claude/skills/repo-map/repo-map.py

# 別リポを YAML で、上限 30KB
python3 .claude/skills/repo-map/repo-map.py /path/to/repo --format yaml --max-bytes 30000

# Python だけに絞る
python3 .claude/skills/repo-map/repo-map.py --language python

# .gitignore を無視して全部走査
python3 .claude/skills/repo-map/repo-map.py --no-gitignore

# 追加で含める / 除外する
python3 .claude/skills/repo-map/repo-map.py --include "configs/**/*.yml" --exclude "fixtures/**"
```

## Options

| Option | 既定値 | 内容 |
|---|---|---|
| `path` | `.` | スキャン対象ルート |
| `--max-bytes N` | `50000` | 出力上限 byte。重要度ランキングで超過分を truncate |
| `--format FMT` | `markdown` | `markdown` / `yaml` / `json` |
| `--language LANGS` | `python,typescript,javascript,bash` | カンマ区切り |
| `--include GLOB` | – | 追加で含める glob（複数指定可） |
| `--exclude GLOB` | – | 追加で除外する glob（複数指定可） |
| `--no-gitignore` | off | `.gitignore` を無視 |
| `--debug` | off | stderr にスキャン詳細 |

## 抽出対象シンボル

| 言語 | 抽出対象 |
|---|---|
| Python (`.py`) | `class` / `def` / `async def` / トップレベル type alias / PEP 695 `type` 文 |
| TypeScript / JavaScript (`.ts/.tsx/.mts/.cts/.js/.jsx/.mjs/.cjs`) | `export class/function/const/let/var`, `interface`, `type X = ...`, `enum`, `export default` |
| Bash (`.sh/.bash`) | `function foo` / `foo()` 形式の関数定義 / `source` / `.` 文 |

非対象拡張子は `--include` で個別に拾える（ただし既知 4 言語以外はパース対象外）。

## 出力例

```markdown
# Repo Map — `claude-code-harness`

- Files scanned: **239**
- Symbols extracted: **1751**
- Files in this map: **44**
- Truncated: **yes**

### `.claude/scripts/agent-stocktake.py` (python)

| Kind | Name | Line | Exported |
|------|------|-----:|:--------:|
| function | `parse_frontmatter` | 80 | Y |
| function | `collect_agents` | 98 | Y |
...
```

サンプル全文: [`examples/sample-output.md`](examples/sample-output.md)

## 重要度ランキング

`--max-bytes` を超えるとファイル単位で truncate される。優先度はシンボル種別の重み合計 + ファイル名ボーナスで決まる:

- `class (10)` > `interface (9)` = `default-export (9)` > `enum (8)` > `type (7)` > `function (6)` > `type-alias (5)` > `method (4)` > `const (3)`
- `exported = true` で +3、1 文字名で −2
- `index.ts` / `__init__.py` / `main.py` / `cli.py` で +5
- ファイル名に `test` / `spec` を含むと −3

## Exit Codes

| code | 意味 |
|:----:|:----|
| 0 | 成功（stdout に出力） |
| 2 | path が無い / 言語指定が空 / 抽出 0 件 |

## 制限事項

- TS/JS は **正規表現ベース**。コメント内 / 文字列内の `class Foo` は誤検出する場合がある（行頭固定で軽減）
- Python の class メソッドはトップレベルクラス直下のみ（ネストクラスのメソッドは取らない）
- Bash の `source` 検出は `$(dirname ...)` 等のパス置換を生のまま記録する
- `.gitignore` 解釈は簡易実装で、git 完全互換ではない（`!` negation, `**`, dir-only `/` まで対応、複雑な anchor は近似）
- 巨大リポ（>5000 file）でもメモリ上に AST を持たないため軽量だが、初回スキャンは I/O bound

## Aider との差分

| 項目 | Aider | repo-map (本 skill) |
|---|---|---|
| パーサ | tree-sitter（言語ごとの完全パース） | Python は `ast` / TS,JS は regex / Bash は regex |
| 言語数 | 30+ | 4 (Python / TS / JS / Bash) |
| 出力 | テキスト固定 | Markdown / YAML / JSON 切替 |
| ランキング | PageRank ベース（参照グラフ） | シンボル種別 + 命名 + ファイル名のヒューリスティック |
| 依存 | `tree-sitter-languages` 等の外部パッケージ | stdlib only |
| 速度 | tree-sitter は高速だが起動コスト | regex / ast は起動コスト 0、巨大リポでも軽い |

完全パースの精度は Aider に劣るが、**「サブエージェント起動前にざっくりマップを渡す」用途では十分**。stdlib only で `python3` さえあれば動く。

## Related

- 詳細仕様 / 制限 / 拡張アイデア: [`README.md`](README.md)
- 出力サンプル: [`examples/sample-output.md`](examples/sample-output.md)
- 元ネタ: <https://aider.chat/docs/repomap.html>
