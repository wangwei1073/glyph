<script setup>
// 画布：图表预览 / 代码视图 / 渲染与导出设置 / 状态行
import { ref, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { useDataStore } from '../stores/data'
import { usePinStore } from '../stores/pins'
import { exportPlot, downloadBlob, genCode, getPlotly } from '../api'

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

async function doExport(format) {
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

    <el-popover v-model:visible="sizePopover" placement="bottom-start" :width="290" trigger="click">
      <template #reference>
        <el-button size="small" text class="gg-mono size-btn" title="预览 / 导出尺寸">
          <span class="size-text">{{ spec.renderOpts.width }}×{{ spec.renderOpts.height }} · {{ spec.renderOpts.dpi }}dpi</span>
        </el-button>
      </template>
      <div class="gg-subhead" style="padding:0 0 6px">预览尺寸</div>
      <div style="display:flex; gap:6px; align-items:center">
        <el-input-number v-model="spec.renderOpts.width" :min="200" :max="4000" :step="20" size="small" controls-position="right" style="width:88px" />
        <el-input-number v-model="spec.renderOpts.height" :min="150" :max="4000" :step="20" size="small" controls-position="right" style="width:88px" />
        <el-select v-model="spec.renderOpts.dpi" size="small" style="width:80px">
          <el-option v-for="d in [72, 96, 150, 200, 300]" :key="d" :value="d" :label="d + ' dpi'" />
        </el-select>
      </div>
      <div class="gg-subhead" style="padding:10px 0 6px">导出尺寸</div>
      <div style="display:flex; gap:6px; align-items:center">
        <el-input-number v-model="exportOpts.width" :min="200" :max="12000" :step="100" size="small" controls-position="right" style="width:88px" />
        <el-input-number v-model="exportOpts.height" :min="150" :max="12000" :step="100" size="small" controls-position="right" style="width:88px" />
        <el-select v-model="exportOpts.dpi" size="small" style="width:80px">
          <el-option v-for="d in [96, 150, 200, 300, 600]" :key="d" :value="d" :label="d + ' dpi'" />
        </el-select>
      </div>
      <div style="padding-top:8px;font-size:11px;color:var(--el-text-color-secondary)">
        导出按上述分辨率独立出图，与预览互不影响
      </div>
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
</style>
