# Confidence Gate (F3)

サブエージェントの完了サマリに **`confidence: 0.X` 自己評価** を埋め込ませ、
閾値未満で SubagentStop を block する SuperClaude 風 self-confidence threshold。

> 早期完了宣言・盲目的 `/finish-task` を抑止する事後ゲート。F1 GateGuard の事前ゲートと対をなす。

## アーキテクチャ

```
[ Subagent (Task tool) ] → completion text を返す
                                    ↓
                           SubagentStop hook
                                    ↓
                  .claude/hooks/confidence-gate.sh
                                    ↓
            ┌─────────────────────────────────┐
            │ 1. transcript_path から最終      │
            │    assistant text を tail 抽出   │
            │ 2. `confidence: 0.X` を grep     │
            │ 3. 閾値 (HC_CONFIDENCE_THRESHOLD)│
            │    と awk で浮動小数比較         │
            └─────────────────────────────────┘
                                    ↓
                ┌──────────────┬──────────────┐
                │   PASS       │   BLOCK      │
                │  exit 0 + {} │  decision:   │
                │              │  "block"     │
                └──────────────┴──────────────┘
```

## 設定（`.claude/harness-config.yml`）

```yaml
confidence_threshold: 0.6                                # pass 最低値（0.0〜1.0）
confidence_required:  true                               # false なら未記載でも pass
confidence_state_dir: .claude/.confidence-gate-state     # bypass marker / log 保管
```

env での override も効く（hook 内で env > YAML の優先順を保証）:

```bash
HC_CONFIDENCE_REQUIRED=false bash .claude/hooks/confidence-gate.sh   # config レベル OFF
ECC_CONFIDENCE_GATE=off       bash .claude/hooks/confidence-gate.sh   # 全 OFF
```

## サブエージェントが書く形式

最終 assistant text のどこかに以下を含めれば検出される（大文字小文字問わず・複数 hit は最後優先）:

```
confidence: 0.85
```

## confidence 算出基準（4 段階）

| レンジ | 判定 | 根拠の例 |
|---|---|---|
| **0.9 - 1.0** | 全条件を実測値で確認 | `npm test` 全 pass の生 log を引用 / grep で caller 0 件確認 / build 成功時刻つき |
| **0.7 - 0.8** | 主要条件は確認、周辺は推定 | unit test pass、ただし integration test は別タスクで未実行 |
| **0.5 - 0.6** | 実装は完了したが検証が浅い | 書いたが実行未確認、あるいは依存 schema を見ていない |
| **0.0 - 0.4** | 方針が不明確 / 仮実装 | TODO や `// FIXME` を残した状態、user の追加判断が必要 |

**完了宣言の最低ライン = 0.6**（既定）。0.5 以下は block されて diagnose に戻る。

## サブエージェント側の記載例

```text
F3 confidence-gate.sh を実装し以下を確認:
- 6 ケースの mock transcript で期待動作を確認（pass/block/env override/bypass）
- harness-audit に新セクション追加、bypass.log を集計
- settings.json の SubagentStop に wired
- 想定外発見: config-loader.sh が env を上書きする件は capture→restore で解消

confidence: 0.9
```

## Bypass 経路（3 種）

| 方法 | スコープ | 痕跡 |
|---|---|---|
| `ECC_CONFIDENCE_GATE=off` | セッション全体 | env のみ（永続化なし） |
| `HC_CONFIDENCE_REQUIRED=false` | セッション全体（config 同等） | env のみ |
| `/gate-bypass confidence <reason>` | **次回 1 回のみ**（再 arm） | `bypass.log` に reason 記録 |

`/gate-bypass confidence ...` 経路は `/harness-audit` で**累計回数 + 直近 5 件**が可視化されるので
隠せない（honor system だが監査可能）。

## 監査

```bash
/harness-audit                    # human-readable
python3 .claude/scripts/harness-audit.py --json | jq .confidence_gate
```

JSON 出力例:

```json
{
  "bypasses": 3,
  "recent_reasons": [
    "2026-05-04T11:47:26Z\tbypassed: docs only edit",
    "2026-05-04T12:15:02Z\tbypassed: hot fix, user 承認済み",
    "2026-05-04T13:01:11Z\tbypassed: subagent transcript parse 失敗の暫定回避"
  ],
  "bypass_marker_pending": false
}
```

`bypass_marker_pending: true` のままセッションを終えた場合、次セッションの最初の SubagentStop が
1 回素通しになる点に注意（state は git ignore 管理なので別チェックアウトでは消える）。

## 既知の制約

- **transcript schema 依存**: Claude Code は `assistant` role の content を新旧両 schema
  （`type:assistant` / `role:assistant`）で出すため、jq 抽出は両対応している。今後の schema
  変更には追従修正が必要。
- **誤検出**: コード片中の `confidence: 0.5` が誤判定される可能性あり。最後の hit を採用するため
  「最終決定値を末尾に書く」運用が安全。
- **fail-open 寄り**: jq 不在 / transcript 抽出失敗 / `confidence_required:false` は全て pass。
  これは hook 自体が壊れて作業停止する事故を防ぐため意図的に fail-open。

## 関連

- `.claude/hooks/confidence-gate.sh` — 本体
- `.claude/commands/gate-bypass.md` — `/gate-bypass confidence ...` の仕様
- `docs/SELF_IMPROVEMENT.md` — F1 / F2 / F3 の位置づけ
- `.claude/scripts/harness-audit.py` — 監査出力
