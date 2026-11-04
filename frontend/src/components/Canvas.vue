<script setup>
// 画布：图表预览 / 代码视图 / 渲染与导出设置 / 状态行
import { ref, computed, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { useDataStore } from '../stores/data'
import { usePinStore } from '../stores/pins'
import { exportPlot, downloadBlob, genCode, getPlotly, checkExport, getJournalTemplates } from '../api'

const spec = useSpecStore()
const meta = useMetaStore()
const data = useDataStore()
const pins = usePinStore()
const view = ref('plot')
const zoom100 = ref(false)
const exporting = ref(false)
const sizePopover = ref(false)
const plotlyVisible = ref(false)
const plotlyData = ref(null)
const plotlyLoading = ref(false)
const plotlyEl = ref(null)

const imgSrc = computed(() => spec.imgSrc)
const statusParts = computed(() => {
  const parts = [`ggplot2 ${meta.ggplot2Version}`]
  if (spec.composeActive) parts.push(`拼图 ${spec.spec.combine.slots.length} 图`)
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
const sizeLabel = computed(() => sizeMode.value === 'mm'
  ? `${renderMm.value.w}×${renderMm.value.h} mm · ${spec.renderOpts.dpi}dpi`
  : `${spec.renderOpts.width}×${spec.renderOpts.height} · ${spec.renderOpts.dpi}dpi`)
const sizeHint = computed(() => {
  const d = spec.renderOpts.dpi || 150
  const ed = exportOpts.value.dpi || 300
  const base = spec.spec.theme?.args?.base_size || 11
  return `预览 ${pxToMm(spec.renderOpts.width, d)}×${pxToMm(spec.renderOpts.height, d)} mm`
    + ` · 导出 ${pxToMm(exportOpts.value.width, ed)}×${pxToMm(exportOpts.value.height, ed)} mm`
    + `。字号按 pt 输出、与 dpi 无关；当前主题基础字号 ${base}pt。`
})

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
  renderMm.value[k] = v
  applyRenderMm()
}
function setRenderDpi(v) {
  spec.renderOpts.dpi = v
  if (sizeMode.value === 'mm') applyRenderMm()
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
})
function setJournal(id) {
  journalId.value = id || ''
  try { localStorage.setItem('ggplotgui-journal', journalId.value) } catch { /* 忽略 */ }
  if (checkVisible.value) runExportCheck(pendingFormat.value)
}

const checkIcon = (level) => ({
  pass: 'CircleCheck', warn: 'Warning', fail: 'CircleClose', info: 'InfoFilled'
}[level] || 'InfoFilled')

async function runExportCheck(format, { silentPass = false } = {}) {
  checking.value = true
  try {
    const res = await checkExport(spec.spec, { ...exportOpts.value, format, journal: journalId.value })
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

async function exportNow(format) {
  checkVisible.value = false
  exporting.value = true
  try {
    const { width, height, dpi } = exportOpts.value
    const { blob, filename } = await exportPlot(spec.spec, { width, height, dpi, format })
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

async function downloadCode() {
  let code = spec.last.code
  if (!code) {
    try { code = (await genCode(spec.spec)).code } catch { return }
  }
  const blob = new Blob([code], { type: 'text/plain;charset=utf-8' })
  downloadBlob(blob, 'ggplot-plot.R')
}

function pinCurrent() {
  if (!spec.spec.layers.length) return
  pins.saveCurrent().then((id) => {
    ElMessage.success(`已存入图库：${pins.byId[id]?.label || id}`)
  }).catch((e) => ElMessage.error(e.message))
}

// 窄窗口「更多」菜单：复用同一个动作入口
function onMoreCmd(cmd) {
  if (cmd === 'pin') pinCurrent()
  else if (cmd === 'plotly') showPlotly()
  else doExport(cmd)
}

function addFirstLayer() {
  spec.addLayer('point')
  if (!Object.keys(spec.spec.layers[0].aes || {}).length) spec.guessAes(spec.spec.layers[0])
}

async function showPlotly() {
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
</script>

<template>
  <div class="gg-canvas-head">
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
    <el-radio-group v-model="view" size="small">
      <el-radio-button value="plot">图表</el-radio-button>
      <el-radio-button value="code">代码</el-radio-button>
    </el-radio-group>
    <el-tooltip content="适合窗口 / 1:1">
      <el-button size="small" text @click="zoom100 = !zoom100">
        <el-icon><component :is="zoom100 ? 'FullScreen' : 'ScaleToOriginal'" /></el-icon>
      </el-button>
    </el-tooltip>

    <el-popover v-model:visible="sizePopover" placement="bottom-start" :width="310" trigger="click">
      <template #reference>
        <el-button size="small" text class="gg-mono size-btn" title="预览 / 导出尺寸">
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
          <el-input-number v-model="spec.renderOpts.width" :min="200" :max="4000" :step="20" size="small"
            controls-position="right" style="width:84px" />
          <span class="unit">×</span>
          <el-input-number v-model="spec.renderOpts.height" :min="150" :max="4000" :step="20" size="small"
            controls-position="right" style="width:84px" />
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
    <el-tooltip content="把当前图存入图库（用于拼图组合）">
      <el-button class="wide-only" size="small"
        :disabled="!spec.spec.layers.length || spec.composeActive || pins.saving"
        @click="pinCurrent">
        <el-icon><StarFilled /></el-icon><span class="btn-label">存入图库</span>
      </el-button>
    </el-tooltip>
    <el-button class="wide-only" size="small" :disabled="!spec.hasPlot" @click="showPlotly">
      <el-icon class="el-icon--left"><DataLine /></el-icon><span class="btn-label">交互预览</span>
    </el-button>
    <el-dropdown class="wide-only" split-button size="small" type="primary" title="导出 PNG"
      @click="doExport('png')" @command="doExport">
      <el-icon><Download /></el-icon><span class="btn-label">导出 PNG</span>
      <template #dropdown>
        <el-dropdown-menu>
          <el-dropdown-item command="png">PNG 位图</el-dropdown-item>
          <el-dropdown-item command="svg">SVG 矢量</el-dropdown-item>
          <el-dropdown-item command="pdf">PDF 矢量</el-dropdown-item>
          <el-dropdown-item command="check" divided>导出前检查…</el-dropdown-item>
        </el-dropdown-menu>
      </template>
    </el-dropdown>

    <!-- 窄窗口：次要动作收进「更多」 -->
    <el-dropdown class="narrow-only" trigger="click" @command="onMoreCmd">
      <el-button size="small"><el-icon><MoreFilled /></el-icon></el-button>
      <template #dropdown>
        <el-dropdown-menu>
          <el-dropdown-item command="pin" :disabled="!spec.spec.layers.length || spec.composeActive">
            存入图库
          </el-dropdown-item>
          <el-dropdown-item command="plotly" :disabled="!spec.hasPlot">交互预览</el-dropdown-item>
          <el-dropdown-item command="png" divided :disabled="!spec.hasPlot">导出 PNG</el-dropdown-item>
          <el-dropdown-item command="svg" :disabled="!spec.hasPlot">导出 SVG</el-dropdown-item>
          <el-dropdown-item command="pdf" :disabled="!spec.hasPlot">导出 PDF</el-dropdown-item>
          <el-dropdown-item command="check" divided :disabled="!spec.hasPlot">导出前检查…</el-dropdown-item>
        </el-dropdown-menu>
      </template>
    </el-dropdown>
  </div>

  <div v-show="view === 'plot'" class="gg-canvas-wrap">
    <img v-if="imgSrc && spec.hasContent" :src="imgSrc" class="gg-canvas-img" :class="{ zoom100 }" alt="plot" />
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

  <div v-if="view === 'plot' && spec.last.error && spec.hasContent" class="err-box">
    <el-alert type="error" :closable="false" show-icon>
      <template #title>渲染出错</template>
      <pre class="err-pre">{{ spec.last.error }}</pre>
    </el-alert>
  </div>

  <div v-if="view === 'plot' && spec.last.warnings.length && spec.hasContent" class="warn-box">
    <el-collapse>
      <el-collapse-item :title="`警告 (${spec.last.warnings.length})`">
        <div v-for="(w, i) in spec.last.warnings.slice(0, 8)" :key="i" class="warn-item">{{ w }}</div>
      </el-collapse-item>
    </el-collapse>
  </div>

  <div v-show="view === 'code'" class="gg-code-view gg-scroll">
    <div class="code-head">
      <span class="gg-hint-md">
        由当前绘图规格生成，可直接粘贴到 RStudio / Positron 运行
      </span>
      <span style="flex:1" />
      <el-button size="small" text @click="copyCode"><el-icon><CopyDocument /></el-icon> 复制</el-button>
      <el-button size="small" text @click="downloadCode"><el-icon><Download /></el-icon> 下载 .R</el-button>
    </div>
    <pre v-if="codeBlock" class="code-block gg-mono">{{ codeBlock }}</pre>
    <div v-else class="gg-empty-hint" style="padding:40px">暂无代码</div>
  </div>

  <div class="gg-status gg-mono" :title="statusParts">{{ statusParts }}</div>

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

  <el-dialog v-model="plotlyVisible" title="plotly 交互预览（部分 geom 不支持）" width="82%" destroy-on-close @opened="drawPlotly">
    <div v-loading="plotlyLoading" style="min-height:300px">
      <div ref="plotlyEl" />
    </div>
  </el-dialog>
</template>

<style scoped>
.gg-canvas-head {
  display: flex; align-items: center; gap: 6px; padding: 6px 12px;
  border-bottom: 1px solid var(--gg-border); background: var(--gg-panel); flex-shrink: 0;
  flex-wrap: nowrap; min-width: 0;
}
.render-spin { position: absolute; top: 56px; right: 22px; z-index: 5; }
.err-box { padding: 8px 14px; flex-shrink: 0; }
.err-pre { margin: 4px 0 0; white-space: pre-wrap; font-size: 12px; font-family: Consolas, monospace; max-height: 140px; overflow: auto; }
.warn-box { padding: 4px 14px 8px; flex-shrink: 0; }
.warn-item { font-size: 12px; color: var(--gg-text-3); padding: 1px 0; }
.gg-code-view { background: var(--gg-panel); flex: 1; min-height: 0; }
.gg-status {
  height: 26px; flex-shrink: 0; display: flex; align-items: center; gap: 8px;
  padding: 0 12px; border-top: 1px solid var(--gg-border); background: var(--gg-panel-2);
  font-size: 12px; color: var(--gg-text-3);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.gg-empty-hint .ghost { color: var(--gg-text-4); margin-bottom: 10px; }
.gg-empty-hint .t { font-size: 14px; font-weight: 600; color: var(--gg-text-2); margin-bottom: 12px; }
.gg-empty-hint .sub { margin-top: 10px; font-size: 12px; color: var(--gg-text-3); }

/* 尺寸设置 */
.size-mode { display: flex; align-items: center; gap: 8px; }
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
