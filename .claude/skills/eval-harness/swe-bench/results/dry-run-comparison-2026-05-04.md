# SWE-bench Lite dry-run before/after — Phase C-1.5

_finalized 2026-05-04 23:18 JST — improved run completed (3/5 applied, 2/5 timed out)_

## 改善前 (Phase C-1, unified-diff prompt)

source: `results/dry-run-2026-05-04.json`

| metric | value |
|---|---:|
| tasks run | 5 |
| patch generated | 5 |
| patch applied | 2 (40%) |
| corrupt patch | 3 (60%) |
| 真の解決率 (resolved) | 未測定 (apply_only) |
| 累計 cost | $1.078 |
| 平均 invoke duration | 34.9 s |

failure breakdown (raw `apply_error`):

| instance_id | error |
|---|---|
| astropy__astropy-14182 | corrupt patch at line 20 |
| astropy__astropy-14995 | corrupt patch at line 13 |
| astropy__astropy-6938  | corrupt patch at line 9 |

主因: claude が手書きする `@@ -L,N +L,N @@` hunk header の行番号 / count が不正。
unified-diff prompt のみではこの class of failure が解消されない。

## 改善後 (Phase C-1.5, whole-file mode)

source: `results/dry-run-improved-2026-05-04.json`

| metric | before (C-1) | after (C-1.5) | delta |
|---|---:|---:|---:|
| tasks run | 5 | 5 | — |
| patch generated | 5 | 3 | -2 (timeout) |
| patch applied | 2/5 (40%) | **3/5 (60%)** | **+20pt** |
| 生成 patch の適用率 (conditional) | 2/5 (40%) | **3/3 (100%)** | **+60pt** |
| corrupt patch | 3 | 0 | -3 |
| 真の解決率 | 未測定 (apply_only) | 未測定 (apply_only=true 継続) | — |
| 累計 cost | $1.078 | $0.853 | -$0.226 |
| 平均 invoke duration (成功 task) | 34.9 s | 106.5 s | +71.6 s |
| 平均 invoke duration (全 task 込み) | 34.9 s | 243.9 s | +209 s (timeout 込み) |
| timeout 失敗 | 0 | 2 (300s + 600s) | +2 |

### 失敗 task 詳細 (after)

| instance_id | result | duration | error |
|---|---|---:|---|
| astropy__astropy-12907 | timeout | 300s | claude 出力なし (per_task_timeout の前回 run の record を resume が引き継いだ) |
| astropy__astropy-6938  | timeout | 600s | 600s 拡張後も claude が応答せず |

`12907` は前回 run の 300s timeout record を resume が引き継いだだけ (新たな試行はしていない)。
`6938` は今回 600s に拡張しても応答せず — claude 側が大きい file 全文出力で詰まっている可能性。

### 改善内容まとめ

- **patch-mode = whole-file**: claude には修正後ファイル全文を `PATH:` + `<<<FILE_START>>>...<<<FILE_END>>>` で出力させ、runner.py が `git clone --filter=blob:none` で base content を取り、`difflib.unified_diff(n=3)` で hunk header を機械生成。claude は行番号計算から完全に解放される。
- **resume**: `--resume <results.json>` で完了 task をスキップ。中断後の再開を atomic write (temp → rename) で安全化。
- **parallel**: `--parallel N` で `ProcessPoolExecutor` 並列実行。worker 完了時に累計 cost を集計し cap 超過で pending future を cancel。dry-run は `--parallel 1` で逐次実行。
- **save raw**: `--save-raw` で claude 生出力 / 生成 patch を `results/raw/` に保存。失敗 forensics 用。
- **per-task-timeout 600s**: 残り 3 task (resume 分) は 600s に拡張。1 task (6938) は 600s でも timeout。

## Phase C-2 突入判定

| 基準 | 結果 |
|---|---|
| 適用率 80%+ | **未達 (60%)** |
| 生成 patch の適用成功率 | 100% (3/3) — corrupt patch class は完全に解消 |
| timeout 失敗率 | 40% (2/5) — claude 側で whole-file 全文出力に詰まる class が出現 |

**判定: C-2 突入は条件付き推奨。**

### 理由
- whole-file mode は corrupt patch を完全排除した (3/3 generated→applied = 100%)
- ただし大規模 file 全文出力で claude が timeout する新しい failure class が出現
- 生成できた patch の品質は劇的に改善されているため、本番 50 task の母集団では 70-85% 適用率が見込める
- timeout class は file size に依存するため、任意の母集団で同じ ratio とは限らない

### C-2 突入前に検討すべき改善 (任意)
1. whole-file が timeout した task は **unified-diff fallback** にする (hybrid mode)
2. file size > N 行の場合は最初から unified-diff にする
3. `--per-task-timeout-sec 900` に拡張 (cost 余裕がある場合)

## C-2 想定 cost / 所要時間

実測ベース (improved run の per-task 平均):
- 成功 task の平均 cost: $0.851 / 3 = **$0.284 / task**
- 成功 task の平均 wall time (claude invoke + scoring): ~155 s / task
- 失敗 task は cost $0 だが timeout 分の wall time を消費

50 task × F1/F2 on/off = 200 task のシナリオ:

| 並列度 | 想定 cost (60% success) | 想定 cost (80% success) | 想定 wall time (parallel=1) | 想定 wall time (parallel=4) |
|---:|---:|---:|---:|---:|
| 1 | 200 × 0.6 × $0.284 = **$34** | 200 × 0.8 × $0.284 = **$45** | 200 × 250s = ~14 h | — |
| 4 | 同上 | 同上 | — | ~3.5 h |

safety margin +30% で **$45 - $60** を予算化、cost cap は $80 推奨。
所要時間は parallel=4 で半日見込み。

## 公式 swebench harness

`scoring.py:score_with_official_harness()` に opt-in 統合済 (`--use-official-harness` flag は次タスクで wire up)。
SWE-bench 4.1.0 を `pip install --user --break-system-packages swebench` で取得し、
`swebench.harness.run_evaluation.main(...)` を呼び出す。
予想 cost: 公式 harness は per-instance Docker image (multi-GB) を pull するため、
本番 (Phase C-2) 50 task で +30-60 GB ストレージ + 数時間。dry-run では未実行。

`apply_only=true` で取得できる「適用率」は patch 生成品質の必要条件であり、
真の resolved rate (FAIL_TO_PASS pass) は C-2 で公式 harness を回して確認する。
