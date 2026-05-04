---
description: Run 6-phase verification (build / type / lint / test / security / diff) and produce a READY/NOT READY report. ECC verification-loop replica.
---

# /verify

PR 直前の事後検証を 6 フェーズで実施。

## 使い方

```
/verify              # 全フェーズ
/verify --quick      # build + test + diff のみ
/verify --security   # Phase 5 のみ
```

## 動作

1. **Phase 1 Build**: `npm run build` / `pnpm build` / `cargo build`
2. **Phase 2 Type**: `tsc --noEmit` / `pyright` / `mypy`
3. **Phase 3 Lint**: `eslint` / `ruff` / `golangci-lint`
4. **Phase 4 Tests**: 全テスト実行 + coverage 計測（80% 目標）
5. **Phase 5 Security**: secret パターン / console.log 残留 を grep
6. **Phase 6 Diff**: `git diff --stat` で変更レビュー

各 phase で FAIL なら停止して修正提案。

## レポート例

```
VERIFICATION REPORT
==================

Build:     PASS
Types:     PASS (0 errors)
Lint:      PASS (3 warnings)
Tests:     PASS (245/245, 87% coverage)
Security:  PASS (0 issues)
Diff:      12 files changed

Overall:   READY for PR

Warnings:
- src/utils/format.ts:42 — unused import (auto-fixable)
```

## 関連

- skill: `.claude/skills/verification-loop/SKILL.md`
- 事前ゲートとペア: `.claude/skills/gateguard/SKILL.md`
- L1: `.claude/skills/eval-harness/SKILL.md`
