---
name: rasis-report
description: "RASIS品質レポート生成 - Asanaインシデント管理データからR/A/S指標を自動計測しMarkdownレポートを出力"
category: workflow
complexity: enhanced
model: opus
mcp-servers: [asana]
---

# /rasis-report - RASIS品質レポート生成

## 概要

Asana「CRMインシデント管理」プロジェクトのタスクデータを取得し、RASIS指標（R: 信頼性、A: 可用性、S: 保守性）を自動計測してMarkdownレポートを生成するコマンド。

**実行頻度:** 週1回（QA MTG前に実行）

## 使用方法

```
# 標準実行（直近のデータで全指標を計算）
/rasis-report

# 引数を指定することも可能
/rasis-report $ARGUMENTS
```

## 定数定義

### Asanaプロジェクト

```
PROJECT_GID = "1210141860554779"   # CRMインシデント管理
```

### セクションGID分類

```
IMPACT_SECTION_GIDS（業務影響あり = A/Sで使用）:
  "1210141860554780"   # 未対応           ← トリアージ前のためRASIS計算から除外
  "1213583272288474"   # 一時対応 / 復旧まで
  "1212427130084727"   # 調査中
  "1212427130084711"   # 調査済み
  "1212442930023501"   # 修正待機中
  "1212411628435001"   # 改修中
  "1212411628434999"   # 完了済み
  "1213308608099451"   # 水道自動申込

RELIABILITY_SECTION_GIDS（R(MTBF)の分母 = トリアージ済みセクションのみ）:
  "1213583272288474"   # 一時対応 / 復旧まで
  "1212427130084727"   # 調査中
  "1212427130084711"   # 調査済み
  "1212442930023501"   # 修正待機中
  "1212411628435001"   # 改修中
  "1212411628434999"   # 完了済み
  "1213308608099451"   # 水道自動申込

NO_IMPACT_SECTION_GIDS（業務影響なし = R/Aから除外）:
  "1212895654036871"   # 修正が必要な業務に影響のないタスク ← S分母には含む
  "1212427130084716"   # 影響のないエラー        ← S分母からも除外
  "1212427130084717"   # 重複エラー              ← S分母からも除外
  "1213037757239679"   # SINGLE_EMAIL_LIMIT...   ← S分母からも除外
  "1212411628435000"   # 過去のエラー            ← S分母からも除外

EXCLUDED_FROM_SERVICEABILITY（Sの分母から除外）:
  "1212427130084716"   # 影響のないエラー
  "1212427130084717"   # 重複エラー
  "1213037757239679"   # SINGLE_EMAIL_LIMIT_EXCEEDED
  "1212411628435000"   # 過去のエラー
```

### カスタムフィールドGID

```
INCIDENT_LEVEL_GID  = "1212430676458427"   # インシデントレベル（enum: 高/中/低）
  HIGH_GID   = "1212430676458428"
  MEDIUM_GID = "1212430676458429"
  LOW_GID    = "1212430676458430"

TAIOU_SECTION_GID     = "1213583272288474" # 一時対応 / 復旧まで（MTTR-1のセクション離脱検知対象）
ERROR_TYPE_GID        = "1210376591796313" # エラー種別
```

### 目標値

```
A_TARGET = 0.99      # 99%
S_TARGET_HOURS = 1   # MTTR 1時間以内

MEASUREMENT_START = "2026-03-10"  # 計測開始日
MAX_PERIOD = 365                  # 最大計測日数

# 経過日数の算出ロジック:
#   elapsed = (today - MEASUREMENT_START) の日数
#   if elapsed > MAX_PERIOD:
#     period = MAX_PERIOD
#     periodStart = today - MAX_PERIOD日
#   else:
#     period = elapsed
#     periodStart = MEASUREMENT_START
```

## 出力

**必ずMarkdownファイルを出力すること。**

- 出力先: `doc_draft/rasis-report/rasis-report-YYYY-MM-DD.md`
- ディレクトリがなければ作成する
- 過去のレポートは上書きしない（日付付きファイル名）
- レポート出力後、サマリーをコンソールにも表示する

## 実行フロー

```
Step 1: Asana APIでタスク全件取得（ページネーション対応）
  ↓
Step 2: 各タスクのセクションGIDで分類
  ↓
Step 3: R（信頼性）計算 → MTBF = 経過日数 / エラー回数
Step 4: MTTR候補を収集 → Stories APIでMTTR取得
Step 5: A（可用性）・S（保守性）計算
  ↓
Step 6: Markdownレポート生成 → doc_draft/rasis-report/ に出力
```

## Step 1: タスク全件取得

Asana MCPの `asana_get_tasks` を使用してタスクを取得する。

```
呼び出し:
  mcp__asana__asana_get_tasks({
    project: "1210141860554779",
    opt_fields: "name,created_at,completed,completed_at,memberships.section.gid,memberships.section.name,custom_fields.gid,custom_fields.name,custom_fields.date_value,custom_fields.enum_value.gid,custom_fields.enum_value.name",
    limit: 100
  })

ページネーション:
  - レスポンスに `next_page.offset` がある場合、offset を指定して次ページを取得
  - offsetがnullになるまで繰り返す
  - 全ページの data を結合して全タスクリストを作成
```

**重要:** 必ず全件取得すること。ページネーションが残っている場合は `offset` を渡して次のページを取得し続ける。

## Step 2: セクション判定

各タスクについて、CRMインシデント管理プロジェクトでのセクションを特定する。

```
function getTaskSection(task):
    ALL_KNOWN_GIDS = IMPACT_SECTION_GIDS + NO_IMPACT_SECTION_GIDS

    for membership in task.memberships:
        if membership.section.gid in ALL_KNOWN_GIDS:
            return membership.section  // CRMインシデント管理のセクション

    // フォールバック: 最初のセクション
    return task.memberships[0].section
```

## Step 3: R（信頼性）計算 - MTBF

**計算式:** `R（MTBF） = 経過日数 / エラー回数`（日）

トリアージ済みの業務影響ありインシデントの発生頻度から、平均故障間隔（MTBF）を算出する。
**計測開始日（2026-03-10）から365日未満の場合は経過日数を使用し、365日以上経過後は直近365日間で算出する。**

```
function calcReliability(tasks, now):
    // 期間算出
    elapsed = (now - MEASUREMENT_START) の日数
    if elapsed > MAX_PERIOD:
        period = MAX_PERIOD
        periodStart = now - MAX_PERIOD日
    else:
        period = elapsed
        periodStart = MEASUREMENT_START

    errorCount = 0
    recentErrors = []  // 直近エラー一覧

    for task in tasks:
        sectionGid = getTaskSection(task).gid
        if sectionGid NOT IN RELIABILITY_SECTION_GIDS:
            continue  // トリアージ前・業務影響なしセクションはスキップ

        createdAt = parseDateTime(task.created_at)
        if createdAt < periodStart:
            continue  // 期間より前はスキップ

        errorCount += 1
        recentErrors.append({
            name: task.name,
            date: toJSTDate(createdAt)
        })

    if errorCount == 0:
        mtbf = null  // エラーなし → MTBF算出不可（最良の状態）
    else:
        mtbf = period / errorCount  // 日

    // 出力: MTBF（日）、エラー回数、直近エラー一覧（最大5件、降順）
    return {
        mtbf: mtbf,
        errorCount: errorCount,
        recentErrors: recentErrors をソート（降順）して最大5件
    }
```

## Step 4: MTTR候補の収集 + Stories API呼び出し

**計測期間内の候補を収集し、Stories APIでセクション移動履歴を取得する。**

### Step 4-1: MTTR候補タスク収集

```
function collectMttrCandidates(tasks, now):
    // 期間算出（Step 3と同じロジック）
    elapsed = (now - MEASUREMENT_START) の日数
    if elapsed > MAX_PERIOD:
        periodStart = now - MAX_PERIOD日
    else:
        periodStart = MEASUREMENT_START
    TAIOU_SECTION_GID = "1213583272288474"  // 一時対応 / 復旧まで

    candidateTasks = []
    for task in tasks:
        sectionGid = getTaskSection(task).gid
        if sectionGid NOT IN IMPACT_SECTION_GIDS:
            continue

        createdAt = parseDateTime(task.created_at)
        if createdAt < periodStart:
            continue

        // 現在「一時対応」セクションに滞留中 → 復旧未完了のためスキップ
        if sectionGid == TAIOU_SECTION_GID:
            continue

        candidateTasks.append(task)

    return candidateTasks
```

### Step 4-2: Stories APIで各タスクのセクション移動履歴を取得

```
function fetchMttrData(candidateTasks):
    // 全候補タスクのMTTRデータを取得（API呼び出しは1候補1回）
    mttrData = []  // { gid, createdAt, mttrHours }

    for task in candidateTasks:
        stories = mcp__asana__asana_get_stories_for_task({
            task_id: task.gid,
            opt_fields: "resource_subtype,text,created_at"
        })

        // 「一時対応 / 復旧まで」から別セクションへ移動したストーリーを検索
        recoveryAt = null
        for story in stories.data:
            if story.text に "一時対応" が含まれる:
                if story.text が "from 一時対応" or "「一時対応」から" パターンにマッチ:
                    recoveryAt = parseDateTime(story.created_at)
                    break  // 最初の離脱（= 暫定復旧完了）を採用

        if recoveryAt == null:
            continue

        createdAt = parseDateTime(task.created_at)
        mttrHours = (recoveryAt - createdAt) のミリ秒差 / 3,600,000

        if mttrHours < 0:
            continue

        mttrData.append({
            gid: task.gid,
            createdAt: createdAt,
            mttrHours: mttrHours
        })

    return mttrData
```

### Stories API呼び出しの注意

- **API呼び出し回数**: 候補タスク1件につき1回のStories API呼び出しが発生
- **精度向上**: Stories APIは秒単位のタイムスタンプを返すため高精度

## Step 5: A（可用性）・S（保守性）を算出

Step 4で取得した `mttrData` から A/S を算出する。

### A（可用性）計算

**計算式:** `A = (経過日数 × 24 − MTTR合計) / (経過日数 × 24) × 100%`

> **計測対象**: 業務に多大な影響を与え、即時復旧が必要なインシデントのみ復旧時間（MTTR）を計測する。
> 計測範囲はインシデント起票から一時対応（暫定復旧）完了までの時間。
> 調査依頼や特定レコードのエラーなど、即時の業務復旧を伴わないタスクは復旧時間の計測対象に含まない。

```
function calcAvailability(mttrData, period):
    TOTAL_HOURS = period * 24  // period日分の総時間

    mttrList = [d.mttrHours for d in mttrData]

    sumMttr = sum(mttrList)
    availability = (TOTAL_HOURS - sumMttr) / TOTAL_HOURS

    return {
        rate: availability,
        sumMttrHours: sumMttr,
        totalHours: TOTAL_HOURS,
        count: len(mttrList),
        mttrList: mttrList,
        meetsTarget: availability >= A_TARGET
    }
```

### S（保守性）計算 - MTTR

**計算式:** `S（MTTR） = AVG(「一時対応」セクション離脱時刻 - created_at)`（H）

```
function calcServiceability(mttrList):
    if mttrList が空:
        return { avg: null, median: null, count: 0, meetsTarget: true }

    avg = sum(mttrList) / len(mttrList)
    med = median(mttrList)

    return {
        avg: avg,
        median: med,
        count: len(mttrList),
        meetsTarget: avg <= S_TARGET_HOURS
    }
```

**median計算:**

```
function median(arr):
    sorted = arr.sort(昇順)
    mid = floor(sorted.length / 2)
    if sorted.length が奇数: return sorted[mid]
    else: return (sorted[mid-1] + sorted[mid]) / 2
```

## Step 6: レポート出力

### 出力先

```
doc_draft/rasis-report/rasis-report-YYYY-MM-DD.md
```

### 出力フォーマット

実行日のレポートをMarkdown形式で生成する。以下のテンプレートに従うこと。
**集計期間は計測開始日（2026-03-10）からの経過日数（最大365日）。**

```markdown
# RASIS品質レポート - YYYY/MM/DD (曜日)

> 対象プロジェクト: CRMインシデント管理
> レポート生成日時: YYYY-MM-DD HH:MM (JST)
> 集計期間: YYYY-MM-DD 〜 YYYY-MM-DD（XX日間）
> ※計測開始日（2026-03-10）から365日未満のため、経過日数で算出（365日経過後はローリングウィンドウ）

---

## サマリー

| 指標             | 値     | 目標   | 判定                |
| ---------------- | ------ | ------ | ------------------- |
| R 信頼性（MTBF） | X.XX日 | -      | -                   |
| A 可用性         | XX.X%  | 99%    | 🟢 達成 / 🔴 未達成 |
| S 保守性（MTTR） | X.XH   | 1H以内 | 🟢 達成 / 🔴 未達成 |

---

## R 信頼性（Reliability）- MTBF

| 項目       | 値                       |
| ---------- | ------------------------ |
| MTBF       | X.XX日                   |
| 計測期間   | YYYY-MM-DD 〜 YYYY-MM-DD |
| エラー回数 | X件                      |
| 計算式     | 経過日数 / エラー回数    |

### 直近のインシデント（5件）

| #   | タスク名   | 発生日     |
| --- | ---------- | ---------- |
| 1   | [タスク名] | YYYY-MM-DD |
| ... | ...        | ...        |

（エラーがない場合: 「計測期間内に業務影響インシデントなし（MTBF算出不可）」と表示）

---

## A 可用性（Availability）

| 項目         | 値                                         |
| ------------ | ------------------------------------------ |
| 可用性       | XX.X%                                      |
| MTTR合計     | X.XH                                       |
| 総稼働時間   | XX×24H（経過日数×24H）                     |
| 対象タスク数 | X件                                        |
| 計測期間     | YYYY-MM-DD 〜 YYYY-MM-DD                   |
| 計算式       | (経過日数×24H - MTTR合計) / (経過日数×24H) |
| 目標達成     | 🟢 達成 / 🔴 未達成                        |

> **計測対象について**
> 業務に多大な影響を与え、即時復旧が必要なインシデントのみ復旧時間（MTTR）を計測しています。
> 計測範囲はインシデント起票から一時対応（暫定復旧）完了までの時間です。
> 調査依頼や特定レコードのエラーなど、即時の業務復旧を伴わないタスクは復旧時間の計測対象に含まれません。

### MTTR内訳

| #   | タスク名   | 起票日時 (JST)   | 復旧日時 (JST)   | MTTR  |
| --- | ---------- | ---------------- | ---------------- | ----- |
| 1   | [タスク名] | YYYY-MM-DD HH:MM | YYYY-MM-DD HH:MM | X.XXH |

（対象タスクが0件の場合: 「計測期間内にMTTR対象タスクなし → 可用性100%」と表示）

---

## S 保守性（Serviceability）- MTTR

| 項目         | 値                       |
| ------------ | ------------------------ |
| MTTR 平均    | X.XH                     |
| MTTR 中央値  | X.XH                     |
| 対象タスク数 | X件                      |
| 計測期間     | YYYY-MM-DD 〜 YYYY-MM-DD |
| 目標達成     | 🟢 達成 / 🔴 未達成      |

（対象タスクが0件の場合: 「計測期間内にMTTR対象タスクなし（一時対応を経由したタスクなし）」と表示）

---

## セクション別タスク分布（参考）

| セクション     | タスク数 | 分類                   |
| -------------- | -------- | ---------------------- |
| [セクション名] | X        | 業務影響あり/なし/除外 |
| ...            | ...      | ...                    |

---

## 今週のインシデント

直近7日間に起票されたインシデント一覧を表示する。

| #   | タスク名 | 起票日     | セクション   | インシデントレベル |
| --- | -------- | ---------- | ------------ | ------------------ |
| 1   | [名前]   | YYYY-MM-DD | [セクション] | 高/中/低/未設定    |

（0件の場合: 「直近7日間にインシデントなし」と表示）

---

## 注記

- R: MTBF = 経過日数 / エラー回数（トリアージ済みの業務影響ありインシデント数）
- A: 可用性 = (経過日数×24H - MTTR合計) / (経過日数×24H)
  - MTTRは業務に多大な影響を与え即時復旧が必要なインシデントのみ対象（一時対応フローを経由したタスク）
  - 計測範囲はインシデント起票〜一時対応（暫定復旧）完了まで
  - 調査依頼や特定レコードのエラーなど、即時の業務復旧を伴わないタスクは対象外
- S: MTTR = 一時対応（暫定復旧）完了時刻 - created_at の平均（時間単位）
- 業務影響あり判定はセクションベース（IMPACT_SECTION_GIDS）
- タイムゾーン: JST（UTC+9）で日付判定
- 計測開始日: YYYY-MM-DD（2026-03-10）。365日未満のため経過日数（XX日）で算出。365日経過後は直近365日間のローリングウィンドウに切替
```

## タイムゾーン処理

- `created_at` はISO8601形式（UTC）で返される → JST（+9時間）に変換して日付判定
- Stories APIの `created_at` もISO8601形式（UTC）→ JST（+9時間）に変換して計算
- **精度向上**: Stories APIは秒単位のタイムスタンプを返すため、旧方式（カスタムフィールドの日付のみ）より高精度

## エッジケース

| ケース                          | 対応                                                            |
| ------------------------------- | --------------------------------------------------------------- |
| 計測期間内にエラー0件           | R: MTBF算出不可（最良）, A=100%, S=データなし                   |
| 全タスクが除外セクション        | R: MTBF算出不可, A=100%, S=データなし                           |
| 一時対応を経由せず直接完了      | A/S: MTTR対象外（セクション離脱ストーリーなし）                 |
| 「一時対応 / 復旧まで」に滞留中 | A/S: MTTR対象外（現在セクションが一時対応のためスキップ）       |
| Stories APIレスポンスが空       | A/S: MTTR対象外として処理（一時対応を経由していない）           |
| MTTR合計 > 総稼働時間           | A: 0%として扱う                                                 |
| 計測開始日から365日未満         | 経過日数で算出（注記に記載）。365日経過後はローリングウィンドウ |

## 実行時の注意

1. **全件取得を必ず行う**: ページネーションが終わるまで `offset` を渡して取得し続けること
2. **JST変換を忘れない**: `created_at` はUTCで返されるため、日付判定前にJST変換する
3. **レポートは毎回新規作成**: 日付付きファイル名で保存し、過去のレポートは上書きしない
4. **計算結果をコンソールにも表示**: ファイル保存前にサマリーをユーザーに表示する

---

---

# Appendix A: 設計書（RASIS品質指標）

> 元ファイル: `doc_draft/basic-design/RASIS品質指標/README.md`

## A-1. 背景・目的

### 背景

- インシデントMTGを「品質保証(QA)MTG」に改称し、対象範囲を拡大
- システム品質をRASIS（信頼性・可用性・保守性・完全性・機密性）の5軸で評価する方針を決定
- 日次でRASIS指標を把握し、QA MTGでの品質改善サイクルを回す必要がある

### 目的

Asana「CRMインシデント管理」プロジェクトのデータを元に、RASIS指標を自動計測し、日次でSlackに投稿する仕組みを構築する。

## A-2. フェーズ分け

| フェーズ      | 期間                   | 対象指標                              | 状態   |
| ------------- | ---------------------- | ------------------------------------- | ------ |
| **フェーズ1** | 3月〜 運用開始         | R（信頼性）, A（可用性）, S（保守性） | 着手   |
| **フェーズ2** | 4月〜 スケジューリング | I（完全性）, S（機密性）              | 未着手 |

## A-3. データソース

### Asana プロジェクト

| 項目            | 内容                                                                                  |
| --------------- | ------------------------------------------------------------------------------------- |
| プロジェクト名  | CRMインシデント管理                                                                   |
| プロジェクトGID | `1210141860554779`                                                                    |
| 認証方式        | Personal Access Token（Script Propertiesに格納）                                      |
| 取得方式        | Asana REST API（`next_page.offset` でページネーション、limit=100/リクエスト）         |
| 取得項目        | タスク名, created_at, completed, completed_at, セクション情報, カスタムフィールド全て |

### カスタムフィールド一覧

| フィールド名       | GID                | 型   | 選択肢                                     | RASIS用途                                                                           |
| ------------------ | ------------------ | ---- | ------------------------------------------ | ----------------------------------------------------------------------------------- |
| エラー種別         | `1210376591796313` | enum | オペレーションに影響あり / 対応不要 / 重複 | R: 業務影響の判定、S: 除外対象の判定                                                |
| インシデントレベル | `1212430676458427` | enum | 高 / 中 / 低                               | A: レベル別MTTR内訳                                                                 |
| 対応種別           | `1210141956819951` | enum | エラー / 生産性向上                        | 参考情報                                                                            |
| 起票種別           | `1212430676458454` | enum | ユーザー / システム                        | 参考情報                                                                            |
| 完了日             | `1212716524519634` | date | -                                          | 参考情報（計算にはcompleted_atを使用）                                              |
| 一時対応完了日時   | `1213587177650004` | date | -                                          | ~~A: MTTR-1の終点~~ → Stories APIに移行済み（フィールドは残存するが計算には未使用） |

### タイムスタンプ

| タイムスタンプ | 取得元                      | 用途                                               |
| -------------- | --------------------------- | -------------------------------------------------- |
| `created_at`   | Asanaタスク自動記録         | インシデント起票日時（障害発生日の判定、MTTR起点） |
| `completed_at` | Asanaタスク完了時に自動記録 | MTTR終点、完了判定                                 |

## A-4. セクションベース判定

> **背景**: カスタムフィールド「エラー種別」の入力率が現状0%のため、**セクション所属**で業務影響の有無を判定する。
> カスタムフィールドの運用が定着した段階でフィールドベースに切替可能な設計とする。

### セクション分類マッピング

| セクション                         | GID                | R（障害日） | A（MTTR-1） | S（分母） | 分類         |
| ---------------------------------- | ------------------ | ----------- | ----------- | --------- | ------------ |
| 未対応                             | `1210141860554780` | **除外**    | **除外**    | **除外**  | トリアージ前 |
| 一時対応 / 復旧まで                | `1213583272288474` | カウント    | 対象        | 含む      | ワークフロー |
| 調査中                             | `1212427130084727` | カウント    | 対象        | 含む      | ワークフロー |
| 調査済み                           | `1212427130084711` | カウント    | 対象        | 含む      | ワークフロー |
| 修正待機中                         | `1212442930023501` | カウント    | 対象        | 含む      | ワークフロー |
| 改修中                             | `1212411628435001` | カウント    | 対象        | 含む      | ワークフロー |
| 完了済み                           | `1212411628434999` | カウント    | 対象        | 含む      | ワークフロー |
| 水道自動申込                       | `1213308608099451` | カウント    | 対象        | 含む      | 特定カテゴリ |
| 修正が必要な業務に影響のないタスク | `1212895654036871` | **除外**    | 除外        | 含む      | 低影響       |
| 影響のないエラー                   | `1212427130084716` | **除外**    | 除外        | **除外**  | 除外         |
| 重複エラー                         | `1212427130084717` | **除外**    | 除外        | **除外**  | 除外         |
| SINGLE_EMAIL_LIMIT_EXCEEDED        | `1213037757239679` | **除外**    | 除外        | **除外**  | 除外         |
| 過去のエラー                       | `1212411628435000` | **除外**    | 除外        | **除外**  | 除外         |

### セクション判定ロジック

タスクは複数プロジェクトに所属し得るため、CRMインシデント管理プロジェクト内のセクションを特定する必要がある。

```
function セクション判定(task):
    既知のセクションGID一覧 = 業務影響ありGID[] + 業務影響なしGID[]

    for membership in task.memberships:
        if membership.section.gid が 既知のセクションGID一覧 に含まれる:
            return membership.section.gid   ← CRMインシデント管理のセクション

    // 該当なしの場合は最初のセクションを返す（フォールバック）
    return task.memberships[0].section.gid
```

## A-5. Asana項目とRASIS計算式の対応

### 使用するAsana API項目一覧

| #   | Asana API項目                         | 型       | 説明                       | 使用先                                                      |
| --- | ------------------------------------- | -------- | -------------------------- | ----------------------------------------------------------- |
| 1   | `task.created_at`                     | datetime | タスク起票日時（自動記録） | R: 障害発生日の判定, A: MTTR-1起点, S: 期間フィルタ         |
| 2   | `task.completed`                      | boolean  | 完了済みフラグ             | S: 完了カウント                                             |
| 3   | `task.completed_at`                   | datetime | タスク完了日時（自動記録） | A: MTTR-2終点（将来レポート化時に使用）                     |
| 4   | `task.memberships[].section.gid`      | string   | 所属セクションのGID        | R/A/S: セクション分類判定                                   |
| 5   | `task.memberships[].section.name`     | string   | セクション名               | レポート表示用                                              |
| 6   | `task.name`                           | string   | タスク名                   | レポート表示用                                              |
| 7   | `task.custom_fields[].enum_value.gid` | string   | カスタムフィールド値       | A: インシデントレベル別MTTR（補助）                         |
| 8   | `task.custom_fields[].date_value`     | date     | カスタムフィールド日付値   | ~~A: MTTR-1終点~~ → Stories APIに移行（参考情報として残存） |
| -   | `story.created_at`（Stories API）     | datetime | タスク履歴のタイムスタンプ | A: MTTR-1終点（「一時対応」セクション離脱時刻）             |

### 計算式とAsana項目の対応

#### R（信頼性） = `経過日数 / エラー回数`

```
// 期間算出: elapsed = (today - MEASUREMENT_START) の日数、period = min(elapsed, 365)
エラー回数 = COUNT(
    task
    WHERE task.memberships[].section.gid IN RELIABILITY_SECTION_GIDS  // トリアージ済みのIMPACTセクション
      AND task.created_at >= periodStart
)
```

#### A（可用性） - 2段階MTTR

> MTTR-1（暫定復旧）をメイン指標としてレポートに表示する。
> MTTR-2（完全解決）は将来のレポート拡張時に使用する。

**MTTR-1（暫定復旧時間）** = `Σ(「一時対応」セクション離脱時刻 - created_at) / 対象タスク数`

> **方式変更（2026-03）**: カスタムフィールド「暫定復旧日時」+ Asanaルール方式から、**Stories API方式**に移行。
> Asanaルールやカスタムフィールド設定が不要になり、秒単位の精度で計測可能。

#### S（保守性） = `完了済みタスク数 / 対象タスク数`

```
// 期間算出: Step 3と同じ動的期間ロジック
対象タスク数 = COUNT(
    task
    WHERE task.memberships[].section.gid NOT IN EXCLUDED_FROM_SERVICEABILITY
      AND task.created_at >= periodStart
)
```

## A-6. エッジケース

| ケース                          | R                                     | A（MTTR-1）                                            | S                          |
| ------------------------------- | ------------------------------------- | ------------------------------------------------------ | -------------------------- |
| 期間内にタスクが0件             | 100%（障害なし）                      | データなし（目標達成扱い）                             | 100%（対応すべきものなし） |
| 全タスクが除外セクション        | 100%                                  | データなし                                             | 100%                       |
| 1日に100件のインシデント        | 障害日は1日としてカウント             | 暫定復旧日時ありの件数が対象                           | 100件が分母                |
| タスクが複数プロジェクトに所属  | CRMインシデント管理のセクションで判定 | 同左                                                   | 同左                       |
| 一時対応を経由せず直接完了      | カウント（業務影響あり）              | MTTR-1対象外（Stories APIにセクション離脱記録なし）    | 分母に含む                 |
| 「一時対応 / 復旧まで」に滞留中 | カウント（業務影響あり）              | MTTR-1対象外（現在セクションが一時対応のためスキップ） | 分母に含む（未完了）       |
| Stories APIレスポンスが空       | -                                     | MTTR-1対象外（一時対応を経由していないと判定）         | -                          |

## A-7. フェーズ2 要件（IS）- 概要のみ

> 4月に詳細を再定義。現時点では方向性のみ記載。

### I（Integrity / 完全性）

| 候補                  | 概要                                                                   | データソース                               | 難易度 |
| --------------------- | ---------------------------------------------------------------------- | ------------------------------------------ | ------ |
| A. データ不整合検知数 | 定期バッチで参照整合性・必須項目のnull等をチェックし、不整合件数を計測 | Salesforce SOQL（バッチ実行）              | 中     |
| B. 入力規則エラー率   | 入力規則で弾かれた操作の割合を計測                                     | Salesforce EventLogFile（SetupAuditTrail） | 高     |
| C. 手動データ修正件数 | DataLoaderやSF Inspector等での手動修正件数をAPI使用量から推定          | ApiTotalUsage CSV / EventMonitoring        | 中     |

### S（Security / 機密性）

| 候補                  | 概要                                     | データソース            | 難易度 |
| --------------------- | ---------------------------------------- | ----------------------- | ------ |
| A. ログイン異常検知数 | 異常ログイン（時間外、海外IP等）の件数   | Salesforce LoginHistory | 中     |
| B. 権限変更監査       | プロファイル・権限セットの変更件数を追跡 | SetupAuditTrail         | 中     |
| C. 共有ルール違反     | 参照権限のないレコードへのアクセス試行数 | EventMonitoring（有料） | 高     |

## A-8. 運用要件

### Stories API方式への移行（2026-03）

> Asanaルールやカスタムフィールド設定は**不要**。
> MTTR-1の計測はStories API（タスク履歴）から「一時対応 / 復旧まで」セクションの離脱時刻を直接取得する。

### ワークフロー定義

```
未対応 → 一時対応 / 復旧まで → 調査中 → 調査済み → 修正待機中 → 改修中 → 完了済み
          ^^^^^^^^^^^^^^^^
          暫定復旧フェーズ          根本対応フェーズ
          (ここを離脱すると
           暫定復旧日時が自動セット)
```

### セクション移動の運用ルール

1. 一時対応で業務復旧したら「一時対応 / 復旧まで」セクションに移動すること
2. 一時対応完了後、根本対応フェーズに進む際は「調査中」セクションに移動すること
3. インシデント対応完了時は必ず「完了済み」セクションに移動すること
4. 重複と判明した場合は「重複エラー」セクションに移動すること
5. 業務影響がないと判明した場合は「影響のないエラー」セクションに移動すること

### Slack投稿

| 項目         | 内容                                        |
| ------------ | ------------------------------------------- |
| 投稿方式     | Slack Incoming Webhook                      |
| フォーマット | Slack mrkdwn形式（太字、絵文字使用）        |
| 目標達成     | 🟢（緑丸）/ 目標未達 🔴（赤丸）             |
| 実行方式     | GAS時間主導型トリガー（毎日午前9〜10時JST） |

---

---

# Appendix B: 要件定義書

> 元ファイル: `doc_draft/requirement/RASIS品質指標/requirement.md`

## B-1. 機能要件

### FR-01: Asanaデータ取得

| 項目             | 内容                                                                |
| ---------------- | ------------------------------------------------------------------- |
| 概要             | Asana REST APIでCRMインシデント管理プロジェクトの全タスクを取得する |
| データソース     | Asanaプロジェクト「CRMインシデント管理」(GID: `1210141860554779`)   |
| 認証方式         | Personal Access Token（Script Propertiesに格納）                    |
| ページネーション | Asana APIの`next_page.offset`を使い全件取得（limit=100/リクエスト） |

### FR-02: セクションベース判定

セクション分類は本コマンドの「定数定義 > セクションGID分類」を参照。

### FR-03〜05: R/A/S計算

計算ロジックは本コマンドの「Step 3〜5」を参照。

### FR-06: 今日のインシデント一覧

| 項目      | 内容                                                   |
| --------- | ------------------------------------------------------ |
| 概要      | レポート実行日に起票されたインシデントの一覧を表示する |
| 表示項目  | タスク名（60文字まで）, エラー種別, セクション名       |
| 0件の場合 | 「インシデントなし」と表示                             |

### FR-07: Slack投稿

| 項目         | 内容                                 |
| ------------ | ------------------------------------ |
| 投稿方式     | Slack Incoming Webhook               |
| フォーマット | Slack mrkdwn形式（太字、絵文字使用） |

### FR-08: 定期実行

| 項目     | 内容                        |
| -------- | --------------------------- |
| 実行方式 | GAS時間主導型トリガー       |
| 実行頻度 | 毎日1回（午前9時〜10時JST） |

## B-2. 非機能要件

| 項目                | 制限値           | 対応                                             |
| ------------------- | ---------------- | ------------------------------------------------ |
| GAS実行時間上限     | 6分              | ページネーションで全件取得しても十分に収まる想定 |
| Asana APIレート制限 | 150リクエスト/分 | 1回の実行で数リクエスト程度のため問題なし        |
| Slack Webhook制限   | 1メッセージ/秒   | 1回の実行で1メッセージのため問題なし             |

## B-3. エラーハンドリング

| エラー種別                | 対応                                     |
| ------------------------- | ---------------------------------------- |
| Asana API認証エラー       | エラーメッセージをthrow（GASログに記録） |
| Asana APIレスポンスエラー | エラー内容をthrow                        |
| Slack Webhook URL未設定   | エラーメッセージをthrow                  |
| 対象データ0件             | 正常系として扱い「データなし」と表示     |

## B-4. セットアップ手順

1. GASエディタで新規スタンドアロンプロジェクトを作成
2. Appendix CのGASスクリプトの内容をペースト
3. Script Propertiesに `ASANA_TOKEN` と `SLACK_WEBHOOK_URL` を設定
4. `rasis_test()` を実行して計算結果を確認
5. トリガーを追加: `rasis_daily_report` → 毎日午前9〜10時

---

---

# Appendix C: GASスクリプト（参考実装）

> 元ファイル: `scripts/gas/rasis-report.gs`
> このスクリプトはGAS（Google Apps Script）で動作するSlack日次投稿用の参考実装。
> `/rasis-report` コマンド自体はAsana MCPを直接使用してMarkdownレポートを生成する。

```javascript
/**
 * RASIS品質レポート - Google Apps Script
 *
 * Asana「CRMインシデント管理」プロジェクトからデータを取得し、
 * R(信頼性)/A(可用性)/S(保守性)を計算してSlackに日次レポートを投稿する。
 *
 * 判定方式: セクションベース（カスタムフィールドは補助的に使用）
 *
 * セットアップ:
 *   1. Script Properties に以下を設定:
 *      - ASANA_TOKEN: Asana Personal Access Token
 *      - SLACK_WEBHOOK_URL: Slack Incoming Webhook URL
 *   2. トリガー設定: rasis_daily_report を毎日9:00に実行
 */

// ============================================================
// 設定値
// ============================================================
const CONFIG = {
  PROJECT_GID: "1210141860554779",

  TAIOU_SECTION_GID: "1213583272288474",

  IMPACT_SECTION_GIDS: [
    "1210141860554780", // 未対応
    "1213583272288474", // 一時対応 / 復旧まで
    "1212427130084727", // 調査中
    "1212427130084711", // 調査済み
    "1212442930023501", // 修正待機中
    "1212411628435001", // 改修中
    "1212411628434999", // 完了済み
    "1213308608099451" // 水道自動申込
  ],

  NO_IMPACT_SECTION_GIDS: [
    "1212895654036871", // 修正が必要な業務に影響のないタスク
    "1212427130084716", // 影響のないエラー
    "1212427130084717", // 重複エラー
    "1213037757239679", // SINGLE_EMAIL_LIMIT_EXCEEDED
    "1212411628435000" // 過去のエラー
  ],

  EXCLUDED_FROM_SERVICEABILITY: [
    "1212427130084716", // 影響のないエラー
    "1212427130084717", // 重複エラー
    "1213037757239679", // SINGLE_EMAIL_LIMIT_EXCEEDED
    "1212411628435000" // 過去のエラー
  ],

  FIELD: {
    ERROR_TYPE: "1210376591796313",
    INCIDENT_LEVEL: "1212430676458427",
    TASK_TYPE: "1210141956819951",
    COMPLETION_DATE: "1212716524519634"
  },

  INCIDENT_LEVEL_VALUE: {
    HIGH: "1212430676458428",
    MEDIUM: "1212430676458429",
    LOW: "1212430676458430"
  },

  RELIABILITY_DAYS: 90,
  AVAILABILITY_DAYS: 90,
  SERVICEABILITY_DAYS: 90,
  TOTAL_HOURS: 90 * 24,

  TARGET: {
    AVAILABILITY: 0.99,
    SERVICEABILITY_HOURS: 1
  }
};

// ============================================================
// メイン関数
// ============================================================

function rasis_daily_report() {
  const tasks = fetchAllIncidentTasks_();
  const now = new Date();
  const reliability = calcReliability_(tasks, now);
  const availabilityResult = calcAvailability_(tasks, now);
  const serviceability = calcServiceability_(availabilityResult.mttrList);
  const todayIncidents = getTodayIncidents_(tasks, now);
  const message = formatSlackMessage_(
    reliability,
    availabilityResult,
    serviceability,
    todayIncidents,
    now
  );
  postToSlack_(message);
}

function rasis_test() {
  const tasks = fetchAllIncidentTasks_();
  const now = new Date();
  const reliability = calcReliability_(tasks, now);
  const availabilityResult = calcAvailability_(tasks, now);
  const serviceability = calcServiceability_(availabilityResult.mttrList);
  const todayIncidents = getTodayIncidents_(tasks, now);
  Logger.log("=== RASIS テスト結果 ===");
  Logger.log(
    "R(信頼性/MTBF): " +
      (reliability.mtbf !== null
        ? reliability.mtbf.toFixed(1) + "日"
        : "算出不可") +
      " (エラー: " +
      reliability.errorCount +
      "件)"
  );
  Logger.log(
    "A(可用性): " +
      (availabilityResult.rate * 100).toFixed(1) +
      "% (MTTR合計: " +
      availabilityResult.sumMttrHours.toFixed(1) +
      "H, 対象: " +
      availabilityResult.count +
      "件)"
  );
  Logger.log(
    "S(保守性/MTTR): " +
      (serviceability.avg !== null
        ? serviceability.avg.toFixed(1) + "H"
        : "データなし") +
      " (中央値: " +
      (serviceability.median !== null
        ? serviceability.median.toFixed(1) + "H"
        : "-") +
      ")"
  );
  const message = formatSlackMessage_(
    reliability,
    availabilityResult,
    serviceability,
    todayIncidents,
    now
  );
  Logger.log("\n--- Slack投稿プレビュー ---");
  Logger.log(message.text);
}

// ============================================================
// Asana API
// ============================================================

function fetchAllIncidentTasks_() {
  const token =
    PropertiesService.getScriptProperties().getProperty("ASANA_TOKEN");
  if (!token)
    throw new Error("ASANA_TOKEN が Script Properties に設定されていません");
  const optFields = [
    "name",
    "created_at",
    "completed",
    "completed_at",
    "memberships.section.gid",
    "memberships.section.name",
    "custom_fields"
  ].join(",");
  var allTasks = [],
    offset = null;
  do {
    var url =
      "https://app.asana.com/api/1.0/projects/" +
      CONFIG.PROJECT_GID +
      "/tasks?opt_fields=" +
      encodeURIComponent(optFields) +
      "&limit=100";
    if (offset) url += "&offset=" + offset;
    var response = UrlFetchApp.fetch(url, {
      headers: { Authorization: "Bearer " + token },
      muteHttpExceptions: true
    });
    var json = JSON.parse(response.getContentText());
    if (json.errors)
      throw new Error("Asana API Error: " + JSON.stringify(json.errors));
    allTasks = allTasks.concat(json.data);
    offset = json.next_page ? json.next_page.offset : null;
  } while (offset);
  return allTasks;
}

function fetchStoriesForTask_(taskGid) {
  var token =
    PropertiesService.getScriptProperties().getProperty("ASANA_TOKEN");
  var url =
    "https://app.asana.com/api/1.0/tasks/" +
    taskGid +
    "/stories?opt_fields=" +
    encodeURIComponent("resource_subtype,text,created_at");
  var response = UrlFetchApp.fetch(url, {
    headers: { Authorization: "Bearer " + token },
    muteHttpExceptions: true
  });
  var json = JSON.parse(response.getContentText());
  if (json.errors) {
    Logger.log(
      "Stories API Error for task " +
        taskGid +
        ": " +
        JSON.stringify(json.errors)
    );
    return [];
  }
  return json.data || [];
}

function getRecoveryTimeFromStories_(taskGid) {
  var stories = fetchStoriesForTask_(taskGid);
  for (var i = 0; i < stories.length; i++) {
    var story = stories[i];
    if (!story.text) continue;
    if (
      story.text.indexOf("一時対応") !== -1 &&
      (story.text.indexOf("from") !== -1 || story.text.indexOf("から") !== -1)
    ) {
      return new Date(story.created_at);
    }
  }
  return null;
}

// ============================================================
// セクション判定
// ============================================================

function getProjectSectionGid_(task) {
  if (!task.memberships) return null;
  var allKnown = CONFIG.IMPACT_SECTION_GIDS.concat(
    CONFIG.NO_IMPACT_SECTION_GIDS
  );
  for (var i = 0; i < task.memberships.length; i++) {
    var secGid = task.memberships[i].section
      ? task.memberships[i].section.gid
      : null;
    if (secGid && allKnown.indexOf(secGid) !== -1) return secGid;
  }
  if (task.memberships.length > 0 && task.memberships[0].section)
    return task.memberships[0].section.gid;
  return null;
}

function isInImpactSection_(task) {
  var secGid = getProjectSectionGid_(task);
  return secGid !== null && CONFIG.IMPACT_SECTION_GIDS.indexOf(secGid) !== -1;
}

function isExcludedFromServiceability_(task) {
  var secGid = getProjectSectionGid_(task);
  return (
    secGid !== null &&
    CONFIG.EXCLUDED_FROM_SERVICEABILITY.indexOf(secGid) !== -1
  );
}

function getCurrentSectionName_(task) {
  if (!task.memberships || task.memberships.length === 0) return "不明";
  var allKnown = CONFIG.IMPACT_SECTION_GIDS.concat(
    CONFIG.NO_IMPACT_SECTION_GIDS
  );
  for (var i = 0; i < task.memberships.length; i++) {
    var m = task.memberships[i];
    if (m.section && allKnown.indexOf(m.section.gid) !== -1)
      return m.section.name;
  }
  if (task.memberships[0].section) return task.memberships[0].section.name;
  return "不明";
}

// ============================================================
// ヘルパー関数
// ============================================================

function getCustomFieldValue_(task, fieldGid) {
  if (!task.custom_fields) return null;
  for (var i = 0; i < task.custom_fields.length; i++) {
    if (task.custom_fields[i].gid === fieldGid) {
      return task.custom_fields[i].enum_value
        ? task.custom_fields[i].enum_value.gid
        : null;
    }
  }
  return null;
}

function getIncidentLevelLabel_(task) {
  var val = getCustomFieldValue_(task, CONFIG.FIELD.INCIDENT_LEVEL);
  if (val === CONFIG.INCIDENT_LEVEL_VALUE.HIGH) return "高";
  if (val === CONFIG.INCIDENT_LEVEL_VALUE.MEDIUM) return "中";
  if (val === CONFIG.INCIDENT_LEVEL_VALUE.LOW) return "低";
  return "-";
}

function toJSTDateString_(date) {
  var jst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  return jst.toISOString().split("T")[0];
}

function daysAgo_(n, from) {
  var d = new Date(from);
  d.setDate(d.getDate() - n);
  d.setHours(0, 0, 0, 0);
  return d;
}

function median_(arr) {
  if (arr.length === 0) return 0;
  var sorted = arr.slice().sort(function (a, b) {
    return a - b;
  });
  var mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 !== 0
    ? sorted[mid]
    : (sorted[mid - 1] + sorted[mid]) / 2;
}

// ============================================================
// RASIS計算
// ============================================================

function calcReliability_(tasks, now) {
  var periodStart = daysAgo_(CONFIG.RELIABILITY_DAYS, now);
  var errorCount = 0,
    recentErrors = [];
  for (var i = 0; i < tasks.length; i++) {
    var task = tasks[i];
    if (!isInImpactSection_(task)) continue;
    var createdAt = new Date(task.created_at);
    if (createdAt < periodStart) continue;
    errorCount++;
    recentErrors.push({
      name: task.name || "(無題)",
      date: toJSTDateString_(createdAt)
    });
  }
  recentErrors.sort(function (a, b) {
    return b.date.localeCompare(a.date);
  });
  return {
    mtbf: errorCount > 0 ? 365 / errorCount : null,
    errorCount: errorCount,
    recentErrors: recentErrors.slice(0, 5)
  };
}

function calcAvailability_(tasks, now) {
  var periodStart = daysAgo_(CONFIG.AVAILABILITY_DAYS, now);
  var allMttr = [];
  for (var i = 0; i < tasks.length; i++) {
    var task = tasks[i];
    if (!isInImpactSection_(task)) continue;
    var createdAt = new Date(task.created_at);
    if (createdAt < periodStart) continue;
    var currentSectionGid = getProjectSectionGid_(task);
    if (currentSectionGid === CONFIG.TAIOU_SECTION_GID) continue;
    var recoveryAt = getRecoveryTimeFromStories_(task.gid);
    if (!recoveryAt) continue;
    var mttrHours = (recoveryAt - createdAt) / (1000 * 60 * 60);
    if (mttrHours < 0) continue;
    allMttr.push(mttrHours);
  }
  var sumMttr =
    allMttr.length > 0
      ? allMttr.reduce(function (a, b) {
          return a + b;
        }, 0)
      : 0;
  var rate = (CONFIG.TOTAL_HOURS - sumMttr) / CONFIG.TOTAL_HOURS;
  if (rate < 0) rate = 0;
  return {
    rate: rate,
    sumMttrHours: sumMttr,
    count: allMttr.length,
    mttrList: allMttr,
    meetsTarget: rate >= CONFIG.TARGET.AVAILABILITY || allMttr.length === 0
  };
}

function calcServiceability_(mttrList) {
  if (!mttrList || mttrList.length === 0)
    return { avg: null, median: null, count: 0, meetsTarget: true };
  var avg =
    mttrList.reduce(function (a, b) {
      return a + b;
    }, 0) / mttrList.length;
  return {
    avg: avg,
    median: median_(mttrList),
    count: mttrList.length,
    meetsTarget: avg <= CONFIG.TARGET.SERVICEABILITY_HOURS
  };
}

function getTodayIncidents_(tasks, now) {
  var todayStr = toJSTDateString_(now),
    incidents = [];
  for (var i = 0; i < tasks.length; i++) {
    var task = tasks[i];
    if (toJSTDateString_(new Date(task.created_at)) !== todayStr || !task.name)
      continue;
    incidents.push({
      name:
        task.name.length > 60 ? task.name.substring(0, 60) + "..." : task.name,
      section: getCurrentSectionName_(task)
    });
  }
  return incidents;
}

// ============================================================
// レポートフォーマット
// ============================================================

function formatSlackMessage_(
  reliability,
  availability,
  serviceability,
  todayIncidents,
  now
) {
  var dateStr = Utilities.formatDate(now, "Asia/Tokyo", "yyyy/MM/dd (E)");
  var aIcon = availability.meetsTarget
    ? ":large_green_circle:"
    : ":red_circle:";
  var sIcon = serviceability.meetsTarget
    ? ":large_green_circle:"
    : ":red_circle:";
  var text = "";
  text += ":bar_chart: *RASIS品質レポート - " + dateStr + "*\n";
  text += "──────────────────────────────\n\n";
  text += ":chart_with_upwards_trend: *R 信頼性（MTBF）: ";
  text +=
    reliability.mtbf !== null
      ? reliability.mtbf.toFixed(1) + "日*\n"
      : "算出不可（エラーなし）*\n";
  text +=
    "    " +
    CONFIG.RELIABILITY_DAYS +
    "日間のエラー回数: " +
    reliability.errorCount +
    "件\n";
  if (reliability.recentErrors.length > 0) {
    text +=
      "    直近エラー: " +
      reliability.recentErrors
        .map(function (e) {
          return e.date;
        })
        .join(", ") +
      "\n";
  }
  text += "\n";
  text +=
    aIcon +
    " *A 可用性: " +
    (availability.rate * 100).toFixed(1) +
    "%*  (目標: " +
    CONFIG.TARGET.AVAILABILITY * 100 +
    "%)\n";
  text +=
    "    MTTR合計: " +
    availability.sumMttrHours.toFixed(1) +
    "H / " +
    CONFIG.TOTAL_HOURS +
    "H  (対象: " +
    availability.count +
    "件)\n\n";
  text += sIcon + " *S 保守性（MTTR）: ";
  text +=
    serviceability.avg !== null
      ? "平均 " +
        serviceability.avg.toFixed(1) +
        "H / 中央値 " +
        serviceability.median.toFixed(1) +
        "H*"
      : "データなし*";
  text += "  (目標: " + CONFIG.TARGET.SERVICEABILITY_HOURS + "H以内)\n";
  text += "    対象: " + serviceability.count + "件\n\n";
  text += "──────────────────────────────\n";
  text += ":pushpin: *今日のインシデント (" + todayIncidents.length + "件)*\n";
  if (todayIncidents.length === 0) {
    text += "    インシデントなし :tada:\n";
  } else {
    for (var k = 0; k < todayIncidents.length; k++) {
      text +=
        "    ・" +
        todayIncidents[k].name +
        " [" +
        todayIncidents[k].section +
        "]\n";
    }
  }
  return { text: text };
}

// ============================================================
// Slack投稿・セットアップ
// ============================================================

function postToSlack_(message) {
  var webhookUrl =
    PropertiesService.getScriptProperties().getProperty("SLACK_WEBHOOK_URL");
  if (!webhookUrl)
    throw new Error(
      "SLACK_WEBHOOK_URL が Script Properties に設定されていません"
    );
  UrlFetchApp.fetch(webhookUrl, {
    method: "post",
    contentType: "application/json",
    payload: JSON.stringify(message),
    muteHttpExceptions: true
  });
}

function setupDirect() {
  PropertiesService.getScriptProperties().setProperties({
    ASANA_TOKEN: "YOUR_ASANA_PERSONAL_ACCESS_TOKEN_HERE",
    SLACK_WEBHOOK_URL: "YOUR_SLACK_WEBHOOK_URL_HERE"
  });
  Logger.log("Script Properties を設定しました");
}
```
