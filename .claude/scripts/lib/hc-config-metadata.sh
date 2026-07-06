# .claude/scripts/lib/hc-config-metadata.sh — task-48 Step 2 (TDD GREEN 前半) + iter1 review fixes
#
# shellcheck shell=bash
#
# 目的:
#   harness-config.yml の全 key に「category + 説明 (description) + 変更効果 (effect)」
#   metadata を定義し、hc-config.sh TUI / --list 説明列拡張から参照させる。
#   inline comment を持つ key (feature_* 21 + review_* 14 = 35 件) は comment を
#   description のソースとして流用 (DRY)、それ以外の key は適切な説明を hardcode。
#
# 設計:
#   - source 専用 lib (chmod +x 不要、shebang なし — 既存 config-loader.sh の慣習に合わせる。
#     静的解析用に shell directive (file 冒頭 line 3) のみ付与し SC2148 を解消)。
#   - bash 3.2 互換: associative array (declare -A) は bash 4+ なので回避。
#     here-doc (`KEY<TAB>category<TAB>description<TAB>effect`) + grep/cut/awk で引く。
#   - file-top に set -euo pipefail を書かない (feedback_set_e_in_sourced_libs 規範、
#     caller の shell flags への leak と SIGPIPE 死を防ぐ)。
#   - 引き関数は subshell ( ) 化 + set -uo pipefail で局所化。
#
# 区切り文字 (iter1 C3 fix):
#   従来 `|` 区切りだったが required_env の description 内 "(NAME|severity|purpose 形式)" の
#   `|` が CSV 区切りと衝突し field 破壊 (description 途中切れ + effect に断片) していた。
#   区切りを TAB (`\t`) に変更。本文 (説明 / 変更効果) は日本語 + path で TAB を含まないため
#   将来の `|` 混入にも強い。required_env の本文 `|` は `／` (全角スラッシュ) にサニタイズ済。
#
# 公開 interface (smoke が期待する関数):
#   - hc_metadata_description <key>      → description を stdout (不在なら空 + return 1)
#   - hc_metadata_effect <key>           → effect を stdout (不在なら空 + return 1)
#   - hc_metadata_category <key>         → category を stdout (不在なら空 + return 1)
#   - hc_metadata_keys_by_category <cat> → category に属する key を改行区切りで stdout
#
# category 7 分類 (smoke Case 2 が期待、task-69 で harness_meta 追加):
#   保護パス / ファイル配置 / state_dir / Gate/Confidence / feature_toggle / reviewer_control / harness_meta
#
# 起源:
#   task-48 Step 2、設計 draft: docs/draft/config-yml-phase3-hc-config-script.md §3.1 §3.2
#   smoke: .claude/tests/hc-config-tui-smoke.sh (Case 1 / 2 / 7 を GREEN にする)

# ============================================================
# metadata table (TSV: KEY<TAB>category<TAB>description<TAB>effect<TAB>label_ja)
# ============================================================
# 区切りは TAB。description / effect / label_ja 内に TAB は使わない (本文に TAB は出ない)。
# label_ja (5 列目、task-78 Step 1 追加): key の短い日本語ラベル (5-15 文字)。Web UI sidebar 表示用。
# 全 80 key を 7 category のいずれかに漏れなく分類 (未分類 0、task-69 で harness_meta 追加 + 5 key 追加)。
_hc_metadata_table() {
  cat <<'METADATA_EOF'
protected_paths	保護パス	委譲ガードがメイン直接操作禁止とみなす path 部分一致リスト (例: src/tests/scripts)	追加すると該当 path が main 直接編集禁止になりサブエージェント委譲が強制される。削除すると委譲ガードが解除される	保護パス一覧
protected_paths_code	保護パス	code 実装の保護パス (Edit/Write 時 code_file_extensions と AND 判定で BLOCK)	追加すると該当 path 配下の code file 編集が subagent 委譲必須になる。削除すると main 直接編集が許可される	コード保護パス
code_file_extensions	保護パス	protected_paths_code と組で BLOCK 判定する code 拡張子リスト (sh/py/ts 等)	追加すると該当拡張子が保護対象に加わる。削除すると該当拡張子が main 直接編集可能になる	コード拡張子
task_dir	ファイル配置	タスク管理ファイルの配置 dir (task-rule-guard が docs/tasks 規約を判定する基準)	変更すると task ファイルの探索先 dir が切り替わる。誤値だと task-rule-guard が規約判定を見失う	タスクdir
draft_dir	ファイル配置	設計 draft の配置 dir (draft-flow-guard / task-rule-guard が docs/draft 規約を判定する基準)	変更すると draft ファイルの探索先 dir が切り替わる。誤値だと設計→承認フローの判定が崩れる	draftdir
bash_whitelist_path	ファイル配置	delegation-guard が読む bash allow-list ファイルの位置 (リポルート相対)	変更すると bash whitelist の読込先が切り替わる。不在だと whitelist 判定がスキップされる	bash許可リストpath
docs_approved_dir	ファイル配置	draft-flow-guard が docs/<value>/foo.md 形式の Write を pass させる承認済 dir (CSV 複数値可)	追加すると該当 docs サブ dir への直接 Write が許可される。空だと docs/draft 経路のみ承認される	承認済docsdir
rule_change_guard_enabled	Gate/Confidence	規範変更 BLOCK 機構 (rules/commands/templates への新規 Write 時に対応 draft の承認を要求)	false にすると task-40 拡張部のみ停止し規範変更が draft なしで通る (docs/ 直下 block は維持)	規範変更ガード有効化
loop_confirmation_detection_enabled	feature_toggle	Loop モード確認質問検出 hook (AI 最終 message の確認質問パターンを検出し自律是正を強制)	false にすると loop-confirmation-detector が完全停止し確認質問の自律是正が効かなくなる	確認質問検出有効化
gateguard_state_dir	state_dir	GateGuard (F1) が cleared/marker 等の状態を書き出す dir	変更すると GateGuard の state 保管先が切り替わる。誤値だと clear 済判定が引き継がれず再 BLOCK する	GateGuard状態dir
taskguard_state_dir	state_dir	task-rule-guard / task-bypass が cleared marker を書き出す dir	変更すると TaskGuard の state 保管先が切り替わる。誤値だと bypass marker が引き継がれない	TaskGuard状態dir
agent_marker_dir	state_dir	subagent 実行中マーカーの保管 dir (多重ゲート防止のため subagent 起動時に書かれる)	変更すると agent marker の保管先が切り替わる。誤値だと subagent 判定が崩れガードが多重発火する	agentマーカーdir
failure_window_dir	state_dir	failure-loop-detect が同一エラー連続失敗を記録する window 保管 dir	変更すると失敗 window の保管先が切り替わる。誤値だと 3 連続失敗検出が引き継がれない	失敗window状態dir
homunculus_root	ファイル配置	continuous-learning v2.1 の observe.sh / harness-audit が観察ログを書き出す外部 root (tilde 展開対応)	変更すると観察ログの蓄積先が切り替わる。誤値だと L4 学習データが分散し instinct 信頼度計算が崩れる	学習ログroot
notify_sound	ファイル配置	notify.sh が再生する afplay 対象音源 (macOS のみ、非 macOS では無視)	変更すると通知音が切り替わる。不在ファイルだと afplay が無音になる	通知音ファイル
stop_sound	ファイル配置	stop.sh が再生する afplay 対象音源 (macOS のみ、非 macOS では無視)	変更すると停止音が切り替わる。不在ファイルだと afplay が無音になる	停止音ファイル
confidence_threshold	Gate/Confidence	Confidence Gate (F3) の pass 最低値 (0.0-1.0、SuperClaude 既定 0.6 相当)	上げると subagent の completion confidence 要求が厳しくなり早期完了宣言を強く抑止する。下げると緩くなる	信頼度しきい値
confidence_required	Gate/Confidence	confidence 未記載時の挙動 (true なら未記載で BLOCK、false なら未記載でも pass)	true にすると confidence 未記載 subagent を BLOCK する。false にすると fail-open 寄りで未記載でも通す	信頼度記載必須
confidence_state_dir	state_dir	Confidence Gate の bypass marker / bypass.log の保管 dir	変更すると Confidence Gate の state 保管先が切り替わる。誤値だと bypass が引き継がれない	信頼度Gate状態dir
required_env	Gate/Confidence	check-required-env が検証する必須環境変数リスト (NAME／severity／purpose 形式)	追加すると未設定時に SessionStart で WARN 通知される (fail-open: 未設定でも起動継続)。空だと検証なし	必須環境変数
improvement_proposal_enabled	feature_toggle	SessionStart で observations を集計し誤動作パターンと改善案を提示する機構	false にすると SessionStart 改善提案が全停止する。true だと data 駆動で 1-N 件提示される	改善提案有効化
improvement_proposal_lookback_days	Gate/Confidence	改善提案が observations.jsonl を遡って読む日数	増やすと過去のより広い観察を集計対象にする。減らすと直近の傾向のみ集計する	改善提案遡及日数
improvement_proposal_max_count	Gate/Confidence	SessionStart 改善提案の最大提示件数	増やすと提示件数が増え noisy になる。減らすと提示件数が絞られる	改善提案最大件数
improvement_proposal_state_dir	state_dir	改善提案の dedup 用 last_shown.json 保管 dir	変更すると dedup state の保管先が切り替わる。誤値だと同一提案が再表示される	改善提案状態dir
improvement_proposal_dedup_hours	Gate/Confidence	同一改善提案を再出力するまでの最小時間 (時間)	増やすと同一提案の再表示間隔が延びる。減らすと頻繁に再表示される	改善提案再表示間隔
context_budget_enabled	feature_toggle	Loop モード時 context 使用率監視 hook (閾値超で /save-state 実行 + 再開提案を強制)	false にすると context-budget が完全停止し Normal モードと等価動作になる	context監視有効化
context_budget_limit	Gate/Confidence	context window サイズ (tokens、Opus 1M=1000000 / Sonnet 200K=200000、モデル切替時手動更新)	変更すると使用率計算の分母が変わる。実モデルと不一致だと閾値発火タイミングがずれる	contextサイズ上限
context_budget_threshold	Gate/Confidence	context 使用率の警告開始 ratio (0.0-1.0、tier は 60/80/95 で自動エスカレート)	上げると警告開始が遅くなる。下げると早めに /save-state を促す	context警告しきい値
context_budget_state_dir	state_dir	warning 済 tier marker の保管 dir	変更すると tier marker の保管先が切り替わる。誤値だと同一 tier 警告が再発火する	context監視状態dir
reviewer_registry_design	reviewer_control	design-review fan-out で並列起動する設計レビュー専門 agent 配列 (System/Code/API/UI/DB)	追加すると design-review で起動候補の agent が増える。削除すると該当領域のレビューが省かれる	設計レビューagent群
reviewer_registry_security	reviewer_control	design-review fan-out のセキュリティレビュー専門 agent 配列	追加すると security レビュー候補 agent が増える。削除すると該当レビューが省かれる	セキュリティレビューagent群
reviewer_registry_test	reviewer_control	test-design / design-review のテスト設計・QA 専門 agent 配列 (採用 6 条 4 で使用)	追加するとテスト設計レビュー候補 agent が増える。削除すると該当レビューが省かれる	テストレビューagent群
reviewer_registry_impl	reviewer_control	module-review / system-review の実装レビュー専門 agent 配列 (言語別 reviewer 含む)	追加すると実装レビュー候補 agent が増える。削除すると該当言語レビューが省かれる	実装レビューagent群
workflow_stages_new	Gate/Confidence	new-feature 14-stage オーケストレータの stage 名配列 (finish 到達を workflow-guard が判定)	変更すると new-feature の必須 stage 列が変わる。最終要素未到達だと finish-task が BLOCK される	新機能stage列
workflow_stages_modify	Gate/Confidence	modify-feature 10-stage オーケストレータの stage 名配列	変更すると modify-feature の必須 stage 列が変わる。最終要素未到達だと finish-task が BLOCK される	機能変更stage列
mainline_branch	Gate/Confidence	AI が merge 先とする本流(統合)ブランチ名 (master/develop/trunk 等に変更可、charset 制限あり)	変更すると git-deny の policy 連動 push 判定対象が切り替わる。main は mainline 移動後も常時 block 維持	本流ブランチ
mainline_integration_policy	Gate/Confidence	本流への統合ポリシー (pr-required/local-merge/local-merge-push の 3 値)	pr-required で本流 push 全 block (PR 停止)、local-merge でローカル merge まで AI、local-merge-push で本流 push まで自動	本流統合ポリシー
list_plan_first_reminder_enabled	feature_toggle	SessionStart で draft 3 件以上 ∧ list.md task 行 0 を検出し経路 B 適用を促す reminder	false にすると plan-first reminder が完全停止し batch planning の plan-first 先置き促しが消える	plan-first促し有効化
parallel_subagent_reminder_enabled	feature_toggle	subagent 起動時に並列性・agent type 選定の reminder を注入する hook (BLOCK しない)	false にすると parallel-subagent-reminder が完全停止し並列起動・専門 type 推奨の促しが消える	並列subagent促し有効化
parallel_subagent_ttl_sec	Gate/Confidence	parallel-subagent-reminder の state file TTL (秒、直近起動判定の窓)	増やすと並列起動なし判定の窓が広がり reminder が出にくくなる。減らすと窓が狭まり出やすくなる	並列促しTTL秒
feature_loop_mode_enforcement_enabled	feature_toggle	loop-confirmation-detector + loop-auto-progress-reminder + mode-enforce	false にすると Loop モード 3 hook を一括 OFF にし Loop モードの自律規律強制が全て止まる	Loopモード強制有効化
feature_draft_flow_guard_enabled	feature_toggle	draft-flow-guard	false にすると draft-flow-guard を OFF にし docs/ 直下 + 規範変更の draft 必須 BLOCK が止まる	draftフローガード有効化
feature_task_rule_guard_enabled	feature_toggle	task-rule-guard + list-md-plan-first-reminder	false にすると task-rule-guard 系を一括 OFF にし設計→承認→タスク化フローの機械強制が止まる	タスクルールガード有効化
feature_delegation_guard_enabled	feature_toggle	delegation-guard	false にすると delegation-guard を OFF にし保護パスへの main 直接操作 BLOCK が止まる	委譲ガード有効化
feature_workflow_enforcement_enabled	feature_toggle	workflow-guard	false にすると workflow-guard を OFF にし new-feature/modify-feature の stage 進行強制が止まる	workflow強制有効化
feature_confidence_gate_enabled	feature_toggle	confidence-gate (F3)	false にすると Confidence Gate (F3) を OFF にし subagent の confidence 閾値 BLOCK が止まる	信頼度ゲート有効化
feature_gateguard_enabled	feature_toggle	gateguard (F1)	false にすると GateGuard (F1) を OFF にし初回 Edit/Write/破壊的 Bash の事実調査要求が止まる	GateGuard有効化
feature_context_budget_enabled	feature_toggle	context-budget	false にすると context-budget を OFF にし Loop モードの context 使用率監視が止まる	context監視有効化(上位)
feature_parallel_subagent_reminder_enabled	feature_toggle	parallel-subagent-reminder	false にすると parallel-subagent-reminder を上位 layer で OFF にし並列性 reminder が止まる	並列促し有効化(上位)
feature_autonomous_action_guard_enabled	feature_toggle	autonomous-action-guard	false にすると autonomous-action-guard を OFF にし禁止 11 カテゴリの Bash BLOCK が止まる	自律操作ガード有効化
feature_byproduct_discharge_enabled	feature_toggle	byproduct-discharge-guard + next-actions-surface	false にすると副産物排出系を一括 OFF にし next-actions 浮上と byproduct 排出促しが止まる	副産物排出有効化
feature_why_x5_enforcement_enabled	feature_toggle	why-x5-reminder + why-x5-violation-detect	false にすると Why x5 強制系を OFF にし「何のため×何をやる」1 行出力の reminder/検出が止まる	Whyx5強制有効化
feature_session_help_surface_enabled	feature_toggle	session-help-surface	false にすると session-help-surface を OFF にし SessionStart の help 浮上が止まる	help浮上有効化
feature_improvement_proposal_enabled	feature_toggle	improvement-proposal	false にすると improvement-proposal を上位 layer で OFF にし SessionStart 改善提案が止まる	改善提案有効化(上位)
feature_mode_session_start_enabled	feature_toggle	mode-session-start	false にすると mode-session-start を OFF にし SessionStart のモード表示・切替提案が止まる	モード表示有効化
feature_check_serena_mcp_enabled	feature_toggle	check-serena-mcp	false にすると check-serena-mcp を OFF にし Serena MCP 接続確認が止まる	SerenaMCP確認有効化
feature_check_required_env_enabled	feature_toggle	check-required-env	false にすると check-required-env を OFF にし必須環境変数の未設定 WARN が止まる	必須環境変数確認有効化
feature_init_tasks_on_start_enabled	feature_toggle	init-tasks-on-start	false にすると init-tasks-on-start を OFF にし SessionStart のタスク台帳テンプレ自動生成が止まる	タスク台帳初期化有効化
feature_notify_enabled	feature_toggle	notify + stop (sound)	false にすると notify/stop の音通知を OFF にし afplay 再生が止まる	音通知有効化
feature_check_md_mermaid_enabled	feature_toggle	check-md-mermaid	false にすると check-md-mermaid を OFF にし md 内 mermaid 構文検証が止まる	mermaid検証有効化
feature_failure_loop_detect_enabled	feature_toggle	failure-loop-detect	false にすると failure-loop-detect を OFF にし同一エラー連続失敗の検出が止まる	失敗ループ検出有効化
feature_agent_router_suggest_enabled	feature_toggle	agent-router-suggest (task-81 復活配線、UserPromptSubmit で agent-router skill を実行し高確信時のみ specialist 推奨 1 行 hint を注入、fail-open)	false にすると agent-router-suggest を OFF にし UserPromptSubmit の specialist 推奨 hint 注入が止まる	agent推奨hint有効化
feature_sessionstart_summary_enabled	feature_toggle	mode-session-start (SessionStart reminder に hc-config.sh --summary 全文を注入して effective state を可視化、P1-4。feature_mode_session_start_enabled OFF 時は本 toggle に関わらず注入されない)	false にすると SessionStart の --summary 全文注入を OFF にし compact status 1 行のみに戻る	summary注入有効化
feature_self_doctor_enabled	feature_toggle	self-doctor.sh (install 末尾で D1-D8 setup issue を検証、期待外 WARN のみ 3 点提示 format で報告、P1-3)	false にすると self-doctor.sh を no-op 化し install 末尾および consuming repo 手動再実行時の setup issue 検証が全 skip される	self-doctor有効化
feature_pre_commit_smoke_enabled	feature_toggle	.githooks/pre-commit fast smoke curated set 実行 (task-92 P2-1、opt-out 契約、budget 超過は smoke 側で WARN)	false にすると pre-commit fast smoke が silent pass 化し curated set 実行が止まる (quality gate 失効)。true にすると commit 前に fast smoke curated set が実行される	pre-commitsmoke有効化
pre_commit_smoke_budget_sec	Gate/Confidence	pre-commit fast smoke の実行時間予算 (秒、超過で smoke 側 WARN、task-92)	増やすと curated set 拡張の余地が広がる。減らすと予算超過 WARN が早期発火し fast smoke の速度契約が保たれる	pre-commit予算秒
feature_asana_prompt_enabled	feature_toggle	mode-asana-prompt.sh (SessionStart で asana 未決 hearing を 1 回のみ提示、mode.yml asana_enabled と直交、task-95)	false にすると mode-asana-prompt.sh を OFF にし SessionStart の Asana 未決 hearing が止まる (asana 排除運用向け)	asana促し有効化
feature_agent_router_llm_fallback_enabled	feature_toggle	agent-router-suggest.sh の LLM fallback 子 toggle (keyword confidence が threshold 未満で router.py に --use-llm-fallback を渡すか、task-96)	false にすると LLM fallback が完全停止し keyword 結果のみで hint 判定される (cost 0 化)。true にすると threshold 未満で LLM 呼出が発生	LLMフォールバック有効化
agent_router_llm_budget_usd_per_day	Gate/Confidence	agent-router LLM fallback の 1 日あたり (UTC day) の cost 累積上限 (USD、超過検出時は当日 fallback を強制 disable、task-96)	増やすと 1 日あたりの LLM 呼出許容量が増え hint 発火頻度が上がる。減らすと当日の早期 disable が発火し hint が抑制される	LLM日次予算USD
agent_router_llm_similarity_threshold	Gate/Confidence	agent-router keyword confidence が本値未満の時のみ LLM fallback を発火 (0.0-1.0、上げると発火頻度低下・cost 低下、task-96)	上げると LLM fallback 発火が絞られ hint が保守的になる。下げると発火頻度が上がり cost が増える	LLM発火しきい値
feature_hc_config_tui_legacy_enabled	feature_toggle	hc-config TUI legacy fallback (task-61 Step 5 iter 2 D、HC_HC_CONFIG_TUI_LEGACY と OR 結合で dispatcher が判定)	true にすると hc-config.sh interactive で task-60 TUI を起動 (default false で task-61 Web UI を起動)	TUIレガシー有効化
review_required_design	reviewer_control	false なら /design-review が no-op skip	false にすると design-review が no-op skip され設計レビュー fan-out が省かれる	設計レビュー必須
review_min_count_design	reviewer_control	design-review fan-out で並列起動する reviewer の最小数 (default 3、reviewer_registry_design 件数下限)	増やすと設計レビューの網羅性が上がるが並列 subagent 消費が増える。減らすとレビューが手薄になり見逃しリスクが上がる	設計レビュー最小数
review_max_count_design	reviewer_control	design-review fan-out で並列起動する reviewer の最大数 (default は registry 全件)	減らすと並列 subagent 消費を抑えられるが設計レビューの網羅性が下がる。増やすと網羅性が上がるが消費が増える	設計レビュー最大数
review_required_test	reviewer_control	false なら採用 6 条 4 テスト設計レビュー step skip 可	false にするとテスト設計レビュー step を skip 可能にする。true だと採用 6 条 4 で必須化される	テストレビュー必須
review_min_count_test	reviewer_control	テスト設計レビュー fan-out で並列起動する reviewer の最小数 (default 5、採用 6 条 4 の 5+ 動的選定下限)	増やすとテスト設計レビューの網羅性が上がるが並列 subagent 消費が増える。減らすとレビューが手薄になる	テストレビュー最小数
review_max_count_test	reviewer_control	テスト設計レビュー fan-out で並列起動する reviewer の最大数 (default は registry 全件)	減らすと並列 subagent 消費を抑えられるがテスト設計レビューの網羅性が下がる。増やすと網羅性が上がるが消費が増える	テストレビュー最大数
review_required_module	reviewer_control	false なら /module-review skip 可	false にすると module-review を skip 可能にする。true だと必須化される	モジュールレビュー必須
review_min_count_module	reviewer_control	default 2 (code-reviewer + refactoring-specialist)	増やすと module-review の reviewer 下限が上がる。減らすと下限が下がる	モジュールレビュー最小数
review_max_count_module	reviewer_control	default registry 全件、上限指定	減らすと module-review の reviewer 上限が下がる。増やすと上限が上がる	モジュールレビュー最大数
review_required_system	reviewer_control	false なら /system-review skip 可	false にすると system-review を skip 可能にする。true だと必須化される	システムレビュー必須
review_min_count_system	reviewer_control	default 2 (architect-reviewer + refactoring-specialist)	増やすと system-review の reviewer 下限が上がる。減らすと下限が下がる	システムレビュー最小数
review_max_count_system	reviewer_control	default registry 全件、上限指定	減らすと system-review の reviewer 上限が下がる。増やすと上限が上がる	システムレビュー最大数
review_required_security	reviewer_control	default false (security 影響 task のみ)	true にすると security レビューを必須化する。false だと security 影響 task のみで起動される	セキュリティレビュー必須
review_min_count_security	reviewer_control	default 1 (security-reviewer)	増やすと security レビューの reviewer 下限が上がる。減らすと下限が下がる	セキュリティレビュー最小数
review_iteration_max	reviewer_control	レビュー → 修正 → 再レビューを繰り返す反復の上限回数 (default 5、採用 6 条 4 の収束上限)	増やすと収束まで粘れるが時間とコストが増える。減らすと早期に user escalation し反復が浅くなる	レビュー反復上限
feature_reviewer_count_guard_enabled	feature_toggle	reviewer-count-guard (test 設計レビュー fan-out 数が review_min/max_count を逸脱した時に warn 注入、task-64 Step 5)	false にすると reviewer-count-guard を OFF にし reviewer 並列起動数の min/max 逸脱 warn が止まる	レビュー数ガード有効化
feature_tool_call_slip_detect_enabled	feature_toggle	tool-call-slip-detector (Stop hook で tool 呼び出しの markup slip を検出し次 turn 自己是正を注入)	false にすると slip 検出 hook を OFF にし markup slip 時の自己是正注入が止まる	tool slip検出有効化
harness_version	harness_meta	harness 本体のバージョン (install.sh が更新する日付文字列、採用先 project は手動編集しない)	変更すると stale-harness-detect の比較基準が切り替わる。手動編集すると採用先 project の取込判定が崩れる	harnessバージョン
stale_harness_markers	harness_meta	stale-harness-detect が consuming repo の取込遅れ検出に使う marker ファイル配列 (CommonRules.md 等)	追加すると stale 検出対象 file が増える。削除すると該当 file の drift が検出されなくなる	stale検出marker群
feature_stale_harness_detect_enabled	harness_meta	stale-harness-detect (consuming repo の harness 取込遅れを SessionStart で WARN 通知する hook)	false にすると stale-harness-detect を OFF にし harness 取込遅れの WARN 通知が止まる	stale検出有効化
stale_harness_check_interval_hours	harness_meta	stale-harness-detect が npm registry latest と semver 比較する際の throttle 間隔 (時間単位、default 24)	大きくすると registry 取得頻度が下がり stale 検出が遅れる。小さくすると毎 session 近く取得し network 負荷が増える	registry取得間隔
harness_npm_version	harness_meta	stale-harness-detect が registry latest と比較する npm semver stamp (install.sh が package.json から書込む)	手動編集すると registry 比較の基準 version がずれ更新通知の判定が崩れる。install.sh 再実行で正規値に戻る	npmバージョンstamp
default_preset	harness_meta	本 repo で適用する enforcement preset (advisory/team-default/strict/harness-dev、guard の期待強制レベルを決める)	変更すると --summary / mismatch smoke が照合する preset 期待値が切り替わる。実 enforcement は feature_*_enabled が SSoT	既定プリセット
enforcement_matrix	harness_meta	guard ごとの docs_claim + preset 期待 + disabled_reason を宣言する nested block (flat parser は値を読まず --summary が直接 parse)	編集すると --summary / mismatch smoke の照合対象 guard と期待値が変わる。実 enforcement の on/off は feature toggle 側が決める	enforcement行列
METADATA_EOF
}

# ============================================================
# 引き関数 (subshell + set -uo pipefail で局所化)
# ============================================================

# TSV の指定 field を key で引く内部 helper
# $1: key, $2: field 番号 (1=key 2=category 3=description 4=effect 5=label_ja)
# 戻り: stdout に値 (不在なら空 + return 1)
# 区切りは TAB。cut -d は実 TAB 文字を渡す ($'\t')。
_hc_metadata_field() (
  set -uo pipefail
  local key="$1"
  local field="$2"
  local tab
  tab=$(printf '\t')
  local line
  line=$(_hc_metadata_table | grep -E "^${key}${tab}" | head -n 1) || true
  if [ -z "$line" ]; then
    return 1
  fi
  printf '%s' "$line" | cut -d"$tab" -f"$field"
)

# key の description を取得
# $1: key
hc_metadata_description() {
  _hc_metadata_field "$1" 3
}

# key の変更効果 (effect) を取得
# $1: key
hc_metadata_effect() {
  _hc_metadata_field "$1" 4
}

# key の category を取得
# $1: key
hc_metadata_category() {
  _hc_metadata_field "$1" 2
}

# key の日本語ラベル (label_ja) を取得
# $1: key
hc_metadata_label_ja() {
  _hc_metadata_field "$1" 5
}

# category に属する全 key を改行区切りで取得
# $1: category 名 (保護パス / ファイル配置 / state_dir / Gate/Confidence / feature_toggle / reviewer_control)
# 戻り: stdout に key 改行区切り (該当なしなら空)
hc_metadata_keys_by_category() (
  set -uo pipefail
  local cat="$1"
  # field 2 (category) が完全一致する行の field 1 (key) を出力 (区切りは TAB)
  _hc_metadata_table | awk -F'\t' -v c="$cat" '$2 == c { print $1 }'
)
