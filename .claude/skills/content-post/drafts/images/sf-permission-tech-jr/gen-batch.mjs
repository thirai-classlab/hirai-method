#!/usr/bin/env node
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';

const GEN = '/Users/t.hirai/.claude/skills/ai-image-gen/scripts/gen.mjs';
const OUT = '/Users/t.hirai/work/雑務/.claude/skills/content-post/drafts/images/sf-permission-tech-jr/test-ai/';
mkdirSync(OUT, { recursive: true });

const STYLE = `STYLE: hand-drawn whiteboard sketchnote, soft pastel colors, Yusei-Magic-like handwritten Japanese font, sticker-style box-shadow on each card, doodle aesthetic, generous padding around all edges (no content touching canvas edges), no strikethrough on regular text.`;

const PROMPTS = [
  {
    name: 'body-overview',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, very generous padding.

TITLE (handwritten with ✦, large): 「✦ Salesforce アクセス制御 — 2 軸モデル」
SUBTITLE: 「機能アクセス × データアクセス が単一ユーザで交差する」
Yellow tilted round badge top-right: 「2軸で / 制御！」

CENTER: A LARGE plus-sign / cross intersection diagram with:
- A vertical column (FUNCTION axis, blue tinted) running top-to-bottom on left side, labeled「機能アクセス軸（何ができるか）」at top
- A horizontal row (DATA axis, pink tinted) running left-to-right at center, labeled「データアクセス軸（何が見えるか）」on right
- The two axes cross at the center forming a plus/cross
- At the cross-center, a yellow circular sticker badge with avatar: 👤「単一ユーザ」

LEFT VERTICAL AXIS (top to bottom, 3 stacked blue/sky-blue cards):
- 🎫「ライセンス」 (most-upper, ribbon: 上位制約)
- 👤「プロファイル」
- ➕「権限セット」

BOTTOM HORIZONTAL AXIS (left to right, 3 pink cards in a row):
- 🌐「組織の共有設定」
- 🌳「ロール階層」
- 🤝「共有ルール」

TWO PASTEL CALLOUT BOXES at corners:
- top-right (cream dashed): 「機能軸: ボタン・タブの可否」
- bottom-right (cream dashed): 「データ軸: レコードが一覧に出るか」

BOTTOM CAPTION (yellow dashed box):
「両方OK でないと操作できない（AND条件）」

${STYLE}
LANGUAGE: All Japanese. NO English subtitles like "License", "Profile", "Permission Set", "Role Hierarchy", "Sharing Rule".`,
  },

  {
    name: 'mermaid-01',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ アクセス制御の 2 軸モデル」
SUBTITLE: 「機能軸とデータ軸を分けて整理する」
Yellow tilted badge top-right: 「2軸 / 切分け！」

VERTICAL FLOWCHART showing 2 parallel branches, each with 3 stacked cards, joining at the bottom:

LEFT BRANCH (sky-blue cards, blue arrows):
- Header pill: 「機能アクセス軸」 (blue)
- Box 1: 🎫「ライセンス」 — 使える機能の枠
- ↓
- Box 2: 👤「プロファイル」 — ベースの最小権限
- ↓
- Box 3: ➕「権限セット」 — 追加付与

RIGHT BRANCH (pink cards, pink arrows):
- Header pill: 「データアクセス軸」 (pink)
- Box 1: 🌐「組織の共有設定」 — 最初に効くデフォルト
- ↓
- Box 2: 🌳「ロール階層」 — 上位への自動拡張
- ↓
- Box 3: 🤝「共有ルール」 — 例外条件で広げる

BOTH BRANCHES merge at bottom into a single mint card: 🎯「アクセス可否（AND判定）」

${STYLE}
LANGUAGE: All Japanese. NO English subtitles.`,
  },

  {
    name: 'body-row-col',
    prompt: `A hand-drawn whiteboard sketchnote depicting a SPREADSHEET grid showing row vs column access. 3:2 landscape, generous padding.

TITLE (handwritten with ✦, large): 「✦ 行の権限 vs 列の権限」
SUBTITLE: 「組織の共有設定/共有ルール=行を絞る、項目レベルセキュリティ/プロファイル=列を絞る」
Pink tilted badge top-right: 「行と列で / 削る！」

CENTER: A LARGE table mockup (5 rows × 6 columns) drawn as a sketched spreadsheet with:
- Column headers: 商談ID / 商談名 / 担当者 / 金額 / フェーズ / 完了予定日
- 5 sample rows with data: OPP-001 / OPP-002 / OPP-003 / OPP-004 / OPP-005

LEFT-SIDE BIG ARROW pointing down with sticker label「行を絞る ↕」(pink) — labeled「組織の共有設定 / ロール階層 / 共有ルール」

TOP BIG ARROW pointing right with sticker label「列を絞る ↔」(blue) — labeled「項目レベルセキュリティ / プロファイル」

VISUAL EFFECT inside table:
- Some rows are grayed out (rows 2, 3, 4 dimmed) to show row-level filtering
- Some columns are masked with 🚫 (担当者 column, 完了予定日 column) to show column-level filtering

BOTTOM CAPTION (cream dashed box):
「行の権限 = WHERE句  /  列の権限 = SELECT句」

${STYLE}
LANGUAGE: All Japanese for headers, labels, captions. Sample data may keep ID format like "OPP-001". NO English subtitles like "Row Permission" / "Column Permission" / "FLS" / "Profile".`,
  },

  {
    name: 'ascii-01',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, very generous padding.

TITLE (handwritten with ✦, very large): 「✦ 制御軸 × 削る方向」
SUBTITLE: 「列方向と行方向の交点でデータセルの可視性が決まる」
Yellow tilted card top-right: 「列×行で / セル可視！」

CENTER LARGE 2D MATRIX layout:
- X axis (top): 「← 列方向（項目）→」 in blue
- Y axis (left): 「↑ 行方向（レコード）↓」 in pink
- A grid of 6-7 cells in matrix style, each cell labeled with its control type

ROWS (top to bottom):
1. 🎫 ライセンス — 削る方向: オブジェクト丸ごと
2. 👤 プロファイル / 権限セット (オブジェクト権限) — 削る方向: オブジェクト丸ごと
3. 📋 項目レベルセキュリティ — 削る方向: 列 ↔ (列が空白化)
4. 🌐 組織の共有設定 — 削る方向: 行 ↕ (行が消える)
5. 🌳 ロール階層 — 削る方向: 行 ↕ (上位は行が増える)
6. 🤝 共有ルール — 削る方向: 行 ↕ (条件付き拡張)
7. 👥 手動共有 / チーム — 削る方向: 行 ↕ (個別拡張)

Each row laid out as a 3-column horizontal stripe: [icon + japanese name] | [削る方向 with up/down arrow ↕ or left/right arrow ↔] | [効果の短い説明]

Color coding:
- License/Profile rows: blue stripe
- Field-level row: orange stripe
- Org-Wide / Role / Sharing Rule / Team rows: pink stripes (data axis)

BOTTOM big yellow dashed callout:
「💡 列を削るのは「列の権限」、行を削るのは「行の権限」 — 両方AND で評価される」

${STYLE}
LANGUAGE: All Japanese. English allowed: "AND" only. NO English row/column labels.`,
  },

  {
    name: 'mermaid-02',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ ユーザに紐づく要素」
SUBTITLE: 「ログイン主体に必須・任意の属性が集まる」
Mint tilted badge top-right: 「ユーザは / ハブ！」

CENTER LAYOUT: A central yellow circular avatar 👤「ユーザ」 with 4 lines radiating outward to 4 satellite cards:

UP: (sky-blue) 🎫「ライセンス」 — ✅必須 — 使える機能の大枠
RIGHT: (sky-blue) 👤「プロファイル」 — ✅必須（必ず1つ） — 最小権限セット
DOWN: (sky-blue) ➕「権限セット」 — 任意（複数可） — 追加権限
LEFT: (pink) 🌳「ロール」 — 任意（あれば1つ） — データ可視範囲の階層

BELOW the diagram (cream dashed callout):
「⚠️ ロールは必須ではない。ロールがないユーザは「ロール階層による可視拡張」を受けない」

${STYLE}
LANGUAGE: All Japanese.`,
  },

  {
    name: 'mermaid-03',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ ライセンス — 使える機能の大枠」
SUBTITLE: 「契約形態でプロファイル以上の上位制約となる」
Yellow tilted badge top-right: 「上位 / 制約！」

VERTICAL FLOWCHART, top to bottom:

TOP CARD (large, yellow): 📜「契約 / ライセンス契約」 — 会社全体の選択

↓ arrow

3 SIDE-BY-SIDE LICENSE TYPE CARDS (sky-blue, mint, purple):
- 🏢「Salesforce ライセンス」 — フル機能 — CRM全機能
- 🛠「Platform ライセンス」 — カスタムアプリ向け — 標準CRM不可
- 🤝「Community / Partner」 — 外部ユーザ向け — 限定機能

↓ arrow

NEXT CARD (pink): 「📑 ライセンスがプロファイルの選択肢を絞る」

↓ arrow

BOTTOM CARD (mint): 👤「ユーザに割当（プロファイルと一緒に）」

LEFT-SIDE STICKY NOTE (cream):
「💡 設定 › 会社の情報 › ユーザライセンス で残数確認」

${STYLE}
LANGUAGE: Mostly Japanese. English allowed: "Salesforce" / "Platform" / "Community" / "Partner" license names.`,
  },

  {
    name: 'mermaid-04',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ プロファイルで制御するもの」
SUBTITLE: 「ユーザのベースライン権限を定義」
Sky-blue tilted badge top-right: 「土台を / 定義！」

MIND-MAP layout: a central round node 「👤 プロファイル」 (sky-blue) with 6 branches radiating outward to 6 leaves:

1. (mint) 📦「オブジェクト権限」 — 作成/参照/編集/削除
2. (mint) 📋「項目レベルセキュリティ」 — 列の参照/編集
3. (orange) 🗂「レコードタイプ割当」 — どのレコードタイプを使えるか
4. (purple) 📑「ページレイアウト割当」 — どの画面が表示されるか
5. (yellow) 📱「アプリケーション割当」 — どのアプリにアクセス可
6. (pink) ⚙「システム権限」 — 全データ参照/編集 等の特殊権限

Each leaf is a hand-drawn sticker card with icon + label + tiny description.

BOTTOM CALLOUT (cream dashed):
「💡 必須・1ユーザ1つ — 役職の土台に使う」

${STYLE}
LANGUAGE: All Japanese. NO English subtitles.`,
  },

  {
    name: 'mermaid-05',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ プロファイル vs 権限セット — 役割分担」
SUBTITLE: 「土台と +α で組み合わせ爆発を防ぐ」
Pink tilted badge top-right: 「薄く広く / +α！」

CENTER 2-COLUMN COMPARISON CARDS:

LEFT CARD (sky-blue, blue ribbon「プロファイル」):
- 👤 big handwritten「プロファイル」(blue)
- subtitle「土台 / ベースライン」
- 4 rows:
  - ✅ 必ず1つ
  - 📍 役職別ベース権限
  - ⚠ 変更頻度: 低い
  - 🚫 増やしすぎ NG（爆発する）
- bottom: 「例: 営業 / カスタマーサポート / 経理」

RIGHT CARD (pastel pink, pink ribbon「権限セット」):
- ➕ big handwritten「権限セット」(pink)
- subtitle「+α / 追加権限」
- 4 rows:
  - 🔢 0〜複数
  - 📌 機能・画面単位
  - ⚡ 変更頻度: 高い
  - ✅ 細かく追加 OK
- bottom: 「例: +レポート作成 / +Einstein」

BOTTOM CALLOUT (yellow dashed):
「💡 「役職で変わる」 → プロファイル / 「機能の有無で変わる」 → 権限セット」

${STYLE}
LANGUAGE: All Japanese. English allowed: "Einstein" only.`,
  },

  {
    name: 'mermaid-06',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ なぜ権限セットが必要か」
SUBTITLE: 「プロファイル爆発問題を権限セットで解決」
Pink tilted badge top-right: 「爆発を / 防ぐ！」

TOP HALF — BAD example (red bordered area, cross icon):
LEFT-LABEL「❌ プロファイルだけで運用」
4 expanding profile cards stacked: 「営業」/「営業+レポート」/「営業+レポート+Einstein」/「営業+...」 with red explosion icon 💥 and label「組合せ爆発！」

DIVIDER ARROW: ⬇ 「だから...」

BOTTOM HALF — GOOD example (green bordered area, check icon):
LEFT-LABEL「✅ プロファイル + 権限セット」
1 base sky-blue card「営業（共通プロファイル）」 with 3 small green chips on the right: 「+レポート」「+Einstein」「+データエクスポート」 attached as add-ons.

BOTTOM CALLOUT (cream dashed):
「💡 ベースのプロファイル1つ + 必要な権限セットを後付け」

${STYLE}
LANGUAGE: All Japanese. English: "Einstein" only.`,
  },

  {
    name: 'mermaid-07',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ 権限セットグループ」
SUBTITLE: 「複数の権限セットを束ねた1つのパック」
Mint tilted badge top-right: 「パックで / 管理！」

LEFT SIDE: 3 individual permission set chips (mint, orange, purple) stacked vertically:
- 🟢「権限セット A: レポート作成」
- 🟠「権限セット B: データエクスポート」
- 🟣「権限セット C: Einstein 機能」

CENTER ARROW: ➡「束ねる」

RIGHT SIDE: 1 large yellow group card (with handwritten title):
🎁「権限セットグループ：営業上級者パック」
  - レポート作成
  - データエクスポート
  - Einstein 機能
  + small label「抑制権限で部分的に打消し可」

BOTTOM ARROW: ⬇

BOTTOM USER CARD (sky-blue): 👤「ユーザに1発で割当」

BOTTOM CALLOUT (cream dashed):
「💡 役職や業務ロール別に「パック」化するのが推奨」

${STYLE}
LANGUAGE: All Japanese. English: "Einstein" only.`,
  },

  {
    name: 'mermaid-08',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ 組織の共有設定 設計の原則」
SUBTITLE: 「狭く始めて、必要最小限だけ広げる」
Pink tilted badge top-right: 「狭く / スタート！」

VERTICAL FLOW with 4 steps (top → bottom):

STEP 1 (red border, cross icon): 🚫「最初に最狭で決める」 — 「非公開（Private）スタート」
↓
STEP 2 (sky-blue): 🌳「ロール階層で必要最小限広げる」 — 上位ロールへ自動可視
↓
STEP 3 (orange): 🤝「共有ルールで条件付き拡張」 — 部門横断など例外
↓
STEP 4 (mint): 👥「手動共有 / チーム」 — 個別レコード単位

LEFT-SIDE WARNING TAG (red dashed): 「⚠️ 逆順は危険：広く開けてから狭めることは原則できない」

BOTTOM CALLOUT (cream dashed):
「💡 鉄則: 下から積み上げ — 狭く始め、足りない分だけ追加で広げる」

${STYLE}
LANGUAGE: All Japanese. English: "(Private)" parenthetical only.`,
  },

  {
    name: 'mermaid-09',
    prompt: `A hand-drawn whiteboard sketchnote depicting an organizational role hierarchy tree. 3:2 landscape, generous padding.

TITLE: 「✦ ロール階層 — 組織ツリーそのもの」
SUBTITLE: 「上位ロールが下位の所有レコードを自動で見る」
Mint tilted badge top-right: 「上が下を / 見る！」

CENTER: A hand-drawn ORG TREE with 4 levels:

LEVEL 1 (top, yellow large card): 👑「CEO」
  ↓ branches to
LEVEL 2 (purple cards): 「営業本部長」 / 「カスタマーサポート本部長」
  ↓ each branches
LEVEL 3 (sky-blue cards under 営業本部長): 「営業マネージャ（関東）」 / 「営業マネージャ（関西）」
  ↓ each branches
LEVEL 4 (mint small chips): 「営業A」「営業B」 (under 関東) / 「営業C」「営業D」 (under 関西)

ARROW LEGEND on right side (cream dashed):
「↑ 上位ロールは下位の所有レコードを自動で見る」
「↓ 下位ロールは上位のレコードは見えない」

BOTTOM CALLOUT (cream dashed):
「💡 兄弟関係（同レベル）は互いに見えない」

${STYLE}
LANGUAGE: All Japanese.`,
  },

  {
    name: 'mermaid-10',
    prompt: `A hand-drawn whiteboard sketchnote depicting a sequence diagram of role-based visibility. 3:2 landscape, generous padding.

TITLE: 「✦ ロール階層での可視性の動き方」
SUBTITLE: 「営業A が作成したレコードが上位へ自動的に伝播」
Sky-blue tilted badge top-right: 「上方向に / 伝播！」

CENTER: A sequence-diagram-style horizontal layout with 4 vertical actor lanes (left to right):
- 👤 営業A
- 👨‍💼 営業マネージャ(関東)
- 🎩 営業本部長
- 👑 CEO

ON ACTOR-A LANE: a yellow card「📝 レコード作成」at top.

DASHED HORIZONTAL ARROWS (with auto-visible labels) extending rightward to each higher actor:
- → 営業マネージャ: 「自動可視 ✓」
- → 営業本部長: 「自動可視 ✓」
- → CEO: 「自動可視 ✓」

BELOW: a SECOND set of arrows showing「兄弟は見えない」:
- 営業B (sibling of 営業A): a 🚫 mark with label「営業B には見えない」

BOTTOM CALLOUT (cream dashed):
「💡 上方向: 自動拡散 / 横方向: 拡散しない」

${STYLE}
LANGUAGE: All Japanese.`,
  },

  {
    name: 'mermaid-11',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ アクセス判定フロー（最重要）」
SUBTITLE: 「ユーザがレコード X にアクセス時の 7 ステップ評価」
Pink tilted badge top-right: 「7ステップ / 評価！」

VERTICAL DECISION FLOW with 7 numbered cards stacked top-to-bottom, each with a numbered circle, emoji, big label, and YES/NO arrow:

1 (yellow) 🎫「ライセンスで使える機能か？」 → NO=拒否 / YES=次へ
2 (sky-blue) 👤「プロファイル/権限セットでオブジェクト権限あるか？」 → NO=拒否 / YES=次へ
3 (orange) 📋「項目レベルセキュリティで項目参照可？」 → NO=列マスク / YES=次へ
4 (pink) 🌐「組織の共有設定で見える範囲か？」 → NO=拒否 / YES=次へ
5 (mint) 🌳「ロール階層で拡張されるか？」 → YES=可視 / NO=次へ
6 (purple) 🤝「共有ルールにヒットするか？」 → YES=可視 / NO=次へ
7 (cream) 👥「手動共有/チーム/Apex 共有あるか？」 → YES=可視 / NO=最終拒否

ARROWS connecting each step downward in a tree (each YES branches to次へ down, NO branches to 拒否 to right side).

BOTTOM CALLOUT (yellow dashed):
「💡 順序: ライセンス → 機能権限 → 項目 → 組織の共有設定 → ロール → 共有ルール → 手動」

${STYLE}
LANGUAGE: All Japanese.`,
  },

  {
    name: 'mermaid-12',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE: 「✦ ClassLab. 風サンプル — 全体設計」
SUBTITLE: 「ライフライン事業（電気・ガス契約代行）の Salesforce 設計例」
Mint tilted badge top-right: 「役職別 / 設計！」

CENTER LAYOUT: 6 user-role cards arranged in 2 rows of 3, each card showing:
- icon + role name
- ライセンス / プロファイル / ロール / 権限セット の組合せ

Row 1:
- (sky-blue) 📞 コールセンター オペレーター: SF/オペレータプロファイル/関東CSロール/+ケース対応
- (sky-blue darker) 👨‍💼 コールセンター スーパーバイザー: SF/SVプロファイル/CSマネージャロール/+全ケース参照
- (mint) 💼 営業: SF/営業プロファイル/担当営業ロール/+商談作成

Row 2:
- (mint darker) 🎩 営業マネージャ: SF/営業マネージャプロファイル/上位ロール/+ダッシュボード
- (yellow) 💰 経理: SF/経理プロファイル/経理ロール/+全データ参照
- (purple) 🤝 パートナー（外部）: Partner Community/外部プロファイル/(なし)/(なし)

BOTTOM CALLOUT (cream dashed):
「💡 6役職 × 4軸（ライセンス/プロファイル/ロール/権限セット）で組み立てる」

${STYLE}
LANGUAGE: All Japanese. English allowed: "ClassLab.", "Salesforce", "Partner Community" technical names.`,
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
