<script setup>
// 数据面板：数据源管理 / 列交互（快速映射·详情·插入表达式）/ 加工对话框 / 预览
import { ref, computed, watch, nextTick } from 'vue'
import { ElMessage } from 'element-plus'
import { useDataStore } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import { useMetaStore } from '../stores/meta'
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
const mutateRefs = ref([])
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
const groupedSources = computed(() => {
  const ds = data.sources.filter(s => s.type === 'dataset')
  const us = data.sources.filter(s => s.type === 'user')
  const out = [{ label: '内置数据集', options: ds }]
  if (us.length) out.push({ label: '我的数据', options: us })
  return out.filter(g => g.options.length)
})
async function onSelect(key) {
  await data.select(key)
  nextTick(() => {
    const el = srcCardsEl.value?.querySelector('.src-card.on')
    if (el && el.scrollIntoView) el.scrollIntoView({ block: 'nearest' })
  })
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
async function onFile(e) {
  const f = e.target.files ? e.target.files[0] : e.dataTransfer ? e.dataTransfer.files[0] : null
  if (!f) return
  uploading.value = true
  try {
    await data.upload(f)
    const src = data.current
    if (src) spec.setSource({ type: 'user', id: src.name })
    ElMessage.success(`已载入 ${f.name}`)
  } catch (err) {
    ElMessage.error('载入失败: ' + err.message)
  } finally {
    uploading.value = false
    if (e.target && 'value' in e.target) e.target.value = ''
    dragging.value = false
  }
}
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
const datasetKey = computed(() => (data.srcKey || '').startsWith('dataset:') ? data.srcKey : '')
const srcCardsEl = ref(null)

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

// ---- 加工 ----
const prepCount = computed(() => {
  let n = 0
  if ((spec.spec.data.filter || '').trim()) n++
  n += (spec.spec.data.mutate || []).filter(m => (m.name || '').trim() && (m.expr || '').trim()).length
  if (spec.spec.data.sample) n++
  return n
})
function addMutate() {
  spec.pushHistory()
  spec.spec.data.mutate.push({ name: '', expr: '' })
}
function rmMutate(i) {
  spec.pushHistory()
  spec.spec.data.mutate.splice(i, 1)
}
async function prepChanged() { await data.refresh() }
function resetPrep() {
  spec.pushHistory()
  spec.spec.data.filter = ''
  spec.spec.data.mutate = []
  spec.spec.data.sample = null
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

    <!-- 我的数据：卡片列表，点击切换活动数据集 -->
    <div v-if="userItems.length" ref="srcCardsEl" class="dp-src-cards">
      <div class="dp-subhead">我的数据</div>
      <div v-for="u in userItems" :key="u.id" class="src-card"
        :class="{ on: data.srcKey === `user:${u.name}` }" @click="onSelect(`user:${u.name}`)">
        <span class="sc-ic"><el-icon><component :is="originIcon(u)" /></el-icon></span>
        <span class="sc-main">
          <span class="sc-name">{{ u.label }}</span>
          <span class="sc-meta">{{ originLabel(u) }} · {{ u.nrow }}×{{ u.ncol }}</span>
        </span>
        <el-tooltip content="数据准备：筛选 / 新增列 / 抽样" placement="top">
          <el-button class="sc-act" text size="small" @click.stop="prepareSource(u)">
            <el-icon><Setting /></el-icon>
          </el-button>
        </el-tooltip>
        <el-popconfirm :title="`删除 ${u.label}？`" width="190" @confirm="removeUser(u.name)">
          <template #reference>
            <el-button class="sc-del" text size="small" type="danger" @click.stop>
              <el-icon><Delete /></el-icon>
            </el-button>
          </template>
        </el-popconfirm>
      </div>
    </div>

    <div style="padding: 6px 10px 2px">
      <div class="dp-subhead" style="padding-left:0">内置数据集</div>
      <el-select :model-value="datasetKey" class="src-select" filterable placeholder="选择内置数据集"
        style="width:100%" @change="onSelect">
        <el-option v-for="s in datasetSources" :key="`dataset:${s.name}`" :value="`dataset:${s.name}`"
          :label="`${s.label}（${s.nrow}×${s.ncol}）`" />
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

    <!-- 底部工具区（原顶栏）：渲染 / 保存状态 / 项目 / 暗色 -->
    <ActionBar @project="(c) => emit('project', c)" />

    <!-- 加工对话框 -->
    <el-dialog v-model="prepVisible" title="数据准备" width="640" append-to-body>
      <div class="gg-subhead" style="padding-top:0">行筛选（R 逻辑表达式；可点击下方列名插入）</div>
      <el-input ref="filterInput" v-model="spec.spec.data.filter" type="textarea" :rows="2" class="gg-mono"
        placeholder="如: hwy > 20 & class == 'suv'"
        @focus="activeExpr = 'filter'" @change="prepChanged" />

      <div class="gg-subhead">常用列（点击插入）</div>
      <div style="display:flex;gap:6px;flex-wrap:wrap">
        <el-tag v-for="c in data.columns" :key="c.name" class="col-chip" :disable-transitions="true"
          style="cursor:pointer" @click="insertName(c.name)">{{ c.name }}</el-tag>
      </div>

      <div class="gg-subhead">新增列</div>
      <div v-for="(m, i) in spec.spec.data.mutate" :key="i" style="display:flex;gap:5px;margin:0 0 5px">
        <el-input v-model="m.name" size="small" placeholder="列名" style="width:120px" @change="prepChanged" />
        <el-input :ref="(el) => { mutateRefs[i] = el; }" v-model="m.expr" size="small" class="gg-mono"
          placeholder="R 表达式，如 hwy / displ"
          @focus="activeExpr = { type: 'mutate', idx: i }" @change="prepChanged" />
        <el-button size="small" text type="danger" @click="() => { rmMutate(i); prepChanged() }">
          <el-icon><Delete /></el-icon>
        </el-button>
      </div>
      <el-button size="small" text @click="addMutate"><el-icon><Plus /></el-icon>新增列</el-button>

      <div class="gg-subhead">抽样 / 随机种子</div>
      <div style="display:flex;gap:8px;align-items:center">
        <el-input-number v-model="spec.spec.data.sample" :min="1" size="small" placeholder="行数"
          controls-position="right" style="width:130px" @change="prepChanged" />
        <span style="font-size:12px;color:var(--el-text-color-secondary)">行</span>
        <el-input-number v-model="spec.spec.data.seed" :min="0" size="small" placeholder="种子"
          controls-position="right" style="width:130px" @change="prepChanged" />
        <span style="font-size:12px;color:var(--el-text-color-secondary)">种子</span>
        <span style="flex:1" />
        <el-button size="small" text @click="resetPrep"><el-icon><RefreshLeft /></el-icon>重置准备</el-button>
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
.dp-src-cards {
  padding: 6px 10px 2px; display: flex; flex-direction: column; gap: 4px;
  max-height: 220px; overflow: auto;
}
.src-card {
  display: flex; align-items: center; gap: 8px; border: 1px solid var(--gg-border);
  border-radius: 6px; padding: 6px 8px; cursor: pointer; background: #fff;
}
.src-card:hover { border-color: var(--gg-brand); }
.src-card.on { border-color: var(--gg-brand); background: var(--gg-brand-2, #eaf1fb); }
.sc-ic { color: var(--gg-brand); display: flex; flex-shrink: 0; }
.sc-main { display: flex; flex-direction: column; min-width: 0; flex: 1; }
.sc-name { font-size: 12.5px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.sc-meta { font-size: 10.5px; color: var(--gg-text-4); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.sc-del, .sc-act { opacity: 0; flex-shrink: 0; }
.src-card:hover .sc-del, .src-card.on .sc-del,
.src-card:hover .sc-act, .src-card.on .sc-act { opacity: 1; }

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
