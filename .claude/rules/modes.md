# HIRAI メソッド 動作モード

HIRAI メソッドは 2 つの動作モードを持つ。

## モード一覧

### Normal モード（既定値）

- 重要分岐でユーザに確認を求めながら進める
- Why × 5 出力（`why-x5-output.md`）は常時 ON
- セッション開始時に Loop モードへの切替を **1 度だけ提案** する

### Loop モード

ユーザの明示的な停止指示まで、AI が推奨する方法を即採用して実装を継続する。

**遵守事項**:
1. **AI 推奨方法を即採用**: 複数選択肢がある場合、ユーザに確認を求めず Why × 5 で評価して推奨を採用
2. **中間確認の停止**: 「進めてもよいですか?」「どちらにしますか?」等の質問は禁止
3. **自律分解と継続**: 大きなタスクは自ら分解し最後まで通す
4. **Why × 5 表示の維持**: 確認は省くが、思考過程の透明性は失わない

**停止条件は以下 3 つのみ**:
- ユーザの明示的な停止指示（"stop" / "ストップ" / "止めて" 等）
- タスクの完了
- 致命的エラー（権限拒否 / 復旧不能 / 重大なデータ破壊リスク）

## 設定

モードは `.claude/mode.yml` で永続化される。値は `normal` か `loop`。

```yaml
mode: normal  # または loop
```

## 切替方法

| 方法 | 用途 |
|---|---|
| `/mode loop` / `/mode normal` slash command | セッション中の切替（推奨） |
| `.claude/mode.yml` 直接編集 | 手動切替 |
| `HC_MODE=loop` 環境変数 | YAML を触らず一時切替 |

値解決の優先順（高 → 低）: `env(HC_MODE)` > `mode.yml` > `default(normal)`

## 強制機構

| Hook | タイミング | 役割 |
|---|---|---|
| `.claude/hooks/mode-session-start.sh` | SessionStart | 現モード表示 / normal 時に切替提案 |
| `.claude/hooks/mode-enforce.sh` | UserPromptSubmit | Loop モード時に毎ターン遵守事項を再注入 |

両者とも `.claude/hooks/lib/mode-loader.sh` で現モードを解決する。

## モードと既存ルールの関係

| ルール | Normal | Loop |
|---|---|---|
| `why-x5-output.md` (Why × 5 表示) | ON | ON |
| 中間確認質問 | 要 | 禁止 |
| サブエージェント委譲（`delegation-guard.sh`） | 要 | 要 |
| 事実検証（`gateguard.sh`） | 要 | 要 |

Loop モードでも委譲・事実検証等の安全ガードは無効化されない。**省略するのはユーザ確認のみ**。
