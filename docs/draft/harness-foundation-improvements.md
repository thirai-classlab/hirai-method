# Harness Foundation Improvements — performance / doc / refactor / drift 検出 のクラスタ修正

**ステータス:** 🔲 **draft (2026-05-23 起案、user 承認待ち)**
**起点:** 2026-05-23 ハーネス網羅分析の MED 案件クラスタ。HIGH (task-21〜24 で個別 task 化) より優先度低いが量が多い改善群を 1 epic にまとめる
**前提:**
- task-21 (system-reminder-attention-fix) と task-22 (hook-reliability-uplift) は本 task と独立並行可能
- 大型 hook 分割は behavior-preserving 必須

**関連 fixture / rule:**
- `.claude/hooks/improvement-proposal.sh` (491 LOC)
- `.claude/hooks/delegation-guard.sh` (400 LOC)
- `.claude/hooks/confidence-gate.sh` (356 LOC)
- `README.md` `CLAUDE.md` (placeholder 残置 / install.sh 未明記)

---

## 1. 真因サマリ / 課題サマリ

2026-05-23 の網羅分析で **10 件の MED 級 改善案件** が判明。個別 task 化すると粒度が小さすぎるため、性質別に 1 epic にまとめる:

- **P-2**: check-md-mermaid.sh timeout 90s (初回 npx mermaid@11 30MB pull) → README で local install 案内
- **P-3**: SessionStart 8 hooks 直列発火合計 28s timeout → 並列発火 or async 化
- **P-4**: observe.sh 全 tool 呼び出しに 6s overhead → tool 種別 sampling
- **C-9**: observe.sh project_id 未解決時の global fallback で project 混線 → `unknown-cwd-<hash>` 区分
- **C-10**: settings.local.json drift 検出機構なし → `/harness-audit` に drift check 追加
- **D-1**: 未着手 draft 15 件が docs/draft/ で滞留 → `/harness-audit` で 90 日超 list、parking-lot 移行 helper
- **D-2**: improvement-proposal.sh 491 LOC / delegation-guard.sh 400 LOC / confidence-gate.sh 356 LOC が肥大化 → lib/*.sh 分割
- **D-3**: hirai-method 本体 CLAUDE.md に template `<例: 公開/非公開フィルタは RLS で...>` placeholder 残置 → 削除 or 実 Lesson 化
- **Doc-2**: README install セクションが setup.sh ベース、install.sh への移行未反映 → rewrite
- **Doc-3**: 3 リポ (hirai-method / recall_poc / classlab-weekly-news / taskManageSystem) の世代差 diff レポート不在 → `/harness-audit --compare <other-repo>` 新設

**真因**: ハーネス機能拡張 (26 hooks) に対し、性能監視 / documentation 同期 / drift 検出 / 大型 hook の refactor が遅れている。

**副次**: いずれも単独では blocker でないが、累積すると新規 採用者の体験を悪化させる。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | 10 件を個別 task 化 (task-25〜34 とか) | 4.0 | 粒度最適、独立 commit | task 管理コスト膨大 |
| **B** | 全 10 件を本 epic 1 task で逐次対処 | 3.0 | 管理コスト最小 | 部分完了で blocker 残る可能性 |
| **C ハイブリッド** | 性質別 3 サブ epic (performance / doc / refactor+drift) | 3.5 | 粒度と管理コストの折衷 | サブ epic 間依存に注意 |

→ **C ハイブリッド** を推奨。サブ epic 単位で Wave 化、各 Wave 完了で個別 commit。

---

## 3. 採用案の詳細設計

### Wave 分割 (3 サブ epic × N Wave)

#### Sub-epic A: Performance (P-2 / P-3 / P-4)

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| A1 | README に `npm i -D mermaid@11 jsdom` local install 案内追加 + check-md-mermaid.sh で local 優先 fallback | 0.2 |
| A2 | SessionStart hook 群を並列発火 (`&` バックグラウンド + wait) に変更 | 0.5 |
| A3 | observe.sh で tool 種別 sampling (Read/Grep/Glob は 100%、Bash は 100%、Edit/Write は 100%、Agent/Task は 100% → 当面全件継続、必要時に Glob/Read のみ skip 検討) | 0.3 |

#### Sub-epic B: Documentation (D-3 / Doc-2 / Doc-3)

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| B1 | hirai-method 本体 CLAUDE.md の `<例: ...>` 行 5-7 を実 Lessons に書き換え (本 session の draft-flow-guard 教訓を 1 件追加) | 0.2 |
| B2 | README install セクションを install.sh ベースに rewrite、setup.sh deprecate 注記 | 0.3 |
| B3 | `/harness-audit --compare <other-repo>` 新設 (rules / hooks / commands の 3 リポ間 diff レポート) | 0.7 |

#### Sub-epic C: Refactor + Drift (D-1 / D-2 / C-9 / C-10)

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| C1 | 大型 3 hooks (improvement-proposal / delegation-guard / confidence-gate) を `.claude/hooks/lib/*.sh` 分割 (behavior-preserving) | 1.2 |
| C2 | `/harness-audit` に「未着手 draft 90 日超」list + parking-lot 移行 helper 表示 | 0.3 |
| C3 | `/harness-audit` に settings.local.json drift check (existing template との diff) 追加 | 0.3 |
| C4 | observe.sh の project_id 未解決時 fallback を `unknown-cwd-<hash>` に変更 (現状 global pool に流入で混線、再分類困難) | 0.3 |

合計: 4.3 session (Sub-epic A 1.0 + B 1.2 + C 2.1)

### Sub-epic A 詳細

#### A1: mermaid local install 推奨
- README の install セクション末尾に「(推奨) `npm i -D mermaid@11.13.0 jsdom`」を追加
- check-md-mermaid.sh で `node_modules/mermaid` 存在時に local 優先、不在で npx fallback

#### A2: SessionStart 並列化
```bash
# settings.json で複数 SessionStart hooks を1コマンドにまとめ:
"command": "bash .claude/hooks/session-start-orchestrator.sh"
# orchestrator が個別 hook を & で並列起動 + wait
```

#### A3: observe.sh sampling (検討、当面は全件継続)
- 現状 PreToolUse + PostToolUse 両方で全 tool 記録
- Read / Grep / Glob は high-frequency なので sampling 候補だが、L4 学習の生データ source なので慎重
- 本 Wave では「実装はせず、計測のみ」して judgement 材料を集める

### Sub-epic C1 詳細 (大型 hook 分割)

#### improvement-proposal.sh (491 LOC) 分割案
```
.claude/hooks/improvement-proposal.sh           # 50 LOC orchestrator
.claude/hooks/lib/proposal/aggregate.sh         # observations.jsonl 集計
.claude/hooks/lib/proposal/pattern-detect.sh    # 誤動作パターン検出
.claude/hooks/lib/proposal/cache.sh             # TTL cache (task-22 W5 で別途)
.claude/hooks/lib/proposal/format.sh            # stderr 出力 format
```

#### delegation-guard.sh (400 LOC) 分割案
```
.claude/hooks/delegation-guard.sh               # 80 LOC orchestrator
.claude/hooks/lib/delegation/path-protect.sh    # protected_paths 判定
.claude/hooks/lib/delegation/bash-whitelist.sh  # bash-whitelist 照合
.claude/hooks/lib/delegation/git-deny.sh        # 破壊的 git deny
.claude/hooks/lib/delegation/branch-protect.sh  # protected branch push deny
```

#### confidence-gate.sh (356 LOC) 分割案
```
.claude/hooks/confidence-gate.sh                # 80 LOC orchestrator
.claude/hooks/lib/confidence/extract.sh         # transcript から confidence 抽出
.claude/hooks/lib/confidence/judge.sh           # 閾値判定
.claude/hooks/lib/confidence/bypass.sh          # bypass marker
```

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| C1 大型 hook 分割で behavior 変化 (regression) | H | H | behavior-preserving 必須、Wave 完了後 既存 smoke で regression 0 確認 |
| A2 SessionStart 並列化で hook 間競合 | M | M | 各 hook が独立 state dir 書き込みで競合なし、出力順は orchestrator が wait + 順次 echo |
| B3 `/harness-audit --compare` で他 repo の secret 漏洩 | L | M | diff は file 名のみ、内容は対象外 |

---

## 5. 移行計画

- [ ] Sub-epic A (performance) を先行着手、A1 → A2 → A3
- [ ] Sub-epic B (doc) を並行、B1 → B2 → B3
- [ ] Sub-epic C (refactor) を最後 (依存度高、blast radius 大)
- [ ] 各 Wave 完了で個別 commit + 既存 smoke regression 0 確認

---

## 6. 完了条件 (DoD)

- [ ] check-md-mermaid.sh が local install で動作、README に案内あり
- [ ] SessionStart 時間が 28s → 5-8s に短縮 (実測)
- [ ] CLAUDE.md placeholder 0 件 (grep `<例:` で 0 matches)
- [ ] README install セクションが install.sh ベース
- [ ] `/harness-audit --compare` で 4 リポ diff レポート出力
- [ ] 大型 3 hooks が lib 分割完了、各 < 100 LOC
- [ ] `/harness-audit` に未着手 draft 90 日超 list + drift check 表示
- [ ] observe.sh project_id 未解決時 fallback が `unknown-cwd-<hash>`

---

## 7. 工数見積

合計 4.3 session (Sub-epic A 1.0 + B 1.2 + C 2.1)。

---

## 8. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-23 | user | (待ち) |

---

## 9. 関連

- 既存設計: `docs/draft/hook-reliability-uplift.md` (task-22、本 task と独立並行可)
- 既存設計: `docs/draft/system-reminder-attention-fix.md` (task-21、attention 改善)
- 関連タスク: 本 draft = task-25 想定
