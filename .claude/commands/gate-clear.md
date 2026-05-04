---
description: Reset GateGuard cleared state — for a specific file, or all entries.
---

# /gate-clear

GateGuard の cleared state をリセットする。リセット後は次回 Edit/Write/Bash で再ゲート発火。

## 使い方

```
/gate-clear              # 対話で対象選択
/gate-clear all          # 全 state 消去
/gate-clear <file>       # 特定ファイルの cleared を消去
/gate-clear --bash <cmd> # 特定 bash コマンドの cleared を消去
```

## 動作

1. `.claude/.gateguard-state/` の対象 marker を `rm`
2. リセット件数を報告

## 例

```bash
# 全リセット
/gate-clear all
# → Removed 6 cleared markers.

# 特定ファイルだけ
/gate-clear src/lib/auth.ts
# → file hash a1b2c3d4e5f6
# → Removed: edit-a1b2c3d4e5f6.cleared
```

## いつ使うか

- 大規模リファクタの前に「全ファイル再ゲート」したい
- セッションをまたいで前のセッションの state を引きずりたくない
- gate を回避したつもりが実は古い state で通っていた、と気付いたとき

## 関連

- `/gate-status`
- `/gate-bypass`
