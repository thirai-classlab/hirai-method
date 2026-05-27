<!--
approved_at: 2026-05-27
retroactive: false
approved_by: user
-->

# UI 実装後のビジュアル検証必須化 (採用 6 条 4 統合、honor-system)

> **発生源**: user 直接指示 2026-05-27「UI実装後はビジュアルの検証を必須化してください。ブラウザ検証は vercel/agentブラウザースキルを利用する。スクリーンショットなども利用する。e2eとは別」
> **設計方針確定**: AskUserQuestion 2026-05-27 — 強制方法「honor-system のみ」+ codify 先「採用 6 条 4 に統合」
> **関連 memory**: [[ui-visual-verification-mandate]]

## §1 真因 / 動機

現状の harness 規範 (`.claude/rules/task-management.md` タスク構造規範 採用 6 条 4「テスト合格 Step」) は **「UI 含む Task は E2E 必須」** 止まりで、**ビジュアル (見た目) の検証が明示的に必須化されていない**。

E2E と visual は別の品質軸:

| 軸 | 検証内容 | 例 |
|---|---|---|
| **E2E (機能フロー)** | クリック → 遷移 → データ反映 等が動作するか | フォーム送信で API が呼ばれ DB に保存される |
| **ビジュアル (見た目)** | レイアウト / 配色 / タイポグラフィ / 余白 / 状態 (hover/focus/active) / レスポンシブ が意図通りか | ボタンが崩れていない / 余白が設計通り / dark mode が破綻していない |

E2E が PASS しても見た目が崩れているケースは捕捉できない。型チェック / unit test も機能正しさであって見た目正しさではない。user 指示でこの gap を埋める。

## §2 採用案

**採用 6 条 4「テスト合格 Step」に「UI (browser/web) 含む Task は E2E に加えてビジュアル検証必須」を統合** (honor-system、hook なし)。

AskUserQuestion で user 確定:
- **強制方法**: honor-system のみ (規範文書に明記、AI が遵守。機械強制 hook は本 task では作らない)
- **codify 先**: 採用 6 条 4 に統合 (新規 dedicated section や workflow stage 追加はしない、既存構造に自然統合)

## §3 採用案 (実装仕様)

### 3.1 task-management.md 採用 6 条 4「テスト合格 Step」への追記

現行:
```
- **テスト合格 Step**:
  - レビューで合意したテスト設計に従いテスト実行
  - UI 含む Task → E2E 必須 (Playwright / 同等)
  - UI 変更なし Task → unit / integration test PASS で OK
```

改定後 (ビジュアル検証を E2E と並列で必須化):
```
- **テスト合格 Step**:
  - レビューで合意したテスト設計に従いテスト実行
  - UI (browser/web) 含む Task → E2E 必須 (Playwright / 同等) かつ ビジュアル検証必須 (下記)
  - UI 変更なし Task → unit / integration test PASS で OK
  - ビジュアル検証 (browser/web UI、E2E とは別レイヤ):
    - agent-browser skill (vercel/agent browser) で実際にブラウザ描画 → screenshot 取得 → 目視確認
    - 主要 breakpoint (320/768/1024/1440 等) / 主要状態 (hover/focus/active/error 等) / 両 theme (あれば) を撮影
    - レイアウト / 配色 / タイポグラフィ / 余白 / レスポンシブ が設計意図通りか確認 (可能なら before/after 比較)
    - E2E (機能フロー動作) とは別の品質軸。両方 PASS で初めて UI Task 完了、E2E のみ / 型チェックのみでは完了宣言しない
    - terminal TUI は対象外 (CLI TUI は TTY 必須の手動操作確認が別途、本規範は browser/web UI 向け)
```

### 3.2 UI 変更検出基準の流用

ビジュアル検証のトリガー (= 何が「UI (browser/web) を含む Task」か) は既存の `.claude/rules/task-management.md` §「UI 変更検出基準」を流用:
- 拡張子: `*.tsx` / `*.jsx` / `*.vue` / `*.svelte` / `*.html` / `*.css` / `*.scss` / `*.sass` / `*.less`
- path: `src/components/**` / `src/pages/**` / `src/app/**` / `apps/**/components/**` / `components/**`

この基準に該当する file 変更を含む Task は「ビジュアル検証必須」。手動 skip format (CSS 変数 rename のみ等 view 影響なし) も既存 §UI 変更検出基準の skip format を流用。

### 3.3 検証ツール (agent-browser skill)

- `agent-browser` skill (Browser automation CLI for AI agents) を default 利用。ページ navigate / 操作 / screenshot 取得。
- dev server 起動 → 対象画面を開く → 主要 breakpoint / 状態で screenshot → 目視確認の流れ。
- 補助: `webapp-testing` / `ui-demo` (Playwright 録画) skill も活用可。
- 非対話環境 (CI 等) では Playwright screenshot で代替可 (既存 `~/.claude/rules/web/testing.md` Visual Regression と整合)。

### 3.4 honor-system 運用 (hook なし)

- 機械強制 hook は本 task では作らない (user 決定)。AI が規範通り「UI Task の完了前にビジュアル検証 + screenshot」を実施する。
- 将来、遵守逃しが N=2 以上観測されたら hook 化 (UI file 変更検出時に screenshot artifact 不在で warn) を別 task で検討 (副産物 entry 経由)。

## §4 スコープ

- **対象**: browser / web UI (画面に描画される HTML/CSS/コンポーネント)
- **対象外**: terminal TUI (task-48 のような CLI TUI)、非 UI 変更、API/backend のみの変更
- **honor-system**: 規範文書追記のみ、hook / smoke / code 変更なし

## §5 リスク

| リスク | 緩和 |
|---|---|
| honor-system のため AI 遵守依存 (忘却リスク) | 規範文書 (採用 6 条 4) + memory `feedback_ui_visual_verification_mandate` の 2 層で想起。遵守逃し N≥2 で hook 化検討 |
| 非対話 / CI 環境で agent-browser 不可 | Playwright screenshot で代替 (既存 web/testing.md と整合) |
| terminal TUI との混同 | 採用 6 条 4 追記で「terminal TUI は対象外」明記 |

## §6 DoD

- [ ] `.claude/rules/task-management.md` 採用 6 条 4「テスト合格 Step」に「UI (browser/web) 含む Task は E2E + ビジュアル検証必須」追記
- [ ] ビジュアル検証手順 (agent-browser + screenshot + breakpoint/状態/theme + E2E との別レイヤ明記 + terminal TUI 除外) を同 Step に記載
- [ ] UI 変更検出基準の流用を明記
- [ ] honor-system (hook なし) を明記
- [ ] 既存 §「UI 変更検出基準」/ workflow.md Stage 13 (scenario-test) との整合性確認 (矛盾しないこと)
- [ ] 規範変更のため draft-flow-guard 通過 (本 draft approved_at 記入後に task-management.md 編集可)

## §7 影響範囲

| 範囲 | 詳細 |
|---|---|
| 修正 file | `.claude/rules/task-management.md` (採用 6 条 4「テスト合格 Step」追記) |
| 新規 file | 本 draft のみ (hook / smoke / code 新設なし) |
| 規模 | 小 (採用 6 条 5 の「1 Task + 1 Step」小タスク該当、doc 追記のみ) |
| 機械強制 | なし (honor-system、user 決定) |

## §8 承認履歴

**✅ 承認済 (2026-05-27、user「承認します。」)** — 確認 3 点すべて OK:
1. 採用 6 条 4「テスト合格 Step」への統合内容 (§3.1 の改定後テキスト) — 承認
2. honor-system のみ (hook なし) — 承認
3. terminal TUI 対象外 / browser-web UI のみのスコープ — 承認

`approved_at: 2026-05-27` 記入済 → task-management.md 編集 (draft-flow-guard 通過) + `/new-task 49` で台帳化。

## §9 関連

- `.claude/rules/task-management.md` 採用 6 条 4 (テスト設計レビュー → テスト合格 → リファクタリング) + §UI 変更検出基準
- `.claude/rules/workflow.md` Stage 13 (scenario-test、E2E、UI 含む Task は E2E 必須)
- `~/.claude/rules/web/testing.md` (Visual Regression priority、screenshot breakpoints 320/768/1024/1440)
- skill: `agent-browser` / `webapp-testing` / `ui-demo`
- memory: [[ui-visual-verification-mandate]]
