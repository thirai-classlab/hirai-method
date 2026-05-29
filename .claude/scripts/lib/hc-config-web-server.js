#!/usr/bin/env node
// .claude/scripts/lib/hc-config-web-server.js — task-61 Step 2
//
// 目的:
//   hc-config.sh interactive (TTY 経路 default) の Web UI 化。
//   Node.js 標準 module のみ (http / child_process / fs / path / os / url)、npm dep 0。
//
// 設計:
//   - localhost (127.0.0.1) only bind、外部 access 禁止
//   - port 3060-3070 自動 detect
//   - 全ての yml 書込は hc-config.sh CLI 経由 (atomic backup + type validation を再利用)
//   - 10 named preset を server.js 内 hardcode (draft §3.4 AI 推奨)
//   - SIGINT graceful shutdown
//
// API endpoint:
//   GET  /                          → redirect /static/index.html
//   GET  /static/*                  → static file serve (index.html / app.js / style.css)
//   GET  /api/keys                  → 74 key + metadata (現在値含む)
//   GET  /api/categories            → 6 category 一覧
//   GET  /api/value/:key            → 単一 key 現在値
//   POST /api/set                   → {key,value} → hc-config.sh --set
//   GET  /api/presets               → 10 preset 一覧 (6 軸 + 説明)
//   GET  /api/preset/:name/diff     → preset 適用差分
//   POST /api/preset/:name/apply    → batch hc-config.sh --set + history 保存
//   GET  /api/preset/history        → 適用履歴一覧
//   POST /api/preset/rollback/:ts   → history rollback
//
// 起源: docs/draft/hc-config-web-ui.md §3.1 §3.2 §3.4 / docs/tasks/task-61-hc-config-web-ui.md Step 2

'use strict'

const http = require('http')
const { spawnSync } = require('child_process')
const fs = require('fs')
const path = require('path')
const os = require('os')
const url = require('url')

// ============================================================
// 定数 / パス解決
// ============================================================

const SCRIPT_DIR = __dirname // .claude/scripts/lib
const HC_CONFIG_SCRIPT = path.resolve(SCRIPT_DIR, '..', 'hc-config.sh')
const REPO_ROOT = path.resolve(SCRIPT_DIR, '..', '..', '..')
const STATIC_DIR = path.join(SCRIPT_DIR, 'hc-config-web-ui')
const HISTORY_DIR = path.join(REPO_ROOT, '.claude', '.preset-history')

const PORT_MIN = 3060
const PORT_MAX = 3070
const HOST = '127.0.0.1'
const HC_SUBPROCESS_TIMEOUT_MS = 5000

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
//
// 6 軸 (preset 分類軸):
//   quality_level         : poc | inner_system | production_service
//   language_framework    : mixed | typescript | python | rust | go
//   git_workflow          : none | unrestricted | main_protected | main_stg_protected
//   tdd_policy            : optional | recommended | mandatory
//   review_intensity      : minimum | standard | strict
//   autonomy_level        : aggressive | moderate | conservative

const PRESET_AXES = [
  { key: 'quality_level', values: ['poc', 'inner_system', 'production_service'] },
  { key: 'language_framework', values: ['mixed', 'typescript', 'python', 'rust', 'go'] },
  { key: 'git_workflow', values: ['none', 'unrestricted', 'main_protected', 'main_stg_protected'] },
  { key: 'tdd_policy', values: ['optional', 'recommended', 'mandatory'] },
  { key: 'review_intensity', values: ['minimum', 'standard', 'strict'] },
  { key: 'autonomy_level', values: ['aggressive', 'moderate', 'conservative'] },
]

// 各 preset は 6 軸 + 影響 key (yml key → value) + use_case を持つ
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
// bash subprocess (hc-config.sh CLI 呼出)
// ============================================================

function callHcConfig(args) {
  const result = spawnSync('bash', [HC_CONFIG_SCRIPT, ...args], {
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

function hcGet(key) {
  const r = callHcConfig(['--get', key])
  if (r.exitCode !== 0) return null
  return r.stdout.replace(/\n$/, '')
}

function hcSet(key, value) {
  return callHcConfig(['--set', `${key}=${value}`])
}

// _hc_metadata_table 全体を一括取得 (74 行 TSV) — bash 経由で一度だけ source して dump
function loadMetadata() {
  const script = `source "${path.join(SCRIPT_DIR, 'hc-config-metadata.sh')}" && _hc_metadata_table`
  const r = spawnSync('bash', ['-c', script], {
    encoding: 'utf8',
    timeout: HC_SUBPROCESS_TIMEOUT_MS,
  })
  if (r.status !== 0) return []
  const lines = (r.stdout || '').split('\n').filter((l) => l.length > 0)
  return lines.map((line) => {
    const parts = line.split('\t')
    return {
      key: parts[0] || '',
      category: parts[1] || '',
      description: parts[2] || '',
      effect: parts[3] || '',
    }
  })
}

// ============================================================
// preset diff 計算 / apply / rollback
// ============================================================

function computePresetDiff(presetName) {
  const preset = PRESETS[presetName]
  if (!preset) return null
  const changes = []
  for (const [key, newVal] of Object.entries(preset.values)) {
    const currentVal = hcGet(key)
    if (currentVal === null) {
      changes.push({ key, current: '<unknown>', new: String(newVal), changed: true, error: 'hc-config --get failed' })
      continue
    }
    if (String(currentVal) !== String(newVal)) {
      changes.push({ key, current: String(currentVal), new: String(newVal), changed: true })
    } else {
      changes.push({ key, current: String(currentVal), new: String(newVal), changed: false })
    }
  }
  return { preset: presetName, axes: preset.axes, use_case: preset.use_case, changes }
}

function applyPreset(presetName, skipKeys) {
  const diff = computePresetDiff(presetName)
  if (!diff) return { ok: false, error: 'unknown preset' }
  const skipSet = new Set(skipKeys || [])
  const applied = []
  const failed = []
  for (const change of diff.changes) {
    if (!change.changed) continue
    if (skipSet.has(change.key)) continue
    const r = hcSet(change.key, change.new)
    if (r.exitCode === 0) {
      applied.push({ key: change.key, from: change.current, to: change.new })
    } else {
      failed.push({ key: change.key, from: change.current, to: change.new, stderr: r.stderr })
    }
  }
  // history 保存
  if (!fs.existsSync(HISTORY_DIR)) {
    fs.mkdirSync(HISTORY_DIR, { recursive: true })
  }
  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
  const histFile = path.join(HISTORY_DIR, `${stamp}-${presetName}.json`)
  const histPayload = {
    preset: presetName,
    applied_at: new Date().toISOString(),
    axes: diff.axes,
    use_case: diff.use_case,
    applied,
    failed,
    skipped: Array.from(skipSet),
  }
  fs.writeFileSync(histFile, JSON.stringify(histPayload, null, 2))
  return { ok: failed.length === 0, applied: applied.length, failed: failed.length, skipped: skipSet.size, history_file: path.basename(histFile), failures: failed }
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
        applied_at: content.applied_at,
        applied_count: (content.applied || []).length,
        failed_count: (content.failed || []).length,
      }
    } catch (e) {
      return { timestamp: f.replace(/\.json$/, ''), error: String(e.message) }
    }
  })
}

function rollbackHistory(timestamp) {
  const histFile = path.join(HISTORY_DIR, `${timestamp}.json`)
  if (!fs.existsSync(histFile)) return { ok: false, error: 'history not found' }
  let payload
  try {
    payload = JSON.parse(fs.readFileSync(histFile, 'utf8'))
  } catch (e) {
    return { ok: false, error: 'history parse failed: ' + e.message }
  }
  const restored = []
  const failed = []
  for (const change of (payload.applied || [])) {
    const r = hcSet(change.key, change.from)
    if (r.exitCode === 0) restored.push(change.key)
    else failed.push({ key: change.key, stderr: r.stderr })
  }
  return { ok: failed.length === 0, restored: restored.length, failed: failed.length, failures: failed }
}

// ============================================================
// HTTP helpers
// ============================================================

function sendJson(res, statusCode, payload) {
  const body = JSON.stringify(payload)
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
  })
  res.end(body)
}

function sendText(res, statusCode, text, contentType) {
  res.writeHead(statusCode, {
    'Content-Type': contentType || 'text/plain; charset=utf-8',
    'Content-Length': Buffer.byteLength(text),
  })
  res.end(text)
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = []
    let total = 0
    req.on('data', (c) => {
      chunks.push(c)
      total += c.length
      if (total > 1024 * 1024) {
        reject(new Error('body too large'))
        req.destroy()
      }
    })
    req.on('end', () => {
      try {
        const body = Buffer.concat(chunks).toString('utf8')
        resolve(body.length === 0 ? {} : JSON.parse(body))
      } catch (e) {
        reject(e)
      }
    })
    req.on('error', reject)
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
// router
// ============================================================

async function handleRequest(req, res) {
  const parsed = url.parse(req.url, true)
  const pathname = parsed.pathname || '/'

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

  // GET /api/keys
  if (req.method === 'GET' && pathname === '/api/keys') {
    const metadata = loadMetadata()
    const categoryFilter = parsed.query && parsed.query.category
    const filtered = categoryFilter ? metadata.filter((m) => m.category === categoryFilter) : metadata
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

  // POST /api/set
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
    const r = hcSet(body.key, body.value)
    if (r.exitCode !== 0) {
      sendJson(res, 400, { error: 'hc-config --set failed', stderr: r.stderr, exit_code: r.exitCode })
      return
    }
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

  // POST /api/preset/:name/apply
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
    sendJson(res, result.ok ? 200 : 500, result)
    return
  }

  // GET /api/preset/history
  if (req.method === 'GET' && pathname === '/api/preset/history') {
    sendJson(res, 200, { history: listHistory() })
    return
  }

  // POST /api/preset/rollback/:timestamp
  const rollbackMatch = pathname.match(/^\/api\/preset\/rollback\/(.+)$/)
  if (req.method === 'POST' && rollbackMatch) {
    const ts = decodeURIComponent(rollbackMatch[1])
    const result = rollbackHistory(ts)
    sendJson(res, result.ok ? 200 : 500, result)
    return
  }

  // 404 fallback
  sendJson(res, 404, { error: 'not found', path: pathname, method: req.method })
}

// ============================================================
// port 探索 + listen
// ============================================================

function tryListen(server, port) {
  return new Promise((resolve, reject) => {
    const onError = (err) => {
      server.removeListener('listening', onListen)
      reject(err)
    }
    const onListen = () => {
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
      if (err && err.code === 'EADDRINUSE') continue
      throw err
    }
  }
  throw new Error(`no free port in ${PORT_MIN}-${PORT_MAX}`)
}

// ============================================================
// browser auto-open
// ============================================================

function openBrowser(url) {
  const platform = os.platform()
  let cmd, args
  if (platform === 'darwin') { cmd = 'open'; args = [url] }
  else if (platform === 'linux') { cmd = 'xdg-open'; args = [url] }
  else if (platform === 'win32') { cmd = 'cmd'; args = ['/c', 'start', '', url] }
  else {
    console.log(`Open this URL manually: ${url}`)
    return
  }
  const r = spawnSync(cmd, args, { timeout: 3000, stdio: 'ignore' })
  if (r.status !== 0 || r.error) {
    console.log(`Browser auto-open failed. Open this URL manually: ${url}`)
  }
}

// ============================================================
// main
// ============================================================

async function main() {
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

module.exports = { PRESETS, PRESET_AXES, computePresetDiff, applyPreset, listHistory, rollbackHistory }
