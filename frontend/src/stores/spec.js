// Glyph - 绘图规格 store：spec 是唯一的绘图事实来源
import { defineStore } from 'pinia'
import { renderPlot, rawRender } from '../api'
import { useDataStore } from './data'

// 用户自定义默认风格：主题面板「存为我的默认」写入，新建/清空画布时自动套用。
// 只存本机（localStorage），不随项目文件走——项目文件自带完整 spec。
const USER_DEFAULT_KEY = 'Glyph-user-default-v1'
export function loadUserDefault() {
  try {
    const o = JSON.parse(localStorage.getItem(USER_DEFAULT_KEY) || 'null')
    return (o && typeof o === 'object') ? o : null
  } catch { return null }
}
export function saveUserDefault(o) {
  try { localStorage.setItem(USER_DEFAULT_KEY, JSON.stringify(o || {})) } catch { /* 忽略 */ }
}
export function clearUserDefault() {
  try { localStorage.removeItem(USER_DEFAULT_KEY) } catch { /* 忽略 */ }
}

export function defaultSpec() {
  // 默认出图风格：Prism 期刊风（未装 ggprism 时启动后会回退到 minimal）；
  // 用户存过「我的默认」则覆盖主题（base/args/elements 逐层合并，缺字段回退内置值）
  const ud = loadUserDefault()
  const udTheme = (ud && ud.theme && ud.theme.base) ? ud.theme : null
  return {
    data: { source: { type: 'none' }, filter: '', mutate: [], sample: null, seed: null, filterDisabled: false, sampleDisabled: false, types: [], text: [], outliers: [], fillna: [], dropnaCols: [], dropnaHow: 'any', dropnaDisabled: false, dedupCols: [], dedupEnabled: false },
    layers: [],
    scales: [],
    coord: { type: '', params: {}, flip: false },
    facet: null,
    labs: {},
    guides: {},
    annotations: [],
    // 图上显著性标注（L3）：[{kind:'bracket'|'text', group1, group2, label, yPos?}]
    sigMarks: [],
    theme: {
      base: udTheme ? udTheme.base : 'prism',
      args: { palette: 'black_and_white', base_size: 12, ...(udTheme ? (udTheme.args || {}) : {}) },
      elements: { ...(udTheme ? (udTheme.elements || {}) : {}) }
    },
    combine: { active: false, slots: [], layout: {}, annotation: {} }
  }
}

const clamp = (v, lo, hi) => Math.min(hi, Math.max(lo, v))

// 项目标识：图库按项目隔离；持久化到 localStorage，刷新后仍是同一个项目
const PROJECT_ID_KEY = 'Glyph-project-id'
function newProjectId() {
  try {
    if (typeof crypto !== 'undefined' && crypto.randomUUID) return crypto.randomUUID()
  } catch { /* 忽略 */ }
  return 'p-' + Date.now().toString(36) + '-' + Math.random().toString(36).slice(2, 8)
}
function currentProjectId() {
  try {
    const saved = localStorage.getItem(PROJECT_ID_KEY)
    if (saved && saved.trim()) return saved.trim()
  } catch { /* 忽略 */ }
  const id = newProjectId()
  try { localStorage.setItem(PROJECT_ID_KEY, id) } catch { /* 忽略 */ }
  return id
}
// 工作区存在时，projectId 由目录派生（见 R/workspace.R 的 id_of），
// 这样「一个目录 = 一个项目」，换浏览器或换机器打开同一目录看到的是同一份图库。
// 没有工作区时退回 localStorage 里的随机 UUID（与旧版行为一致）。

// 未保存草稿（崩溃/误关恢复）：只存 spec，数据本身由服务端 userdata/ 持久化
const DRAFT_KEY = 'Glyph-draft-v1'

export const useSpecStore = defineStore('spec', {
  state: () => ({
    spec: defaultSpec(),
    selectedLayer: 0,
    projectId: currentProjectId(),
    autoRender: true,
    rendering: false,
    renderQueued: false,
    // pngUrl: /api/plot/xxx.png（后端落盘）；png: base64 备用
    last: { pngUrl: null, png: null, code: '', warnings: [], messages: [], error: null, elapsed: 0, ok: false },
    pendingCode: '',
    // 外部推送的代码是否要在填入编辑器后立即运行（/api/code/push 的 run 标记）
    pendingCodeRun: false,
    // 画布内容来自哪个图库条目（打开 spec 图后记下）。
    // 用于「存入图库」时决定是覆盖更新那条、还是另存为新条目。
    sourcePinId: '',
    sourcePinLabel: '',
    renderOpts: (() => {
      const ud = loadUserDefault()
      return { width: 900, height: 560, dpi: 150, ...((ud && ud.renderOpts) || {}) }
    })(),
    dark: false,
    history: [],
    future: [],
    renderToken: 0,
    savedHash: '',      // 最近一次「保存项目 / 载入项目」时的 spec 指纹
    draftAt: 0          // 草稿最近写入时间
  }),
  getters: {
    curLayer(state) {
      return state.spec.layers[state.selectedLayer] || null
    },
    canUndo(state) {
      return state.history.length > 0
    },
    canRedo(state) {
      return state.future.length > 0
    },
    hasPlot(state) {
      return !!state.last.pngUrl || !!state.last.png
    },
    // 「画布上有没有东西可画」= 有图层或有拼图槽位。
    // 注意：不要在这里判断 last.pngUrl/png —— 原始代码模式渲染出的图也会写进 last，
    // 若把它算作「有内容」，空画布就会显示一张空白图、并吞掉首屏引导。
    // 需要「有没有渲染结果」时用 hasPlot。
    hasContent(state) {
      const cb = state.spec.combine
      return state.spec.layers.length > 0 ||
        !!(cb && cb.active && cb.slots && cb.slots.length)
    },
    composeActive(state) {
      const cb = state.spec.combine
      return !!(cb && cb.active && cb.slots && cb.slots.length)
    },
    imgSrc(state) {
      return state.last.pngUrl || (state.last.png ? `data:image/png;base64,${state.last.png}` : null)
    },
    // 有内容且与「已保存」指纹不同 → 未保存
    dirty(state) {
      if (!state.spec.layers.length) return false
      return state.savedHash !== JSON.stringify(state.spec)
    }
  },
  actions: {
    // setProjectId 只在下方「项目」区定义（对象字面量重复键会被后者静默覆盖，勿在此重复）
    reset() {
      this.spec = defaultSpec()
      this.ensureDefaultTheme()
      this.selectedLayer = 0
      this.history = []
      this.future = []
      this.savedHash = ''
    },

    // ---- 草稿：自动保存 / 崩溃恢复 -------------------------------------
    markSaved() {
      this.savedHash = JSON.stringify(this.spec)
      this.clearDraft()
    },
    saveDraft() {
      if (!this.spec.layers.length || !this.dirty) { this.clearDraft(); return false }
      try {
        localStorage.setItem(DRAFT_KEY, JSON.stringify({
          at: Date.now(), spec: this.spec, renderOpts: this.renderOpts
        }))
        this.draftAt = Date.now()
        return true
      } catch {
        return false
      }
    },
    readDraft() {
      try {
        const d = JSON.parse(localStorage.getItem(DRAFT_KEY) || 'null')
        return d && d.spec && Array.isArray(d.spec.layers) && d.spec.layers.length ? d : null
      } catch {
        return null
      }
    },
    clearDraft() {
      try { localStorage.removeItem(DRAFT_KEY) } catch { /* 忽略 */ }
      this.draftAt = 0
    },
    restoreDraft(draft) {
      if (!draft || !draft.spec) return
      this.loadProject(draft.spec)
      if (draft.renderOpts) this.renderOpts = { ...this.renderOpts, ...draft.renderOpts }
      this.savedHash = ''   // 恢复出来的内容仍算「未保存」，提醒用户另存
    },
    // ---- 历史 ----
    pushHistory() {
      this.history.push(JSON.stringify(this.spec))
      if (this.history.length > 60) this.history.shift()
      this.future = []
    },
    undo() {
      if (!this.history.length) return
      this.future.push(JSON.stringify(this.spec))
      this.spec = JSON.parse(this.history.pop())
      this.selectedLayer = clamp(this.selectedLayer, 0, Math.max(0, this.spec.layers.length - 1))
    },
    redo() {
      if (!this.future.length) return
      this.history.push(JSON.stringify(this.spec))
      this.spec = JSON.parse(this.future.pop())
    },

    // ---- 数据 ----
    setSource(source) {
      this.pushHistory()
      this.spec.data.source = source
      // 给空图层猜 aes
      const ds = useDataStore()
      if (ds.colNames.length) {
        for (const l of this.spec.layers) {
          if (!Object.keys(l.aes).length) this.guessAes(l)
        }
        this.syncDefaultPalette('fill')
        this.syncDefaultPalette('colour')
      }
    },
    guessAes(layer) {
      const ds = useDataStore()
      const meta = useMetaStoreSafe()
      const g = meta.geomByName[layer.geom]
      const req = (g && g.aes.required) || ['x', 'y']
      const nums = ds.columns.filter(c => c.type === 'numeric').map(c => c.name)
      const others = ds.columns.filter(c => c.type !== 'numeric').map(c => c.name)
      const ordered = [...nums, ...others]
      if (!ordered.length) return
      let ci = 0
      for (const a of req) {
        if (a === 'group') continue
        if (ci < ordered.length && !layer.aes[a]) layer.aes[a] = { map: ordered[ci++] }
      }
    },

    // ---- 图层 ----
    addLayer(geomName) {
      this.pushHistory()
      const layer = { geom: geomName, stat: '', position: { type: '', params: {} }, aes: {}, params: {}, aesParams: {}, visible: true }
      this.guessAes(layer)
      this.spec.layers.push(layer)
      this.selectedLayer = this.spec.layers.length - 1
      this.syncDefaultPalette('fill')
      this.syncDefaultPalette('colour')
    },
    // 图层显隐：隐藏的层不参与出图，但仍保留在列表里（可随时恢复）
    toggleLayerVisible(i) {
      const layer = this.spec.layers[i]
      if (!layer) return
      this.pushHistory()
      layer.visible = layer.visible === false
      this.renderNow()
    },
    // 多重标度（ggnewscale）：在该层之前插入 new_scale_*()，
    // 让这一层及其后重新开始一套 fill/colour 标度
    toggleLayerResetScale(i, kind = 'fill') {
      const layer = this.spec.layers[i]
      if (!layer) return
      if (i === 0) return   // 第一层前面没有标度可重置
      this.pushHistory()
      const cur = Array.isArray(layer.resetScale)
        ? layer.resetScale.slice()
        : (layer.resetScale ? [layer.resetScale] : [])
      const idx = cur.indexOf(kind)
      if (idx >= 0) cur.splice(idx, 1)
      else cur.push(kind)
      if (cur.length) layer.resetScale = cur
      else delete layer.resetScale
      this.renderNow()
    },
    removeLayer(i) {
      this.pushHistory()
      this.spec.layers.splice(i, 1)
      this.selectedLayer = clamp(this.selectedLayer, 0, Math.max(0, this.spec.layers.length - 1))
    },
    dupLayer(i) {
      this.pushHistory()
      const copy = JSON.parse(JSON.stringify(this.spec.layers[i]))
      this.spec.layers.splice(i + 1, 0, copy)
      this.selectedLayer = i + 1
    },
    moveLayer(i, dir) {
      const j = i + dir
      if (j < 0 || j >= this.spec.layers.length) return
      this.pushHistory()
      const arr = this.spec.layers
      ;[arr[i], arr[j]] = [arr[j], arr[i]]
      this.selectedLayer = j
    },
    selectLayer(i) { this.selectedLayer = i },

    // ---- 图层细节 ----
    setLayerAes(i, aesName, value) {
      const layer = this.spec.layers[i]
      if (!layer) return
      if (value === null || value === undefined || value === '') delete layer.aes[aesName]
      else layer.aes[aesName] = value
      if (aesName === 'fill' || aesName === 'colour') this.syncDefaultPalette(aesName)
    },
    // 默认配色：离散 fill/colour 映射且用户没设过标度时，自动挂一个 Prism 配色
    // （标度面板可见、可改；取消映射会移除，改过类型则保留用户选择）
    syncDefaultPalette(aesName) {
      const meta = useMetaStoreSafe()
      if (!meta.ext || !meta.ext.ggprism) return
      const ds = useDataStore()
      const cols = new Set()
      for (const l of this.spec.layers) {
        const v = l.aes && l.aes[aesName]
        if (v && typeof v === 'object' && v.map) cols.add(String(v.map))
      }
      let want = cols.size > 0
      if (want) {
        want = [...cols].every((name) => {
          const c = (ds.columns || []).find(x => x.name === name)
          return c && ['factor', 'character', 'logical'].includes(c.type)
        })
      }
      const idx = this.spec.scales.findIndex(s => s.aes === aesName)
      const existing = idx >= 0 ? this.spec.scales[idx] : null
      if (want && (!existing || existing.auto)) {
        const next = {
          aes: aesName, type: 'prism', params: { palette: 'floral' },
          position: '', secAxis: null, auto: true
        }
        if (existing) this.spec.scales[idx] = next
        else this.spec.scales.push(next)
      } else if (!want && existing && existing.auto) {
        this.spec.scales.splice(idx, 1)
      }
    },
    // 启动后兜底：没装 ggprism 时把默认 Prism 主题换成 minimal
    ensureDefaultTheme() {
      if (this.spec.theme.base !== 'prism') return
      const meta = useMetaStoreSafe()
      // meta 尚未加载完成时不要下结论，否则会把 prism 误判成不可用而永久降级
      if (!meta.loaded || !meta.themeByName) return
      if (!meta.themeByName['prism']) {
        this.spec.theme.base = 'minimal'
        this.spec.theme.args = { base_size: 12 }
      }
    },
    setLayerAesParam(i, name, value) {
      const layer = this.spec.layers[i]
      if (!layer) return
      if (value === null || value === undefined || value === '') delete layer.aesParams[name]
      else layer.aesParams[name] = value
    },
    // 更换图层类型：保留新 geom 接受的 aes 映射/常量与参数，其余清理
    // （ggplot2 的 layer() 遇到无法识别的参数会直接报错，故按 registry 交集过滤）
    changeGeom(i, newGeom) {
      const layer = this.spec.layers[i]
      if (!layer || layer.geom === newGeom) return
      this.pushHistory()
      const meta = useMetaStoreSafe()
      const allowedAes = new Set(meta.layerAes(newGeom))
      // 兼容三种形态：裸原始值（ParamPanel 直接写入）、{value}/{map}/{expr} 包装
      const okVal = (v) => v !== null && v !== undefined && v !== '' && (
        typeof v !== 'object' ||
        ('map' in v && String(v.map ?? '') !== '') ||
        ('expr' in v && String(v.expr || '').trim() !== '') ||
        'value' in v
      )
      const aes = {}
      for (const k of Object.keys(layer.aes || {})) {
        if (allowedAes.has(k) && okVal(layer.aes[k])) aes[k] = layer.aes[k]
      }
      layer.aes = aes
      const allowParams = new Set([
        ...meta.layerParams(newGeom).map(p => p.name),
        ...meta.layerStatParams(newGeom).map(p => p.name)
      ])
      const params = {}
      for (const k of Object.keys(layer.params || {})) if (allowParams.has(k)) params[k] = layer.params[k]
      layer.params = params
      const aesParams = {}
      for (const k of Object.keys(layer.aesParams || {})) {
        if (allowedAes.has(k) && okVal(layer.aesParams[k])) aesParams[k] = layer.aesParams[k]
      }
      layer.aesParams = aesParams
      layer.geom = newGeom
      this.syncDefaultPalette('fill')
      this.syncDefaultPalette('colour')
    },
    setLayerParam(i, name, value) {
      const layer = this.spec.layers[i]
      if (!layer) return
      if (value === null || value === undefined || value === '') delete layer.params[name]
      else layer.params[name] = value
    },

    // ---- 标度 ----
    addScale(aes) {
      this.pushHistory()
      const exists = this.spec.scales.find(s => s.aes === aes)
      if (!exists) this.spec.scales.push({ aes, type: '', params: {}, position: '', secAxis: null })
    },
    removeScale(i) {
      this.pushHistory()
      this.spec.scales.splice(i, 1)
    },

    // ---- 其他组件 ----
    setCoord(patch) {
      this.pushHistory()
      Object.assign(this.spec.coord, patch)
      if (patch.type === '') this.spec.coord.params = {}
    },
    setFacet(f) {
      this.pushHistory()
      this.spec.facet = f
    },
    setTheme(patch) {
      this.pushHistory()
      Object.assign(this.spec.theme, patch)
    },

    // ---- 显著性标注（L3）----
    ensureSigMarks() {
      if (!Array.isArray(this.spec.sigMarks)) this.spec.sigMarks = []
      return this.spec.sigMarks
    },
    addSigMark(mark) {
      this.pushHistory()
      const arr = this.ensureSigMarks()
      arr.push({
        kind: mark.kind || 'bracket',
        group1: mark.group1 || '',
        group2: mark.group2 || '',
        label: mark.label || '*',
        yPos: mark.yPos ?? null
      })
      return arr.length - 1
    },
    setSigMark(i, patch) {
      const arr = this.ensureSigMarks()
      if (!arr[i]) return
      Object.assign(arr[i], patch)
    },
    removeSigMark(i) {
      this.pushHistory()
      const arr = this.ensureSigMarks()
      if (i >= 0 && i < arr.length) arr.splice(i, 1)
    },
    clearSigMarks() {
      this.pushHistory()
      this.spec.sigMarks = []
    },

    // ---- 项目 ----
    // 设置项目标识（工作区建立/切换时调用）。持久化到 localStorage，
    // 这样同一浏览器下次打开仍是同一个项目；换机器则由图库条目的 project 字段决定可见性。
    setProjectId(id) {
      const v = String(id || '').trim()
      if (!v || v === this.projectId) return
      this.projectId = v
      try { localStorage.setItem(PROJECT_ID_KEY, v) } catch { /* 忽略 */ }
    },
    loadProject(obj) {
      this.pushHistory()
      const base = defaultSpec()
      const merged = { ...base, ...(obj || {}) }
      // 逐层补齐默认值，避免旧版/手改的 JSON 缺字段后在组件里 undefined.push
      merged.data = { ...base.data, ...((obj && obj.data) || {}) }
      merged.coord = { ...base.coord, ...((obj && obj.coord) || {}) }
      merged.theme = { ...base.theme, ...((obj && obj.theme) || {}) }
      // 旧草稿/旧项目可能带着 theme: { base: '', args: {}, elements: {} }，
      // 直接浅合并会把默认的 Prism 主题覆盖成空 → 恢复后图变成 ggplot 原始样式。
      // 只有「用户确实表达过主题意图」（选了基础主题或改过元素）才保留，否则回落默认。
      const otheme = (obj && obj.theme) || {}
      const noBase = !otheme.base
      const noArgs = !otheme.args || !Object.keys(otheme.args).length
      const noEls = !otheme.elements || !Object.keys(otheme.elements).length
      if (noBase && noArgs && noEls) {
        merged.theme = JSON.parse(JSON.stringify(base.theme))
      }
      merged.combine = { ...base.combine, ...((obj && obj.combine) || {}) }
      merged.layers = Array.isArray(obj && obj.layers) ? obj.layers : []
      merged.scales = Array.isArray(obj && obj.scales) ? obj.scales : []
      merged.annotations = Array.isArray(obj && obj.annotations) ? obj.annotations : []
      merged.labs = (obj && obj.labs) || {}
      merged.guides = (obj && obj.guides) || {}
      this.spec = merged
      this.ensureDefaultTheme()
      this.selectedLayer = 0
      // 通用载入入口（项目文件 / 草稿恢复 / 空项目）：不再对应任何图库条目。
      // 从图库打开 spec 图时，调用方会在这之后重新设上来源。
      this.sourcePinId = ''
      this.sourcePinLabel = ''
    },
    // 数据源切换后，丢弃指向不存在列的映射（否则渲染报「找不到对象 'xxx'」）
    // 换数据源时按列名继承映射（同构数据批量出图）：
    // 旧映射列在新数据里找不到时，尝试大小写不敏感的唯一匹配改绑；仍无匹配留给 pruneMappings 清除
    remapMappings(oldNames, newNames) {
      const old = oldNames || []
      if (!old.length || !(newNames || []).length) return
      const lower = new Map()
      for (const n of newNames) {
        const k = n.toLowerCase()
        if (!lower.has(k)) lower.set(k, n)  // 重名歧义时取第一个，避免误绑
      }
      const remap = (v) => {
        if (!(v && typeof v === 'object' && 'map' in v && v.map)) return
        const name = String(v.map)
        if (newNames.includes(name)) return
        const hit = lower.get(name.toLowerCase())
        if (hit) v.map = hit
      }
      for (const l of this.spec.layers) {
        for (const k of Object.keys(l.aes || {})) remap(l.aes[k])
      }
    },
    pruneMappings(colNames) {
      const colSet = new Set(colNames || [])
      if (!colSet.size) return false
      let changed = false
      const stale = (v) => v && typeof v === 'object' && 'map' in v && !colSet.has(String(v.map))
      for (const l of this.spec.layers) {
        for (const k of Object.keys(l.aes || {})) {
          if (stale(l.aes[k])) { delete l.aes[k]; changed = true }
        }
        for (const k of Object.keys(l.aesParams || {})) {
          if (stale(l.aesParams[k])) { delete l.aesParams[k]; changed = true }
        }
      }
      const f = this.spec.facet
      if (f) {
        const keep = (arr) => (arr || []).filter(x => colSet.has(String(x)))
        const vars = keep(f.vars), rows = keep(f.rows), fcols = keep(f.cols)
        if (vars.length !== (f.vars || []).length || rows.length !== (f.rows || []).length ||
            fcols.length !== (f.cols || []).length) {
          f.vars = vars; f.rows = rows; f.cols = fcols; changed = true
        }
      }
      return changed
    },
    exportProject() {
      return JSON.stringify(this.spec, null, 2)
    },

    // 从「代码图」回到按当前 spec 渲染的图。
    // 代码图状态下 spec 改动不会自动重渲染（见 App.vue 的守卫），
    // 因此需要一个显式出口；画布顶栏与各设置面板都调这里。
    // 返回 true 表示已切换，false 表示画布上没有可渲染的内容。
    backToSpec() {
      if (!this.hasContent) return false
      if (this.last) this.last = { ...this.last, renderedFromCode: false }
      this.renderNow()
      return true
    },

    // ---- 渲染 ----
    // 串行化：同一时刻只发一个渲染请求（后端 httpuv 单线程，排队只会让所有请求一起变慢）；
    // 渲染期间的新请求合并成「结束后再来一次」。
    //
    // 关键：当前画面可能来自「原始代码模式」（last.renderedFromCode）。
    // 此时不能按 spec 渲染 —— spec 是空的（或停在用户旧的图层配置），
    // 渲染出来会顶掉代码图。正确做法是用同一段代码按新尺寸重渲染。
    // 这同时解决两个问题：
    //   1) 自适应/改画幅时，代码图能跟着重渲染，而不是被 spec 覆盖
    //   2) 项目里有自己图层映射时，拖窗口不会把代码图顶掉
    async renderNow() {
      if (this.rendering) { this.renderQueued = true; return }
      const token = ++this.renderToken
      this.rendering = true
      this.renderQueued = false
      try {
        const asCode = !!(this.last && this.last.renderedFromCode && this.last.code)
        const res = asCode
          ? await rawRender(this.last.code, this.spec, this.renderOpts)
          : await renderPlot(this.spec, this.renderOpts)
        if (token !== this.renderToken) return
        if (res.ok) {
          this.last = {
            ok: true, pngUrl: res.pngUrl || null, png: res.png || null,
            // 代码模式：沿用当前编辑器里的代码；spec 模式：用后端回传的生成代码
            code: asCode ? this.last.code : res.code,
            warnings: res.warnings || [], messages: res.messages || [],
            error: null, elapsed: res.elapsedMs || 0,
            // 保持来源标记，否则下一次 resize 又会走 spec 分支
            ...(asCode ? { renderedFromCode: true } : {})
          }
        } else {
          this.last = { ...this.last, ok: false, error: res.error, warnings: res.warnings || [] }
          if (res.code) this.last.code = res.code
        }
      } catch (e) {
        if (token !== this.renderToken) return
        this.last = { ...this.last, ok: false, error: e.message }
      } finally {
        this.rendering = false
        if (this.renderQueued) {
          this.renderQueued = false
          this.renderNow()
        }
      }
    }
  }
})

// 惰性获取（避免循环依赖顶层引用）
import { useMetaStore } from './meta'
function useMetaStoreSafe() { return useMetaStore() }
