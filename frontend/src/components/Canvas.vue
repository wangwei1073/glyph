<script setup>
// 画布：图表预览 / 代码视图 / 渲染与导出设置 / 状态行
import { ref, computed, onMounted, onBeforeUnmount, nextTick } from 'vue'
import { ElMessage } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { useDataStore } from '../stores/data'
import { usePinStore } from '../stores/pins'
import { exportPlot, downloadBlob, genCode, getPlotly, checkExport, getJournalTemplates, bundlePlot } from '../api'
import StatsPanel from './StatsPanel.vue'
import CodeEditor from './CodeEditor.vue'
import { useUiStore } from '../stores/ui'

const spec = useSpecStore()
const meta = useMetaStore()
const data = useDataStore()
const pins = usePinStore()
const ui = useUiStore()
const view = ref('plot')
const zoom100 = ref(false)
// 「自适应画布」：按容器实际尺寸 × devicePixelRatio 渲染，让大屏也能看到清晰的图。
// 图仍按 1:1 像素显示（不插值放大），所以清晰度不损失。
// 用户手动改画幅时自动关闭，避免设置被窗口尺寸覆盖。
const fitToCanvas = ref(localStorage.getItem('gg-fit-canvas') !== '0')
const canvasWrapEl = ref(null)
let ro = null          // ResizeObserver：容器尺寸变化（窗口缩放 / 拖动左右面板）
const exporting = ref(false)
const sizePopover = ref(false)
const plotlyVisible = ref(false)
const plotlyData = ref(null)
const plotlyLoading = ref(false)
const plotlyEl = ref(null)

const imgSrc = computed(() => spec.imgSrc)

// ---- 色觉/灰度模拟预览（只作用于画布显示，不影响导出文件）----
// 投稿前检查配色在色觉障碍读者与灰度打印下的可读性。
// 矩阵取 Machado (2009) 的通用模拟值；灰度用亮度加权的 CSS 滤镜。
const cvdFilter = ref('')   // '' | gray | deu | pro | tri
const CVD_OPTIONS = [
  { value: '', label: '正常视觉' },
  { value: 'gray', label: '灰度打印模拟' },
  { value: 'deu', label: '绿色盲（Deuteranopia）' },
  { value: 'pro', label: '红色盲（Protanopia）' },
  { value: 'tri', label: '蓝黄色盲（Tritanopia）' }
]
const cvdStyle = computed(() => {
  if (!cvdFilter.value) return null
  return { filter: cvdFilter.value === 'gray' ? 'grayscale(1)' : `url(#cvd-${cvdFilter.value})` }
})
// 代码图状态下，导出/检查/打包都必须针对「这段代码」而不是 spec：
// 代码图没有图层，按 spec 走会导出一张空白图（而且不报错）。
const activeCode = computed(() =>
  (spec.last && spec.last.renderedFromCode) ? (spec.last.code || '') : '')
// 扩展是否启用（关闭后隐藏/禁用对应入口，避免点了才报错）
const plotlyOn = computed(() => !!(meta.ext && meta.ext.plotly))
// 底栏状态：优先表达画布自身状态（空画布 / 拼图），其次数据上下文与耗时
const statusParts = computed(() => {
  if (!spec.hasContent) return '空画布 · 尚未添加图层'
  const parts = []
  if (spec.composeActive) parts.push(`拼图 ${spec.spec.combine.slots.length} 图`)
  const cur = data.current
  if (cur && cur.type !== 'none') parts.push(`${cur.label} ${data.preview.nrow}×${data.preview.ncol}`)
  if (spec.last.elapsed) parts.push(`渲染 ${spec.last.elapsed}ms`)
  return parts.join(' · ')
})
// 完整信息（含环境版本与警告）走 tooltip
const statusTitle = computed(() => {
  const parts = [`ggplot2 ${meta.ggplot2Version}`]
  if (!spec.hasContent) parts.push('空画布')
  const cur = data.current
  if (cur && cur.type !== 'none') parts.push(`${cur.label} ${data.preview.nrow}×${data.preview.ncol}`)
  if (spec.last.elapsed) parts.push(`渲染 ${spec.last.elapsed}ms`)
  if (spec.last.warnings?.length) parts.push(`警告 ${spec.last.warnings.length}`)
  return parts.join(' · ')
})

// 导出尺寸独立于预览尺寸（默认高清）
const exportOpts = ref({ width: 1600, height: 1000, dpi: 300 })

// ---- 物理尺寸模式（mm ⇄ px）----
const pxToMm = (px, dpi) => Math.round((px / Math.max(dpi, 1)) * 25.4 * 10) / 10
const mmToPx = (mm, dpi) => Math.max(1, Math.round((mm / 25.4) * dpi))
const sizeMode = ref(localStorage.getItem('ggplotgui-size-mode') === 'mm' ? 'mm' : 'px')
const renderMm = ref({
  w: pxToMm(900, 150), h: pxToMm(560, 150)
})
const exportMm = ref({
  w: pxToMm(1600, 300), h: pxToMm(1000, 300)
})
const PRESETS = [
  { label: '单栏 85', mm: 85 },
  { label: '1.5 栏 114', mm: 114 },
  { label: '双栏 170', mm: 170 },
  { label: 'Nature 89', mm: 89 }
]
const sizeLabel = computed(() => {
  const base = sizeMode.value === 'mm'
    ? `${renderMm.value.w}×${renderMm.value.h} mm · ${spec.renderOpts.dpi}dpi`
    : `${spec.renderOpts.width}×${spec.renderOpts.height} · ${spec.renderOpts.dpi}dpi`
  // 自适应开启时加个标记，让用户知道这个数字会随窗口变化
  return fitToCanvas.value ? `${base} · 自适应` : base
})
const sizeHint = computed(() => {
  const d = spec.renderOpts.dpi || 150
  const ed = exportOpts.value.dpi || 300
  const base = spec.spec.theme?.args?.base_size || 11
  return `预览 ${pxToMm(spec.renderOpts.width, d)}×${pxToMm(spec.renderOpts.height, d)} mm`
    + ` · 导出 ${pxToMm(exportOpts.value.width, ed)}×${pxToMm(exportOpts.value.height, ed)} mm`
    + `。字号按 pt 输出、与 dpi 无关；当前主题基础字号 ${base}pt。`
})

// 从「代码图」回到「自己的 spec 图」—— 实际逻辑在 store，画布顶栏与设置面板共用
function backToSpec() {
  if (!spec.backToSpec()) {
    ElMessage.warning('画布没有图层，无法返回；先添加图层或载入项目')
  }
}

// 计算「画布实际的渲染像素尺寸」：容器内容区尺寸 × DPR
// 说明：减去 padding 是因为 .gg-canvas-wrap 有 16px 内边距，图片可用的就是内容区。
const DPR = Math.min(window.devicePixelRatio || 1, 2)   // 上限 2，避免 3x/4x 屏渲染过慢
function computeFitSize() {
  const el = canvasWrapEl.value
  if (!el) return null
  // 容器隐藏时（切到「代码」页签）尺寸为 0，此时不更新画幅，避免误渲染成最小值
  if (el.clientWidth < 80 || el.clientHeight < 80) return null
  const cs = getComputedStyle(el)
  const padX = parseFloat(cs.paddingLeft) + parseFloat(cs.paddingRight)
  const padY = parseFloat(cs.paddingTop) + parseFloat(cs.paddingBottom)
  const w = Math.max(200, Math.round((el.clientWidth - padX) * DPR))
  const h = Math.max(150, Math.round((el.clientHeight - padY) * DPR))
  return { width: Math.min(w, 4000), height: Math.min(h, 4000) }
}

// 应用自适应尺寸：仅在值真的变化时更新，避免无谓重渲染
function applyFitSize() {
  if (!fitToCanvas.value) return
  const s = computeFitSize()
  if (!s) return
  if (s.width === spec.renderOpts.width && s.height === spec.renderOpts.height) return
  spec.renderOpts.width = s.width
  spec.renderOpts.height = s.height
  if (sizeMode.value === 'mm') {
    renderMm.value = {
      w: pxToMm(s.width, spec.renderOpts.dpi),
      h: pxToMm(s.height, spec.renderOpts.dpi)
    }
  }
  // 只改 renderOpts，不在这里触发渲染：App.vue 的 renderOpts watch 是唯一的渲染触发者。
  // 此前两处各挂一个防抖（这里 320ms + App 550ms），每次 fit-size 变化都会打两次后端渲染。
  // renderNow 内部会判断当前画面是「代码图」还是「普通图」，来源判断不依赖这里。
}

function toggleFit() {
  fitToCanvas.value = !fitToCanvas.value
  try { localStorage.setItem('gg-fit-canvas', fitToCanvas.value ? '1' : '0') } catch { /* 忽略 */ }
  if (fitToCanvas.value) applyFitSize()
}

// 用户手动改画幅 → 关闭自适应（否则设置会被窗口尺寸覆盖，造成困惑）
function markManualSize() {
  if (!fitToCanvas.value) return
  fitToCanvas.value = false
  try { localStorage.setItem('gg-fit-canvas', '0') } catch { /* 忽略 */ }
}

function setSizeMode(mode) {
  sizeMode.value = mode
  try { localStorage.setItem('ggplotgui-size-mode', mode) } catch { /* 忽略 */ }
  if (mode === 'mm') {
    renderMm.value = {
      w: pxToMm(spec.renderOpts.width, spec.renderOpts.dpi),
      h: pxToMm(spec.renderOpts.height, spec.renderOpts.dpi)
    }
    exportMm.value = {
      w: pxToMm(exportOpts.value.width, exportOpts.value.dpi),
      h: pxToMm(exportOpts.value.height, exportOpts.value.dpi)
    }
  }
}
function applyRenderMm() {
  const d = spec.renderOpts.dpi || 150
  spec.renderOpts.width = mmToPx(renderMm.value.w, d)
  spec.renderOpts.height = mmToPx(renderMm.value.h, d)
}
function setRenderMm(k, v) {
  if (!v) return
  markManualSize()
  renderMm.value[k] = v
  applyRenderMm()
}
function setRenderDpi(v) {
  markManualSize()
  spec.renderOpts.dpi = v
  if (sizeMode.value === 'mm') applyRenderMm()
}
// 像素模式下手动改宽高：同样视为「用户接管尺寸」，关闭自适应
function setRenderPx(k, v) {
  if (!v) return
  markManualSize()
  spec.renderOpts[k] = v
}
function applyExportMm() {
  const d = exportOpts.value.dpi || 300
  exportOpts.value.width = mmToPx(exportMm.value.w, d)
  exportOpts.value.height = mmToPx(exportMm.value.h, d)
}
function setExportMm(k, v) {
  if (!v) return
  exportMm.value[k] = v
  applyExportMm()
}
function setExportDpi(v) {
  exportOpts.value.dpi = v
  if (sizeMode.value === 'mm') applyExportMm()
}
function applyPreset(which, mm) {
  const cur = which === 'render' ? renderMm.value : exportMm.value
  const ratio = (cur.h / cur.w) || 0.66
  const next = { w: mm, h: Math.max(20, Math.round(mm * ratio)) }
  if (which === 'render') {
    markManualSize()
    renderMm.value = next
    applyRenderMm()
  } else {
    exportMm.value = next
    applyExportMm()
  }
}

// ---- 导出前检查 ----
const checkVisible = ref(false)
const checkIssues = ref([])
const checkInfo = ref(null)
const checking = ref(false)
const pendingFormat = ref('png')

// 期刊模板（可选）：选中后检查按模板的栏宽/字号/字体/格式判定
const journals = ref([])
const journalId = ref(localStorage.getItem('ggplotgui-journal') || '')
onMounted(async () => {
  try {
    const r = await getJournalTemplates()
    journals.value = r.templates || []
  } catch { /* 模板不可用不影响导出 */ }

  // 自适应画布：首次挂载后按容器实际尺寸定一次画幅
  await nextTick()
  applyFitSize()

  // 用 ResizeObserver 监听画布容器本身：
  // 窗口缩放、拖动左右面板、折叠侧栏都会改变容器尺寸，而只有前者会触发 window.resize。
  // 只监听 window.resize 会导致「拖面板后画布不对齐、且不重新渲染」。
  if (typeof ResizeObserver !== 'undefined' && canvasWrapEl.value) {
    ro = new ResizeObserver(() => {
      if (!fitToCanvas.value) return
      clearTimeout(resizeTimer)
      resizeTimer = setTimeout(() => { resizeTimer = null; applyFitSize() }, 260)
    })
    ro.observe(canvasWrapEl.value)
  }
  window.addEventListener('resize', onWinResize)
})

// 窗口/面板宽度变化 → 重新按容器尺寸渲染（防抖，避免拖动时反复请求）
let resizeTimer = null
function onWinResize() {
  if (!fitToCanvas.value) return
  clearTimeout(resizeTimer)
  resizeTimer = setTimeout(() => { resizeTimer = null; applyFitSize() }, 260)
}

onBeforeUnmount(() => {
  window.removeEventListener('resize', onWinResize)
  if (ro) { ro.disconnect(); ro = null }
  clearTimeout(resizeTimer)
})
function setJournal(id) {
  journalId.value = id || ''
  try { localStorage.setItem('ggplotgui-journal', journalId.value) } catch { /* 忽略 */ }
  if (checkVisible.value) runExportCheck(pendingFormat.value)
}

// 期刊模板一键套用：栏宽 → 导出宽度（mm 模式换算），dpi → 模板下限，然后立刻重新检查。
// 只动导出尺寸不动画布渲染尺寸——用户可以继续用大画布编辑，投稿导出时才是期刊规格
function applyJournal() {
  const tpl = journals.value.find(t => t.id === journalId.value)
  if (!tpl) return
  if (tpl.minDpi) exportOpts.value.dpi = tpl.minDpi
  if (tpl.widthMm) {
    exportMm.value.w = tpl.widthMm
    applyExportMm()   // 按（已更新的）dpi 把 mm 换算回 px
  }
  ElMessage.success(`已套用 ${tpl.label}：${tpl.widthMm ? `${tpl.widthMm}mm 栏宽 · ` : ''}${exportOpts.value.dpi} dpi`)
  runExportCheck(pendingFormat.value)
}

const checkIcon = (level) => ({
  pass: 'CircleCheck', warn: 'Warning', fail: 'CircleClose', info: 'InfoFilled'
}[level] || 'InfoFilled')

async function runExportCheck(format, { silentPass = false } = {}) {
  checking.value = true
  try {
    const res = await checkExport(spec.spec, { ...exportOpts.value, format, journal: journalId.value, code: activeCode.value })
    checkIssues.value = res.issues || []
    checkInfo.value = res.info || null
    const blocking = checkIssues.value.some(i => i.level === 'warn' || i.level === 'fail')
    if (blocking || !silentPass) checkVisible.value = true
    return res
  } catch (e) {
    ElMessage.warning('导出检查暂不可用：' + e.message)
    return null
  } finally {
    checking.value = false
  }
}

// 一键修复：只改确定性的 spec/尺寸，然后自动重新检查
function applyFix(fix) {
  if (!fix) return
  const f = fix.action
  if (f === 'dpi') {
    // 改 dpi 时保持物理尺寸不变（模板修复的语义），而不是保持像素不变
    const mmW = pxToMm(exportOpts.value.width, exportOpts.value.dpi)
    const mmH = pxToMm(exportOpts.value.height, exportOpts.value.dpi)
    exportOpts.value.dpi = fix.value
    exportOpts.value.width = mmToPx(mmW, fix.value)
    exportOpts.value.height = mmToPx(mmH, fix.value)
    exportMm.value = { w: mmW, h: mmH }
  } else if (f === 'width') {
    const ratio = (exportMm.value.h / exportMm.value.w) || 0.66
    exportMm.value = { w: fix.value, h: Math.max(20, Math.round(fix.value * ratio)) }
    applyExportMm()
  } else if (f === 'textsize') {
    const base = Math.max(8, Math.ceil(fix.value / 0.8))
    if (!spec.spec.theme.base) spec.setTheme({ base: 'minimal', args: { base_size: base } })
    else spec.setTheme({ args: { ...(spec.spec.theme.args || {}), base_size: base } })
  } else if (f === 'white') {
    const els = { ...(spec.spec.theme.elements || {}) }
    els['plot.background'] = { type: 'rect', props: { fill: '#FFFFFF' } }
    els['panel.background'] = { type: 'rect', props: { fill: '#FFFFFF' } }
    spec.setTheme({ elements: els })
  } else if (f === 'font') {
    if (!spec.spec.theme.base) spec.setTheme({ base: 'minimal', args: { base_family: fix.value } })
    else spec.setTheme({ args: { ...(spec.spec.theme.args || {}), base_family: fix.value } })
  } else if (f === 'format') {
    pendingFormat.value = fix.value
  }
  setTimeout(() => runExportCheck(pendingFormat.value), 350)
}

async function doExport(format) {
  if (format === 'bundle') return bundleNow()
  if (format === 'check') {
    if (!spec.hasPlot) return ElMessage.warning('先渲染一张图再检查')
    pendingFormat.value = 'png'
    await runExportCheck('png')
    return
  }
  if (!spec.hasPlot) return
  pendingFormat.value = format
  const res = await runExportCheck(format, { silentPass: true })
  if (res === null) return exportNow(format)        // 检查接口异常时直接导出
  const blocking = (res.issues || []).some(i => i.level === 'warn' || i.level === 'fail')
  if (!blocking) await exportNow(format)
}

// 可复现包：图 + 数据 + 代码 + sessionInfo + 图注 + 项目文件
async function bundleNow() {
  if (!spec.hasPlot) return ElMessage.warning('先渲染一张图再打包')
  exporting.value = true
  try {
    const { width, height, dpi } = exportOpts.value
    const res = await bundlePlot(spec.spec, { width, height, dpi, journal: journalId.value, projectId: spec.projectId, code: activeCode.value })
    if (!res.ok || !res.url) throw new Error(res.error || '打包失败')
    const r = await fetch(res.url)
    if (!r.ok) throw new Error(`下载失败: HTTP ${r.status}`)
    downloadBlob(await r.blob(), res.filename || 'ggplotgui-bundle.zip')
    ElMessage.success('可复现包已导出（图 + 数据 + 代码 + 图注）')
  } catch (e) {
    ElMessage.error('可复现包导出失败: ' + e.message)
  } finally {
    exporting.value = false
  }
}

async function exportNow(format) {
  checkVisible.value = false
  exporting.value = true
  try {
    const { width, height, dpi } = exportOpts.value
    const { blob, filename } = await exportPlot(spec.spec, { width, height, dpi, format, code: activeCode.value })
    downloadBlob(blob, filename)
    ElMessage.success(`已导出 ${filename}`)
  } catch (e) {
    ElMessage.error('导出失败: ' + e.message)
  } finally {
    exporting.value = false
  }
}

const checkSummary = computed(() => {
  const list = checkIssues.value
  const nWarn = list.filter(i => i.level === 'warn').length
  const nFail = list.filter(i => i.level === 'fail').length
  if (nFail) return `${nFail} 项未通过`
  if (nWarn) return `${nWarn} 项建议`
  return '全部通过'
})

async function copyCode() {
  const text = codeBlock.value || spec.last.code
  if (!text) return
  try {
    await navigator.clipboard.writeText(text)
    ElMessage.success('代码已复制')
  } catch {
    ElMessage.warning('复制失败，请手动选择复制')
  }
}

const codeBlock = computed(() => spec.last.code || '')
const codeLineCount = computed(() => (codeBlock.value ? codeBlock.value.split('\n').length : 0))

// 把当前代码送进「高级」页编辑器：切页签 + 填内容
// 之后用户在高级页改代码、点运行，画布与本代码视图会随渲染结果同步更新。
function loadIntoEditor() {
  const code = codeBlock.value
  if (!code) return ElMessage.warning('还没有可载入的代码，先渲染一次图形')
  spec.pendingCode = code
  ui.setTab('adv')
  ElMessage.success('已载入「高级」页编辑器，可修改后点击运行')
}

async function downloadCode() {
  let code = spec.last.code
  if (!code) {
    try { code = (await genCode(spec.spec)).code } catch { return }
  }
  const blob = new Blob([code], { type: 'text/plain;charset=utf-8' })
  downloadBlob(blob, 'ggplot-plot.R')
}

// 存入图库：编辑自某条图库条目时覆盖更新（标签不变），否则新建。
// 需要「另存为新条目」时去图库页签的分体按钮下拉里选。
function pinCurrent() {
  if (!spec.spec.layers.length) return
  pins.saveCurrent().then((res) => {
    const label = pins.byId[res.id]?.label || res.id
    if (res.created) ElMessage.success(`已存入图库：${label}`)
    else ElMessage.success(`已更新图库条目：${label}`)
  }).catch((e) => ElMessage.error(e.message))
}

function addFirstLayer() {
  spec.addLayer('point')
  if (!Object.keys(spec.spec.layers[0].aes || {}).length) spec.guessAes(spec.spec.layers[0])
}

async function showPlotly() {
  if (!plotlyOn.value) {
    ElMessage.warning('plotly 扩展已在「高级 → 扩展管理」中关闭')
    return
  }
  plotlyVisible.value = true
  plotlyLoading.value = true
  try {
    const res = await getPlotly(spec.spec, spec.renderOpts)
    if (res.ok && res.url) {
      // 大 JSON 走文件流获取
      const r2 = await fetch(res.url)
      if (!r2.ok) throw new Error(`HTTP ${r2.status}`)
      plotlyData.value = await r2.json()
      setTimeout(drawPlotly, 60)
    } else if (res.ok) {
      plotlyData.value = res.plotly
      setTimeout(drawPlotly, 60)
    } else ElMessage.error(res.error)
  } catch (e) {
    ElMessage.error('plotly 预览失败: ' + e.message)
  } finally {
    plotlyLoading.value = false
  }
}

async function drawPlotly() {
  if (!plotlyEl.value || !plotlyData.value) return
  const Plotly = (await import('plotly.js-dist-min')).default
  Plotly.react(plotlyEl.value, plotlyData.value.data, {
    ...plotlyData.value.layout,
    width: plotlyEl.value.clientWidth,
    autosize: false
  }, plotlyData.value.config)
}

// 关闭时清理 Plotly 实例：destroy-on-close 只删 DOM，不清 Plotly 内部注册表，反复开关会累积泄漏
async function purgePlotly() {
  plotlyData.value = null
  if (!plotlyEl.value) return
  try {
    const Plotly = (await import('plotly.js-dist-min')).default
    Plotly.purge(plotlyEl.value)
  } catch { /* 忽略 */ }
}
</script>

<template>
  <div class="gg-canvas-head">
    <!-- 组 1｜编辑：撤销 / 重做 -->
    <div class="ch-group">
      <el-tooltip content="撤销 (Ctrl+Z)">
        <el-button size="small" text :disabled="!spec.canUndo" @click="spec.undo()">
          <el-icon><RefreshLeft /></el-icon>
        </el-button>
      </el-tooltip>
      <el-tooltip content="重做 (Ctrl+Y)">
        <el-button size="small" text :disabled="!spec.canRedo" @click="spec.redo()">
          <el-icon><RefreshRight /></el-icon>
        </el-button>
      </el-tooltip>
    </div>

    <span class="ch-sep" />

    <!-- 组 2｜视图：图表 / 代码 + 缩放 -->
    <div class="ch-group">
      <el-radio-group v-model="view" size="small">
        <el-radio-button value="plot">图表</el-radio-button>
        <el-radio-button value="code">代码</el-radio-button>
      </el-radio-group>
      <el-tooltip content="适合窗口 / 1:1">
        <el-button size="small" text @click="zoom100 = !zoom100">
          <el-icon><component :is="zoom100 ? 'FullScreen' : 'ScaleToOriginal'" /></el-icon>
        </el-button>
      </el-tooltip>
    </div>

    <!-- 代码图状态：放在顶栏而不是浮在画布上，避免遮挡图表 -->
    <template v-if="spec.last.renderedFromCode">
      <span class="ch-sep" />
      <div class="ch-group">
        <el-tooltip content="当前画布显示的是从图库打开的代码图。它由代码绘制，主题、配色、标度等设置对它不生效；点右侧「返回我的图」可按当前设置重新出图" placement="bottom">
          <span class="head-code-tag"><el-icon><Tickets /></el-icon>代码图</span>
        </el-tooltip>
        <el-tooltip v-if="spec.hasContent" content="切回按当前图层设置生成的图" placement="bottom">
          <el-button size="small" text type="primary" @click="backToSpec">
            <el-icon class="el-icon--left"><Back /></el-icon><span class="btn-label">返回我的图</span>
          </el-button>
        </el-tooltip>
      </div>
    </template>

    <span class="ch-sep" />

    <!-- 组 3：尺寸 -->
    <el-popover v-model:visible="sizePopover" placement="bottom-start" :width="310" trigger="click">
      <template #reference>
        <el-button size="small" text class="gg-mono size-btn" title="预览 / 导出尺寸">
          <el-icon class="size-icon"><FullScreen /></el-icon>
          <span class="size-text">{{ sizeLabel }}</span>
        </el-button>
      </template>

      <div class="size-mode">
        <el-radio-group :model-value="sizeMode" size="small" @update:model-value="setSizeMode">
          <el-radio-button value="px">像素</el-radio-button>
          <el-radio-button value="mm">毫米</el-radio-button>
        </el-radio-group>
        <span class="gg-hint">{{ sizeMode === 'mm' ? '按最终印刷尺寸设置' : '按屏幕像素设置' }}</span>
      </div>

      <!-- 自适应画布：按窗口实际大小渲染，大屏也能看清；手动改画幅会自动关闭 -->
      <div class="fit-row">
        <el-switch :model-value="fitToCanvas" size="small" @update:model-value="toggleFit" />
        <span class="fit-label">自适应画布</span>
        <span class="gg-hint">按窗口尺寸渲染，拖动窗口自动重算</span>
      </div>

      <div class="gg-subhead" style="padding:10px 0 4px">预览</div>
      <div class="size-row">
        <template v-if="sizeMode === 'mm'">
          <el-input-number :model-value="renderMm.w" :min="30" :max="500" :step="1" size="small"
            controls-position="right" style="width:84px" @update:model-value="setRenderMm('w', $event)" />
          <span class="unit">×</span>
          <el-input-number :model-value="renderMm.h" :min="20" :max="500" :step="1" size="small"
            controls-position="right" style="width:84px" @update:model-value="setRenderMm('h', $event)" />
          <span class="unit">mm</span>
        </template>
        <template v-else>
          <el-input-number :model-value="spec.renderOpts.width" :min="200" :max="4000" :step="20" size="small"
            controls-position="right" style="width:84px" @update:model-value="setRenderPx('width', $event)" />
          <span class="unit">×</span>
          <el-input-number :model-value="spec.renderOpts.height" :min="150" :max="4000" :step="20" size="small"
            controls-position="right" style="width:84px" @update:model-value="setRenderPx('height', $event)" />
          <span class="unit">px</span>
        </template>
        <el-select :model-value="spec.renderOpts.dpi" size="small" style="width:78px"
          @update:model-value="setRenderDpi">
          <el-option v-for="d in [72, 96, 150, 200, 300]" :key="d" :value="d" :label="d + ' dpi'" />
        </el-select>
      </div>
      <div class="size-presets">
        <el-button v-for="p in PRESETS" :key="'r' + p.mm" size="small" text
          @click="applyPreset('render', p.mm)">{{ p.label }}</el-button>
      </div>

      <div class="gg-subhead" style="padding:10px 0 4px">导出</div>
      <div class="size-row">
        <template v-if="sizeMode === 'mm'">
          <el-input-number :model-value="exportMm.w" :min="30" :max="500" :step="1" size="small"
            controls-position="right" style="width:84px" @update:model-value="setExportMm('w', $event)" />
          <span class="unit">×</span>
          <el-input-number :model-value="exportMm.h" :min="20" :max="500" :step="1" size="small"
            controls-position="right" style="width:84px" @update:model-value="setExportMm('h', $event)" />
          <span class="unit">mm</span>
        </template>
        <template v-else>
          <el-input-number v-model="exportOpts.width" :min="200" :max="12000" :step="100" size="small"
            controls-position="right" style="width:84px" />
          <span class="unit">×</span>
          <el-input-number v-model="exportOpts.height" :min="150" :max="12000" :step="100" size="small"
            controls-position="right" style="width:84px" />
          <span class="unit">px</span>
        </template>
        <el-select :model-value="exportOpts.dpi" size="small" style="width:78px"
          @update:model-value="setExportDpi">
          <el-option v-for="d in [96, 150, 200, 300, 600]" :key="d" :value="d" :label="d + ' dpi'" />
        </el-select>
      </div>
      <div class="size-presets">
        <el-button v-for="p in PRESETS" :key="'e' + p.mm" size="small" text
          @click="applyPreset('export', p.mm)">{{ p.label }}</el-button>
      </div>

      <div class="gg-hint" style="padding-top:8px">{{ sizeHint }}</div>
    </el-popover>

    <span style="flex:1" />

    <!-- 组 4｜渲染：自动 / 手动 + 立即渲染 -->
    <div class="ch-group ch-render">
      <el-tooltip :content="spec.autoRender
        ? '自动渲染：改动后自动出图（点击改为手动）'
        : '手动渲染：改动后不出图，点右侧「渲染」'">
        <el-switch v-model="spec.autoRender" size="small" />
      </el-tooltip>
      <span class="ch-auto-label" :class="{ off: !spec.autoRender }">
        {{ spec.autoRender ? '自动' : '手动' }}
      </span>
      <el-tooltip content="立即重新渲染当前图形">
        <el-button size="small" :loading="spec.rendering" @click="spec.renderNow()">
          <el-icon class="el-icon--left"><MagicStick /></el-icon><span class="btn-label">渲染</span>
        </el-button>
      </el-tooltip>
    </div>
  </div>

  <div v-show="view === 'plot'" ref="canvasWrapEl" class="gg-canvas-wrap">
    <!--
      显示条件用 hasContent（有图层/拼图槽位），而不是 hasPlot：
      - 空画布时后端也会渲染一张空白图并写进 last，若只看 hasPlot 就会显示这块白板，
        同时把首屏引导吞掉；
      - 「原始代码模式」只产出图、没有图层的情况，由 codeMode 兜住
        （该模式下 spec.layers 为空但确实要显示渲染结果）。
    -->
    <!-- 只用 zoom100 控制缩放；渲染中不做透明度变化。
         浏览器在新 src 加载完成前会继续显示旧的帧，所以不会闪白，
         渲染进展由右上角转圈提示。 -->
    <img v-if="imgSrc && (spec.hasContent || spec.last.renderedFromCode)"
      :src="imgSrc" class="gg-canvas-img" :class="{ zoom100 }"
      :style="cvdStyle" alt="plot" />
    <div v-else-if="!spec.last.error" class="gg-empty-hint">
      <el-icon class="ghost" :size="58"><TrendCharts /></el-icon>
      <div class="t">还没有图形</div>
      <el-button type="primary" size="small" @click="addFirstLayer">添加第一个图层</el-button>
      <div class="sub">左侧选择数据，右侧组合 geom 与设置</div>
    </div>
    <el-icon v-if="spec.rendering || spec.renderQueued" class="render-spin is-loading">
      <Loading />
    </el-icon>
  </div>

  <!-- 错误/警告：只要有图层或已产出过图就展示，避免渲染失败时把报错也藏起来 -->
  <div v-if="view === 'plot' && spec.last.error && (spec.hasContent || spec.hasPlot)" class="err-box">
    <el-alert type="error" :closable="false" show-icon>
      <template #title>渲染出错</template>
      <pre class="err-pre">{{ spec.last.error }}</pre>
    </el-alert>
  </div>

  <div v-if="view === 'plot' && spec.last.warnings.length && (spec.hasContent || spec.hasPlot)" class="warn-box">
    <el-collapse>
      <el-collapse-item :title="`警告 (${spec.last.warnings.length})`">
        <div v-for="(w, i) in spec.last.warnings.slice(0, 8)" :key="i" class="warn-item">{{ w }}</div>
      </el-collapse-item>
    </el-collapse>
  </div>

  <div v-show="view === 'code'" class="gg-code-view">
    <div class="code-head">
      <span class="gg-hint-md">
        由当前绘图规格生成，可直接粘贴到 RStudio / Positron 运行
      </span>
      <span style="flex:1" />
      <el-tooltip content="等宽字体、语法高亮、自动换行；可框选后复制" placement="bottom-end">
        <span class="code-lines gg-mono">{{ codeLineCount }} 行</span>
      </el-tooltip>
      <!-- 把当前代码送进「高级」页的编辑器，可改后再运行；跑完画布与本视图会同步更新 -->
      <el-tooltip content="载入到「高级」页编辑器，可修改后重新运行" placement="bottom-end">
        <el-button size="small" type="primary" plain :disabled="!codeBlock" @click="loadIntoEditor">
          <el-icon><EditPen /></el-icon> 载入编辑器
        </el-button>
      </el-tooltip>
      <el-button size="small" text @click="copyCode"><el-icon><CopyDocument /></el-icon> 复制</el-button>
      <el-button size="small" text @click="downloadCode"><el-icon><Download /></el-icon> 下载 .R</el-button>
    </div>
    <!-- 只读代码编辑器：与「高级」页共用 CodeEditor，保留高亮/行号/换行能力 -->
    <CodeEditor v-if="codeBlock" :model-value="codeBlock" readonly height="auto" class="code-editor" />
    <div v-else class="gg-empty-hint" style="padding:40px">暂无代码</div>
  </div>

  <!-- 底栏：数据统计抽屉（描述统计 + 统计检验） -->
  <StatsPanel />

  <!-- 底栏：单行。左侧状态提示，右侧产出与导出类动作 -->
  <div class="gg-footer">
    <div class="ft-status" :title="statusTitle">{{ statusParts }}</div>
    <el-tag v-if="spec.last.warnings?.length" size="small" type="warning" effect="plain"
      class="ft-warn" :disable-transitions="true">{{ spec.last.warnings.length }} 条警告</el-tag>
    <span class="ft-spacer" />

    <!-- 图库：编辑自某条时是「更新」，否则是「存入」 -->
    <el-tooltip :content="spec.sourcePinId
      ? `更新图库条目「${spec.sourcePinLabel || spec.sourcePinId}」（标签不变）`
      : '把当前图存入图库（用于拼图组合）'">
      <el-button size="small" text :disabled="!spec.spec.layers.length || spec.composeActive || pins.saving"
        @click="pinCurrent">
        <el-icon class="el-icon--left"><StarFilled /></el-icon>
        <span class="ft-label">{{ spec.sourcePinId ? '更新图库' : '存入图库' }}</span>
      </el-button>
    </el-tooltip>
    <el-tooltip :content="plotlyOn ? '生成可缩放、可悬停的交互图' : 'plotly 扩展已在「高级 → 扩展管理」中关闭'">
      <el-button size="small" text :disabled="!spec.hasPlot || !plotlyOn" @click="showPlotly">
        <el-icon class="el-icon--left"><DataLine /></el-icon><span class="ft-label">交互预览</span>
      </el-button>
    </el-tooltip>

    <!-- 色觉/灰度模拟：只改画布预览，导出文件不受影响 -->
    <el-dropdown trigger="click" size="small" @command="(v) => (cvdFilter = v)">
      <el-button size="small" text :type="cvdFilter ? 'primary' : ''">
        <el-icon class="el-icon--left"><View /></el-icon><span class="ft-label">色觉模拟</span>
      </el-button>
      <template #dropdown>
        <el-dropdown-menu>
          <el-dropdown-item v-for="o in CVD_OPTIONS" :key="o.value" :command="o.value"
            :class="{ 'cvd-on': cvdFilter === o.value }">{{ o.label }}</el-dropdown-item>
        </el-dropdown-menu>
      </template>
    </el-dropdown>

    <span class="ft-sep" />

    <!-- 导出：检查 / 可复现包 / 主导出按钮 -->
    <el-tooltip content="导出前检查画幅 / dpi / 字体 / 白底等期刊要求">
      <el-button size="small" text :disabled="!spec.hasPlot" @click="doExport('check')">
        <el-icon class="el-icon--left"><CircleCheck /></el-icon><span class="ft-label">导出检查</span>
      </el-button>
    </el-tooltip>
    <el-tooltip content="导出可复现包：图 + 数据 + 代码 + 图注 (.zip)">
      <el-button size="small" text :disabled="!spec.hasPlot" @click="bundleNow()">
        <el-icon class="el-icon--left"><Files /></el-icon><span class="ft-label">可复现包</span>
      </el-button>
    </el-tooltip>
    <el-dropdown split-button size="small" type="primary" :title="`导出 ${pendingFormat.toUpperCase()}`"
      :disabled="!spec.hasPlot" @click="doExport(pendingFormat)" @command="doExport">
      <el-icon><Download /></el-icon><span class="ft-label">导出</span>
      <template #dropdown>
        <el-dropdown-menu>
          <el-dropdown-item command="png">PNG 位图</el-dropdown-item>
          <el-dropdown-item command="svg">SVG 矢量</el-dropdown-item>
          <el-dropdown-item command="pdf">PDF 矢量</el-dropdown-item>
          <el-dropdown-item command="tiff" divided>TIFF 位图（投稿常用，LZW 压缩）</el-dropdown-item>
          <el-dropdown-item command="emf">EMF 矢量（Word）</el-dropdown-item>
        </el-dropdown-menu>
      </template>
    </el-dropdown>
  </div>

  <el-dialog v-model="checkVisible" title="导出前检查" width="580px">
    <div class="check-head">
      <el-icon :class="['check-dot', checkSummary === '全部通过' ? 'ok' : 'warn']"><CircleCheckFilled v-if="checkSummary === '全部通过'" /><WarningFilled v-else /></el-icon>
      <b>{{ checkSummary }}</b>
      <span v-if="checkInfo" class="gg-hint">
        {{ checkInfo.widthMm }} × {{ checkInfo.heightMm }} mm · {{ checkInfo.dpi }} dpi ·
        {{ (checkInfo.format || 'png').toUpperCase() }}
      </span>
      <span style="flex:1" />
      <el-select :model-value="journalId" size="small" class="journal-sel"
        placeholder="目标期刊" @update:model-value="setJournal">
        <el-option value="" label="不套模板" />
        <el-option v-for="t in journals" :key="t.id" :value="t.id" :label="t.label" />
      </el-select>
      <el-button size="small" :disabled="!journalId" @click="applyJournal">套用</el-button>
    </div>
    <div v-if="journalId" class="check-note">
      {{ journals.find(t => t.id === journalId)?.note }}
    </div>
    <div class="check-list">
      <div v-for="(it, i) in checkIssues" :key="i" class="check-item" :class="it.level">
        <el-icon class="ci-icon"><component :is="checkIcon(it.level)" /></el-icon>
        <div class="ci-body">
          <div class="ci-title">{{ it.title }}</div>
          <div class="ci-detail">{{ it.detail }}</div>
        </div>
        <el-button v-if="it.fix" size="small" text class="ci-fix" @click="applyFix(it.fix)">
          {{ it.fix.label }}
        </el-button>
      </div>
    </div>
    <template #footer>
      <el-button size="small" @click="checkVisible = false">取消</el-button>
      <el-button size="small" type="primary" :loading="exporting"
        @click="exportNow(pendingFormat)">
        仍然导出 {{ (pendingFormat || 'png').toUpperCase() }}
      </el-button>
    </template>
  </el-dialog>

  <el-dialog v-model="plotlyVisible" title="plotly 交互预览（部分 geom 不支持）" width="82%" destroy-on-close @opened="drawPlotly" @close="purgePlotly">
    <div v-loading="plotlyLoading" style="min-height:300px">
      <div ref="plotlyEl" />
    </div>
  </el-dialog>

  <!-- 色觉模拟滤镜矩阵（Machado 2009 近似），供画布 img 的 CSS filter: url() 引用 -->
  <svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false">
    <defs>
      <filter id="cvd-deu">
        <feColorMatrix type="matrix" values="0.367 0.860 -0.227 0 0  0.280 0.673 0.047 0 0  -0.012 0.043 0.969 0 0  0 0 0 1 0" />
      </filter>
      <filter id="cvd-pro">
        <feColorMatrix type="matrix" values="0.152 1.052 -0.204 0 0  0.115 0.786 0.099 0 0  -0.003 -0.048 1.051 0 0  0 0 0 1 0" />
      </filter>
      <filter id="cvd-tri">
        <feColorMatrix type="matrix" values="1.256 -0.077 -0.179 0 0  -0.016 0.927 0.089 0 0  0.006 0.143 0.851 0 0  0 0 0 1 0" />
      </filter>
    </defs>
  </svg>
</template>

<style scoped>
.gg-canvas-head {
  display: flex; align-items: center; gap: 6px; padding: 0 12px;
  height: var(--gg-strip-h);
  border-bottom: 1px solid var(--gg-border); background: var(--gg-panel); flex-shrink: 0;
  flex-wrap: nowrap; min-width: 0; overflow: hidden;
}
/* 分组：同组内间距最小，组与组之间用分隔线，视觉上归纳成 5 个区 */
.ch-group { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }
.ch-sep {
  width: 1px; height: 16px; flex-shrink: 0;
  background: var(--gg-border); margin: 0 2px;
}
.ch-auto-label {
  font-size: var(--gg-fs-xs); color: var(--gg-text-3); white-space: nowrap;
  cursor: default; user-select: none;
}
.ch-auto-label.off { color: #c07f18; }
/* 页签与尺寸这类"必须完整显示"的控件不允许收缩；其余按钮允许被裁 */
.gg-canvas-head :deep(.el-radio-group) { flex-shrink: 0; }
.gg-canvas-head :deep(.el-button) { flex-shrink: 0; }
.btn-label { white-space: nowrap; }
/* 画布变窄时逐级收起文字，只留图标；自动/手动开关始终可见 */
@media (max-width: 1480px) {
  .gg-canvas-head .ch-auto-label { display: none; }
  .gg-canvas-head { gap: 4px; padding: 0 8px; }
}
@media (max-width: 1240px) {
  .gg-canvas-head .btn-label { display: none; }
  .gg-canvas-head .ch-sep { display: none; }
}
.render-spin { position: absolute; top: var(--gg-strip-h); right: 22px; z-index: 5; }
.err-box { padding: 8px 14px; flex-shrink: 0; }
.err-pre { margin: 4px 0 0; white-space: pre-wrap; font-size: 12px; font-family: Consolas, monospace; max-height: 140px; overflow: auto; }
.warn-box { padding: 4px 14px 8px; flex-shrink: 0; }
.warn-item { font-size: 12px; color: var(--gg-text-3); padding: 1px 0; }
/* 代码视图：头部固定，编辑器区域自身滚动 */
.gg-code-view {
  background: var(--gg-panel); flex: 1; min-height: 0;
  display: flex; flex-direction: column;
}
.code-editor { flex: 1; min-height: 0; overflow: auto; }
.code-lines {
  font-size: var(--gg-fs-xs); color: var(--gg-text-4);
  margin-right: 8px; white-space: nowrap;
}

/* 底栏：单行 34px。左侧状态提示（可省略），右侧产出与导出类动作 */
.gg-footer {
  flex-shrink: 0; display: flex; align-items: center; gap: 2px;
  height: var(--gg-foot-h); padding: 0 10px;
  border-top: 1px solid var(--gg-border);
  background: var(--gg-panel);
  overflow: hidden;
}
.ft-status {
  flex: 0 1 auto; min-width: 0; max-width: 40%;
  font-family: Consolas, "JetBrains Mono", "Courier New", monospace;
  font-size: var(--gg-fs-xs); color: var(--gg-text-3);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
  padding: 0 2px;
}
.ft-spacer { flex: 1 1 auto; min-width: 4px; }
/* 底栏内的动作分隔线：图库类 ｜ 导出类 */
.ft-sep {
  width: 1px; height: 14px; flex-shrink: 0;
  background: var(--gg-border); margin: 0 4px;
}
.gg-footer .el-button { margin: 0; padding: 0 6px; height: 22px; font-size: var(--gg-fs-sm); flex-shrink: 0; }
.gg-footer :deep(.el-dropdown) { flex-shrink: 0; margin-left: 2px; }
.gg-footer :deep(.el-dropdown .el-button) { height: 24px; }
.ft-label { white-space: nowrap; }
.ft-warn { flex-shrink: 0; }
/* 窄底栏：先隐按钮文字，再隐状态文字，保证导出主按钮始终完整 */
@media (max-width: 1240px) {
  .gg-footer .ft-label { display: none; }
}
@media (max-width: 1080px) {
  .gg-footer .ft-status { display: none; }
}
.gg-empty-hint .ghost { color: var(--gg-text-4); margin-bottom: 10px; }
.gg-empty-hint .t { font-size: 14px; font-weight: 600; color: var(--gg-text-2); margin-bottom: 12px; }
.gg-empty-hint .sub { margin-top: 10px; font-size: 12px; color: var(--gg-text-3); }

/* 顶栏里的「代码图」状态标签：橙色调，与图库卡片的代码图徽标呼应 */
.head-code-tag {
  display: inline-flex; align-items: center; gap: 3px; flex-shrink: 0;
  height: 20px; padding: 0 6px; border-radius: var(--gg-r-sm);
  font-size: var(--gg-fs-xs); font-weight: 500;
  background: #fff5e6; color: #a4700f; border: 1px solid #f0d9b5;
  white-space: nowrap;
}
html.dark .head-code-tag { background: #3a2f18; color: #ddb26a; border-color: #5a4a25; }

/* 尺寸设置 */
.size-mode { display: flex; align-items: center; gap: 8px; }
.fit-row { display: flex; align-items: center; gap: 6px; padding: 8px 0 2px; }
.fit-row .fit-label { font-size: var(--gg-fs-sm); color: var(--gg-text-2); }
.fit-row .gg-hint { font-size: var(--gg-fs-xs); color: var(--gg-text-4); }
.size-row { display: flex; align-items: center; gap: 4px; }
.size-row .unit { font-size: 11px; color: var(--gg-text-4); }
.size-presets { display: flex; flex-wrap: wrap; gap: 2px; margin-top: 4px; }
.size-presets .el-button { margin: 0; padding: 0 6px; height: 22px; font-size: 11px; color: var(--gg-text-3); }
.size-presets .el-button:hover { color: var(--gg-brand); background: transparent; }

/* 导出前检查 */
.check-head { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; font-size: 13px; }
.check-head .check-dot { font-size: 18px; }
.check-dot.ok { color: var(--gg-success, #3f9d6b); }
.check-dot.warn { color: #d98c1f; }
.check-list { display: flex; flex-direction: column; gap: 2px; max-height: 360px; overflow: auto; }
.check-item { display: flex; gap: 9px; padding: 8px 10px; border-radius: 8px; background: var(--gg-panel-2); }
.check-item + .check-item { margin-top: 4px; }
.check-item .ci-icon { margin-top: 1px; font-size: 15px; color: var(--gg-text-4); }
.check-item.pass .ci-icon { color: #3f9d6b; }
.check-item.warn .ci-icon { color: #d98c1f; }
.check-item.fail { background: #fdf1f1; }
.check-item.fail .ci-icon { color: #d9534f; }
.check-item.info .ci-icon { color: var(--gg-brand); }
.ci-title { font-size: 12.5px; font-weight: 600; color: var(--gg-text-1); }
.ci-detail { font-size: 12px; color: var(--gg-text-3); line-height: 1.55; margin-top: 2px; }
.check-item { align-items: flex-start; }
.ci-fix { flex-shrink: 0; margin-left: auto; padding: 0 4px; font-size: 12px; color: var(--gg-brand); }
.journal-sel { width: 130px; flex-shrink: 0; }
.check-note { font-size: 11px; color: var(--gg-text-3); margin: -2px 0 8px 26px; }
</style>
<style scoped>
/* 色觉模拟下拉里当前选中项高亮（el-dropdown-item 无内置选中态） */
.cvd-on { color: var(--gg-accent); font-weight: 600; background: rgba(74, 144, 217, .08); }
</style>
