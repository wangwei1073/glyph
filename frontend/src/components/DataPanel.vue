<script setup>
// 数据面板：数据源管理 / 列交互（快速映射·详情·插入表达式）/ 加工对话框 / 预览
import { ref, computed, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useDataStore } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import { setExprEl } from '../exprInsert'
import DataPreviewDialog from './DataPreviewDialog.vue'
import ColumnActions from './ColumnActions.vue'

const data = useDataStore()
const spec = useSpecStore()
const ui = useUiStore()

const pasteVisible = ref(false)
const pasteText = ref('')
const prepVisible = ref(false)     // 加工对话框
const uploading = ref(false)
const fileInput = ref(null)
const filterInput = ref(null)      // el-input 实例（含内部 textarea）
const mutateRefs = ref([])
const activeExpr = ref(null)       // 'filter' | {type:'mutate', idx}
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
function onSelect(key) {
  data.select(key)
  const src = data.current
  if (src) {
    spec.setSource(src.type === 'dataset' ? { type: 'dataset', name: src.name }
      : src.type === 'user' ? { type: 'user', id: src.name } : { type: 'none' })
  }
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
async function prepChanged() { await data.refreshPreview() }
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
const DOT = {
  numeric: '#2170b5', character: '#c07f18', factor: '#3e8929',
  logical: '#8d3fb0', date: '#c55a11', datetime: '#c55a11'
}
function dotFor(c) { return DOT[c.type] || '#888' }

// 列插入：共享模块（弹窗列菜单同样可用）
function insertName(name) {
  const r = insertExpr(name)
  if (!r.ok) ElMessage.info(r.msg)
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
    <div class="gg-panel-title">
      <el-icon><Coin /></el-icon>数据
      <span style="flex:1" />
      <el-button text size="small" class="collapse-btn" title="收起数据面板" @click="ui.toggleLeft()">
        <el-icon><ArrowLeft /></el-icon>
      </el-button>
    </div>

    <!-- 数据源 -->
    <div class="dp-srcrow">
      <el-dropdown trigger="click" @command="(c) => c === 'up' ? fileInput.click() : (pasteVisible = true)">
        <el-button size="small" :loading="uploading">
          <el-icon><Plus /></el-icon>添加数据
          <el-icon><ArrowDown /></el-icon>
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item command="up"><el-icon><UploadFilled /></el-icon>上传文件</el-dropdown-item>
            <el-dropdown-item command="paste"><el-icon><Document /></el-icon>粘贴数据</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
      <el-button size="small" :type="prepCount ? 'primary' : ''" plain @click="prepVisible = true">
        <el-icon><Filter /></el-icon>加工
        <span v-if="prepCount" class="prep-badge">{{ prepCount }}</span>
      </el-button>
      <el-button size="small" :disabled="!data.srcKey || data.srcKey === 'none'" @click="openPreview()">
        <el-icon><DataBoard /></el-icon>预览
        <span v-if="data.preview.nrow" class="pv-count">{{ data.preview.nrow }}×</span>
      </el-button>
      <el-popover v-if="userItems.length" v-model:visible="manageVisible" placement="bottom-start"
        :width="260" trigger="click">
        <template #reference>
          <el-button size="small" text :title="'管理我的数据'">
            <el-icon><MoreFilled /></el-icon>
          </el-button>
        </template>
        <div v-for="u in userItems" :key="u.id" class="pin-row">
          <span class="pin-badge gg-mono">{{ u.id }}</span>
          <span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;font-size:12px">
            {{ u.label }}（{{ u.nrow }}×{{ u.ncol }}）
          </span>
          <el-popconfirm :title="`删除 ${u.label}？`" width="190" @confirm="removeUser(u.id)">
            <template #reference>
              <el-button size="small" text type="danger"><el-icon><Delete /></el-icon></el-button>
            </template>
          </el-popconfirm>
        </div>
      </el-popover>
    </div>

    <div style="padding: 6px 10px 2px">
      <el-select :model-value="data.srcKey" class="src-select" filterable placeholder="选择数据源"
        style="width:100%" @change="onSelect">
        <el-option-group v-for="g in groupedSources" :key="g.label" :label="g.label">
          <el-option v-for="s in g.options" :key="`${s.type}:${s.name}`" :value="`${s.type}:${s.name}`"
            :label="`${s.label}（${s.nrow}×${s.ncol}）`" />
        </el-option-group>
      </el-select>
    </div>

    <!-- 列 -->
    <div class="dp-sechead" :class="{ fold: collapsed.cols }" @click="collapsed.cols = !collapsed.cols">
      <el-icon><component :is="collapsed.cols ? 'ArrowRight' : 'ArrowDown'" /></el-icon>
      列（{{ data.columns.length }}）
      <span style="font-weight:400;letter-spacing:0" v-if="data.preview.nrow">· 加工后 {{ data.preview.nrow }} 行</span>
      <span style="flex:1" />
      <el-input v-if="!collapsed.cols && data.columns.length > 8" v-model="q" size="small"
        placeholder="过滤列…" style="width:100px" @click.stop clearable>
        <template #prefix><el-icon><Search /></el-icon></template>
      </el-input>
      <el-button size="small" text title="重新加载列信息" @click.stop="data.refresh()">
        <el-icon><Refresh /></el-icon>
      </el-button>
    </div>
    <div v-if="!collapsed.cols" class="gg-scroll" style="flex:1; min-height:0">
      <div v-for="(c, i) in shownCols" :key="c.name" class="colitem">
        <div class="colrow" :class="{ open: expandedCol === c.name }"
          :title="`${c.name} · 单击展开映射与统计`" @click="toggleCol(c.name)">
          <el-icon class="col-caret"><component :is="expandedCol === c.name ? 'ArrowDown' : 'ArrowRight'" /></el-icon>
          <span class="dot" :style="{ background: dotFor(c) }" />
          <span class="colname">{{ c.name }}</span>
          <span class="coln">{{ c.nUnique }}</span>
          <el-button size="small" text class="col-open" title="在数据表格中查看此列"
            @click.stop="openPreview(c.name)">
            <el-icon><MoreFilled /></el-icon>
          </el-button>
        </div>
        <div v-if="expandedCol === c.name" class="col-expand">
          <ColumnActions :col="c" compact />
        </div>
      </div>
      <div v-if="!data.columns.length" style="padding:12px;color:var(--el-text-color-secondary);font-size:12px">
        尚未选择数据
      </div>
    </div>

    <input ref="fileInput" type="file" hidden accept=".csv,.tsv,.txt,.xlsx,.xls,.rds,.json,.rdata,.rda"
      @change="onFile" />

    <!-- 加工对话框 -->
    <el-dialog v-model="prepVisible" title="数据加工" width="640" append-to-body>
      <div class="gg-subhead" style="padding-top:0">行筛选（R 逻辑表达式；可点击下方列名插入）</div>
      <el-input ref="filterInput" v-model="spec.spec.data.filter" type="textarea" :rows="2" class="gg-mono"
        placeholder="如: hwy > 20 & class == 'suv'"
        @focus="activeExpr = 'filter'; setExprEl(filterInput)" @change="prepChanged" />

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
          @focus="activeExpr = { type: 'mutate', idx: i }; setExprEl(mutateRefs[i])" @change="prepChanged" />
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
        <el-button size="small" text @click="resetPrep"><el-icon><RefreshLeft /></el-icon>重置加工</el-button>
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

    <DataPreviewDialog v-model:visible="pvdVisible" :focus-col="pvdFocus" />
    <div v-if="dragging" class="drop-mask">
      <el-icon :size="42"><UploadFilled /></el-icon>
      <div>释放以载入数据文件</div>
    </div>
  </div>
</template>

<style scoped>
.dp-panel {
  display: flex; flex-direction: column; height: 100%; min-height: 0; overflow: hidden;
  position: relative;
}
.dp-panel.dragging { outline: 2px dashed var(--gg-accent); outline-offset: -6px; }
.dp-srcrow {
  display: flex; align-items: center; gap: 6px; padding: 8px 10px 0; flex-wrap: wrap;
}
.prep-badge {
  background: #fff; color: var(--gg-accent); border-radius: 999px;
  font-size: 11px; padding: 0 5px; margin-left: 5px; font-weight: 600;
}
.dp-sechead {
  display: flex; align-items: center; gap: 6px;
  padding: 9px 12px 4px; font-size: 12px; font-weight: 600;
  color: var(--el-text-color-secondary); flex-shrink: 0; cursor: pointer;
  user-select: none; letter-spacing: .4px;
}
.dp-sechead:not(.fold):hover { color: var(--el-text-color-primary); }
.pv-n { font-weight: 400; font-size: 11px; }
.colrow {
  display: flex; align-items: center; gap: 6px; padding: 3px 8px 3px 8px; font-size: 13px;
  cursor: pointer;
}
.colrow:hover { background: rgba(47, 111, 191,.07); }
.colrow.open { background: rgba(47, 111, 191,.10); }
.colrow.open .colname { font-weight: 600; color: var(--gg-accent); }
.col-caret { font-size: 11px; color: var(--el-text-color-placeholder); flex-shrink: 0; margin-right: -2px; }
.col-expand {
  padding: 6px 10px 8px 26px;
  background: rgba(47, 111, 191,.05);
  border-left: 2px solid var(--gg-accent);
  margin-bottom: 2px;
}
.dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
.colname { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }
.coln {
  margin-left: auto; font-size: 11px; color: var(--el-text-color-secondary);
  background: rgba(128,128,128,.10); border-radius: 8px; padding: 0 6px; line-height: 14px;
}
.col-open { padding: 2px; }
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
.pv-count {
  font-size: 11px; color: var(--el-text-color-secondary); margin-left: 4px;
}
.drop-mask {
  position: absolute; inset: 0; z-index: 20; display: flex; flex-direction: column;
  align-items: center; justify-content: center; gap: 8px;
  background: rgba(47, 111, 191,.14); backdrop-filter: blur(1px);
  color: var(--gg-accent); font-size: 13px; pointer-events: none;
}
</style>
