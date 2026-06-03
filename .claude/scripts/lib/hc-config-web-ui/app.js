// hc-config Web UI — task-76 2 分割再設計 (左 preset / 右 category accordion + 上部タブ 設定/履歴)
// vanilla JS + Tailwind CDN, fetch API only, no external deps。
//
// 設計 SSoT: docs/draft/hc-config-web-2pane-redesign.md §3 (2 分割レイアウト / accordion 同時 1 開 /
//   編集→custom 遷移 / 履歴タブ分離 / no-scroll)。task-63 の top/edit 2-view は廃止。
//
// API contract (Step 2 確定):
//   GET /api/presets        → { presets:[{name, display_name_ja, use_case, affected_key_count, group}], axes_schema }
//                             group ∈ {POC, 社内ツール, 本番運用, その他}
//   GET /api/current-preset → 一致: {name, display_name_ja, match_type:'preset', axes}
//                             不一致: {name:'custom', display_name_ja:'未保存変更あり', match_type:'custom', axes:null}
//   GET /api/categories     → { categories:[{name, key_count}] }  実 7 種
//   GET /api/keys?category= → { keys:[{key, category, description, effect, current_value}], total }
//   GET /api/preset/:name/diff → { preset, axes, use_case, changes:[{key, current, new, changed, effect}] }
//   POST /api/set {key,value}  → { ok:true, key, value }   (batch は client で loop)
//   GET /api/preset/history    → { history:[{timestamp, preset, preset_display_name_ja?, applied_at, applied_count, failed_count, rolled_back_count}] }
//   POST /api/preset/rollback/:ts → rollback
//
// State machine (新):
//   tab: 'config' | 'history'
//   presets[]                  : 左ペイン source (group 付き)
//   categories[]               : 右ペイン accordion 見出し source (実 7 category)
//   keysByCategory{}           : category → keys[] cache (lazy load)
//   keyMeta{}                  : key → {category, description, effect, type} (型推定込み)
//   baseline{}                 : key → 保存済 (server) の現在値 (文字列)
//   draft{}                    : key → ユーザ編集後の値 (文字列)。baseline と差分があるものだけ保存対象
//   selectedPreset             : 左で選択中の preset name (preview 中)。編集発生で null + custom 化
//   isCustom                   : 手動編集が発生して custom 状態か (draft §3 「手動編集が発生したら custom」)
//   openCategory               : 現在開いている accordion category 名 (同時 1 つだけ)
//   history[]
//   saving / rollbackInProgress
//
// XSS: DOM 構築は el() builder (textContent / 属性のみ、innerHTML 不使用)。
// a11y: タブ role=tab/aria-selected、accordion は <details>/<summary> でキーボード操作可。
//
;(function () {
  'use strict'

  // ============================================================
  // 定数
  // ============================================================
  // 左ペイン group の表示順 (server の group 値と一致)
  const PRESET_GROUP_ORDER = ['POC', '社内ツール', '本番運用', 'その他']

  // 既知 enum key (select で表示)。/api/keys に enum 情報が無いため client 側 SSoT。
  //   default_preset は 4 enforcement level (modes.md / CommonRules.md 由来)。
  //   mainline_integration_policy は git 統合 policy 3 値 (task-77 §3.5、git-deny.sh が enforcement)。
  const ENUM_OPTIONS = {
    default_preset: ['advisory', 'team-default', 'strict', 'harness-dev'],
    mainline_integration_policy: ['pr-required', 'local-merge', 'local-merge-push'],
  }

  // ============================================================
  // initial state
  // ============================================================
  const initialState = {
    tab: 'config', // 'config' | 'history'
    presets: [],
    categories: [],
    keysByCategory: {}, // category → keys[]
    keyMeta: {}, // key → { category, description, effect, type }
    baseline: {}, // key → server 現在値 (string)
    draft: {}, // key → 編集後値 (string)
    selectedPreset: null,
    isCustom: false,
    openCategory: null,
    history: [],
    saving: false,
    rollbackInProgress: false,
  }

  let state = { ...initialState }

  // ============================================================
  // value type 推定 ('boolean' | 'enum' | 'text')
  //   /api/keys は型 field を持たないため current_value + 既知 enum から推定する。
  // ============================================================
  function inferType(key, value) {
    if (Object.prototype.hasOwnProperty.call(ENUM_OPTIONS, key)) return 'enum'
    const v = value === null || value === undefined ? '' : String(value).trim().toLowerCase()
    if (v === 'true' || v === 'false') return 'boolean'
    return 'text'
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
      const timeoutSuffix = data && data.timed_out === true ? ' (timeout 5s 超過)' : ''
      throw new Error(`${method} ${path} failed: ${detail}${timeoutSuffix}`)
    }
    return data
  }

  const loadPresets = async () => (await api('GET', '/api/presets')).presets || []
  const loadCategories = async () => (await api('GET', '/api/categories')).categories || []
  const loadKeys = async (category) => (await api('GET', `/api/keys?category=${encodeURIComponent(category)}`)).keys || []
  const loadHistory = async () => (await api('GET', '/api/preset/history')).history || []
  const loadPresetDiff = async (name) => await api('GET', `/api/preset/${encodeURIComponent(name)}/diff`)
  const setKeyApi = async (key, value) => await api('POST', '/api/set', { key, value })
  const rollbackApi = async (timestamp) => await api('POST', `/api/preset/rollback/${encodeURIComponent(timestamp)}`)
  const loadCurrentPreset = async () => {
    try {
      const r = await api('GET', '/api/current-preset')
      if (!r.match_type) r.match_type = r.name && r.name !== 'custom' ? 'preset' : 'custom'
      return r
    } catch (e) {
      return { match_type: 'custom', name: 'custom', display_name_ja: '未保存変更あり', axes: null }
    }
  }

  // ============================================================
  // DOM utils (textContent only、innerHTML 禁止 XSS 防止)
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
        else if (k === 'ontoggle') e.addEventListener('toggle', v)
        else if (k === 'htmlFor') e.htmlFor = v
        else if (v === true) e.setAttribute(k, '')
        else if (v === false || v === undefined || v === null) {
          // skip falsy attr
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

  function $(id) {
    return document.getElementById(id)
  }

  // ============================================================
  // toast (error / success / warning / info、絵文字なしテキストアイコン)
  // ============================================================
  function toast(message, type) {
    let cls, icon
    if (type === 'error') { cls = 'bg-red-700 text-white'; icon = '[!]' }
    else if (type === 'success') { cls = 'bg-emerald-700 text-white'; icon = '[OK]' }
    else if (type === 'warning') { cls = 'bg-amber-600 text-white'; icon = '[!]' }
    else if (type === 'info') { cls = 'bg-blue-700 text-white'; icon = '[i]' }
    else { cls = 'bg-slate-800 text-white'; icon = '' }
    const t = el(
      'div',
      {
        class: `pointer-events-auto px-4 py-2 rounded shadow-lg text-sm flex items-center gap-2 ${cls}`,
        // L1: error / warning は role=alert (即時読み上げ)、それ以外は status
        role: (type === 'error' || type === 'warning') ? 'alert' : 'status',
      },
      icon ? el('span', { 'aria-hidden': 'true', class: 'font-mono text-xs' }, icon) : null,
      el('span', null, message)
    )
    const cont = $('toast-container')
    if (cont) cont.appendChild(t)
    setTimeout(() => t.remove(), 4000)
  }

  function setStatus(text) {
    const sb = $('status-text')
    if (sb) sb.textContent = text
  }

  // ============================================================
  // dialog helper (resolved flag で二重 resolve 防止、task-61 から継承)
  // ============================================================
  function showConfirmDialog(opts) {
    return new Promise((resolve) => {
      const dlg = $('confirm-dialog')
      const titleEl = $('confirm-dialog-title')
      const bodyEl = $('confirm-dialog-body')
      const okBtn = $('confirm-dialog-ok')
      const cancelBtn = $('confirm-dialog-cancel')

      titleEl.textContent = opts.title || '確認'
      clear(bodyEl)
      for (const line of opts.bodyLines || []) bodyEl.appendChild(el('p', null, line))
      okBtn.textContent = opts.okLabel || '実行'
      cancelBtn.textContent = opts.cancelLabel || 'キャンセル'
      okBtn.className = opts.danger
        ? 'px-4 py-2 text-sm bg-red-700 hover:bg-red-800 text-white font-semibold rounded min-h-[44px]'
        : 'px-4 py-2 text-sm bg-emerald-600 hover:bg-emerald-700 text-white font-semibold rounded min-h-[44px]'

      let resolved = false
      const safeResolve = (value) => {
        if (resolved) return
        resolved = true
        cleanup()
        resolve(value)
      }
      const onClose = () => safeResolve(dlg.returnValue === 'ok')
      function cleanup() {
        okBtn.removeEventListener('click', okClickHandler)
        cancelBtn.removeEventListener('click', cancelClickHandler)
        dlg.removeEventListener('close', onClose)
        if (dlg.open) {
          try { dlg.close() } catch (e) { /* noop */ }
        }
      }
      const okClickHandler = () => { dlg.returnValue = 'ok'; safeResolve(true) }
      const cancelClickHandler = () => { dlg.returnValue = 'cancel'; safeResolve(false) }
      okBtn.addEventListener('click', okClickHandler)
      cancelBtn.addEventListener('click', cancelClickHandler)
      dlg.addEventListener('close', onClose)
      if (typeof dlg.showModal === 'function') dlg.showModal()
      else dlg.setAttribute('open', '')
      setTimeout(() => cancelBtn.focus(), 10)
    })
  }

  function activateOnEnterOrSpace(action) {
    return (ev) => {
      if (ev.key === 'Enter' || ev.key === ' ' || ev.key === 'Spacebar') {
        ev.preventDefault()
        action(ev)
      }
    }
  }

  // ============================================================
  // derived helpers
  // ============================================================
  // baseline と draft の差分 key (保存対象)
  function changedKeys() {
    const out = []
    for (const key of Object.keys(state.draft)) {
      if (String(state.draft[key]) !== String(state.baseline[key])) out.push(key)
    }
    return out
  }

  function hasChanges() {
    return changedKeys().length > 0
  }

  // 現在の表示値 (draft 優先、無ければ baseline)
  function currentValue(key) {
    return Object.prototype.hasOwnProperty.call(state.draft, key) ? state.draft[key] : state.baseline[key]
  }

  // key の表示ラベル (task-78 Step 2/3): `<key_name> (<label_ja>)`、label 空は key 名のみ。
  //   返り値は textContent でのみ使用 (el() builder 経由) なので XSS 安全。
  function labelJaOf(key) {
    const meta = state.keyMeta[key]
    return meta && meta.label_ja ? String(meta.label_ja) : ''
  }
  function keyDisplayLabel(key) {
    const lj = labelJaOf(key)
    return lj ? `${key} (${lj})` : key
  }

  // ============================================================
  // 左ペイン render (preset を group section 化 + ★ カスタム)
  //   render target: #preset-list
  // ============================================================
  function renderPresetList() {
    const cont = $('preset-list')
    if (!cont) return
    clear(cont)

    if (!state.presets.length) {
      cont.appendChild(el('p', { class: 'text-sm text-slate-400 px-2 py-1' }, '読み込み中...'))
      return
    }

    // group ごとに分類
    const groups = {}
    for (const p of state.presets) {
      const g = p.group || 'その他'
      if (!groups[g]) groups[g] = []
      groups[g].push(p)
    }
    const orderedGroupNames = PRESET_GROUP_ORDER.filter((g) => groups[g] && groups[g].length)
    // 想定外 group も末尾に拾う
    for (const g of Object.keys(groups)) {
      if (!orderedGroupNames.includes(g)) orderedGroupNames.push(g)
    }

    for (const g of orderedGroupNames) {
      cont.appendChild(el('h3', { class: 'preset-group__heading', lang: 'ja' }, g))
      const ul = el('ul', { class: 'preset-group__list', role: 'list', 'aria-label': `${g} のプリセット` })
      for (const p of groups[g]) {
        ul.appendChild(renderPresetItem(p))
      }
      cont.appendChild(ul)
    }

    // ★ カスタム (H3 fix: preset group 'その他' とは独立した「カスタム」見出しにし、
    //   server が 'その他' group の preset を返した場合の見出し重複を防ぐ)
    cont.appendChild(el('h3', { class: 'preset-group__heading', lang: 'ja' }, 'カスタム'))
    const customSel = state.isCustom
    const onCustom = () => { /* custom は選択操作不可 (編集結果として自動遷移)。クリックは no-op */ }
    cont.appendChild(
      el(
        'div',
        {
          class: `preset-item preset-item--custom ${customSel ? 'preset-item--selected' : ''}`,
          role: 'listitem',
          'aria-current': customSel ? 'true' : null,
          lang: 'ja',
          tabindex: '-1',
          onclick: onCustom,
        },
        el('span', { class: 'preset-item__name' }, '★ カスタム'),
        el('span', { class: 'preset-item__sub text-xs text-slate-500' }, '手動編集後の未保存状態')
      )
    )
  }

  function renderPresetItem(p) {
    const isSel = !state.isCustom && state.selectedPreset === p.name
    const onSelect = () => onSelectPreset(p.name)
    return el(
      'li',
      {
        class: `preset-item ${isSel ? 'preset-item--selected' : ''}`,
        role: 'listitem',
        tabindex: '0',
        'data-preset-key': p.name,
        'aria-current': isSel ? 'true' : null,
        'aria-label': `プリセット ${p.display_name_ja || p.name}${isSel ? ' (選択中)' : ''}`,
        onclick: onSelect,
        onkeydown: activateOnEnterOrSpace(onSelect),
        lang: 'ja',
      },
      el('span', { class: 'preset-item__name' }, p.display_name_ja || p.name),
      el('span', { class: 'preset-item__sub text-xs text-slate-400 font-mono' }, p.name),
      p.use_case ? el('span', { class: 'preset-item__sub text-xs text-slate-500', lang: 'ja' }, p.use_case) : null
    )
  }

  // ============================================================
  // 右ペイン render (実 7 category を accordion 化、同時 1 つ開く)
  //   render target: #category-accordion
  // ============================================================
  function renderCategoryAccordion() {
    const cont = $('category-accordion')
    if (!cont) return
    clear(cont)

    if (!state.categories.length) {
      cont.appendChild(el('p', { class: 'text-sm text-slate-400 px-2 py-2' }, '読み込み中...'))
      return
    }

    for (const c of state.categories) {
      const catName = c.name || '(未分類)'
      const isOpen = state.openCategory === catName
      const detailsAttrs = {
        class: 'category-accordion__item',
        'data-category': catName,
        ontoggle: (ev) => onToggleCategory(catName, ev.target.open),
      }
      if (isOpen) detailsAttrs.open = true

      const summary = el(
        'summary',
        { class: 'category-accordion__summary', lang: 'ja' },
        el('span', { class: 'category-accordion__name' }, catName),
        el('span', { class: 'category-accordion__count text-xs text-slate-400' }, `${c.key_count} keys`)
      )

      const bodyChildren = []
      if (isOpen) {
        const keys = state.keysByCategory[catName]
        if (!keys) {
          bodyChildren.push(el('p', { class: 'text-xs text-slate-400 px-3 py-2' }, '読み込み中...'))
        } else if (!keys.length) {
          bodyChildren.push(el('p', { class: 'text-xs text-slate-400 px-3 py-2' }, 'key がありません'))
        } else {
          for (const k of keys) bodyChildren.push(renderKeyRow(k))
        }
      }
      const body = el('div', { class: 'category-accordion__body' }, ...bodyChildren)
      cont.appendChild(el('details', detailsAttrs, summary, body))
    }
  }

  function renderKeyRow(keyObj) {
    const key = keyObj.key
    const meta = state.keyMeta[key] || { type: 'text', description: '', effect: '', label_ja: '' }
    const val = currentValue(key)
    // 変更扱い: draft に key があり baseline と値が異なる (C1/L1 fix: tautology を簡素化)
    const isChanged = Object.prototype.hasOwnProperty.call(state.draft, key) &&
      String(state.draft[key]) !== String(state.baseline[key])

    // M3 fix: control に id を付与し .key-row__name を <label htmlFor=id> にして
    //   ラベルクリックで control に focus が移るようにする。
    const controlId = `keyctl-${key}`
    let control
    if (meta.type === 'boolean') {
      const checked = String(val).trim().toLowerCase() === 'true'
      control = el('input', {
        type: 'checkbox',
        id: controlId,
        class: 'key-row__toggle',
        checked: checked ? true : false,
        'aria-label': `${key} (${checked ? 'on' : 'off'})`,
        onchange: (ev) => onEditKey(key, ev.target.checked ? 'true' : 'false'),
      })
    } else if (meta.type === 'enum') {
      const opts = ENUM_OPTIONS[key] || []
      const sel = el('select', {
        id: controlId,
        class: 'key-row__select',
        'aria-label': key,
        onchange: (ev) => onEditKey(key, ev.target.value),
      })
      const cur = String(val == null ? '' : val)
      // 現在値が既知 option に無い場合も先頭に保持
      const allOpts = opts.includes(cur) ? opts : [cur, ...opts]
      for (const o of allOpts) {
        const optEl = el('option', { value: o }, o)
        if (o === cur) optEl.selected = true
        sel.appendChild(optEl)
      }
      control = sel
    } else {
      control = el('input', {
        type: 'text',
        id: controlId,
        class: 'key-row__text',
        value: val == null ? '' : String(val),
        'aria-label': key,
        oninput: (ev) => onEditKey(key, ev.target.value),
      })
    }

    return el(
      'div',
      { class: `key-row ${isChanged ? 'key-row--changed' : ''}`, 'data-key': key },
      el(
        'div',
        { class: 'key-row__head' },
        el('label', { class: 'key-row__name font-mono', htmlFor: controlId, title: meta.description || '' }, keyDisplayLabel(key)),
        control
      ),
      meta.description ? el('p', { class: 'key-row__desc text-xs text-slate-500', lang: 'ja' }, meta.description) : null,
      meta.effect ? el('p', { class: 'key-row__effect text-xs text-slate-400', lang: 'ja' }, meta.effect) : null
    )
  }

  // ============================================================
  // 保存バー / 状態バッジ update (render の一部、再描画なしで text のみ)
  // ============================================================
  function updateSaveBar() {
    const note = $('save-bar-note')
    const saveBtn = $('btn-save')
    const cancelBtn = $('btn-cancel')
    const n = changedKeys().length
    if (note) {
      note.textContent = state.saving
        ? '保存中...'
        : (n > 0 ? `${n} 件の変更があります` : '変更なし')
    }
    const disabled = state.saving || n === 0
    if (saveBtn) {
      saveBtn.disabled = disabled
      saveBtn.textContent = state.saving ? '保存中...' : '保存'
    }
    if (cancelBtn) cancelBtn.disabled = disabled
    // M5: 変更ありのとき保存バーを視覚強調
    const bar = $('save-bar')
    if (bar) bar.classList.toggle('save-bar--dirty', n > 0 && !state.saving)
  }

  function updateStateBadge() {
    const badge = $('header-state-badge')
    if (!badge) return
    badge.classList.remove('state-badge--preset', 'state-badge--custom')
    if (state.isCustom) {
      badge.textContent = 'カスタム'
      badge.classList.add('state-badge--custom')
    } else if (state.selectedPreset) {
      const p = state.presets.find((x) => x.name === state.selectedPreset)
      badge.textContent = p ? (p.display_name_ja || p.name) : state.selectedPreset
      badge.classList.add('state-badge--preset')
    } else {
      badge.textContent = '—'
    }
  }

  // ============================================================
  // 右サイドバー「変更内容」render (task-78 Step 3、render target: #changes-list)
  //   baseline↔draft 差分を `<label_ja> (<key>): <old> → <new>` で live 表示。
  //   label 空は key のみ。変更 0 件は「変更なし」。textContent のみで XSS 安全。
  // ============================================================
  function renderChangesSidebar() {
    const cont = $('changes-list')
    if (!cont) return
    clear(cont)

    const keys = changedKeys()
    if (!keys.length) {
      cont.appendChild(el('p', { class: 'changes-empty text-xs text-slate-400', lang: 'ja' }, '変更なし'))
      return
    }

    for (const key of keys.slice().sort()) {
      const lj = labelJaOf(key)
      const oldVal = state.baseline[key]
      const newVal = state.draft[key]
      const oldStr = oldVal == null || oldVal === '' ? '(空)' : String(oldVal)
      const newStr = newVal == null || newVal === '' ? '(空)' : String(newVal)
      cont.appendChild(
        el(
          'div',
          { class: 'changes-item', 'data-key': key },
          // 見出し: label (key)。label 空は key のみ。
          lj
            ? el(
                'div',
                { class: 'changes-item__name', lang: 'ja' },
                el('span', { class: 'changes-item__label' }, lj),
                el('span', { class: 'changes-item__key font-mono text-xs text-slate-400' }, ` (${key})`)
              )
            : el('div', { class: 'changes-item__name font-mono' }, key),
          // old → new
          el(
            'div',
            { class: 'changes-item__diff text-xs' },
            el('span', { class: 'changes-item__old' }, oldStr),
            el('span', { class: 'changes-item__arrow', 'aria-hidden': 'true' }, ' → '),
            el('span', { class: 'changes-item__new font-semibold' }, newStr)
          )
        )
      )
    }
  }

  // ============================================================
  // 履歴タブ render (render target: #history-tbody)
  // ============================================================
  function formatHistoryTime(h) {
    if (h.applied_at) {
      const d = new Date(h.applied_at)
      if (!isNaN(d.getTime())) return d.toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo', hour12: false })
    }
    return h.timestamp
  }

  function renderHistory() {
    const tbody = $('history-tbody')
    if (!tbody) return
    clear(tbody)
    if (!state.history.length) {
      tbody.appendChild(el('tr', null, el('td', { class: 'py-2 text-slate-400', colspan: 6 }, '履歴なし')))
      return
    }
    for (const h of state.history) {
      const failedCount = Number(h.failed_count || 0)
      const failedCell = failedCount > 0
        ? el('span', { class: 'text-red-700 font-semibold' }, String(failedCount))
        : el('span', { class: 'text-slate-500' }, '0')
      const rolledBackCount = Number(h.rolled_back_count || 0)
      const rolledBackCell = rolledBackCount > 0
        ? el('span', { class: 'text-amber-700 font-semibold' }, String(rolledBackCount))
        : el('span', { class: 'text-slate-500' }, '0')
      const presetDisplay = h.preset_display_name_ja || h.preset || '<unknown>'
      const rollbackDisabled = state.rollbackInProgress
      const tr = el(
        'tr',
        { class: 'history-row border-t border-slate-100' },
        el('td', { class: 'py-1 pr-3 font-mono text-xs' }, formatHistoryTime(h)),
        el('td', { class: 'py-1 pr-3 text-xs', lang: 'ja' }, presetDisplay),
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
              onclick: () => onRollback(h.timestamp, presetDisplay, h.applied_count),
              disabled: rollbackDisabled,
              'aria-label': `${h.timestamp} (preset: ${presetDisplay}) をロールバック`,
            },
            'この時点へ戻す'
          )
        )
      )
      tbody.appendChild(tr)
    }
  }

  // ============================================================
  // tab 切替 (DOM 属性 + panel hidden 切替)
  // ============================================================
  function applyTabUI() {
    const isConfig = state.tab === 'config'
    const tabConfig = $('tab-config')
    const tabHistory = $('tab-history')
    const panelConfig = $('panel-config')
    const panelHistory = $('panel-history')
    if (tabConfig) { tabConfig.setAttribute('aria-selected', isConfig ? 'true' : 'false'); tabConfig.tabIndex = isConfig ? 0 : -1 }
    if (tabHistory) { tabHistory.setAttribute('aria-selected', isConfig ? 'false' : 'true'); tabHistory.tabIndex = isConfig ? -1 : 0 }
    if (panelConfig) panelConfig.classList.toggle('hidden', !isConfig)
    if (panelHistory) panelHistory.classList.toggle('hidden', isConfig)
  }

  function switchTab(tab) {
    state = { ...state, tab }
    applyTabUI()
    if (tab === 'history') renderHistory()
  }

  // ============================================================
  // master render (設定タブの再描画)
  // ============================================================
  function render() {
    renderPresetList()
    renderCategoryAccordion()
    updateSaveBar()
    updateStateBadge()
    renderChangesSidebar()
  }

  // ============================================================
  // event: accordion 開閉 (同時 1 つだけ開く)
  // ============================================================
  async function onToggleCategory(catName, isOpen) {
    if (isOpen) {
      if (state.openCategory === catName) return
      state = { ...state, openCategory: catName }
      // 当該 category の keys を未取得なら lazy load
      if (!state.keysByCategory[catName]) {
        try {
          const keys = await loadKeys(catName)
          const byCat = { ...state.keysByCategory, [catName]: keys }
          const meta = { ...state.keyMeta }
          const baseline = { ...state.baseline }
          for (const k of keys) {
            meta[k.key] = {
              category: k.category,
              description: k.description,
              effect: k.effect,
              label_ja: k.label_ja || '',
              type: inferType(k.key, k.current_value),
            }
            // baseline は初回 load 時のみ (編集中 draft を壊さない)
            if (!Object.prototype.hasOwnProperty.call(baseline, k.key)) {
              baseline[k.key] = k.current_value == null ? '' : String(k.current_value)
            }
          }
          state = { ...state, keysByCategory: byCat, keyMeta: meta, baseline }
        } catch (e) {
          toast(`設定値の取得に失敗: ${e.message}`, 'error')
        }
      }
      // 他 category を閉じるため再描画
      render()
    } else {
      // close: state も閉に同期 (再描画はしない、details の DOM 状態に追従)
      if (state.openCategory === catName) state = { ...state, openCategory: null }
    }
  }

  // ============================================================
  // event: key 編集 (draft 更新 → custom 化)
  // ============================================================
  function onEditKey(key, value) {
    const draft = { ...state.draft, [key]: String(value) }
    // baseline と一致に戻ったら draft から除去 (= 変更なし扱い)
    if (String(value) === String(state.baseline[key])) {
      delete draft[key]
    }
    // 手動編集が発生したら custom (draft §3「手動編集が発生したら custom」)。
    //   全 draft を baseline に戻して stillHasChange===false なら custom 状態も解除する
    //   (H4 fix: isCustom を true 据え置きにすると「★ カスタム」が居座る)。
    const stillHasChange = Object.keys(draft).some((k) => String(draft[k]) !== String(state.baseline[k]))
    state = {
      ...state,
      draft,
      isCustom: stillHasChange,
      selectedPreset: stillHasChange ? null : state.selectedPreset,
    }
    // text input は再描画で focus を失わないよう、保存バー / バッジのみ更新 + 左ペインのみ再描画。
    //   中央 accordion は再描画しない (input の focus 維持)。右サイドバーは別 DOM のため live 再描画可。
    renderPresetList()
    updateSaveBar()
    updateStateBadge()
    renderChangesSidebar()
  }

  // ============================================================
  // event: preset 選択 (diff を draft に反映、preview)
  // ============================================================
  async function onSelectPreset(presetName) {
    setStatus(`プリセット ${presetName} を読み込み中...`)
    try {
      const diff = await loadPresetDiff(presetName)
      const draft = { ...state.draft }
      const baseline = { ...state.baseline }
      const meta = { ...state.keyMeta }
      for (const c of (diff.changes || [])) {
        // diff.current は server 現在値 = baseline。未取得 key の baseline を補完。
        if (c.current !== '<unknown>' && !Object.prototype.hasOwnProperty.call(baseline, c.key)) {
          baseline[c.key] = String(c.current)
        }
        // preset 値を draft に反映 (preview)
        draft[c.key] = String(c.new)
        if (c.current !== '<unknown>' && String(c.new) === String(baseline[c.key])) {
          delete draft[c.key] // 値が同一なら draft 不要
        }
        if (!meta[c.key]) {
          meta[c.key] = { category: '', description: '', effect: c.effect || '', label_ja: '', type: inferType(c.key, c.new) }
        }
      }
      state = {
        ...state,
        draft,
        baseline,
        keyMeta: meta,
        selectedPreset: presetName,
        isCustom: false,
      }
      render()
      const p = state.presets.find((x) => x.name === presetName)
      const dn = p ? (p.display_name_ja || p.name) : presetName
      setStatus(`プリセット「${dn}」を選択 (未保存プレビュー)`)
    } catch (e) {
      toast(`差分取得失敗: ${e.message}`, 'error')
      setStatus('エラー')
    }
  }

  // ============================================================
  // event: 保存 (変更のあった key だけ /api/set で loop)
  // ============================================================
  async function onClickSave() {
    if (state.saving) return
    const keys = changedKeys()
    if (!keys.length) {
      toast('変更がありません', 'info')
      return
    }
    const confirmed = await showConfirmDialog({
      title: '保存の確認',
      bodyLines: [
        `${keys.length} 件の設定値を harness-config.yml に保存します。`,
        '各 key は atomic backup 付きで個別に更新されます。',
      ],
      okLabel: '保存する',
      cancelLabel: 'キャンセル',
      danger: false,
    })
    if (!confirmed) return

    state = { ...state, saving: true }
    updateSaveBar()
    setStatus('保存中...')
    let ok = 0
    let failed = 0
    const newBaseline = { ...state.baseline }
    for (const key of keys) {
      try {
        await setKeyApi(key, state.draft[key])
        newBaseline[key] = String(state.draft[key])
        ok += 1
      } catch (e) {
        failed += 1
        toast(`${key} の保存に失敗: ${e.message}`, 'error')
      }
    }
    // baseline を保存済値で更新、draft から保存成功分を除去
    const newDraft = { ...state.draft }
    for (const key of keys) {
      if (String(newDraft[key]) === String(newBaseline[key])) delete newDraft[key]
    }
    state = { ...state, saving: false, baseline: newBaseline, draft: newDraft }

    if (failed === 0) toast(`保存成功: ${ok} 件`, 'success')
    else toast(`部分保存: ${ok} 成功 / ${failed} 失敗`, 'warning')

    // 保存後に現在 preset を再判定 (バッジ update)
    try {
      const cp = await loadCurrentPreset()
      if (cp.match_type === 'preset') {
        state = { ...state, isCustom: false, selectedPreset: cp.name }
      } else {
        state = { ...state, isCustom: hasChanges() ? state.isCustom : false }
        if (!hasChanges()) state = { ...state, isCustom: true } // 保存済だが preset 不一致 = custom
      }
      const newHistory = await loadHistory()
      state = { ...state, history: newHistory }
    } catch (e) {
      // バッジ再判定失敗は致命的でない
    }
    render()
    renderHistory()
    setStatus('保存完了')
  }

  // ============================================================
  // event: 取消 (編集破棄、server から再 load)
  // ============================================================
  async function onClickCancel() {
    if (state.saving) return
    state = { ...state, draft: {}, isCustom: false }
    // 開いている category を再 load (baseline = server 値で表示が戻る)
    const cat = state.openCategory
    if (cat) {
      try {
        const keys = await loadKeys(cat)
        const byCat = { ...state.keysByCategory, [cat]: keys }
        const baseline = { ...state.baseline }
        const meta = { ...state.keyMeta }
        for (const k of keys) {
          baseline[k.key] = k.current_value == null ? '' : String(k.current_value)
          meta[k.key] = { category: k.category, description: k.description, effect: k.effect, label_ja: k.label_ja || '', type: inferType(k.key, k.current_value) }
        }
        state = { ...state, keysByCategory: byCat, baseline, keyMeta: meta }
      } catch (e) { /* noop */ }
    }
    // 現在 preset 再判定
    try {
      const cp = await loadCurrentPreset()
      state = { ...state, selectedPreset: cp.match_type === 'preset' ? cp.name : null, isCustom: cp.match_type !== 'preset' }
    } catch (e) { /* noop */ }
    render()
    setStatus('編集を破棄しました')
  }

  // ============================================================
  // event: rollback (履歴タブ)
  // ============================================================
  async function onRollback(timestamp, presetDisplayName, appliedCount) {
    if (state.rollbackInProgress) return
    const confirmed = await showConfirmDialog({
      title: 'ロールバック確認',
      bodyLines: [
        `履歴: ${timestamp}`,
        `元プリセット: ${presetDisplayName}`,
        `復元 key 数: 約 ${appliedCount !== undefined ? appliedCount : '?'} 件`,
        '当時の適用前の値に復元します。現在値は上書きされます。',
      ],
      okLabel: 'ロールバック実行',
      cancelLabel: 'キャンセル',
      danger: true,
    })
    if (!confirmed) return

    state = { ...state, rollbackInProgress: true }
    renderHistory()
    setStatus('ロールバック中...')
    try {
      const r = await rollbackApi(timestamp)
      if (r.ok) toast(`ロールバック成功: ${r.restored} 件復元`, 'success')
      else toast(`部分失敗: ${r.restored} 成功 / ${r.failed} 失敗`, 'warning')
      // 設定値 / 現在 preset / 履歴を再取得
      await reloadAfterMutation()
      setStatus('ロールバック完了')
    } catch (e) {
      toast(`ロールバック失敗: ${e.message}`, 'error')
      setStatus('エラー')
    } finally {
      state = { ...state, rollbackInProgress: false }
      renderHistory()
    }
  }

  // server 値が変わった後の再 load (rollback 後など)
  async function reloadAfterMutation() {
    // 開いている category の keys を fresh load + baseline 更新 + draft クリア
    const cat = state.openCategory
    const byCat = { ...state.keysByCategory }
    const baseline = { ...state.baseline }
    const meta = { ...state.keyMeta }
    if (cat) {
      try {
        const keys = await loadKeys(cat)
        byCat[cat] = keys
        for (const k of keys) {
          baseline[k.key] = k.current_value == null ? '' : String(k.current_value)
          meta[k.key] = { category: k.category, description: k.description, effect: k.effect, label_ja: k.label_ja || '', type: inferType(k.key, k.current_value) }
        }
      } catch (e) { /* noop */ }
    }
    let cp
    try { cp = await loadCurrentPreset() } catch (e) { cp = { match_type: 'custom', name: 'custom' } }
    let history = state.history
    try { history = await loadHistory() } catch (e) { /* noop */ }
    state = {
      ...state,
      keysByCategory: byCat,
      baseline,
      keyMeta: meta,
      draft: {},
      selectedPreset: cp.match_type === 'preset' ? cp.name : null,
      isCustom: cp.match_type !== 'preset',
      history,
    }
    render()
    renderHistory()
  }

  // ============================================================
  // Tailwind CDN detection (task-61 から継承)
  // ============================================================
  function detectTailwind() {
    const warningEl = $('cdn-warning')
    if (!warningEl) return
    const cdnLoaded = () => typeof window.tailwind !== 'undefined'
    const hideWarning = () => warningEl.classList.add('hidden')
    const showWarning = () => warningEl.classList.remove('hidden')
    const scripts = document.querySelectorAll('script[src*="tailwindcss.com"]')
    let scriptErrored = false
    for (const s of scripts) {
      s.addEventListener('error', () => { scriptErrored = true; showWarning() })
    }
    const start = Date.now()
    const timeoutMs = 3000
    const tick = () => {
      if (cdnLoaded()) { hideWarning(); return }
      if (scriptErrored) return
      if (Date.now() - start > timeoutMs) { showWarning(); return }
      requestAnimationFrame(tick)
    }
    requestAnimationFrame(tick)
  }

  // ============================================================
  // 静的 DOM の event 配線 (タブ / 保存 / 取消)
  // ============================================================
  function wireStaticControls() {
    const tabConfig = $('tab-config')
    const tabHistory = $('tab-history')
    if (tabConfig) {
      tabConfig.addEventListener('click', () => switchTab('config'))
      tabConfig.addEventListener('keydown', (ev) => {
        if (ev.key === 'ArrowRight' || ev.key === 'ArrowLeft') { ev.preventDefault(); $('tab-history').focus(); switchTab('history') }
      })
    }
    if (tabHistory) {
      tabHistory.addEventListener('click', () => switchTab('history'))
      tabHistory.addEventListener('keydown', (ev) => {
        if (ev.key === 'ArrowRight' || ev.key === 'ArrowLeft') { ev.preventDefault(); $('tab-config').focus(); switchTab('config') }
      })
    }
    const saveBtn = $('btn-save')
    const cancelBtn = $('btn-cancel')
    if (saveBtn) saveBtn.addEventListener('click', onClickSave)
    if (cancelBtn) cancelBtn.addEventListener('click', onClickCancel)
  }

  // ============================================================
  // init
  // ============================================================
  async function init() {
    setStatus('読み込み中...')
    detectTailwind()
    wireStaticControls()
    applyTabUI()
    try {
      const [presets, categories, currentPreset, history] = await Promise.all([
        loadPresets(),
        loadCategories(),
        loadCurrentPreset(),
        loadHistory(),
      ])
      state = {
        ...state,
        presets,
        categories,
        history,
        selectedPreset: currentPreset && currentPreset.match_type === 'preset' ? currentPreset.name : null,
        isCustom: !(currentPreset && currentPreset.match_type === 'preset'),
        // 初期は先頭 category を開く (右ペインが空白に見えないように)
        openCategory: categories.length ? (categories[0].name || null) : null,
      }
      // 先頭 category の keys を先読み
      if (state.openCategory) {
        try {
          const keys = await loadKeys(state.openCategory)
          const meta = {}
          const baseline = {}
          for (const k of keys) {
            meta[k.key] = { category: k.category, description: k.description, effect: k.effect, label_ja: k.label_ja || '', type: inferType(k.key, k.current_value) }
            baseline[k.key] = k.current_value == null ? '' : String(k.current_value)
          }
          state = { ...state, keysByCategory: { [state.openCategory]: keys }, keyMeta: meta, baseline }
        } catch (e) { /* noop、accordion 開時に再試行 */ }
      }
      render()
      renderHistory()
      const cpName = currentPreset && currentPreset.match_type === 'preset'
        ? (currentPreset.display_name_ja || currentPreset.name)
        : 'カスタム'
      setStatus(`Ready (${cpName} / ${presets.length} presets / ${categories.length} categories)`)
    } catch (e) {
      toast(`初期化失敗: ${e.message}`, 'error')
      setStatus('エラー (server 起動を確認してください)')
    }
  }

  // expose for smoke / debugging (grep verify 用、task-76 Step 7 smoke が参照)
  window.__hcConfigUi = {
    inferType,
    changedKeys: () => changedKeys(),
    keyDisplayLabel,
    renderChangesSidebar,
    initialState,
    PRESET_GROUP_ORDER,
    ENUM_OPTIONS,
    getState: () => state,
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init)
  } else {
    init()
  }
})()
