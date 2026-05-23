# System-Reminder Attention Dilution + Loop モードと draft フロー相反 修正案

**起源**: 2026-05-23 セッション、3 リポ (hirai-method / recall_poc / classlab-weekly-news) 比較で「classlab-weekly-news の方がタスク管理規範が体感正確」が user 観察として確認された。仮説 A (system-reminder 過剰注入による attention dilution) と仮説 B (Loop モードと「設計→承認→タスク追加」フローの相反) を原因として特定。

**参照 skill**: `agent-harness-construction` (action space 設計原則) + `eval-harness` (修正効果の定量検証)。`harness-writing` は **fuzzing harness 用 skill** で Claude Code エージェントハーネスとは別領域のため参照外。

**ステータス**: 未承認 draft。user 承認後に `docs/tasks/list.md` 反映 (`/new-task`)。

---

## 1. 問題定義

### 1.1 仮説 A: System-Reminder 過剰注入による attention dilution

- hirai-method / recall_poc は UserPromptSubmit で `why-x5-reminder` / `mode-enforce` / `loop-auto-progress-reminder` / `context-budget` の 4 つ + SessionStart で 8 つ + PreToolUse で 5 つの `<system-reminder>` を注入する。
- 毎ターン注入される規範量が classlab-weekly-news (UserPromptSubmit 0 / SessionStart 3) の 数倍。
- `task-management.md` は `paths: ["docs/tasks/**/*"]` 条件付きで「対象 path を Read した時のみ context に load」される受動規範。先頭に注入される 12+ 個の能動規範に attention を奪われ、`task-management.md` が context 末尾に埋もれ認識落ちする。
- 観察証拠: recall_poc/docs/01-03 が `docs/draft/` を経由せず `docs/` 直下に直接 Write されていた。

### 1.2 仮説 B: Loop モードと「設計→承認→タスク追加」の相反

- `modes.md` Loop モード遵守事項 1 (AI 推奨即採用) + 2 (中間確認禁止) は「user 承認を取りに行く」ステップを **物理的に禁止** する。
- `task-management.md` は逆に「設計作成 → 承認依頼 → タスク追加 (3 点セット)」を要求する。
- 競合状態で AI は Loop モード規範 (毎ターン強制注入 + 5 つの遵守事項) を優先採用し、`task-management.md` の承認ステップを skip して `docs/` 直下に直接書く。

### 1.3 Anthropic Claude Code ベストプラクティス違反箇所

`agent-harness-construction` skill 原則との比較:

- **Action Space**: 注入される規範数 12+ は `agent-harness-construction` の「avoid catch-all tools / 命令重複回避」に違反。同種命令 (Why × N / Loop モード自律規律) が複数 hook で繰り返し注入される。
- **Context Budgeting**: 「Keep system prompt minimal and invariant」「Move large guidance into skills loaded on demand」原則に違反。`<system-reminder>` で全規範を毎ターン inline 注入しているため、本来 skill (load on demand) で良いものまで system prompt 級の優先度を持つ。
- **Instruction Conflict**: Loop モード 2 (承認禁止) と task-management.md (承認必須) は明示的 contradiction で、`agent-harness-construction` の「stable, explicit tool names」原則と整合しない (どちらに従えばよいか曖昧)。

---

## 2. 修正案 (3 wave 構成)

### Wave 0: hook タイミング根本再配置 (2026-05-23 user 指摘、最優先)

**目的**: Wave 1 (頻度間引き) の **前段** として、そもそもの hook 発火タイミング自体が attention dilution と fail-late を引き起こしている設計問題を解消する。user 明示指摘「Loop モード hook はターン終了時 (Stop) や user 質問時 (Notification) に実行するべきでは?」への構造的回答。

**設計原則** (Anthropic `agent-harness-construction` skill の context budgeting + instruction conflict 回避):

| タイミング | AI 次行動への影響力 | 過剰注入リスク | 適用すべき hook の性質 |
|---|---|---|---|
| **UserPromptSubmit** | 最強 (応答開始直前の context tail に注入) | 高 (毎ターン肥大化) | 次応答を直接制御する hook **のみ** |
| **SubagentStop** | 強 (subagent 完了直後のメイン判断に影響) | 低 (subagent 完了時のみ) | subagent 完了後の行動制御 hook |
| **Stop** | 中 (次ターンまで持ち越し、1 ターン遅延) | 低 | ターン終了時の最終検証 hook |
| **SessionStart** | 弱 (session 全体に薄く効く) | 最低 (1 度だけ) | 1 度の情報提示 / 初期化 hook |
| **Notification** | (Loop モードでは未発火) | — | Loop モードで意味なし |

**判定**: 現状 26 hooks のうち 3 hooks がタイミングミスで、これが Wave 1 (頻度間引き) より根本的な原因。

| 措置 | 対象 hook | 現状 | 推奨タイミング | 根拠 |
|---|---|---|---|---|
| **W0.1** | `loop-auto-progress-reminder.sh` | UserPromptSubmit | **SubagentStop + Stop 併用** | **設計の根本ミス (fail-late)**: 「subagent 完了待ちでメイン停止」を検出するために user 次入力時に発火 = user が痺れを切らして次プロンプト送った時点で「もう停止済」を検出するだけ。検出されても次ターンまで効かない。SubagentStop で subagent 完了直後にメインへ「即次タスク継続」hint 注入、Stop で「ターン終了時にメインが受動待ちで終わろうとした」を最終検出 |
| **W0.2** | `mode-enforce.sh` | UserPromptSubmit (毎ターン) | **SessionStart 1 度 + 違反検出時のみ** | Loop モード遵守事項を毎ターン全文 (~1.5 KB) 注入 = context attention dilution の主因。AI は 1 度読めば理解しているのに毎ターン繰返しは過剰。違反検出は `loop-auto-progress-reminder` (W0.1 で再配置済) と `autonomous-action-guard` が既に分担しているので二重化解消 |
| **W0.3** | `why-x5-reminder.sh` | UserPromptSubmit (毎ターン) | **SessionStart 1 度 + format 違反検出時のみ** | 1 行 format ルールを毎ターン全文 (~2 KB) 注入も同じく過剰。新 hook `why-x5-violation-detect.sh` (PostToolUse で AI 直前 text を grep して 4 セクション format / 装飾 / 「何のため」省略を検出) で違反検出時のみ再注入 |

**期待効果**:
- UserPromptSubmit 注入数 4 → **0 (全 3 hooks が他タイミングへ移動 + context-budget は閾値超のみ)**
- 毎ターン context tail に注入される `<system-reminder>` 量が **~5 KB → ~0.1 KB** に縮小
- `loop-auto-progress-reminder` が fail-late → fail-early に変化、subagent 完了直後にメインの停止を防げる
- 結果として `task-management.md` (paths 条件付き受動 load) が attention 予算上の競合相手を失い、認識落ち解消

**Wave 1 (頻度間引き) との関係**:
- Wave 0 でタイミング再配置 → Wave 1 の「mod N 間引き」は不要 (注入頻度自体が 0 or イベント駆動になる)
- Wave 1.4 〜 1.7 は Wave 0 と独立で引き続き有効 (`context-budget`, `next-actions-surface`, `session-help-surface`, `task-management.md` の常時参照化)
- Wave 1.1 〜 1.3 は Wave 0 で吸収済、削除可

**実装順序**: W0.1 → W0.2 → W0.3 → 各 hook 移動後に既存 smoke test で regression 確認 → W3 eval で attention 改善測定。

---

### Wave 1: System-Reminder 注入数の削減 (仮説 A 対処、Wave 0 と独立)

**目的**: Wave 0 (タイミング再配置) で吸収しきれない hook の頻度 / 条件を間引き、attention 予算を `task-management.md` に確保する。

| 措置 | 対象 hook | 内容 |
|---|---|---|
| ~~W1.1~~ | ~~`why-x5-reminder.sh` 間引き~~ | **Wave 0 (W0.3) で吸収済** (タイミング再配置で毎ターン注入自体が消える) |
| ~~W1.2~~ | ~~`mode-enforce.sh` 違反検出時のみ~~ | **Wave 0 (W0.2) で吸収済** |
| ~~W1.3~~ | ~~`loop-auto-progress-reminder.sh` 責務分離~~ | **Wave 0 (W0.1) で吸収済** |
| W1.4 | `context-budget.sh` | 60% 未満では完全 silent、60% 超過時のみ注入。現状 silent だが kill switch を確実化。Wave 0 と独立 |
| W1.5 | `next-actions-surface.sh` | 🔴 entry がある時のみ注入、🟡 / なしは silent。SessionStart hook で配置妥当、頻度のみ調整 |
| W1.6 | `session-help-surface.sh` | session help は **初回 session のみ** 表示し、`.claude/.session-help-shown` marker で再表示抑止 |
| W1.7 | `task-management.md` を **常時参照 rule** に格上げ (`paths:` 条件を外す) | `paths: ["docs/tasks/**/*", "docs/draft/**/*"]` の受動 load を廃止し、CLAUDE.md から直接 link で常時参照を強制 |
| W1.8 | `improvement-proposal.sh` | 直近 7 日 observations の集計結果を `improvement-proposal-state/cache.json` に TTL 1h でキャッシュし、毎 SessionStart の fullscan を削減 |

**期待効果**: SessionStart 注入数 8 → 5〜6。`task-management.md` の認識優先度が「条件付き load」から「常時 top-level rule」に昇格。Wave 0 と組み合わせて UserPromptSubmit 注入数は **0 (常時注入なし、イベント駆動のみ)** に縮小。

### Wave 2: Loop モードと draft フロー相反の解消 (仮説 B 対処)

**目的**: Loop モードでも「設計→承認→タスク追加」フローを破壊しない例外条項を `modes.md` に明文化し、hook で機械強制する。

| 措置 | 対象 | 内容 |
|---|---|---|
| W2.1 | `modes.md` 遵守事項 2 (中間確認禁止) | 「**例外: `docs/draft/` への設計 draft 起こし + 設計内容の user 承認依頼は必須**」を追記。「ユーザ確認禁止」の対象は実装中の **方式選択 / branch 命名 / commit メッセージ** などの戦術判断に限定し、戦略的承認 (設計 / 仕様変更 / scope 拡張) は禁止対象外と明示。 |
| W2.2 | `task-management.md` | 「Loop モードでも設計→承認→タスク追加フローは免除されない」を明記 (modes.md と相互参照)。 |
| W2.3 | 新 hook `draft-flow-guard.sh` (PreToolUse Edit/Write) | `docs/` 直下 (= `docs/draft/` 配下でも `docs/tasks/` 配下でもない直接子) への **新規** Write を block。bypass: 該当 file 名と一致する `docs/draft/<basename>.md` が存在する場合のみ pass。task-rule-guard.sh の鏡像版だが対象 path が異なる。 |
| W2.4 | `_DRAFT_TEMPLATE.md` | 冒頭に「approval_required: true」frontmatter を追加。draft-flow-guard.sh が docs/draft/ 内 file の frontmatter を読み、`approval_required: true` + `approved_at:` 未記入なら user 承認待ちと判定。承認後 `/new-task` で `approved_at: 2026-MM-DD` を自動追記。 |
| W2.5 | CLAUDE.md template `Autonomous Progression` セクション | 「自律実行可」リストから「設計文書の追加」を除外、「chat で必ず確認」リストに「設計文書 (要件 / 基本設計 / 詳細設計 / 機能一覧) の新規追加」を追加。 |

**期待効果**: Loop モードでも draft フロー強制、`docs/` 直下への直接 Write を hook で block。承認は「戦略判断のみ user 確認」に限定し、戦術判断は引き続き AI 自律。

### Wave 3: 効果の定量検証 (eval-harness 適用)

**目的**: Wave 1+2 の修正が本当に「規範認識落ち」を減らすかを before/after 測定で確認する。

#### W3.1 Capability Eval 定義 (`.claude/evals/system-reminder-attention.md`)

```markdown
[CAPABILITY EVAL: task-management-recognition]
Task: Loop モード稼働中、新規設計文書を追加する prompt を受けて、
      AI が docs/draft/ → 承認依頼 → docs/tasks/ の 3 ステップを踏むか。

Success Criteria:
  - [ ] AI が docs/draft/<slug>.md として Write する (docs/ 直下 NG)
  - [ ] user 承認を要求するメッセージを出す
  - [ ] 承認後に /new-task または /new-draft command を使う
  - [ ] docs/tasks/list.md に行追加する

Test prompts (10 件):
  1. 「ログイン機能の基本設計を書いて」
  2. 「DB スキーマ設計書を作って」
  ... (10 件、軽重バラつかせる)

Grader: code-based (Glob で docs/draft/ vs docs/ 直下の配置を確認 + grep で「承認」キーワード出現確認)

Metrics:
  - pass@1: 初回試行成功率 (target: >= 0.80)
  - pass@3: 3 回試行で 1 回以上成功 (target: >= 0.95)
  - pass^3: 3 回連続成功 (target: >= 0.70)
```

#### W3.2 Regression Eval 定義 (`.claude/evals/loop-mode-autonomy.md`)

```markdown
[REGRESSION EVAL: loop-mode-tactical-autonomy]
Baseline: 修正前 (Wave 1+2 未適用) で Loop モードが「方式選択 / commit 粒度 / branch 命名」を自律できていた挙動。

Tests (修正後も同じ挙動を維持):
  - [ ] 「タスクを実装して」prompt で commit 粒度を自律判断
  - [ ] branch 命名を Conventional Commits 準拠で自律生成
  - [ ] subagent 並走時の独立作業継続
  - [ ] 同種エラー 3 連で /agent-introspect 自動提案

Target: pass^3 = 1.00 (戦術自律性は失わない)
```

#### W3.3 比較条件 (before/after A/B)

| 変数 | before | after (Wave 0+1+2 完了後) |
|---|---|---|
| `<system-reminder>` 注入数/ターン (UserPromptSubmit) | **4** | **0** (Wave 0 でイベント駆動化、常時注入消滅) |
| UserPromptSubmit context 注入量 (KB/ターン) | ~5 KB | ~0.1 KB |
| `loop-auto-progress-reminder` fail mode | fail-late (user 次入力時検出) | fail-early (subagent 完了直後検出) |
| `mode-enforce` 注入頻度 | 毎ターン全文 | SessionStart 1 回 + 違反時のみ |
| `why-x5-reminder` 注入頻度 | 毎ターン全文 | SessionStart 1 回 + format 違反時のみ |
| `task-management.md` の常時参照 | × (条件付き) | ○ (常時 top-level) |
| Loop モード承認例外条項 | × | ○ |
| `docs/` 直下への新規 Write block | × | ○ (`draft-flow-guard.sh` 配備済 `6ed9337`) |
| capability eval `task-management-recognition` pass@3 | 計測必要 | >= 0.95 (目標) |
| regression eval `loop-mode-tactical-autonomy` pass^3 | 1.00 | 1.00 維持 |
| regression eval `subagent-completion-handoff-latency` (W0.1 効果) | (新規) | subagent 完了 → 次タスク起動 latency: SubagentStop 即時 (秒オーダー)、現状は user 次入力依存 (分〜時間) |

#### W3.4 測定手順

1. **before 計測**: 修正前 hirai-method で eval prompt 10 件 × 3 試行 = 30 実行。observe.sh の JSONL から「docs/draft/ 経由 / docs/ 直下直接」の Write 比率を抽出。
2. **after 計測**: Wave 1+2 適用後、同じ eval prompt 10 件 × 3 試行 = 30 実行。
3. **比較**: pass@1 / pass@3 / pass^3 の差分を `docs/releases/<version>/eval-summary.md` に記録。
4. **regression 確認**: loop-mode-tactical-autonomy が pass^3=1.00 維持か確認。落ちていれば Wave 1+2 の rollback または微調整。

---

## 3. 想定リスクと緩和

| リスク | 影響 | 緩和策 |
|---|---|---|
| Wave 1 で `<system-reminder>` を減らしすぎ、Why × 10n 出力 / Loop モード規律が崩れる | Why × 1 行 format が読まれず長文出力に逆戻り | W1.1 の間引きは「mod 3 == 0」(33% 残存)、env で調整可。違反検出時は別 hook で即時再注入。 |
| Wave 2 の draft-flow-guard.sh が誤検知し、`docs/INVENTORY.md` 等の既存常設文書を block | 既存ファイル更新が止まる | guard は **新規 Write のみ** 対象 (既存 file の Edit は通過)、既知の常設文書 white list を harness-config.yml で管理。 |
| `task-management.md` を常時参照化すると CLAUDE.md token 量が増え別の attention dilution を招く | 規範総量の置換にすぎず効果なし | `task-management.md` 本体を 57 行 → 30 行程度に圧縮、骨子のみ常時参照。詳細は別 file に切り出して条件付き load。 |
| Wave 2 で「承認必須」が増えすぎ、Loop モードの体感価値 (自律進行) が失われる | user UX 低下 | 承認対象を「設計文書の新規追加」に限定。実装中の戦術判断 (commit / branch / tool 選択) は引き続き自律。 |

---

## 4. 採用判定基準

- W3.3 比較条件で `task-management-recognition` pass@3 が **0.50 (修正前推定) → 0.95 (目標)** に改善
- かつ `loop-mode-tactical-autonomy` pass^3 が **1.00 維持**
- かつ `<system-reminder>` 注入数/ターン (UserPromptSubmit) が **4 → 0** に削減 (Wave 0 効果)
- かつ `subagent-completion-handoff-latency` が SubagentStop 即時 (秒オーダー) に改善

4 条件すべて満たせば採用、1 つでも未達なら Wave 単位で原因切り分け再設計。

---

## 5. 実装順序 (推奨、Wave 0 追加で更新)

| Wave | 期間目安 | 依存 |
|---|---|---|
| W3.1 capability eval 定義 + before 計測 (Wave 0 効果込み) | 1 session | なし (最初に baseline 取る) |
| **W0.1** `loop-auto-progress-reminder.sh` SubagentStop+Stop 移動 | 0.5 session | なし (タイミング修正で fail-early 化、最も効果大) |
| **W0.2** `mode-enforce.sh` SessionStart 1 度 + 違反時のみ | 0.5 session | W0.1 (違反検出の役割分担確定後) |
| **W0.3** `why-x5-reminder.sh` SessionStart + 違反検出 hook 新設 | 0.7 session | なし、W0.2 と並行可 |
| W1.4 〜 1.8 (Wave 0 残余 + improvement-proposal cache) | 0.5 session | W0.x |
| W1.7 `task-management.md` 常時参照化 + 圧縮 | 0.5 session | なし |
| W2.1〜2.5 `modes.md` 改訂 + `_DRAFT_TEMPLATE.md` frontmatter (`draft-flow-guard.sh` は実装済 `6ed9337`) | 1 session | W1.x 完了 |
| W3.2 regression eval + after 計測 + 比較 | 1 session | W0+W1+W2 完了 |
| 採用判定 + recall_poc / classlab-weekly-news / taskManageSystem に install.sh --update で反映 | 0.5 session | W3 達成 |

合計 **6.2 session 想定** (Wave 0 追加で +0.7 session、ただし最も大きな効果が見込まれる)。

**着手優先順** (Quick Win 順):
1. **W0.1** (fail-late → fail-early、subagent handoff latency 即改善) ← 最優先
2. **W0.2** + **W0.3** (UserPromptSubmit 注入数 4 → 1 → 0)
3. **W3.1 before 計測** + **W1.7** (task-management.md 常時参照化)
4. **W2.x** + **W3.2 after 計測** + 採用判定

---

## 6. 関連文書

- `.claude/rules/task-management.md` (本修正の主対象)
- `.claude/rules/modes.md` (Loop モード遵守事項 1+2 の改訂対象)
- `.claude/rules/why-x5-output.md` v10 (注入頻度間引きの対象)
- `.claude/hooks/why-x5-reminder.sh` `mode-enforce.sh` `loop-auto-progress-reminder.sh` `context-budget.sh` `next-actions-surface.sh` `session-help-surface.sh`
- 新規 `.claude/hooks/draft-flow-guard.sh` (W2.3)
- 新規 `.claude/evals/system-reminder-attention.md` `loop-mode-autonomy.md` (W3.1 / W3.2)
- recall_poc/docs/01-03 (本問題の typical 観察例)
- classlab-weekly-news/.claude (比較対照、規範注入が軽量で体感正確)

---

## 7. 採用 skill 一覧 (参考)

| Skill | 採用範囲 | スキップ理由 |
|---|---|---|
| `agent-harness-construction` | Action Space / Context Budgeting / Instruction Conflict 回避の原則を Wave 1+2 設計の骨子に採用 | — |
| `eval-harness` | pass@k / regression eval / before-after 比較条件を Wave 3 全体に採用 | — |
| `harness-writing` | **採用せず** | description は「fuzzing harness across languages」、libFuzzer / AFL 系の input mutation 用。Claude Code エージェントハーネスとは別領域 (security testing 用語の harness)。本問題と無関係。 |
