<script setup>
// 数据面板：数据源管理 / 列交互（快速映射·详情·插入表达式）/ 加工对话框 / 预览
import { ref, computed, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useDataStore } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import { useMetaStore } from '../stores/meta'
import { getPrepSummary } from '../api'
import DataPreviewDialog from './DataPreviewDialog.vue'
import ColumnActions from './ColumnActions.vue'
import ActionBar from './ActionBar.vue'
import ImportDialog from './ImportDialog.vue'

const emit = defineEmits(['project'])   // 工具区的项目操作交给 App 处理

const data = useDataStore()
const spec = useSpecStore()
const ui = useUiStore()
const meta = useMetaStore()

const pasteVisible = ref(false)
const pasteText = ref('')
const importVisible = ref(false)
const prepVisible = ref(false)     // 加工对话框
const uploading = ref(false)
const fileInput = ref(null)
const filterInput = ref(null)      // el-input 实例（含内部 textarea）
const activeExpr = ref(null)       // 'filter' | {type:'mutate', idx}
watch(prepVisible, (v) => { if (!v) activeExpr.value = null })
const dragging = ref(false)
const pvdVisible = ref(false)
const pvdFocus = ref('')
const manageVisible = ref(false)   // 管理我的数据

// ---- 折叠状态（localStorage 记忆） ----
const KEY = 'ggplotgui-datafold'
const collapsed = ref({ cols: false, preview: false })
try { Object.assign(collapsed.value, JSON.parse(localStorage.getItem(KEY) || '{}')) } catch { /* */ }
watch(collapsed, (v) => { try { localStorage.setItem(KEY, JSON.stringify(v)) } catch { /* */ } }, { deep: true })

// ---- 数据源 ----
// 说明：数据源改成一个分组下拉后，这里的分组/排序就是唯一的展示顺序依据。
// 组顺序：我的数据 → 内置数据集。下拉打开时默认高亮第一项，用户数据在前，
//         回车选中的就是自己的数据集，不会误选内置数据。
// 组内顺序：我的数据按编号倒序 —— 刚导入的排最前（原先是 u1、u2… 插入顺序，
//         最新的沉在底部）。编号要按数值比，否则 u10 会排到 u9 前面。
function userSeq(s) {
  const m = String(s.name || '').match(/(\d+)\s*$/)
  return m ? Number(m[1]) : 0
}
async function onSelect(key) {
  await data.select(key)
  const src = data.current
  if (src) {
    spec.setSource(src.type === 'dataset' ? { type: 'dataset', name: src.name }
      : src.type === 'user' ? { type: 'user', id: src.name } : { type: 'none' })
  }
}

async function prepareSource(u) {
  await onSelect(`user:${u.name}`)
  prepVisible.value = true
}
async function onImported(src) {
  await data.load()
  if (src && src.id) onSelect(`user:${src.id}`)
  importVisible.value = false
  if (src) ElMessage.success(`已导入：${src.label}（${src.nrow}×${src.ncol}），可在「数据准备」中清洗与转换`)
}
// 多 sheet Excel：快速上传时后端返回 needSheet + sheets，弹窗选择后带 sheet 重新上传
const sheetDialog = ref(false)
const sheetList = ref([])
const sheetPick = ref('')
let pendingFile = null

async function onFile(e) {
  const f = e.target.files ? e.target.files[0] : e.dataTransfer ? e.dataTransfer.files[0] : null
  if (!f) return
  uploading.value = true
  try {
    const res = await data.upload(f)
    if (res && res.needSheet) {
      pendingFile = f
      sheetList.value = res.sheets || []
      sheetPick.value = sheetList.value[0] || ''
      sheetDialog.value = true
      return
    }
    ElMessage.success(`已载入 ${f.name}`)
  } catch (err) {
    ElMessage.error('载入失败: ' + err.message)
  } finally {
    uploading.value = false
    if (e.target && 'value' in e.target) e.target.value = ''
    dragging.value = false
  }
}

async function confirmSheet() {
  if (!pendingFile) { sheetDialog.value = false; return }
  const idx = sheetList.value.indexOf(sheetPick.value) + 1   // 后端 sheet 支持 1 起始下标
  sheetDialog.value = false
  uploading.value = true
  try {
    await data.upload(pendingFile, idx)
    ElMessage.success(`已载入 ${pendingFile.name}（工作表：${sheetPick.value}）`)
  } catch (err) {
    ElMessage.error('载入失败: ' + err.message)
  } finally {
    uploading.value = false
    pendingFile = null
  }
}

function cancelSheet() { pendingFile = null }
async function doPaste() {
  if (!pasteText.value.trim()) return
  try {
    await data.paste(pasteText.value)
    const src = data.current
    if (src) spec.setSource({ type: 'user', id: src.name })
    pasteVisible.value = false
    pasteText.value = ''
    ElMessage.success('粘贴数据已载入')
  } catch (err) {
    ElMessage.error('解析失败: ' + err.message)
  }
}
const userItems = computed(() => data.sources.filter(s => s.type === 'user'))
const datasetSources = computed(() => data.sources.filter(s => s.type === 'dataset'))
// 分组下拉的数据：我的数据在前（组内按编号倒序），内置数据集在后
const srcGroups = computed(() => {
  const us = userItems.value.slice().sort((a, b) => userSeq(b) - userSeq(a))
  const out = []
  if (us.length) out.push({ label: '我的数据', options: us })
  if (datasetSources.value.length) out.push({ label: '内置数据集', options: datasetSources.value })
  return out
})
// 下拉的绑定值：只在 user:/dataset: 两类里有对应选项；
// 未选数据时 srcKey 是 none:__none__，直接绑会显示成 "none" 这种原始值。
const srcValue = computed(() => /^(user|dataset):/.test(data.srcKey || '') ? data.srcKey : '')
const numericColumns = computed(() => data.columns.filter(c => c.type === 'num'))

function originLabel(s) {
  const o = s.origin || {}
  if (o.kind === 'db') return (o.driver ? o.driver : '数据库') + (o.table ? ` · ${o.table}` : '')
  if (o.kind === 'sqlite') return 'SQLite' + (o.table ? ` · ${o.table}` : '')
  if (o.kind === 'file') return '文件'
  if (o.kind === 'clip') return '剪贴板'
  return '数据'
}
function originIcon(s) {
  const k = s.origin?.kind
  if (k === 'db' || k === 'sqlite') return 'Coin'
  if (k === 'file') return 'Document'
  return 'DocumentCopy'
}
async function removeUser(id) {
  try {
    await data.remove(id)
    manageVisible.value = false
    ElMessage.success('已删除')
  } catch (e) {
    ElMessage.error(e.message)
  }
}

// ---- 数据准备 ----
const prepSummary = ref(null)
const prepSummaryLoading = ref(false)
let prepSummaryTimer = null

const prepCount = computed(() => {
  const sd = spec.spec.data
  let n = 0
  if (!sd.filterDisabled && (sd.filter || '').trim()) n++
  n += (sd.mutate || []).filter(m => !m.disabled && (m.name || '').trim() && (m.expr || '').trim()).length
  if (!sd.sampleDisabled && sd.sample) n++
  if (!sd.dropnaDisabled && (sd.dropnaCols || []).length) n++
  if (sd.dedupEnabled) n++
  n += (sd.types || []).filter(t => !t.disabled && t.name && t.type).length
  n += (sd.text || []).filter(t => !t.disabled && t.name && t.op).length
  n += (sd.outliers || []).filter(o => !o.disabled && o.name).length
  return n
})
function addFill() {
  if (!Array.isArray(spec.spec.data.fillna)) spec.spec.data.fillna = []
  spec.pushHistory()
  spec.spec.data.fillna.push({ name: '', method: 'constant', value: '', disabled: false })
}
function rmFill(i) {
  spec.pushHistory()
  spec.spec.data.fillna.splice(i, 1)
}
function addOutlier() {
  if (!Array.isArray(spec.spec.data.outliers)) spec.spec.data.outliers = []
  spec.pushHistory()
  spec.spec.data.outliers.push({ name: '', method: 'iqr', k: 1.5, action: 'flag', disabled: false })
}
function rmOutlier(i) {
  spec.pushHistory()
  spec.spec.data.outliers.splice(i, 1)
}
function addText() {
  if (!Array.isArray(spec.spec.data.text)) spec.spec.data.text = []
  spec.pushHistory()
  spec.spec.data.text.push({ name: '', op: 'trim', from: '', to: '', disabled: false })
}
function rmText(i) {
  spec.pushHistory()
  spec.spec.data.text.splice(i, 1)
}
function addType() {
  if (!Array.isArray(spec.spec.data.types)) spec.spec.data.types = []
  spec.pushHistory()
  spec.spec.data.types.push({ name: '', type: 'num', disabled: false })
}
function rmType(i) {
  spec.pushHistory()
  spec.spec.data.types.splice(i, 1)
}
function addMutate() {
  spec.pushHistory()
  spec.spec.data.mutate.push({ name: '', expr: '' })
}
function rmMutate(i) {
  spec.pushHistory()
  spec.spec.data.mutate.splice(i, 1)
}
async function prepChanged() { await data.refresh() }

async function loadPrepSummary() {
  const c = data.current
  if (!c || c.type === 'none') { prepSummary.value = null; return }
  const source = c.type === 'dataset'
    ? { type: 'dataset', name: c.name }
    : { type: 'user', id: c.name }
  const sd = spec.spec.data
  const prep = { filter: sd.filter || '', mutate: sd.mutate || [], sample: sd.sample, seed: sd.seed, filterDisabled: !!sd.filterDisabled, sampleDisabled: !!sd.sampleDisabled, types: sd.types || [], outliers: sd.outliers || [], fillna: sd.fillna || [], dropnaCols: sd.dropnaCols || [], dropnaHow: sd.dropnaHow || 'any', dropnaDisabled: !!sd.dropnaDisabled, dedupCols: sd.dedupCols || [], dedupEnabled: !!sd.dedupEnabled }
  prepSummaryLoading.value = true
  try {
    const res = await getPrepSummary(source, prep)
    prepSummary.value = res
  } catch { prepSummary.value = null } finally { prepSummaryLoading.value = false }
}

function schedulePrepSummary() {
  if (!prepVisible.value) return
  if (prepSummaryTimer) clearTimeout(prepSummaryTimer)
  prepSummaryTimer = setTimeout(loadPrepSummary, 300)
}

watch(prepVisible, (v) => { if (v) loadPrepSummary() })
watch(() => [spec.spec.data.filter, spec.spec.data.mutate,
             spec.spec.data.sample, spec.spec.data.seed,
             spec.spec.data.filterDisabled, spec.spec.data.sampleDisabled],
      schedulePrepSummary, { deep: true })

function prepStepLabel(s) {
  if (s.error) return `失败：${s.error}`
  if (s.type === 'type') return `类型 ${s.name}→${s.to}`
  if (s.type === 'text') return `文本 ${s.name}`
  if (s.type === 'fillna') return `填充 ${s.name} · ${s.filled} 个`
  if (s.type === 'outlier') return `异常值 ${s.name}${s.action === 'flag' ? ` · 标记 ${s.n}` : ''}`
  if (s.type === 'mutate') return `新增 ${s.name}`
  if (s.type === 'dropna') return `缺失值 −${s.removed} 行`
  if (s.type === 'dedup') return `去重 −${s.removed} 行`
  if (s.type === 'filter') return `筛选 −${s.removed} 行`
  if (s.type === 'sample') return `抽样 ${s.n} 行`
  return ''
}
function resetPrep() {
  spec.pushHistory()
  spec.spec.data.filter = ''
  spec.spec.data.filterDisabled = false
  spec.spec.data.types = []
  spec.spec.data.text = []
  spec.spec.data.outliers = []
  spec.spec.data.fillna = []
  spec.spec.data.dropnaCols = []
  spec.spec.data.dropnaDisabled = false
  spec.spec.data.dedupCols = []
  spec.spec.data.dedupEnabled = false
  spec.spec.data.mutate = []
  spec.spec.data.sample = null
  spec.spec.data.sampleDisabled = false
  spec.spec.data.seed = null
  prepChanged()
}
const columnOptions = computed(() => data.columns.map(c => ({
  value: c.name, label: c.name, type: c.type, nUnique: c.nUnique
})))

// ---- 列交互 ----
const q = ref('')
const expandedCol = ref('')   // 展开映射/统计的列名（点击列行切换）
function toggleCol(name) {
  expandedCol.value = expandedCol.value === name ? '' : name
}
const shownCols = computed(() => {
  const s = q.value.trim().toLowerCase()
  return s ? data.columns.filter(c => c.name.toLowerCase().includes(s)) : data.columns
})
const TYPE_ABBR = {
  numeric: 'num', character: 'chr', factor: 'fct',
  logical: 'lgl', date: 'date', datetime: 'dttm'
}
function typeAbbr(c) { return TYPE_ABBR[c.type] || String(c.type || '').slice(0, 3) }

// 列插入：共享模块（弹窗列菜单同样可用）
// 插入列名：直接写入当前聚焦的表达式（默认行筛选），不依赖 DOM 焦点
function insertName(name) {
  if (!prepVisible.value) {
    ElMessage.info('先打开「数据准备」对话框，再点击列名插入')
    return
  }
  const t = activeExpr.value
  if (t && typeof t === 'object' && t.type === 'mutate') {
    const m = spec.spec.data.mutate[t.idx]
    if (!m) return
    const cur = m.expr || ''
    m.expr = cur + (cur && !/\s$/.test(cur) ? ' ' : '') + name + ' '
  } else {
    const cur = spec.spec.data.filter || ''
    spec.spec.data.filter = cur + (cur && !/\s$/.test(cur) ? ' ' : '') + name + ' '
  }
  prepChanged()
}
function openPreview(colName = '') {
  pvdFocus.value = colName
  pvdVisible.value = true
}

</script>

<template>
  <div class="dp-panel" :class="{ dragging }"
    @dragover.prevent="dragging = true"
    @dragleave="dragging = false"
    @drop.prevent="onFile">
    <div class="dp-brand" :title="`ggplot2 ${meta.ggplot2Version}`">
      <b class="dp-brand-name">Glyph</b>
      <span class="dp-brand-sep" />
      <el-icon :size="13"><Coin /></el-icon><span class="dp-brand-sec">数据</span>
      <span style="flex:1" />
      <el-button text size="small" class="collapse-btn" title="收起数据面板" @click="ui.toggleLeft()">
        <el-icon><ArrowLeft /></el-icon>
      </el-button>
    </div>
    <!-- 数据源 -->
    <div class="dp-srcrow">
      <el-button size="small" type="primary" :loading="uploading" @click="importVisible = true">
        <el-icon><Plus /></el-icon>导入数据
      </el-button>
      <el-button size="small" @click="prepVisible = true">
        <el-icon><Filter /></el-icon>数据准备
        <span v-if="prepCount" class="prep-badge">{{ prepCount }}</span>
      </el-button>
      <el-button size="small" :disabled="!data.srcKey || data.srcKey === 'none'"
        :title="data.preview.nrow ? `预览数据（${data.preview.nrow} 行）` : '预览数据'"
        @click="openPreview()">
        <el-icon><DataBoard /></el-icon>预览
      </el-button>
    </div>

    <!-- 数据源：一个分组下拉管两组（我的数据 / 内置数据集）
         相比原先「两份标题 + 卡片 + 下拉」的纵向堆叠省约 96px，
         省出来的高度留给下面的「列」列表。 -->
    <div class="dp-src">
      <div class="dp-subhead">数据源</div>
      <el-select :model-value="srcValue" class="src-select" filterable
        placeholder="选择数据集" style="width:100%" @change="onSelect">
        <el-option-group v-for="g in srcGroups" :key="g.label" :label="g.label">
          <el-option v-for="s in g.options" :key="`${s.type}:${s.name}`"
            :value="`${s.type}:${s.name}`" :label="s.label">
            <div class="src-opt">
              <span class="so-ic"><el-icon><component :is="originIcon(s)" /></el-icon></span>
              <span class="so-name" :title="s.label">{{ s.label }}</span>
              <span class="so-meta">{{ s.nrow }}×{{ s.ncol }}</span>
              <span v-if="s.type === 'user'" class="so-acts">
                <el-tooltip content="数据准备：筛选 / 新增列 / 抽样" placement="top">
                  <el-button class="so-act" text size="small" @click.stop="prepareSource(s)">
                    <el-icon><Setting /></el-icon>
                  </el-button>
                </el-tooltip>
                <el-popconfirm :title="`删除 ${s.label}？`" width="190" @confirm="removeUser(s.name)">
                  <template #reference>
                    <el-button class="so-act" text size="small" type="danger" @click.stop>
                      <el-icon><Delete /></el-icon>
                    </el-button>
                  </template>
                </el-popconfirm>
              </span>
            </div>
          </el-option>
        </el-option-group>
      </el-select>
    </div>

    <!-- 列 -->
    <div class="dp-sechead" :class="{ fold: collapsed.cols }" @click="collapsed.cols = !collapsed.cols"
      :title="`处理后 ${data.preview.nrow || 0} 行 · ${data.columns.length} 列`">
      <el-icon><component :is="collapsed.cols ? 'ArrowRight' : 'ArrowDown'" /></el-icon>
      列（{{ data.columns.length }}）
      <span style="flex:1" />
      <el-input v-if="!collapsed.cols && data.columns.length > 8" v-model="q" size="small"
        class="dp-filter" placeholder="过滤" @click.stop clearable>
        <template #prefix><el-icon><Search /></el-icon></template>
      </el-input>
      <el-button size="small" text title="重新加载列信息" @click.stop="data.refresh()">
        <el-icon><Refresh /></el-icon>
      </el-button>
    </div>
    <div v-if="!collapsed.cols" class="gg-scroll" style="flex:1; min-height:0">
      <div v-for="(c, i) in shownCols" :key="c.name" class="colitem">
        <div class="colrow" :class="{ open: expandedCol === c.name }"
          :title="`${c.name}（${c.type}）· 单击展开映射与统计`" @click="toggleCol(c.name)">
          <el-icon class="col-caret"><component :is="expandedCol === c.name ? 'ArrowDown' : 'ArrowRight'" /></el-icon>
          <span class="col-type" :class="c.type">{{ typeAbbr(c) }}</span>
          <span class="colname">{{ c.name }}</span>
          <span class="coln" :title="`唯一值 ${c.nUnique}`">{{ c.nUnique }}</span>
          <el-button size="small" text class="col-open" title="在数据表格中查看此列"
            @click.stop="openPreview(c.name)">
            <el-icon><MoreFilled /></el-icon>
          </el-button>
        </div>
        <div v-if="expandedCol === c.name" class="col-expand">
          <ColumnActions :col="c" compact :insert="insertName" />
        </div>
      </div>
      <div v-if="!data.columns.length" style="padding:12px;color:var(--el-text-color-secondary);font-size:12px">
        尚未选择数据
      </div>
    </div>

    <input ref="fileInput" type="file" hidden accept=".csv,.tsv,.txt,.xlsx,.xls,.rds,.json,.rdata,.rda"
      @change="onFile" />

    <!-- 多 sheet Excel 的快速上传工作表选择 -->
    <el-dialog v-model="sheetDialog" title="选择 Excel 工作表" width="340px"
      :close-on-click-modal="false" @close="cancelSheet">
      <div style="font-size:12px;color:var(--el-text-color-secondary);margin-bottom:8px">
        该 Excel 包含 {{ sheetList.length }} 个工作表，选择要导入的一个：
      </div>
      <el-select v-model="sheetPick" size="small" style="width:100%">
        <el-option v-for="(s, i) in sheetList" :key="s" :value="s" :label="`${s}（第 ${i + 1} 个）`" />
      </el-select>
      <template #footer>
        <el-button size="small" @click="sheetDialog = false">取消</el-button>
        <el-button size="small" type="primary" :loading="uploading" @click="confirmSheet">导入</el-button>
      </template>
    </el-dialog>

    <!-- 底部工具区（原顶栏）：渲染 / 保存状态 / 项目 / 暗色 -->
    <ActionBar @project="(c) => emit('project', c)" />

    <!-- 加工对话框 -->
    <el-dialog v-model="prepVisible" title="数据准备" width="720" append-to-body class="prep-dialog">
      <div v-if="prepSummary" class="prep-summary">
        <span class="ps-raw">原始 {{ prepSummary.raw.nrow }}×{{ prepSummary.raw.ncol }}</span>
        <span class="ps-arrow">→</span>
        <span class="ps-final">当前 {{ prepSummary.final.nrow }}×{{ prepSummary.final.ncol }}</span>
        <span class="ps-note">原始数据不会被修改，可随时重置</span>
      </div>
      <div v-if="prepSummary && prepSummary.steps.length" class="prep-steps">
        <span v-for="(s, i) in prepSummary.steps" :key="i" class="pstep" :class="{ err: s.error }">
          {{ prepStepLabel(s) }}
        </span>
      </div>
      <el-collapse v-if="prepSummary && prepSummary.code" class="prep-code">
        <el-collapse-item title="查看数据准备代码（R）" name="code">
          <pre class="gg-mono">{{ prepSummary.code }}</pre>
        </el-collapse-item>
      </el-collapse>

      <div class="gg-subhead" style="padding-top:0">步骤（按执行顺序；可单独停用）</div>

      <!-- ① 新增列 -->
      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">1</span><span class="ps-title">类型转换</span>
          <span class="hint">先转换类型，再做筛选/派生</span>
        </div>
        <div v-for="(t, i) in spec.spec.data.types" :key="i" class="ps-line">
          <el-select v-model="t.name" size="small" filterable placeholder="选择列" style="flex:1;min-width:0"
            :disabled="!!t.disabled" @change="prepChanged">
            <el-option v-for="c in data.columns" :key="c.name" :value="c.name" :label="c.name" />
          </el-select>
          <el-select v-model="t.type" size="small" style="width:110px" :disabled="!!t.disabled"
            @change="prepChanged">
            <el-option value="num" label="数值 num" />
            <el-option value="chr" label="字符 chr" />
            <el-option value="fct" label="因子 fct" />
            <el-option value="lgl" label="逻辑 lgl" />
            <el-option value="date" label="日期 date" />
          </el-select>
          <el-button size="small" text type="danger" @click="() => { rmType(i); prepChanged() }">
            <el-icon><Delete /></el-icon>
          </el-button>
          <el-switch size="small" :model-value="!t.disabled" title="启用/停用此步"
            @update:model-value="(v) => { t.disabled = !v; prepChanged() }" />
        </div>
        <el-button size="small" text @click="addType"><el-icon><Plus /></el-icon>类型转换</el-button>
      </div>

      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">2</span><span class="ps-title">文本清洗</span>
          <span class="hint">去空格 / 大小写 / 替换</span>
        </div>
        <div v-for="(tx, i) in spec.spec.data.text" :key="i" class="ps-line">
          <el-select v-model="tx.name" size="small" filterable placeholder="选择列" style="flex:1;min-width:0"
            :disabled="!!tx.disabled" @change="prepChanged">
            <el-option v-for="c in data.columns" :key="c.name" :value="c.name" :label="c.name" />
          </el-select>
          <el-select v-model="tx.op" size="small" style="width:110px" :disabled="!!tx.disabled"
            @change="prepChanged">
            <el-option value="trim" label="去空格" />
            <el-option value="upper" label="转大写" />
            <el-option value="lower" label="转小写" />
            <el-option value="replace" label="替换" />
            <el-option value="split" label="拆分列" />
          </el-select>
          <template v-if="tx.op === 'replace'">
            <el-input v-model="tx.from" size="small" placeholder="查找" style="width:80px"
              :disabled="!!tx.disabled" @change="prepChanged" />
            <el-input v-model="tx.to" size="small" placeholder="替换为" style="width:80px"
              :disabled="!!tx.disabled" @change="prepChanged" />
          </template>
          <template v-else-if="tx.op === 'split'">
            <el-input v-model="tx.sep" size="small" placeholder="分隔符" style="width:70px"
              :disabled="!!tx.disabled" @change="prepChanged" />
            <el-input v-model="tx.into1" size="small" placeholder="新列1" style="width:90px"
              :disabled="!!tx.disabled" @change="prepChanged" />
            <el-input v-model="tx.into2" size="small" placeholder="新列2" style="width:90px"
              :disabled="!!tx.disabled" @change="prepChanged" />
          </template>
          <el-button size="small" text type="danger" @click="() => { rmText(i); prepChanged() }">
            <el-icon><Delete /></el-icon>
          </el-button>
          <el-switch size="small" :model-value="!tx.disabled" title="启用/停用此步"
            @update:model-value="(v) => { tx.disabled = !v; prepChanged() }" />
        </div>
        <el-button size="small" text @click="addText"><el-icon><Plus /></el-icon>文本清洗</el-button>
      </div>

      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">3</span><span class="ps-title">异常值</span>
          <span class="hint">IQR / z-score · 默认标记，不删数据</span>
        </div>
        <div v-for="(o, i) in spec.spec.data.outliers" :key="i" class="ps-line">
          <el-select v-model="o.name" size="small" filterable placeholder="数值列" style="flex:1;min-width:0"
            :disabled="!!o.disabled" @change="prepChanged">
            <el-option v-for="c in numericColumns" :key="c.name" :value="c.name" :label="c.name" />
          </el-select>
          <el-select v-model="o.method" size="small" style="width:100px" :disabled="!!o.disabled"
            @change="prepChanged">
            <el-option value="iqr" label="IQR" />
            <el-option value="z" label="z-score" />
          </el-select>
          <el-input-number v-model="o.k" :min="0.1" :step="0.5" size="small" style="width:90px"
            :disabled="!!o.disabled" @change="prepChanged" />
          <el-select v-model="o.action" size="small" style="width:96px" :disabled="!!o.disabled"
            @change="prepChanged">
            <el-option value="flag" label="标记" />
            <el-option value="drop" label="删除行" />
            <el-option value="winsor" label="缩尾" />
          </el-select>
          <el-button size="small" text type="danger" @click="() => { rmOutlier(i); prepChanged() }">
            <el-icon><Delete /></el-icon>
          </el-button>
          <el-switch size="small" :model-value="!o.disabled" title="启用/停用此步"
            @update:model-value="(v) => { o.disabled = !v; prepChanged() }" />
        </div>
        <el-button size="small" text @click="addOutlier"><el-icon><Plus /></el-icon>异常值</el-button>
      </div>

      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">4</span><span class="ps-title">新增列</span>
          <span class="hint">先执行，供筛选与绘图使用</span>
        </div>
        <div v-for="(m, i) in spec.spec.data.mutate" :key="i" class="ps-line">
          <el-input v-model="m.name" size="small" placeholder="列名" style="width:110px"
            :disabled="!!m.disabled" @change="prepChanged" />
          <el-input v-model="m.expr" size="small" class="gg-mono" placeholder="R 表达式，如 hwy / displ"
            style="flex:1;min-width:0" :disabled="!!m.disabled"
            @focus="activeExpr = { type: 'mutate', idx: i }" @change="prepChanged" />
          <el-button size="small" text type="danger" @click="() => { rmMutate(i); prepChanged() }">
            <el-icon><Delete /></el-icon>
          </el-button>
          <el-switch size="small" :model-value="!m.disabled" title="启用/停用此步"
            @update:model-value="(v) => { m.disabled = !v; prepChanged() }" />
        </div>
        <el-button size="small" text @click="addMutate"><el-icon><Plus /></el-icon>新增列</el-button>
      </div>

      <!-- ② 缺失值 -->
      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">5</span><span class="ps-title">缺失值</span>
          <span class="hint">按所选列删除缺失行</span>
          <span style="flex:1" />
          <el-switch size="small" :model-value="!spec.spec.data.dropnaDisabled"
            @update:model-value="(v) => { spec.spec.data.dropnaDisabled = !v; prepChanged() }" />
        </div>
        <div class="ps-line">
          <el-select v-model="spec.spec.data.dropnaCols" multiple collapse-tags size="small"
            placeholder="选择列（可多选）" style="flex:1" :disabled="!!spec.spec.data.dropnaDisabled">
            <el-option v-for="c in data.columns" :key="c.name" :value="c.name" :label="c.name" />
          </el-select>
          <el-select v-model="spec.spec.data.dropnaHow" size="small" style="width:110px"
            :disabled="!!spec.spec.data.dropnaDisabled">
            <el-option value="any" label="任一缺失" />
            <el-option value="all" label="全部缺失" />
          </el-select>
        </div>
      </div>

      <!-- ③ 行筛选 -->
      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">6</span><span class="ps-title">缺失值填充</span>
          <span class="hint">常数 / 均值 / 中位数 / 众数</span>
        </div>
        <div v-for="(f, i) in spec.spec.data.fillna" :key="i" class="ps-line">
          <el-select v-model="f.name" size="small" filterable placeholder="选择列" style="flex:1;min-width:0"
            :disabled="!!f.disabled" @change="prepChanged">
            <el-option v-for="c in data.columns" :key="c.name" :value="c.name" :label="c.name" />
          </el-select>
          <el-select v-model="f.method" size="small" style="width:110px" :disabled="!!f.disabled"
            @change="prepChanged">
            <el-option value="constant" label="常数" />
            <el-option value="mean" label="均值" />
            <el-option value="median" label="中位数" />
            <el-option value="mode" label="众数" />
          </el-select>
          <el-input v-if="f.method === 'constant'" v-model="f.value" size="small" placeholder="填充值"
            style="width:90px" :disabled="!!f.disabled" @change="prepChanged" />
          <el-button size="small" text type="danger" @click="() => { rmFill(i); prepChanged() }">
            <el-icon><Delete /></el-icon>
          </el-button>
          <el-switch size="small" :model-value="!f.disabled" title="启用/停用此步"
            @update:model-value="(v) => { f.disabled = !v; prepChanged() }" />
        </div>
        <el-button size="small" text @click="addFill"><el-icon><Plus /></el-icon>缺失值填充</el-button>
      </div>

      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">7</span><span class="ps-title">行筛选</span>
          <span class="hint">R 逻辑表达式；点击下方列名插入</span>
          <span style="flex:1" />
          <el-switch size="small" :model-value="!spec.spec.data.filterDisabled"
            @update:model-value="(v) => { spec.spec.data.filterDisabled = !v; prepChanged() }" />
        </div>
        <el-input ref="filterInput" v-model="spec.spec.data.filter" type="textarea" :rows="2" class="gg-mono"
          placeholder="如: hwy > 20 & class == 'suv'" :disabled="!!spec.spec.data.filterDisabled"
          @focus="activeExpr = 'filter'" @change="prepChanged" />
        <div class="chips">
          <el-tag v-for="c in data.columns" :key="c.name" class="col-chip" :disable-transitions="true"
            style="cursor:pointer" @click="insertName(c.name)">{{ c.name }}</el-tag>
        </div>
      </div>

      <!-- ④ 去重 -->
      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">8</span><span class="ps-title">去重</span>
          <span class="hint">按所选列去重；不选则按全部列</span>
          <span style="flex:1" />
          <el-switch size="small" :model-value="!!spec.spec.data.dedupEnabled"
            @update:model-value="(v) => { spec.spec.data.dedupEnabled = v; prepChanged() }" />
        </div>
        <div class="ps-line">
          <el-select v-model="spec.spec.data.dedupCols" multiple collapse-tags size="small"
            placeholder="全部列（默认）" style="flex:1" :disabled="!spec.spec.data.dedupEnabled">
            <el-option v-for="c in data.columns" :key="c.name" :value="c.name" :label="c.name" />
          </el-select>
        </div>
      </div>

      <!-- ⑤ 抽样 -->
      <div class="prep-step">
        <div class="ps-head">
          <span class="ps-idx">9</span><span class="ps-title">抽样</span>
          <span class="hint">按随机种子抽取固定行数</span>
          <span style="flex:1" />
          <el-switch size="small" :model-value="!spec.spec.data.sampleDisabled"
            @update:model-value="(v) => { spec.spec.data.sampleDisabled = !v; prepChanged() }" />
        </div>
        <div class="ps-line">
          <el-input-number v-model="spec.spec.data.sample" :min="1" size="small" placeholder="行数"
            :disabled="!!spec.spec.data.sampleDisabled" controls-position="right" style="width:130px" @change="prepChanged" />
          <span class="unit">行</span>
          <el-input-number v-model="spec.spec.data.seed" :min="0" size="small" placeholder="种子"
            :disabled="!!spec.spec.data.sampleDisabled" controls-position="right" style="width:130px" @change="prepChanged" />
          <span class="unit">种子</span>
          <span style="flex:1" />
          <el-button size="small" text @click="resetPrep"><el-icon><RefreshLeft /></el-icon>重置准备</el-button>
        </div>
      </div>

      <el-alert v-if="data.preview.error" type="error" :title="data.preview.error" :closable="false" style="margin-top:10px" />
      <template #footer>
        <el-button @click="prepVisible = false">关闭</el-button>
        <el-button type="primary" @click="() => { prepChanged(); prepVisible = false }">应用并刷新预览</el-button>
      </template>
    </el-dialog>

    <!-- 粘贴对话框 -->
    <el-dialog v-model="pasteVisible" title="粘贴表格数据（CSV / TSV）" width="560">
      <el-input v-model="pasteText" type="textarea" :rows="10" class="gg-mono"
        placeholder="a,b,c&#10;1,2,x&#10;3,4,y" />
      <template #footer>
        <el-button @click="pasteVisible = false">取消</el-button>
        <el-button type="primary" @click="doPaste">载入</el-button>
      </template>
    </el-dialog>

    <ImportDialog v-model="importVisible" @imported="onImported" />
    <DataPreviewDialog v-model:visible="pvdVisible" :focus-col="pvdFocus" />
    <div v-if="dragging" class="drop-mask">
      <el-icon :size="42"><UploadFilled /></el-icon>
      <div>释放以载入数据文件</div>
    </div>
  </div>
</template>

<style scoped>
/* 品牌条：原顶栏 logo 迁入左栏顶部（顶栏已移除）
   高度与画布工具栏（--gg-strip-h）对齐，两栏顶部齐平 */
/* 品牌条：原顶栏 logo 迁入左栏顶部（顶栏已移除）
   与画布工具栏（--gg-strip-h）同高同底色，两栏顶部完全齐平 */
.dp-brand {
  display: flex; align-items: center; gap: 7px; flex-shrink: 0;
  height: var(--gg-strip-h); padding: 0 10px;
  background: var(--gg-panel); color: var(--gg-text-1);
  border-bottom: 1px solid var(--gg-border);
}
.dp-brand b { font-size: 14px; letter-spacing: .2px; font-weight: 650; color: var(--gg-text-1); }

/* 品牌文字背景框：主题蓝底 + 白字，作为产品名的视觉锚点 */
.dp-brand-name {
  display: inline-flex; align-items: center; flex-shrink: 0;
  height: 22px; padding: 0 8px; border-radius: var(--gg-r-ctl);
  background: var(--gg-brand); color: #fff !important;
  line-height: 1; user-select: none;
}

.dp-brand-sep { width: 1px; height: 14px; background: var(--gg-border-strong); margin: 0 3px; }
.dp-brand-sec { font-size: 12.5px; color: var(--gg-text-2); }
.dp-brand .el-icon { color: var(--gg-text-3); }
.dp-brand .collapse-btn { color: var(--gg-text-4); height: 22px; }
.dp-brand .collapse-btn:hover { color: var(--gg-brand); }

.dp-panel {
  display: flex; flex-direction: column; height: 100%; min-height: 0; overflow: hidden;
  position: relative;
}
/* 底部工具条锚定在底部：列清单收起 / 无数据时不能被顶上来 */
.dp-panel :deep(.act-bar) { margin-top: auto; }
.dp-panel.dragging { outline: 2px dashed var(--gg-accent); outline-offset: -6px; }
.dp-srcrow {
  display: flex; align-items: center; gap: 6px; padding: 8px 10px 0; flex-wrap: nowrap;
}
.dp-srcrow > .el-button {
  flex: 1 1 0; min-width: 0; margin-left: 0 !important;
  padding-left: 4px; padding-right: 4px; justify-content: center;
}
.prep-badge {
  background: #fff; color: var(--gg-accent); border-radius: 999px;
  font-size: 11px; padding: 0 5px; margin-left: 5px; font-weight: 600;
}
/* 数据源：分组下拉（我的数据 / 内置数据集） */
.dp-src { padding: 6px 10px 4px; }
.dp-src .dp-subhead { margin-bottom: 5px; }

/* 下拉选项内部布局：图标 + 名称 + 维度 + 操作（仅我的数据） */
.src-opt { display: flex; align-items: center; gap: 7px; min-width: 0; }
.so-ic { display: flex; flex-shrink: 0; color: var(--gg-brand); }
.so-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.so-meta { flex-shrink: 0; font-size: 10.5px; color: var(--gg-text-4); }
.so-acts { display: flex; gap: 2px; flex-shrink: 0; opacity: 0; }
/* 悬停选项或已被选中时才露出操作按钮，避免下拉列表过于嘈杂 */
.el-select-dropdown__item:hover .so-acts,
.el-select-dropdown__item.is-selected .so-acts { opacity: 1; }
.so-act { padding: 0 4px; height: 20px; }


.prep-summary { display: flex; align-items: center; gap: 8px; font-size: 12px; margin-bottom: 6px; }
.ps-raw { color: var(--gg-text-3); }
.ps-arrow { color: var(--gg-text-4); }
.ps-final { color: var(--gg-brand); font-weight: 600; }
.ps-note { margin-left: auto; font-size: 11px; color: var(--gg-text-4); }
.prep-steps { display: flex; flex-wrap: wrap; gap: 4px; margin-bottom: 8px; }
.pstep { font-size: 11px; background: #eef2f7; color: var(--gg-text-2); border-radius: 3px; padding: 1px 6px; }
.pstep.err { background: #fdeceb; color: #c0392b; }
.prep-code { margin-bottom: 8px; }
.prep-code pre {
  margin: 0; background: #fbfcfe; border: 1px solid var(--gg-border); border-radius: 4px;
  padding: 6px 8px; font-size: 11.5px; color: var(--gg-text-2); white-space: pre-wrap;
}
.prep-step {
  border: 1px solid var(--gg-border); border-radius: 6px; padding: 8px 10px;
  margin-bottom: 8px; background: #fcfdff;
}
.ps-head { display: flex; align-items: center; gap: 8px; margin-bottom: 6px; }
.ps-idx {
  width: 18px; height: 18px; border-radius: 50%; background: var(--gg-brand-2, #eaf1fb);
  color: var(--gg-brand); font-size: 11px; display: flex; align-items: center;
  justify-content: center; font-weight: 600; flex-shrink: 0;
}
.ps-title { font-size: 12.5px; font-weight: 600; }
.ps-line { display: flex; align-items: center; gap: 6px; margin-bottom: 5px; flex-wrap: wrap; }
.ps-line .el-input, .ps-line .el-select { min-width: 0; }
.prep-dialog .el-dialog__body { max-height: 64vh; overflow-y: auto; scrollbar-width: none; -ms-overflow-style: none; }
.prep-dialog .el-dialog__body::-webkit-scrollbar { width: 0; height: 0; display: none; }
.ps-line:last-child { margin-bottom: 0; }
.ps-line .el-input { flex-shrink: 0; }
.chips { display: flex; gap: 5px; flex-wrap: wrap; margin-top: 6px; }
.unit { font-size: 12px; color: var(--gg-text-3); }
.dp-sechead {
  display: flex; align-items: center; gap: 6px;
  padding: 10px 12px 6px; font-size: 12px; font-weight: 600;
  color: var(--gg-text-3); flex-shrink: 0; cursor: pointer;
  user-select: none; letter-spacing: .2px;
}
.dp-sechead:not(.fold):hover { color: var(--gg-text-1); }
.dp-filter { width: 96px; flex-shrink: 0; }
.dp-filter :deep(.el-input__wrapper) { padding-left: 6px; }
.pv-n { font-weight: 400; font-size: 11px; }
.colrow {
  display: flex; align-items: center; gap: 6px; padding: 2px 8px 2px 6px;
  min-height: 28px; font-size: 13px; cursor: pointer; border-radius: 6px;
  margin: 0 4px;
}
.colrow:hover { background: rgba(47, 111, 191, .07); }
.colrow.open { background: rgba(47, 111, 191, .08); }
.colrow.open .colname { font-weight: 600; color: var(--gg-brand); }
.col-caret { font-size: 11px; color: var(--gg-text-4); flex-shrink: 0; }
.col-expand {
  margin: 2px 6px 8px 24px; padding: 9px 10px 10px;
  background: var(--gg-panel-2); border: 1px solid var(--gg-border);
  border-left: 2px solid var(--gg-brand);
  border-radius: 8px;
}
.col-type {
  flex-shrink: 0; width: 30px; text-align: center; letter-spacing: 0;
  font-weight: 500; text-transform: lowercase;
}
.colname { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
.coln {
  margin-left: auto; font-size: 11px; color: var(--gg-text-4);
  font-variant-numeric: tabular-nums;
}
.col-open { padding: 2px; opacity: 0; transition: opacity .12s; }
.colrow:hover .col-open, .colrow.open .col-open, .col-open:focus-visible { opacity: 1; }
.coldetail { font-size: 12px; }
.cd-stat { color: var(--el-text-color-secondary); font-size: 12px; padding: 4px 0; }
.cd-prev { display: flex; gap: 5px; flex-wrap: wrap; }
.cd-prev code {
  background: rgba(128,128,128,.08); border-radius: 4px; padding: 1px 5px;
  font-size: 11px; max-width: 90px; overflow: hidden; text-overflow: ellipsis;
  white-space: nowrap;
}
.coldot {
  font-size: 11px; color: #fff; border-radius: 4px; padding: 0 5px;
  line-height: 14px;
}
.col-chip { cursor: pointer; }
.col-chip:hover { border-color: var(--gg-accent); color: var(--gg-accent); }
.gg-pvwrap { flex: 1; min-height: 90px; }
.pv-table { border-collapse: collapse; font-size: 12px; width: 100%; }
.pv-table th {
  position: sticky; top: 0; background: var(--gg-panel);
  text-align: left; padding: 3px 8px; border-bottom: 1px solid var(--gg-border);
  font-weight: 600; white-space: nowrap;
}
.pv-table td {
  padding: 2.5px 8px; border-bottom: 1px solid var(--gg-border);
  white-space: nowrap; max-width: 110px; overflow: hidden; text-overflow: ellipsis;
}
.pin-row { display: flex; align-items: center; gap: 7px; padding: 4px 6px; }
.pin-badge {
  font-size: 11px; background: rgba(47, 111, 191,.12); color: var(--gg-accent);
  border-radius: 4px; padding: 1px 5px;
}
.drop-mask {
  position: absolute; inset: 0; z-index: 20; display: flex; flex-direction: column;
  align-items: center; justify-content: center; gap: 8px;
  background: rgba(47, 111, 191,.14); backdrop-filter: blur(1px);
  color: var(--gg-accent); font-size: 13px; pointer-events: none;
}
</style>

<style>
.prep-dialog .el-dialog__body { max-height: 64vh; overflow-y: auto; scrollbar-width: none; -ms-overflow-style: none; }
.prep-dialog .el-dialog__body::-webkit-scrollbar { width: 0; height: 0; display: none; }
</style>
