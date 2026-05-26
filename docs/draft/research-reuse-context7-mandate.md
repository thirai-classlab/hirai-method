<!--
approved_at: 2026-05-26
retroactive: false
approved_by: user
-->

# 外部 library / framework 仕様確認に context7 を default 利用する規範

## §1 真因 (背景)

本 session で context7 MCP server を `.mcp.json` に追加 (PR #14、merge 済) + 採用 4 リポへ portable 同期完了。ただし「AI が context7 を確実に使う」確証は MCP server instructions (session-start で自動注入される `## context7` block) に依存しており、以下のリスクが残る:

1. **environment 依存**: user の Claude Code instructions / global config が変更されれば AI 行動も変わる、project 規範として SSoT 化されていない
2. **採用先での一貫性**: ハーネス採用 4 リポで session-start instructions が config 差で変動する可能性
3. **AI 認知偏り**: 「training data で知っている library」を context7 確認せず推測実装するリスク (`Next.js` `React` `Prisma` 等の Familier library で発生しやすい)

### user 質問起源

「context7 を使うように `.claude/rules/development-process.md` に記載するのはどうですか?」(2026-05-26) → AI 推奨「入れた方が良い」→ user 「入れてください」承認。

## §2 採用案

| 案 | 内容 | 評価 |
|---|---|---|
| A | development-process.md に新 § 「研究と再利用 (research-reuse)」追加 | 規範 SSoT 化、paths auto-load で関連 task 時 context 投入確実 |
| B | CommonRules.md Development Policy に 1 行追加のみ | 軽量、ただし詳細 fallback chain / bypass を書きにくい |
| **C ハイブリッド** | A (詳細 section) + B (CommonRules.md Development Policy 1 行 cross-ref) | 詳細 + 集約、4 リポへ portable 同期も両 file 経由 |

→ **C ハイブリッド** 採用。

## §3 採用案 (実装仕様)

### 3.1 development-process.md 新 § 「研究と再利用 (research-reuse)」

`## 出力フォーマット` の後、`## TDD` の前に挿入 (= AI 行動規範の冒頭近傍、TDD 着手前の研究フェーズとして配置)。

内容:

> ## 研究と再利用 (research-reuse、必読)
>
> 新規実装 / 既存改修の **前** に、外部 library / framework / API の仕様を確認する義務がある。
>
> ### 仕様確認の fallback chain
>
> 1. **context7 MCP を最初に試行**: `mcp__context7__resolve-library-id` + `mcp__context7__query-docs` で公式 docs を fetch
>    - 対象: API syntax / config / version migration / lifecycle / deprecation 等の library-specific 内容
>    - 既知 library (Next.js / React / Prisma / Vercel AI SDK 等) でも **必ず確認** (training data outdated 回避)
> 2. **WebFetch で公式 docs 補完**: context7 が library 未対応 / 結果不足の場合、公式 docs URL を WebFetch
> 3. **GitHub code search / Exa**: 実装例が必要な場合 `gh search code` / Exa neural search で battle-tested pattern を探索
>
> ### 適用対象 task
>
> - 新 library / package 採用前
> - 既存 library の major version migration
> - API syntax / config / option の確認
> - error message debug (library 由来の場合)
> - 新機能 / lifecycle hook の利用
>
> ### bypass
>
> - MCP server fail (context7 unreachable 等) で loop 停止しない (development-process.md §5「Bash deny / whitelist 不在時の subagent 委譲反射」と類似構造、fail → WebFetch fallback chain に自動 retry)
> - 「training data で確信あり」を理由に context7 skip しない (verify before recommending 原則、memory `feedback_verify_path_before_implementation.md` 起源)
>
> ### 関連
>
> - `.mcp.json` の context7 entry (PR #14、`npx -y @upstash/context7-mcp@latest`)
> - 採用 4 リポへ portable 同期済 (本 PR merge + `install.sh --update` で同期)

### 3.2 CommonRules.md Development Policy bullet 追記

`## Development Policy` の既存 bullet 末尾に 1 行追加:

> - **外部 library / framework 仕様確認**: context7 MCP を default 利用 (既知 library でも training data outdated 回避)、fallback chain 詳細は `.claude/rules/development-process.md` §「研究と再利用」参照

### 3.3 既存 rule file との整合

- `.claude/rules/development-process.md` の §「サブエージェント委譲 (Hook で強制)」内、subagent 委譲先 listing に `Web 調査 → Agent 内で WebSearch/WebFetch` の bullet 既存 → 本 § 追加で「最初に context7 試行」を明文化、subagent 委譲も同 chain 適用
- ~/.claude/rules/common/development-workflow.md user global rule にも類似記述あり (Research & Reuse §0) → project rule とは別 layer (user environment) で並存、project rule が SSoT

## §4 TDD 戦略

規範文書追記のため RED → GREEN → REFACTOR の典型 TDD は適用外。代わりに以下で検証:

### 検証手段

1. **grep 検証**: `grep -c "context7" .claude/rules/development-process.md` ≥ 5 hit (新 § + 既存箇所)
2. **grep 検証**: `grep -c "context7" .claude/CommonRules.md` ≥ 1 hit (Development Policy bullet)
3. **paths auto-load 動作確認**: development-process.md の paths frontmatter (`src/**`, `scripts/**`, `tests/**`, `docs/tasks/**`, `docs/draft/**`) は変更不要、既存 scope のまま auto-load 継続
4. **draft-flow-guard 通過確認**: 本 draft (`docs/draft/research-reuse-context7-mandate.md`) で `approved_at:` 非空 → development-process.md / CommonRules.md への Edit が hook BLOCK されないこと

### smoke 新設は不要

規範文書 1 § 追加 + Development Policy 1 行追加のみで、機械的 hook 追加なし。既存 smoke (rule-change-draft-flow-guard-smoke.sh) で本 draft 経路の通過を確認できる (Case 14 YAML 起源)。

## §5 Step 計画

| Step | Status | 作業概要 | 完了条件 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | draft + task file + list.md row | 全 file 存在、draft `approved_at: 2026-05-26` |
| 2 | 🔲 | development-process.md 新 § 「研究と再利用」追加 (subagent staging) | grep "## 研究と再利用" 1 hit |
| 3 | 🔲 | CommonRules.md Development Policy bullet 追記 (main 直接 Edit) | grep "context7 MCP" 1+ hit in CommonRules.md |
| 4 | 🔲 | (テスト設計レビュー skip 明示) 規範文書追記のみで reviewer 5+ 並列起動 overkill | skip 理由を Step 内で明示 |
| 5 | 🔲 | (テスト合格) grep 検証 3 件 (development-process.md / CommonRules.md / draft 整合) + draft-flow-guard 通過実証 | 3 件全 PASS |
| 6 | 🔲 | (リファクタリング) skip 明示: 規範追記のみで refactor 余地なし | skip 理由を Step 内で明示 |
| 7 | 🔲 | commit + push + PR create | PR URL 提示 |
| 8 | 🔲 | 4 リポ user manual install 案内 (`bash install.sh --update`) | install command 提示 |

## §6 DoD

- [ ] `docs/draft/research-reuse-context7-mandate.md` 存在 + `approved_at` 非空
- [ ] `.claude/rules/development-process.md` に新 § 「研究と再利用」追加
- [ ] `.claude/CommonRules.md` Development Policy に context7 1 行追加
- [ ] grep 検証 3 件全 PASS
- [ ] draft-flow-guard 通過 (development-process.md Edit が block されない)
- [ ] PR create + user merge 案内
- [ ] 4 リポ user manual install 案内

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| ファイル (新規) | `docs/draft/research-reuse-context7-mandate.md` / `docs/tasks/task-43-research-reuse-context7-mandate.md` |
| ファイル (修正) | `.claude/rules/development-process.md` (新 § 追加) / `.claude/CommonRules.md` (Development Policy 1 行) / `docs/tasks/list.md` (task-43 row 追加) |
| ファイル (test) | なし (規範文書追記のみ、既存 rule-change-draft-flow-guard-smoke で間接検証) |
| migration | なし |
| 環境変数 | なし |
| 互換性 | 採用 4 リポは `install.sh --update` で `.claude/rules/development-process.md` + `.claude/CommonRules.md` 自動同期 |

## §8 レビューサイクル

| iter | reviewer | CRITICAL | HIGH | MEDIUM | LOW | 状態 |
|---|---|---|---|---|---|---|
| (skip 明示) | — | — | — | — | — | 規範文書追記のみ reviewer 5+ 並列 overkill、Step 4 で skip 理由明示 |

## §9 関連

- 起源: 2026-05-26 user 質問「context7 を使うように development-process.md に記載するのはどうですか?」 + AI 推奨「入れた方が良い」 + user 「入れてください」承認
- 関連 task: task-42 (CLAUDE.md slim 化 + CommonRules.md 切り出し、PR #13 merge 済) + context7 MCP `.mcp.json` 追加 (PR #14 merge 済、前提)
- 関連 memory: `feedback_verify_path_before_implementation.md` (verify before recommending 原則と整合)
