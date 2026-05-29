#!/usr/bin/env node
// .claude/scripts/lib/hc-config-web-server.js — task-61 Step 5 iter 2 (領域 A fixes)
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
// API endpoint:
//   GET  /                          → redirect /static/index.html
//   GET  /static/*                  → static file serve (index.html / app.js / style.css)
//   GET  /api/keys                  → 74 key + metadata (現在値含む、bulk hcGet)
//   GET  /api/categories            → 6 category 一覧
//   GET  /api/value/:key            → 単一 key 現在値
//   POST /api/set                   → {key,value} → hc-config.sh --set
//   GET  /api/presets               → 10 preset 一覧 (6 軸 + 説明)
//   GET  /api/preset/:name/diff     → preset 適用差分 (effect 列含む)
//   POST /api/preset/:name/apply    → batch hc-config.sh --set + history 保存 (atomic)
//   POST /api/preset/save           → {name, axes} → .claude/presets/custom-<name>.yml 保存
//   GET  /api/preset/history        → 適用履歴一覧
//   POST /api/preset/rollback/:ts   → history rollback (chain 修復 + traversal 防止)
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
const HISTORY_DIR = path.join(REPO_ROOT, '.claude', '.preset-history')
const PRESETS_DIR = path.join(REPO_ROOT, '.claude', 'presets')

const PORT_MIN = 3060
const PORT_MAX = 3070
const HOST = '127.0.0.1'
const HC_SUBPROCESS_TIMEOUT_MS = 5000

// rollback timestamp validation (M-P3): ISO-8601 風 + preset name 区切り
//   実 history file 名 stem は `2026-05-29T12-34-56-789Z-poc-no-git` 形式 (toISOString の `:` / `.` を `-` 置換)
//   後段 path.basename も併用して path traversal を 2 重に防ぐ。
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
function callHcConfig(args, overrides) {
  overrides = overrides || {}
  const spawnFn = overrides.spawnFn || spawnSync
  const result = spawnFn('bash', [HC_CONFIG_SCRIPT, ...args], {
    encoding: 'utf8',
    timeout: HC_SUBPROCESS_TIMEOUT_MS,
    cwd: REPO_ROOT,
  })
  return {
    exitCode: result.status === null ? -1 : result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    error: result.error ? String(result.error.message) : null,
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
// metadata cache (H-1: process-lifetime cache、/api/set で invalidate)
// ============================================================

let _metadataCache = null

function invalidateMetadataCache() {
  _metadataCache = null
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
// history payload は applied / failed / snapshot / type を保存し
// rollbackHistory が chain 修復できる構造に。
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
  const rolledBack = []
  const rollbackFailed = []
  if (aborted) {
    for (const a of applied) {
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
    return {
      ok: false,
      error: 'history dir create failed: ' + e.message,
      applied: aborted ? 0 : applied.length,
      failed: aborted ? 1 : 0,
    }
  }
  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
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
    return {
      ok: false,
      error: 'history write failed: ' + e.message,
      applied: aborted ? 0 : applied.length,
      failed: aborted ? 1 : 0,
    }
  }

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
  const rollbackPreSnapshot = {}
  const targets = (payload.applied || [])
  for (const change of targets) {
    const cur = hcGet(change.key, overrides)
    rollbackPreSnapshot[change.key] = cur === null ? '<unknown>' : cur
  }

  // 各 applied entry の from 値に戻す
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
    const stamp = new Date().toISOString().replace(/[:.]/g, '-')
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
        const original = targets.find((t) => t.key === k)
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
// custom preset save (M-Q2 / draft §3.2)
// ============================================================

// POST /api/preset/save { name, axes } で .claude/presets/custom-<name>.yml を保存。
// 軽量 YAML 形式 (key: value、コメント先頭) で書出。
function savePreset(body) {
  if (!body || typeof body !== 'object') return { ok: false, error: 'body required' }
  const name = body.name
  const axes = body.axes
  if (!name || typeof name !== 'string') return { ok: false, error: 'name required (string)' }
  if (!/^[a-z][a-z0-9-]{1,40}$/.test(name)) {
    return { ok: false, error: 'name must match ^[a-z][a-z0-9-]{1,40}$' }
  }
  if (!axes || typeof axes !== 'object') return { ok: false, error: 'axes required (object)' }
  // axes 検証 (6 軸 + 値域)
  const axesByKey = {}
  for (const a of PRESET_AXES) axesByKey[a.key] = new Set(a.values)
  for (const [k, v] of Object.entries(axes)) {
    if (!axesByKey[k]) return { ok: false, error: `unknown axis: ${k}` }
    if (!axesByKey[k].has(v)) return { ok: false, error: `invalid value for ${k}: ${v}` }
  }
  try {
    if (!fs.existsSync(PRESETS_DIR)) {
      fs.mkdirSync(PRESETS_DIR, { recursive: true })
    }
    const filePath = path.join(PRESETS_DIR, `custom-${name}.yml`)
    // M-Q2: path traversal 二重防御
    const normalized = path.normalize(filePath)
    if (!normalized.startsWith(PRESETS_DIR + path.sep)) {
      return { ok: false, error: 'path traversal detected' }
    }
    const lines = [
      `# .claude/presets/custom-${name}.yml`,
      `# preset: custom-${name}`,
      `# saved_at: ${new Date().toISOString()}`,
      `# axes:`,
    ]
    for (const a of PRESET_AXES) {
      const v = axes[a.key]
      if (v !== undefined) lines.push(`#   ${a.key}: ${v}`)
    }
    lines.push('')
    // axes を yml に展開
    for (const a of PRESET_AXES) {
      const v = axes[a.key]
      if (v !== undefined) lines.push(`${a.key}: ${v}`)
    }
    const content = lines.join('\n') + '\n'
    const tmpFile = `${normalized}.tmp`
    fs.writeFileSync(tmpFile, content)
    fs.renameSync(tmpFile, normalized)
    return { ok: true, name: `custom-${name}`, path: path.relative(REPO_ROOT, normalized) }
  } catch (e) {
    return { ok: false, error: 'write failed: ' + e.message }
  }
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

  // GET /api/categories
  if (req.method === 'GET' && pathname === '/api/categories') {
    const metadata = loadMetadata()
    const counts = {}
    for (const m of metadata) {
      counts[m.category] = (counts[m.category] || 0) + 1
    }
    const categories = Object.entries(counts).map(([name, count]) => ({ name, key_count: count }))
    sendJson(res, 200, { categories })
    return
  }

  // GET /api/keys (H-1: cache + bulk hcGet 不要、metadata の key 列をそのまま使う)
  if (req.method === 'GET' && pathname === '/api/keys') {
    const metadata = loadMetadata()
    const categoryFilter = reqUrl.searchParams.get('category')
    const filtered = categoryFilter ? metadata.filter((m) => m.category === categoryFilter) : metadata
    // H-1: current_value 同期取得は必要だが、cache 化で metadata.sh source は 1 回のみ
    //   個別 hcGet は spawnSync N 回必要 (個別 key の env override 反映のため)、
    //   ここは仕様上避けられない (--list で全値出るが key 抽出に正規表現必要)
    const enriched = filtered.map((m) => {
      const current = hcGet(m.key)
      return { ...m, current_value: current }
    })
    sendJson(res, 200, { keys: enriched, total: enriched.length })
    return
  }

  // GET /api/value/:key
  if (req.method === 'GET' && pathname.startsWith('/api/value/')) {
    const key = decodeURIComponent(pathname.slice('/api/value/'.length))
    const current = hcGet(key)
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
      sendJson(res, 400, { error: 'invalid JSON body', detail: String(e.message) })
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
    const r = hcSet(body.key, String(body.value))
    if (r.exitCode !== 0) {
      sendJson(res, 400, { error: 'hc-config --set failed', stderr: r.stderr, exit_code: r.exitCode })
      return
    }
    // H-1: /api/set 成功で metadata cache invalidate
    //   (metadata 自体は変わらないが、enriched current_value が古くなるため
    //    /api/keys 経由 path でも fresh load させる)
    invalidateMetadataCache()
    sendJson(res, 200, { ok: true, key: body.key, value: body.value })
    return
  }

  // GET /api/presets
  if (req.method === 'GET' && pathname === '/api/presets') {
    const list = Object.entries(PRESETS).map(([name, p]) => ({
      name,
      axes: p.axes,
      use_case: p.use_case,
      affected_key_count: Object.keys(p.values).length,
    }))
    sendJson(res, 200, { presets: list, axes_schema: PRESET_AXES })
    return
  }

  // GET /api/preset/:name/diff
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
  const applyMatch = pathname.match(/^\/api\/preset\/([^/]+)\/apply$/)
  if (req.method === 'POST' && applyMatch) {
    const name = decodeURIComponent(applyMatch[1])
    let body
    try {
      body = await readJsonBody(req)
    } catch (e) {
      sendJson(res, 400, { error: 'invalid JSON body', detail: String(e.message) })
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

  // POST /api/preset/save (M-Q2 / draft §3.2)
  if (req.method === 'POST' && pathname === '/api/preset/save') {
    let body
    try {
      body = await readJsonBody(req)
    } catch (e) {
      sendJson(res, 400, { error: 'invalid JSON body', detail: String(e.message) })
      return
    }
    const result = savePreset(body)
    sendJson(res, result.ok ? 200 : 400, result)
    return
  }

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
      console.error('handler error:', err)
      if (!res.headersSent) {
        sendJson(res, 500, { error: 'internal error', detail: String(err.message) })
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
module.exports = {
  PRESETS,
  PRESET_AXES,
  ROLLBACK_TS_REGEX,
  callHcConfig,
  hcGet,
  hcSet,
  loadMetadata,
  invalidateMetadataCache,
  getKnownKeys,
  getEffectMap,
  computePresetDiff,
  applyPreset,
  savePreset,
  listHistory,
  rollbackHistory,
  readJsonBody,
  serveStatic,
  sendJson,
  sendText,
  handleRequest,
}
