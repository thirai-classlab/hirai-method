> Layer A: [`development-process.md`](../../rules/development-process.md) §コーディング指針 / 出力 / 研究 (必読) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# 研究と再利用 詳細 (Layer B)

## 適用対象 task (完全 list)

- 新 library / package 採用前 (npm install / pnpm add / pip install 等の **直前**)
- 既存 library の major version migration (例: React 18 → 19、Next.js 14 → 16)
- API syntax / config / option の確認 (新 hook / 新 API 利用時)
- error message debug (library 由来 error の stack trace を context7 / 公式 docs と照合)
- 新機能 / lifecycle hook の利用 (例: Next.js Cache Components / use cache directive 等)

## 関連設定

- `.mcp.json` の context7 entry (`npx -y @upstash/context7-mcp@latest`、stdio transport)
- 採用 4 リポへ portable 同期済 (本 repo `.mcp.json` SSoT + `install.sh --update` で同期)
- subagent 委譲時も同 chain 適用 (Agent prompt に「library 仕様確認は context7 を最初に」と明示)

## bypass の補足

- MCP server fail (context7 unreachable / npx fail) で loop 停止しない構造は §「Bash deny / whitelist 不在時の subagent 委譲反射」と類似 (fail → fallback chain に自動 retry、停止理由にしない)
- 起源 memory: `feedback_verify_path_before_implementation.md` (verify before recommending 原則)
