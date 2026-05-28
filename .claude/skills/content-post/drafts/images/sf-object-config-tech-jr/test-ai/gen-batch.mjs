#!/usr/bin/env node
import { spawn } from 'node:child_process';
import path from 'node:path';

const GEN = '/Users/t.hirai/.claude/skills/ai-image-gen/scripts/gen.mjs';
const OUT = '/Users/t.hirai/work/雑務/.claude/skills/content-post/drafts/images/sf-object-config-tech-jr/test-ai/';

const COMMON_STYLE = `STYLE: hand-drawn whiteboard sketchnote, soft pastel colors, Yusei-Magic-like handwritten Japanese font, sticker-style box-shadow on each card, doodle aesthetic, generous padding around all edges (no content touching canvas edges), no strikethrough on regular text.`;

const PROMPTS = [
  {
    name: 'body-relation',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (top-center, dark rounded badge with cream text, big handwritten): 「✦ 参照関係 vs 主従関係 ✦」

TWO LARGE PANELS side-by-side, each with rounded corners and sticker-shadow:

LEFT PANEL (pastel sky-blue background, blue border):
- Round tilted blue badge top-right of panel: 「ゆるい / つながり」
- Big title: 「① 参照関係」 (blue)
- Subtitle: 「親と子は独立した別オブジェクト」
- Center stage: red-bordered pill 「親（取引先）削除」, then dashed yellow connector label 「┊ 点線で接続 ┊」, then green-bordered pill 「子（商談）は残る ✓」
- Note line below stage in red: 「❌ 親を削除しても 子レコードはそのまま残る」
- 4 property lines at bottom (dashed top divider):
  ▶ 共有設定 ＝ 独立 (green) / ▶ 積み上げ集計 ＝ 不可 (red) / ▶ 任意 / 必須 ＝ 選べる (green) / ▶ 親変更で子も付け替え可 (green)

RIGHT PANEL (pastel pink background, pink border):
- Round tilted pink badge top-right: 「つよい / つながり」
- Big title: 「② 主従関係」 (pink)
- Subtitle: 「子は親に完全に従属する」
- Center stage: a yellow dashed-border nested box containing: pill「親（取引先）削除」, red text「↓ カスケード ↓」, pill「子（商談明細）も削除」
- Note line below in red: 「💥 親が消えると子も カスケード削除される」
- 4 property lines at bottom:
  ▶ 共有設定 ＝ 親に従属 (amber) / ▶ 積み上げ集計 ＝ 使える (green) / ▶ 親フィールド ＝ 必須 (amber) / ▶ 1 オブジェクトに最大 2 親まで (amber)

${COMMON_STYLE}
LANGUAGE: All text Japanese. NO English words anywhere.`,
  },

  {
    name: 'mermaid-01',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (yellow rounded badge): 「✦ Salesforce Admin 認定試験 ✦」
SUBTITLE: 「主要アーキテクチャを把握して、管理者としての基盤を固める」
Pink tilted round sticker top-right: 「下から / 積み上げ！」

4 horizontal pill cards stacked vertically with small ↑ arrows between, BOTTOM to TOP:

L1 BOTTOM (pastel cream/yellow, ochre border): 🗄️ big label「スキーマ」 + 3 white chip pills: 📦オブジェクト | 🏷️項目（フィールド） | 🔗リレーション
L2 (pastel sky-blue): 🖼️ big label「UI」 + chips: 📄ページレイアウト | 🗂️レコードタイプ | 📋リストビュー
L3 (pastel pink): 🛡️ big label「ルール」 + chips: ✅入力規則 | 📌必須項目 | 🔁重複ルール
L4 TOP (pastel mint): ⚙️ big label「自動化」 + chips: 🌊フロー | 📋承認プロセス | 🧩Apexトリガ

BOTTOM CAPTION (yellow dashed tag): 「下から積み上げて、強固な Salesforce 組織を構築 ✦」

${COMMON_STYLE}
LANGUAGE: All Japanese characters. ONLY English allowed: "Salesforce", "Admin", "Apex", "UI". Do NOT include "Schema", "Automation", "Rule", "User Interface" anywhere.`,
  },

  {
    name: 'mermaid-02',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (blue rounded badge): 「✦ レコードトリガーフロー 実行順序 ✦」
SUBTITLE: 「レコード保存時の処理は 7 ステップで進む」
Mint tilted round sticker top-right: 「7 / ステップ」

7 step cards in a single horizontal row, each with a numbered circle (1-7) on top, an emoji, a Japanese label, brief Japanese description:

1 (yellow): 👤 「ユーザ保存」 — ユーザがレコードを保存
2 (sky-blue): 🌊 「保存前フロー」 — 同レコード上の項目を編集
3 (pink): ✅ 「入力規則」 — 条件違反なら保存停止
4 (mint): 💾 「DBコミット」 — レコードが確定する
5 (sky-blue): 🌊 「保存後フロー」 — 関連レコードを更新
6 (purple): ⚙️ 「ワークフロー」 — 既存ルールが追従発火
7 (purple): 📊 「積み上げ集計」 — 親オブジェクトを再集計

BELOW: a yellow-cream dashed-bordered legend box with 5 colored dots and Japanese labels:
🟡 ユーザアクション (人の操作)
🔵 フロー (フローによる処理)
🌸 検証 (データ品質チェック)
🟢 保存 (DBへ書込み)
🟣 自動化 (レコード保存後)

${COMMON_STYLE}
LANGUAGE: All Japanese. NO English subtitles like "User Save", "Before-Save Flow", "Validation Rule", "DB Commit", "After-Save Flow", "Workflow Rule", "Roll-up". Only "DB" abbreviation is allowed.`,
  },

  {
    name: 'mermaid-03',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (handwritten with ✦ star): 「✦ 主従関係（Master-Detail）」
SUBTITLE: 「親レコードに従属する子オブジェクトの関係。削除・共有・集計が連動する」
Yellow tilted round badge top-right: 「親と子は / 運命共同体！」

CENTER LAYOUT — TWO object cards side by side connected by a tilted yellow connector label「主従関係 ⟷」:

LEFT CARD (pastel sky-blue, blue border, sticker shadow):
- Header: 🏢 「Property__c」 + role tag「親 (Master)」
- 5 row pills: Name | テキスト / Address__c | 住所 / Property_Type__c | 選択リスト / Purchase_Date__c | 日付 / [HIGHLIGHTED YELLOW] Total_Amount__c | 積み上げ集計

RIGHT CARD (pastel pink, pink border):
- Header: 📄 「Contract__c」 + role tag「子 (Detail)」
- 5 row pills: Name | テキスト / [HIGHLIGHTED YELLOW] Property__c | 主従 / Start_Date__c | 日付 / Amount__c | 通貨 / Stage__c | 選択リスト

BOTTOM: 3 small bubble cards in a row:
- (mint) 🗑️ 「親削除 → 子も削除」 — 物件レコードを消すと、紐づく契約もまとめて削除される
- (purple) 🤝 「共有は親に従属」 — 子の共有設定は持てず、親の共有ルールがそのまま適用
- (orange) 📊 「積み上げ集計が可能」 — 子の値を親に積み上げ集計で集計できる

${COMMON_STYLE}
LANGUAGE: All Japanese. English allowed: API names with __c suffix, "Master" and "Detail" as parenthetical role tags, "Master-Detail" inside title parens. NO other English subtitles like "Roll-up Summary".`,
  },

  {
    name: 'mermaid-04',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (handwritten with ✦): 「✦ 多対多リレーション（Junction Object）」
SUBTITLE: 「主従関係 2 本で M:N を実現するジャンクションオブジェクトの構成」
Purple tilted round badge top-right: 「主従×2で / M:N！」

CENTER: 3 object cards in a row connected by 2 yellow tilted connector labels「主従関係 →」「主従関係 ←」.

LEFT CARD (pastel sky-blue):
- Header: 🧑‍🎓 「Student__c」 + tag「受講生」
- Rows: Name | テキスト / Email__c | メール / Affiliation__c | 所属 / CreatedDate | 日付

CENTER JUNCTION CARD (pastel lavender/purple, slightly tilted ~-1deg):
- Header: 🔗 「Enrollment__c」 + tag「受講登録」
- Rows: Name | 受講ID / [HIGHLIGHTED] Student__c | 主・主従 / [HIGHLIGHTED] Course__c | 副・主従 / Status__c | 選択リスト

RIGHT CARD (pastel pink):
- Header: 📚 「Course__c」 + tag「コース」
- Rows: Name | テキスト / Category__c | 分類 / Description__c | 説明 / CreatedDate | 日付

BOTTOM CAPTION (cream dashed-bordered box, big text):
「主従関係 2 本でジャンクションを挟むと、 受講生（Student）⇔ コース（Course）の M:N（多対多） が成立する」

${COMMON_STYLE}
LANGUAGE: All Japanese. English allowed: API names ending __c, "Master-Detail" / "Junction Object" / "Student" / "Course" / "M:N" only as parenthetical glosses or API references in title/caption.`,
  },

  {
    name: 'mermaid-05',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (handwritten with ✦): 「✦ ページレイアウト × レコードタイプ × プロファイル」
SUBTITLE: 「3層の組み合わせで、ユーザごと・業務ごとに最適な画面を割り当てる」
Yellow tilted round badge top-right: 「3層を / 組合せ！」

3 column cards in a row separated by 2 arrows. Arrow labels (yellow tilted): 「割当 →」 between col1-2, 「適用 →」 between col2-3.

COL 1 (pastel sky-blue, blue border):
- 👤 big label「プロファイル」
- Description box (dashed): 「誰が使うか。権限とアクセス可能なレコードタイプを定義」
- 例： 2 chips: 🛡️システム管理者 / 💼セールスユーザ

COL 2 (pastel orange, orange border):
- 🗂️ big label「レコードタイプ」
- Description box: 「どの業務シナリオか。選択リスト値や適用するレイアウトを切替える」
- 例： 2 chips: 🆕新規契約 / 🔄更新契約

COL 3 (pastel mint, mint border):
- 📄 big label「ページレイアウト」
- Description box: 「何を見せるか。項目・関連リスト・ボタン配置を決める」
- 例： 3 chips: 📋レイアウト-標準 / 🔁レイアウト-更新 / ⚙️レイアウト-管理者

BOTTOM CAPTION (cream dashed box):
「プロファイル がレコードタイプへのアクセスを制御し、 レコードタイプ ごとに ページレイアウト を割り当てる」

${COMMON_STYLE}
LANGUAGE: All Japanese. NO English subtitles like "Profile", "Record Type", "Page Layout", "System Admin", "Sales User".`,
  },

  {
    name: 'mermaid-06',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (handwritten with ✦): 「✦ 重複管理（Duplicate Management）の構成」
SUBTITLE: 「重複ルールが「一致ルール」と「アクション」の 2 つを束ねるマスター設定」
Pink tilted round badge top-right: 「2部品で / 制御！」

TOP CENTER (large yellow tilted card, ~-1deg rotation):
- 📑 big title「重複ルール」
- Small label below: 「Duplicate Rule」
- Description box (dashed border, white): 「重複を検出し、一致ルールとアクションをまとめて適用するマスター設定」

Below the top card, two splitting arrows ↙ ↘ leading to two child cards.

BOTTOM LEFT CARD (pastel sky-blue, blue border):
- 🔍 big label「一致ルール」 + small「（照合条件）」
- Tag: 「何を重複と見なすか」
- Mini caption: 「例：法人取引先を Name + 郵便番号で照合」
- 2 field rows: 「Match Field 1: Name」 / 「Match Field 2: BillingPostalCode」

BOTTOM RIGHT CARD (pastel orange, orange border):
- ⚙️ big label「アクション」 + small「（一致時の挙動）」
- Tag: 「どう動くか」
- Mini caption: 「例：重複が見つかったときの動作を選択」
- 2 action rows:
  - 「🚫 拒否（ブロック）」 — desc「保存させない」
  - 「⚠️ 警告とともに許可」 — desc「確認の上で保存可」

${COMMON_STYLE}
LANGUAGE: All Japanese. English allowed: "Duplicate Rule" small label, "Match Field 1/2", "Name", "BillingPostalCode" (API references). NO other English subtitles.`,
  },

  {
    name: 'mermaid-07',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, very generous padding (lots of breathing room because content is dense).

TITLE (handwritten with ✦): 「✦ フロー起動方法とトリガ実行順序」
SUBTITLE: 「4種のフローを場面で使い分け、レコード保存時の実行順序を意識する」
Mint tilted round badge top-right: 「順番が / 命！」

SECTION A — small yellow rotated tag「起動方法」 followed by 4 flow cards in a row:
- (sky-blue) 🖥️ 「画面フロー」 — ボタンや Lightning ページから手動で起動
- (pink) 📝 「レコードトリガーフロー」 — 作成・更新・削除に連動して自動実行
- (purple) ⏰ 「スケジュールフロー」 — 指定時刻に定期バッチとして起動
- (mint) 🔁 「自動起動フロー」 — 他のフローや Apex から呼び出して実行

SECTION B — small yellow rotated tag「実行順序」 followed by 7 step cards in a row, each with numbered circle on top, emoji, label, short desc:
1 (yellow) 💾 保存開始 — レコード送信
2 (sky-blue) ⚡ 保存前フロー — 項目補正
3 (orange) ✅ 入力規則 — 条件チェック
4 (purple) 🗄️ DBコミット — DBに確定
5 (sky-blue) 🌊 保存後フロー — 関連レコード操作
6 (pink) 📋 ワークフロー — 項目自動更新
7 (mint) 📊 積み上げ集計 — 親レコード反映

Bottom row of arrows: → → → → → → →

Footnote (cream dashed box centered): 「※ 実行順序は Salesforce 公式の実行順に基づく概念図」

${COMMON_STYLE}
LANGUAGE: All Japanese. English allowed: "Salesforce", "Apex", "Lightning", "DB" (technical terms commonly used in Japanese SF docs). NO English subtitles like "Screen Flow", "Record-Triggered Flow", "Scheduled Flow", "Autolaunched Flow", "Validation".`,
  },

  {
    name: 'ascii-01',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (handwritten with ✦, very large): 「✦ データ保存時の実行順」
SUBTITLE: 「どの制御がいつ効くかで「拒否」と「補正」を使い分ける」
Yellow tilted card top-right: 「上から順に / 処理される！」

LAYOUT: Two-column, LEFT ~70% width / RIGHT ~30%.

LEFT COLUMN — 5 step cards stacked vertically with small ↓ arrows between, each card has a dashed-circle number badge on left, "STEP N" small subtitle, emoji + big Japanese label, Japanese description:

① (gray, START) 📨 「データ保存リクエスト」 — UI / API / Apex から発火
② (yellow, STEP 1) 📋 「必須(レイアウト)」 — UI入力時の必須項目チェック
③ (purple, STEP 2) 🛠️ 「保存前フロー」 — 値の書き換え(補正)が可能
④ (pink, STEP 3) 🛡️ 「入力規則」 — 条件違反は「拒否」のみ(補正不可)
⑤ (orange, STEP 4) 🔗 「主従関係(FK制約)」 — 親なしのレコードは拒否

RIGHT COLUMN:
- Section title「★ 役割の整理」 (blue with dashed underline)
- 4 cream sticky notes vertically: (1) 必須チェック / (2) 値補正 / (3) 検証 / (4) 後処理(コミット後)
- Below: a green "STEP 5 / 後処理" card (mint background, dark mint border):
  Big label「保存後フロー / 積み上げ集計」
  Bullet list with ✦: 他レコードの更新 / 集計の再計算 / DBコミット後の連鎖処理
- Bottom corner cream dashed note: 「※ 拒否系: 入力規則 / 主従関係 ※ 補正系: 保存前フロー」

${COMMON_STYLE}
LANGUAGE: All Japanese. English allowed: "STEP", "API", "UI", "DB", "FK", "Apex" (technical abbreviations naturalized in Japanese SF docs). NO full English words like "Validation", "Save", "Commit", "Save Request".`,
  },

  {
    name: 'ascii-02',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (handwritten with ✦, very large): 「✦ 項目の連動関係」
SUBTITLE: 「制御項目の値で従属項目の選択肢を絞り込む」
Pink tilted card top-right: 「親で / 絞り込む！」

3 COLUMN HEADERS above a table (with dashed underlines):
- LEFT (blue, big handwritten): 「★ 国 (制御)」
- CENTER (small gray): 「→ 絞込 →」
- RIGHT (orange, big handwritten): 「★ 都道府県/州 (従属)」

3 ROWS of pairing — each row: (blue control card) | (large arrow ➜ + pink "絞込" tag below) | (yellow candidate box):

Row 1:
- Control card: small label「国」, big value「🇯🇵 日本」
- Yellow box label「候補」, white pills: 「東京」「神奈川」「大阪」「福岡」「…」

Row 2:
- Control card: 「国」 / 「🇺🇸 アメリカ」
- Pills: 「カリフォルニア」「テキサス」「ニューヨーク」「…」

Row 3:
- Control card: 「国」 / 「🇬🇧 イギリス」
- Pills: 「イングランド」「スコットランド」「ウェールズ」「…」

BOTTOM (cream dashed box):
「📍 設定パス: 設定 › オブジェクトマネージャ › 対象オブジェクト › 項目とリレーション › 項目の連動関係 › 新規」

${COMMON_STYLE}
LANGUAGE: All Japanese — this is critical. NO English country names "Japan/USA/UK" — use 日本/アメリカ/イギリス. NO English region names like "California/Texas/NY/England/Scotland/Wales" — use Japanese transliterations カリフォルニア/テキサス/ニューヨーク/イングランド/スコットランド/ウェールズ. NO English column headers like "Country/State/Region" — use 国/都道府県/州.`,
  },

  {
    name: 'ascii-03',
    prompt: `A hand-drawn whiteboard sketchnote depicting a Salesforce record-detail screen mockup. 3:2 landscape, generous padding.

TITLE (handwritten with ✦, large): 「✦ ページレイアウト — 入力フォームの構成」
SUBTITLE: 「ハイライト / パス / 詳細 / 関連 / アクション の 5 ブロックで構成」
Yellow tilted card top-right: 「5ブロック / で組み立て！」

CENTER: a large rounded "browser screen" mockup (very light gray-blue background, dark thick border, big drop shadow). At top-left of the screen, a black tab labeled「🖥 Salesforce レコード詳細画面」.

INSIDE THE SCREEN — 5 stacked horizontal blocks vertically:

① (gray block): 「① ハイライトパネル (コンパクトレイアウト)」
② (orange/yellow block): 「② パス — フェーズ進捗 (Lightning)」 — below, a row of 5 chevron-style stage pills: 検討 (done dark-yellow) | 提案 (done) | 交渉/レビュー (active orange) | 受注 (empty) | 失注 (empty)
③ (sky-blue block): 「③ 詳細セクション」 — below, 3 small purple sub-cards in a row:
  - セクション1: 基本情報 — fields: Name / Owner / Date
  - セクション2: 金額情報 — fields: Amount / Currency
  - セクション3: 詳細 — Description (ロングテキストエリア)
④ (mint green block): 「④ 関連リスト — 子オブジェクト一覧」 — below, 4 chip pills: Contracts(主従子) / Tasks / Files / Notes
⑤ (cream block): 「⑤ ボタン / アクション」 — below, 4 buttons: 新規 (blue) / 編集 / 削除 (red) / カスタム

${COMMON_STYLE}
LANGUAGE: All section titles Japanese. Sample form field names (Name/Owner/Date/Amount/Currency/Description) and related-list object names (Contracts/Tasks/Files/Notes) may stay English as API references. Stage pill names MUST be Japanese: 検討/提案/交渉・レビュー/受注/失注. Button labels Japanese.`,
  },

  {
    name: 'ascii-04',
    prompt: `A hand-drawn whiteboard sketchnote, 3:2 landscape, generous padding.

TITLE (handwritten with ✦, large): 「✦ レコードタイプ 設計例 — 「新規契約」と「更新契約」を分岐」
SUBTITLE: 「同じオブジェクトでもレコードタイプを分けて レイアウト / フェーズ / 必須項目を切り替え」
Purple tilted card top-right: 「同じ箱でも / 用途で分岐！」

CENTER: 2 large comparison cards side by side, each with a colored ribbon at top.

LEFT CARD (sky-blue tinted background, blue border, big shadow):
- Top ribbon (blue, white text): 「レコードタイプ 1」
- Big heading (blue): 「新規契約 (New)」
- 3 rows separated by dashed lines:
  - 📄 ページレイアウト | white pill 「Sales New」
  - 🚀 フェーズ | 4 stage pills (blue outline): 検討 / 交渉・レビュー / 受注 / 失注
  - ⭐ 必須項目 | red required pill 「顧客紹介経路」

RIGHT CARD (purple tinted background, purple border, big shadow):
- Top ribbon (purple, white text): 「レコードタイプ 2」
- Big heading (purple): 「更新契約 (Renew)」
- 3 rows:
  - 📄 ページレイアウト | white pill 「Sales Renew」
  - 🚀 フェーズ | 3 stage pills (purple outline): レビュー保留中 / 受注 / 失注
  - ⭐ 必須項目 | red required pill 「前契約 ID」

BOTTOM HINT (yellow dashed box, centered):
「💡 レコードタイプは 増やしすぎない — 3〜5 個が目安、10 個超は保守困難」

${COMMON_STYLE}
LANGUAGE: All Japanese. English allowed: "New" / "Renew" parentheticals next to Japanese title, "Sales New" / "Sales Renew" page-layout API names. Stage pills MUST be Japanese: 検討/交渉・レビュー/受注/失注/レビュー保留中. NO English row labels like "Page Layout", "Phase", "Required Fields".`,
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
