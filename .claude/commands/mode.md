---
description: HIRAI メソッドの動作モードを切替える (normal / loop)
---

# /mode — 動作モード切替

引数: `normal` または `loop`

## 動作

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください。

1. **引数の検証**:
   - 引数が `normal` または `loop` であることを確認
   - 不正な引数の場合、使い方を表示して終了
2. **設定ファイル更新**: `.claude/mode.yml` の `mode:` 行を新しい値に書き換える
   - 既存の他のキー / コメントは保持
   - sed や Edit ツールで `mode: <旧値>` → `mode: <新値>` を 1 箇所だけ置換
3. **確認出力**: 「Mode switched to **{新値}**」をユーザに報告
4. **次セッションへの注意**:
   - 設定変更は本セッションでは即座には適用されない（hook は次の UserPromptSubmit から効く）
   - ただし、本ターン以降の応答は新モードのルールに従って行うこと
5. **Loop モードへの切替時**:
   - 直ちに Loop モードの動作ルール (`.claude/rules/modes.md` 参照) を遵守
   - ユーザ確認を取らず推奨方法で実装を継続
6. **Normal モードへの切替時**:
   - 重要分岐でユーザ確認を取る通常動作に戻る

## 使い方

```
/mode loop    # Loop モードに切替
/mode normal  # Normal モードに切替
```

## 関連

- `.claude/rules/modes.md` — モードルール詳細
- `.claude/hooks/mode-session-start.sh` — SessionStart で現モード表示
- `.claude/hooks/mode-enforce.sh` — UserPromptSubmit で Loop ルール強制
