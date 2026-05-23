# Delegation Code Enforcement — `.claude/hooks/` `.claude/skills/` `.claude/scripts/` への直接 Edit を hook で BLOCK + 規範 DRY 化

**ステータス:** 🔲 **draft (2026-05-23 起案、user 承認待ち)**
**起点:** 2026-05-23 user 指摘「なぜ基本原則に従ってサブエージェントに移譲しないのですか?」+ 本 session 中の規範違反 (本 session で hirai-method 本体の hook を 9 件メイン直接編集してしまった事実)
**前提:**
- `task-22 W1` (set policy 統一、commit `6561475`) と `task-22 W2` (jq guard 追加、commit `17c493e`) は本 session でメイン直接編集された (規範違反、ただし機能は正しいので revert はしない)
- `draft-flow-guard.sh` (commit `6ed9337`) も同じく規範違反でメイン直接編集された

**関連 fixture / rule:**
- `.claude/rules/development-process.md` (「コード実装 → Agent(general-purpose) 委譲」明記、ただし機械強制なし)
- `.claude/hooks/delegation-guard.sh` (現状は src/ tests/ scripts/ のみ block 対象、`.claude/hooks/` は対象外)
- `.claude/harness-config.yml` (`protected_paths: [src, tests, scripts]`)
- CLAUDE.md Critical Operational Lessons HIGH「サブエージェント `.claude/` 編集の staging 戦略」

---

## 1. 真因サマリ / 課題サマリ

2026-05-23 user 明示指摘により以下の構造問題が判明:

**根本原因**: `development-process.md` で「コード実装は subagent 委譲」と規範化されているが、`delegation-guard.sh` の `protected_paths` は **src/ tests/ scripts/ のみ**で `.claude/hooks/` `.claude/skills/` `.claude/scripts/` は対象外。結果として **メインが `.claude/hooks/*.sh` を直接 Edit/Write しても hook が block しない**。規範と機械強制の乖離が「メインがコード実装してしまう」事故を誘発。

**副次 (context 複雑化)**: 規範文書間の重複が多い。`development-process.md` `task-management.md` `workflow.md` `modes.md` で「設計→承認→タスク追加」「メイン専任」「サブエージェント委譲」が **個別に書かれている**。AI が規範を読む際、同じ規範が複数 file に散在するため認識精度が落ち、結果的に「.claude/ 配下はメインで触れる (規範では設定編集を想定)」を **コード実装にまで誤って拡大解釈**してしまう。

**観察証拠** (本 session):
- 本 session で hirai-method 本体の hook を 9 件メイン直接編集 (`6ed9337` draft-flow-guard 新設、`6561475` set policy 4 件、`17c493e` jq guard 5 件)
- いずれも `.claude/hooks/*.sh` 配下で、本来は subagent 委譲 + staging 戦略 で実装すべきだった
- user 指摘されるまでメインは違反を自己検知できなかった

---

## 2. 解決アプローチ比較

| 案 | 内容 | 工数 | メリット | デメリット |
|:---:|:---|---:|:---|:---|
| **A** | `delegation-guard.sh` の protected_paths に `.claude/hooks` `.claude/skills` `.claude/scripts` を追加 | 0.5 | 既存 hook 拡張、SSoT 整合性高 | 過剰検知リスク (.claude 配下の他 file 誤検知) |
| **B** | 新 hook `delegation-code-guard.sh` を分離、code パターン (`.sh` `.py` `.mjs` `.ts` `.js`) のみ block | 1.0 | 拡張子で精密判定、誤検知低 | hook が 1 個増える |
| **C ハイブリッド** | A + harness-config.yml に新キー `protected_paths_code` 導入、delegation-guard.sh が code パターン + 配下判定 で block | 0.8 | config 化で SSoT 維持 + 精密判定 + 後方互換 | 実装複雑度 +1 |

→ **C ハイブリッド** を推奨。harness-config.yml で project 毎に切替可能、SSoT 整合性 + 精密判定 + 既存 hook 拡張で hook 数を増やさない。

---

## 3. 採用案の詳細設計

### Wave 分割

| Wave | 内容 | 工数 |
|:---:|:---|---:|
| W1 | `harness-config.yml` に新キー `protected_paths_code: [.claude/hooks, .claude/skills, .claude/scripts]` 追加 (default)。code 拡張子 list `code_file_extensions: [sh, py, mjs, ts, js, tsx, jsx, rb, go, rs]` も追加 | 0.2 |
| W2 | `delegation-guard.sh` 拡張: tool=Edit/Write 時、file_path が `protected_paths_code` 配下 **かつ** `code_file_extensions` のいずれかに合致するなら block (subagent 委譲を強制) | 0.5 |
| W3 | `delegation-guard-code-smoke.sh` 新設 — 5-7 ケース (`.claude/hooks/foo.sh` メイン block / subagent pass / `.claude/rules/foo.md` メイン pass / `.claude/harness-config.yml` メイン pass 等) | 0.5 |
| W4 | 規範 DRY 化 (context 複雑化対処): `development-process.md` / `task-management.md` / `workflow.md` / `modes.md` で重複する「サブエージェント委譲」「メイン専任」「設計→承認→タスク追加」3 規範を **1 箇所に集約** + 他 file は 1 行 link で参照 | 0.7 |
| W5 | CLAUDE.md / development-process.md に「コード実装 = subagent 委譲 (delegation-code-guard hook が機械強制)」と明示、Critical Operational Lessons に本 session の違反事例を 1 件追加 | 0.3 |
| W6 | recall_poc / taskManageSystem / classlab-weekly-news に install.sh --update で反映 | 0.2 |

合計: 2.4 session

### W1 詳細 (config 拡張)

#### 変更内容
```yaml
# .claude/harness-config.yml に追加
# === コード実装の保護パス (subagent 委譲を強制) ===
# delegation-guard.sh が tool=Edit/Write 時、file_path が
# protected_paths_code 配下 かつ code_file_extensions のいずれかなら BLOCK。
# subagent 経由 (Agent tool) は通過 (既存 agent-marker による判定と同じ)。
#
# 規範文書 (.md) や設定 file (.yml/.json/.txt) は対象外で、メインで編集可。
protected_paths_code: [.claude/hooks, .claude/skills, .claude/scripts]
code_file_extensions: [sh, py, mjs, ts, js, tsx, jsx, rb, go, rs, java, kt, swift, php, cpp, c, h]
```

### W2 詳細 (delegation-guard.sh 拡張)

#### 変更内容 (擬似コード)
```bash
# delegation-guard.sh の Edit|Write branch に追加
if [ "$tool" = "Edit" ] || [ "$tool" = "Write" ]; then
  if [ "$is_subagent" = "false" ]; then
    # 既存 protected_paths (src/ tests/ scripts/) block 判定
    # ↓ ここに追加
    for code_path in $HC_PROTECTED_PATHS_CODE; do
      case "$file_path" in
        */${code_path}/*)
          ext="${file_path##*.}"
          for valid_ext in $HC_CODE_FILE_EXTENSIONS; do
            if [ "$ext" = "$valid_ext" ]; then
              # block: コード実装は subagent 委譲
              exit 2  # with reason: "コード実装は Agent tool で subagent 委譲してください"
            fi
          done
          ;;
      esac
    done
  fi
fi
```

### W4 詳細 (規範 DRY 化)

#### 重複規範の集約案

| 規範 | 現状の散在 | DRY 化後 SSoT |
|---|---|---|
| サブエージェント委譲 (Edit/Write/Bash) | development-process.md §3, modes.md, workflow.md §3 | **development-process.md §3** に統合、他は 1 行 link |
| メイン専任 (タスク管理) | development-process.md §「タスク管理」, task-management.md §1, workflow.md §「メイン専任」 | **task-management.md §1** に統合、他は 1 行 link |
| 設計→承認→タスク追加 | development-process.md §「設計→承認→タスク追加フロー」, task-management.md §2 | **task-management.md §2** に統合、他は 1 行 link |
| Loop モード遵守事項 | modes.md §「Loop モード」, workflow.md §「Loop モード自律規律」 | **modes.md** に統合、workflow.md は参照のみ |

#### 期待効果
- 規範総 LOC 削減 (重複セクション 600+ 行 → ~200 行)
- AI が規範を読む際の context 注入量 ~3 KB → ~1 KB
- 規範改訂時の drift リスク解消 (1 箇所修正で全 file 反映)

---

## 4. リスクと緩和

| リスク | 確率 | 影響 | 緩和 |
|---|:---:|:---:|---|
| W2 block が過剰検知し、メインの正当な編集 (harness-config.yml / mode.yml 等) を巻き込む | M | M | W3 smoke で正当ケース 5+ 件を必ず PASS 検証、`HC_CODE_FILE_EXTENSIONS` に該当しない拡張子は通過 |
| W4 規範統合で既存 link が切れる | M | L | 全 link を grep で抽出、統合後に redirect 注記 |
| 既存メイン直接編集の習慣が残り、block で作業が止まる | H | M | bypass env `ECC_ALLOW_MAIN_CODE_EDIT=1` を実装 (緊急時のみ、bypass.log 記録) |
| subagent 委譲時の staging 戦略漏れで .claude/ permission denied | M | M | W5 で CLAUDE.md Critical Lessons に staging 強制を再注意喚起 |

---

## 5. 移行計画

- [ ] W1: harness-config.yml に新キー追加
- [ ] W2: delegation-guard.sh 拡張 (subagent 経由で実装、本 task 自身が即 dogfooding)
- [ ] W3: smoke 5-7 ケース PASS
- [ ] W4: 規範 4 file の重複セクション統合 (subagent 経由)
- [ ] W5: CLAUDE.md / development-process.md に明示
- [ ] W6: 3 リポに install.sh --update 反映

---

## 6. 完了条件 (DoD)

- [ ] メインで `.claude/hooks/foo.sh` への直接 Write が block される (実測)
- [ ] subagent 経由で同じ Write が pass する (実測)
- [ ] `.claude/rules/foo.md` `.claude/harness-config.yml` `.claude/mode.yml` 等のメイン編集は引き続き pass
- [ ] 規範 4 file の重複セクションが SSoT 1 箇所に集約
- [ ] CLAUDE.md Critical Operational Lessons に本 session 違反事例 1 件追加
- [ ] 既存 smoke 全件 regression 0

---

## 7. 工数見積

合計 2.4 session (W1 0.2 + W2 0.5 + W3 0.5 + W4 0.7 + W5 0.3 + W6 0.2)。

---

## 8. 承認履歴

| 日付 | 承認者 | 結果 |
|---|---|---|
| 2026-05-23 | user | (待ち、ただし起源指摘自体は user 明示) |

---

## 9. 関連

- 既存設計: `docs/draft/system-reminder-attention-fix.md` (task-21、context 複雑化の attention dilution 側面と相補)
- 既存設計: `docs/draft/hook-reliability-uplift.md` (task-22、本 task 完了後は subagent 委譲で実装)
- 観察証拠: 本 session 中の commit `6ed9337` `6561475` `17c493e` (全 3 件メイン直接編集で規範違反)
- 関連タスク: 本 draft = task-26 想定
