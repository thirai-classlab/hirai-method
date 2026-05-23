# Task #24: taskManageSystem Recovery — draft-flow-guard 同期 / PROJECT_ROOT 解決 / 二重 .claude 境界

> Status: **draft (要承認)** | **🔲 未着手**
> 起案: 2026-05-23
> 関連: #12 (dual-mode-portability、subdir 配置という第三 mode を追加)
> 設計起源: [taskmanagesystem-recovery.md](../draft/taskmanagesystem-recovery.md)

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

- [ ] taskManageSystem に draft-flow-guard.sh 配備 + smoke pass
- [ ] PROJECT_ROOT が `taskManageSystem` に解決される
- [ ] `docs/design/foo.md` への新規 Write が approved_dir 経由で通過
- [ ] COEXISTENCE.md で parent-child 役割明文化
- [ ] tasks.md archive 移動 + README 案内
- [ ] next-actions に汎用化案 B entry あり
