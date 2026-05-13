---
description: HIRAI メソッドの動作モードを切替える (normal / loop / asana on|off)
---

# /mode — 動作モード切替

引数:
- `normal` または `loop` — 動作モード (確認スタイル) 切替
- `asana on` または `asana off` — Asana 連携 ON/OFF 切替

## 動作

このコマンドが呼ばれたら、メインエージェントは以下の手順を実行してください。

### サブコマンド: `normal` / `loop` (動作モード)

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

### サブコマンド: `asana on` / `asana off` (Asana 連携 mode)

1. **引数の検証**:
   - 第 1 引数が `asana`、第 2 引数が `on` または `off` であることを確認
   - `on` → `asana_enabled: true`、`off` → `asana_enabled: false`
2. **設定ファイル更新**: `.claude/mode.yml` の `asana_enabled:` 行を書き換える
   - 既存値が無い場合は新規追加、ある場合は置換
3. **確認出力**: 「Asana 連携: **on / off** に設定しました」
4. **on 時**: `/work-init`, `work-session-check.sh`, Asana/Slack MCP 関連機能が有効化
5. **off 時**: 上記機能は no-op、ハーネスは Asana 抜きで動作

## 使い方

```
/mode loop          # Loop モードに切替
/mode normal        # Normal モードに切替
/mode asana on      # Asana 連携を有効化
/mode asana off     # Asana 連携を無効化
```

## 関連

- `.claude/rules/modes.md` — モードルール詳細
- `.claude/hooks/mode-session-start.sh` — SessionStart で現モード表示
- `.claude/hooks/mode-enforce.sh` — UserPromptSubmit で Loop ルール強制
- `.claude/hooks/mode-asana-prompt.sh` — SessionStart で asana_enabled 未設定時に user ヒアリング
