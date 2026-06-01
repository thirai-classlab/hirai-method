// hc-config Web UI — task-63 設計簡素化版 (top/edit 2-view、カスタム保存撤去)
// vanilla JS + Tailwind CDN, fetch API only, no external deps
//
// 起源: docs/draft/hc-config-web-ui-ux-redesign.md §3.5 / §3.7 / §3.9
//        + user 確定要求「プリセット名保存不要」(task-63 設計簡素化)
//
// State machine:
//   view: 'top' | 'edit'
//   - top   : 起動時の現状確認 view (現在 preset 名 banner + 6 軸 read-only table / unsaved カスタム表示 + 「設定を変更」CTA)
//   - edit  : 設定編集 view (preset list 日本語名 + 「適用」「キャンセル」)
//
// task-61 から継承:
//   - WCAG 2.2 AA (iter 2 16 SC 全 closure / iter 4 B 7 件)
//   - C-U1 / C-U2 / H-U1 / H-U3 / H-U4 / H-XSS / M-U3 / M-U4
//   - dialog helpers (showConfirmDialog with resolved flag)
//
// task-63 簡素化版 + task-65 (6 軸 data model 案 A):
//   - state.view 'top' | 'edit' 排他切替
//   - state.currentPreset (起動時 /api/current-preset fetch)。
//       preset 一致: { match_type:'preset', name, display_name_ja, axes:{6 軸 object} }
//       unsaved    : { match_type:'unsaved', name:'custom', display_name_ja, axes:null }
//   - state.editPresetSelection (編集画面 preset 選択中の英 key)
//   - reducer(state, action) Pure Function (副作用なし、state 不変更新)
//   - renderTop(state) / renderEdit(state) (state → DOM)
//   - top view は cp.axes 直接参照 (object→6 軸 table / null→カスタム表示)
//   - getDisplayName(preset) (display_name_ja 優先、fallback name)
//   - カスタム保存機能撤去 (showPromptDialog / savePresetApi / edit:save_custom action 削除)
//   - task-65: 6 軸 dropdown 個別編集撤去 (loadCurrentAxes / loadAxesWithOptions / setKeyApi /
//     onChangeAxis / applyIndividualMode / editMode / editAxisChanges / edit:change_axis 全削除)。
//     編集経路は preset 一括変更に一本化。
//   - 絵文字なし (user F1 確定要求)
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
  // 軸日本語ラベル (draft §3.4 wireframe text 準拠)
  // ============================================================
  const AXIS_LABELS_JA = {
    quality_level: '品質レベル',
    language_framework: '言語・FW',
    git_workflow: 'Git 運用',
    tdd_policy: 'TDD ポリシー',
    review_intensity: 'レビュー強度',
    autonomy_level: '自律度',
  }

  // ============================================================
  // initial state
  // ============================================================
  const initialState = {
    view: 'top', // 'top' | 'edit'  (task-63 採用、task-61 'idle'/'category'/'key'/'preset' 廃止)
    // task-65: currentPreset.axes は API response 由来。
    //   preset 一致: { match_type:'preset', name, display_name_ja, axes:{6 軸 object} }
    //   unsaved    : { match_type:'unsaved', name:'custom', display_name_ja, axes:null }
    currentPreset: null,
    presets: [], // [{ name, display_name_ja, ... }] (server /api/presets)
    history: [],
    // edit view 内 sub-state (task-65: 6 軸個別編集撤去により preset 選択のみ)
    editPresetSelection: null, // 選択中 preset 英 key
    editPresetDiff: null, // diff preview (preset 選択時)
    // UI flag
    applying: false,
    rollbackInProgress: false,
  }

  // ============================================================
  // mutable state holder (reducer 経由のみ更新)
  // ============================================================
  let state = { ...initialState }

  // ============================================================
  // reducer (Pure Function、副作用なし、新 state を return)
  // 起源: draft §3.7
  // ============================================================
  function reducer(prevState, action) {
    if (!action || !action.type) return prevState
    switch (action.type) {
      case 'load:current': {
        // payload: { currentPreset, presets, history }
        return {
          ...prevState,
          currentPreset: action.payload.currentPreset || prevState.currentPreset,
          presets: action.payload.presets !== undefined ? action.payload.presets : prevState.presets,
          history: action.payload.history !== undefined ? action.payload.history : prevState.history,
          view: 'top',
        }
      }
      case 'top:enter': {
        // edit → top 戻り、編集 buffer を破棄 (task-65: editMode / 個別変更 state 撤去)
        return {
          ...prevState,
          view: 'top',
          editPresetSelection: null,
          editPresetDiff: null,
        }
      }
      case 'edit:enter': {
        // top → edit (task-65: preset 選択のみ、6 軸 baseline snapshot 撤去)
        return {
          ...prevState,
          view: 'edit',
          editPresetSelection: null,
          editPresetDiff: null,
        }
      }
      case 'edit:select_preset': {
        // payload: { presetName, diff }
        return {
          ...prevState,
          editPresetSelection: action.payload.presetName,
          editPresetDiff: action.payload.diff || null,
        }
      }
      case 'edit:cancel': {
        return reducer(prevState, { type: 'top:enter' })
      }
      case 'edit:apply': {
        // 適用後は top 復帰、currentPreset は payload で更新。
        // applying flag を必ず false に戻す (部分失敗パスでも applying 残留を防ぐ。
        //   catch 節以外の成功/部分失敗パスは明示 reset が無いため、apply 完了 action で集中 reset)
        return {
          ...prevState,
          view: 'top',
          editPresetSelection: null,
          editPresetDiff: null,
          applying: false,
          currentPreset: action.payload && action.payload.currentPreset ? action.payload.currentPreset : prevState.currentPreset,
        }
      }
      case 'ui:set_flag': {
        // payload: { flag: 'applying'|'rollbackInProgress', value: bool }
        return { ...prevState, [action.payload.flag]: action.payload.value }
      }
      case 'history:update': {
        return { ...prevState, history: action.payload.history || [] }
      }
      default:
        return prevState
    }
  }

  function dispatch(action) {
    state = reducer(state, action)
    render()
  }

  // ============================================================
  // getDisplayName (display_name_ja 優先、fallback name)
  // ============================================================
  function getDisplayName(preset) {
    if (!preset) return ''
    if (preset.display_name_ja && typeof preset.display_name_ja === 'string' && preset.display_name_ja.length > 0) {
      return preset.display_name_ja
    }
    return preset.name || ''
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

  const loadPresets = async () => {
    const r = await api('GET', '/api/presets')
    return r.presets || []
  }
  const loadHistory = async () => {
    const r = await api('GET', '/api/preset/history')
    return r.history || []
  }
  // task-63: 起動時に /api/current-preset で現在 preset 判定
  //   draft §3.6 仕様: { match_type: 'preset'|'unsaved', name, display_name_ja, axes } (custom 撤去済 draft §8)
  //   server 互換補正: match_type 不在で name == 'custom' / 'unsaved' の旧 server response も unsaved に正規化
  const loadCurrentPreset = async () => {
    try {
      const r = await api('GET', '/api/current-preset')
      // 互換: server 側で match_type 欠落時、name から推定
      if (!r.match_type) {
        if (r.name === 'custom') r.match_type = 'unsaved'
        else if (r.name === 'unsaved') r.match_type = 'unsaved'
        else if (r.name) r.match_type = 'preset'
        else r.match_type = 'unsaved'
      }
      return r
    } catch (e) {
      // task-65: /api/current-preset 取得失敗時は unsaved 扱い (axes:null)。
      //   (旧 loadCurrentAxes fallback は 6 軸が yml key でなく常に空を返すため撤去)
      return { match_type: 'unsaved', name: null, display_name_ja: null, axes: null }
    }
  }
  const loadPresetDiff = async (name) => {
    const r = await api('GET', `/api/preset/${encodeURIComponent(name)}/diff`)
    return r
  }
  const applyPresetApi = async (name, skipKeys) => {
    return await api('POST', `/api/preset/${encodeURIComponent(name)}/apply`, { skip_keys: skipKeys || [] })
  }
  // task-65: setKeyApi (個別 key set) は 6 軸 dropdown 撤去により呼出元消失のため削除。
  const rollbackApi = async (timestamp) => {
    return await api('POST', `/api/preset/rollback/${encodeURIComponent(timestamp)}`)
  }
  // task-65: loadCurrentAxes / loadAxesWithOptions は撤去。
  //   6 軸 (quality_level 等) は yml raw key ではなく preset metadata のため、/api/keys からの
  //   軸 key 抽出は常に空を返す dead path だった。top view は /api/current-preset の axes を直接
  //   参照し、edit view の 6 軸 dropdown は撤去 (編集経路は preset 一括変更に一本化)。

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
  // task-63: 絵文字なし、テキストアイコンのみ
  // ============================================================
  function toast(message, type) {
    let cls
    let icon
    if (type === 'error') { cls = 'bg-red-700 text-white'; icon = '[!]' }
    else if (type === 'success') { cls = 'bg-emerald-700 text-white'; icon = '[OK]' }
    else if (type === 'warning') { cls = 'bg-amber-600 text-white'; icon = '[!]' }
    else if (type === 'info') { cls = 'bg-blue-700 text-white'; icon = '[i]' }
    else { cls = 'bg-slate-800 text-white'; icon = '' }
    const t = el(
      'div',
      {
        class: `pointer-events-auto px-4 py-2 rounded shadow-lg text-sm flex items-center gap-2 ${cls}`,
        role: type === 'error' ? 'alert' : 'status',
      },
      icon ? el('span', { 'aria-hidden': 'true', class: 'font-mono text-xs' }, icon) : null,
      el('span', null, message)
    )
    const cont = document.getElementById('toast-container')
    if (cont) cont.appendChild(t)
    setTimeout(() => t.remove(), 4000)
  }

  function setStatus(text) {
    const sb = document.getElementById('status-text')
    if (sb) sb.textContent = text
  }

  // ============================================================
  // dialog helpers (task-61 から継承、resolved flag で二重 resolve 防止)
  // ============================================================
  function showConfirmDialog(opts) {
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
      const onOk = () => safeResolve(true)
      const onCancel = () => safeResolve(false)
      const onClose = () => safeResolve(dlg.returnValue === 'ok')

      function cleanup() {
        okBtn.removeEventListener('click', okClickHandler)
        cancelBtn.removeEventListener('click', cancelClickHandler)
        dlg.removeEventListener('close', onClose)
        if (dlg.open) {
          try { dlg.close() } catch (e) { /* noop */ }
        }
      }
      const okClickHandler = () => { dlg.returnValue = 'ok'; onOk() }
      const cancelClickHandler = () => { dlg.returnValue = 'cancel'; onCancel() }
      okBtn.addEventListener('click', okClickHandler)
      cancelBtn.addEventListener('click', cancelClickHandler)
      dlg.addEventListener('close', onClose)
      if (typeof dlg.showModal === 'function') dlg.showModal()
      else dlg.setAttribute('open', '')
      setTimeout(() => cancelBtn.focus(), 10)
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
  // task-65: 6 軸 read-only table builder (preset 一致時)
  //   axes = matched preset の axes object (6 key)。日本語ラベル (AXIS_LABELS_JA) + 値で表示。
  // ============================================================
  function renderAxesTable(axes) {
    const tableBox = el('div', { class: 'bg-white rounded-lg border border-slate-200 overflow-hidden' })
    tableBox.appendChild(
      el(
        'div',
        { class: 'px-4 py-2 border-b border-slate-200 bg-slate-50' },
        el('h3', { class: 'text-sm font-semibold text-slate-700' }, '設定内容 (6 軸)')
      )
    )
    const table = el(
      'table',
      { class: 'w-full text-sm', 'aria-label': '現在の 6 軸設定 (読み取り専用)' },
      el(
        'caption',
        { class: 'sr-only' },
        '現在の harness-config.yml の 6 軸状態 (品質レベル / 言語フレームワーク / Git 運用 / TDD ポリシー / レビュー強度 / 自律度)'
      )
    )
    const thead = el(
      'thead',
      { class: 'bg-slate-50 text-xs uppercase text-slate-500' },
      el(
        'tr',
        null,
        el('th', { scope: 'col', class: 'text-left px-3 py-2' }, '軸'),
        el('th', { scope: 'col', class: 'text-left px-3 py-2' }, '現在値')
      )
    )
    table.appendChild(thead)
    const tbody = el('tbody', null)
    for (const k of AXIS_KEYS) {
      const labelJa = AXIS_LABELS_JA[k] || k
      // task-65 iter2 (ui M-2): HTML タグ風 `<未設定>` 表示の誤解を避け '—' に変更。
      const val = axes[k] !== undefined && axes[k] !== null ? String(axes[k]) : '—'
      tbody.appendChild(
        el(
          'tr',
          { class: 'border-t border-slate-100' },
          // task-65 iter2 (ui M-3 / WCAG 1.3.1): 軸名 (ラベル) 列を th scope="row" で row header 化。
          el(
            'th',
            { scope: 'row', class: 'px-3 py-2 text-left font-normal', lang: 'ja' },
            el('span', { class: 'font-semibold text-slate-700' }, labelJa),
            el('span', { class: 'text-xs text-slate-400 ml-2 font-mono' }, k)
          ),
          el('td', { class: 'px-3 py-2 font-mono text-sm text-blue-700' }, val)
        )
      )
    }
    table.appendChild(tbody)
    tableBox.appendChild(table)
    return tableBox
  }

  // ============================================================
  // task-65: unsaved (axes:null) 時のカスタム表示 panel
  //   preset 外 (unsaved) では 6 軸の現在値が一意に定まらないため、6 軸 table の代わりに
  //   「カスタム設定 (プリセット外)」見出し + 説明を表示。どの設定が preset と異なるかは
  //   edit view の preset 選択 diff preview で確認する導線に委ねる (top view では一意 diff 不能)。
  // ============================================================
  function renderCustomPanel() {
    return el(
      'div',
      {
        class: 'bg-white rounded-lg border border-slate-200 p-4',
        role: 'region',
        'aria-labelledby': 'custom-panel-heading',
        lang: 'ja',
      },
      el('h3', { id: 'custom-panel-heading', class: 'text-sm font-semibold text-slate-700 mb-1' }, 'カスタム設定 (プリセット外)'),
      el(
        'p',
        { class: 'text-sm text-slate-600' },
        '現在の設定はどの組み込みプリセットにも一致しません (未保存変更あり)。'
      ),
      el(
        'p',
        { class: 'text-xs text-slate-500 mt-1' },
        'プリセットとの差分は「設定を変更」からプリセットを選ぶと確認できます。'
      )
    )
  }

  // ============================================================
  // render: top view (現状確認 + 「設定を変更」CTA)
  // 起源: draft §3.4 wireframe
  // a11y: banner region + table read-only + CTA button focus ring
  // ============================================================
  function renderTop(currentState) {
    const cp = currentState.currentPreset
    const box = el('section', {
      class: 'space-y-4',
      'aria-labelledby': 'top-view-heading',
      role: 'region',
      lang: 'ja',
    })

    box.appendChild(
      el('h2', { id: 'top-view-heading', class: 'sr-only' }, '現在の設定')
    )

    // 現在 preset banner
    //   task-65 iter2 (ui H-1 / code-rev M2): server は 'preset'/'unsaved' のみ返す
    //   ('custom' は task-63 で廃止)。2-state (preset / else=unsaved) に collapse。
    const matchType = cp && cp.match_type === 'preset' ? 'preset' : 'unsaved'
    let bannerLabel = ''
    let bannerValue = ''
    if (matchType === 'preset') {
      bannerLabel = 'プリセット'
      bannerValue = getDisplayName(cp) || '(不明)'
    } else {
      bannerLabel = '状態'
      bannerValue = '未保存変更あり (どのプリセットにも一致しません)'
    }
    // task-65 iter2 (ui H-2): matchType 応じた状態別カラークラス (style.css L133-149 定義済の amber/emerald)。
    const bannerStateClass = matchType === 'preset' ? 'preset-banner--preset' : 'preset-banner--unsaved'
    const banner = el(
      'div',
      {
        class: `preset-banner ${bannerStateClass} bg-white rounded-lg border border-slate-200 p-5`,
        role: 'region',
        'aria-label': '現在の設定状態',
      },
      el('h3', { class: 'text-base font-bold text-slate-800 mb-2' }, '現在の設定'),
      el(
        'div',
        { class: 'flex items-baseline gap-3 flex-wrap' },
        el('span', { class: 'text-sm uppercase text-slate-500 font-semibold' }, bannerLabel),
        el('span', { class: 'text-lg font-bold text-blue-800', lang: 'ja' }, bannerValue)
      )
    )
    box.appendChild(banner)

    // task-65: cp.axes を直接参照 (API が matched preset の axes を返す)。
    //   axes が object (preset 一致) → 6 軸 read-only table を表示。
    //   axes が null/undefined (unsaved) → 「カスタム設定 (プリセット外)」見出しに切替。
    const axes = cp && cp.axes && typeof cp.axes === 'object' ? cp.axes : null
    if (axes) {
      box.appendChild(renderAxesTable(axes))
    } else {
      box.appendChild(renderCustomPanel())
    }

    // CTA: 「設定を変更」ボタン
    const actions = el(
      'div',
      { class: 'flex items-center gap-3 flex-wrap' },
      el(
        'button',
        {
          type: 'button',
          class: 'px-5 py-3 text-base bg-blue-700 hover:bg-blue-800 text-white font-bold rounded shadow-sm min-h-[44px] focus:outline-none focus:ring-2 focus:ring-blue-400 focus:ring-offset-2',
          onclick: onClickGotoEdit,
          lang: 'ja',
        },
        '設定を変更'
      )
    )
    box.appendChild(actions)

    return box
  }

  // ============================================================
  // render: edit view (preset list + 適用 / キャンセル)
  // 起源: draft §3.5 / §3.9 a11y。task-65 で 6 軸 dropdown 撤去済 — preset 一括変更のみ。
  // ============================================================
  function renderEdit(currentState) {
    const box = el('section', {
      class: 'space-y-4',
      'aria-labelledby': 'edit-view-heading',
      role: 'region',
      lang: 'ja',
    })

    box.appendChild(
      el(
        'div',
        { class: 'flex items-center justify-between flex-wrap gap-2' },
        el('h2', { id: 'edit-view-heading', class: 'text-lg font-bold text-slate-800' }, '設定を編集'),
        el(
          'button',
          {
            type: 'button',
            class: 'px-3 py-2 text-sm bg-slate-100 hover:bg-slate-200 border border-slate-300 rounded text-slate-700 min-h-[44px] focus:outline-none focus:ring-2 focus:ring-blue-400',
            onclick: onClickBackToTop,
            'aria-label': 'トップ画面に戻る',
          },
          'トップに戻る'
        )
      )
    )

    // ============ preset 選択 section ============
    const presetSection = el(
      'div',
      {
        class: 'bg-white rounded-lg border border-slate-200 p-4',
        role: 'region',
        'aria-labelledby': 'edit-preset-heading',
      },
      el('h3', { id: 'edit-preset-heading', class: 'text-base font-semibold text-slate-800 mb-3' }, 'プリセットから選ぶ')
    )

    if (!currentState.presets || currentState.presets.length === 0) {
      presetSection.appendChild(
        el('p', { class: 'text-sm text-slate-500' }, 'プリセットを読み込み中...')
      )
    } else {
      const presetUl = el('ul', {
        class: 'space-y-1',
        role: 'list',
        'aria-label': 'プリセット選択リスト',
      })
      for (const p of currentState.presets) {
        const isSel = currentState.editPresetSelection === p.name
        const displayName = getDisplayName(p)
        const onSelect = () => onSelectPresetInEdit(p.name)
        const li = el(
          'li',
          {
            class: `cursor-pointer px-3 py-2 rounded border min-h-[44px] focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1 ${isSel ? 'border-blue-500 bg-blue-50 ring-1 ring-blue-200' : 'border-slate-200 hover:bg-slate-50'}`,
            role: 'listitem',
            tabindex: '0',
            'data-preset-key': p.name,
            'aria-current': isSel ? 'true' : null,
            'aria-label': `プリセット ${displayName}${isSel ? ' (選択中)' : ''}`,
            onclick: onSelect,
            onkeydown: activateOnEnterOrSpace(onSelect),
            lang: 'ja',
          },
          el(
            'div',
            { class: 'flex items-baseline justify-between gap-2 flex-wrap' },
            el('span', { class: 'text-sm font-semibold text-slate-800', lang: 'ja' }, displayName),
            el('span', { class: 'text-xs text-slate-400 font-mono' }, p.name)
          ),
          p.use_case ? el('div', { class: 'text-xs text-slate-500 mt-0.5', lang: 'ja' }, p.use_case) : null
        )
        presetUl.appendChild(li)
      }
      presetSection.appendChild(presetUl)

      // preset 選択時 diff preview
      if (currentState.editPresetDiff) {
        const diff = currentState.editPresetDiff
        const changed = (diff.changes || []).filter((c) => c.changed)
        const previewBox = el(
          'div',
          {
            class: 'mt-3 p-3 bg-blue-50 border border-blue-200 rounded text-sm',
            role: 'region',
            'aria-label': '選択プリセットの差分プレビュー',
          },
          el(
            'p',
            { class: 'font-semibold text-blue-900 mb-1' },
            `差分: ${changed.length} 件の変更`
          )
        )
        if (changed.length > 0) {
          const ul = el('ul', { class: 'space-y-0.5 text-xs', role: 'list' })
          for (const c of changed) {
            ul.appendChild(
              el(
                'li',
                { class: 'font-mono text-slate-700' },
                `${c.key}: ${c.current} → ${c.new}`
              )
            )
          }
          previewBox.appendChild(ul)
        }
        presetSection.appendChild(previewBox)
      }
    }
    box.appendChild(presetSection)

    // task-65: 個別変更 section (6 軸 drop-down) は撤去。
    //   6 軸は yml raw key でなく preset metadata のため、/api/keys からの options 取得元が無く
    //   常に 0 件 (dead UI) だった。編集経路は preset 一括変更に一本化 (6 軸は top view で read-only 表示専用)。

    // ============ アクション buttons (task-63 簡素化: 「キャンセル」「適用」のみ) ============
    const hasChange = !!currentState.editPresetSelection
    const applyDisabled = currentState.applying || !hasChange

    const actions = el(
      'div',
      { class: 'flex items-center gap-3 flex-wrap' },
      el(
        'button',
        {
          type: 'button',
          class: 'px-4 py-2 text-sm bg-slate-200 hover:bg-slate-300 text-slate-800 rounded min-h-[44px] focus:outline-none focus:ring-2 focus:ring-slate-400',
          onclick: onClickCancel,
          'aria-label': '編集を破棄してトップ画面に戻る',
        },
        'キャンセル'
      ),
      el(
        'button',
        {
          type: 'button',
          class: `px-4 py-2 text-sm font-semibold rounded shadow-sm min-h-[44px] focus:outline-none focus:ring-2 focus:ring-offset-1 ${applyDisabled ? 'bg-emerald-400 text-white opacity-60 cursor-not-allowed' : 'bg-emerald-700 hover:bg-emerald-800 text-white focus:ring-emerald-400'}`,
          onclick: onClickApply,
          disabled: applyDisabled,
          'aria-label': currentState.applying ? '適用処理中' : '編集内容を harness-config.yml に適用',
          'aria-disabled': applyDisabled ? 'true' : 'false',
        },
        currentState.applying ? '適用中...' : '適用'
      )
    )
    box.appendChild(actions)

    return box
  }

  // ============================================================
  // render: dispatcher (state → DOM)
  // ============================================================
  function render() {
    // 描画 target は index.html の <div id="view-container"> (L34、<main id="main"> 内の動的 content div)。
    // 旧 'main-panel' は index.html に実在しない id で view 全体が描画されない bug の原因だった (task-63 Step 7 修正)。
    const panel = document.getElementById('view-container')
    if (!panel) return
    clear(panel)
    if (state.view === 'top') {
      panel.appendChild(renderTop(state))
    } else if (state.view === 'edit') {
      panel.appendChild(renderEdit(state))
    } else {
      // unknown view fallback → top
      panel.appendChild(renderTop(state))
    }
    // sidebar / category list は task-63 で廃止 (DOM 非存在の場合 silent)
    // history footer は維持
    renderHistory()
  }

  // ============================================================
  // history footer (task-61 から継承、絵文字なしテキスト化)
  // ============================================================
  function formatHistoryTime(h) {
    if (h.applied_at) {
      const d = new Date(h.applied_at)
      if (!isNaN(d.getTime())) {
        return d.toLocaleString('ja-JP', { timeZone: 'Asia/Tokyo', hour12: false })
      }
    }
    return h.timestamp
  }

  function renderHistory() {
    const tbody = document.getElementById('history-tbody')
    if (!tbody) return
    clear(tbody)
    if (!state.history.length) {
      tbody.appendChild(el('tr', null, el('td', { class: 'py-2 text-slate-400', colspan: 6 }, '履歴なし')))
      return
    }
    for (const h of state.history) {
      const failedCount = Number(h.failed_count || 0)
      const failedCell = failedCount > 0
        ? el(
            'span',
            { class: 'inline-flex items-center gap-1 text-red-700 font-semibold' },
            el('span', { 'aria-hidden': 'true', class: 'font-mono text-xs' }, '[!]'),
            String(failedCount)
          )
        : el('span', { class: 'text-slate-500' }, '0')
      const rolledBackCount = Number(h.rolled_back_count || 0)
      const rolledBackCell = rolledBackCount > 0
        ? el(
            'span',
            { class: 'inline-flex items-center gap-1 text-amber-700 font-semibold' },
            el('span', { 'aria-hidden': 'true', class: 'font-mono text-xs' }, '[r]'),
            String(rolledBackCount)
          )
        : el('span', { class: 'text-slate-500' }, '0')

      const presetDisplay = h.preset_display_name_ja || h.preset || '<unknown>'
      const rollbackLabel = `${h.timestamp} (preset: ${presetDisplay}) をロールバック`
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
  // event handlers (task-63 state machine 適合)
  // ============================================================
  function onClickGotoEdit() {
    // task-65: 6 軸 dropdown 撤去により編集 baseline (currentAxes) / options fetch は不要。
    //   edit view は preset list (preset 一括変更経路) のみ。
    dispatch({ type: 'edit:enter' })
    setStatus('編集画面')
  }

  function onClickBackToTop() {
    dispatch({ type: 'top:enter' })
    setStatus('トップ画面')
  }

  async function onSelectPresetInEdit(presetName) {
    setStatus(`プリセット ${presetName} の差分を計算中...`)
    try {
      const diff = await loadPresetDiff(presetName)
      dispatch({ type: 'edit:select_preset', payload: { presetName, diff } })
      setStatus(`プリセット ${presetName} を選択中`)
    } catch (e) {
      toast(`差分取得失敗: ${e.message}`, 'error')
      setStatus('エラー')
    }
  }

  async function onClickApply() {
    if (state.applying) return
    if (state.editPresetSelection) {
      await applyPresetMode()
    } else {
      toast('適用対象の変更がありません', 'info')
    }
  }

  async function applyPresetMode() {
    const presetName = state.editPresetSelection
    const selected = (state.presets || []).find((p) => p.name === presetName)
    const displayName = getDisplayName(selected) || presetName
    const diff = state.editPresetDiff
    const changedCount = diff ? (diff.changes || []).filter((c) => c.changed).length : '?'

    const confirmed = await showConfirmDialog({
      title: 'プリセット適用の確認',
      bodyLines: [
        `『${displayName}』を適用しますか?`,
        `変更対象: ${changedCount} 軸`,
        '実行すると harness-config.yml が atomic backup 付きで更新されます。',
      ],
      okLabel: '適用する',
      cancelLabel: 'キャンセル',
      danger: false,
    })
    if (!confirmed) return

    dispatch({ type: 'ui:set_flag', payload: { flag: 'applying', value: true } })
    setStatus('適用中...')
    try {
      const r = await applyPresetApi(presetName, [])
      if (r.ok) {
        toast(`適用成功: ${r.applied} 件適用 (『${displayName}』)`, 'success')
      } else if (r.partial) {
        toast(`部分失敗: ${r.applied || 0} 成功 / ${r.failed || 1} 失敗`, 'warning')
      } else {
        toast(`適用失敗: ${r.error || 'unknown'}`, 'error')
      }
      // top 復帰 + currentPreset 再取得
      await _finalizeApply('適用完了')
    } catch (e) {
      toast(`適用失敗: ${e.message}`, 'error')
      setStatus('エラー')
      dispatch({ type: 'ui:set_flag', payload: { flag: 'applying', value: false } })
    }
  }

  // 適用成功後の共通後処理:
  //   currentPreset / history を再取得し、state を top 復帰させ render する。
  //   (task-65: 個別変更経路撤去により呼出元は applyPresetMode のみ)
  async function _finalizeApply(statusText) {
    const newCurrent = await loadCurrentPreset()
    const newHistory = await loadHistory()
    state = reducer(state, { type: 'edit:apply', payload: { currentPreset: newCurrent } })
    state = reducer(state, { type: 'history:update', payload: { history: newHistory } })
    setStatus(statusText)
    render()
  }

  // task-65: applyIndividualMode (6 軸 dropdown 個別変更) は撤去。編集経路は preset 一括変更のみ。

  function onClickCancel() {
    dispatch({ type: 'edit:cancel' })
    setStatus('編集を破棄、トップ画面')
  }

  // ============================================================
  // rollback (history footer 経由)
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

    dispatch({ type: 'ui:set_flag', payload: { flag: 'rollbackInProgress', value: true } })
    setStatus('ロールバック中...')
    try {
      const r = await rollbackApi(timestamp)
      if (r.ok) {
        toast(`ロールバック成功: ${r.restored} 件復元`, 'success')
      } else {
        toast(`部分失敗: ${r.restored} 成功 / ${r.failed} 失敗`, 'warning')
      }
      const newCurrent = await loadCurrentPreset()
      const newHistory = await loadHistory()
      state = reducer(state, { type: 'load:current', payload: { currentPreset: newCurrent, history: newHistory } })
      state = reducer(state, { type: 'ui:set_flag', payload: { flag: 'rollbackInProgress', value: false } })
      setStatus('ロールバック完了')
      render()
    } catch (e) {
      toast(`ロールバック失敗: ${e.message}`, 'error')
      setStatus('エラー')
      dispatch({ type: 'ui:set_flag', payload: { flag: 'rollbackInProgress', value: false } })
    }
  }

  // ============================================================
  // Tailwind CDN detection (task-61 から継承、M-U1)
  // ============================================================
  function detectTailwind() {
    const warningEl = document.getElementById('cdn-warning')
    if (!warningEl) return
    const cdnLoaded = () => typeof window.tailwind !== 'undefined'
    const hideWarning = () => warningEl.classList.add('hidden')
    const showWarning = () => warningEl.classList.remove('hidden')
    const scripts = document.querySelectorAll('script[src*="tailwindcss.com"]')
    let scriptErrored = false
    for (const s of scripts) {
      s.addEventListener('error', () => {
        scriptErrored = true
        showWarning()
      })
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
  // init
  // ============================================================
  async function init() {
    setStatus('読み込み中...')
    detectTailwind()
    try {
      const [currentPreset, presets, history] = await Promise.all([
        loadCurrentPreset(),
        loadPresets(),
        loadHistory(),
      ])
      state = reducer(state, { type: 'load:current', payload: { currentPreset, presets, history } })
      render()
      // task-65 iter2 (ui H-1 / code-rev M2): 'custom' dead branch 撤去 (server は 'preset'/'unsaved' のみ)。
      const cpName = currentPreset && currentPreset.match_type === 'preset'
        ? getDisplayName(currentPreset)
        : '未保存変更'
      setStatus(`Ready (${cpName} / ${presets.length} presets)`)
    } catch (e) {
      toast(`初期化失敗: ${e.message}`, 'error')
      setStatus('エラー (server 起動を確認してください)')
    }
  }

  // expose for smoke / debugging (task-63 grep verify 用)
  window.__hcConfigUi = {
    reducer,
    getDisplayName,
    initialState,
    AXIS_KEYS,
    AXIS_LABELS_JA,
    getState: () => state,
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init)
  } else {
    init()
  }
})()
