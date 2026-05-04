---
name: verification-loop
description: Comprehensive 6-phase verification system (build / type / lint / test / security / diff) for Claude Code sessions. Pair with GateGuard for full fact-check coverage. Replicated from ECC.
origin: ECC
---

# Verification Loop — 事後検証

GateGuard が「実行前の事実検証」を担うのに対し、Verification Loop は **PR 直前の事後検証** を 6 フェーズで実施。

## When to Use

- 機能実装の完了直後
- PR 作成直前
- リファクタリング後
- 品質ゲートを通したい全ての変更

## 6 Phases

### Phase 1: Build Verification

```bash
npm run build 2>&1 | tail -20
# or pnpm build / yarn build / cargo build
```

ビルド失敗 → STOP。修正してから次へ。

### Phase 2: Type Check

```bash
npx tsc --noEmit 2>&1 | head -30        # TypeScript
pyright . 2>&1 | head -30                # Python
mypy . 2>&1 | head -30                   # Python alt
```

エラー全件報告。critical なものは修正。

### Phase 3: Lint

```bash
npm run lint 2>&1 | head -30             # ESLint
ruff check . 2>&1 | head -30             # Python
golangci-lint run 2>&1 | head -30        # Go
```

### Phase 4: Tests + Coverage

```bash
npm run test -- --coverage 2>&1 | tail -50
```

報告:
- Total / Passed / Failed
- Coverage（80% 最低目標）

### Phase 5: Security Scan

```bash
# Secret 漏洩チェック
grep -rn "sk-" --include="*.ts" --include="*.js" . 2>/dev/null | head -10
grep -rn "api_key\|API_KEY" --include="*.ts" --include="*.js" . 2>/dev/null | head -10

# console.log 残留チェック
grep -rn "console.log" --include="*.ts" --include="*.tsx" src/ 2>/dev/null | head -10
```

### Phase 6: Diff Review

```bash
git diff --stat
git diff HEAD~1 --name-only
```

各変更ファイルで:
- 意図しない変更が混入していないか
- error handling 漏れ
- edge case 考慮

## Output Report

```
VERIFICATION REPORT
==================

Build:     [PASS/FAIL]
Types:     [PASS/FAIL] (X errors)
Lint:      [PASS/FAIL] (X warnings)
Tests:     [PASS/FAIL] (X/Y passed, Z% coverage)
Security:  [PASS/FAIL] (X issues)
Diff:      [X files changed]

Overall:   [READY/NOT READY] for PR

Issues to Fix:
1. ...
```

## Continuous Mode

長セッションでは 15 分毎 or 主要変更後に走らせる:

- 各関数完了後
- 各コンポーネント完了後
- 次タスクへ移る前

## Hook 連携

PostToolUse hook（Mermaid validator 等）が即時検出するのに対し、本スキルは **複数フェーズの統合検証** を提供する。

| | Hook | Verification Loop |
|---|:---:|:---:|
| 即時性 | ◎ | – |
| 網羅性 | – | ◎ |
| Build/Test 統合 | – | ◎ |
| 軽量 | ◎ | – |

## Slash Command

`/verify` で 6 phase 全実行 + report 生成。

## Integration

| 層 | 関係 |
|---|---|
| **L1** Eval Harness | 各 phase は eval grader として機能 |
| **GateGuard** | 事前ゲート↔事後検証のペア |
| **L4** Continuous Learning | 失敗 phase パターンを instinct 化 |
| **L5** Introspection | 失敗が続けば 4-Phase 自己診断へ |
