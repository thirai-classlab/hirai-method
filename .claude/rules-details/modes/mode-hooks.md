> Layer A: [`modes.md`](../../rules/modes.md) §強制機構 (mode 系 hook) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# mode hook 詳細 (Layer B)

本 file は Layer A の SSoT を補完する詳細解説。mode-loader.sh 内部仕様 / mode-session-start.sh / mode-enforce.sh の context 注入詳細 / context-budget.sh tier 算出ロジックを含む。

## mode-loader.sh 内部仕様

`.claude/hooks/lib/mode-loader.sh` は全 mode 系 hook で source される共通 lib。

**API**:
- `get_mode()` — 現モードを stdout に出力 (`normal` or `loop`)
- 値解決順: `env(HC_MODE)` > `.claude/mode.yml` の `mode:` キー > `default(normal)`
- 値検証: 不正値は `normal` にフォールバック + stderr 警告

**fail policy**:
- `set -uo pipefail` (file-top に書かない、subshell 関数化で局所化、caller の shell flags への leak 防止)
- yml parse 失敗 → `normal` fallback (fail-open、セッション継続)

## mode-session-start.sh の context 注入

| 状況 | 動作 |
|---|---|
| Normal モード | 「現在 Normal モード。Loop モードへの切替は `/mode loop`」を SessionStart で 1 度だけ提案 |
| Loop モード | 「現在 Loop モード。停止は `/mode normal` or 「ストップ」発話」を表示 |
| mode.yml 不在 | `normal` 扱いで切替提案 (fail-open) |

## mode-enforce.sh の context 注入

| 状況 | 動作 |
|---|---|
| Loop モード | 毎ターン UserPromptSubmit で遵守事項 9 件を `<system-reminder>` で再注入 |
| Normal モード | no-op |
| 注入内容 | 遵守事項 9 件の見出しのみ (本文は modes.md 参照と link)、context 節約 |

## context-budget.sh tier 算出ロジック

| tier | ratio 閾値 | 動作 |
|---|---|---|
| 60 | `ratio >= 0.60` | `<system-reminder>` で `/save-state` 提案 |
| 80 | `ratio >= 0.80` | `<system-reminder>` で `/save-state` **強制実行** + 「新 session で `/resume-state` で復元するか継続するか」を user に提示 |
| 95 | `ratio >= 0.95` | `<system-reminder>` で緊急 `/save-state` + セッション終了案内 |

**spam 防止**:
- 同一 tier は 1 セッションあたり 1 度のみ発火
- 状態は `.claude/.workflow-state/context-budget-tiers.json` で永続化
- bypass: `HC_CONTEXT_BUDGET_ENABLED=false` で hook 全停止

**閾値変更**:
- `.claude/harness-config.yml` の `context_budget_threshold:` キーで上書き可
- `hc-config.sh --set context_budget_threshold='[60,80,95]'` で安全に変更可 (atomic backup + type validation)
