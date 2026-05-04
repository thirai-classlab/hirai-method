---
description: Show learned instincts (project + global) with confidence scores. Replicated from ECC continuous-learning-v2.
---

# /instinct-status

このセッション中に蓄積された instinct を一覧表示する。project-scoped と global を区別。

## 使い方

```
/instinct-status
```

引数なし。現在の project（git remote から自動検出）+ global の instinct を出す。

## 動作

1. `python3 .claude/skills/continuous-learning-v2/instinct-cli.py status` を実行
2. 出力を整形して提示
3. confidence 順に並ぶ

## 出力例

```
=== GLOBAL (3) ===
  ████████░░ 0.80  always-validate-input          (security)
  ███████░░░ 0.70  grep-before-edit               (tool-use)
  █████░░░░░ 0.50  conventional-commits           (git)

=== PROJECT (5) [my-app] ===
  █████████░ 0.90  use-supabase-rls               (security)
  ████████░░ 0.80  prefer-functional-react        (code-style)
  ███████░░░ 0.70  test-with-vitest               (testing)
  ██████░░░░ 0.60  microcms-cache-on-isr          (workflow)
  ████░░░░░░ 0.40  no-dark-mode                   (code-style)
```

## 関連

- `/projects` — 既知プロジェクト一覧
- `/evolve` — instinct クラスタリング
- `/promote` — project → global 昇格
