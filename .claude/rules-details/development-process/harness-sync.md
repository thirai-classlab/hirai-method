> Layer A: [`development-process.md`](../../rules/development-process.md) §harness 取込チェックリスト (proactive sync、consuming repo 必須) | 本 file は **明示 Read のみ** (context 自動注入 OFF)

# harness 取込 詳細 (Layer B)

## CI 自動化 (将来 opt-in、parking-lot)

CI (GitHub Actions 等) で hirai-method SSoT と `.claude/` の diff を定期検出 → PR / issue 自動起票する自動化案 (案 B) は **consuming repo 側の opt-in** で将来導入。詳細は `docs/tasks/parking-lot.md` の 🔍 entry「CI 自動 .claude diff 検出 (G2 案 B)」を参照。

## 取込手順の補足

- **hirai-method 最新化**: consuming repo 側に直接 push する場合は不要
- **`bash install.sh --update <consuming repo absolute path>`** は cross-repo write のため **user manual (terminal) 実行のみ可能** (詳細: §「cross-repo write 例外」)
- **分離 commit** (task-58 G1) で `chore: sync .claude/ from hirai-method <YYYY-MM-DD>` 形式で記録、`install.sh --update --commit` flag で自動 commit 可能

## 起源

- 2026-05-28 task-59 (G2: harness-sync-proactive-workflow)、設計 draft: [`docs/draft/harness-sync-proactive-workflow.md`](../../docs/draft/harness-sync-proactive-workflow.md) §3 採用案 C ハイブリッド
- 前提:
  - task-56 = F (stale-harness-detect、reactive 検出 + WARN 案内、commit `f5149fb`)
  - task-58 = G1 (未 commit drift、`install.sh --update --commit` flag)
- F WARN 連携: `stale-harness-detect.sh` の WARN 文に既に「`bash install.sh --update <repo>`」案内が含まれる (commit `f5149fb`、smoke Case 2 で grep verify 済、Case 10 で取込手順 strengthen)
