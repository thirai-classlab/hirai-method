# taskManageSystem Recovery — draft-flow-guard 同期 / PROJECT_ROOT 解決 / 二重 .claude 境界 / 派生 flow 明文化

**ステータス:** 🔲 **draft (2026-05-23 起案、user 承認待ち)**
**起点:** 2026-05-23 taskManageSystem 調査で 5 件の運用課題発覚 (draft-flow-guard 未配備 / PROJECT_ROOT が parent 解決 / 派生 flow / parent-child .claude 境界 / tasks.md 二重)
**前提:**
- `draft-flow-guard.sh` (本 session 新設、commit `6ed9337`) を install.sh --update で同期する必要あり
- taskManageSystem は git 管理下 (parent `/Users/t.hirai/タスクマネジメント/` が git root)

**関連 fixture / rule:**
- `/Users/t.hirai/タスクマネジメント/taskManageSystem/.claude/` (HIRAI ハーネス本体、本書対象)
- `/Users/t.hirai/タスクマネジメント/.claude/` (parent dir の最小 .claude、別系統)
- `/Users/t.hirai/タスクマネジメント/taskManageSystem/CLAUDE.md` (「ハーネス専用 subdir」と明示)
- `/Users/t.hirai/タスクマネジメント/taskManageSystem/tasks.md` (root 直下、14158B、3/4 古い)

---

## 1. 真因サマリ / 課題サマリ

2026-05-23 の調査で taskManageSystem に **5 件の運用課題** が判明:

- **T-1**: 本 session で hirai-method に追加した `draft-flow-guard.sh` (`6ed9337`) が taskManageSystem に **未同期**。install.sh --update で反映可能だが未実行
- **T-2**: 二重 .claude/ 構造 (parent = git root / child = ハーネス本体) のため、`draft-flow-guard.sh` 配備しても **PROJECT_ROOT が parent に解決される**。`resolve_project_root` が git rev-parse 優先 → `/Users/t.hirai/タスクマネジメント/` を返し、child の `taskManageSystem/docs/draft/` を見落とす
- **T-3**: docs/draft/ → docs/design/ という **独自承認フロー** が hirai-method 標準 (`docs/draft/` → `docs/tasks/`) と乖離。CLAUDE.md には明記あるが config 化されておらず、tooling が認識できない
- **T-4**: parent `/Users/t.hirai/タスクマネジメント/.claude/` と child `taskManageSystem/.claude/` の境界 / 役割分担が CLAUDE.md 内のみに記載、`/harness-audit` で drift 検出不可
- **T-5**: project root に `tasks.md` (14158B、3/4 古い) と `docs/tasks/list.md` の **二重 task 管理**

**真因**: taskManageSystem は「ハーネス本体を subdir に分離」という意図的設計を取っているが、ハーネス本体が「project root = git root = `.claude` 配置 dir」を暗黙の前提にしている (PROJECT_ROOT 解決 / docs/ path 等)。この設計と前提の不整合が複数 hook で表面化。

**副次**: 本問題は他の monorepo / subdir 配置 project でも同種の問題を起こす可能性あり (一般化価値)。

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | taskManageSystem を git root に昇格 (移動) | 3.0 | hirai-method 前提に完全整合 | 既存 git 履歴 / branch / PR が壊れる、reject |
| **B** | hirai-method の hook 群を「subdir 配置対応」に汎用化 (PROJECT_ROOT 解決を `.claude` 同居 dir 優先に変更) | 2.0 | 全 hook が subdir 配置にも対応、他 project 横展開可 | 既存 project の動作変化 risk |
| **C ハイブリッド** | env override (`HC_PROJECT_ROOT=...`) で taskManageSystem 固有に解決 + 汎用化は将来別 task | 0.8 | 即対処可能、副作用なし | 各 subdir project で env 設定が必要 |

→ **C ハイブリッド** を即対処として推奨。汎用化 (B) は別 task で hirai-method 本体 issue 化 (next-actions 起こし)。

---

## 3. 採用案の詳細設計

### Wave 分割

| Wave | 内容 | 工数 | 効果 |
|:---:|:---|---:|:---|
| W1 | install.sh --update で draft-flow-guard.sh + 配線を taskManageSystem に同期 | 0.1 | T-1 解消 |
| W2 | taskManageSystem/.claude/harness-config.yml に env override 明記 + project ローカル `.envrc` 等で `HC_PROJECT_ROOT=$PWD` 自動セット | 0.3 | T-2 解消 (PROJECT_ROOT を child dir に固定) |
| W3 | harness-config.yml に新キー `docs_approved_dir: docs/design` を追加 (default: 空 = docs/ 直下)、task-rule-guard.sh / draft-flow-guard.sh が approved_dir を尊重 | 0.5 | T-3 解消 (派生 flow を config 化) |
| W4 | parent `/Users/t.hirai/タスクマネジメント/.claude/` を `taskManageSystem/.claude/COEXISTENCE.md` で明文化 (役割分担 / drift check 手順) | 0.2 | T-4 解消 |
| W5 | `tasks.md` (root 直下、古い) を `docs/archive/tasks-root-2026-05-23.md` に移動 + README で `docs/tasks/list.md` への migration を明記 | 0.2 | T-5 解消 |
| W6 | next-actions に「PROJECT_ROOT 解決の `.claude` 同居 dir 優先化 (汎用化案 B)」entry 起こし → 別 task | 0.1 | 汎用化を将来 task として残す |

合計: 1.4 session

### W2 詳細 (PROJECT_ROOT 環境変数固定)

#### スコープ
- 対象: `/Users/t.hirai/タスクマネジメント/taskManageSystem/.envrc` (新規、direnv 利用) または `.claude/harness-config.yml` コメント追記
- 対象: `taskManageSystem/CLAUDE.md` に「Claude Code 起動時に必ず `cd taskManageSystem && export HC_PROJECT_ROOT=$PWD` する」を明記

#### 変更内容
```bash
# /Users/t.hirai/タスクマネジメント/taskManageSystem/.envrc (direnv)
export HC_PROJECT_ROOT="$PWD"
```

#### テスト
- `cd taskManageSystem && bash -c 'source .claude/hooks/lib/project-root.sh; resolve_project_root'` で `/Users/t.hirai/タスクマネジメント/taskManageSystem` を返すか

### W3 詳細 (docs_approved_dir config 化)

#### 変更内容 (hirai-method 本体)
```yaml
# .claude/harness-config.yml (hirai-method 本体)
# === 設計承認後の配置 dir ===
# docs/draft/ で承認された設計を移動する dir。空なら docs/ 直下 (default)。
# 例: docs_approved_dir: docs/design  (派生 flow を使う project 向け)
docs_approved_dir: ""
```

#### draft-flow-guard.sh 改修
```bash
# approved_dir が設定されていれば、そこへの Write は通過させる
approved_dir="${HC_DOCS_APPROVED_DIR:-}"
if [ -n "$approved_dir" ]; then
  case "$file_path" in
    "$root/$approved_dir"/*) exit 0 ;;
  esac
fi
```

#### taskManageSystem 側設定
```yaml
docs_approved_dir: docs/design
```

これで `docs/design/{architecture,basic-design,...}.md` への新規 Write が pass。

### W4 詳細 (parent-child 境界明文化)

#### 新規 file
```
taskManageSystem/.claude/COEXISTENCE.md
```

#### 内容構成
- parent (`/Users/t.hirai/タスクマネジメント/.claude/`) の役割 (実装本体用、project local commands 等)
- child (`taskManageSystem/.claude/`) の役割 (HIRAI ハーネス本体)
- drift 検出手順 (`/harness-audit` で両者を区分集計)
- どちらで Claude Code を起動すべきか (実装作業 = parent、ハーネス作業 = child)

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| HC_PROJECT_ROOT が他 hook の挙動を変える | M | M | W2 完了後、全 hook smoke を taskManageSystem で実行して regression 確認 |
| docs_approved_dir 新キーが他 project (recall_poc / classlab-weekly-news / hirai-method 本体) に影響 | L | L | default 空のため後方互換、明示設定したプロジェクトのみ動作変化 |
| `tasks.md` archive で過去参照 link 切れ | M | L | git mv で履歴維持、README で新 path を明記 |

---

## 5. 移行計画

- [ ] W1: install.sh --update 実行 + draft-flow-guard.sh 配備確認
- [ ] W2: .envrc 配置 (or env 明示) + PROJECT_ROOT 解決テスト
- [ ] W3: hirai-method 本体に `docs_approved_dir` 実装 → taskManageSystem に設定
- [ ] W4: COEXISTENCE.md 起草
- [ ] W5: tasks.md archive 移動
- [ ] W6: next-actions に汎用化案 B 起こし

---

## 6. 完了条件 (DoD)

- [ ] taskManageSystem に draft-flow-guard.sh 配備済 + smoke pass
- [ ] PROJECT_ROOT が `taskManageSystem` に解決される (環境変数または `.envrc`)
- [ ] `docs/design/foo.md` への新規 Write が draft-flow-guard.sh を通過 (approved_dir 経由)
- [ ] COEXISTENCE.md で parent-child 役割が明文化
- [ ] tasks.md が archive 移動、README で新 path 案内
- [ ] next-actions に汎用化案 B (汎用 PROJECT_ROOT 解決) entry あり

---

## 7. 工数見積

合計 1.4 session (W1 0.1 + W2 0.3 + W3 0.5 + W4 0.2 + W5 0.2 + W6 0.1)。

---

## 8. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-23 | user | (待ち) |

---

## 9. 関連

- 既存設計: `docs/draft/dual-mode-portability.md` (task #12、project-level / user-level install 二択を扱った前 task) — 本 task は subdir 配置という第三 mode を追加する位置付け
- 観察証拠: 本 session 調査結果 (taskManageSystem 構造の特殊性)
- 関連タスク: 本 draft = task-24 想定
