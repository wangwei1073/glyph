// Glyph - 后端 API 封装
// 超时按路由区分：普通请求 20s；渲染/导出/plotly 这类重活给 300s（后端单线程，
// 一次重图可能跑几十秒）；上传不设上限（由用户自己等）。
export const T_NORMAL = 20000
export const T_HEAVY = 300000
export const T_UPLOAD = 0

async function api(path, opts = {}, timeoutMs = T_NORMAL) {
  const ac = new AbortController()
  const timer = timeoutMs > 0 ? setTimeout(() => ac.abort(), timeoutMs) : null
  let r
  try {
    r = await fetch(path, { ...opts, signal: ac.signal })
  } catch (e) {
    if (e && e.name === 'AbortError') {
      throw new Error(`请求超时（${Math.round(timeoutMs / 1000)}s）：${path} 仍在渲染，可稍后重试或减小数据量`)
    }
    throw e
  } finally {
    if (timer) clearTimeout(timer)
  }
  let data = null
  let parseErr = null
  try { data = await r.json() } catch (e) { parseErr = e }
  if (!r.ok) {
    throw new Error((data && data.error) || `HTTP ${r.status}`)
  }
  if (!data) throw new Error('响应解析失败' + (parseErr ? `: ${parseErr.message}` : ''))
  return data
}

function post(path, body, timeoutMs = T_NORMAL) {
  return api(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body)
  }, timeoutMs)
}

export const getMeta = () => api('/api/meta')
// 工作区（项目目录）：读取 / 切换
export const getWorkspace = () => api('/api/workspace')
export const setWorkspace = (dir) => post('/api/workspace', { dir })
// 扩展管理
export const getExtensions = () => api('/api/extensions')
export const toggleExtension = (id, enabled) =>
  post('/api/extensions/toggle', { id, enabled }, T_HEAVY)
// 一键安装扩展 / 运行期依赖（后台任务，轮询状态）
export const installExtension = (pkg) => post('/api/extensions/install', { pkg })
export const getInstallStatus = () => api('/api/extensions/install/status')
export const getSources = () => api('/api/sources')

// ---- 导入向导（P0）----
export const getImportDrivers = () => api('/api/import/drivers')
export const importUpload = (name, ext, dataBase64) =>
  post('/api/import/upload', { name, ext, dataBase64 }, T_HEAVY)
export const importPreview = (token, opts = {}, limit = 50) =>
  post('/api/import/preview', { token, opts, limit }, T_HEAVY)
export const importCommit = (token, opts = {}, label = '') =>
  post('/api/import/commit', { token, opts, label }, T_HEAVY)
export const sqliteTables = (token) =>
  api(`/api/import/sqlite/tables?token=${encodeURIComponent(token)}`)
export const sqlitePreview = (token, table, limit = 100) =>
  post('/api/import/sqlite/preview', { token, table, limit }, T_HEAVY)
export const sqliteCommit = (token, table, label = '') =>
  post('/api/import/sqlite/commit', { token, table, label }, T_HEAVY)

// ---- 远程数据库（P1）----
export const getDbDrivers = () => api('/api/db/drivers')
export const dbTest = (opts) => post('/api/db/test', opts, T_HEAVY)
export const dbConnect = (opts) => post('/api/db/connect', opts, T_HEAVY)
export const dbTables = (conn) => api(`/api/db/tables?conn=${encodeURIComponent(conn)}`)
export const dbPreview = (opts) => post('/api/db/preview', opts, T_HEAVY)
export const dbImport = (opts) => post('/api/db/import', opts, T_HEAVY)
export const dbDisconnect = (conn) => post('/api/db/disconnect', { conn })
export const getColumns = (source, prep = null) => {
  if (prep) return post('/api/columns', { source, prep })
  const key = typeof source === 'string' ? source : `${source.type}:${source.name || source.id}`
  return api(`/api/columns?src=${encodeURIComponent(key)}`)
}
export const getPrepSummary = (source, prep) => post('/api/prep/summary', { source, prep })
export const deleteData = (id) => post('/api/data/delete', { id })
export const previewData = (source, prep, opts = {}) => {
  const body = { source, prep }
  if (opts.start) body.start = opts.start
  if (opts.length) body.length = opts.length
  if (opts.sortCol) { body.sortCol = opts.sortCol; body.asc = !!opts.asc }
  if (opts.n) body.n = opts.n
  return post('/api/data/preview', body)
}

// 导出"加工后"的数据为 CSV（走文件下载）
export const exportPreparedCSV = async (source, prep) => {
  const res = await post('/api/data/export-csv', { source, prep })
  if (!res.ok || !res.url) throw new Error(res.error || '导出失败')
  const r = await fetch(res.url)
  if (!r.ok) throw new Error(`下载失败: HTTP ${r.status}`)
  const blob = await r.blob()
  return { blob, filename: res.filename }
}

// 后端请求体上限 50MB（base64 膨胀 4/3），因此文件本身限制在 35MB
export const MAX_UPLOAD_BYTES = 35 * 1024 * 1024

export const uploadData = async (file) => {
  if (file.size > MAX_UPLOAD_BYTES) {
    throw new Error(`文件过大：${(file.size / 1048576).toFixed(1)}MB，上限 ${MAX_UPLOAD_BYTES / 1048576}MB`)
  }
  const b64 = await new Promise((resolve, reject) => {
    const fr = new FileReader()
    fr.onload = () => resolve(String(fr.result).split(',')[1] || '')
    fr.onerror = reject
    fr.readAsDataURL(file)
  })
  return post('/api/data/upload', { name: file.name, ext: file.name.split('.').pop(), dataBase64: b64 }, T_UPLOAD)
}

export const pasteData = (text, label = null) => post('/api/data/paste', label ? { text, label } : { text })

// 项目文件内嵌数据：拿上传数据的 CSV 快照（内置数据集不需要）
export const snapshotData = (source) => post('/api/data/snapshot', { source })
export const getEdits = (key) => api(`/api/edits?key=${encodeURIComponent(key)}`)
export const importEdits = (source, ops) => post('/api/edits/import', { source, ops })

export const renderPlot = (spec, { width = 800, height = 500, dpi = 150 } = {}) =>
  post('/api/render', { spec, width, height, dpi }, T_HEAVY)

export const genCode = (spec) => post('/api/code', { spec })

export const checkPackages = (packages) => post('/api/packages/check', { packages })
export const formatCode = (code) => post('/api/code/format', { code })
export const rawRender = (code, spec, { width = 800, height = 500, dpi = 150 } = {}) =>
  post('/api/rawrender', { code, spec, width, height, dpi }, T_HEAVY)

// code 非空时按代码导出（代码图）；否则按 spec 导出
export const exportPlot = async (spec, { width = 1600, height = 1000, dpi = 300, format = 'png', code = '' } = {}) => {
  const res = await post('/api/export', { spec, width, height, dpi, format, code }, T_HEAVY)
  if (!res.ok || !res.url) throw new Error(res.error || '导出失败')
  const r = await fetch(res.url)
  if (!r.ok) throw new Error(`下载导出文件失败: HTTP ${r.status}`)
  const blob = await r.blob()
  return { blob, filename: res.filename || `Glyph.${format}` }
}

// 导出前检查（白底 / 尺寸 / dpi / 矢量 / 字体 / 字号；可选期刊模板）
export const checkExport = (spec, { width = 1600, height = 1000, dpi = 300, format = 'png', journal = '', code = '' } = {}) =>
  post('/api/export/check', { spec, width, height, dpi, format, journal, code }, T_HEAVY)

export const getJournalTemplates = () => api('/api/journal/templates')

// 可复现包：图 + 数据 + 代码 + sessionInfo + 图注 + 项目文件（zip）
export const bundlePlot = (spec, { width = 1600, height = 1000, dpi = 300, journal = '', projectId = '', code = '' } = {}) =>
  post('/api/bundle', { spec, width, height, dpi, journal, projectId, code }, T_HEAVY)

export const getPlotly = (spec, { width = 800, height = 500 } = {}) =>
  post('/api/plotly', { spec, width, height }, T_HEAVY)

// 描述统计（L1）：基于「加工 + 手工编辑后」的数据，与画布一致
export const statsColumns = (source, prep) => post('/api/stats/columns', { source, prep })
export const statsSummary = (source, prep, vars, groupBy) =>
  post('/api/stats/summary', { source, prep, vars, groupBy }, T_HEAVY)
// 统计检验（L2）
export const statsSuggest = (source, prep) => post('/api/stats/suggest', { source, prep })
export const statsTest = (source, prep, { y = '', x = '', group = '', method = '' } = {}) =>
  post('/api/stats/test', { source, prep, y, x, group, method }, T_HEAVY)
// 显著性标注规划（L3）：可选比较对 + 默认 y 位置
export const sigPlan = (spec) => post('/api/sig/plan', { spec })
// 回归分析（L4）
export const regColumns = (source, prep) => post('/api/reg/columns', { source, prep })
export const regFit = (source, prep, { y = '', xs = [], method = 'lm' } = {}) =>
  post('/api/reg/fit', { source, prep, y, xs, method }, T_HEAVY)
// 基线特征表（L5）
export const table1Columns = (source, prep) => post('/api/table1/columns', { source, prep })
export const table1Build = (source, prep, opts = {}) =>
  post('/api/table1/build', {
    source, prep,
    vars: opts.vars || [], by: opts.by || '', statId: opts.statId || 'mean_sd',
    addP: !!opts.addP, includeOverall: !!opts.includeOverall, digits: opts.digits ?? 2
  }, T_HEAVY)
export const table1Export = (source, prep, opts = {}, format = 'docx') =>
  post('/api/table1/export', {
    source, prep,
    vars: opts.vars || [], by: opts.by || '', statId: opts.statId || 'mean_sd',
    addP: !!opts.addP, includeOverall: !!opts.includeOverall, digits: opts.digits ?? 2,
    format
  }, T_HEAVY)

// 手动编辑（编辑模式）：ops 针对 source 的加工+编辑后数据
export const editAdd = async (source, prep, op) => {
  const res = await post('/api/edits/add', { source, prep, op })
  if (!res.ok && !('count' in res)) throw new Error(res.error || '编辑失败')
  if (res.ok === false) throw new Error(res.error)
  return res
}
export const editUndo = (source) => post('/api/edits/undo', { source })
export const editsClear = (source) => post('/api/edits/clear', { source })

// 图库（pins，用于 patchwork 拼图）
export const getPins = () => api('/api/pins')
export const savePin = (specJson, label = null, project = '') => post('/api/pins/save', { specJson, label, project })
// 覆盖更新已有条目（标签不变）；条目已删除时后端会回退为新建，返回 created 标记
export const updatePin = (id, specJson, label = null, project = '') =>
  post('/api/pins/update', { id, specJson, label, project })
export const deletePin = (id) => post('/api/pins/delete', { id })
export const renamePin = (id, label) => post('/api/pins/rename', { id, label })
export const saveCodePin = (payload) => post('/api/pins/save-code', payload)
export const openPin = (id) => post('/api/pins/open', { id })

// 退出服务：后端置标志位，由 R 主循环优雅停止（进程退出后本页面将不再可用）
export const shutdownServer = () => post('/api/shutdown', {})

export function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 4000)
}
