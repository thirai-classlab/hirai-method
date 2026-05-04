---
description: Show GateGuard cleared/pending state for the current session.
---

# /gate-status

GateGuard が cleared した（事実調査済みとマークした）ファイル/コマンドを一覧表示する。

## 使い方

```
/gate-status
```

## 動作

1. `.claude/.gateguard-state/` を ls
2. 各 cleared エントリを type（edit/write/bash）と hash で表示
3. 必要なら hash → 元 path のリバース検索（recent observations から）

## 出力例

```
=== GateGuard State ===
state dir: .claude/.gateguard-state/

Edit cleared (3):
  edit-a1b2c3d4e5f6.cleared    src/lib/auth.ts
  edit-1f2e3d4c5b6a.cleared    src/components/Hero.tsx
  edit-fedcba987654.cleared    .claude/rules/self-improvement.md

Write cleared (1):
  write-aabbccddeeff.cleared   src/lib/new-helper.ts

Bash cleared (2):
  bash-112233445566.cleared    rm -rf node_modules
  bash-778899aabbcc.cleared    git reset --hard origin/main

Bypass: ECC_GATEGUARD = (unset → active)
```

## 関連

- `/gate-clear [file|all]` — リセット
- `/gate-bypass <file>` — pre-clear
- skill: `.claude/skills/gateguard/SKILL.md`
