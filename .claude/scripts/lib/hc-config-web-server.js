#!/usr/bin/env node
// .claude/scripts/lib/hc-config-web-server.js — task-63 Step 4 領域 A (設計簡素化、案 C values 完全一致判定)
//
// task-63 Step 4 領域 A 修正項目 (4 件、user 確定要求「プリセット名保存不要」2026-05-29):
//   A1. 撤去: /api/preset/save endpoint + savePreset() + scanCustomPresets() + isTestPollutionName() +
//             TEST_POLLUTION_PATTERNS const + /api/presets / /api/preset/:name/diff / /api/preset/:name/apply
//             の custom preset merge ロジック (~80-100 LOC 削減)
//   A2. 案 C 採用: getCurrentPreset() を values field 完全一致判定 (subset) に書換、
//                axesEqual() → valuesSubsetEqual() に rename + logic 変更、PRESETS axes 6 軸照合は廃止
//   A3. response 簡素化: /api/presets から axes_values 撤去、/api/current-preset は { name, display_name_ja, match_type }
//   A4. module.exports 整理: savePreset / scanCustomPresets / isTestPollutionName / axesEqual 撤去、
//                            getCurrentPreset / valuesSubsetEqual 追加
//
// task-63 Step 1 修正項目 (継承、UX 再設計の API 基盤):
//   1. PRESETS 全 10 件に display_name_ja field 追加 (draft §3.1 mapping、日本語表示専用、絵文字なし)
//   2. /api/presets response 各 entry に display_name_ja field 追加
//   3. /api/current-preset 新規 endpoint (現在 yml 全 key 値 vs PRESETS values 完全一致 subset 判定)
//   4. router に /api/current-preset GET 分岐追加
//   5. module.exports に getCurrentPreset / valuesSubsetEqual 追加
//
// iter 6 A 修正項目 (5 件 = HIGH×2 + MED×2 + 補強):
//   item 1 (HIGH 3-rev): HC_HISTORY_DIR_OVERRIDE + HC_PRESETS_DIR_OVERRIDE env override (test isolation)
//   item 2 (HIGH 2-rev / MED-N3 実 HIGH): savePreset で PRESETS in-memory 追加 + /api/presets で
//                                          PRESETS_DIR/custom-*.yml dynamic scan (§6 DoD 完全達成)
//   item 3 (MED code-rev): HISTORY_MAX_FILES NaN / 負値 / 0 safe fallback 1000
//   item 4 (MED code-rev): /api/value/:key + /api/set で hcGet/hcSet に {} 明示 (DI seam)
// (UI 側 item 5 + style.css item 6 は app.js / style.css に別途実装)
//
// 目的:
//   hc-config.sh interactive (TTY 経路 default) の Web UI 化。
//   Node.js 標準 module のみ (http / child_process / fs / path / os / url / net)、npm dep 0。
//
// 設計:
//   - localhost (127.0.0.1) only bind、外部 access 禁止
//   - port 3060-3070 自動 detect (listen error event 監視で EADDRINUSE 試行、race 排除)
//   - 全ての yml 書込は hc-config.sh CLI 経由 (atomic backup + type validation を再利用)
//   - 10 named preset を server.js 内 hardcode (draft §3.4 AI 推奨)
//   - SIGINT graceful shutdown
//   - applyPreset は 2-phase atomic (snapshot → apply、N 番目失敗で全件 rollback)
//   - rollback timestamp は path.basename + regex で path traversal 防止
//   - loadMetadata は process-lifetime cache、/api/set 成功で invalidate
//   - module.exports に unit test seam (callHcConfig / loadMetadata / readJsonBody / serveStatic)
//
// iter 4 A 修正項目 (10 件):
//   NEW-C-1 (CRIT): hcListAll() で /api/keys を 74 spawn → 1 spawn に集約 (Node event loop 370s block 解消)
//   NF-13   (HIGH): history stamp に pid + counter 追加 (同 ms 衝突 silent data loss 防止)
//   NF-2/9  (HIGH): applyPreset history write 失敗時 snapshot から rollback 実行 (silent data loss 防止)
//   NF-8    (HIGH): handleRequest catch で internal abs path leak 防止 (REPO_ROOT → <repo> sanitize、stack trace 除外)
//   HIGH-Q3 (MED) : savePreset で invalidateMetadataCache() 追加 (一貫性確保)
//   NF-12   (MED) : NEW-C-1 統合で解消 (本項目は no-op 補強のみ)
//   NF-3    (MED) : rollback restore 順序 LIFO 化 (apply 順 → 逆順、依存 key 不整合最小化)
//   NF-6    (MED) : listHistory cleanup 機構追加 (1000 件超で古い順削除、HC_HISTORY_MAX_FILES env 上書き可)
//   NF-10   (MED) : callHcConfig で timeout 判定 + timedOut flag 追加 (UI 側で "timeout 5s 超過" 明示)
//   設計乖離 : savePreset name regex を ^[a-z0-9][a-z0-9-]{2,48}$ (3-49 char、app.js と統一)、axes 6 軸完全必須
//
// API endpoint:
//   GET  /                          → redirect /static/index.html
//   GET  /static/*                  → static file serve (index.html / app.js / style.css)
//   GET  /api/keys                  → 74 key + metadata (現在値含む、bulk hcListAll = 1 spawn)
//   GET  /api/categories            → 6 category 一覧
//   GET  /api/current-preset        → 現在 yml 全 key 値 vs PRESETS values 完全一致 subset 判定 (task-63 Step 4 案 C)
//   GET  /api/value/:key            → 単一 key 現在値
//   POST /api/set                   → {key,value} → hc-config.sh --set
//   GET  /api/presets               → 10 preset 一覧 (display_name_ja + use_case + affected_key_count)
//   GET  /api/preset/:name/diff     → preset 適用差分 (effect 列含む)
//   POST /api/preset/:name/apply    → batch hc-config.sh --set + history 保存 (atomic)
//   GET  /api/preset/history        → 適用履歴一覧
//   POST /api/preset/rollback/:ts   → history rollback (chain 修復 + traversal 防止)
//
// task-63 Step 4 撤去 (user 確定要求「プリセット名保存不要」):
//   POST /api/preset/save (404 fallback で応答、savePreset/scanCustomPresets/isTestPollutionName 全て撤去)
//
// 起源: docs/draft/hc-config-web-ui.md §3.1 §3.2 §3.4 §6 / docs/tasks/task-61-hc-config-web-ui.md Step 5

'use strict'

const http = require('http')
const { spawnSync } = require('child_process')
const fs = require('fs')
const path = require('path')
const os = require('os')

// ============================================================
// 定数 / パス解決
// ============================================================

const SCRIPT_DIR = __dirname // .claude/scripts/lib
const HC_CONFIG_SCRIPT = path.resolve(SCRIPT_DIR, '..', 'hc-config.sh')
const REPO_ROOT = path.resolve(SCRIPT_DIR, '..', '..', '..')
const STATIC_DIR = path.join(SCRIPT_DIR, 'hc-config-web-ui')
// iter 6 A item 1 (HIGH 3-rev): env override で test isolation を可能化
//   smoke が HC_HISTORY_DIR_OVERRIDE を渡しても server.js が読まなかった bug
//   (server boot で常に repo root の .claude/.preset-history を参照)
const HISTORY_DIR = process.env.HC_HISTORY_DIR_OVERRIDE || path.join(REPO_ROOT, '.claude', '.preset-history')
// task-63 Step 4 A1: PRESETS_DIR は撤去済 (custom preset 保存機能廃止)
// env override (HC_PRESETS_DIR_OVERRIDE) は smoke regression 互換のため定義のみ維持 (実利用なし)

const PORT_MIN = 3060
const PORT_MAX = 3070
const HOST = '127.0.0.1'
const HC_SUBPROCESS_TIMEOUT_MS = 5000

// NF-6: history file 最大保持件数 (超過は古い順 cleanup)
// iter 6 A item 3 (MED): NaN / 負値 / 0 は安全 fallback 1000
const _historyMaxParsed = parseInt(process.env.HC_HISTORY_MAX_FILES || '1000', 10)
const HISTORY_MAX_FILES = Number.isFinite(_historyMaxParsed) && _historyMaxParsed > 0 ? _historyMaxParsed : 1000

// rollback timestamp validation (M-P3): ISO-8601 風 + preset name 区切り
//   実 history file 名 stem は `2026-05-29T12-34-56-789Z-poc-no-git` 形式 (toISOString の `:` / `.` を `-` 置換)
//   NF-13 後の format: `<ISO-stamp>-<pid>-<counter>-<preset>.json` or `<ISO-stamp>-<pid>-<counter>-rollback-of-<src>.json`
//   後段 path.basename も併用して path traversal を 2 重に防ぐ。
//   regex は旧 format (pid/counter 無し) も後方互換で受理 (英数 + `-` + `_` + `.` 許容)。
const ROLLBACK_TS_REGEX = /^[0-9TZ-]+[a-z0-9._-]+$/i

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
}

// ============================================================
// 6 軸 + 10 named preset hardcode (draft §3.4)
// ============================================================

const PRESET_AXES = [
  { key: 'quality_level', values: ['poc', 'inner_system', 'production_service'] },
  { key: 'language_framework', values: ['mixed', 'typescript', 'python', 'rust', 'go'] },
  { key: 'git_workflow', values: ['none', 'unrestricted', 'main_protected', 'main_stg_protected'] },
  { key: 'tdd_policy', values: ['optional', 'recommended', 'mandatory'] },
  { key: 'review_intensity', values: ['minimum', 'standard', 'strict'] },
  { key: 'autonomy_level', values: ['aggressive', 'moderate', 'conservative'] },
]

const PRESETS = {
  'poc-no-git': {
    display_name_ja: 'POC・お試し (Git なし)',
    axes: { quality_level: 'poc', language_framework: 'mixed', git_workflow: 'none', tdd_policy: 'optional', review_intensity: 'minimum', autonomy_level: 'aggressive' },
    use_case: '実験 / 一時試作 (1 日以内、捨てる予定)',
    values: {
      confidence_threshold: '0.5',
      confidence_required: 'false',
      review_required_design: 'false',
      review_required_test: 'false',
      review_required_module: 'false',
      review_required_system: 'false',
      review_required_security: 'false',
      review_min_count_design: '1',
      review_min_count_test: '1',
      review_iteration_max: '2',
      feature_loop_mode_enforcement_enabled: 'true',
      feature_gateguard_enabled: 'false',
      feature_workflow_enforcement_enabled: 'false',
      feature_draft_flow_guard_enabled: 'false',
      feature_task_rule_guard_enabled: 'false',
    },
  },
  'poc-with-git': {
    display_name_ja: 'POC・お試し (Git あり)',
    axes: { quality_level: 'poc', language_framework: 'mixed', git_workflow: 'unrestricted', tdd_policy: 'optional', review_intensity: 'minimum', autonomy_level: 'aggressive' },
    use_case: '個人 spike / 軽量 POC (Git 管理あり)',
    values: {
      confidence_threshold: '0.5',
      confidence_required: 'false',
      review_required_design: 'false',
      review_required_test: 'false',
      review_required_module: 'false',
      review_required_system: 'false',
      review_min_count_design: '1',
      review_min_count_test: '2',
      review_iteration_max: '2',
      feature_gateguard_enabled: 'false',
      feature_workflow_enforcement_enabled: 'false',
    },
  },
  'inner-typescript': {
    display_name_ja: '社内ツール (TypeScript)',
    axes: { quality_level: 'inner_system', language_framework: 'typescript', git_workflow: 'main_protected', tdd_policy: 'recommended', review_intensity: 'standard', autonomy_level: 'moderate' },
    use_case: '内部 tool TypeScript (社内利用、main protected)',
    values: {
      confidence_threshold: '0.6',
      confidence_required: 'true',
      review_required_design: 'true',
      review_required_test: 'true',
      review_required_module: 'true',
      review_required_system: 'false',
      review_min_count_design: '3',
      review_min_count_test: '3',
      review_min_count_module: '2',
      review_iteration_max: '3',
      feature_gateguard_enabled: 'true',
      feature_workflow_enforcement_enabled: 'true',
    },
  },
  'inner-python': {
    display_name_ja: '社内ツール (Python)',
    axes: { quality_level: 'inner_system', language_framework: 'python', git_workflow: 'main_protected', tdd_policy: 'recommended', review_intensity: 'standard', autonomy_level: 'moderate' },
    use_case: '内部 tool Python (社内利用、main protected)',
    values: {
      confidence_threshold: '0.6',
      confidence_required: 'true',
      review_required_design: 'true',
      review_required_test: 'true',
      review_required_module: 'true',
      review_required_system: 'false',
      review_min_count_design: '3',
      review_min_count_test: '3',
      review_min_count_module: '2',
      review_iteration_max: '3',
      feature_gateguard_enabled: 'true',
      feature_workflow_enforcement_enabled: 'true',
    },
  },
  'production-typescript-personal': {
    display_name_ja: '本番運用・個人 (TypeScript)',
    axes: { quality_level: 'production_service', language_framework: 'typescript', git_workflow: 'main_stg_protected', tdd_policy: 'mandatory', review_intensity: 'standard', autonomy_level: 'moderate' },
    use_case: '個人 production (classlab 等、main/stg protected)',
    values: {
      confidence_threshold: '0.6',
      confidence_required: 'true',
      review_required_design: 'true',
      review_required_test: 'true',
      review_required_module: 'true',
      review_required_system: 'true',
      review_required_security: 'false',
      review_min_count_design: '3',
      review_min_count_test: '5',
      review_min_count_module: '2',
      review_min_count_system: '2',
      review_iteration_max: '5',
      feature_gateguard_enabled: 'true',
      feature_workflow_enforcement_enabled: 'true',
      feature_confidence_gate_enabled: 'true',
    },
  },
  'production-typescript-enterprise': {
    display_name_ja: '本番運用・企業 (TypeScript)',
    axes: { quality_level: 'production_service', language_framework: 'typescript', git_workflow: 'main_stg_protected', tdd_policy: 'mandatory', review_intensity: 'strict', autonomy_level: 'conservative' },
    use_case: '企業 production TypeScript (strict review + conservative autonomy)',
    values: {
      confidence_threshold: '0.7',
      confidence_required: 'true',
      review_required_design: 'true',
      review_required_test: 'true',
      review_required_module: 'true',
      review_required_system: 'true',
      review_required_security: 'true',
      review_min_count_design: '5',
      review_min_count_test: '7',
      review_min_count_module: '3',
      review_min_count_system: '3',
      review_min_count_security: '2',
      review_iteration_max: '5',
      feature_gateguard_enabled: 'true',
      feature_workflow_enforcement_enabled: 'true',
      feature_confidence_gate_enabled: 'true',
      feature_autonomous_action_guard_enabled: 'true',
    },
  },
  'production-python': {
    display_name_ja: '本番運用 (Python)',
    axes: { quality_level: 'production_service', language_framework: 'python', git_workflow: 'main_stg_protected', tdd_policy: 'mandatory', review_intensity: 'strict', autonomy_level: 'conservative' },
    use_case: '企業 production Python (strict + conservative)',
    values: {
      confidence_threshold: '0.7',
      confidence_required: 'true',
      review_required_design: 'true',
      review_required_test: 'true',
      review_required_module: 'true',
      review_required_system: 'true',
      review_required_security: 'true',
      review_min_count_design: '5',
      review_min_count_test: '7',
      review_min_count_module: '3',
      review_min_count_system: '3',
      review_iteration_max: '5',
      feature_gateguard_enabled: 'true',
      feature_workflow_enforcement_enabled: 'true',
      feature_autonomous_action_guard_enabled: 'true',
    },
  },
  'production-rust': {
    display_name_ja: '本番運用 (Rust)',
    axes: { quality_level: 'production_service', language_framework: 'rust', git_workflow: 'main_stg_protected', tdd_policy: 'mandatory', review_intensity: 'strict', autonomy_level: 'conservative' },
    use_case: '企業 production Rust (strict + conservative)',
    values: {
      confidence_threshold: '0.7',
      confidence_required: 'true',
      review_required_design: 'true',
      review_required_test: 'true',
      review_required_module: 'true',
      review_required_system: 'true',
      review_required_security: 'true',
      review_min_count_design: '5',
      review_min_count_test: '7',
      review_min_count_module: '3',
      review_min_count_system: '3',
      review_iteration_max: '5',
      feature_gateguard_enabled: 'true',
      feature_workflow_enforcement_enabled: 'true',
      feature_autonomous_action_guard_enabled: 'true',
    },
  },
  'production-go': {
    display_name_ja: '本番運用 (Go)',
    axes: { quality_level: 'production_service', language_framework: 'go', git_workflow: 'main_stg_protected', tdd_policy: 'mandatory', review_intensity: 'strict', autonomy_level: 'conservative' },
    use_case: '企業 production Go (strict + conservative)',
    values: {
      confidence_threshold: '0.7',
      confidence_required: 'true',
      review_required_design: 'true',
      review_required_test: 'true',
      review_required_module: 'true',
      review_required_system: 'true',
      review_required_security: 'true',
      review_min_count_design: '5',
      review_min_count_test: '7',
      review_min_count_module: '3',
      review_min_count_system: '3',
      review_iteration_max: '5',
      feature_gateguard_enabled: 'true',
      feature_workflow_enforcement_enabled: 'true',
      feature_autonomous_action_guard_enabled: 'true',
    },
  },
  'harness-development': {
    display_name_ja: 'ハーネス開発専用',
    axes: { quality_level: 'inner_system', language_framework: 'mixed', git_workflow: 'main_protected', tdd_policy: 'recommended', review_intensity: 'strict', autonomy_level: 'moderate' },
    use_case: 'hirai-method 自体の開発 (dogfooding)',
    values: {
      confidence_threshold: '0.6',
      confidence_required: 'true',
      review_required_design: 'true',
      review_required_test: 'true',
      review_required_module: 'true',
      review_required_system: 'true',
      review_min_count_design: '3',
      review_min_count_test: '5',
      review_min_count_module: '2',
      review_min_count_system: '2',
      review_iteration_max: '5',
      feature_gateguard_enabled: 'true',
      feature_workflow_enforcement_enabled: 'true',
      feature_confidence_gate_enabled: 'true',
    },
  },
}

// ============================================================
// bash subprocess (hc-config.sh CLI 呼出) — DI 化 (C-unit-seam)
// ============================================================

// overrides.spawnFn: テスト用 DI seam (default は spawnSync)
// NF-10: timeout 時 timedOut フラグを返し、UI 側で "5s 超過" を明示できるようにする
function callHcConfig(args, overrides) {
  overrides = overrides || {}
  const spawnFn = overrides.spawnFn || spawnSync
  const result = spawnFn('bash', [HC_CONFIG_SCRIPT, ...args], {
    encoding: 'utf8',
    timeout: HC_SUBPROCESS_TIMEOUT_MS,
    cwd: REPO_ROOT,
  })
  // NF-10: timeout 判定
  //   spawnSync timeout: result.signal === 'SIGTERM' || error.code === 'ETIMEDOUT'
  //   exitCode === null (signal kill) も timeout 候補
  const timedOut =
    !!(result.error && (result.error.code === 'ETIMEDOUT' || result.error.code === 'ERR_CHILD_PROCESS_STDIO_MAXBUFFER')) ||
    result.signal === 'SIGTERM' ||
    result.status === null
  return {
    exitCode: result.status === null ? -1 : result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    error: result.error ? String(result.error.message) : null,
    timedOut,
  }
}

function hcGet(key, overrides) {
  const r = callHcConfig(['--get', key], overrides)
  if (r.exitCode !== 0) return null
  return r.stdout.replace(/\n$/, '')
}

function hcSet(key, value, overrides) {
  return callHcConfig(['--set', `${key}=${value}`], overrides)
}

// ============================================================
// NEW-C-1 fix: hcListAll() で全 key=value を 1 spawnSync で一括取得
// ============================================================
//
// 旧経路: /api/keys は 74 個別 hcGet (=74 spawnSync) を直列実行 → Node event loop ~370s block
// 新経路: bash subprocess を 1 回起動し、その内部で metadata.sh の key 一覧を取得後、
//   各 key について `hc-config.sh --get` を bash subprocess 内部 loop で呼び TSV 出力。
//   Node spawnSync は 1 回のみで、内部 bash の child process spawn は Node event loop を block しない。
//
// 出力 format: <key>\t<value>\n (改行終端、空 value は <key>\t\n)
// 失敗 key は entry なし (Node 側で undefined → null として扱う)
//
// overrides.spawnFn: テスト用 DI seam

let _keysValueCache = null

function invalidateKeysValueCache() {
  _keysValueCache = null
}

function hcListAll(overrides) {
  overrides = overrides || {}
  if (_keysValueCache && !overrides.bypassCache) return _keysValueCache
  const spawnFn = overrides.spawnFn || spawnSync
  // bash one-shot:
  //   1. metadata.sh source して全 key 一覧を取得 (hc_metadata_table | cut -f1)
  //   2. 各 key を hc-config.sh --get で取得し TSV 出力
  //   - bash 3.2 互換 (associative array 不使用)
  //   - エラー key は silent skip (空行ではなく entry 自体省略)
  const script = `
set -u
META="${path.join(SCRIPT_DIR, 'hc-config-metadata.sh').replace(/"/g, '\\"')}"
HCSCRIPT="${HC_CONFIG_SCRIPT.replace(/"/g, '\\"')}"
# shellcheck disable=SC1090
source "$META" 2>/dev/null || exit 1
keys=$(_hc_metadata_table 2>/dev/null | awk -F'\\t' 'NF>0 && $1!=""{print $1}')
[ -z "$keys" ] && exit 0
while IFS= read -r k; do
  [ -z "$k" ] && continue
  v=$(bash "$HCSCRIPT" --get "$k" 2>/dev/null) || continue
  # trailing newline は cmd_get で常に付与されるので除去
  v=\${v%$'\\n'}
  printf '%s\\t%s\\n' "$k" "$v"
done <<< "$keys"
`
  const r = spawnFn('bash', ['-c', script], {
    encoding: 'utf8',
    timeout: HC_SUBPROCESS_TIMEOUT_MS * 6, // 74 key 内部 fork ぶん拡張 (30s)
    cwd: REPO_ROOT,
  })
  if (r.status !== 0 && !r.stdout) return {}
  const lines = (r.stdout || '').split('\n').filter((l) => l.length > 0)
  const map = {}
  for (const line of lines) {
    const idx = line.indexOf('\t')
    if (idx === -1) continue
    const key = line.slice(0, idx)
    const value = line.slice(idx + 1)
    map[key] = value
  }
  if (!overrides.bypassCache) {
    _keysValueCache = map
  }
  return map
}

// ============================================================
// metadata cache (H-1: process-lifetime cache、/api/set で invalidate)
// ============================================================

let _metadataCache = null

function invalidateMetadataCache() {
  _metadataCache = null
  // NEW-C-1: keys-value cache も同期 invalidate (一貫性保証)
  invalidateKeysValueCache()
}

// _hc_metadata_table 全体を一括取得 (74 行 TSV) — bash 経由で一度だけ source して dump
// overrides.spawnFn: テスト用 DI seam
// overrides.bypassCache: cache を無視して fresh load (テスト用)
function loadMetadata(overrides) {
  overrides = overrides || {}
  if (_metadataCache && !overrides.bypassCache) return _metadataCache
  const spawnFn = overrides.spawnFn || spawnSync
  const script = `source "${path.join(SCRIPT_DIR, 'hc-config-metadata.sh')}" && _hc_metadata_table`
  const r = spawnFn('bash', ['-c', script], {
    encoding: 'utf8',
    timeout: HC_SUBPROCESS_TIMEOUT_MS,
  })
  if (r.status !== 0) return []
  const lines = (r.stdout || '').split('\n').filter((l) => l.length > 0)
  const result = lines.map((line) => {
    const parts = line.split('\t')
    return {
      key: parts[0] || '',
      category: parts[1] || '',
      description: parts[2] || '',
      effect: parts[3] || '',
    }
  })
  if (!overrides.bypassCache) {
    _metadataCache = result
  }
  return result
}

// known key set (H-11: /api/set whitelist 検証)
function getKnownKeys(overrides) {
  const md = loadMetadata(overrides)
  return new Set(md.map((m) => m.key).filter((k) => k.length > 0))
}

// effect lookup helper (draft §3 diff table effect 列)
function getEffectMap(overrides) {
  const md = loadMetadata(overrides)
  const map = {}
  for (const m of md) {
    if (m.key) map[m.key] = m.effect || ''
  }
  return map
}

// ============================================================
// NF-13: history stamp 生成 (pid + counter で同 ms 衝突回避)
// ============================================================

let _historyStampCounter = 0

function nextHistoryStamp() {
  _historyStampCounter = (_historyStampCounter + 1) % 1000000
  const iso = new Date().toISOString().replace(/[:.]/g, '-')
  return `${iso}-${process.pid}-${_historyStampCounter}`
}

// ============================================================
// NF-6: history file cleanup (最大 HISTORY_MAX_FILES 件、古い順削除)
// ============================================================

function cleanupHistoryFiles() {
  try {
    if (!fs.existsSync(HISTORY_DIR)) return
    const files = fs
      .readdirSync(HISTORY_DIR)
      .filter((f) => f.endsWith('.json'))
      .sort() // 名前順 (= 時系列順、ISO stamp prefix のため)
    if (files.length <= HISTORY_MAX_FILES) return
    const excess = files.length - HISTORY_MAX_FILES
    for (let i = 0; i < excess; i++) {
      try {
        fs.unlinkSync(path.join(HISTORY_DIR, files[i]))
      } catch (_) {
        // cleanup 失敗は silent skip (本流 apply に影響させない)
      }
    }
  } catch (_) {
    // dir 読み取り失敗も silent (本流に影響させない)
  }
}

// ============================================================
// preset diff 計算 / apply (atomic) / rollback (chain repair)
// ============================================================

// H-12 + draft §3: diff の changed 判定は hcGet 成功 + 値差分の AND
//   hcGet が null (get 失敗) なら changed: false に降格 (apply 対象から除外)
//   effect: metadata から lookup
function computePresetDiff(presetName, overrides) {
  const preset = PRESETS[presetName]
  if (!preset) return null
  const effectMap = getEffectMap(overrides)
  const changes = []
  for (const [key, newVal] of Object.entries(preset.values)) {
    const currentVal = hcGet(key, overrides)
    const effect = effectMap[key] || ''
    if (currentVal === null) {
      // hcGet 失敗 → changed: false に降格 + error 注記 (UI 側で skip 表示)
      changes.push({
        key,
        current: '<unknown>',
        new: String(newVal),
        changed: false,
        effect,
        error: 'hc-config --get failed (skipped)',
      })
      continue
    }
    const changed = String(currentVal) !== String(newVal)
    changes.push({
      key,
      current: String(currentVal),
      new: String(newVal),
      changed,
      effect,
    })
  }
  return { preset: presetName, axes: preset.axes, use_case: preset.use_case, changes }
}

// C-atomic: 2-phase atomic apply
//   phase 1: 全変更対象 key の現在値を snapshot
//   phase 2: hcSet 順次実行、N 番目失敗で snapshot から rollback
//
// NF-2/9 fix: history write 失敗時、yml 適用済みを snapshot から rollback (silent data loss 防止)
// NF-13 fix: history stamp に pid + counter 追加 (同 ms 衝突回避)
function applyPreset(presetName, skipKeys, overrides) {
  const diff = computePresetDiff(presetName, overrides)
  if (!diff) return { ok: false, error: 'unknown preset' }
  const skipSet = new Set(skipKeys || [])

  // phase 1: snapshot 対象 key 抽出 + 現在値確定
  const targets = []
  const snapshot = {}
  for (const change of diff.changes) {
    if (!change.changed) continue
    if (skipSet.has(change.key)) continue
    targets.push(change)
    snapshot[change.key] = change.current
  }

  // phase 2: 順次 apply、失敗で全件 rollback
  const applied = []
  let aborted = null
  for (const change of targets) {
    const r = hcSet(change.key, change.new, overrides)
    if (r.exitCode === 0) {
      applied.push({ key: change.key, from: change.current, to: change.new })
    } else {
      aborted = { key: change.key, from: change.current, to: change.new, stderr: r.stderr }
      break
    }
  }

  // C-atomic phase 2 abort 時の rollback (snapshot 復元)
  // NF-3: rollback restore 順序を LIFO (apply 逆順) で実行 (依存 key 不整合最小化)
  const rolledBack = []
  const rollbackFailed = []
  if (aborted) {
    const reverseApplied = applied.slice().reverse()
    for (const a of reverseApplied) {
      const r = hcSet(a.key, a.from, overrides)
      if (r.exitCode === 0) {
        rolledBack.push(a.key)
      } else {
        rollbackFailed.push({ key: a.key, target: a.from, stderr: r.stderr })
      }
    }
  }

  // history 保存 (snapshot 込み、rollback chain 用)
  try {
    if (!fs.existsSync(HISTORY_DIR)) {
      fs.mkdirSync(HISTORY_DIR, { recursive: true })
    }
  } catch (e) {
    // NF-2/9: history dir create 失敗 → snapshot rollback 実行 (apply 済 yml を元に戻す)
    const dirRecover = rollbackAppliedFromSnapshot(applied, snapshot, overrides)
    return {
      ok: false,
      error: 'history dir create failed: ' + e.message,
      applied: 0,
      failed: aborted ? 1 : 0,
      rolled_back_on_history_failure: dirRecover.recovered,
      rollback_failed_on_history_failure: dirRecover.failed,
    }
  }
  // NF-13: pid + counter で stamp unique 化
  const stamp = nextHistoryStamp()
  const histFile = path.join(HISTORY_DIR, `${stamp}-${presetName}.json`)
  const histPayload = {
    preset: presetName,
    applied_at: new Date().toISOString(),
    type: 'apply',
    axes: diff.axes,
    use_case: diff.use_case,
    snapshot, // C-atomic: rollback / chain 用に全対象 key の元値
    targets: targets.map((t) => ({ key: t.key, from: t.current, to: t.new })),
    applied: aborted ? [] : applied, // abort 時は実質 0 件 (rollback 済)
    failed: aborted ? [aborted] : [],
    rolled_back: rolledBack,
    rollback_failed: rollbackFailed,
    skipped: Array.from(skipSet),
  }
  try {
    // C-atomic write: tmp → rename で history file 自体の atomic 保証
    const tmpFile = `${histFile}.tmp`
    fs.writeFileSync(tmpFile, JSON.stringify(histPayload, null, 2))
    fs.renameSync(tmpFile, histFile)
  } catch (e) {
    // NF-2/9: history write 失敗 → snapshot から apply 済 yml を rollback
    //   abort 経由なら applied は既に rollback 済なので no-op
    //   abort なし (= 全 key 成功) なら applied から snapshot 復元
    const writeRecover = rollbackAppliedFromSnapshot(applied, snapshot, overrides)
    return {
      ok: false,
      error: 'history_write_failed',
      detail: e.message,
      applied: 0,
      failed: aborted ? 1 : 0,
      rolled_back_on_history_failure: writeRecover.recovered,
      rollback_failed_on_history_failure: writeRecover.failed,
      message:
        writeRecover.failed.length === 0
          ? 'history write failed, yml was rolled back to original state'
          : `history write failed and partial rollback occurred (${writeRecover.failed.length} keys failed to restore)`,
    }
  }

  // NF-6: history write 成功後に cleanup (古い分削除、本流に影響させない)
  cleanupHistoryFiles()

  // H-7: partial failure は ok:false だが 200 OK (router 側で判定)
  if (aborted) {
    return {
      ok: false,
      partial: true,
      applied: 0,
      failed: 1,
      rolled_back: rolledBack.length,
      rollback_failed: rollbackFailed.length,
      skipped: skipSet.size,
      history_file: path.basename(histFile),
      aborted_at: aborted,
      message: `apply aborted at key=${aborted.key}, ${rolledBack.length} keys rolled back`,
    }
  }
  return {
    ok: true,
    applied: applied.length,
    failed: 0,
    skipped: skipSet.size,
    history_file: path.basename(histFile),
  }
}

// NF-2/9 helper: history dir create / write 失敗時、apply 済 yml を snapshot から復元
//   LIFO 順 (apply 逆順) で hcSet を呼び元値に戻す
//   返却: { recovered: [key, ...], failed: [{ key, target, stderr }, ...] }
function rollbackAppliedFromSnapshot(applied, snapshot, overrides) {
  const recovered = []
  const failed = []
  const reverseApplied = applied.slice().reverse()
  for (const a of reverseApplied) {
    const original = snapshot[a.key]
    if (original === undefined) {
      // snapshot 不在 = 復元不可 (発生条件理論上なし、防御的に記録)
      failed.push({ key: a.key, target: '<unknown>', stderr: 'snapshot entry missing' })
      continue
    }
    const r = hcSet(a.key, original, overrides)
    if (r.exitCode === 0) {
      recovered.push(a.key)
    } else {
      failed.push({ key: a.key, target: original, stderr: r.stderr })
    }
  }
  return { recovered, failed }
}

function listHistory() {
  if (!fs.existsSync(HISTORY_DIR)) return []
  const files = fs.readdirSync(HISTORY_DIR).filter((f) => f.endsWith('.json')).sort().reverse()
  return files.map((f) => {
    try {
      const content = JSON.parse(fs.readFileSync(path.join(HISTORY_DIR, f), 'utf8'))
      return {
        timestamp: f.replace(/\.json$/, ''),
        preset: content.preset,
        type: content.type || 'apply',
        applied_at: content.applied_at,
        applied_count: (content.applied || []).length,
        failed_count: (content.failed || []).length,
        rolled_back_count: (content.rolled_back || []).length,
      }
    } catch (e) {
      return { timestamp: f.replace(/\.json$/, ''), error: String(e.message) }
    }
  })
}

// C-rollback-chain: rollback 実行時に rollback 前の現在値を snapshot として
// 新規 history entry に保存 (type: 'rollback')。これにより rollback chain で
// 何度でも戻れる構造を確保。
// C-traversal: timestamp は path.basename + regex 二重防御。
// NF-3: rollback 内 restore も LIFO 順 (applied 逆順) で実行 (依存 key 不整合最小化)
// NF-13: chain history stamp も pid + counter で unique 化
function rollbackHistory(timestamp, overrides) {
  // C-traversal: path traversal 防止
  if (!ROLLBACK_TS_REGEX.test(timestamp)) {
    return { ok: false, error: 'invalid timestamp format' }
  }
  const safeTs = path.basename(timestamp)
  if (safeTs !== timestamp || safeTs.length === 0) {
    return { ok: false, error: 'invalid timestamp (basename mismatch)' }
  }

  const histFile = path.join(HISTORY_DIR, `${safeTs}.json`)
  // 念のため normalize して HISTORY_DIR 内に閉じ込め確認
  const normalized = path.normalize(histFile)
  if (!normalized.startsWith(HISTORY_DIR + path.sep)) {
    return { ok: false, error: 'path traversal detected' }
  }
  if (!fs.existsSync(normalized)) return { ok: false, error: 'history not found' }

  let payload
  try {
    payload = JSON.parse(fs.readFileSync(normalized, 'utf8'))
  } catch (e) {
    return { ok: false, error: 'history parse failed: ' + e.message }
  }

  // rollback 前の現在値を snapshot (chain 修復用)
  const appliedTargets = payload.applied || []
  const rollbackPreSnapshot = {}
  for (const change of appliedTargets) {
    const cur = hcGet(change.key, overrides)
    rollbackPreSnapshot[change.key] = cur === null ? '<unknown>' : cur
  }

  // NF-3: LIFO 順 (apply 逆順) で restore
  const targets = appliedTargets.slice().reverse()
  const restored = []
  const failed = []
  for (const change of targets) {
    const r = hcSet(change.key, change.from, overrides)
    if (r.exitCode === 0) restored.push({ key: change.key, restored_to: change.from })
    else failed.push({ key: change.key, target: change.from, stderr: r.stderr })
  }

  // chain 修復: rollback 自体を新規 history entry として記録
  try {
    if (!fs.existsSync(HISTORY_DIR)) {
      fs.mkdirSync(HISTORY_DIR, { recursive: true })
    }
    // NF-13: chain stamp も pid + counter で unique 化
    const stamp = nextHistoryStamp()
    const chainFile = path.join(HISTORY_DIR, `${stamp}-rollback-of-${safeTs}.json`)
    const chainPayload = {
      preset: payload.preset || '<unknown>',
      applied_at: new Date().toISOString(),
      type: 'rollback',
      rolled_back_from: safeTs,
      snapshot: rollbackPreSnapshot, // rollback 前の値 (= chain 用)
      // applied フィールドは「rollback chain で更に戻る場合の target」となるよう
      // 「rollback 前値 → rollback 後値」を逆向きで記録 (rollback の rollback で
      // 元 apply 直後状態に復帰可能)
      applied: Object.entries(rollbackPreSnapshot).map(([k, v]) => {
        // rollback で k は change.from (元の preset 適用前値) に戻った
        const original = appliedTargets.find((t) => t.key === k)
        return {
          key: k,
          from: v, // rollback 直前 = preset apply 後の状態
          to: original ? original.from : v, // rollback 直後 = preset apply 前の状態
        }
      }),
      failed,
      restored,
    }
    const tmpFile = `${chainFile}.tmp`
    fs.writeFileSync(tmpFile, JSON.stringify(chainPayload, null, 2))
    fs.renameSync(tmpFile, chainFile)
    // NF-6: chain write 後も cleanup
    cleanupHistoryFiles()
    return {
      ok: failed.length === 0,
      restored: restored.length,
      failed: failed.length,
      failures: failed,
      chain_history_file: path.basename(chainFile),
    }
  } catch (e) {
    // chain 書込失敗でも restore 結果は返す (degraded)
    return {
      ok: failed.length === 0,
      restored: restored.length,
      failed: failed.length,
      failures: failed,
      chain_history_error: String(e.message),
    }
  }
}

// ============================================================
// task-63 Step 4 案 C: getCurrentPreset (values field 完全一致 subset 判定)
// ============================================================
//
// 仕様 (task-63 Step 4 spec、user 確定要求「プリセット名保存不要」2026-05-29):
//   1. 現在 yml の全 key 値を hcListAll() で取得 (1 spawn、cache hit で 0 spawn)
//   2. PRESETS (built-in 10 件) の各 preset values と current yml を subset 一致判定
//      - 各 preset の values 全 entry について current yml と一致するかを確認
//      - preset values は yml の部分集合 (subset)、yml の他 key は無視
//   3. 完全一致 (subset): { name: <preset key>, display_name_ja: <日本語名>, match_type: 'preset' }
//   4. 不一致: { name: 'custom', display_name_ja: '未保存変更あり', match_type: 'unsaved' }
//
// task-65 (案 A): axes field を additive に復活。matched preset の axes メタデータ (6 軸) を返す。
//   既存 field (name / display_name_ja / match_type) は不変 (後方互換)。
//   preset 一致時: axes = matched preset の axes object (6 key)。
//   unsaved 時: axes = null (preset 外では axis 値が一意でないため。UI 側でカスタム表示に切替)。
//   (task-63 Step 4 A3 で撤去した axes 返却を、6 軸 read-only 表示の data contract gap 解消のため復活)
//
// overrides.spawnFn: DI seam (テスト用)
function getCurrentPreset(overrides) {
  overrides = overrides || {}
  // 1. 現在 yml 全 key 値を取得 (hcListAll 経由、cache hit で 0 spawn)
  const allValues = hcListAll(overrides)

  // 2. PRESETS (built-in only、custom-* は廃止) を順次照合
  for (const [key, p] of Object.entries(PRESETS)) {
    if (valuesSubsetEqual(p.values, allValues)) {
      return {
        name: key,
        display_name_ja: p.display_name_ja || key,
        match_type: 'preset',
        // task-65 (iter2 M1): 空 axes object が all-`—` table に退化する原 bug 再発を防ぐため、
        //   axes が空 / 不在なら null を返す (UI 側でカスタム表示に切替、6 軸 table を描かない)。
        axes: (p.axes && Object.keys(p.axes).length) ? p.axes : null,
      }
    }
  }

  // 3. 一致なし (unsaved): axes は preset 外で一意でない → null (UI 側でカスタム表示)
  return { name: 'custom', display_name_ja: '未保存変更あり', match_type: 'unsaved', axes: null }
}

// task-63 Step 4 A2: values subset 完全一致判定
//   presetValues の全 key について currentValues に同 key + 同 value が存在するかを check。
//   currentValues に preset 不在 key があっても OK (subset 関係のみ確認)。
//   string 比較、yml 形式差異吸収のため trim。
function valuesSubsetEqual(presetValues, currentValues) {
  if (!presetValues || typeof presetValues !== 'object') return false
  if (!currentValues || typeof currentValues !== 'object') return false
  for (const [k, pv] of Object.entries(presetValues)) {
    if (!Object.prototype.hasOwnProperty.call(currentValues, k)) return false
    const cv = currentValues[k]
    if (cv === undefined || cv === null) return false
    if (String(pv).trim() !== String(cv).trim()) return false
  }
  return true
}

// ============================================================
// HTTP helpers
// ============================================================

// L-2: Buffer.from で生成し Content-Length は buffer.length を使う
function sendJson(res, statusCode, payload) {
  const buf = Buffer.from(JSON.stringify(payload), 'utf8')
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': buf.length,
  })
  res.end(buf)
}

function sendText(res, statusCode, text, contentType) {
  const buf = Buffer.from(text, 'utf8')
  res.writeHead(statusCode, {
    'Content-Type': contentType || 'text/plain; charset=utf-8',
    'Content-Length': buf.length,
  })
  res.end(buf)
}

// H-3: destroyed flag で reject 二重呼び出し防止
function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = []
    let total = 0
    let settled = false
    const safeReject = (err) => {
      if (settled) return
      settled = true
      reject(err)
    }
    const safeResolve = (val) => {
      if (settled) return
      settled = true
      resolve(val)
    }
    req.on('data', (c) => {
      if (settled) return
      chunks.push(c)
      total += c.length
      if (total > 1024 * 1024) {
        safeReject(new Error('body too large'))
        try { req.destroy() } catch (_) { /* ignore */ }
      }
    })
    req.on('end', () => {
      if (settled) return
      try {
        const body = Buffer.concat(chunks).toString('utf8')
        safeResolve(body.length === 0 ? {} : JSON.parse(body))
      } catch (e) {
        safeReject(e)
      }
    })
    req.on('error', safeReject)
    req.on('close', () => {
      if (!settled) safeReject(new Error('connection closed'))
    })
  })
}

function serveStatic(req, res, relativePath) {
  // path traversal 防止
  const safe = path.normalize(relativePath).replace(/^(\.\.[\\/])+/, '')
  const full = path.join(STATIC_DIR, safe)
  if (!full.startsWith(STATIC_DIR)) {
    sendText(res, 403, 'forbidden')
    return
  }
  if (!fs.existsSync(full) || !fs.statSync(full).isFile()) {
    sendText(res, 404, 'not found')
    return
  }
  const ext = path.extname(full).toLowerCase()
  const mime = MIME_TYPES[ext] || 'application/octet-stream'
  const content = fs.readFileSync(full)
  res.writeHead(200, { 'Content-Type': mime, 'Content-Length': content.length })
  res.end(content)
}

// NF-8 helper: error message から internal abs path leak を除外
//   REPO_ROOT を <repo> に置換 + HOME を <home> に置換
function sanitizeErrorMessage(message) {
  if (!message) return ''
  let s = String(message)
  // REPO_ROOT 置換 (最も特異)
  if (REPO_ROOT && REPO_ROOT.length > 0) {
    s = s.split(REPO_ROOT).join('<repo>')
  }
  const home = os.homedir()
  if (home && home.length > 0) {
    s = s.split(home).join('<home>')
  }
  return s
}

// ============================================================
// router (L-3: url.parse → new URL)
// ============================================================

async function handleRequest(req, res) {
  // L-3: deprecated url.parse → WHATWG URL
  const reqUrl = new URL(req.url, `http://${HOST}`)
  const pathname = reqUrl.pathname || '/'

  // GET / → redirect
  if (req.method === 'GET' && pathname === '/') {
    res.writeHead(302, { Location: '/static/index.html' })
    res.end()
    return
  }

  // GET /static/*
  if (req.method === 'GET' && pathname.startsWith('/static/')) {
    serveStatic(req, res, pathname.slice('/static/'.length))
    return
  }

  // GET /api/current-preset (task-63 Step 4 案 C、values subset 完全一致判定)
  //   現在 yml 全 key 値 vs PRESETS (built-in 10) values を subset 完全一致判定し、
  //   { name, display_name_ja, match_type, axes } を返却。
  //   task-65 (案 A) で axes を additive に復活: matched preset の 6 軸メタデータを返す
  //   (top view の 6 軸 read-only table 描画用)。unsaved 時は axes=null。
  //   - 一致: name=<preset key> + display_name_ja=preset 日本語名 + match_type='preset' + axes=preset の 6 軸 object
  //   - 不一致: name='custom' + display_name_ja='未保存変更あり' + match_type='unsaved' + axes=null
  if (req.method === 'GET' && pathname === '/api/current-preset') {
    const result = getCurrentPreset()
    sendJson(res, 200, result)
    return
  }

  // GET /api/categories
  if (req.method === 'GET' && pathname === '/api/categories') {
    const metadata = loadMetadata()
    const counts = {}
    for (const m of metadata) {
      counts[m.category] = (counts[m.category] || 0) + 1
    }
    // LOW fix 1 (case-03): category name が空文字列 / 'undefined' の場合は表示上の不整合を防ぐため
    //   name field として返す (client 側で fallback 表示する)。filter はしない (key 件数は正確に保つ)。
    const categories = Object.entries(counts).map(([name, count]) => ({ name: name || '', key_count: count }))
    sendJson(res, 200, { categories })
    return
  }

  // GET /api/keys (NEW-C-1 fix: hcListAll で 1 spawn に集約、74 spawn 370s block 解消)
  if (req.method === 'GET' && pathname === '/api/keys') {
    const metadata = loadMetadata()
    const categoryFilter = reqUrl.searchParams.get('category')
    const filtered = categoryFilter ? metadata.filter((m) => m.category === categoryFilter) : metadata
    // NEW-C-1: hcListAll() で全 key 値を 1 spawnSync で取得 (74 → 1)
    //   旧経路 (個別 hcGet ループ) を削除し、cache hit すれば spawn 0 件で即返却
    const allValues = hcListAll()
    const enriched = filtered.map((m) => {
      const value = Object.prototype.hasOwnProperty.call(allValues, m.key) ? allValues[m.key] : null
      return { ...m, current_value: value }
    })
    sendJson(res, 200, { keys: enriched, total: enriched.length })
    return
  }

  // GET /api/value/:key (個別 key、single hcGet 維持)
  // iter 6 A item 4 (MED): DI seam を明示 (integration test で spawnFn 差替可能化)
  if (req.method === 'GET' && pathname.startsWith('/api/value/')) {
    const key = decodeURIComponent(pathname.slice('/api/value/'.length))
    const current = hcGet(key, {})
    if (current === null) {
      sendJson(res, 404, { error: 'key not found or get failed', key })
      return
    }
    sendJson(res, 200, { key, current_value: current })
    return
  }

  // POST /api/set (H-11: known key whitelist + cache invalidate)
  if (req.method === 'POST' && pathname === '/api/set') {
    let body
    try {
      body = await readJsonBody(req)
    } catch (e) {
      sendJson(res, 400, { error: 'invalid JSON body', detail: sanitizeErrorMessage(e.message) })
      return
    }
    if (!body.key || body.value === undefined) {
      sendJson(res, 400, { error: 'key and value required' })
      return
    }
    // H-11: whitelist 検証
    const known = getKnownKeys()
    if (!known.has(body.key)) {
      sendJson(res, 400, { error: 'unknown key', key: body.key })
      return
    }
    // iter 6 A item 4 (MED): DI seam を明示 (integration test で spawnFn 差替可能化)
    const r = hcSet(body.key, String(body.value), {})
    if (r.exitCode !== 0) {
      // NF-10: timeout 明示
      const errPayload = {
        error: 'hc-config --set failed',
        stderr: sanitizeErrorMessage(r.stderr),
        exit_code: r.exitCode,
      }
      if (r.timedOut) errPayload.timed_out = true
      sendJson(res, 400, errPayload)
      return
    }
    // H-1: /api/set 成功で metadata cache invalidate
    //   (metadata 自体は変わらないが、enriched current_value が古くなるため
    //    /api/keys 経由 path でも fresh load させる)
    //   NEW-C-1: keysValueCache も同期 invalidate (invalidateMetadataCache 経由)
    invalidateMetadataCache()
    sendJson(res, 200, { ok: true, key: body.key, value: body.value })
    return
  }

  // GET /api/presets (task-63 Step 4 A3: axes_values 撤去、display_name_ja + use_case + affected_key_count のみ)
  //   custom preset 機能は task-63 Step 4 A1 で撤去済 (scanCustomPresets 呼出なし、PRESETS は built-in 10 件固定)
  if (req.method === 'GET' && pathname === '/api/presets') {
    const list = Object.entries(PRESETS).map(([name, p]) => ({
      name,
      display_name_ja: p.display_name_ja || name,
      use_case: p.use_case,
      affected_key_count: Object.keys(p.values).length,
    }))
    sendJson(res, 200, { presets: list, axes_schema: PRESET_AXES })
    return
  }

  // GET /api/preset/:name/diff (task-63 Step 4 A1: custom preset merge ロジック撤去、built-in 10 件のみ)
  const diffMatch = pathname.match(/^\/api\/preset\/([^/]+)\/diff$/)
  if (req.method === 'GET' && diffMatch) {
    const name = decodeURIComponent(diffMatch[1])
    const diff = computePresetDiff(name)
    if (!diff) {
      sendJson(res, 404, { error: 'unknown preset', preset: name })
      return
    }
    sendJson(res, 200, diff)
    return
  }

  // POST /api/preset/:name/apply (H-7: partial failure は 200 OK + body.ok:false)
  // task-63 Step 4 A1: custom preset merge ロジック撤去 (built-in 10 件のみ)
  const applyMatch = pathname.match(/^\/api\/preset\/([^/]+)\/apply$/)
  if (req.method === 'POST' && applyMatch) {
    const name = decodeURIComponent(applyMatch[1])
    let body
    try {
      body = await readJsonBody(req)
    } catch (e) {
      sendJson(res, 400, { error: 'invalid JSON body', detail: sanitizeErrorMessage(e.message) })
      return
    }
    const skipKeys = Array.isArray(body.skip_keys) ? body.skip_keys : []
    const result = applyPreset(name, skipKeys)
    if (result.error === 'unknown preset') {
      sendJson(res, 404, result)
      return
    }
    // H-7: result.ok=false でも部分失敗は 200 (body で client が判定)
    // 完全失敗 (preset 不存在 / history dir エラー等の致命的) のみ 5xx
    if (!result.ok && !result.partial && result.error) {
      // NF-8: history_write_failed は client に正常に伝えるため 500 ではなく 200 で返却
      //   (yml は rollback 済、UI 側で「history 不在で復旧不可」を表示できる)
      if (result.error === 'history_write_failed') {
        // cache invalidate (yml が rollback されたが念のため)
        invalidateMetadataCache()
        sendJson(res, 200, result)
        return
      }
      sendJson(res, 500, result)
      return
    }
    // H-1: apply 成功で cache invalidate
    if (result.ok || result.partial) {
      invalidateMetadataCache()
    }
    sendJson(res, 200, result)
    return
  }

  // task-63 Step 4 A1: POST /api/preset/save endpoint 撤去 (user 確定要求「プリセット名保存不要」2026-05-29)
  //   404 fallback で応答 (本 endpoint への request は handleRequest 末尾で 404 not found を返す)

  // GET /api/preset/history
  if (req.method === 'GET' && pathname === '/api/preset/history') {
    sendJson(res, 200, { history: listHistory() })
    return
  }

  // POST /api/preset/rollback/:timestamp (C-traversal + C-rollback-chain)
  const rollbackMatch = pathname.match(/^\/api\/preset\/rollback\/(.+)$/)
  if (req.method === 'POST' && rollbackMatch) {
    const ts = decodeURIComponent(rollbackMatch[1])
    // C-traversal: 早期 validation (rollbackHistory 内部でも二重検証)
    if (!ROLLBACK_TS_REGEX.test(ts)) {
      sendJson(res, 400, { error: 'invalid timestamp format' })
      return
    }
    const result = rollbackHistory(ts)
    if (result.error === 'history not found') {
      sendJson(res, 404, result)
      return
    }
    if (result.error === 'invalid timestamp format' || result.error === 'invalid timestamp (basename mismatch)' || result.error === 'path traversal detected') {
      sendJson(res, 400, result)
      return
    }
    if (!result.ok && result.error) {
      sendJson(res, 500, result)
      return
    }
    // chain 書込成功時に cache invalidate (rollback で yml 値変更されたため)
    invalidateMetadataCache()
    sendJson(res, 200, result)
    return
  }

  // 404 fallback
  sendJson(res, 404, { error: 'not found', path: pathname, method: req.method })
}

// ============================================================
// port 探索 + listen (H-4: error event 監視で TOCTOU 排除)
// ============================================================

function tryListen(server, port) {
  return new Promise((resolve, reject) => {
    let settled = false
    const onError = (err) => {
      if (settled) return
      settled = true
      server.removeListener('listening', onListen)
      reject(err)
    }
    const onListen = () => {
      if (settled) return
      settled = true
      server.removeListener('error', onError)
      resolve(port)
    }
    server.once('error', onError)
    server.once('listening', onListen)
    server.listen(port, HOST)
  })
}

async function findPortAndListen(server) {
  for (let port = PORT_MIN; port <= PORT_MAX; port++) {
    try {
      await tryListen(server, port)
      return port
    } catch (err) {
      if (err && (err.code === 'EADDRINUSE' || err.code === 'EACCES')) continue
      throw err
    }
  }
  throw new Error(`no free port in ${PORT_MIN}-${PORT_MAX}`)
}

// ============================================================
// browser auto-open
// ============================================================

function openBrowser(targetUrl) {
  const platform = os.platform()
  let cmd, args
  if (platform === 'darwin') { cmd = 'open'; args = [targetUrl] }
  else if (platform === 'linux') { cmd = 'xdg-open'; args = [targetUrl] }
  else if (platform === 'win32') { cmd = 'cmd'; args = ['/c', 'start', '', targetUrl] }
  else {
    console.log(`Open this URL manually: ${targetUrl}`)
    return
  }
  const r = spawnSync(cmd, args, { timeout: 3000, stdio: 'ignore' })
  if (r.status !== 0 || r.error) {
    console.log(`Browser auto-open failed. Open this URL manually: ${targetUrl}`)
  }
}

// ============================================================
// main
// ============================================================

async function main() {
  // M-P2: 起動時 REPO_ROOT 解決を stderr に明示出力
  console.error(`[hc-config-web-server] REPO_ROOT=${REPO_ROOT}`)
  console.error(`[hc-config-web-server] HC_CONFIG_SCRIPT=${HC_CONFIG_SCRIPT}`)
  if (!fs.existsSync(HC_CONFIG_SCRIPT)) {
    console.error(`[hc-config-web-server] WARN: HC_CONFIG_SCRIPT not found at resolved path`)
  }

  const server = http.createServer((req, res) => {
    handleRequest(req, res).catch((err) => {
      // NF-8: internal abs path leak 防止 (sanitize + stack trace 除外)
      console.error('handler error:', err && err.stack ? err.stack : err)
      if (!res.headersSent) {
        sendJson(res, 500, {
          error: 'internal error',
          detail: sanitizeErrorMessage(err && err.message ? err.message : String(err)),
        })
      }
    })
  })

  let port
  try {
    port = await findPortAndListen(server)
  } catch (err) {
    console.error(`Failed to start server: ${err.message}`)
    process.exit(1)
  }

  const fullUrl = `http://${HOST}:${port}/`
  console.log(`hc-config Web UI server started on ${fullUrl}`)
  console.log(`   Press Ctrl+C to stop.`)

  // CLI flag で auto-open 無効化
  const noOpen = process.argv.includes('--no-open') || process.env.HC_WEB_NO_OPEN === '1'
  if (!noOpen) {
    openBrowser(fullUrl)
  }

  const shutdown = (signal) => {
    console.log(`\nReceived ${signal}, shutting down.`)
    server.close(() => {
      console.log('bye.')
      process.exit(0)
    })
    // 強制終了 fallback
    setTimeout(() => process.exit(0), 2000).unref()
  }
  process.on('SIGINT', () => shutdown('SIGINT'))
  process.on('SIGTERM', () => shutdown('SIGTERM'))
}

if (require.main === module) {
  main().catch((err) => {
    console.error('fatal:', err)
    process.exit(1)
  })
}

// C-unit-seam: unit テスト用 seam (callHcConfig / loadMetadata / readJsonBody / serveStatic 追加)
// iter 4 A 追加 seam: hcListAll / invalidateKeysValueCache / nextHistoryStamp / cleanupHistoryFiles /
//   rollbackAppliedFromSnapshot / sanitizeErrorMessage
// task-63 Step 4 A4: savePreset / scanCustomPresets / isTestPollutionName / axesEqual 撤去、
//                    getCurrentPreset / valuesSubsetEqual を保持 (axesEqual → valuesSubsetEqual に rename)
module.exports = {
  PRESETS,
  PRESET_AXES,
  ROLLBACK_TS_REGEX,
  HISTORY_MAX_FILES,
  callHcConfig,
  hcGet,
  hcSet,
  hcListAll,
  invalidateKeysValueCache,
  loadMetadata,
  invalidateMetadataCache,
  getKnownKeys,
  getEffectMap,
  computePresetDiff,
  applyPreset,
  rollbackAppliedFromSnapshot,
  getCurrentPreset,    // task-63 Step 4 案 C
  valuesSubsetEqual,   // task-63 Step 4 案 C (helper、test seam)
  listHistory,
  rollbackHistory,
  readJsonBody,
  serveStatic,
  sendJson,
  sendText,
  sanitizeErrorMessage,
  nextHistoryStamp,
  cleanupHistoryFiles,
  handleRequest,
}
