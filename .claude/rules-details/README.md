# .claude/rules-details/ — Layer B (詳細版) SSoT

本 dir は HIRAI メソッドハーネスの規範文書 **Layer B (詳細版)** を集約する。**Claude Code は `.claude/rules/` のみを discover + startup load する** (公式 doc: [code.claude.com/docs/en/memory.md](https://code.claude.com/docs/en/memory.md))。本 dir はその discover 範囲の外側のため、startup context に**注入されない**。

## 採用経緯 (task-51)

`.claude/rules/<rule>.details.md` に Layer B を置き frontmatter `paths: []` で非注入を狙う初期設計は **Claude Code 仕様上成立しない** ことが claude-code-guide subagent + 公式 doc で確定 (`paths:` は path match 時の**追加適用**機構で除外機構ではなく、`paths: []` は spec undefined、frontmatter に negation pattern 不在)。

→ 2026-05-28 A 案 (user 承認) で `.claude/rules-details/` 配下へ物理移動、startup から ~25K tok 削減 (実測値は移動後 fresh session で再計測予定)。

## ファイル命名規約 (task-67 で断片化、2026-06-01)

```
.claude/rules/<rule>.md                    # Layer A (要約 + command/key 表 + pointer のみ、常時 startup 注入、目標 <120 行)
.claude/rules-details/<rule>/<topic>.md    # Layer B 断片 (topic 別、明示 Read のみ、目標 <100 行)
```

- **1 断片 = 1 Layer A pointer 先 = 1 cohesive topic** (旧 `<rule>.details.md` の 1 `##` section ≒ 1 断片)。
- `<topic>` は kebab-case (例: `14-stage`, `workflow-guard`, `mece-20`)。
- **旧方式 `<rule>.details.md` (1 rule = 1 巨大ファイル) は task-67 で `<rule>/` ディレクトリへ分割**。「detail 1 個欲しいだけで全文 Read」を解消し on-demand Read を断片単位 surgical 化する。

## link reference 規約 (task-67 断片版、断片ファイル直リンク)

### Layer A → B 断片 (forward-link、Layer A 内に書く)
```markdown
> 詳細: [<rule>/<topic>.md](../rules-details/<rule>/<topic>.md)
```
旧 `<rule>.details.md §<section> anchor` 方式は廃止 (断片ファイルを直接指すことで Read を最小化)。

### Layer B 断片 → A (back-link、各断片冒頭に書く、`../../` の 2 階層上り)
```markdown
> Layer A: [`<rule>.md`](../../rules/<rule>.md) §<該当 section> | 本 file は **明示 Read のみ** (context 自動注入 OFF)
```

## auto-load 非対象の保証 (CRITICAL)

- Claude Code は `.claude/rules/*.md` のみ discover + startup load する。`.claude/rules-details/<rule>/` は rules/ の **外** かつ subdir のため **auto-load されない** (断片化で subdir を作っても本性質は不変)。
- **検証方法 (Step 4 smoke)**: (1) 全 Layer A (`rules/*.md`) の `(../rules-details/...)` pointer を抽出し、各リンク先断片の実在を assert (dangling 0)。(2) `rules-details/` 配下に置くべき断片が誤って `rules/` 直下に無いことを assert。(3) `layer-b-context-isolation-smoke.sh` を断片構造に対応更新。

## Read trigger 4 条件 (Layer A 冒頭に共通明記)

1. 違反検出時 (hook BLOCK / warn 注入受領 / regex 不一致)
2. 規範変更時 (rule 編集 / draft 起案 / 採用 N 条改定)
3. 新規事案 (初遭遇 keyword / 例外パターン疑い)
4. 学習 / dogfood (依存先必読 / harness audit / 副産物整理)

通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。

## Layer B 断片 index (task-67、Step 2 で随時更新)

各 rule の `<rule>/` ディレクトリ配下の断片一覧。Layer A の pointer はこの断片を直リンクする。

| rule | ディレクトリ | 断片 (topic) | 移行状態 |
|---|---|---|---|
| workflow | `workflow/` | 14-stage / 10-stage / workflow-guard / draft-flow-guard / refactoring / mece-20 / fan-out / reviewer-prompt / byproduct-discharge / session-persistence / related-skills / origin (12 断片) | ✅ (task-67) |
| development-process | `development-process/` | research-reuse / delegation-requirements / parallelization-origin / staging-strategy / cross-repo-write / confidence-gate / harness-sync / origin (8 断片) | ✅ (task-67) |
| modes | `modes/` | compliance-items / five-layer-enforcement / mode-hooks / artifacts / origin (5 断片) | ✅ (task-67) |
| task-management | `task-management/` | six-articles / mandatory-reading / task-migration / ui-detection / plan-first / hook-enforcement / parking-lot / origin (8 断片) | ✅ (task-67) |
| self-improvement | `self-improvement/` | when-to-use-layers / l4-mechanics / related-skills / origin (4 断片) | ✅ (task-67) |
| why-x5-output | `why-x5-output/` | examples / v1-v10-history / feedback-memory / origin (4 断片) | ✅ (task-67) |

> 移行完了した rule は旧 `<rule>.details.md` を削除し、本表の移行状態を ✅ に更新する。

## install.sh / smoke test 配下対応

- `install.sh` の `rsync -a .claude/` で本 dir は自動同期される (RSYNC_EXCLUDES 不在のため)
- `.claude/tests/layer-b-context-isolation-smoke.sh` は本 dir を Layer B 検査対象として参照する
