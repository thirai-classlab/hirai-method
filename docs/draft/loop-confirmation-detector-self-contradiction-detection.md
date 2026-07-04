<!--
approval_required: true
approved_at:
approved_by:
retroactive: false
-->

# loop-confirmation-detector: 同 turn 内「Enqueue 宣言 ↔ turn 区切り」自己矛盾の検出強化

**ステータス:** 🔲 **draft（2026-06-07 起案、user 承認待ち）**
**起点:** next-actions #50（2026-05-27 user 別 repo recall_poc ログ指摘）。AI が「遵守事項 9 通り次 task 自動 enque」と宣言直後、同 turn 内で「次 turn 計画: ... turn 区切り」と矛盾発言する事象。
**前提:**
- task-41 で loop-confirmation-detector.sh に確認質問 keyword 検出を実装済（Stop hook）
- 本 session でも「turn 区切り報告で停止」の抑止が繰り返し課題（CLAUDE.md HIGH 教訓）

**関連 fixture / rule:**
- `.claude/hooks/loop-confirmation-detector.sh`（Stop hook、DEFAULT_PATTERNS）
- `.claude/rules/modes.md` 遵守事項 9
- `.claude/tests/loop-confirmation-detector-smoke.sh`

---

## 1. 真因サマリ / 課題サマリ

Loop モードで AI が同一 turn 内に「次 task を自動 enque する（遵守事項 9）」と宣言しつつ、直後に「本 turn は区切り、次 turn で着手」と**自己矛盾**する発言をする。user から見ると「Enqueue と書いた直後に turn 区切りで上書きされている」ように見え、自律進行が実際には止まる。

`loop-confirmation-detector.sh` は **Stop hook = post-execution** のため、検出できるのは AI の最終 message 出力後で、次 turn への warning 注入のみ。**同 turn 内で「Enqueue 宣言」と「turn 区切り宣言」が併記される自己矛盾**は、現状 keyword が「確認質問」中心で、この併記パターンを CRITICAL として捉えていない。

**真因:** (1) 検出 keyword に「Enqueue 宣言 ↔ turn 区切り宣言の同 turn 内併記」パターンが不在 (2) 規範（遵守事項 9）に「両者の同 turn 併記禁止」が未明文化 (3) 内蔵 TaskList に open task 残存中の turn 区切りが violation 判定と連動していない。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | hook 検出強化: Enqueue 宣言 keyword（「自動 enque」「次 task 着手」「遵守事項 9」）と turn 区切り keyword（「次 turn 計画」「本 turn は区切り」「turn 区切り」）の**同 message 内併記**を検出 → CRITICAL warning + 「即時着手せよ」phrasing 注入 | 0.8 | 併記の自己矛盾を機械検出 | Stop hook のため是正は次 turn（同 turn block は構造的に不可） |
| **B** | modes.md 遵守事項 9 に「Enqueue 宣言と turn 区切り宣言の同 turn 併記禁止」を明文化（honor system） | 0.3 | 低コスト、規範明確化 | 機械強制なし |
| **C ハイブリッド** | A + B + TaskList 連動（内蔵 TaskList に open/pending task 残存中の turn 区切り宣言を violation 加重） | 1.2 | 機械検出 + 規範 + TaskList 状態連動で多層 | Stop hook 制約（次 turn 是正）は残る |

→ **案 C ハイブリッド** を推奨。理由: 同 turn 内 block は Stop hook = post-execution の構造的制約で不可能なため、「次 turn での強力な是正注入 + 規範明文化 + TaskList 状態連動」の多層で実効性を高めるのが現実解。UserPromptSubmit 側での事前抑止（次 turn 冒頭で「前 turn の矛盾を是正し即着手」を強制）と組み合わせる。

---

## 3. 採用案の詳細設計（案 C、要 user 承認で確定）

### Step 計画（暫定）

| Step | 作業概要 | 工数 |
|:---:|:---|---:|
| 1 | loop-confirmation-detector.sh に「Enqueue 宣言 ∧ turn 区切り宣言」同 message 併記検出ロジック追加（両 keyword group の AND マッチで CRITICAL 注入、通常の確認質問検出とは別 severity） | 0.5h |
| 2 | modes.md 遵守事項 9 に「Enqueue 宣言と turn 区切り 同 turn 内併記禁止」明文化 | 0.2h |
| 3 | TaskList 連動: 内蔵 TaskList に open/pending 残存中の turn 区切り宣言を violation 加重（実装可能性を Step 1 で調査、Stop hook が TaskList 状態を読めるか要確認） | 0.3h |
| 4 | (テスト設計レビュー) reviewer 動的選定 | 0.3h |
| 5 | (テスト合格) smoke: 併記あり→CRITICAL / Enqueue のみ→通過 / turn 区切りのみ→既存動作 / feature OFF→no-op | 0.4h |
| 6 | (リファクタリング) 3 観点 or skip | 0.2h |

合計: 約 1.9h（案確定後に採用 6 条準拠で詳細化）

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| Stop hook のため同 turn block 不可（次 turn 是正のみ） | H | M | 案 C で「次 turn 冒頭強制是正 + 規範 + TaskList 連動」多層化、構造的限界は受容 |
| keyword AND マッチの false positive（正当な「今 turn 完遂 + 次 task は別」報告を誤検出） | M | M | 併記の意味的区別を keyword 精緻化 + smoke で境界検証、bypass env 用意 |
| TaskList 状態を Stop hook が読めない | M | L | Step 1 で実現性調査、不可なら案 A+B のみ（TaskList 連動 drop） |

---

## 5-9. 移行 / DoD / 工数 / レビュー / 承認

- **DoD**: 併記検出で CRITICAL 注入（smoke）/ modes.md 明文化 / false positive 境界 smoke / feature OFF no-op / 既存 loop-confirmation smoke regression 0。
- **承認履歴**: 2026-06-07 起案、user 承認待ち（案 C 確定 + TaskList 連動の実現性判断含む）。

---

## 10. 関連

- next-actions #50（本 draft の起点、user 別 repo recall_poc ログ指摘）
- task-41（loop-confirmation-detector 拡張、本 hook の前身）
- modes.md 遵守事項 9（Loop モード = list.md 全 task 連続自律実行）+ 5 層強制機構
- CLAUDE.md HIGH 教訓（subagent 待ち中の turn 区切り停止の再発防止）
