// ggplotGUI - 后端 API 封装
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
export const getSources = () => api('/api/sources')
export const getColumns = (src) => api(`/api/columns?src=${encodeURIComponent(src)}`)
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

export const rawRender = (code, spec, { width = 800, height = 500, dpi = 150 } = {}) =>
  post('/api/rawrender', { code, spec, width, height, dpi }, T_HEAVY)

export const exportPlot = async (spec, { width = 1600, height = 1000, dpi = 300, format = 'png' } = {}) => {
  const res = await post('/api/export', { spec, width, height, dpi, format }, T_HEAVY)
  if (!res.ok || !res.url) throw new Error(res.error || '导出失败')
  const r = await fetch(res.url)
  if (!r.ok) throw new Error(`下载导出文件失败: HTTP ${r.status}`)
  const blob = await r.blob()
  return { blob, filename: res.filename || `ggplotgui.${format}` }
}

export const getPlotly = (spec, { width = 800, height = 500 } = {}) =>
  post('/api/plotly', { spec, width, height }, T_HEAVY)

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
export const savePin = (specJson, label = null) => post('/api/pins/save', { specJson, label })
export const deletePin = (id) => post('/api/pins/delete', { id })

export function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = filename
  a.click()
  setTimeout(() => URL.revokeObjectURL(url), 4000)
}
