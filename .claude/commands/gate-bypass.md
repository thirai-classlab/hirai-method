---
description: Pre-clear GateGuard for a specific file, or pre-pass the next Confidence Gate (F3) check.
---

# /gate-bypass

GateGuard 系を **事前 clear** する汎用コマンド。

| 形式 | 用途 |
|---|---|
| `/gate-bypass <file>` | F1 GateGuard: 指定ファイルの Edit/Write 両方を pre-clear |
| `/gate-bypass --edit <file>` | F1 GateGuard: Edit のみ |
| `/gate-bypass --write <file>` | F1 GateGuard: Write のみ |
| `/gate-bypass confidence <reason>` | F3 Confidence Gate: 次回 1 回 PASS（reason は bypass.log に記録） |

## F1 GateGuard bypass

すでに事実調査が済んでいる（サブエージェントの報告から得た等）ケースで、無駄なゲート発火を防ぐ。

### 動作

1. file path を SHA-256 12文字 hash 化
2. `.claude/.gateguard-state/edit-<hash>.cleared` と `write-<hash>.cleared` を `touch`
3. 次回の Edit/Write は通過

### 例

```bash
# サブエージェントから「auth.ts は影響範囲調査済み（importers 12 ファイル、API 不変）」と報告を受けた
/gate-bypass src/lib/auth.ts
# → cleared: edit-a1b2c3d4e5f6.cleared
# → cleared: write-a1b2c3d4e5f6.cleared
```

## F3 Confidence Gate bypass

サブエージェントの完了サマリから confidence が抽出できなかった / 閾値未満だが、メイン側で
別ルートの確証がある場合に使う **1 回限り** の通過 marker。

### 動作

1. `.claude/.confidence-gate-state/bypass.cleared` を作成（reason を本文に記入）
2. **次回 1 回** だけ confidence-gate.sh が PASS を返す
3. その際 `bypass.log` に `<ISO 時刻>\tbypassed: <reason>` を 1 行追記
4. marker は自動削除（**re-armed** — 2 回目以降は通常判定）

### 実体（cli から手動実行する場合）

```bash
mkdir -p .claude/.confidence-gate-state
printf '%s' "user 確認済み: docs only 修正" > .claude/.confidence-gate-state/bypass.cleared
```

### 例

```bash
/gate-bypass confidence "user 確認済み: docs only 修正で confidence 計測対象外"
# → .claude/.confidence-gate-state/bypass.cleared 作成
# → 次回 SubagentStop で 1 回 PASS し、bypass.log に記録
```

bypass の理由は `/harness-audit` で集計されるため、後から監査可能。

## 注意

- **honor system**: 事実調査を実際にせずに bypass するとゲートの意義を失う
- bypass の根拠は CLAUDE.md / docs/tasks/ の該当エントリに記録するのが望ましい
- F1: セキュリティ機微ファイルや migration には使わない
- F3: 連続 bypass は `/harness-audit` で可視化される（隠せない）

## 関連

- `/gate-status` — 何が cleared か確認
- `/gate-clear` — F1 取り消し
- `/harness-audit` — F3 bypass 集計（bypass.log 行数 + 直近 5 件 reason）
- skill: `.claude/skills/gateguard/SKILL.md`
- docs: [`docs/CONFIDENCE-GATE.md`](../../docs/CONFIDENCE-GATE.md)
