<script setup>
// 数据统计抽屉（壳）：抽屉外观/页签/摘要徽标 + 各页签共享的列状态与 refreshColumns。
// 轻拆结构：六个页签各有子组件（同目录 StatsXxxTab.vue），私有状态随子组件走；
// 跨页签共享的输入/结果经 defineModel 双向绑定留在本壳。
// —— L1/L2/L4/L5 的执行函数与 L3 的标注状态已随子组件迁移，壳只保留共享部分。
import { computed, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useDataStore, buildPrep } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import { statsColumns, statsSuggest, statsAgg, statsPaired } from '../api'
import { suggestCharts } from '../chartSuggest'
import { num, pval } from '../statsShared'
import StatsDescTab from './StatsDescTab.vue'
import StatsTestTab from './StatsTestTab.vue'
import StatsMarkTab from './StatsMarkTab.vue'
import StatsRegTab from './StatsRegTab.vue'
import StatsTable1Tab from './StatsTable1Tab.vue'
import StatsIdeaTab from './StatsIdeaTab.vue'

const data = useDataStore()
const spec = useSpecStore()
const ui = useUiStore()

// ---- 共享：列状态（refreshColumns 填充，各页签消费）----
const loading = ref(false)
const error = ref('')               // 列加载等共用错误
const numericCols = ref([])
const groupCols = ref([])
const catCols = ref([])
const methods = ref([])             // statsSuggest 的可选检验方法（L2 用）

const tab = ref('desc')
const hasSource = computed(() => !!data.current && data.current.type !== 'none')
const prep = computed(() => buildPrep(spec.spec.data || {}))
const source = computed(() => {
  const c = data.current
  if (!c || c.type === 'none') return { type: 'none' }
  return c.type === 'dataset' ? { type: 'dataset', name: c.name } : { type: 'user', id: c.name }
})

// ---- L1 描述统计（共享：变量选择 + 结果；执行在 StatsDescTab）----
const vars = ref([])
const groupBy = ref([])
const descResult = ref(null)

// ---- L2 统计检验（共享：变量/方法 + 结果；执行在 StatsTestTab）----
const testMethod = ref('')
const testY = ref('')
const testX = ref('')
const testGroup = ref('')
const testResult = ref(null)

// ---- L4 回归分析（共享：模型/变量 + 结果；执行在 StatsRegTab）----
const regMethod = ref('lm')
const regY = ref('')
const regXs = ref([])
const regResult = ref(null)

// ---- L5 基线表（共享：选项 + 结果；执行在 StatsTable1Tab）----
const t1Vars = ref([])
const t1By = ref('')
const t1Stat = ref('mean_sd')
const t1AddP = ref(true)
const t1Overall = ref(false)
const t1Digits = ref(2)
const t1Result = ref(null)

// ---- 列探测（打开抽屉或数据/加工变化时刷新各页签的列清单）----
async function refreshColumns() {
  if (!hasSource.value) {
    numericCols.value = []; groupCols.value = []; catCols.value = []
    vars.value = []; groupBy.value = []; methods.value = []
    descResult.value = null; testResult.value = null
    return
  }
  loading.value = true
  error.value = ''
  try {
    const [cols, sug] = await Promise.all([
      statsColumns(source.value, prep.value),
      statsSuggest(source.value, prep.value).catch(() => ({ methods: [], roles: {} }))
    ])
    numericCols.value = cols.numeric || []
    groupCols.value = cols.groupable || []
    catCols.value = (sug.roles && sug.roles.categorical) || []
    methods.value = sug.methods || []

    vars.value = vars.value.filter(v => numericCols.value.includes(v))
    groupBy.value = groupBy.value.filter(v => groupCols.value.includes(v))
    if (!vars.value.length && numericCols.value.length) vars.value = [numericCols.value[0]]

    // 检验变量槽位：失效则清空
    if (testY.value && !numericCols.value.includes(testY.value) && !catCols.value.includes(testY.value)) testY.value = ''
    if (testX.value && !numericCols.value.includes(testX.value)) testX.value = ''
    if (testGroup.value && !groupCols.value.includes(testGroup.value)) testGroup.value = ''
    if (!testY.value && numericCols.value.length) testY.value = numericCols.value[0]
    if (!testGroup.value && groupCols.value.length) testGroup.value = groupCols.value[0]
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

let timer = null
// 只在抽屉打开时才请求：此前 immediate:true 让「从未打开过的抽屉」也在开机与每次映射
// 变化时打后端。key 用整个 prep 序列化，覆盖 types/text/outliers/fillna/dropna/dedup
// （旧 key 漏了这些字段，做过相应加工后统计列会停留在旧状态）
watch(() => `${data.srcKey}|${JSON.stringify(prep.value)}`,
  () => {
    if (!ui.statsOpen) return
    clearTimeout(timer); timer = setTimeout(refreshColumns, 400)
  },
  { immediate: true })

// 抽屉打开那一刻也要加载一次（watcher 平时被 statsOpen 挡住）
watch(() => ui.statsOpen, (v) => { if (v) refreshColumns() })

// ---- 一键误差条图层 ----
// 描述统计结果 → 后端聚合成 均值±CI 长表（注册为用户数据集）→ 画布生成 柱+误差条 图层组
const aggLoading = ref(false)
async function makeErrorbar() {
  if (!descResult.value?.summary?.length) return
  aggLoading.value = true
  try {
    const res = await statsAgg(source.value, prep.value, vars.value, groupBy.value, 'ci95')
    if (!res.ok) throw new Error(res.error || '聚合失败')
    // 多变量时柱与误差条都按 variable 着色并 dodge 对齐；单变量直接居中
    const layersPos = res.nVars > 1
      ? { type: 'dodge', params: {} } : { type: '', params: {} }
    // 柱层：均值；多变量按 variable 着色，单变量分组时按组着色
    spec.addLayer('col')
    const i = spec.spec.layers.length - 1
    spec.spec.layers[i].aes = { x: { map: res.xSuggest }, y: { map: 'mean' }, fill: { map: res.fillSuggest } }
    spec.spec.layers[i].position = { ...layersPos }
    // 误差条层：CI 上下界；多变量时 group=variable 保证与柱对齐 dodge
    spec.addLayer('errorbar')
    const j = spec.spec.layers.length - 1
    const errAes = { x: { map: res.xSuggest }, ymin: { map: 'lower' }, ymax: { map: 'upper' } }
    if (res.nVars > 1) errAes.group = { map: 'variable' }
    spec.spec.layers[j].aes = errAes
    spec.spec.layers[j].position = { ...layersPos }
    // 两层的数据源切换为聚合数据集；列面板同步到聚合列
    spec.setSource({ type: 'user', id: res.id })
    await data.select(`user:${res.id}`)
    spec.renderNow()
    ElMessage.success(`已生成误差条图层（均值 ${res.errLabel}，数据集「${res.info?.label || res.id}」）`)
  } catch (e) {
    ElMessage.error('生成误差条图层失败: ' + e.message)
  } finally {
    aggLoading.value = false
  }
}

// ---- 一键配对线图层 ----
// 配对检验的两列按行位置转长表（id/variable/value）→ 画布生成 配线+散点 图层组
const pairedLoading = ref(false)
async function makePairedLines() {
  if (!testMethod.value || !testResult.value) return
  pairedLoading.value = true
  try {
    const res = await statsPaired(source.value, prep.value, testY.value, testGroup.value)
    if (!res.ok) throw new Error(res.error || '生成失败')
    // 配线层：同一 id 连成一条灰线（个体轨迹）
    spec.addLayer('line')
    const i = spec.spec.layers.length - 1
    spec.spec.layers[i].aes = { x: { map: 'variable' }, y: { map: 'value' }, group: { map: 'id' } }
    spec.spec.layers[i].aesParams = { colour: 'grey55', linewidth: 0.7 }
    // 散点层：按前后着色
    spec.addLayer('point')
    const j = spec.spec.layers.length - 1
    spec.spec.layers[j].aes = { x: { map: 'variable' }, y: { map: 'value' }, colour: { map: 'variable' } }
    spec.setSource({ type: 'user', id: res.id })
    await data.select(`user:${res.id}`)   // 列面板同步到配对长表列
    spec.renderNow()
    ElMessage.success(`已生成配对线图层（${res.n} 对，${res.level1} → ${res.level2}）`)
  } catch (e) {
    ElMessage.error('生成配对线图层失败: ' + e.message)
  } finally {
    pairedLoading.value = false
  }
}

// ---- 图表建议 ----
// 依据「列画像 + 已有统计结果」推导候选图；统计结果越完整，建议越贴合
const chartIdeas = computed(() => suggestCharts(data.columns, {
  summary: descResult.value,
  testRes: testResult.value,
  regRes: regResult.value
}))

function applyIdea(idea) {
  if (!data.columns.length) { ElMessage.warning('先选择数据源'); return }
  // 防护：拟合/平滑层要求 x 连续，分类 x 上 geom_smooth 会静默画不出线
  if (idea.addLayer && idea.addLayer.geom === 'smooth') {
    const xName = idea.aes?.x?.map
    const xCol = data.columns.find(c => c.name === xName)
    const isDiscrete = !xCol || ['character', 'factor', 'logical', 'date', 'datetime'].includes(xCol.type) ||
      (xCol.type === 'numeric' && (xCol.nUnique ?? 99) <= 8)
    if (isDiscrete) {
      ElMessage.warning(`「${xName}」不是连续变量，无法叠加拟合线；已仅添加散点`)
      idea = { ...idea, addLayer: null }
    }
  }
  spec.addLayer(idea.geom || 'point')
  const i = spec.spec.layers.length - 1
  // 覆盖 guessAes 推测的映射
  spec.spec.layers[i].aes = JSON.parse(JSON.stringify(idea.aes || {}))
  if (idea.stat) spec.spec.layers[i].stat = idea.stat
  if (idea.position) spec.spec.layers[i].position = JSON.parse(JSON.stringify(idea.position))
  // 需要叠加图层（拟合线）时一并加上
  if (idea.addLayer) {
    spec.addLayer(idea.addLayer.geom)
    const j = spec.spec.layers.length - 1
    spec.spec.layers[j].aes = JSON.parse(JSON.stringify(idea.addLayer.aes || {}))
    if (idea.addLayer.params) spec.spec.layers[j].params = { ...idea.addLayer.params }
  }
  // 有分类 fill 映射时挂上默认 Prism 配色，否则箱线图是空心黑白的
  if (idea.aes?.fill?.map) {
    spec.syncDefaultPalette('fill')
    spec.syncDefaultPalette('colour')
  }
  spec.renderNow()
  ElMessage.success(`已应用：${idea.title}`)
}

// ---- 顶栏摘要徽标：优先显示「当前页签」的结果，没有结果时不显示 ----
const sigClass = computed(() => {
  const p = testResult.value?.p
  if (p === null || p === undefined || Number.isNaN(p)) return ''
  return Number(p) < 0.05 ? 'sig' : 'ns'
})
const summaryBadge = computed(() => {
  const t = tab.value
  if (t === 'test') {
    if (!testResult.value) return null
    const p = testResult.value.p
    return {
      text: `${testResult.value.methodLabel} · p = ${pval(p)}`,
      cls: sigClass.value
    }
  }
  if (t === 'desc') {
    if (!descResult.value?.summary?.length) return null
    return { text: `描述统计 · ${descResult.value.summary.length} 行`, cls: '' }
  }
  if (t === 'reg') {
    const r = regResult.value
    if (!r) return null
    const fit = r.method === 'lm' ? `R² = ${num(r.fitStats?.r2)}`
      : (r.method === 'corr' ? `${r.coefs?.length ?? 0} 对相关` : `AIC = ${num(r.fitStats?.aic)}`)
    return { text: `${r.methodLabel} · ${fit}`, cls: '' }
  }
  if (t === 'table1') {
    if (!t1Result.value) return null
    return { text: `基线表 · ${t1Result.value.vars?.length ?? 0} 变量`, cls: '' }
  }
  if (t === 'mark') {
    const n = (spec.spec.sigMarks || []).length
    return n ? { text: `${n} 个标注`, cls: '' } : null
  }
  if (t === 'idea') {
    const n = chartIdeas.value.length
    return n ? { text: `${n} 条建议`, cls: '' } : null
  }
  return null
})

// ---- 抽屉高度拖拽 ----
const resizing = ref(false)
let dragStartY = 0
let dragStartH = 0

function startResize(e) {
  resizing.value = true
  dragStartY = e.clientY
  dragStartH = ui.statsHeight
  window.addEventListener('mousemove', onResizing)
  window.addEventListener('mouseup', stopResize)
  // 拖拽时禁用文本选择，避免选中页面内容
  document.body.style.userSelect = 'none'
  document.body.style.cursor = 'ns-resize'
}
function onResizing(e) {
  if (!resizing.value) return
  // 向上拖 → 变高；因此用起始高度减去位移
  const next = dragStartH - (e.clientY - dragStartY)
  ui.setStatsHeight(next)
}
function stopResize() {
  resizing.value = false
  window.removeEventListener('mousemove', onResizing)
  window.removeEventListener('mouseup', stopResize)
  document.body.style.userSelect = ''
  document.body.style.cursor = ''
}
</script>
<template>
  <div class="stats-drawer" :class="{ open: ui.statsOpen }"
    :style="ui.statsOpen ? { height: ui.statsHeight + 'px' } : null">
    <!-- 顶部拖拽条：上下拖动调整抽屉高度 -->
    <div v-if="ui.statsOpen" class="sd-resizer" :class="{ active: resizing }"
      title="拖动调整高度" @mousedown.prevent="startResize">
      <span class="sd-bar" />
    </div>

    <!-- 标题栏：折叠 + 页签 + 结果摘要 -->
    <div class="sd-head">
      <span class="sd-collapse" @click="ui.toggleStats()">
        <el-icon :size="13"><component :is="ui.statsOpen ? 'ArrowDown' : 'ArrowRight'" /></el-icon>
        <span class="sd-title">数据统计</span>
      </span>

      <template v-if="ui.statsOpen">
        <el-radio-group v-model="tab" size="small" class="sd-tabs">
          <el-radio-button value="desc">描述统计</el-radio-button>
          <el-radio-button value="test">统计检验</el-radio-button>
          <el-radio-button value="reg">回归分析</el-radio-button>
          <el-radio-button value="idea">图表建议</el-radio-button>
          <el-radio-button value="mark">图上标注</el-radio-button>
          <el-radio-button value="table1">基线表</el-radio-button>
        </el-radio-group>
      </template>

      <span v-if="summaryBadge" class="sd-badge" :class="summaryBadge.cls">
        {{ summaryBadge.text }}
      </span>

      <span style="flex:1" />
      <span class="sd-toggle" @click="ui.toggleStats()">{{ ui.statsOpen ? '收起' : '展开' }}</span>
    </div>

    <div v-if="ui.statsOpen" class="sd-body">
      <div v-if="!hasSource" class="gg-empty-hint" style="padding:30px">
        <el-icon class="big"><Coin /></el-icon>
        <div>先在左侧选择数据源</div>
      </div>

      <template v-else>
        <StatsDescTab v-show="tab === 'desc'"
          v-model:vars="vars" v-model:group-by="groupBy" v-model:result="descResult"
          :numeric-cols="numericCols" :group-cols="groupCols"
          :source="source" :prep="prep" :has-source="hasSource"
          :loading="loading" :agg-loading="aggLoading" :err="error"
          @refresh="refreshColumns" @agg="makeErrorbar" />

        <StatsTestTab v-show="tab === 'test'"
          v-model:test-method="testMethod" v-model:test-y="testY"
          v-model:test-x="testX" v-model:test-group="testGroup" v-model:result="testResult"
          :methods="methods" :numeric-cols="numericCols" :group-cols="groupCols"
          :source="source" :prep="prep" :has-source="hasSource"
          :paired-loading="pairedLoading" :err="error" @paired="makePairedLines" />

        <StatsRegTab v-show="tab === 'reg'"
          v-model:reg-method="regMethod" v-model:reg-y="regY" v-model:reg-xs="regXs"
          v-model:result="regResult"
          :active="tab === 'reg'" :source="source" :prep="prep"
          :has-source="hasSource" :err="error" />

        <StatsIdeaTab v-show="tab === 'idea'"
          :ideas="chartIdeas" :has-desc="!!descResult" :has-test="!!testResult"
          :has-reg="!!regResult" @apply="applyIdea" />

        <StatsMarkTab v-show="tab === 'mark'"
          :active="tab === 'mark'" :test-result="testResult" />

        <StatsTable1Tab v-show="tab === 'table1'"
          v-model:t1-vars="t1Vars" v-model:t1-by="t1By" v-model:t1-stat="t1Stat"
          v-model:t1-add-p="t1AddP" v-model:t1-overall="t1Overall" v-model:t1-digits="t1Digits"
          v-model:result="t1Result"
          :active="tab === 'table1'" :source="source" :prep="prep"
          :has-source="hasSource" :err="error" />
      </template>
    </div>
  </div>
</template>

<!--
  样式说明：本块不再是 scoped。轻拆后 .sd-* / .stat-table 等类分布在壳与六个子组件里，
  父组件的 scoped 属性不会加到子组件 DOM 上；所有规则统一加 .stats-drawer 前缀限定作用域，
  类名在全局均以 sd-/sp-/stat-/res-/test-/reg-/idea-/aes-chip/mk-/tm-/rf-/tg 等命名，无冲突。
-->
<style>
.stats-drawer {
  flex-shrink: 0; display: flex; flex-direction: column;
  border-top: 1px solid var(--gg-border);
  background: var(--gg-panel); min-height: 0;
}
.stats-drawer.open { height: 304px; }

/* 拖拽条：视觉上是一条细线，热区 8px */
.stats-drawer .sd-resizer {
  height: 8px; flex-shrink: 0; cursor: ns-resize;
  display: flex; align-items: center; justify-content: center;
  margin-top: -4px; position: relative; z-index: 2;
}
.stats-drawer .sd-bar {
  width: 46px; height: 3px; border-radius: 2px;
  background: rgba(128, 128, 128, .3); transition: background .12s, width .12s;
}
.stats-drawer .sd-resizer:hover .sd-bar, .stats-drawer .sd-resizer.active .sd-bar {
  background: var(--gg-accent); width: 64px;
}

.stats-drawer .sd-head {
  display: flex; align-items: center; gap: 10px; flex-shrink: 0;
  padding: 4px 10px; border-bottom: 1px solid var(--gg-border);
  font-size: 12px;
}
.stats-drawer .sd-collapse {
  display: flex; align-items: center; gap: 6px;
  cursor: pointer; user-select: none; padding: 2px 4px; border-radius: 4px;
}
.stats-drawer .sd-collapse:hover { background: rgba(74, 144, 217, .08); }
.stats-drawer .sd-title { font-weight: 600; }
.stats-drawer .sd-tabs .el-radio-button__inner { padding: 4px 12px; font-size: 11.5px; }
.stats-drawer .sd-toggle { font-size: 11px; color: var(--el-text-color-secondary); }
.stats-drawer .sd-toggle { cursor: pointer; }
.stats-drawer .sd-toggle:hover { color: var(--gg-accent); }
.stats-drawer .sd-badge {
  font-size: 10.5px; padding: 1px 7px; border-radius: 9px;
  background: rgba(128, 128, 128, .12); color: var(--el-text-color-secondary);
  font-variant-numeric: tabular-nums; white-space: nowrap;
}
.stats-drawer .sd-badge.sig { background: rgba(84, 178, 142, .16); color: #2f8b68; }

/* ---------- 内容区：左参数 + 右结果 ---------- */
.stats-drawer .sd-body { flex: 1; min-height: 0; display: flex; }
.stats-drawer .sd-pane { flex: 1; min-width: 0; display: flex; }

.stats-drawer .sd-params {
  width: 264px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;
  padding: 10px 12px; border-right: 1px solid var(--gg-border);
  overflow-y: auto;
}
.stats-drawer .sp-field { display: flex; flex-direction: column; gap: 3px; }
.stats-drawer .sp-field > label { font-size: 11px; color: var(--el-text-color-secondary); }
.stats-drawer .sp-actions { display: flex; align-items: center; gap: 6px; padding-top: 2px; }
.stats-drawer .sp-hint {
  font-size: 10.5px; line-height: 1.5; color: var(--el-text-color-secondary);
  padding-top: 2px;
}
.stats-drawer .sp-hint.warn { color: #c07f18; }

.stats-drawer .sd-result {
  flex: 1; min-width: 0; display: flex; flex-direction: column;
  padding: 8px 12px 10px; overflow: hidden;
}
.stats-drawer .res-head {
  display: flex; align-items: center; gap: 6px; flex-shrink: 0;
  padding-bottom: 5px; font-size: 11px; color: var(--el-text-color-secondary);
}
.stats-drawer .res-table-wrap {
  flex: 1; min-height: 0; border: 1px solid var(--gg-border); border-radius: 6px;
}
.stats-drawer .res-code { flex-shrink: 0; margin-top: 6px; }
.stats-drawer .res-code-head {
  display: flex; align-items: center; gap: 4px; flex-shrink: 0;
  font-size: 11px; color: var(--el-text-color-secondary);
}

/* ---------- 表格 ---------- */
.stats-drawer .stat-table { border-collapse: collapse; width: 100%; font-size: 11.5px; }
.stats-drawer .stat-table th {
  position: sticky; top: 0; z-index: 1; background: var(--gg-panel);
  text-align: left; font-weight: 600; white-space: nowrap;
  padding: 4px 8px; border-bottom: 1px solid var(--gg-border);
}
.stats-drawer .stat-table td {
  padding: 2px 8px; border-bottom: 1px solid var(--gg-border);
  white-space: nowrap; max-width: 140px; overflow: hidden; text-overflow: ellipsis;
}
.stats-drawer .stat-table .n { text-align: right; font-variant-numeric: tabular-nums; }
.stats-drawer .stat-table tbody tr:hover td { background: rgba(74, 144, 217, .06); }
.stats-drawer .stat-table tbody tr.total td { background: rgba(74, 144, 217, .09); font-weight: 600; }

/* ---------- 代码块 ---------- */
.stats-drawer .code-pre {
  margin: 4px 0 0; padding: 8px; max-height: 150px; overflow: auto;
  background: rgba(128, 128, 128, .08); border-radius: 6px;
  font-size: 11px; line-height: 1.45; white-space: pre-wrap; word-break: break-all;
}

/* ---------- 检验结果卡片 ---------- */
.stats-drawer .test-card {
  flex: 1; min-height: 0; overflow-y: auto;
  padding: 9px 11px; border: 1px solid var(--gg-border);
  border-left-width: 3px; border-radius: 6px; background: var(--gg-panel);
}
.stats-drawer .test-card.sig { border-left-color: #54b28e; }
.stats-drawer .test-card.ns { border-left-color: #b0b8c0; }
.stats-drawer .test-title { display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 600; }
.stats-drawer .test-metrics {
  display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 4px 16px; margin-top: 7px;
}
.stats-drawer .tm { display: flex; align-items: baseline; gap: 6px; font-size: 11.5px; }
.stats-drawer .tm-l { color: var(--el-text-color-secondary); min-width: 46px; flex-shrink: 0; }
.stats-drawer .tm-v { font-variant-numeric: tabular-nums; }
.stats-drawer .stars { color: #e8734a; font-weight: 700; margin-left: 3px; }
.stats-drawer .test-groups { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 7px; }
.stats-drawer .tg {
  font-size: 10.5px; padding: 1px 6px; border-radius: 8px;
  background: rgba(128, 128, 128, .1); color: var(--el-text-color-secondary);
}
.stats-drawer .test-notes { margin-top: 7px; padding-top: 6px; border-top: 1px dashed var(--gg-border); }
.stats-drawer .note-line { font-size: 10.5px; line-height: 1.55; color: var(--el-text-color-secondary); }
.stats-drawer .opt-row { display: flex; justify-content: space-between; gap: 14px; align-items: center; }
.stats-drawer .opt-fn { font-size: 10.5px; color: var(--el-text-color-secondary); }

/* ---------- 图上标注 ---------- */
.stats-drawer .mark-list { flex: 1; min-height: 0; }
.stats-drawer .mark-row {
  display: flex; align-items: center; gap: 6px;
  padding: 3px 4px; border-bottom: 1px solid var(--gg-border);
}
.stats-drawer .mk-g { font-size: 11.5px; max-width: 78px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.stats-drawer .mk-vs { font-size: 10.5px; color: var(--el-text-color-secondary); }
.stats-drawer .mk-label { width: 92px; }
.stats-drawer .mk-y { width: 74px; }
.stats-drawer .res-note {
  flex-shrink: 0; padding-top: 6px; font-size: 10.5px; line-height: 1.5;
  color: var(--el-text-color-secondary);
}

/* ---------- 回归 ---------- */
.stats-drawer .reg-fit {
  display: flex; align-items: center; gap: 14px; flex-wrap: wrap; flex-shrink: 0;
  padding: 0 0 6px; font-size: 11.5px;
}
.stats-drawer .rf-item { color: var(--el-text-color-secondary); font-variant-numeric: tabular-nums; }
.stats-drawer .rf-item b { color: var(--el-text-color-primary); font-weight: 600; margin-right: 3px; }
.stats-drawer .reg-notes {
  flex-shrink: 0; max-height: 62px; overflow-y: auto;
  padding: 5px 0 2px; border-top: 1px dashed var(--gg-border); margin-top: 5px;
}

/* ---------- 图表建议 ---------- */
.stats-drawer .idea-tags { display: flex; gap: 4px; flex-wrap: wrap; }
.stats-drawer .idea-list { flex: 1; min-height: 0; }
.stats-drawer .idea-card {
  display: flex; align-items: flex-start; gap: 8px;
  padding: 7px 8px; border-bottom: 1px solid var(--gg-border);
}
.stats-drawer .idea-card:hover { background: rgba(74, 144, 217, .05); }
.stats-drawer .idea-rank {
  width: 18px; height: 18px; border-radius: 50%; flex-shrink: 0;
  background: rgba(74, 144, 217, .14); color: var(--gg-accent);
  font-size: 10.5px; font-weight: 600;
  display: flex; align-items: center; justify-content: center; margin-top: 1px;
}
.stats-drawer .idea-main { flex: 1; min-width: 0; }
.stats-drawer .idea-title { font-size: 12.5px; font-weight: 600; display: flex; align-items: center; gap: 6px; }
.stats-drawer .idea-geom { font-family: Consolas, monospace; font-size: 10px; }
.stats-drawer .idea-reason {
  font-size: 11px; line-height: 1.5; margin-top: 3px;
  color: var(--el-text-color-secondary);
}
.stats-drawer .idea-extra { font-size: 10.5px; margin-top: 3px; color: #c07f18; }
.stats-drawer .idea-aes {
  display: flex; flex-wrap: wrap; align-items: center; gap: 4px; margin-top: 4px;
}
.stats-drawer .aes-chip {
  display: inline-flex; align-items: center; gap: 2px;
  padding: 0 5px; height: 17px; border-radius: 3px;
  background: rgba(74, 144, 217, .1); color: var(--gg-accent);
  font-size: 10px; line-height: 17px; white-space: nowrap;
}
.stats-drawer .aes-chip b { font-weight: 600; }
.stats-drawer .aes-chip .aes-eq { opacity: .5; }
.stats-drawer .aes-chip.stat { background: rgba(232, 115, 74, .12); color: #c0552f; }
.stats-drawer .aes-chip.layer { background: rgba(84, 178, 142, .14); color: #2f8b68; }
.stats-drawer .aes-plus { font-size: 10px; color: var(--el-text-color-placeholder); }
</style>
