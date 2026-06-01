> Layer A: [`development-process.md`](../../rules/development-process.md) §サブエージェント完了サマリ (Confidence Gate / F3 必須) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# confidence-gate 詳細 (Layer B)

## 記載例

```text
F3 confidence-gate.sh を実装し以下を確認:
- 6 ケースの mock transcript で期待動作を確認（pass/block/env override/bypass）
- harness-audit に新セクション追加、bypass.log を集計
- settings.json の SubagentStop に wired

confidence: 0.9
```

## major subagent only block (2026-05-13、task #9) の補足

F3 confidence-gate は **major subagent (`general-purpose` / `Explore` / `Task` allowlist or `is_sidechain==path_subagents`)** のみ confidence 自己評価を強制し、軽量 sidechain (Task tool query / 短い tool-use only sidechain) は **fail-open** で通過させる。

- env `HC_CONFIDENCE_MAJOR_AGENT_ONLY=false` で従来動作 (全 stop event で block 判定) に復帰可
- 設計起源: `docs/draft/harness-audit-followups.md` §3 W1 (2026-05-13)
- 観測: `/harness-audit` で `regex_no_match` 累計が major subagent 由来のみに絞られる
