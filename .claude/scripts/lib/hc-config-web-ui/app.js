// hc-config Web UI — task-61 Step 3
// vanilla JS + Tailwind CDN, fetch API only, no external deps
//
// State machine:
//   view: 'idle' | 'category' | 'key' | 'preset'
//   - idle    : 初期表示
//   - category: category 選択 → key 一覧
//   - key     : key 選択 → edit form
//   - preset  : preset 選択 → diff preview + apply
;(function () {
  'use strict'

  // ============================================================
  // state
  // ============================================================
  const state = {
    view: 'idle',
    categories: [],
    keys: [],
    keysAll: [],
    presets: [],
    selectedCategory: null,
    selectedKey: null,
    selectedPreset: null,
    presetDiff: null,
    skipKeys: {}, // key -> bool (true = skip)
    history: [],
  }

  // ============================================================
  // API wrappers
  // ============================================================
  async function api(method, path, body) {
    const opts = { method, headers: { 'Content-Type': 'application/json' } }
    if (body !== undefined) opts.body = JSON.stringify(body)
    const res = await fetch(path, opts)
    const text = await res.text()
    let data
    try {
      data = text.length ? JSON.parse(text) : {}
    } catch (e) {
      throw new Error(`Invalid JSON response from ${path}: ${text.slice(0, 200)}`)
    }
    if (!res.ok) {
      const detail = data && data.error ? `${data.error}${data.stderr ? ' / ' + data.stderr : ''}` : `${res.status} ${res.statusText}`
      throw new Error(`${method} ${path} failed: ${detail}`)
    }
    return data
  }

  const loadCategories = async () => {
    const r = await api('GET', '/api/categories')
    state.categories = r.categories || []
  }
  const loadKeys = async (category) => {
    const q = category ? `?category=${encodeURIComponent(category)}` : ''
    const r = await api('GET', `/api/keys${q}`)
    state.keys = r.keys || []
    if (!category) state.keysAll = state.keys
  }
  const loadPresets = async () => {
    const r = await api('GET', '/api/presets')
    state.presets = r.presets || []
  }
  const loadPresetDiff = async (name) => {
    const r = await api('GET', `/api/preset/${encodeURIComponent(name)}/diff`)
    state.presetDiff = r
  }
  const applyPresetApi = async (name, skipKeys) => {
    return await api('POST', `/api/preset/${encodeURIComponent(name)}/apply`, { skip_keys: skipKeys })
  }
  const setKeyApi = async (key, value) => {
    return await api('POST', '/api/set', { key, value })
  }
  const loadHistory = async () => {
    const r = await api('GET', '/api/preset/history')
    state.history = r.history || []
  }
  const rollbackApi = async (timestamp) => {
    return await api('POST', `/api/preset/rollback/${encodeURIComponent(timestamp)}`)
  }

  // ============================================================
  // utils
  // ============================================================
  function el(tag, attrs, ...children) {
    const e = document.createElement(tag)
    if (attrs) {
      for (const [k, v] of Object.entries(attrs)) {
        if (k === 'class') e.className = v
        else if (k === 'onclick') e.addEventListener('click', v)
        else if (k === 'onchange') e.addEventListener('change', v)
        else if (k === 'oninput') e.addEventListener('input', v)
        else if (v !== undefined && v !== null) e.setAttribute(k, String(v))
      }
    }
    for (const c of children) {
      if (c === null || c === undefined) continue
      if (typeof c === 'string' || typeof c === 'number') e.appendChild(document.createTextNode(String(c)))
      else e.appendChild(c)
    }
    return e
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild)
  }

  function toast(message, type) {
    const cls =
      type === 'error'
        ? 'bg-red-600 text-white'
        : type === 'success'
        ? 'bg-emerald-600 text-white'
        : 'bg-slate-800 text-white'
    const t = el('div', { class: `pointer-events-auto px-4 py-2 rounded shadow-lg text-sm ${cls}` }, message)
    document.getElementById('toast-container').appendChild(t)
    setTimeout(() => t.remove(), 4000)
  }

  function setStatus(text) {
    const sb = document.getElementById('status-text')
    if (sb) sb.textContent = text
  }

  // ============================================================
  // render: sidebar
  // ============================================================
  function renderSidebar() {
    const presetUl = document.getElementById('preset-list')
    clear(presetUl)
    for (const p of state.presets) {
      const isSel = state.view === 'preset' && state.selectedPreset === p.name
      const li = el(
        'li',
        {
          class: `preset-card cursor-pointer px-2 py-1.5 rounded border ${isSel ? 'border-blue-500 bg-blue-50 ring-1 ring-blue-200' : 'border-transparent hover:bg-slate-100'}`,
          onclick: () => onSelectPreset(p.name),
        },
        el('div', { class: 'font-mono text-xs font-semibold text-slate-800' }, p.name),
        el('div', { class: 'text-xs text-slate-500 mt-0.5' }, p.use_case || ''),
        el('div', { class: 'text-xs text-slate-400 mt-0.5' }, `${p.affected_key_count} keys`)
      )
      presetUl.appendChild(li)
    }

    const catUl = document.getElementById('category-list')
    clear(catUl)
    for (const c of state.categories) {
      const isSel = state.view === 'category' && state.selectedCategory === c.name
      const li = el(
        'li',
        {
          class: `cursor-pointer px-2 py-1.5 rounded ${isSel ? 'bg-blue-50 text-blue-900 font-semibold' : 'hover:bg-slate-100'}`,
          onclick: () => onSelectCategory(c.name),
        },
        el('span', { class: '' }, c.name),
        el('span', { class: 'text-xs text-slate-400 ml-1' }, `(${c.key_count})`)
      )
      catUl.appendChild(li)
    }
  }

  // ============================================================
  // render: main panel
  // ============================================================
  function renderMain() {
    const panel = document.getElementById('main-panel')
    clear(panel)

    if (state.view === 'idle') {
      panel.appendChild(
        el(
          'div',
          { class: 'bg-white rounded-lg border border-slate-200 p-6' },
          el('p', { class: 'text-slate-600' }, '左 sidebar から '),
          el('strong', null, 'Preset'),
          el('span', { class: 'text-slate-600' }, ' または '),
          el('strong', null, 'Category'),
          el('span', { class: 'text-slate-600' }, ' を選択してください。')
        )
      )
      return
    }

    if (state.view === 'preset') {
      panel.appendChild(renderPresetPanel())
      return
    }

    if (state.view === 'category') {
      panel.appendChild(renderCategoryPanel())
      return
    }

    if (state.view === 'key') {
      panel.appendChild(renderKeyPanel())
      return
    }
  }

  function renderPresetPanel() {
    const diff = state.presetDiff
    const box = el('div', { class: 'space-y-4' })

    const header = el(
      'div',
      { class: 'bg-white rounded-lg border border-slate-200 p-4' },
      el('h2', { class: 'text-lg font-bold text-slate-800' }, `Preset: ${state.selectedPreset}`),
      el('p', { class: 'text-sm text-slate-600 mt-1' }, diff && diff.use_case ? diff.use_case : '')
    )

    // axes pills
    if (diff && diff.axes) {
      const pills = el('div', { class: 'flex flex-wrap gap-1.5 mt-2' })
      for (const [k, v] of Object.entries(diff.axes)) {
        pills.appendChild(
          el('span', { class: 'text-xs px-2 py-0.5 bg-slate-100 border border-slate-200 rounded font-mono' }, `${k}=${v}`)
        )
      }
      header.appendChild(pills)
    }
    box.appendChild(header)

    if (!diff) {
      box.appendChild(el('div', { class: 'bg-white rounded-lg border border-slate-200 p-6 text-slate-500' }, 'diff 読込中...'))
      return box
    }

    const changes = diff.changes || []
    const changed = changes.filter((c) => c.changed)
    const unchanged = changes.filter((c) => !c.changed)

    // diff table
    const tableBox = el('div', { class: 'bg-white rounded-lg border border-slate-200 overflow-hidden' })
    tableBox.appendChild(
      el(
        'div',
        { class: 'px-4 py-2 border-b border-slate-200 bg-slate-50 flex items-center justify-between' },
        el(
          'div',
          { class: 'text-sm font-semibold text-slate-700' },
          `Diff Preview: ${changed.length} 変更, ${unchanged.length} 不変`
        ),
        el(
          'div',
          { class: 'space-x-2' },
          el(
            'button',
            {
              class: 'px-3 py-1 text-xs bg-slate-200 hover:bg-slate-300 rounded',
              onclick: () => onToggleAllSkip(true),
            },
            'すべて skip'
          ),
          el(
            'button',
            {
              class: 'px-3 py-1 text-xs bg-slate-200 hover:bg-slate-300 rounded',
              onclick: () => onToggleAllSkip(false),
            },
            'すべて適用'
          )
        )
      )
    )

    const table = el('table', { class: 'w-full text-sm' })
    const thead = el(
      'thead',
      { class: 'bg-slate-50 text-xs uppercase text-slate-500' },
      el(
        'tr',
        null,
        el('th', { class: 'text-left px-3 py-2 w-12' }, '適用'),
        el('th', { class: 'text-left px-3 py-2' }, 'Key'),
        el('th', { class: 'text-left px-3 py-2' }, 'Current'),
        el('th', { class: 'text-left px-3 py-2' }, 'New'),
        el('th', { class: 'text-left px-3 py-2 w-20' }, '状態')
      )
    )
    table.appendChild(thead)
    const tbody = el('tbody', null)
    for (const c of changes) {
      const isSkip = state.skipKeys[c.key] === true
      const row = el(
        'tr',
        {
          class: `diff-row border-t border-slate-100 ${isSkip ? 'skip' : ''} ${c.changed ? '' : 'opacity-60'}`,
        },
        el(
          'td',
          { class: 'px-3 py-2' },
          c.changed
            ? el('input', {
                type: 'checkbox',
                ...(isSkip ? {} : { checked: 'checked' }),
                onchange: (ev) => onToggleSkip(c.key, !ev.target.checked),
              })
            : el('span', { class: 'text-slate-300' }, '—')
        ),
        el('td', { class: 'px-3 py-2 font-mono text-xs text-slate-800' }, c.key),
        el('td', { class: 'px-3 py-2 font-mono text-xs text-slate-600' }, c.current),
        el('td', { class: 'px-3 py-2 font-mono text-xs text-blue-700' }, c.new),
        el(
          'td',
          { class: 'px-3 py-2 text-xs' },
          c.changed ? el('span', { class: 'text-amber-700' }, '変更') : el('span', { class: 'text-slate-400' }, '不変')
        )
      )
      tbody.appendChild(row)
    }
    table.appendChild(tbody)
    tableBox.appendChild(table)
    box.appendChild(tableBox)

    // apply button
    const actions = el(
      'div',
      { class: 'flex items-center gap-3' },
      el(
        'button',
        {
          class: 'px-4 py-2 bg-emerald-600 text-white rounded shadow-sm hover:bg-emerald-700 text-sm font-semibold',
          onclick: onApplyPreset,
        },
        `Apply Preset (${changed.length - countSkip(changed)} keys)`
      ),
      el(
        'button',
        {
          class: 'px-4 py-2 bg-slate-200 text-slate-800 rounded hover:bg-slate-300 text-sm',
          onclick: () => loadPresetDiff(state.selectedPreset).then(() => renderMain()),
        },
        '差分再読込'
      )
    )
    box.appendChild(actions)

    return box
  }

  function countSkip(changes) {
    return changes.filter((c) => state.skipKeys[c.key]).length
  }

  function renderCategoryPanel() {
    const box = el('div', { class: 'space-y-4' })
    box.appendChild(
      el(
        'div',
        { class: 'bg-white rounded-lg border border-slate-200 p-4' },
        el('h2', { class: 'text-lg font-bold text-slate-800' }, `Category: ${state.selectedCategory}`),
        el('p', { class: 'text-sm text-slate-600 mt-1' }, `${state.keys.length} 個の key`)
      )
    )

    const tableBox = el('div', { class: 'bg-white rounded-lg border border-slate-200 overflow-hidden' })
    const table = el('table', { class: 'w-full text-sm' })
    table.appendChild(
      el(
        'thead',
        { class: 'bg-slate-50 text-xs uppercase text-slate-500' },
        el(
          'tr',
          null,
          el('th', { class: 'text-left px-3 py-2' }, 'Key'),
          el('th', { class: 'text-left px-3 py-2' }, '現在値'),
          el('th', { class: 'text-left px-3 py-2' }, '説明'),
          el('th', { class: 'text-left px-3 py-2 w-16' }, '操作')
        )
      )
    )
    const tbody = el('tbody', null)
    for (const k of state.keys) {
      const tr = el(
        'tr',
        { class: 'border-t border-slate-100 hover:bg-slate-50 cursor-pointer', onclick: () => onSelectKey(k.key) },
        el('td', { class: 'px-3 py-2 font-mono text-xs text-slate-800' }, k.key),
        el('td', { class: 'px-3 py-2 font-mono text-xs text-blue-700' }, k.current_value === null ? '<n/a>' : String(k.current_value)),
        el('td', { class: 'px-3 py-2 text-xs text-slate-600' }, k.description || ''),
        el('td', { class: 'px-3 py-2 text-xs text-blue-600 underline' }, '編集')
      )
      tbody.appendChild(tr)
    }
    table.appendChild(tbody)
    tableBox.appendChild(table)
    box.appendChild(tableBox)
    return box
  }

  function renderKeyPanel() {
    const key = state.selectedKey
    const meta = state.keys.find((k) => k.key === key) || state.keysAll.find((k) => k.key === key) || { key, current_value: '', description: '', effect: '' }
    const box = el('div', { class: 'space-y-4' })
    box.appendChild(
      el(
        'div',
        { class: 'bg-white rounded-lg border border-slate-200 p-4' },
        el('h2', { class: 'text-lg font-bold text-slate-800 font-mono' }, key),
        meta.description ? el('p', { class: 'text-sm text-slate-700 mt-2' }, meta.description) : null,
        meta.effect ? el('p', { class: 'text-xs text-slate-500 mt-1' }, `効果: ${meta.effect}`) : null
      )
    )

    const formBox = el('div', { class: 'bg-white rounded-lg border border-slate-200 p-4 space-y-3' })
    formBox.appendChild(
      el(
        'div',
        null,
        el('label', { class: 'text-xs uppercase text-slate-500 font-semibold' }, '現在値'),
        el(
          'div',
          { class: 'mt-1 font-mono text-sm bg-slate-100 rounded px-3 py-2' },
          meta.current_value === null ? '<n/a>' : String(meta.current_value)
        )
      )
    )
    const input = el('input', {
      type: 'text',
      class: 'w-full font-mono text-sm border border-slate-300 rounded px-3 py-2 focus:outline-none focus:ring focus:ring-blue-200',
      value: meta.current_value === null ? '' : String(meta.current_value),
      placeholder: '新しい値',
    })
    formBox.appendChild(
      el(
        'div',
        null,
        el('label', { class: 'text-xs uppercase text-slate-500 font-semibold' }, '新しい値'),
        el('div', { class: 'mt-1' }, input)
      )
    )
    formBox.appendChild(
      el(
        'div',
        { class: 'flex gap-2' },
        el(
          'button',
          {
            class: 'px-4 py-2 bg-blue-600 text-white text-sm font-semibold rounded hover:bg-blue-700',
            onclick: () => onApplyKey(key, input.value),
          },
          'Apply'
        ),
        el(
          'button',
          {
            class: 'px-4 py-2 bg-slate-200 text-slate-800 text-sm rounded hover:bg-slate-300',
            onclick: () => {
              if (state.selectedCategory) {
                onSelectCategory(state.selectedCategory)
              } else {
                state.view = 'idle'
                renderSidebar()
                renderMain()
              }
            },
          },
          'キャンセル'
        )
      )
    )
    box.appendChild(formBox)
    return box
  }

  function renderHistory() {
    const tbody = document.getElementById('history-tbody')
    clear(tbody)
    if (!state.history.length) {
      tbody.appendChild(el('tr', null, el('td', { class: 'py-2 text-slate-400', colspan: 5 }, '履歴なし')))
      return
    }
    for (const h of state.history) {
      const tr = el(
        'tr',
        { class: 'history-row border-t border-slate-100' },
        el('td', { class: 'py-1 pr-3 font-mono text-xs' }, h.timestamp),
        el('td', { class: 'py-1 pr-3 font-mono text-xs' }, h.preset || '<unknown>'),
        el('td', { class: 'py-1 pr-3' }, String(h.applied_count !== undefined ? h.applied_count : '?')),
        el(
          'td',
          { class: 'py-1 pr-3' },
          h.failed_count > 0
            ? el('span', { class: 'text-red-600 font-semibold' }, String(h.failed_count))
            : el('span', { class: 'text-slate-400' }, '0')
        ),
        el(
          'td',
          { class: 'py-1 pr-3' },
          el(
            'button',
            {
              class: 'text-xs px-2 py-0.5 bg-amber-100 hover:bg-amber-200 text-amber-800 rounded border border-amber-300',
              onclick: () => onRollback(h.timestamp),
            },
            'Rollback'
          )
        )
      )
      tbody.appendChild(tr)
    }
  }

  // ============================================================
  // event handlers
  // ============================================================
  async function onSelectPreset(name) {
    state.view = 'preset'
    state.selectedPreset = name
    state.selectedCategory = null
    state.selectedKey = null
    state.skipKeys = {}
    state.presetDiff = null
    setStatus(`Preset: ${name} の diff を計算中...`)
    renderSidebar()
    renderMain()
    try {
      await loadPresetDiff(name)
      setStatus(`Preset: ${name}`)
      renderMain()
    } catch (e) {
      toast(`diff 取得失敗: ${e.message}`, 'error')
      setStatus('エラー')
    }
  }

  async function onSelectCategory(name) {
    state.view = 'category'
    state.selectedCategory = name
    state.selectedPreset = null
    state.selectedKey = null
    setStatus(`Category: ${name} を読込中...`)
    renderSidebar()
    renderMain()
    try {
      await loadKeys(name)
      setStatus(`Category: ${name}`)
      renderMain()
    } catch (e) {
      toast(`key 取得失敗: ${e.message}`, 'error')
      setStatus('エラー')
    }
  }

  function onSelectKey(key) {
    state.view = 'key'
    state.selectedKey = key
    renderMain()
  }

  function onToggleSkip(key, skip) {
    state.skipKeys[key] = skip
    renderMain()
  }

  function onToggleAllSkip(skip) {
    if (!state.presetDiff) return
    for (const c of state.presetDiff.changes) {
      if (c.changed) state.skipKeys[c.key] = skip
    }
    renderMain()
  }

  async function onApplyPreset() {
    if (!state.selectedPreset || !state.presetDiff) return
    const skipKeys = Object.entries(state.skipKeys)
      .filter(([_, v]) => v === true)
      .map(([k, _]) => k)
    const changed = state.presetDiff.changes.filter((c) => c.changed && !state.skipKeys[c.key])
    if (changed.length === 0) {
      toast('適用対象 key が 0 件です', 'info')
      return
    }
    if (!confirm(`${changed.length} key を適用します。よろしいですか?`)) return
    setStatus('適用中...')
    try {
      const r = await applyPresetApi(state.selectedPreset, skipKeys)
      if (r.ok) {
        toast(`Apply 成功: ${r.applied} keys`, 'success')
      } else {
        toast(`Apply 部分失敗: ${r.applied} 成功 / ${r.failed} 失敗`, 'error')
      }
      await Promise.all([loadHistory(), loadPresetDiff(state.selectedPreset)])
      setStatus(`Preset: ${state.selectedPreset}`)
      renderMain()
      renderHistory()
    } catch (e) {
      toast(`Apply 失敗: ${e.message}`, 'error')
      setStatus('エラー')
    }
  }

  async function onApplyKey(key, value) {
    if (!key) return
    setStatus(`${key} を設定中...`)
    try {
      await setKeyApi(key, value)
      toast(`${key} = ${value} を適用しました`, 'success')
      // 再ロード
      if (state.selectedCategory) {
        await loadKeys(state.selectedCategory)
      }
      setStatus('完了')
      // category panel に戻る
      if (state.selectedCategory) {
        state.view = 'category'
        renderMain()
      }
    } catch (e) {
      toast(`apply 失敗: ${e.message}`, 'error')
      setStatus('エラー')
    }
  }

  async function onRollback(timestamp) {
    if (!confirm(`${timestamp} の preset apply を rollback します。よろしいですか?`)) return
    setStatus('Rollback 中...')
    try {
      const r = await rollbackApi(timestamp)
      if (r.ok) {
        toast(`Rollback 成功: ${r.restored} keys 復元`, 'success')
      } else {
        toast(`Rollback 部分失敗: ${r.restored} 成功 / ${r.failed} 失敗`, 'error')
      }
      await loadHistory()
      // 現在 preset 表示中なら diff 再計算
      if (state.view === 'preset' && state.selectedPreset) {
        await loadPresetDiff(state.selectedPreset)
        renderMain()
      } else if (state.view === 'category' && state.selectedCategory) {
        await loadKeys(state.selectedCategory)
        renderMain()
      }
      renderHistory()
      setStatus('Rollback 完了')
    } catch (e) {
      toast(`Rollback 失敗: ${e.message}`, 'error')
      setStatus('エラー')
    }
  }

  // ============================================================
  // Tailwind CDN detection
  // ============================================================
  function detectTailwind() {
    // Tailwind CDN は window.tailwind を設定する
    setTimeout(() => {
      if (typeof window.tailwind === 'undefined') {
        const w = document.getElementById('cdn-warning')
        if (w) w.classList.remove('hidden')
      }
    }, 1500)
  }

  // ============================================================
  // init
  // ============================================================
  async function init() {
    setStatus('読み込み中...')
    detectTailwind()
    try {
      await Promise.all([loadCategories(), loadPresets(), loadHistory()])
      renderSidebar()
      renderMain()
      renderHistory()
      setStatus(`Ready (${state.presets.length} presets / ${state.categories.length} categories)`)
    } catch (e) {
      toast(`初期化失敗: ${e.message}`, 'error')
      setStatus('エラー (server 起動を確認してください)')
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init)
  } else {
    init()
  }
})()
