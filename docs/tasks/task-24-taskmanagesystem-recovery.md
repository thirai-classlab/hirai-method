# Task #24: taskManageSystem Recovery — draft-flow-guard 同期 / PROJECT_ROOT 解決 / 二重 .claude 境界

> Status: **✅ 完了** (2026-05-27、W1-W6 全完了。W5 cross-repo は task-42 で agent 着手可能化、taskManageSystem local commit `ad4b99d` 実行 [push は user 承認待ち])
> 起案: 2026-05-23
> 関連: #12 (dual-mode-portability、subdir 配置という第三 mode を追加)
> 設計起源: [taskmanagesystem-recovery.md](../draft/taskmanagesystem-recovery.md)

## 進捗ログ (2026-05-23)

### W3 完遂 (commit `7df49d7`、subagent a08c00c50b8e594bf confidence 0.95)

**hirai-method 本体 docs_approved_dir 実装**:
- `.claude/harness-config.yml`: `docs_approved_dir` key 追加 (+20 行、default 空文字、CSV 複数値対応 e.g. `design,research`、詳細コメント込み)
- `.claude/hooks/lib/config-loader.sh`: `HC_DOCS_APPROVED_DIR` を `_HC_KNOWN_KEYS` に追加 + default 値 + env export (+5/-2 行)
- `.claude/hooks/draft-flow-guard.sh`: `approved_dir_raw` 読み出し + 深さ 2 (`docs/<approved_dir>/foo.md`) の CSV 複数値判定 logic + bypass help message 追加 (+40/-3 行)
- 新 `.claude/tests/draft-flow-guard-approved-dir-smoke.sh` 7 cases PASS + 既存 `draft-flow-guard-smoke.sh` 5/5 PASS (regression 0)

**設計判断**:
- 深さ仕様: `docs/<approved_dir>/foo.md` (深さ 2) のみ approved、深さ 3 以上 (`docs/<approved_dir>/sub/nested.md`) は既存 hook の素通り (BLOCK でも approved でもない) 挙動を維持
- CSV 複数値: scope 内、`IFS=',' read -r -a` で split + trim + 各 entry 照合
- backward compat 100%: `docs_approved_dir` default 空文字、空時は `if [ -n "$approved_dir_raw" ]` ガードで素通り、既存挙動と完全一致

**cross-repo blocker (W3 範囲外、user manual 必要)**:
- taskManageSystem 側 `.claude/harness-config.yml` に `docs_approved_dir: design` (または `docs/design` の `docs/` 削った値) 設定 → 別途 user manual
- `bash install.sh --update /Users/t.hirai/タスクマネジメント/taskManageSystem` で本 W3 の hook + config-loader 同期 → 別途 user manual

> **cross-repo 注意**: 上記 cross-repo blocker は task-31 で規範化済 (commit `f90d194`)。Claude Code sandbox + `delegation-guard.sh` 二重制約で agent 経路完全 denied、`bash install.sh --update <target>` は **user manual (terminal) 実行のみ可能** (subagent foreground / background / `isolation: "worktree"` いずれも回避不可)。詳細は `.claude/rules/development-process.md` §「cross-repo write 例外」参照。

### W5 完遂 (2026-05-27、subagent ae3e1c707ed155c63 confidence 0.9、cross-repo agent 着手)

cross-repo 制約は task-42 (2026-05-26) で superseded (agent 直接 write 実証済) のため、W5 を user manual ではなく **agent cross-repo 自律実行**:
- **tasks.md archive 移動**: `taskManageSystem/tasks.md` → `taskManageSystem/docs/archive/tasks-root-2026-05-23.md` (git mv 100% rename、履歴保持、14158 bytes)
- **docs_approved_dir 設定**: `.claude/harness-config.yml` に `docs_approved_dir: "design"` (yml contract が「`docs/` 配下 dir セグメント、slash なし」のため `"docs/design"` ではなく `"design"`。`docs/design/foo.md` が approved_dir 経由で PASS する正しい値)
- **README 案内**: `docs/README.md` Archive section に「root tasks.md は docs/archive/ に移動、現行 task 管理は docs/tasks/list.md」を追記
- **local commit**: taskManageSystem (git root `/Users/t.hirai/タスクマネジメント`、branch `fix/critical-gaps`) で `ad4b99d`。**push は user 承認待ち** (modes.md 遵守事項 8 第三者リポ)
- **smoke**: `draft-flow-guard-approved-dir-smoke.sh` 7/7 PASS (Case 2 `docs/design/foo.md` PASS + Case 3 `docs/foo.md` BLOCK regression 含む)

### user follow-up (push)

- taskManageSystem の local commit `ad4b99d` を user が push (別 repo push は自律禁止)

## 背景・目的

2026-05-23 の taskManageSystem 調査で 5 件の運用課題が判明:
- draft-flow-guard.sh 未配備 (本 session 新設 hook が未同期)
- 二重 .claude/ 構造で PROJECT_ROOT が parent に解決される → child docs/ を見落とす
- docs/draft → docs/design という独自承認フローが hirai-method 標準と乖離
- parent .claude と child .claude の境界が CLAUDE.md 内のみ
- root 直下 tasks.md と docs/tasks/list.md の二重 task 管理

本 task で subdir 配置という特殊構造に対応する。

## 仕様 (要決定 → 決定済)

### Q1: PROJECT_ROOT 解決方針

→ **C ハイブリッド**: env override (`HC_PROJECT_ROOT=$PWD`) で taskManageSystem 固有に解決。汎用化 (B 案、`.claude` 同居 dir 優先) は別 task で hirai-method 本体 issue 化 (本 task W6 で next-actions 起こし)。

### Q2: 独自承認フロー (docs/design) の扱い

→ **harness-config.yml に新キー `docs_approved_dir` 追加**。default 空 (= docs/ 直下)、taskManageSystem では `docs_approved_dir: docs/design`。draft-flow-guard.sh が approved_dir を尊重。

### Q3: tasks.md の扱い

→ **archive 移動** (`docs/archive/tasks-root-2026-05-23.md`)、README で `docs/tasks/list.md` へ migration 案内。

## 設計

詳細は [taskmanagesystem-recovery.md](../draft/taskmanagesystem-recovery.md) §3 参照。

### Wave 構成

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| W1 | install.sh --update で draft-flow-guard.sh 同期 | 0.1 |
| W2 | .envrc 配置 + HC_PROJECT_ROOT 固定 | 0.3 |
| W3 | hirai-method 本体に docs_approved_dir 実装 + taskManageSystem に設定 | 0.5 |
| W4 | parent/child COEXISTENCE.md 起草 | 0.2 |
| W5 | tasks.md archive 移動 | 0.2 |
| W6 | next-actions に汎用化案 B (PROJECT_ROOT .claude 同居 dir 優先化) 起こし | 0.1 |

合計 1.4 session。

## TDD 戦略

### RED

- `taskManageSystem/.claude/tests/project-root-subdir-smoke.sh` 新設 — HC_PROJECT_ROOT 設定下で resolve_project_root が child dir を返すか
- `.claude/tests/draft-flow-guard-approved-dir-smoke.sh` — `docs_approved_dir` 設定下で approved_dir 経由 Write が pass するか

### GREEN

- hirai-method 本体 draft-flow-guard.sh に approved_dir 対応追加
- taskManageSystem 側 .envrc + harness-config.yml 設定

## 派生 task / 次アクション候補

- 汎用化案 B (PROJECT_ROOT 解決を `.claude` 同居 dir 優先) を別 task で。これが完了すれば本 task の W2 (env override) は不要になる
- monorepo 全般での subdir 配置パターンを INVENTORY.md / PORTABILITY.md に追記

## 完了条件

- [x] taskManageSystem に draft-flow-guard.sh 配備 + smoke pass (W1、smoke 7/7 PASS で W5 再確認)
- [x] PROJECT_ROOT が `taskManageSystem` に解決される (W2 `.envrc` + HC_PROJECT_ROOT)
- [x] `docs/design/foo.md` への新規 Write が approved_dir 経由で通過 (W3 実装 + W5 で `docs_approved_dir: "design"` 設定、live guard PASS 確認)
- [x] COEXISTENCE.md で parent-child 役割明文化 (W4)
- [x] tasks.md archive 移動 + README 案内 (W5、commit `ad4b99d`)
- [x] next-actions に汎用化案 B entry あり (W6)
