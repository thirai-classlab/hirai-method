<!--
approval_required: true
approved_at: 2026-06-06
approved_by: user
retroactive: false
-->

# プロジェクトルール保護 (project-rules/ companion + @import)

**ステータス:** 🔲 **draft（2026-06-06 起案、user 承認済 = 詳細仕様指定 + 実現性確定）**
**起点:** user 依頼 (2026-06-06)「ハーネスルール編集についてのルール作成。7 rule + detail は触らず、各 rule から @import で project-rules/ companion を呼び、update/install では project-rules はなければ作成・あっても更新しない」。自動アップデート (【3】) の前提機能 (【1】)
**前提:**
- 実現性確定 (claude-code-guide conf 0.97、出典 code.claude.com/docs/en/memory.md): `.claude/rules/*.md` 内の `@path` import は **展開される** (recursive depth 4)、相対 path は import 元 file 基準、`.claude/rules/` 外 (project-rules/) は auto-discover されず @import が唯一の読込経路

**関連 rule:** CLAUDE.md Design Constraints (harness-config.yml SSoT vs local.yml 保護モデルと同型)

---

## 1. 課題サマリ

harness 7 rule (`.claude/rules/{development-process,git-workflow,modes,self-improvement,task-management,why-x5-output,workflow}.md`) + `rules-details/` は harness 所有で **update の rsync で上書き**される。consuming repo が rule を project 固有に拡張/override すると update で消失する。

**解決**: harness rule (上書き追従) と project rule (永続保護) を分離。各 harness rule から `@../project-rules/<name>.md` を import し、project companion は update 免除。

---

## 2. 解決アプローチ (採用、user 指定設計)

harness-config.yml (SSoT、上書き) / harness-config.local.yml (project override、保護) と**同型の保護モデル**を rule にも適用:

| layer | 配置 | update 挙動 | 用途 |
|---|---|---|---|
| harness rule | `.claude/rules/<name>.md` | 上書き (harness 所有) | 共通規範 + 末尾に `@../project-rules/<name>.md` import 1 行 |
| project rule | `.claude/project-rules/<name>.md` | **なければ作成・あれば更新しない** (保護) | project 固有の拡張/override |

→ harness 共通ルールは update 追従、project 固有は永続保護を両立。新規ルール領域は project-rules/ に file 追加で対応可。

---

## 3. 採用案の詳細設計

### 3.1 @import 配線 (7 harness rule、一度だけ)
各 `.claude/rules/<name>.md` の**末尾**に追記 (project rule が harness rule の後 = 拡張/override order):
```markdown

---
> **project 固有の追補・override は `.claude/project-rules/<name>.md` に書く** (本 file は harness 所有、`install.sh --update` で上書きされる。project 固有編集は下記 import 先へ)。
@../project-rules/<name>.md
```
- 対象 7 file。`rules-details/` は触らない (user 指定)
- 相対 path `../project-rules/<name>.md` = `.claude/rules/` から `.claude/project-rules/<name>.md` (実現性確定済)

### 3.2 project-rules/ companion 作成 (7 file、空テンプレ)
`.claude/project-rules/<name>.md` を 7 個作成。各 file の中身 (header のみ、本体空):
```markdown
# project 固有ルール: <name> (CommonRules / harness rule への追補)

> 本 file は **project 所有** (`install.sh --update` で上書きされない、なければ作成のみ)。
> `.claude/rules/<name>.md` (harness 所有・update 上書き) から `@import` され、harness rule の**後に**結合 load される。
> harness 共通 rule を変えたい時は本 file に override/追補を書く (7 harness rule 本体は触らない)。
> 新規ルール領域は `.claude/project-rules/` に新 file 追加 + 必要なら CLAUDE.md / 既存 rule から @import。

<!-- ここに project 固有のルールを記述。空のままでも可 (harness rule のみ有効)。 -->
```

### 3.3 install.sh 保護
- **create-if-absent**: install (default/update/force/overwrite-all) で `.claude/project-rules/<name>.md` がなければ空テンプレを配置、**あれば skip** (docs/tasks templates と同じ冪等ロジック)
- **rsync exclude**: `RSYNC_EXCLUDES` に `--exclude=project-rules/` 追加 (update で project 編集を上書きしない)。※ harness 自身の repo では project-rules/ は空テンプレを tracked (consuming repo の参照雛形)

### 3.4 ガバナンスルール文書化
- README に「§ project-rules 保護」セクション追加 (harness rule vs project rule の分離、@import 結合、編集先の指針)
- 各 harness rule 末尾の pointer (3.1) + project-rules header (3.2) で「7 file を触らず project-rules/ を編集」を明示

### Step 計画 (採用 6 条準拠)

| Step | Status | 作業概要 | 依存 |
|:---:|:---:|:---|:---|
| 1 | 🔲 | 7 harness rule 末尾に @import + pointer 追記 / `.claude/project-rules/<name>.md` 7 file 空テンプレ作成 | — |
| 2 | 🔲 | install.sh: project-rules create-if-absent (skip-if-exists) + RSYNC_EXCLUDES に project-rules/ 追加 + summary 案内 / README §project-rules 追記 | 1 |
| 3 | 🔲 | (テスト設計レビュー) reviewer 動的選定 | 2 |
| 4 | 🔲 | (テスト合格) smoke: 7 rule に @import 存在 / project-rules 7 file 存在 / install create-if-absent / 既存 project-rules を update で上書きしない / rsync exclude。既存 install smoke regression 0 | 3 |
| 5 | 🔲 | (リファクタリング) 3 観点 or skip | 4 |

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| @import が展開されず project rule が無効 | L | H | 実現性確定済 (公式 doc、depth 4 recursive)。smoke で @import 行存在を検証 (展開自体は Claude Code session でのみ確認可、目視) |
| update で project-rules 上書き → project 編集消失 | M | H | rsync exclude + create-if-absent の二重保護。smoke で「既存 project-rules を update で touch しない」を実測 |
| harness rule 上書きで @import 行も消える | L | M | @import 行は **harness source の 7 file に含める**ので update で再配布される (消えない) |
| recursive import depth 4 超過 | L | L | 1 hop (rule → project-rule) のみ、余裕 |

---

## 6. 完了条件（DoD）

- [ ] 7 harness rule 末尾に `@../project-rules/<name>.md` + pointer 追記
- [ ] `.claude/project-rules/<name>.md` 7 file (header 付き空テンプレ) 作成
- [ ] install.sh: project-rules create-if-absent (既存 skip) + RSYNC_EXCLUDES exclude
- [ ] smoke: @import 存在 / project-rules 存在 / create-if-absent / update 非上書き / rsync exclude (実測)
- [ ] 既存 install smoke regression 0 / README §project-rules 追記 / bash 3.2 互換

---

## 7. 工数見積
約 1.5h

---

## 8. レビューサイクル

| iter | 日付 | reviewer (起動数) | CRITICAL | HIGH | MEDIUM | LOW | 修正 commit | 状態 |
|:---:|---|---|:---:|:---:|:---:|:---:|---|---|
| 1 | — | (Task 最終 Step のテスト設計レビューで実施) | — | — | — | — | — | 未着手 |

---

## 9. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-06-06 | user | **承認** (詳細仕様指定 + @import 実現性 conf 0.97 確定) → task-82 化。【1】= 自動アップデート roadmap の前提機能 |

---

## 10. 関連
- 【2】npx 化 / 【3】自動アップデート (本 task は前提。roadmap は次 task で draft)
- `.claude/rules/*.md` (7 file) / `.claude/project-rules/` (新規) / `install.sh` / README
- 実現性調査: claude-code-guide (@import in rules、conf 0.97)
