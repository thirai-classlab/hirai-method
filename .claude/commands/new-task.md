---
description: 承認済 draft からタスクファイルを生成し、list.md に行を追加する。設計→承認→タスク化フローの最終ステップ。
---

# /new-task — 新規タスクファイル作成

`docs/draft/<slug>.md` の承認済設計から `docs/tasks/task-<id>-<slug>.md` を起こし、`docs/tasks/list.md` に新規行を追加する。

## 前提

**設計→承認→タスク追加フロー**（rules/development-process.md）を厳守:
1. `docs/draft/<slug>.md` を `_DRAFT_TEMPLATE.md` から起こす
2. user に承認を得る
3. **このコマンド**で task ファイルを生成 + list.md 行追加

設計が無い状態でこのコマンドは使わない（hook が block する）。

## 使い方

```
/new-task <id> <slug>                              # 既定: phase 推定 / 依存自動解析
/new-task <id> <slug> --phase "Phase 11"           # phase 明示
/new-task <id> <slug> --depends "#33,#38"          # 依存明示
/new-task <id> <slug> --draft docs/draft/foo.md    # 設計 draft 明示指定
/new-task <id> <slug> --no-draft                   # 設計なしで作成（hot fix 等の例外、要 user 承認）
```

## 引数

- `<id>` — タスク番号（連番、または "11.3a" 形式の sub-id 可）
- `<slug>` — kebab-case の短縮名（例: `link-card-componentize`）

## 動作

### Phase 1: 前提チェック

1. `docs/draft/<slug>.md` の存在 + ステータスが「承認済」か確認
2. 既存 `docs/tasks/task-<id>-*.md` が無いことを確認（衝突回避）
3. `docs/tasks/list.md` 既存 📝 行 (**同 ID かつ 同 slug の AND 一致**、ID 単独 / slug 単独 grep 禁止) を検出:
   - **既存あり (📝 status)** → update mode (Phase 3 で 📝 → 🔲 update、新規行 append しない)
   - **不在** → append mode (Phase 3 で新規行 append、経路 A default 動作)
   - **同 ID で 📝 以外 status (🔲 / 🔄 / ✅) 既存** → **BLOCK** (重複 ID 修正案内: 別 ID を払い出すか既存 task を Edit せよ)
   - **複数マッチ (同 ID + 同 slug で 2 行以上 hit)** → **BLOCK** (list.md の行重複を user が手動修正してから再実行)

### Phase 2: テンプレ展開

1. `.claude/templates/docs/tasks/_TASK_TEMPLATE.md` をコピー
2. プレースホルダ置換:
   - `<ID>` → タスク番号
   - `<タスク名>` → draft の H1 タイトル
   - 起案日 → 今日
   - 設計起源 → draft への相対リンク

### Phase 3: list.md 📝 行 update or append

`task-management.md` §「plan-first 行先置きフロー (batch planning) — 2 経路分岐」に従って 2 mode 分岐 (Phase 1 step 3 で判定済の mode に従う):

#### update mode (経路 B、batch planning 中間状態): 既存 📝 行を 🔲 に書き換え

`list.md` に **同 ID + 同 slug の AND 一致 📝 行** が既存なら status のみ更新 (行重複なし、新規行 append しない):

旧行:
```markdown
| <id> | 📝 | <Phase> | <概要> | <依存> | [task-<id>-<slug>.md](task-<id>-<slug>.md) |
```

新行:
```markdown
| <id> | 🔲 | <Phase> | <概要> | <依存> | [task-<id>-<slug>.md](task-<id>-<slug>.md) |
```

`📝` を `🔲` に置換、他列維持。`<Phase>` / `<概要>` / `<依存>` は draft の最新情報で更新可 (batch planning 起案時点から内容が進化している場合)。

#### append mode (経路 A、単発 default): 新規行 append

`list.md` 同 ID 不在 (Phase 1 step 3 判定) なら末尾に新規行 append:

```markdown
| <id> | 🔲 | <Phase> | <概要> | <依存> | [task-<id>-<slug>.md](task-<id>-<slug>.md) |
```

`<概要>` は draft の「真因サマリ」または「目的」から 1 行抽出。

#### 実装 helper (task-34 Step 2 で実装、iter3 で parallel race 等修正)

helper script: `.claude/scripts/new-task-helper.sh` の `update_or_append_task_row()` 関数 (subshell 関数化 / kebab-word boundary 照合 / atomic-mkdir lock 内蔵)。

CLI 呼出 (経路 A / B 共通):

```bash
bash .claude/scripts/new-task-helper.sh update_or_append_task_row <id> <slug> <row_content> [<list_md>]
```

引数:
- `<id>` — タスク ID (非負整数、leading zero は `printf '%d'` で正規化、**18 桁上限** = signed 64-bit overflow 防止 / 規範 §plan-first 経路 B では ID 払い出し時 `next_id=$((${max:-0} + 1))` で 1 始まり連番のため実用上 18 桁に到達しない)
- `<slug>` — kebab-case slug (英数字 + `-` のみ)
- `<row_content>` — 完成済 list.md 行 (`| <id> | 🔲 | ... |`、**改行 `\n` / `\r` 不可** = input validation で reject、CR-only / CRLF も検出)
- `<list_md>` — optional、既定は `${HC_TASK_DIR:-docs/tasks}/list.md`

動作 (Phase 1 step 3 判定と整合):
1. id 数値正規化 + non-negative integer validation (非数値 / leading zero / 改行 row_content は exit 2 = system-level error)
2. atomic-mkdir lock 取得 (`<list_md>.lock.d`、最大 100 retries × 50ms = 5 秒、timeout で exit 2)
3. `^\| <id> \|` で同 ID 行を取得、`(^|[^a-zA-Z0-9-])<slug>([^a-zA-Z0-9-]|$)` (kebab-word boundary) で同 slug 判定
4. 同 ID + 別 slug + 📝 既存 → BLOCK 「誤連番」(exit 1)
5. 同 ID + 同 slug + 📝 以外 (🔲/🔄/✅) → BLOCK 「重複起動 / 完了済 task の上書き」(exit 1)
6. 同 ID + 同 slug + 📝 単数 → status 列のみ 🔲 へ書換 (update mode、行数増えず)
7. 同 ID + 同 slug + 📝 複数 → BLOCK 「list.md 行重複、user 手動修正必須」(exit 1)
8. 同 ID 不在 → 末尾 append (append mode、`_new_task_ensure_eol` で末尾改行担保)

exit code 仕様 (caller の error path 設計に必須):
- `0` — 成功 (update / append いずれか)
- `1` — data-level BLOCK (誤連番 / 重複起動 / 行重複)
- `2` — system-level error (引数不正 / lock timeout / mktemp 失敗 / 改行 row_content)

caller 責務 (`/new-task` command 内で本 helper を呼ぶ Bash script):
- `HC_TASK_DIR` を本 helper に伝える必要がある場合は、caller 側で `.claude/hooks/lib/config-loader.sh` を source して `HC_TASK_DIR` を export してから helper を呼ぶ
- helper 自身は `config-loader.sh` を source せず env fallback (`${HC_TASK_DIR:-docs/tasks}`) のみ実装、CLI 単独実行 (smoke test) と caller 経由実行の両用途に対応 (Design Constraints 遵守)

並列実行安全性 (task-34 iter3 で確保):
- atomic-mkdir lock により subagent 並列 `/new-task` 実行時の race condition を防止
- iter2 では 3 並列で 10/10 race 再現 → iter3 lock 実装で 0/10 race 達成
- bash-whitelist 登録: `^bash \.claude/scripts/new-task-helper\.sh( |$)` (`.claude/bash-whitelist.txt`)

### Phase 4: draft の取り扱い

- draft は `docs/draft/<slug>.md` に **残す**（設計履歴として）
- task ファイルから「設計起源」リンクで参照

### Phase 5: 承認確認 + 着手提案

```
✅ Task #<id> 起こしました。
  - docs/tasks/task-<id>-<slug>.md
  - docs/tasks/list.md に行追加 (🔲 未着手)

次の操作:
  /start-task <id>     ← 着手するなら
  /finish-task         ← この task は不要なら delete + parking-lot へ
```

## 制約

- **設計なし起こしは原則禁止**（`--no-draft` は hot fix 等で user 承認下のみ）
- **ID + slug AND 一致 📝 行が既存 → update mode** (経路 B、batch planning)、**不在 → append mode** (経路 A、単発 default)
- **同 ID + 別 slug 既存** → BLOCK (重複 ID 修正案内、別 ID 払い出し or 既存 task Edit 要)
- **同 ID + 同 slug で 📝 以外 status (🔲 / 🔄 / ✅) 既存** → BLOCK (既存 task 進行中の可能性)
- **複数マッチ (同 ID + 同 slug で 2 行以上 hit)** → BLOCK (list.md の行重複を user 手動修正必須)
- list.md と個別ファイルを **必ず同時更新**
- 規範参照: [`.claude/rules/task-management.md` §「plan-first 行先置きフロー (batch planning) — 2 経路分岐」](../rules/task-management.md#plan-first-行先置きフロー-batch-planning--2-経路分岐)

## 関連

- `/init-tasks` — テンプレ初期化
- `/start-task <id>` — 着手フロー
- `/new-draft <slug>` — 設計 draft 起こし（このコマンドの前段）
- rule: `.claude/rules/development-process.md`
