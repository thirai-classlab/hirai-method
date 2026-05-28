# .claude/rules-details/ — Layer B (詳細版) SSoT

本 dir は HIRAI メソッドハーネスの規範文書 **Layer B (詳細版)** を集約する。**Claude Code は `.claude/rules/` のみを discover + startup load する** (公式 doc: [code.claude.com/docs/en/memory.md](https://code.claude.com/docs/en/memory.md))。本 dir はその discover 範囲の外側のため、startup context に**注入されない**。

## 採用経緯 (task-51)

`.claude/rules/<rule>.details.md` に Layer B を置き frontmatter `paths: []` で非注入を狙う初期設計は **Claude Code 仕様上成立しない** ことが claude-code-guide subagent + 公式 doc で確定 (`paths:` は path match 時の**追加適用**機構で除外機構ではなく、`paths: []` は spec undefined、frontmatter に negation pattern 不在)。

→ 2026-05-28 A 案 (user 承認) で `.claude/rules-details/` 配下へ物理移動、startup から ~25K tok 削減 (実測値は移動後 fresh session で再計測予定)。

## ファイル命名規約

```
.claude/rules/<rule>.md              # Layer A (要約、常時 startup 注入)
.claude/rules-details/<rule>.details.md   # Layer B (詳細、明示 Read のみ)
```

## link reference 規約 (2 要素 hard match、task-51 Step H 由来)

### Layer A → B (forward-link、Layer A 内に書く)
```markdown
> 詳細: [<rule>.details.md](../rules-details/<rule>.details.md)
> **例詳細**: [<rule>.details.md §<section>](../rules-details/<rule>.details.md#<anchor>)
```

### Layer B → A (back-link、Layer B 冒頭に書く)
```markdown
> Layer A: [`<rule>.md`](../rules/<rule>.md) | 本 file は **明示 Read のみ** (context 自動注入 OFF)
```

## Read trigger 4 条件 (Layer A 冒頭に共通明記)

1. 違反検出時 (hook BLOCK / warn 注入受領 / regex 不一致)
2. 規範変更時 (rule 編集 / draft 起案 / 採用 N 条改定)
3. 新規事案 (初遭遇 keyword / 例外パターン疑い)
4. 学習 / dogfood (依存先必読 / harness audit / 副産物整理)

通常運用は Layer A のみで判断、Layer B Read skip (token 節約)。

## install.sh / smoke test 配下対応

- `install.sh` の `rsync -a .claude/` で本 dir は自動同期される (RSYNC_EXCLUDES 不在のため)
- `.claude/tests/layer-b-context-isolation-smoke.sh` は本 dir を Layer B 検査対象として参照する
