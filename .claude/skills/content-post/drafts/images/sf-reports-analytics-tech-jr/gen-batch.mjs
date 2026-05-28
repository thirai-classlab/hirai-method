#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const GEN = '/Users/t.hirai/.claude/skills/ai-image-gen/scripts/gen.mjs';
const OUT = '/Users/t.hirai/work/雑務/.claude/skills/content-post/drafts/images/sf-reports-analytics-tech-jr/test-ai/';
mkdirSync(OUT, { recursive: true });

const STYLE = `STYLE: hand-drawn whiteboard sketchnote, soft pastel colors, Yusei-Magic-like handwritten Japanese font, sticker-style box-shadow on each card, doodle aesthetic, generous padding around all edges (no content touching canvas edges), no strikethrough on regular text.`;

const PROMPTS = [
  {
    name: 'body-pipeline',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, very generous padding.

TITLE (handwritten with ✦, large): 「✦ レポート分析の 4 層モデル」
SUBTITLE: 「データソース → 集計 → 可視化 → 配信 の縦パイプライン」
Yellow tilted badge top-right: 「4層で / 整理！」

CENTER: 4 stacked horizontal cards with downward arrows between, top to bottom:

LAYER 1 (sky-blue, big card): 🗄️「データソース層」
  - subtitle:「どのオブジェクトの組合せから取るか」
  - chips: 標準レポートタイプ / カスタムレポートタイプ

⬇

LAYER 2 (orange, big card): 📊「集計層」
  - subtitle:「どう集計して並べるか」
  - chips: レポート形式 / 検索条件 / グループ化 / 数式

⬇

LAYER 3 (mint, big card): 📈「可視化層」
  - subtitle:「どう見せるか」
  - chips: ダッシュボード / 動的ダッシュボード / コンポーネント

⬇

LAYER 4 (pink, big card): 📤「配信・共有層」
  - subtitle:「誰に届けるか」
  - chips: フォルダ / 配信登録 / アクセス権限

LEFT-SIDE NOTE (cream dashed): 「💡 「数値が出ない」時はレポートタイプを疑い、 「並びがおかしい」時は形式を疑う」

${STYLE}
LANGUAGE: All Japanese. English allowed only for "KPI" if used.`,
  },

  {
    name: 'mermaid-01',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ レポート分析の 4 層モデル」
SUBTITLE: 「層構造を掴むのが理解の最短ルート」
Mint tilted badge top-right: 「4層で / 切分け！」

VERTICAL FLOWCHART, 4 stacked cards with downward arrows:

1 (sky-blue): 🗄️「データソース層」 — レポートタイプの選択
↓
2 (orange): 📊「集計層」 — 形式・検索条件・数式
↓
3 (mint): 📈「可視化層」 — ダッシュボード化
↓
4 (pink): 📤「配信・共有層」 — フォルダ・配信登録

EACH layer has 2-3 small chips on the right showing concrete features.

BOTTOM CALLOUT (cream dashed):
「💡 層を切り分けて問題箇所を特定」

${STYLE}
LANGUAGE: All Japanese.`,
  },

  {
    name: 'mermaid-02',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ 検索条件 4種類」
SUBTITLE: 「絞込みの実装パターンを使い分ける」
Yellow tilted badge top-right: 「4種類 / 整理！」

CENTER: 4 horizontal cards in a 2x2 grid, each with icon + name + brief example:

(top-left, sky-blue) 🎯「標準検索条件」 — 例: 日付項目、所有者、ステータス
(top-right, orange) 📋「項目検索条件」 — 例: Amount > 500000、フェーズ = 受注
(bottom-left, mint) 🔗「クロス条件」 — 例: ケースを持たない取引先
(bottom-right, pink) 🧮「条件ロジック」 — 例: 1 AND (2 OR 3)

BOTTOM CALLOUT (cream dashed):
「💡 項目検索条件は既定で AND。OR を入れたい時だけ条件ロジック」

${STYLE}
LANGUAGE: All Japanese. English allowed: "AND" / "OR" logical operators, sample API field names like "Amount" in examples.`,
  },

  {
    name: 'ascii-01',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, very generous padding.

TITLE (handwritten with ✦, very large): 「✦ レポート評価パイプライン」
SUBTITLE: 「Salesforce DB から表示まで、4 段階で評価される」
Mint tilted badge top-right: 「4段階で / 評価！」

CENTER: 5 stacked horizontal cards (with downward arrows between), top to bottom, each showing the stage and what control kicks in:

STAGE 0 (gray): 🗄️「Salesforce DB（生データ）」 — 全レコードが格納

⬇

STAGE 1 (pink): 🌐「共有設定（組織の共有設定/ロール/共有ルール）」
  RDB類推: WHERE句（RLS）
  削る方向: 行 ↕

⬇

STAGE 2 (orange): 🔍「レポート検索条件」
  RDB類推: 追加WHERE句
  削る方向: 行 ↕

⬇

STAGE 3 (sky-blue): 📊「形式 / グループ化 / 集計」
  RDB類推: GROUP BY / 集計関数
  削る方向: 表示構造

⬇

STAGE 4 (mint): 📋「項目レベルセキュリティ + 表示」
  RDB類推: SELECT列の制限
  削る方向: 列 ↔

BOTTOM CALLOUT (yellow dashed, big text):
「💡 「レポートに出ない」時、 まず疑うのは検索条件ではなく 共有設定！」

${STYLE}
LANGUAGE: All Japanese. English allowed: "WHERE", "GROUP BY", "SELECT", "RLS", "RDB" technical SQL terms.`,
  },

  {
    name: 'mermaid-03',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ カスタムレポートタイプ」
SUBTITLE: 「Admin が定義する独自結合（試験頻出）」
Pink tilted badge top-right: 「自由に / 結合！」

VERTICAL FLOWCHART with 6 numbered steps:

1 (yellow): 「設定 › レポートタイプ › 新規カスタムレポートタイプ」
↓
2 (sky-blue): 🏛️「主オブジェクトを選択」 — 必須
↓
3 (mint): 🔗「関連オブジェクトを追加」 — 任意・最大3つで合計4階層
↓
4 (orange): 「を持つ / を持つかどうかにかかわらず」を選択
  - を持つ B = 内部結合
  - を持つかどうかにかかわらず B = 左外部結合
↓
5 (purple): 📋「レイアウトで表示項目を選別」
↓
6 (pink): ✅「リリース」 — 状態を「リリース済」に変更

BOTTOM CALLOUT (cream dashed):
「💡 リリース済でないとレポート作成画面に出ない」

${STYLE}
LANGUAGE: All Japanese.`,
  },

  {
    name: 'mermaid-04',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ レポートタイプの選び方フロー」
SUBTITLE: 「標準 / カスタム / Apex の使い分け」
Sky-blue tilted badge top-right: 「3択を / 決める！」

DECISION FLOWCHART (top to bottom):

START circle (yellow): 🚀「レポート作成」
↓
Q1 diamond (sky-blue): 「💭 関連オブジェクトを持たないものも取りたい？」
  - YES → カスタムレポートタイプ (mint card)
  - NO → 次へ
↓
Q2 diamond (sky-blue): 「💭 標準レポートタイプに該当する組合せがある？」
  - YES → 標準レポートタイプ (orange card)
  - NO → 次へ
↓
Q3 diamond (sky-blue): 「💭 動的・複雑なロジックが必要？」
  - YES → Apex で SOQL カスタム実装 (purple card)
  - NO → カスタムレポートタイプ (mint card)

3 END NODES (right side, color-coded):
- 🟧「標準レポートタイプ」(orange)
- 🟢「カスタムレポートタイプ」(mint)
- 🟣「Apex / SOQL カスタム」(purple)

BOTTOM CALLOUT (cream dashed):
「💡 標準で足りれば標準を。作りすぎ注意」

${STYLE}
LANGUAGE: All Japanese. English allowed: "Apex", "SOQL".`,
  },

  {
    name: 'body-formats',
    prompt: `A hand-drawn whiteboard sketchnote comparing 4 report formats. 3:2 landscape, very generous padding.

TITLE (handwritten with ✦, large): 「✦ 4種のレポート形式の比較」
SUBTITLE: 「表形式 / サマリー / マトリックス / 結合 を使い分ける」
Yellow tilted badge top-right: 「4形式 / 比較！」

CENTER: 2x2 GRID of mini-table mockups showing how each format actually looks:

TOP-LEFT (sky-blue card) 「表形式 (Tabular)」:
  Mini flat 4-column table preview, no grouping
  Subtitle: フラットな一覧 / グラフ❌

TOP-RIGHT (orange card) 「サマリー (Summary)」:
  Mini table with grouped rows + subtotals shown
  Subtitle: 1〜3階層グループ / グラフ✅

BOTTOM-LEFT (mint card) 「マトリックス (Matrix)」:
  Mini 2-axis pivot grid (rows × columns intersection)
  Subtitle: 行×列クロス集計 / グラフ✅

BOTTOM-RIGHT (pink card) 「結合 (Joined)」:
  Mini multi-block layout with 2-3 small tables side by side
  Subtitle: 複数ブロック横並び / 異オブジェクト

BOTTOM CALLOUT (cream dashed):
「💡 まず表形式で書いて、 グラフ化したいならサマリーへ」

${STYLE}
LANGUAGE: All Japanese for explanations. English allowed: "(Tabular)" / "(Summary)" / "(Matrix)" / "(Joined)" parenthetical glosses next to Japanese names.`,
  },

  {
    name: 'ascii-02',
    prompt: `A hand-drawn whiteboard sketchnote depicting a SUMMARY REPORT example. 3:2 landscape, very generous padding.

TITLE (handwritten with ✦, large): 「✦ サマリーレポート例」
SUBTITLE: 「フェーズ別にレコードをグループ化し、各小計と総計を表示」
Sky-blue tilted badge top-right: 「グループ化 / 集計！」

CENTER: A LARGE hand-drawn report mockup with header row and 2 grouped sections:

HEADER ROW (gray): 商談ID | 商談名 | 担当者 | 金額 | 確度

GROUP 1 (orange tinted, expandable arrow): ▼「フェーズ: 交渉/レビュー」
  - OPP-001 | ABC不動産 | 営業A | 500万 | 80%
  - OPP-003 | 山田不動産 | 営業C | 800万 | 90%
  - 小計: 1,300万 (highlighted yellow strip)

GROUP 2 (orange tinted, expandable arrow): ▼「フェーズ: 提案/価格見積」
  - OPP-002 | XYZ管理 | 営業B | 300万 | 60%
  - 小計: 300万 (highlighted yellow)

GRAND TOTAL ROW (yellow strong): 「総計: 1,600万」

LEFT-SIDE NOTE (cream dashed): 「最大3階層までネスト可能（例: 担当者 → 月 → 製品）」

${STYLE}
LANGUAGE: All Japanese. Sample IDs like "OPP-001" and amounts may stay format. NO English subtitles like "Summary".`,
  },

  {
    name: 'ascii-03',
    prompt: `A hand-drawn whiteboard sketchnote depicting a MATRIX REPORT example. 3:2 landscape, very generous padding.

TITLE (handwritten with ✦, large): 「✦ マトリックスレポート例」
SUBTITLE: 「行軸 フェーズ × 列軸 期間 の クロス集計表」
Mint tilted badge top-right: 「2軸クロス / 集計！」

CENTER: A LARGE hand-drawn matrix table mockup:

TOP HEADER ROW (sky-blue): 「フェーズ \\ 期間」 | 2026Q1 | 2026Q2 | 2026Q3 | 総計

ROWS (orange row labels):
- 検討 | - | - | 150万 | 150万
- 提案/価格見積 | - | 300万 | - | 300万
- 交渉/レビュー | - | 500万 | - | 500万
- 受注 | - | - | - | -

BOTTOM TOTAL ROW (yellow strong): 合計 | - | 800万 | 150万 | 950万

ROW LABEL ANNOTATION (left side dashed arrow): ↑「行軸: 最大2階層」
COLUMN LABEL ANNOTATION (top side dashed arrow): ←「列軸: 最大2階層」

BOTTOM CALLOUT (cream dashed):
「💡 行・列ともに最大2階層までクロス集計」

${STYLE}
LANGUAGE: All Japanese.`,
  },

  {
    name: 'mermaid-05',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ ダッシュボード コンポーネントの種類」
SUBTITLE: 「KPI を可視化する各種パーツ」
Yellow tilted badge top-right: 「7種を / 使分け！」

CENTER: 7 small component-card icons arranged in 3 rows on a dashboard-grid background:

Row 1 (sky-blue cards):
- 📊「グラフ（棒/折線/円）」 — 推移・比較
- 🔢「メトリック」 — 単一KPI数値

Row 2 (orange cards):
- ⏲️「ゲージ」 — 達成率・しきい値
- 📋「テーブル」 — 上位N件

Row 3 (mint/pink cards):
- 🎯「数式メトリック」 — 派生KPI
- 📈「動的ダッシュボード対応」
- 🌍「Lightning コンポーネント」 — カスタム拡張

BOTTOM CALLOUT (cream dashed):
「💡 レポート無しでは作れない（ソースレポート必須）」

${STYLE}
LANGUAGE: All Japanese. English allowed: "KPI", "Lightning" only.`,
  },

  {
    name: 'mermaid-06',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ 動的ダッシュボード」
SUBTITLE: 「閲覧者本人を実行ユーザにし、各自の範囲だけ見える」
Pink tilted badge top-right: 「各自に / カスタム！」

CENTER: 2-column comparison cards:

LEFT CARD (sky-blue, blue ribbon「静的」):
- 🔒「静的ダッシュボード」
- 実行ユーザ: 固定（作成者or指定）
- 全員に同じデータ
- 例: KPI 共通

RIGHT CARD (mint, mint ribbon「動的」):
- 🔄「動的ダッシュボード」
- 実行ユーザ: 閲覧者本人
- 各自の権限で見える
- 例: 営業マネージャ用「配下の進捗」

CENTER ARROWS at top: a dashboard panel splits and routes:
- → 静的: 「全員に同じビュー」
- → 動的: 「各ユーザの権限でレンダ」

BOTTOM YELLOW CALLOUT (dashed):
「💡 ライセンス制限: Enterprise 5本 / Unlimited 10本まで」

${STYLE}
LANGUAGE: All Japanese. English allowed: "KPI", "Enterprise", "Unlimited" license names.`,
  },

  {
    name: 'mermaid-07',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ レポートのアクセス判定フロー」
SUBTITLE: 「6 ステップで評価される（試験頻出）」
Mint tilted badge top-right: 「6ステップ / 評価！」

VERTICAL DECISION FLOW with 6 numbered cards stacked top-to-bottom:

1 (yellow) 🎫「レポート実行権限あるか？」 → NO=拒否
↓
2 (sky-blue) 📁「フォルダにアクセス権あるか？」 → NO=拒否
↓
3 (orange) 🗄️「レポートタイプが使える？」 → NO=拒否
↓
4 (mint) 📦「オブジェクト権限あるか？」 → NO=拒否
↓
5 (pink) 🌐「共有設定で見える範囲か？」 → NO=行が消える
↓
6 (purple) 📋「項目レベルセキュリティで列参照可？」 → NO=列がマスク

BOTTOM CALLOUT (yellow dashed):
「💡 順序: レポート実行 → フォルダ → レポートタイプ → オブジェクト → 共有 → 項目」

${STYLE}
LANGUAGE: All Japanese.`,
  },
];

const runOne = ({ name, prompt }) => new Promise((resolve, reject) => {
  console.log(`▶ start: ${name}`);
  const proc = spawn('node', [
    GEN, 'generate', prompt,
    '--model', 'openai/gpt-image-2',
    '--size', '1536x1024',
    '--quality', 'high',
    '--n', '1',
    '--out', OUT,
    '--prefix', `${name}-trial`,
  ], { stdio: ['ignore', 'pipe', 'pipe'] });
  let out = '', err = '';
  proc.stdout.on('data', d => { out += d.toString(); });
  proc.stderr.on('data', d => { err += d.toString(); });
  proc.on('close', code => {
    if (code === 0) {
      console.log(`✓ done: ${name}`);
      resolve({ name, out });
    } else {
      console.error(`✗ fail: ${name} (exit ${code})\n${err}`);
      reject(new Error(`${name} exit ${code}: ${err}`));
    }
  });
});

const results = await Promise.allSettled(PROMPTS.map(runOne));
const ok = results.filter(r => r.status === 'fulfilled').length;
const fail = results.filter(r => r.status === 'rejected');
console.log(`\n=== summary: ${ok}/${PROMPTS.length} succeeded ===`);
if (fail.length) {
  console.log('FAILED:');
  for (const f of fail) console.log('  -', f.reason.message);
  process.exit(1);
}
