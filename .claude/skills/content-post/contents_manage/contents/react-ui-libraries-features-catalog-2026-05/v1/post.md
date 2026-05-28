
> React で使える UI コンポーネントライブラリを、**GitHub Star・機能性・用途・デザインテイスト** で横断比較するエンジニア向けレファレンス。デザインテイストが極力重複しないよう15個を選定し、各ライブラリに **公式サンプル画像（公式アセットへのリンク）と公式ショーケースURL** を併載する。

---

## 0. TL;DR

**一行サマリ**
2026年のReact UIライブラリは「**フルスタイル付き（MUI/Ant/Chakra/Mantine 等）**」「**コピペ所有（shadcn/ui）**」「**ヘッドレス（Radix/Base UI/React Aria）**」の3アーキに整理できる。機能網羅で選ぶなら MUI / Ant Design / PrimeReact、所有とカスタムなら shadcn/ui、堅牢なアクセシビリティ基盤なら React Aria / Base UI。

**旧知識との差分（LLM訓練データで陳腐化しやすい論点 — 本ドキュメントで上書き宣言）**

| 旧知識（〜2026/01訓練データ） | 2026-05 時点の実態（本ドキュメントで上書き） |
|---|---|
| MUI / Ant Design が Star 二強 | **shadcn/ui が ~104k★ で最多**。npm非依存の「コピペして所有する」モデルが新規プロジェクトの主流に |
| NextUI が人気の新興 | **HeroUI に改名・v3**（Tailwind v4 + React Aria 基盤へ刷新） |
| Radix UI がヘッドレスの王 | **WorkOS が買収し一部コンポーネントの更新が鈍化**。MUIチームの **Base UI（v1.0, 2025/12）** が後継的存在に台頭 |
| Chakra UI は Emotion 製 | **Chakra UI v3** は内部を Ark UI / Panda CSS 系に刷新 |
| MUI は Emotion ランタイム CSS-in-JS | **Pigment CSS でゼロランタイム CSS への移行**を進行中（SSR/RSC対応強化） |
| Ant Design は v5 | **Ant Design v6**（デザイントークン刷新・性能改善） |
| ヘッドレスは Radix / Headless UI の二択 | **Base UI / React Aria** が機能・a11y で重要選択肢に。multi-select/combobox は Base UI が先行 |
| データ可視化は別途チャートライブラリ | **Tremor** などダッシュボード特化UIが定着（KPIカード/チャート/テーブル一体） |

**最大差別化点（3アーキの対比）**
- **フルスタイル付き** = すぐ使える・機能網羅。デザインは各ライブラリの世界観に乗る（MUI=マテリアル、Ant=エンタープライズ 等）。
- **コピペ所有（shadcn/ui）** = コンポーネントのソースを自分のリポジトリに持ち、完全にカスタムできる。ロックインなし。
- **ヘッドレス（Radix/Base UI/React Aria）** = 挙動とa11yだけ提供しスタイルは自前。最も自由だが見た目はゼロから作る。

---

## 1. React UIライブラリとは何か — 理念と分類

### 1.1 3つのアーキテクチャ（選定の最重要軸）

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/react-ui-libraries-features-catalog-2026-05/e7c55cbc-mermaid-01.png" alt="1.1 3つのアーキテクチャ（選定の最重要軸） 概念図" width="1536" height="864">

### 1.2 デザインテイスト一覧（重複を避けた15選）

| ライブラリ | デザインテイスト |
|---|---|
| MUI | マテリアルデザイン（Google Material） |
| Ant Design | エンタープライズ整然（独自言語・データ密） |
| shadcn/ui | ミニマル中立（Tailwind・own-code） |
| Chakra UI | フレンドリー/モジュラー（角丸・親しみやすい） |
| Mantine | モダン多機能（フラット・実用的） |
| HeroUI | 洗練・モーション（モダンガラス調・rounded） |
| Fluent UI | Microsoft Fluent（深度・半透明アクリル） |
| Carbon | IBM工業的（シャープ・2xグリッド・高コントラスト） |
| PrimeReact | テーマ可変・万能（皮膚を着せ替え） |
| React Bootstrap | Bootstrap（クラシック・親しみ） |
| Blueprint | 高密度データ/デスクトップ（情報密度重視） |
| Tremor | ダッシュボード/データ可視化（チャート前提） |
| Radix UI | デザインなし（無スタイル・プリミティブ） |
| Base UI | デザインなし（最新ヘッドレス） |
| React Aria | デザインなし（hooks・a11y最重視） |

### 1.3 エンジニアにとっての意味（立場別）

| 立場 | 効く選択 |
|---|---|
| フロントエンド（プロダクト） | shadcn/ui（所有・カスタム）、Mantine/MUI（速度） |
| フロントエンド（デザインシステム構築） | Radix/Base UI/React Aria（基盤）+ 独自スタイル |
| 管理画面/業務アプリ | Ant Design / MUI X / PrimeReact / Blueprint |
| 社内ダッシュボード | Tremor / Mantine charts / MUI X Charts |
| アクセシビリティ契約要件 | React Aria（最厳格）/ Base UI |
| Microsoftエコシステム | Fluent UI |

---

## 2. 全体マップ（1枚絵）

### 2.1 ライブラリ俯瞰（アーキ × デザインテイスト）

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/react-ui-libraries-features-catalog-2026-05/b0717a81-mermaid-02.png" alt="2.1 ライブラリ俯瞰（アーキ × デザインテイスト） 概念図" width="1536" height="864">

### 2.2 「どれを選ぶか」の地図

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/react-ui-libraries-features-catalog-2026-05/fa75ddd0-mermaid-03.png" alt="2.2 「どれを選ぶか」の地図 概念図" width="1536" height="864">

---

## 3. 前提知識

### 3.1 スタイリング方式の違い（性能・SSRに直結）

| 方式 | 代表ライブラリ | 特徴 |
|---|---|---|
| CSS-in-JS（ランタイム） | MUI（Emotion）/ Chakra（旧）/ Fluent（Griffel） | テーマ柔軟だがランタイムコスト。RSCと相性に注意 |
| ゼロランタイムCSS | Mantine（CSS Modules）/ MUI（Pigment CSS移行中） | SSR/RSCで高速。ビルド時に解決 |
| Tailwind（ユーティリティ） | shadcn/ui / HeroUI / Tremor | クラス合成。Tailwind v4前提が増加 |
| 独自CSS/トークン | Ant Design / Carbon / Bootstrap | デザイントークンで一括テーマ |
| スタイルなし（headless） | Radix / Base UI / React Aria | 自前で何でも |

### 3.2 ライセンス・コスト前提

- 本15ライブラリは **すべて OSS（MIT等）で無料**。
- 一部は **有料の上位プロダクト**を持つ: MUI X Pro/Premium（DataGrid Pro等）、Ant Design Pro、HeroUI Pro、Tailwind Plus（旧Tailwind UI）。
- 「機能性」評価は無料枠の範囲を基準とし、有料枠は注記する。

### 3.3 本ドキュメントの評価表記凡例

- **対応 / 一部 / 非対応** — 機能の有無
- Star数は 2026-05 時点の **概算**（変動するため目安）

---

## 4. ライブラリカタログ

> 各ライブラリは **🎯概要・デザインテイスト（公式画像）/ 👨‍💻用途 / ⭐機能性&Star / 🖼️公式ショーケース / 🔥差別化 / 🏢ClassLab.活用 / ⚠️注意点** の7ブロック。画像は各公式の社会的プレビュー（OGP）アセットへのリンク。

### 4.A フルスタイル付き — マテリアル / モダン汎用

#### 4.A.1 MUI（Material UI）

**🎯 概要・デザインテイスト** — **マテリアルデザイン**（Google Material 準拠）

![MUI 公式プレビュー](https://mui.com/static/social-previews/home-preview.jpg)

GoogleのMaterial Designを実装した、最も広く使われるReactライブラリの一つ。100以上のコンポーネントと、別売の **MUI X**（DataGrid / Date Pickers / Charts / Tree View）で業務アプリを一気通貫で作れる。

**👨‍💻 用途**: 業務アプリ・管理画面・ダッシュボード、Material準拠のプロダクト、長期保守の堅実な選択。

**⭐ 機能性 & Star**: ~95k★ / 100+コンポーネント / 強力なテーマ(theming)・ダークモード / MUI X でデータグリッド等を拡張 / TypeScript完備。

**🖼️ 公式ショーケース**: 全コンポーネント → https://mui.com/material-ui/all-components/ ／ MUI X → https://mui.com/x/

**🔥 差別化**: 圧倒的なコンポーネント網羅と実績・ドキュメント。MUI X のDataGridは無料枠でも強力。

**🏢 ClassLab.活用**: 社内管理画面・業務ダッシュボードの標準UI。MUI X DataGridで契約データ一覧を高速構築。

**⚠️ 注意点**: Emotion(CSS-in-JS)のランタイムコスト→ **Pigment CSS** へ移行中。マテリアル色が濃く「MUIらしさ」が出やすい。MUI X の高度機能は有料。

---

#### 4.A.2 Ant Design

**🎯 概要・デザインテイスト** — **エンタープライズ整然**（独自デザイン言語・データ密）

![Ant Design 公式プレビュー](https://gw.alipayobjects.com/zos/rmsportal/rlpTLlbMzTNYuZGGCVYM.png)

エンタープライズ/管理画面に特化した独自デザイン言語。v6 でトークン刷新。データテーブル・フォーム・ツリーなどデータ重視コンポーネントが厚い。ProComponents で管理画面を高速構築。

**👨‍💻 用途**: データ重視のエンタープライズB2B、管理画面、（中国/アジア市場向けプロダクト）。

**⭐ 機能性 & Star**: ~94k★ / 60+コンポーネント / Table・Form・Tree が強力 / ProComponents・Pro Table / 国際化。

**🖼️ 公式ショーケース**: コンポーネント一覧 → https://ant.design/components/overview/ ／ Pro → https://pro.ant.design/

**🔥 差別化**: 無料枠で最も「データ業務」が完結する。管理画面テンプレ(ProComponents)が充実。

**🏢 ClassLab.活用**: 契約・顧客データの管理画面、フィルタ/ソート/編集が多い社内ツール。

**⚠️ 注意点**: デザインの「Antらしさ」が強くカスタムで個性を出しにくい。バンドルが大きめ。

---

#### 4.A.3 shadcn/ui

**🎯 概要・デザインテイスト** — **ミニマル中立**（Tailwind・コードを所有する）

![shadcn/ui 公式プレビュー](https://opengraph.githubassets.com/1/shadcn-ui/ui)

「npmパッケージではなくソースを配る」モデル。コンポーネントを自分のリポジトリにコピーして所有・改変する。Radix（→Base UI）+ Tailwind で、アクセシブルかつ完全カスタム可能。2026は新規の最有力。

**👨‍💻 用途**: greenfield、デザインを自社で所有・カスタムしたい、Next.js/RSC、デザインシステムの出発点。

**⭐ 機能性 & Star**: ~104k★（最多）/ npm非依存・コピペ所有 / registry・blocks・charts / Tailwind v4 / ロックインなし。

**🖼️ 公式ショーケース**: コンポーネント → https://ui.shadcn.com/docs/components ／ ブロック集 → https://ui.shadcn.com/blocks

**🔥 差別化**: 「所有」によりバージョン衝突・ブラックボックスがない。中立的な見た目でブランドに合わせやすい。

**🏢 ClassLab.活用**: 自社プロダクトのデザインシステム基盤。Weekly Newsサイトのような独自UIに最適。

**⚠️ 注意点**: 初期投資（コンポーネントを揃える手間）が必要。アップデートは手動マージ。Tailwind前提。

---

#### 4.A.4 Chakra UI

**🎯 概要・デザインテイスト** — **フレンドリー/モジュラー**（角丸・親しみやすい）

![Chakra UI 公式プレビュー](https://next.chakra-ui.com/og-image.png)

style props（`<Box p={4} bg="gray.100">`）で素早く組める、アクセシビリティ重視のライブラリ。v3 で内部を Ark UI / Panda CSS 系に刷新。

**👨‍💻 用途**: 素早いプロトタイプ/MVP、アクセシビリティ重視の新規、style props派。

**⭐ 機能性 & Star**: ~38k★ / アクセシブル / style props API / テーマトークン / v3で性能改善。

**🖼️ 公式ショーケース**: https://chakra-ui.com/docs/components/concepts/overview

**🔥 差別化**: 学習が容易で開発速度が速い。a11yがデフォルトで効く。

**🏢 ClassLab.活用**: 社内ツールの素早い立ち上げ、検証用UI。

**⚠️ 注意点**: v2→v3で破壊的変更あり（移行コスト）。超大規模ではトークン設計が必要。

---

#### 4.A.5 Mantine

**🎯 概要・デザインテイスト** — **モダン多機能**（フラット・実用的）

![Mantine 公式プレビュー](https://raw.githubusercontent.com/mantinedev/mantine/master/.demo/social-preview.png)

100以上のコンポーネント + 70以上のフックを備えた多機能トールキット。フォーム・日付・通知・スポットライト・リッチテキスト・チャートまで内蔵。**CSS Modules でゼロランタイム** → SSR/Next.jsで高速。2026の総合力で評価が高い。

**👨‍💻 用途**: 多機能を一括導入したい、SSR/Next.js、管理画面〜プロダクト全般。

**⭐ 機能性 & Star**: ~30k★ / 100+コンポーネント + 70+ hooks / `@mantine/form`・dates・notifications・charts・spotlight / ゼロランタイムCSS。

**🖼️ 公式ショーケース**: コンポーネント → https://mantine.dev/core/button/ ／ レイアウト集 → https://ui.mantine.dev/

**🔥 差別化**: 「これ一つで揃う」機能量とフックの充実。SSR性能が良い。

**🏢 ClassLab.活用**: フォーム/日付/通知が多い社内アプリを最短で。Next.jsプロダクトの標準候補。

**⚠️ 注意点**: 独自エコシステムが大きく、学習範囲は広い。デザインの個性は中庸。

---

#### 4.A.6 HeroUI（旧 NextUI）

**🎯 概要・デザインテイスト** — **洗練・モーション**（モダンガラス調・rounded）

![HeroUI 公式プレビュー](https://www.heroui.com/images/twitter-card.jpg)

NextUIから改名し v3 へ。**Tailwind v4 + React Aria**（a11y）+ モーションで、ビジュアルの美しさと機能性を両立。ランディングやSaaSの「見栄え」に強い。

**👨‍💻 用途**: ランディングページ、SaaS、ビジュアルポリッシュが重要なプロダクト。

**⭐ 機能性 & Star**: ~24k★ / Tailwind v4 / React Aria 基盤でa11y / アニメーション / ダークモード。

**🖼️ 公式ショーケース**: https://www.heroui.com/docs/components/button （コンポーネント一覧は左ナビ）

**🔥 差別化**: デフォルトで美しく、React Aria基盤で挙動も堅い。shadcn/uiより「すぐ綺麗」。

**🏢 ClassLab.活用**: 対外的なLP・キャンペーンページ、見栄え重視の機能。

**⚠️ 注意点**: Tailwind前提。v2→v3移行あり。世界観が「HeroUIらしさ」に寄る。

---

### 4.B フルスタイル付き — エンタープライズ系

#### 4.B.1 Fluent UI（Microsoft）

**🎯 概要・デザインテイスト** — **Microsoft Fluent**（深度・半透明アクリル）

![Fluent UI 公式プレビュー](https://react.fluentui.dev/fluentui-banner-meta.png)

Microsoft公式のFluent Design実装（v9）。Teams/Office風の世界観。Griffel(CSS-in-JS)。

**👨‍💻 用途**: Microsoftエコシステム/業務アプリ、Teams・Office連携、Windows風UI。

**⭐ 機能性 & Star**: ~19k★ / Fluent v9 / 企業向けコンポーネント / テーマ(ライト/ダーク/ハイコントラスト)。

**🖼️ 公式ショーケース**: https://react.fluentui.dev/

**🔥 差別化**: Microsoft製品と統一感。エンタープライズのアクセシビリティ・ハイコントラスト対応。

**🏢 ClassLab.活用**: Teams/Microsoft 365 連携の社内ツール。

**⚠️ 注意点**: 世界観がMicrosoft色。エコシステム外では過剰になりがち。

---

#### 4.B.2 Carbon Design System（IBM）

**🎯 概要・デザインテイスト** — **IBM工業的**（シャープ・2xグリッド・高コントラスト）

![Carbon 公式プレビュー](https://carbondesignsystem.com/ogimage.png)

IBMのデザインシステム。厳格なグリッドとデータ可視化、業務システム向けの硬質な見た目。

**👨‍💻 用途**: エンタープライズ/データ製品、IBM準拠、ガバナンスが厳しい業務UI。

**⭐ 機能性 & Star**: ~8k★ / `@carbon/react` / データ可視化(Carbon Charts) / 厳格なデザイントークン。

**🖼️ 公式ショーケース**: Storybook → https://react.carbondesignsystem.com/ ／ ガイド → https://carbondesignsystem.com/

**🔥 差別化**: 工業的で情報密度が高く、大規模エンタープライズのガバナンスに強い。

**🏢 ClassLab.活用**: 堅牢性・一貫性が要る基幹データUI（採用ハードルは高め）。

**⚠️ 注意点**: 見た目が硬く、コンシューマ向けには不向き。学習コスト高め。

---

#### 4.B.3 PrimeReact

**🎯 概要・デザインテイスト** — **テーマ可変・万能**（皮膚を着せ替えられる）

![PrimeReact 公式プレビュー](https://primefaces.org/static/social/primereact-preview.jpg)

90以上のコンポーネントを持つ最多級ライブラリ。DataTable / TreeTable / Chart / OrgChart / WYSIWYGエディタまで網羅。**テーマを着せ替え**られる（Material/Bootstrap風など）。Mercedes/VW/Intel採用。

**👨‍💻 用途**: 機能を網羅したい、テーマを切替えたい、エンタープライズ全般。

**⭐ 機能性 & Star**: ~7k★ / 90+コンポーネント（最多級）/ 高度なDataTable / 多数のプリセットテーマ / アクセシビリティ。

**🖼️ 公式ショーケース**: https://primereact.org/button/ （左ナビに全コンポーネント）

**🔥 差別化**: 単一ライブラリでの機能網羅が最強クラス。テーマ着せ替えで見た目を変えられる。

**🏢 ClassLab.活用**: 高機能な業務テーブル・帳票・編集UIをまとめて。

**⚠️ 注意点**: Star数の割に巨大。デザインの一貫性はテーマ依存。ドキュメントは機能寄り。

---

#### 4.B.4 React Bootstrap

**🎯 概要・デザインテイスト** — **Bootstrap**（クラシック・親しみ）

![React Bootstrap 公式プレビュー](https://opengraph.githubassets.com/2/react-bootstrap/react-bootstrap)

Bootstrap 5 をReactコンポーネント化（jQuery不要）。世界で最も馴染みのある見た目で、学習・移行が容易。

**👨‍💻 用途**: 既存Bootstrap資産の移行、慣れた見た目で素早く、社内ツール。

**⭐ 機能性 & Star**: ~22k★ / Bootstrap 5準拠 / グリッド・基本コンポーネント / 学習容易。

**🖼️ 公式ショーケース**: https://react-bootstrap.netlify.app/docs/components/

**🔥 差別化**: 圧倒的な知名度と学習資源。Bootstrapテーマ資産をそのまま活かせる。

**🏢 ClassLab.活用**: 既存Bootstrapサイトのreact化、短期の社内ツール。

**⚠️ 注意点**: 「Bootstrap感」が出る。最先端のデザイン/性能では新興に劣る。

---

#### 4.B.5 Blueprint（Palantir）

**🎯 概要・デザインテイスト** — **高密度データ/デスクトップ**（情報密度重視）

![Blueprint 公式プレビュー](https://blueprintjs.com/assets/fb-image.png)

Palantir製。**データ密なデスクトップ風Webアプリ**に特化。Table・Tree・DateRangePicker等、大量情報を扱うUIが得意（金融端末・開発ツール・分析基盤）。

**👨‍💻 用途**: データ密管理画面、デスクトップ風アプリ、分析/トレーディング/開発者ツール。

**⭐ 機能性 & Star**: ~21k★ / 高密度コンポーネント / 強力なTable・Tree・日付 / キーボード操作。

**🖼️ 公式ショーケース**: https://blueprintjs.com/docs/

**🔥 差別化**: 情報密度と操作効率に全振り。専門業務アプリで他の追随を許さない。

**🏢 ClassLab.活用**: 大量データを一画面で扱うオペレーション端末・分析ツール。

**⚠️ 注意点**: コンシューマ向けには情報過密。モバイルは不得手。

---

#### 4.B.6 Tremor

**🎯 概要・デザインテイスト** — **ダッシュボード/データ可視化**（チャート前提）

![Tremor 公式プレビュー](https://tremor.so/opengraph-image.png?f5bbf8e00be369e2)

ダッシュボードに特化したTailwindベースのライブラリ。チャート・KPIカード・テーブル・データ可視化要素が揃い、分析画面を素早く構築できる。

**👨‍💻 用途**: 分析ダッシュボード、KPI/メトリクス画面、社内BI。

**⭐ 機能性 & Star**: ~15k★ / チャート・KPIカード・テーブル / Tailwind / ダッシュボード前提の構成。

**🖼️ 公式ショーケース**: https://tremor.so/ （ブロック/コンポーネント）

**🔥 差別化**: 「ダッシュボードを作る」用途に最短距離。チャートと数値カードが一体。

**🏢 ClassLab.活用**: 契約数・売上・KPIの社内ダッシュボード、運用メトリクス可視化。

**⚠️ 注意点**: 汎用UIライブラリではない（ダッシュボード特化）。Tailwind前提。

---

### 4.C ヘッドレス — 挙動 + アクセシビリティのみ

#### 4.C.1 Radix UI

**🎯 概要・デザインテイスト** — **デザインなし**（無スタイル・プリミティブ）

![Radix UI 公式プレビュー](https://radix-ui.com/social/themes.png)

30以上の無スタイル・アクセシブルなプリミティブ（Dialog/Dropdown/Popover等）。キーボード操作・フォーカス管理・ARIA・RTLを内蔵。**shadcn/ui の基盤**として広く使われる。別途 Radix Themes（スタイル付き）もある。

**👨‍💻 用途**: 自前デザインの土台、デザインシステム構築、shadcn/uiの裏側。

**⭐ 機能性 & Star**: ~94k★ / 30+プリミティブ / a11y/keyboard/focus/RTL / Radix Themes(styled)も提供。

**🖼️ 公式ショーケース**: Primitives → https://www.radix-ui.com/primitives/docs/overview/introduction ／ Themes → https://www.radix-ui.com/themes/docs

**🔥 差別化**: ヘッドレスの事実上の標準。豊富な採用実績。

**🏢 ClassLab.活用**: 自社デザインシステムの挙動基盤（shadcn/ui経由が現実的）。

**⚠️ 注意点**: **WorkOSが買収し一部の更新が鈍化**。新規の基盤としては Base UI も検討。

---

#### 4.C.2 Base UI（MUIチーム）

**🎯 概要・デザインテイスト** — **デザインなし**（最新ヘッドレス）

![Base UI 公式プレビュー](https://base-ui.com/opengraph-image-j8qpfc.png?b1b9e0366e512854)

MUI / Radix / Floating UI の開発者が結集して作る新しいヘッドレスライブラリ。**v1.0 を2025年12月に到達**。multi-select / combobox など Radix にないパターンも提供し、活発に開発中。

**👨‍💻 用途**: 最新のヘッドレス基盤、Radixの代替、自前デザインのデザインシステム。

**⭐ 機能性 & Star**: ~4k★（新興・成長中）/ v1.0安定版 / multi-select/combobox等 / 活発な開発。

**🖼️ 公式ショーケース**: https://base-ui.com/react/overview/quick-start （コンポーネントは左ナビ）

**🔥 差別化**: Radixの更新鈍化を埋める「ヘッドレスの後継候補」。豊富なパターンと活発な保守。

**🏢 ClassLab.活用**: 新規デザインシステムの挙動基盤（中長期）。

**⚠️ 注意点**: 新しくStar/採用実績はこれから。エコシステム成熟度はRadix未満。

---

#### 4.C.3 React Aria（Adobe）

**🎯 概要・デザインテイスト** — **デザインなし**（hooks・アクセシビリティ最重視）

![React Aria 公式プレビュー](https://opengraph.githubassets.com/2/adobe/react-spectrum)

Adobe製。**アクセシビリティを最も厳格に**扱うヘッドレス。40以上のパターンを、挙動・ARIA・国際化・アダプティブ操作まで含めて hooks で提供。フックを組み合わせて自前コンポーネントを作る。

**👨‍💻 用途**: a11y契約要件（政府/エンタープライズ）、国際化必須、独自デザインで堅牢な挙動が欲しい。

**⭐ 機能性 & Star**: ~14k★（React Spectrum）/ 40+パターン / WAI-ARIA準拠・i18n・アダプティブ / hooks合成。

**🖼️ 公式ショーケース**: https://react-spectrum.adobe.com/react-aria/components.html

**🔥 差別化**: アクセシビリティと国際化の厳格さが随一。HeroUIの基盤でもある。

**🏢 ClassLab.活用**: 公共/金融など a11y要件が厳しい案件の挙動基盤。

**⚠️ 注意点**: 学習コストが高い（hooks合成）。スタイルは完全自前。

---

## 5. 比較マトリクス

### 5.1 デザインテイスト一覧（重複回避の確認）

| ライブラリ | デザインテイスト | 被りやすい相手との違い |
|---|---|---|
| MUI | マテリアル | 唯一のGoogle Material |
| Ant Design | エンタープライズ整然 | データ密・独自言語（Carbonより柔らかい） |
| shadcn/ui | ミニマル中立 | 着色前提・own-code（HeroUIより素） |
| Chakra UI | フレンドリー角丸 | style props・親しみ（Mantineより装飾的） |
| Mantine | モダン実用フラット | 多機能・中庸（Chakraより硬派） |
| HeroUI | 洗練ガラス調 | モーション・rounded（shadcnより華やか） |
| Fluent UI | Fluent（半透明深度） | Microsoft固有 |
| Carbon | 工業的シャープ | 高コントラスト硬質（Antより硬い） |
| PrimeReact | テーマ可変 | 着せ替え前提（固定テイストを持たない） |
| React Bootstrap | Bootstrap | クラシック既視感 |
| Blueprint | 高密度データ | 情報過密・デスクトップ |
| Tremor | ダッシュボード | チャート前提の特化 |
| Radix/Base UI/React Aria | デザインなし | スタイルを持たない（テイスト非該当） |

### 5.2 機能性比較

> 凡例: 対応 / 一部 / 非対応。コンポーネント数は無料枠の概数。

| ライブラリ | コンポーネント数 | 高機能DataGrid/Table | フォーム支援 | チャート | a11y | SSR/RSC | TypeScript |
|---|:-:|:-:|:-:|:-:|:-:|:-:|:-:|
| MUI | 100+ | 対応(MUI X) | 一部 | 対応(MUI X) | 対応 | 一部(Pigment移行中) | 対応 |
| Ant Design | 60+ | 対応 | 対応(Form) | 一部 | 対応 | 一部 | 対応 |
| shadcn/ui | 50+(任意追加) | 一部(TanStack併用) | 対応(RHF前提) | 一部 | 対応(Radix) | 対応 | 対応 |
| Chakra UI | 50+ | 非対応 | 一部 | 非対応 | 対応 | 対応 | 対応 |
| Mantine | 100+ | 一部 | 対応(@mantine/form) | 対応 | 対応 | 対応(ゼロランタイム) | 対応 |
| HeroUI | 50+ | 一部 | 一部 | 非対応 | 対応(React Aria) | 対応 | 対応 |
| Fluent UI | 60+ | 対応 | 一部 | 一部 | 対応 | 一部 | 対応 |
| Carbon | 40+ | 対応 | 一部 | 対応(Carbon Charts) | 対応 | 一部 | 対応 |
| PrimeReact | 90+ | 対応(高度) | 対応 | 対応 | 対応 | 一部 | 対応 |
| React Bootstrap | 30+ | 非対応 | 一部 | 非対応 | 一部 | 一部 | 対応 |
| Blueprint | 40+ | 対応(高密度) | 一部 | 一部 | 対応 | 一部 | 対応 |
| Tremor | 30+(ダッシュ) | 一部 | 非対応 | 対応(特化) | 一部 | 対応 | 対応 |
| Radix UI | 30+(headless) | 非対応 | 非対応 | 非対応 | 対応(厳格) | 対応 | 対応 |
| Base UI | 25+(headless) | 非対応 | 非対応 | 非対応 | 対応(厳格) | 対応 | 対応 |
| React Aria | 40+(hooks) | 一部(hooks) | 一部(hooks) | 非対応 | 対応(最厳格) | 対応 | 対応 |

### 5.3 GitHub Star / スタイリング / ライセンス（2026-05 概算）

| ライブラリ | GitHub Star | スタイリング方式 | ライセンス | 有料上位 |
|---|---|---|---|---|
| shadcn/ui | ~104k★ | Tailwind(own-code) | MIT | — |
| MUI | ~95k★ | CSS-in-JS→Pigment | MIT | MUI X Pro/Premium |
| Ant Design | ~94k★ | 独自CSS/トークン | MIT | Ant Design Pro |
| Radix UI | ~94k★ | なし(headless) | MIT | — |
| Chakra UI | ~38k★ | CSS-in-JS→Panda系 | MIT | — |
| Mantine | ~30k★ | CSS Modules(ゼロランタイム) | MIT | — |
| HeroUI | ~24k★ | Tailwind v4 | MIT | HeroUI Pro |
| React Bootstrap | ~22k★ | Bootstrap CSS | MIT | — |
| Blueprint | ~21k★ | 独自CSS(Sass) | Apache-2.0 | — |
| Fluent UI | ~19k★ | CSS-in-JS(Griffel) | MIT | — |
| Tremor | ~15k★ | Tailwind | Apache-2.0 | — |
| React Aria | ~14k★(Spectrum) | なし(hooks/headless) | Apache-2.0 | — |
| Carbon | ~8k★ | 独自CSS/トークン(Sass) | Apache-2.0 | — |
| PrimeReact | ~7k★ | テーマCSS(着せ替え) | MIT | — |
| Base UI | ~4k★ | なし(headless) | MIT | — |

> 注: Star数は変動するため目安。npm週間DLは Star と一致しない（例: Mantine は Star3分の1でもDLはMUIに肉薄、LangGraph同様「Star≠採用」）。

---

## 6. 選定の詳細

### 6.1 アーキ別の選び方

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/react-ui-libraries-features-catalog-2026-05/e3bc0937-mermaid-04.png" alt="6.1 アーキ別の選び方 概念図" width="1536" height="864">

### 6.2 性能・SSRの勘所

- **RSC/Next.js App Router 重視** → ゼロランタイム勢（Mantine / shadcn(Tailwind) / MUI Pigment移行版）が有利。Emotionランタイム(旧MUI/Chakra)はRSCで注意。
- **バンドル最小化** → Tailwind系(shadcn/HeroUI/Tremor)やヘッドレス+自前が軽い。Ant/MUIは機能が多い分大きい。
- **データ密アプリ** → MUI X / Ant Table / PrimeReact DataTable / Blueprint が選択肢。

---

## 7. ClassLab. での活用ロードマップ（汎用例）

### 7.1 短期（〜3ヶ月）

| 用途 | 推奨 | 内容 |
|---|---|---|
| 自社プロダクトの独自UI | shadcn/ui | デザインを所有しブランドに合わせる。Weekly Newsサイト系に最適 |
| 社内管理画面 | MUI(+MUI X) / Ant Design | DataGrid/Tableで契約・顧客データ管理を高速構築 |
| 社内ダッシュボード | Tremor / Mantine charts | KPI・契約数・売上の可視化 |
| 素早い検証UI | Chakra UI / Mantine | プロトタイプ・社内ツールを最短で |

### 7.2 中長期（3〜12ヶ月）

| 用途 | 推奨 | 内容 |
|---|---|---|
| 自社デザインシステム | Radix/Base UI/React Aria + Tailwind | 挙動・a11y基盤の上に独自スタイルを構築 |
| a11y要件が厳しい案件 | React Aria | WAI-ARIA/国際化を担保した堅牢なUI |
| 高機能業務アプリ | PrimeReact / Ant Design / Blueprint | 帳票・高度テーブル・データ密オペUI |

### 7.3 既存資産との関係

- Weekly News サイト（Next.js）は **shadcn/ui + Radix(→Base UI)** の所有モデルが最も相性が良い
- 社内ツールは速度重視で **Mantine / MUI**、データ業務は **Ant / PrimeReact**

---

## 8. 採用判断フロー

### 8.1 採用適性 Quadrant

<img src="https://d2f75plg0t6qwk.cloudfront.net/knowledge/react-ui-libraries-features-catalog-2026-05/cab3fee4-mermaid-05.png" alt="8.1 採用適性 Quadrant 概念図" width="1536" height="864">

### 8.2 ひとことサマリ（用途で即決）

| こういう時 | これ |
|---|---|
| 新規で自社デザインを所有 | **shadcn/ui** |
| とにかく機能網羅・実績 | **MUI** / **Ant Design** / **PrimeReact** |
| 多機能を一括 + SSR高速 | **Mantine** |
| 見栄え重視のLP/SaaS | **HeroUI** |
| データ密の業務/分析 | **Blueprint** / **Ant** / **Carbon** |
| ダッシュボード | **Tremor** |
| a11y契約要件 | **React Aria** |
| 自前デザインシステム基盤 | **Radix UI** / **Base UI** |
| Microsoft連携 | **Fluent UI** |
| Bootstrap資産の移行 | **React Bootstrap** |

---

## 9. 公式リファレンス & Sources

### 公式サイト / コンポーネント一覧

- MUI: https://mui.com/ ／ https://mui.com/material-ui/all-components/
- Ant Design: https://ant.design/ ／ https://ant.design/components/overview/
- shadcn/ui: https://ui.shadcn.com/ ／ https://ui.shadcn.com/docs/components ／ https://ui.shadcn.com/blocks
- Chakra UI: https://chakra-ui.com/
- Mantine: https://mantine.dev/ ／ https://ui.mantine.dev/
- HeroUI: https://www.heroui.com/
- Fluent UI: https://react.fluentui.dev/
- Carbon: https://carbondesignsystem.com/ ／ https://react.carbondesignsystem.com/
- PrimeReact: https://primereact.org/
- React Bootstrap: https://react-bootstrap.netlify.app/
- Blueprint: https://blueprintjs.com/
- Tremor: https://tremor.so/
- Radix UI: https://www.radix-ui.com/
- Base UI: https://base-ui.com/
- React Aria: https://react-spectrum.adobe.com/react-aria/

### 参照した Web Sources

- [15+ Best React UI Component Libraries 2026 — UIdeck](https://uideck.com/blog/react-component-libraries)
- [14 Best React UI Component Libraries 2026 — Untitled UI](https://www.untitledui.com/blog/react-component-libraries)
- [17 Best React UI Frameworks & Component Libraries 2026 — AdminLTE](https://adminlte.io/blog/react-ui-frameworks/)
- [The best React UI component libraries of 2026 — Croct](https://blog.croct.com/post/best-react-ui-component-libraries)
- [shadcn/ui vs MUI vs Ant Design 2026 — AdminLTE](https://adminlte.io/blog/shadcn-ui-vs-mui-vs-ant-design/)
- [Mantine vs Chakra UI vs MUI 2026 — AdminLTE](https://adminlte.io/blog/mantine-vs-chakra-ui-vs-mui/)
- [Top Headless UI libraries for React in 2026 — GreatFrontEnd](https://www.greatfrontend.com/blog/top-headless-ui-libraries-for-react-in-2026)
- [Headless UI alternatives: Radix vs React Aria vs Ark vs Base UI — LogRocket](https://blog.logrocket.com/headless-ui-alternatives/)
- [Base UI vs Radix UI 2026 — BestskyTools](https://bestsky.tools/blog/base-ui-vs-radix-ui)
- [HeroUI v3 (Previously NextUI) — 公式](https://heroui.com/) ／ [GitHub](https://github.com/heroui-inc/heroui)
- [Best React Component Libraries (2026): 12 Options Ranked — DesignRevision](https://designrevision.com/blog/best-react-component-libraries)
- [15 Best React UI Libraries 2026 — Builder.io](https://www.builder.io/blog/react-component-libraries-2026)
- [Blueprint — Palantir (GitHub)](https://github.com/palantir/blueprint)
- [React Bootstrap GitHub](https://github.com/react-bootstrap/react-bootstrap) ／ [Tremor GitHub](https://github.com/tremorlabs/tremor) ／ [Adobe React Spectrum GitHub](https://github.com/adobe/react-spectrum)

> 注: GitHub Star数・バージョン・買収/改名などの事実は 2026-05 時点の Web 調査に基づく概算。各ライブラリは更新が速いため、採用前に必ず公式サイト/リポジトリで最新値を確認すること。サンプル画像は各公式の社会的プレビュー（OGP）アセットへのリンクであり、本ドキュメントは画像を再ホストしていない。
