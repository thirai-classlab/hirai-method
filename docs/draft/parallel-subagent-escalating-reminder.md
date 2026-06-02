<!--
approval_required: true
approved_at: 2026-06-02
approved_by: takuma hirai (AskUserQuestion で escalating reminder approach を選択)
retroactive: false
-->

# parallel-subagent-reminder escalating 強化 (連続単発起動 streak で段階注入)

**ステータス:** draft (2026-06-02 起案、approach は user 承認済)
**起点:** user 指示「可能な限り並行で作業を適切なサブエージェントに降って作業を行うように修正してください」「memory ではなくハーネスの修正が必要です」
**対象:** `.claude/hooks/parallel-subagent-reminder.sh` + `.claude/tests/parallel-subagent-reminder-smoke.sh`

---

## 1. 問題 (現状の harness 欠陥)

`parallel-subagent-reminder.sh` (PreToolUse(Agent)) は、単発 Agent 起動 + 並列性 keyword 検出時に **advisory hint を 1 回注入するだけ**で、無視されても escalate しない。

実証 (2026-06-02 の超長 session、remediation plan task-69〜74): 同 hint が **~20 回発火**したのにメインが逐次 1 体ずつ起動を継続。advisory が弱く、繰り返し無視できる構造が真因。「ルールに書いて守らせる」でなく「hook で機械強制」の harness 原則 (CommonRules Design Constraints) に対し、本機構は強制力が不足。

## 2. あるべき姿

連続単発起動 (parallelizable なのに逐次) の **streak を検出し、段階的に reminder を強める**。BLOCK はしない (fail-open 維持、genuine 逐次依存もあるため) が、無視し続けにくくする。3+ fan-out は task-68 規範どおり Workflow ツールへ誘導。

## 3. 採用案 (escalating reminder、user 承認 2026-06-02)

### streak 定義
- **連続単発起動 streak** = 「単発起動 (本起動が並列 batch でない) かつ並列性 keyword 該当」が TTL 内に連続した回数。
- **streak リセット条件**: 同一 turn 内で複数 Agent が並列起動された (= recent state に近接 ts の複数 entry) / Workflow ツール使用 / TTL 経過 / 除外 keyword (reviewer 等) 起動。
- 既存 state (`recent.json`、ts+type 配列) を流用。streak は recent entries の近接 ts クラスタ判定 or 専用 counter で算出 (実装で決定、TTL filter 済 count と近接 gap で「連続単発」を導出)。

### 段階注入 (tier)
| streak | 注入内容 |
|---|---|
| 1 | 現状の advisory hint (維持) |
| 2 | **強い reminder**: 「直近 N 回連続で単発起動。独立作業なら**同一 message 内で複数 Agent を並列起動** (run_in_database true) するか、依存逐次なら次は意識的に。」 |
| ≥3 | **最強 reminder**: 「3+ の独立 fan-out は `Workflow` ツール (決定論 orchestration) を default 検討せよ (task-68)。逐次が必要な場合は genuine dependency (調査→実装→レビュー / 共有 file race) の理由を内部で明示。」 |

- 並列起動 or Workflow 検出で streak リセット → tier 1 に戻る。
- agent type 選定 reminder (Case 6-8、既存 B 機構) は不変。

### enforcement
- BLOCK しない (fail-open 維持)。escalation は `additionalContext` 注入の強度を上げるのみ。
- feature toggle `feature_parallel_subagent_reminder_enabled` 配下 (既存)。bypass `HC_PARALLEL_SUBAGENT_REMINDER_ENABLED=false` 不変。
- 新規 env: `HC_PARALLEL_SUBAGENT_STREAK_TIER2=2` / `HC_PARALLEL_SUBAGENT_STREAK_TIER3=3` (閾値 override、default 2/3)。

## 4. 実装方針

- `parallel-subagent-reminder.sh` の (A) 並列性 reminder 判定部に streak 算出 + tier 分岐を追加。state `recent.json` に「並列 batch 起動」マーカー (近接 ts 複数 entry) を見て streak を導出 (専用 streak counter file `streak.json` を追加してもよい、実装判断)。
- メッセージを tier 別に分岐 (1=現状 / 2=強 / 3=Workflow 誘導)。
- 既存の lock / fail-open / TTL / feature toggle ロジックは保持 (behavior-preserving、escalation 追加のみ)。

## 5. テスト (TDD)

`parallel-subagent-reminder-smoke.sh` (既存) に escalation case 追加:
- streak=1 → 現状 hint (既存 case 維持)
- streak=2 → 強 reminder 文字列 present
- streak≥3 → Workflow 誘導文字列 present
- 並列 batch 起動 (近接 ts 複数) → streak リセット (次回 tier 1)
- 除外 keyword / feature OFF / bypass → 既存挙動不変 (regression 0)

## 6. 受け入れ条件 (DoD)

- 連続単発起動で reminder が tier 1→2→3 に escalate する
- 並列/Workflow 起動で streak リセット
- BLOCK しない (fail-open 維持)、feature toggle / bypass 不変
- smoke で escalation + リセット + regression 0
- reviewer approve

## 7. リスクと緩和

| リスク | 緩和 |
|---|---|
| genuine 逐次依存 (調査→実装→レビュー) でも escalate して鬱陶しい | BLOCK でなく advisory のまま。tier 3 文言に「genuine dependency なら逐次 OK」を明記。除外 keyword (reviewer/review/監査/audit) は streak 加算しない |
| streak 算出が誤判定 (並列 batch を単発と誤認) | 近接 ts クラスタ判定の窓を適切に (同一 turn = 数秒以内)。誤判定しても fail-open で実害は「余分な hint」のみ |
| state file 肥大 | 既存 TTL filter + lock 機構を流用 |

## 8. 関連

- `.claude/hooks/parallel-subagent-reminder.sh` (task-38 由来、本 draft で escalation 強化)
- `.claude/rules/development-process.md` §並列化義務 + 多数 fan-out の Workflow 標準化 (task-68)
- `docs/draft/parallel-subagent-enforcement.md` (task-38 原設計)
