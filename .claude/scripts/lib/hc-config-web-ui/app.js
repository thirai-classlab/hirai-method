// hc-config Web UI — task-61 Step 5 iter 4 B (UI a11y + UX fix)
// vanilla JS + Tailwind CDN, fetch API only, no external deps
//
// State machine:
//   view: 'idle' | 'category' | 'key' | 'preset'
//   - idle    : 初期表示
//   - category: category 選択 → key 一覧
//   - key     : key 選択 → edit form
//   - preset  : preset 選択 → diff preview + apply
//
// WCAG 2.2 AA 準拠 (iter 2 で 16 SC 違反全 closure 済、iter 4 B で追加維持):
//   - C-U1 accessible name: rollback / diff checkbox / 全 button
//   - C-U2 label-input 関連付け: for=/id= 形式
//   - H-U1 keyboard navigation: tabindex / role + Enter/Space handler
//   - H-U3 color only state: ●○⚠ アイコン併用
//   - H-U4 custom dialog: <dialog> + focus trap + Esc cancel
//   - H-XSS textContent only (innerHTML 禁止)
//   - M-U3 二重送信防止 (state.applying flag + disabled)
//   - M-U4 heading 階層: <h3>/<h4> 動的 panel
//
// iter 4 B 修正項目 (7 件):
//   - H-new-1: sidebar role="listbox" → role="list" + role="option" → role="listitem" (APG 完全実装の代わりに YAGNI)
//   - M-new-1: showConfirmDialog/showPromptDialog cleanup 二重呼び出し防止 (resolved flag)
//   - M-new-2: prompt dialog validation error を aria-live="assertive" output で SR 通知
//   - M-new-3: diff table skip row tr に aria-label dynamic + checkbox aria-label dynamic
//   - MED-Q1: onApplyPreset partial failure 時 toast に applied/failed/rolled_back/rollback_failed 詳細明示
//   - MED-Q5: onSaveCustomPreset axes を「選択中 preset の axes」ではなく「現在の yml 6 軸」を fetch して送信
//   - API contract: preset name regex 3-49 char に統一 (server.js 領域 A と整合)
//
;(function () {
  'use strict'

  // ============================================================
  // 6 軸 key list (axes fetcher 用、領域 A server.js PRESET_AXES と整合)
  // ============================================================
  const AXIS_KEYS = [
    'quality_level',
    'language_framework',
    'git_workflow',
    'tdd_policy',
    'review_intensity',
    'autonomy_level',
  ]

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
    applying: false, // M-U3 二重送信防止
    rollbackInProgress: false,
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
      // iter 6 A item 5 (MED pr-test): NF-10 fix の UI 連携完成
      //   server 側で timeout を timedOut/timed_out flag で返却している場合、
      //   error 文字列に "(timeout 5s 超過)" を追加して UI 上で明示する。
      const detail = data && data.error ? `${data.error}${data.stderr ? ' / ' + data.stderr : ''}` : `${res.status} ${res.statusText}`
      const timeoutSuffix = data && data.timed_out === true ? ' (timeout 5s 超過)' : ''
      throw new Error(`${method} ${path} failed: ${detail}${timeoutSuffix}`)
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
  const savePresetApi = async (name, axes) => {
    return await api('POST', '/api/preset/save', { name, axes })
  }

  // MED-Q5 iter 4 B: 現在の yml 6 軸を取得 (server.js /api/keys は metadata.sh 経由で current_value 含む)
  //   /api/keys?category=... の API が axes 専用 endpoint を持たないため、全 key 取得 → 6 軸 filter
  //   (将来 /api/axes or /api/keys?keys=a,b,c で軽量化可能、本 iter は最小修正)
  const loadCurrentAxes = async () => {
    const r = await api('GET', '/api/keys')
    const keys = r.keys || []
    const axes = {}
    for (const k of AXIS_KEYS) {
      const entry = keys.find((x) => x.key === k)
      if (entry && entry.current_value !== null && entry.current_value !== undefined) {
        axes[k] = String(entry.current_value)
      }
    }
    return axes
  }

  // ============================================================
  // utils (DOM 構築は createElement + textContent のみ、innerHTML 禁止)
  // ============================================================
  function el(tag, attrs, ...children) {
    const e = document.createElement(tag)
    if (attrs) {
      for (const [k, v] of Object.entries(attrs)) {
        if (k === 'class') e.className = v
        else if (k === 'onclick') e.addEventListener('click', v)
        else if (k === 'onchange') e.addEventListener('change', v)
        else if (k === 'oninput') e.addEventListener('input', v)
        else if (k === 'onkeydown') e.addEventListener('keydown', v)
        else if (k === 'htmlFor') e.htmlFor = v
        else if (v === true) e.setAttribute(k, '')
        else if (v === false || v === undefined || v === null) {
          // skip
        } else {
          e.setAttribute(k, String(v))
        }
      }
    }
    for (const c of children) {
      if (c === null || c === undefined || c === false) continue
      if (typeof c === 'string' || typeof c === 'number') {
        e.appendChild(document.createTextNode(String(c)))
      } else {
        e.appendChild(c)
      }
    }
    return e
  }

  function clear(node) {
    while (node.firstChild) node.removeChild(node.firstChild)
  }

  // ============================================================
  // toast (4 type: error / success / warning / info)
  // ============================================================
  function toast(message, type) {
    let cls
    let icon
    if (type === 'error') {
      cls = 'bg-red-700 text-white'
      icon = '✖' // ✖
    } else if (type === 'success') {
      cls = 'bg-emerald-700 text-white'
      icon = '✔' // ✔
    } else if (type === 'warning') {
      cls = 'bg-amber-600 text-white'
      icon = '⚠' // ⚠
    } else if (type === 'info') {
      cls = 'bg-blue-700 text-white'
      icon = 'ℹ' // ℹ
    } else {
      cls = 'bg-slate-800 text-white'
      icon = ''
    }
    const t = el(
      'div',
      {
        class: `pointer-events-auto px-4 py-2 rounded shadow-lg text-sm flex items-center gap-2 ${cls}`,
        role: type === 'error' ? 'alert' : 'status',
      },
      icon ? el('span', { 'aria-hidden': 'true' }, icon) : null,
      el('span', null, message)
    )
    document.getElementById('toast-container').appendChild(t)
    setTimeout(() => t.remove(), 4000)
  }

  function setStatus(text) {
    const sb = document.getElementById('status-text')
    if (sb) sb.textContent = text
  }

  // ============================================================
  // dialog helpers (H-U4: custom <dialog> + focus trap + Esc cancel)
  // M-new-1 iter 4 B: resolved flag で cleanup 二重呼び出し / 二重 resolve 防止
  // ============================================================
  function showConfirmDialog(opts) {
    // opts: { title, bodyLines: string[], okLabel, cancelLabel, danger }
    return new Promise((resolve) => {
      const dlg = document.getElementById('confirm-dialog')
      const titleEl = document.getElementById('confirm-dialog-title')
      const bodyEl = document.getElementById('confirm-dialog-body')
      const okBtn = document.getElementById('confirm-dialog-ok')
      const cancelBtn = document.getElementById('confirm-dialog-cancel')

      titleEl.textContent = opts.title || '確認'
      clear(bodyEl)
      for (const line of opts.bodyLines || []) {
        bodyEl.appendChild(el('p', null, line))
      }
      okBtn.textContent = opts.okLabel || '実行'
      cancelBtn.textContent = opts.cancelLabel || 'キャンセル'
      // danger 時は red、それ以外は emerald (CSS class 上書き)
      okBtn.className = opts.danger
        ? 'px-4 py-2 text-sm bg-red-700 hover:bg-red-800 text-white font-semibold rounded min-h-[44px]'
        : 'px-4 py-2 text-sm bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded min-h-[44px]'

      // M-new-1 iter 4 B: resolved flag で二重発火を防止
      let resolved = false

      const safeResolve = (value) => {
        if (resolved) return
        resolved = true
        cleanup()
        resolve(value)
      }

      const onOk = () => safeResolve(true)
      const onCancel = () => safeResolve(false)
      const onCancelKey = (ev) => {
        // <dialog> native は Esc で close する。close 時 returnValue が 'cancel' なら cancel 扱い。
        if (ev.key === 'Escape') {
          // 既定動作で close するため、close event で resolve
        }
      }
      const onClose = () => safeResolve(dlg.returnValue === 'ok')

      function cleanup() {
        okBtn.removeEventListener('click', okClickHandler)
        cancelBtn.removeEventListener('click', cancelClickHandler)
        dlg.removeEventListener('keydown', onCancelKey)
        dlg.removeEventListener('close', onClose)
        if (dlg.open) {
          try { dlg.close() } catch (e) { /* noop */ }
        }
      }

      const okClickHandler = () => { dlg.returnValue = 'ok'; onOk() }
      const cancelClickHandler = () => { dlg.returnValue = 'cancel'; onCancel() }

      okBtn.addEventListener('click', okClickHandler)
      cancelBtn.addEventListener('click', cancelClickHandler)
      dlg.addEventListener('keydown', onCancelKey)
      dlg.addEventListener('close', onClose)

      if (typeof dlg.showModal === 'function') {
        dlg.showModal()
      } else {
        dlg.setAttribute('open', '')
      }
      // 初期フォーカスは Cancel ボタン (誤操作防止)
      setTimeout(() => cancelBtn.focus(), 10)
    })
  }

  function showPromptDialog(opts) {
    // opts: { title, message, placeholder, validate(name) -> string | null }
    return new Promise((resolve) => {
      const dlg = document.getElementById('prompt-dialog')
      const titleEl = document.getElementById('prompt-dialog-title')
      const input = document.getElementById('prompt-dialog-input')
      const errorEl = document.getElementById('prompt-dialog-error')
      const okBtn = document.getElementById('prompt-dialog-ok')
      const cancelBtn = document.getElementById('prompt-dialog-cancel')

      if (opts.title) titleEl.textContent = opts.title
      input.value = ''
      input.placeholder = opts.placeholder || ''
      // M-new-2 iter 4 B: error 表示を初期状態にリセット
      input.setAttribute('aria-invalid', 'false')
      if (errorEl) {
        errorEl.textContent = ''
        errorEl.classList.add('hidden')
      }

      // M-new-1 iter 4 B: resolved flag で二重発火を防止
      let resolved = false

      const safeResolve = (value) => {
        if (resolved) return
        resolved = true
        cleanup()
        resolve(value)
      }

      // M-new-2 iter 4 B: validation error 表示 (toast 廃止、inline aria-live で SR 通知)
      const showError = (msg) => {
        input.setAttribute('aria-invalid', 'true')
        if (errorEl) {
          errorEl.textContent = msg
          errorEl.classList.remove('hidden')
        }
        input.focus()
        input.select()
      }
      const clearError = () => {
        input.setAttribute('aria-invalid', 'false')
        if (errorEl) {
          errorEl.textContent = ''
          errorEl.classList.add('hidden')
        }
      }

      const onOk = () => {
        const value = input.value.trim()
        if (opts.validate) {
          const err = opts.validate(value)
          if (err) {
            showError(err)
            return
          }
        }
        clearError()
        safeResolve(value)
      }
      const onCancel = () => safeResolve(null)
      const onKey = (ev) => {
        if (ev.key === 'Enter') {
          ev.preventDefault()
          onOk()
        }
      }
      // M-new-2 iter 4 B: input 変化で error 自動 clear (UX 改善)
      const onInputChange = () => {
        if (input.getAttribute('aria-invalid') === 'true') clearError()
      }
      const onClose = () => {
        // close event for backdrop Esc
        if (dlg.returnValue !== 'ok') safeResolve(null)
      }

      function cleanup() {
        okBtn.removeEventListener('click', okHandler)
        cancelBtn.removeEventListener('click', cancelHandler)
        input.removeEventListener('keydown', onKey)
        input.removeEventListener('input', onInputChange)
        dlg.removeEventListener('close', onClose)
        if (dlg.open) {
          try { dlg.close() } catch (e) { /* noop */ }
        }
      }

      const okHandler = () => { dlg.returnValue = 'ok'; onOk() }
      const cancelHandler = () => { dlg.returnValue = 'cancel'; onCancel() }

      okBtn.addEventListener('click', okHandler)
      cancelBtn.addEventListener('click', cancelHandler)
      input.addEventListener('keydown', onKey)
      input.addEventListener('input', onInputChange)
      dlg.addEventListener('close', onClose)

      if (typeof dlg.showModal === 'function') {
        dlg.showModal()
      } else {
        dlg.setAttribute('open', '')
      }
      setTimeout(() => input.focus(), 10)
    })
  }

  // ============================================================
  // keyboard helper: Enter/Space → action (H-U1)
  // ============================================================
  function activateOnEnterOrSpace(action) {
    return (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ' || ev.key === 'Spacebar') {
        ev.preventDefault()
        action(ev)
      }
    }
  }

  // ============================================================
  // render: sidebar
  // H-new-1 iter 4 B: role="option" + aria-selected 廃止、role="listitem" 化
  //   (APG Listbox 完全実装 (Arrow key navigation / aria-activedescendant) は YAGNI、
  //    keyboard accessibility は tabindex=0 + Tab + Enter/Space で確保 SC 2.1.1)
  // ============================================================
  function renderSidebar() {
    const presetUl = document.getElementById('preset-list')
    clear(presetUl)
    for (const p of state.presets) {
      const isSel = state.view === 'preset' && state.selectedPreset === p.name
      const onSelect = () => onSelectPreset(p.name)
      const keyWord = `${p.affected_key_count} key${p.affected_key_count === 1 ? '' : 's'}`
      const li = el(
        'li',
        {
          class: `preset-card cursor-pointer px-2 py-1.5 rounded border min-h-[44px] focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 ${isSel ? 'border-blue-500 bg-blue-50 ring-1 ring-blue-200' : 'border-transparent hover:bg-slate-100'}`,
          // H-new-1: role="option" → "listitem"、aria-selected 削除 (listbox 専用)
          role: 'listitem',
          tabindex: '0',
          'aria-current': isSel ? 'true' : null,
          'aria-label': `プリセット ${p.name}: ${p.use_case || ''} (${keyWord})${isSel ? ' (選択中)' : ''}`,
          onclick: onSelect,
          onkeydown: activateOnEnterOrSpace(onSelect),
        },
        el('div', { class: 'font-mono text-xs font-semibold text-slate-800' }, p.name),
        el('div', { class: 'text-xs text-slate-500 mt-0.5' }, p.use_case || ''),
        el('div', { class: 'text-xs text-slate-400 mt-0.5' }, keyWord)
      )
      presetUl.appendChild(li)
    }

    const catUl = document.getElementById('category-list')
    clear(catUl)
    for (const c of state.categories) {
      const isSel = state.view === 'category' && state.selectedCategory === c.name
      const onSelect = () => onSelectCategory(c.name)
      const li = el(
        'li',
        {
          class: `cursor-pointer px-2 py-1.5 rounded min-h-[44px] focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 ${isSel ? 'bg-blue-50 text-blue-900 font-semibold' : 'hover:bg-slate-100'}`,
          // H-new-1: role="option" → "listitem"、aria-selected 削除
          role: 'listitem',
          tabindex: '0',
          'aria-current': isSel ? 'true' : null,
          'aria-label': `カテゴリ ${c.name} (${c.key_count} key)${isSel ? ' (選択中)' : ''}`,
          onclick: onSelect,
          onkeydown: activateOnEnterOrSpace(onSelect),
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
          el('strong', null, 'プリセット'),
          el('span', { class: 'text-slate-600' }, ' または '),
          el('strong', null, 'カテゴリ'),
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
      // M-U4: 動的 panel の見出しは h3 (header h1 / sidebar h2 の下)
      el('h3', { class: 'text-lg font-bold text-slate-800' }, `プリセット: ${state.selectedPreset}`),
      el('p', { class: 'text-sm text-slate-600 mt-1' }, diff && diff.use_case ? diff.use_case : '')
    )

    // axes pills
    if (diff && diff.axes) {
      const pills = el('div', { class: 'flex flex-wrap gap-1.5 mt-2', 'aria-label': '6 軸状態' })
      for (const [k, v] of Object.entries(diff.axes)) {
        pills.appendChild(
          el('span', { class: 'text-xs px-2 py-0.5 bg-slate-100 border border-slate-200 rounded font-mono' }, `${k}=${v}`)
        )
      }
      header.appendChild(pills)

      // Save as Custom Preset button (draft §6 DoD)
      // MED-Q5 iter 4 B: onSaveCustomPreset は現在の yml 6 軸を fetch するため引数なしに変更
      const saveBtn = el(
        'button',
        {
          type: 'button',
          class: 'mt-3 px-3 py-2 text-xs bg-slate-100 hover:bg-slate-200 border border-slate-300 rounded text-slate-800 min-h-[44px]',
          onclick: () => onSaveCustomPreset(),
          'aria-label': '現在の yml 6 軸状態をカスタムプリセットとして保存',
        },
        '⬇ 現在の 6 軸を保存'
      )
      header.appendChild(saveBtn)
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
        { class: 'px-4 py-2 border-b border-slate-200 bg-slate-50 flex items-center justify-between flex-wrap gap-2' },
        el(
          'h4',
          { class: 'text-sm font-semibold text-slate-700' },
          `差分プレビュー: ${changed.length} 変更, ${unchanged.length} 不変`
        ),
        el(
          'div',
          { class: 'flex gap-2' },
          el(
            'button',
            {
              type: 'button',
              class: 'px-3 py-1 text-xs bg-slate-200 hover:bg-slate-300 rounded min-h-[32px]',
              onclick: () => onToggleAllSkip(true),
              'aria-label': 'すべての変更を skip にする',
            },
            'すべて skip'
          ),
          el(
            'button',
            {
              type: 'button',
              class: 'px-3 py-1 text-xs bg-slate-200 hover:bg-slate-300 rounded min-h-[32px]',
              onclick: () => onToggleAllSkip(false),
              'aria-label': 'すべての変更を適用対象にする',
            },
            'すべて適用'
          )
        )
      )
    )

    const table = el('table', { class: 'w-full text-sm', 'aria-label': '差分プレビュー table' })
    const thead = el(
      'thead',
      { class: 'bg-slate-50 text-xs uppercase text-slate-500' },
      el(
        'tr',
        null,
        el('th', { scope: 'col', class: 'text-left px-3 py-2 w-12' }, '適用'),
        el('th', { scope: 'col', class: 'text-left px-3 py-2' }, 'キー'),
        el('th', { scope: 'col', class: 'text-left px-3 py-2' }, '現在値'),
        el('th', { scope: 'col', class: 'text-left px-3 py-2' }, '新しい値'),
        el('th', { scope: 'col', class: 'text-left px-3 py-2' }, 'Effect'),
        el('th', { scope: 'col', class: 'text-left px-3 py-2 w-20' }, '状態')
      )
    )
    table.appendChild(thead)
    const tbody = el('tbody', null)
    for (const c of changes) {
      const isSkip = state.skipKeys[c.key] === true
      // M-new-3 iter 4 B: checkbox aria-label を skip 状態で動的化
      const cbLabel = c.changed
        ? (isSkip ? `${c.key} を適用対象にする (現在: skip)` : `${c.key} を skip にする (現在: 適用対象)`)
        : `${c.key} は変更なし、適用対象外`
      const cbAttrs = {
        type: 'checkbox',
        class: 'w-5 h-5 cursor-pointer',
        'aria-label': cbLabel,
        onchange: (ev) => onToggleSkip(c.key, !ev.target.checked),
      }
      if (!isSkip) cbAttrs.checked = true
      const cb = c.changed
        ? el('input', cbAttrs)
        : el('span', { class: 'text-slate-300', 'aria-label': '変更なし、適用対象外' }, '—')

      // H-U3 color only state → アイコン併用
      const stateCell = c.changed
        ? el(
            'span',
            { class: 'inline-flex items-center gap-1 text-amber-700 font-semibold' },
            el('span', { 'aria-hidden': 'true' }, '●'), // ●
            'changed'
          )
        : el(
            'span',
            { class: 'inline-flex items-center gap-1 text-slate-500' },
            el('span', { 'aria-hidden': 'true' }, '○'), // ○
            'unchanged'
          )

      const effectText = (c.effect !== undefined && c.effect !== null && c.effect !== '') ? String(c.effect) : '—'

      // M-new-3 iter 4 B: tr に aria-label dynamic
      const rowAriaLabel = c.changed
        ? (isSkip ? `${c.key}: skip 対象 (適用しない)` : `${c.key}: 適用対象`)
        : `${c.key}: 変更なし`

      const row = el(
        'tr',
        {
          class: `diff-row border-t border-slate-100 ${isSkip ? 'skip' : ''} ${c.changed ? '' : 'opacity-70'}`,
          'aria-label': rowAriaLabel,
        },
        el('td', { class: 'px-3 py-2' }, cb),
        el('td', { class: 'px-3 py-2 font-mono text-xs text-slate-800' }, c.key),
        el('td', { class: 'px-3 py-2 font-mono text-xs text-slate-600' }, c.current),
        el('td', { class: 'px-3 py-2 font-mono text-xs text-blue-700' }, c.new),
        el('td', { class: 'px-3 py-2 text-xs text-slate-700' }, effectText),
        el('td', { class: 'px-3 py-2 text-xs' }, stateCell)
      )
      tbody.appendChild(row)
    }
    table.appendChild(tbody)
    tableBox.appendChild(table)
    box.appendChild(tableBox)

    // apply button
    const applyCount = changed.length - countSkip(changed)
    const applyDisabled = state.applying || applyCount === 0
    const actions = el(
      'div',
      { class: 'flex items-center gap-3 flex-wrap' },
      el(
        'button',
        {
          type: 'button',
          class: `px-4 py-2 text-sm font-semibold rounded shadow-sm min-h-[44px] ${applyDisabled ? 'bg-emerald-400 text-white opacity-60 cursor-not-allowed' : 'bg-emerald-700 text-white hover:bg-emerald-800'}`,
          onclick: onApplyPreset,
          disabled: applyDisabled,
          'aria-label': state.applying ? '適用処理中...' : `プリセットを適用 (${applyCount} key)`,
          'aria-disabled': applyDisabled ? 'true' : 'false',
        },
        state.applying ? '適用中...' : `プリセットを適用 (${applyCount} key)`
      ),
      el(
        'button',
        {
          type: 'button',
          class: 'px-4 py-2 bg-slate-200 text-slate-800 rounded hover:bg-slate-300 text-sm min-h-[44px]',
          onclick: () => loadPresetDiff(state.selectedPreset).then(() => renderMain()),
          'aria-label': '差分を再計算',
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
        el('h3', { class: 'text-lg font-bold text-slate-800' }, `カテゴリ: ${state.selectedCategory}`),
        el('p', { class: 'text-sm text-slate-600 mt-1' }, `${state.keys.length} 個の key`)
      )
    )

    const tableBox = el('div', { class: 'bg-white rounded-lg border border-slate-200 overflow-hidden' })
    const table = el('table', { class: 'w-full text-sm', 'aria-label': `${state.selectedCategory} カテゴリの key 一覧` })
    table.appendChild(
      el(
        'thead',
        { class: 'bg-slate-50 text-xs uppercase text-slate-500' },
        el(
          'tr',
          null,
          el('th', { scope: 'col', class: 'text-left px-3 py-2' }, 'キー'),
          el('th', { scope: 'col', class: 'text-left px-3 py-2' }, '現在値'),
          el('th', { scope: 'col', class: 'text-left px-3 py-2' }, '説明'),
          el('th', { scope: 'col', class: 'text-left px-3 py-2 w-16' }, '操作')
        )
      )
    )
    const tbody = el('tbody', null)
    for (const k of state.keys) {
      const onEdit = () => onSelectKey(k.key)
      const tr = el(
        'tr',
        {
          class: 'border-t border-slate-100 hover:bg-slate-50 cursor-pointer focus:outline-none focus:bg-blue-50 focus:ring-2 focus:ring-blue-400',
          tabindex: '0',
          role: 'button',
          'aria-label': `${k.key} を編集`,
          onclick: onEdit,
          onkeydown: activateOnEnterOrSpace(onEdit),
        },
        el('td', { class: 'px-3 py-2 font-mono text-xs text-slate-800' }, k.key),
        el('td', { class: 'px-3 py-2 font-mono text-xs text-blue-700' }, k.current_value === null ? '<n/a>' : String(k.current_value)),
        el('td', { class: 'px-3 py-2 text-xs text-slate-700' }, k.description || ''),
        el('td', { class: 'px-3 py-2 text-xs text-blue-700 underline' }, '編集')
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
        // M-U4: panel header h3
        el('h3', { class: 'text-lg font-bold text-slate-800 font-mono break-all' }, key),
        meta.description ? el('p', { class: 'text-sm text-slate-700 mt-2' }, meta.description) : null,
        meta.effect ? el('p', { class: 'text-xs text-slate-600 mt-1' }, `効果: ${meta.effect}`) : null
      )
    )

    const formBox = el('div', { class: 'bg-white rounded-lg border border-slate-200 p-4 space-y-3' })
    formBox.appendChild(el('h4', { class: 'sr-only' }, 'キー値編集フォーム'))

    // C-U2 「現在値」は label + read-only div (関連付け aria-describedby)
    const currentDisplayId = 'key-current-display'
    formBox.appendChild(
      el(
        'div',
        null,
        el(
          'label',
          { class: 'text-xs uppercase text-slate-600 font-semibold', htmlFor: currentDisplayId },
          '現在値'
        ),
        el(
          'output',
          { id: currentDisplayId, class: 'mt-1 block font-mono text-sm bg-slate-100 rounded px-3 py-2', 'aria-live': 'polite' },
          meta.current_value === null ? '<n/a>' : String(meta.current_value)
        )
      )
    )

    // C-U2 「新しい値」は label + input (for=/id= 形式)
    const inputId = 'key-value-input'
    const input = el('input', {
      id: inputId,
      type: 'text',
      class: 'w-full font-mono text-sm border border-slate-300 rounded px-3 py-2 focus:outline-none focus:ring focus:ring-blue-200 min-h-[44px]',
      value: meta.current_value === null ? '' : String(meta.current_value),
      placeholder: '新しい値',
      'aria-describedby': meta.effect ? 'key-effect-hint' : null,
      autocomplete: 'off',
    })
    formBox.appendChild(
      el(
        'div',
        null,
        el(
          'label',
          { class: 'text-xs uppercase text-slate-600 font-semibold', htmlFor: inputId },
          '新しい値'
        ),
        el('div', { class: 'mt-1' }, input),
        meta.effect
          ? el('p', { id: 'key-effect-hint', class: 'text-xs text-slate-600 mt-1' }, `効果ヒント: ${meta.effect}`)
          : null
      )
    )

    formBox.appendChild(
      el(
        'div',
        { class: 'flex gap-2 flex-wrap' },
        el(
          'button',
          {
            type: 'button',
            class: 'px-4 py-2 bg-blue-700 text-white text-sm font-semibold rounded hover:bg-blue-800 min-h-[44px]',
            onclick: () => onApplyKey(key, input.value),
            'aria-label': `${key} の新しい値を適用`,
          },
          '適用'
        ),
        el(
          'button',
          {
            type: 'button',
            class: 'px-4 py-2 bg-slate-200 text-slate-800 text-sm rounded hover:bg-slate-300 min-h-[44px]',
            onclick: () => {
              if (state.selectedCategory) {
                onSelectCategory(state.selectedCategory)
              } else {
                state.view = 'idle'
                renderSidebar()
                renderMain()
              }
            },
            'aria-label': '編集をキャンセル',
          },
          'キャンセル'
        )
      )
    )
    box.appendChild(formBox)
    return box
  }

  // MED-Q1 iter 4 B: history table に Rolled back 列追加 + colspan=6 化
  function renderHistory() {
    const tbody = document.getElementById('history-tbody')
    clear(tbody)
    if (!state.history.length) {
      tbody.appendChild(el('tr', null, el('td', { class: 'py-2 text-slate-400', colspan: 6 }, '履歴なし')))
      return
    }
    for (const h of state.history) {
      // H-U3 失敗時のアイコン併用
      const failedCount = Number(h.failed_count || 0)
      const failedCell = failedCount > 0
        ? el(
            'span',
            { class: 'inline-flex items-center gap-1 text-red-700 font-semibold' },
            el('span', { 'aria-hidden': 'true' }, '⚠'), // ⚠
            String(failedCount)
          )
        : el('span', { class: 'text-slate-500' }, '0')

      // MED-Q1 iter 4 B: rolled_back_count を視覚化
      const rolledBackCount = Number(h.rolled_back_count || 0)
      const rolledBackCell = rolledBackCount > 0
        ? el(
            'span',
            { class: 'inline-flex items-center gap-1 text-amber-700 font-semibold' },
            el('span', { 'aria-hidden': 'true' }, '↺'),
            String(rolledBackCount)
          )
        : el('span', { class: 'text-slate-500' }, '0')

      const rollbackLabel = `${h.timestamp} (preset: ${h.preset || 'unknown'}) をロールバック`
      const rollbackDisabled = state.rollbackInProgress
      const tr = el(
        'tr',
        { class: 'history-row border-t border-slate-100' },
        el('td', { class: 'py-1 pr-3 font-mono text-xs' }, h.timestamp),
        el('td', { class: 'py-1 pr-3 font-mono text-xs' }, h.preset || '<unknown>'),
        el('td', { class: 'py-1 pr-3' }, String(h.applied_count !== undefined ? h.applied_count : '?')),
        el('td', { class: 'py-1 pr-3' }, failedCell),
        el('td', { class: 'py-1 pr-3' }, rolledBackCell),
        el(
          'td',
          { class: 'py-1 pr-3' },
          el(
            'button',
            {
              type: 'button',
              class: `text-xs px-3 py-1.5 bg-amber-100 hover:bg-amber-200 text-amber-900 rounded border border-amber-400 min-h-[32px] ${rollbackDisabled ? 'opacity-60 cursor-not-allowed' : ''}`,
              onclick: () => onRollback(h.timestamp, h.preset || 'unknown', h.applied_count),
              disabled: rollbackDisabled,
              'aria-label': rollbackLabel,
              'aria-disabled': rollbackDisabled ? 'true' : 'false',
            },
            'ロールバック'
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
    setStatus(`プリセット: ${name} の diff を計算中...`)
    renderSidebar()
    renderMain()
    try {
      await loadPresetDiff(name)
      setStatus(`プリセット: ${name}`)
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
    setStatus(`カテゴリ: ${name} を読込中...`)
    renderSidebar()
    renderMain()
    try {
      await loadKeys(name)
      setStatus(`カテゴリ: ${name}`)
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
    // 編集 panel に focus 移動 (a11y)
    setTimeout(() => {
      const inp = document.getElementById('key-value-input')
      if (inp) inp.focus()
    }, 10)
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

  // MED-Q1 iter 4 B: partial failure 時 toast 詳細化
  //   applied / failed / rolled_back / rollback_failed 全列挙
  //   rollback_failed 上位 3 件 + 残数明示
  async function onApplyPreset() {
    if (state.applying) return
    if (!state.selectedPreset || !state.presetDiff) return
    const skipKeys = Object.entries(state.skipKeys)
      .filter(([_, v]) => v === true)
      .map(([k, _]) => k)
    const changed = state.presetDiff.changes.filter((c) => c.changed && !state.skipKeys[c.key])
    if (changed.length === 0) {
      toast('適用対象 key が 0 件です', 'info')
      return
    }
    const confirmed = await showConfirmDialog({
      title: 'プリセット適用の確認',
      bodyLines: [
        `プリセット: ${state.selectedPreset}`,
        `適用対象: ${changed.length} key (skip: ${skipKeys.length} key)`,
        '実行すると harness-config.yml が atomic backup 付きで更新されます。',
      ],
      okLabel: '適用する',
      cancelLabel: 'キャンセル',
      danger: false,
    })
    if (!confirmed) return

    state.applying = true
    renderMain()
    setStatus('適用中...')
    try {
      const r = await applyPresetApi(state.selectedPreset, skipKeys)
      if (r.ok) {
        toast(`適用成功: ${r.applied} key 適用`, 'success')
      } else if (r.partial) {
        // MED-Q1 iter 4 B: partial failure 詳細
        const failedKey = r.aborted_at && r.aborted_at.key ? r.aborted_at.key : '<unknown>'
        const rolledBack = Number(r.rolled_back || 0)
        const rollbackFailed = Number(r.rollback_failed || 0)
        // 詳細 toast (warning)
        const lines = []
        lines.push(`部分失敗: ${failedKey} で停止`)
        lines.push(`成功 0 / 失敗 1 / 復元 ${rolledBack} 件`)
        if (rollbackFailed > 0) {
          lines.push(`復元失敗 ${rollbackFailed} 件 (yml 状態が不整合の可能性、history を確認)`)
        }
        toast(lines.join(' / '), 'warning')
        // 復元失敗は別 toast (error) で強調 (SR alert)
        if (rollbackFailed > 0) {
          toast(`警告: ${rollbackFailed} 件の rollback が失敗、yml 状態確認必須`, 'error')
        }
      } else {
        // 完全失敗 (5xx) は API wrapper で throw されるため通常到達不可
        toast(`適用失敗: ${r.error || 'unknown error'}`, 'error')
      }
      await Promise.all([loadHistory(), loadPresetDiff(state.selectedPreset)])
      setStatus(`プリセット: ${state.selectedPreset}`)
    } catch (e) {
      toast(`適用失敗: ${e.message}`, 'error')
      setStatus('エラー')
    } finally {
      state.applying = false
      renderMain()
      renderHistory()
    }
  }

  async function onApplyKey(key, value) {
    if (!key) return
    if (state.applying) return
    state.applying = true
    setStatus(`${key} を設定中...`)
    try {
      await setKeyApi(key, value)
      toast(`${key} = ${value} を適用しました`, 'success')
      if (state.selectedCategory) {
        await loadKeys(state.selectedCategory)
      }
      setStatus('完了')
      if (state.selectedCategory) {
        state.view = 'category'
        renderMain()
      }
    } catch (e) {
      toast(`適用失敗: ${e.message}`, 'error')
      setStatus('エラー')
    } finally {
      state.applying = false
    }
  }

  async function onRollback(timestamp, presetName, appliedCount) {
    if (state.rollbackInProgress) return
    const confirmed = await showConfirmDialog({
      title: 'ロールバック確認',
      bodyLines: [
        `履歴: ${timestamp}`,
        `元プリセット: ${presetName}`,
        `復元 key 数: 約 ${appliedCount !== undefined ? appliedCount : '?'} 件`,
        '当時の適用前の値に復元します。現在値は上書きされます。',
      ],
      okLabel: 'ロールバック実行',
      cancelLabel: 'キャンセル',
      danger: true,
    })
    if (!confirmed) return

    state.rollbackInProgress = true
    renderHistory()
    setStatus('ロールバック中...')
    try {
      const r = await rollbackApi(timestamp)
      if (r.ok) {
        toast(`ロールバック成功: ${r.restored} key 復元`, 'success')
      } else {
        toast(`部分失敗: ${r.restored} 成功 / ${r.failed} 失敗`, 'warning')
      }
      await loadHistory()
      if (state.view === 'preset' && state.selectedPreset) {
        await loadPresetDiff(state.selectedPreset)
        renderMain()
      } else if (state.view === 'category' && state.selectedCategory) {
        await loadKeys(state.selectedCategory)
        renderMain()
      }
      setStatus('ロールバック完了')
    } catch (e) {
      toast(`ロールバック失敗: ${e.message}`, 'error')
      setStatus('エラー')
    } finally {
      state.rollbackInProgress = false
      renderHistory()
    }
  }

  // MED-Q5 iter 4 B: 「選択中 preset の axes」ではなく「現在の yml 6 軸」を fetch して送信
  //   設計 §6 DoD: 現在の harness-config.yml の 6 軸状態を新規 custom preset として保存
  // API contract iter 4 B: name regex 3-49 char (server.js 領域 A 仕様と整合: ^[a-z0-9][a-z0-9-]{2,48}$)
  async function onSaveCustomPreset() {
    const name = await showPromptDialog({
      title: 'カスタムプリセットとして保存',
      placeholder: 'my-preset',
      validate: (v) => {
        if (!v) return 'プリセット名を入力してください'
        if (!/^[a-z0-9][a-z0-9-]{2,48}$/.test(v)) return '英数字とハイフン (先頭は英数字、3-49 文字) のみ使えます'
        return null
      },
    })
    if (!name) return
    setStatus(`カスタムプリセット ${name} を保存中 (現在の yml 6 軸を取得)...`)
    try {
      // MED-Q5: 現在の yml 値を fetch (選択中 preset の axes ではない)
      const currentAxes = await loadCurrentAxes()
      const missing = AXIS_KEYS.filter((k) => currentAxes[k] === undefined)
      if (missing.length > 0) {
        toast(`保存失敗: 現在 yml で 6 軸が不完全 (欠落: ${missing.join(', ')})`, 'error')
        setStatus('エラー')
        return
      }
      await savePresetApi(name, currentAxes)
      toast(`カスタムプリセット ${name} を保存しました (現在の yml 6 軸)`, 'success')
      await loadPresets()
      renderSidebar()
      setStatus('保存完了')
    } catch (e) {
      toast(`保存失敗: ${e.message}`, 'error')
      setStatus('エラー')
    }
  }

  // ============================================================
  // Tailwind CDN detection (M-U1: link.onerror + MutationObserver 2 段)
  // ============================================================
  function detectTailwind() {
    const warningEl = document.getElementById('cdn-warning')
    if (!warningEl) return

    const cdnLoaded = () => typeof window.tailwind !== 'undefined'
    const hideWarning = () => warningEl.classList.add('hidden')
    const showWarning = () => warningEl.classList.remove('hidden')

    // 1 段目: script tag の onerror で即検知
    const scripts = document.querySelectorAll('script[src*="tailwindcss.com"]')
    let scriptErrored = false
    for (const s of scripts) {
      s.addEventListener('error', () => {
        scriptErrored = true
        showWarning()
      })
    }

    // 2 段目: MutationObserver + polling fallback で window.tailwind 設定検知
    const start = Date.now()
    const timeoutMs = 3000
    const tick = () => {
      if (cdnLoaded()) {
        hideWarning()
        return
      }
      if (scriptErrored) return
      if (Date.now() - start > timeoutMs) {
        showWarning()
        return
      }
      requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
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
