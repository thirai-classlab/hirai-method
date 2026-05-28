# Parking Lot（今後検討タスク）

> 「設計済みだが着手不可」「将来条件付きで実施」のタスクを管理する台帳。
> アクティブな着手可能タスクは [`list.md`](list.md) 側で管理。
> 再検討トリガーが成立したら本ファイルから `list.md` に移行して着手する。

## 凡例

| アイコン | ステータス | 意味 |
|:---:|:---|:---|
| 🧊 | 保留 | 外部条件待ち（プラットフォーム制約、データ蓄積待ち等） |
| 🔍 | 再検討予定 | 定期レビュー対象、トリガー成立なしでも見直しする |
| ❌ | 不採用 | 検討の結果、永続的に不採用（履歴として残す） |

## エントリフォーマット

各エントリは以下の項目を必須とする（**設計なしの追加は禁止**、`docs/draft/` または既存設計へのリンクが必要）。

- **起案日** — 保留に入った日（YYYY-MM-DD）
- **保留日** — `list.md` から本ファイルへ移した日
- **保留理由** — なぜ今着手できないか（外部条件・データ不足・優先度）
- **設計書** — 既存設計へのリンク（新規設計の場合は `docs/draft/` → 承認後ここにリンク）
- **実装状態** — コード・テスト・DB 変更がどこまで進んでいるか
- **再検討トリガー** — どういう条件が揃えば `list.md` に移せるか（`いずれか / すべて` を明示）
- **代替現状** — 保留中のワークアラウンド or 影響度

## ステータス遷移

```
作成
  ↓
🧊 保留 ─── トリガー成立 ──→ list.md（🔄 進行中）へ
  ↓               ↑
  ├─ 四半期レビュー─┘
  ↓
🔍 再検討予定 ─── 不採用 ──→ ❌ 不採用（履歴）
```

---

## タスク一覧

<!-- 例:

### 🧊 N.M <短い名前>

**起案:** YYYY-MM-DD（経緯）
**保留日:** YYYY-MM-DD（list.md → ここに移した日）

**保留理由:**
<外部条件・依存・優先度の話を 2-3 行>

**設計書:**
- [<設計書名>](../<path>) — 設計内容
- [<関連 PDCA>](../pdca/<path>) — 関連実証

**実装状態:**
- どこまで実装済か
- 保持しているコード/migration/test の場所
- 「温存する／削除する」の方針

**再検討トリガー（いずれか成立時に `list.md` へ移行）:**
1. <条件1>
2. <条件2>

**代替現状:**
<今のワークアラウンド・影響度>

---

-->

### 🔍 P2 CI 自動 .claude diff 検出 (G2 案 B、consuming repo opt-in)

**起案:** 2026-05-28 (task-59 G2 設計 §2 案 B「CI で SSoT との `.claude` diff 定期検出 → PR / issue 自動起票」を採用案 C ハイブリッドの将来オプションとして保留採用)
**保留日:** 2026-05-28 (task-59 完了と同時に parking-lot へ登録)

**保留理由:**
task-59 で C ハイブリッド (規範チェックリスト + F WARN 連携) を採用済 → 採用 4 リポ全件で運用開始。案 B (CI 自動化) は工数 2.5 と高く、consuming repo ごとに GitHub Actions 設定が必要で **cross-repo は user manual** で対応不可。現状の reactive WARN (F) + proactive 規範 (G2 case C) で「取込忘れ」事故は構造的に抑止できているため、CI 自動化は consuming repo 側で「週次定期 sync が回らない」「team 規模で取込担当が分散して honor system が崩れる」等の trigger が成立した時点で opt-in 導入する。

**設計書:**
- [`docs/draft/harness-sync-proactive-workflow.md`](../draft/harness-sync-proactive-workflow.md) §2 案 B — CI 自動 diff 検出 (工数 2.5、メリット: 自動・確実 / デメリット: CI 構築 + consuming repo 個別設定、cross-repo は user manual)
- [`.claude/rules/development-process.md`](../../.claude/rules/development-process.md) §「harness 取込チェックリスト」§ CI 自動化 (将来 opt-in、parking-lot) — 採用案 C ハイブリッドの記載
- 統合分析資料: `docs/draft/harness-health-7items-analysis.md` §8/§9 (G2 起点)

**実装状態:**
- 未着手 (採用案 C ハイブリッド = 規範 + F WARN 連携で task-59 完遂、案 B は将来 opt-in 位置付け)
- 関連 task: task-56 = F (stale-harness-detect、reactive 検出) / task-58 = G1 (未 commit drift、`install.sh --update --commit` flag) / task-59 = G2 case C (規範化)
- 副産物 entry: なし (本 entry は task-59 完了時点で計画通り parking-lot 登録)

**再検討トリガー（いずれか成立時に `list.md` へ移行）:**
1. consuming repo 側で「週次定期 sync が回らない」事案が観測される (例: 同 consuming repo で F WARN が連続 4 週検出される、honor system 崩壊の signal)
2. team 規模で取込担当が分散し、誰が `install.sh --update` を実行するか不明瞭になる
3. hirai-method 側の hook / 規範更新頻度が週次以上に増加し、手動 sync の人的コストが ROI 負に転じる
4. consuming repo 数が 4 件 → 10 件以上に増加し、user manual sync の管理工数が爆発する
5. GitHub Actions / 同等 CI 経路で cross-repo diff 検出 → PR 自動起票する OSS template が登場 (実装工数が 2.5 → 0.5 に低下)

**代替現状:**
- 案 C ハイブリッド (規範チェックリスト + F WARN 連携) で「取込忘れ」の reactive 検出 + proactive 義務化を実現
- consuming repo 側 user が weekly に `bash install.sh --update <repo>` を terminal 手動実行 (運用合意)
- F WARN 検出時は表示された取込手順 (`bash install.sh --update <repo>`) を即座に user manual 実行
- 四半期 review で本 parking-lot entry の再検討トリガー 1-5 該当を user manual で確認

---

### 🔍 P1 cross-repo sandbox 緩和の future Claude Code 仕様変化追随

**起案:** 2026-05-23（task-31 設計 Q1 案 B「自動代替策探索」を案 C ハイブリッドの一部として保留採用）
**保留日:** 2026-05-23（task-31 起票と同時に parking-lot へ登録）

**保留理由:**
cross-repo write (本 repo `hirai-method` → 外部 repo `recall_poc` / `taskManageSystem` / `classlab-weekly-news` 等) の agent 経路 deny は **Claude Code system-level sandbox** の制約。`dangerouslyDisableSandbox: true` 付き Bash / subagent foreground / background / `isolation: "worktree"` いずれも回避不可 (task-24 W1 subagent a174bcef696b54860 confidence 0.85 で実証)。`ECC_*_OVERRIDE` / `HC_*_ENABLED=false` 等 harness-level bypass env は system-level 制約に効かないため、現時点では `bash install.sh --update <target>` を **user manual (terminal) 実行のみ可能** とする運用が唯一解。将来 Anthropic 側 Claude Code が cross-repo Write を opt-in で許可する future feature を提供すれば自動化が可能になるが、現状その仕様変化は未提供のため保留。

**設計書:**
- [`docs/draft/cross-repo-write-user-manual-normative.md`](../draft/cross-repo-write-user-manual-normative.md) §仕様 Q1 案 B — 自動代替策探索 (subprocess / `child_process.spawn` / 外部 helper) は sandbox 制約 system-level のため実現性ほぼなし、ROI 低い
- [`.claude/rules/development-process.md`](../../.claude/rules/development-process.md) §「cross-repo write 例外」(task-31 で規範化、commit `f90d194`)
- Serena memory: `feedback_cross_repo_write_sandbox_block.md` (2026-05-23、事実根拠)

**実装状態:**
- 未着手 (案 B の自動代替策は実現性低と評価済、コード / migration / test なし)
- 案 A (規範化のみ) + 案 C (規範化 + parking-lot 将来追随窓口) は task-31 で実装済 (Phase 1-5)
- 副産物 entry: `docs/tasks/next-actions.md` entry #17 (2026-05-23、🟡)
- 関連 audit: `.claude/.workflow-state/bypass.log` (cross-repo agent 試行 block 痕跡)、`harness-audit.py` `bypass_log_summary` (再発検知)

**再検討トリガー（いずれか成立時に `list.md` へ移行）:**
1. Claude Code release notes で「cross-repo Write を opt-in 許可する」future feature が announce される
2. Anthropic 側 sandbox 仕様 (例: `dangerouslyAllowCrossRepoWrite: true` 等) が docs / changelog に明示追加される
3. `dangerouslyDisableSandbox` が cross-repo path に対しても有効になる挙動変化を実測検出 (本 repo の smoke で確認可能)
4. ハーネス側で subprocess / 外部 helper 経由の自動化が ROI 正と判明 (cross-repo 反映頻度 ≥ 月 5 回 等)

**代替現状:**
- `bash install.sh --update <target>` を user manual (terminal) で実行 (運用上の唯一解)
- task draft / task file の Phase 計画段で「Phase N (cross-repo): user manual 案内」を必ず明記 (`_TASK_TEMPLATE.md` の cross-repo hint で強制)
- 副産物 entry 起票時も「(c) user manual 経路で対応」を推奨処理に明記
- 四半期 review で Claude Code release notes を user manual で監視 (本 entry の再検討トリガー 1-3 該当時)

---

## 定期レビュー

🔍 のエントリは **四半期ごと** に見直す:
- トリガー再評価
- 不採用に降格 → ❌ へ
- 着手可能に昇格 → `list.md` へ

❌ のエントリは履歴として残し、過去の意思決定を辿れるようにする。
