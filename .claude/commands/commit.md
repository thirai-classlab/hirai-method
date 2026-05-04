---
description: Conventional Commits 形式の commit メッセージを diff から自動生成。CLAUDE.md "Autonomous Progression" 準拠、Co-Authored-By 不要、scope 自動検出。
---

# /commit — Conventional Commits 自動生成

`git diff` を分析し、CLAUDE.md "Autonomous Progression" の commit 規約に沿った commit message を生成します。

## 使い方

```
/commit                       # staged (なければ全変更) を自動 commit 提案
/commit <scope ヒント>         # scope を強制指定 (例: /commit harness)
```

引数で scope を指定可能。指定がなければ変更ファイルパスから自動推定。

## 動作

1. `git status --short` で変更内容を確認
2. **staged が空なら明示的に staging しない** — ユーザーが意図的に staging したファイルを尊重し、空なら全部 staging すべきか確認する
3. `git diff --cached` (or `git diff` if nothing staged) で diff を取得
4. 変更を分析:
   - `src/lib/` → scope=lib
   - `src/components/` → scope=ui
   - `src/app/api/` → scope=api
   - `supabase/migrations/` → scope=db
   - `.claude/` → scope=harness
   - `docs/` → scope=docs
   - `.github/` `package.json` 等 → scope=repo
5. type を推定:
   - `feat:` 新機能・新エンドポイント・新ページ
   - `fix:` バグ修正(既存挙動の修正)
   - `refactor:` 機能変更を伴わない構造改善
   - `docs:` ドキュメントのみ
   - `test:` テスト追加/修正
   - `chore:` 設定・依存更新
   - `perf:` パフォーマンス改善
   - `ci:` CI/CD 設定
   - `style:` フォーマットのみ(コード意味に影響なし)
6. **複数の論理単位**が含まれていたら警告し、commit を分割する案を提示
7. 関連 issue 番号を以下から推定:
   - 現在のブランチ名 (`feature/issue-42-foo` → `(#42)`)
   - diff 内の `(#NN)` 言及
   - `docs/tasks/list.md` の進行中タスク
8. メッセージを生成して提示し、**ユーザー承認後に commit**

## 出力フォーマット

```
<type>(<scope>): <subject> (#<issue>)

- <変更点 1>
- <変更点 2>

Closes #<issue>
```

例(本リポの commit log から):
```
fix(harness): close Bash delegation gap + use afplay for reliable Stop sound
chore(repo): ignore .claude/skills/ + output/ artifacts
docs(sync): align design docs with Phase 11 W2 + #33-#41 reality
fix(css): scope .rich-source-link block style + inline rescue (#37 hotfix)
fix(related): handle multi-chunk source embeddings (#33 follow-up)
```

## 制約・原則

- **CLAUDE.md "Autonomous Progression" 準拠**:
  - subject は **70 文字以内**、命令形・現在形(add/fix not added/fixed)
  - 大文字始まり禁止 (`feat:Add` ではなく `feat: add`)
  - 末尾 `.` を付けない
- **Co-Authored-By を絶対に追加しない**(`~/.claude/settings.json` でグローバル無効化済)
- **`--no-verify` 禁止** — pre-commit hook が失敗したら原因を直す
- **意図せず staged にない変更を含めない** — `git add -A` を勝手に走らせない
- 関連 issue 不明時は `(#?)` ではなく**省略**(後で `git commit --amend` で追加可能)

## サブエージェント連携

複雑な diff(多数ファイル / 言語混在 / 設計変更含む)では以下を活用:

- **typescript-reviewer**(グローバル ~/.claude/agents/) — TS/JS の意味的レビュー
- **code-reviewer**(グローバル) — 一般品質チェック
- **debugger**(グローバル、本セッションで追加) — 既存挙動が壊れた疑いがあれば

## 注意点

- staged 0 件でユーザーが「全部入れて」と明示したら `git add -A` で staging
- pre-commit hook が失敗 → fix → **新しい commit を作成**(`--amend` 禁止、CLAUDE.md の git ガード方針)
- 100 行を超える diff は内容サマリのみ提示、メッセージ生成精度を優先

## 関連

- テンプレート: [`.gitmessage`](../../.gitmessage)
- 規約: [CLAUDE.md "Autonomous Progression"](../../CLAUDE.md#autonomous-progression自律進行ルール)
- 不変ルール: [CLAUDE.md](../../CLAUDE.md) の Development Policy
