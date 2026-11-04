<script setup>
// 数据预览与列操作弹窗：服务端分页 + 排序 + 表头列菜单（映射/插入表达式/统计）+ CSV 导出
import { ref, computed, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useDataStore } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import { previewData, exportPreparedCSV, editAdd, editUndo } from '../api'
import ColumnActions from './ColumnActions.vue'

const props = defineProps({
  visible: Boolean,
  focusCol: { type: String, default: '' }   // 打开时定位/高亮的列
})
const emit = defineEmits(['update:visible'])

const data = useDataStore()
const spec = useSpecStore()

const rows = ref([])
const cols = ref([])
const total = ref(0)
const page = ref(1)
const pageSize = ref(50)
const sortCol = ref('')
const sortAsc = ref(true)
const loading = ref(false)
const exporting = ref(false)
const editMode = ref(false)
const rowIds = ref([])
const editCount = ref(0)
const editing = ref(null)
const undoing = ref(false)
const scheduleTimer = ref(null)
const cellErr = ref('')
const menuVis = ref({})          // 列头菜单开合（隐藏时关掉别的）
const currSrcName = ref('')

const dotBase = {
  numeric: '#2170b5', character: '#c07f18', factor: '#3e8929',
  logical: '#8d3fb0', date: '#c55a11', datetime: '#c55a11'
}
const total_pages = computed(() => Math.max(1, Math.ceil(total.value / pageSize.value)))
const prepChips = computed(() => {
  const chips = []
  if ((spec.spec.data.filter || '').trim()) chips.push('筛选')
  const nm = (spec.spec.data.mutate || []).filter(m => (m.name || '').trim()).length
  if (nm) chips.push(`新增列 ${nm}`)
  if (spec.spec.data.sample) chips.push(`抽样 ${spec.spec.data.sample}`)
  return chips
})

async function load() {
  const cur = data.current
  if (!cur || cur.type === 'none') { rows.value = []; cols.value = []; total.value = 0; return }
  loading.value = true
  try {
    const src = cur.type === 'dataset' ? { type: 'dataset', name: cur.name } : { type: 'user', id: cur.name }
    const d = await previewData(src, {
      filter: spec.spec.data.filter || '', mutate: spec.spec.data.mutate || [],
      sample: spec.spec.data.sample, seed: spec.spec.data.seed
    }, { start: (page.value - 1) * pageSize.value + 1, length: pageSize.value,
         sortCol: sortCol.value || null, asc: sortAsc.value })
    rows.value = d.rows || []
    cols.value = d.columns || []
    total.value = d.nrow || 0
    rowIds.value = d.rowIds || []
    editCount.value = await fetchEditCount()
  } catch (e) {
    ElMessage.error('预览加载失败: ' + e.message)
  } finally {
    loading.value = false
  }
}

// 编辑操作的存储键与后端 .keyof 保持一致："dataset:mpg" / "user:u1"
function editKey() {
  const c = data.current
  return c && c.type !== 'none' ? `${c.type}:${c.name}` : ''
}
async function fetchEditCount() {
  const k = editKey()
  if (!k) return 0
  try {
    const r = await fetch('/api/edits?key=' + encodeURIComponent(k))
    if (!r.ok) return 0
    const j = await r.json()
    return j.count || 0
  } catch { return 0 }
}

function setSort(colName) {
  if (sortCol.value === colName) {
    if (!sortAsc.value) { sortCol.value = ''; sortAsc.value = true }  // 第三次取消排序
    else sortAsc.value = false
  } else {
    sortCol.value = colName; sortAsc.value = true
  }
  page.value = 1
  load()
}

const cur = computed(() => data.current)
const title = computed(() => {
  const c = cur.value
  const label = c ? (c.label || c.name) : ''
  return `${label}（加工后 ${total.value} 行 × ${cols.value.length} 列）`
})

function dotFor(c) { return dotBase[c.type] || '#888' }
function fmt(v) {
  if (v === null || v === undefined) return ''
  if (typeof v === 'number') return Number.isInteger(v) ? v : String(+v.toFixed(4))
  return String(v)
}

const srcObj = computed(() => {
  const c = cur.value
  if (!c || c.type === 'none') return { type: 'none' }
  return c.type === 'dataset' ? { type: 'dataset', name: c.name } : { type: 'user', id: c.name }
})
const prepObj = computed(() => ({
  filter: spec.spec.data.filter || '', mutate: spec.spec.data.mutate || [],
  sample: spec.spec.data.sample, seed: spec.spec.data.seed
}))

function scheduleRender() {
  clearTimeout(scheduleTimer.value)
  scheduleTimer.value = setTimeout(() => spec.renderNow(), 550)
}
async function commitOp(op) {
  cellErr.value = ''
  try {
    await editAdd(srcObj.value, prepObj.value, op)
    load()
    scheduleRender()
    return true
  } catch (e) {
    cellErr.value = e.message
    ElMessage.error('编辑被拒绝: ' + e.message)
    return false
  }
}

function startEdit(ri, ci, curVal, colName) {
  if (!editMode.value) return
  const c = cols.value[ci]
  editing.value = { ri, ci, value: fmt(curVal), col: colName, type: c.type }
}
function cancelEdit() { editing.value = null }
async function commitEdit() {
  const ed = editing.value
  if (!ed) return
  let raw = ed.value
  let ok = true
  if (ed.type === 'numeric') {
    if (raw.trim() === '' || /^na$/i.test(raw.trim())) raw = null
    else if (isNaN(Number(raw))) { ok = false; cellErr.value = '值 ' + raw + ' 不是数字' }
    else raw = Number(raw)
  } else if (ed.type === 'logical') {
    if (/^(true|false)$/i.test(raw.trim())) raw = /^true$/i.test(raw.trim())
    else if (raw.trim() === '' || /^na$/i.test(raw.trim())) raw = null
    else { ok = false; cellErr.value = '逻辑列只能填 TRUE / FALSE / NA' }
  }
  if (ok) {
    const rid = rowIds.value[ed.ri]
    const done = await commitOp({ kind: 'cell', rid, col: ed.col, value: raw === undefined ? null : raw })
    if (done) editing.value = null
  }
}
function keydownCell(e) {
  if (e.key === 'Enter') { e.preventDefault(); commitEdit() }
  if (e.key === 'Escape') cancelEdit()
}
async function deleteRow(rid) {
  const done = await commitOp({ kind: 'rowDel', rid })
  if (done) ElMessage.success('行已删除')
}
async function addRow() {
  const values = {}
  for (const c of cols.value) values[c.name] = null
  const done = await commitOp({ kind: 'rowIns', values })
  if (done) {
    await load(); page.value = total_pages.value
    ElMessage.success('已添加行')
  }
}
async function renameCol(colName) {
  let r
  try {
    r = await ElMessageBox.prompt('将列 ' + colName + ' 改名为：', '列改名', {
      inputValue: colName, inputPattern: /^[A-Za-z][A-Za-z0-9._]*$/,
      inputErrorMessage: '以字母开头，可含字母/数字/点/下划线'
    })
  } catch { return }  // 用户取消
  menuVis.value = {}
  const to = (r.value || '').trim()
  if (!to || to === colName) return
  const done = await commitOp({ kind: 'colRen', from: colName, to })
  if (done) ElMessage.success('已改名')
}
async function deleteCol(colName) {
  const done = await commitOp({ kind: 'colDel', col: colName })
  if (done) ElMessage.success('列已删除')
}
async function undoLast() {
  cellErr.value = ''
  try {
    const res = await editUndo(srcObj.value)
    if (res.ok) {
      await load()
      scheduleRender()
      editCount.value = await fetchEditCount()
    }
  } catch (e) { ElMessage.error(e.message) }
}

async function doExport() {
  const c = cur.value
  if (!c || c.type === 'none') return
  exporting.value = true
  try {
    const src = c.type === 'dataset' ? { type: 'dataset', name: c.name } : { type: 'user', id: c.name }
    const { blob, filename } = await exportPreparedCSV(src, {
      filter: spec.spec.data.filter || '', mutate: spec.spec.data.mutate || [],
      sample: spec.spec.data.sample, seed: spec.spec.data.seed
    })
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = filename
    a.click()
    setTimeout(() => URL.revokeObjectURL(a.href), 4000)
    ElMessage.success(`已导出 ${filename}`)
  } catch (e) {
    ElMessage.error('导出失败: ' + e.message)
  } finally {
    exporting.value = false
  }
}

watch(() => props.visible, (v) => {
  if (v) {
    page.value = 1
    if (props.focusCol && data.columns.some(c => c.name === props.focusCol)) {
      sortCol.value = ''; sortAsc.value = true
      // 定位列：不排序而是记住，渲染后高亮滚动
      setTimeout(scrollFocus, 400)
    }
    load()
  }
})
watch([page, pageSize], load)
watch(() => `${data.srcKey}|${spec.spec.data.filter}|${spec.spec.data.sample}|${(spec.spec.data.mutate || []).map(m => m.expr).join('|')}`,
  (nv, ov) => { if (props.visible && nv !== ov) { page.value = 1; load() } })

function scrollFocus() {
  if (!props.focusCol) return
  setTimeout(() => {
    const th = document.querySelector(`.pvd-table th[data-col="${props.focusCol}"]`)
    if (th) th.scrollIntoView({ behavior: 'smooth', block: 'nearest', inline: 'center' })
    const menuBtn = document.querySelector(`.pvd-table th[data-col="${props.focusCol}"] .pvd-menu`)
    if (menuBtn) menuBtn.click()
  }, 250)
}
</script>

<template>
  <el-dialog :model-value="visible" @update:model-value="emit('update:visible', $event)"
    :title="`数据预览 · ${title}`" width="94%" top="4vh" destroy-on-close class="pvd-dialog">
    <div v-loading="loading" class="pvd-body">
      <div class="pvd-bar">
        <el-tag v-for="(c, i) in prepChips" :key="i" size="small" type="info" :disable-transitions="true">{{ c }}</el-tag>
        <el-tag v-if="editCount" size="small" type="warning" :disable-transitions="true">手工编辑 {{ editCount }} 条</el-tag>
        <span style="flex:1" />
        <el-select v-model="pageSize" size="small" style="width:92px">
          <el-option v-for="n in [25, 50, 100, 200]" :key="n" :value="n" :label="n + ' 行/页'" />
        </el-select>
        <el-button size="small" :loading="exporting" @click="doExport">
          <el-icon class="el-icon--left"><Download /></el-icon>导出 CSV
        </el-button>
      </div>

      <div v-if="!rows.length" class="gg-empty-hint" style="padding:40px">
        {{ data.preview.error || '没有数据' }}
      </div>
      <div v-else class="pvd-scroll gg-scroll">
        <table class="pvd-table">
          <thead>
            <tr>
              <th v-for="h in cols" :key="h.name" :data-col="h.name"
                :class="{ focus: h.name === focusCol, sorted: sortCol === h.name }">
                <div class="th-in">
                  <span class="dot" :style="{ background: dotFor(h) }" />
                  <span class="th-name" :title="h.name">{{ h.name }}</span>
                  <span class="th-n" :title="`唯一值 ${h.nUnique} · 缺失 ${h.nMissing}`">{{ h.nUnique }}</span>
                  <el-button size="small" text class="pvd-sort" :class="{ on: sortCol === h.name }"
                    :title="`按 ${h.name} 排序`" @click="setSort(h.name)">
                    <el-icon><component :is="sortCol === h.name && !sortAsc ? 'ArrowDown' : 'ArrowUp'" /></el-icon>
                  </el-button>
                  <el-popover placement="bottom-start" :width="280" trigger="click"
                    :visible="menuVis[h.name]" @update:visible="menuVis[h.name] = $event">
                    <template #reference>
                      <el-button size="small" text class="pvd-menu" title="列操作">
                        <el-icon><MoreFilled /></el-icon>
                      </el-button>
                    </template>
                    <div class="pvd-menu-body">
                      <ColumnActions :col="h" compact />
                      <div v-if="editMode" class="pvd-editrow">
                        <el-button size="small" text @click="() => { menuVis[h.name] = false; renameCol(h.name) }">
                          <el-icon><Edit /></el-icon>改名
                        </el-button>
                        <el-button size="small" text type="danger"
                          @click="() => { menuVis[h.name] = false; deleteCol(h.name) }">
                          <el-icon><Delete /></el-icon>删除列
                        </el-button>
                      </div>
                    </div>
                  </el-popover>
                </div>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="(r, i) in rows" :key="i">
              <td v-if="editMode" class="pvd-redit">
                <el-popconfirm :title="'删除第 ' + (i + 1) + ' 行？'" width="200"
                  @confirm="deleteRow(rowIds[i])">
                  <template #reference>
                    <el-button size="small" text type="danger"><el-icon><Delete /></el-icon></el-button>
                  </template>
                </el-popconfirm>
              </td>
              <td v-for="(h, ci) in cols" :key="h.name"
                :class="{ 'pvd-editable': editMode }"
                :title="editMode ? '双击编辑' : fmt(r[h.name])"
                @dblclick="startEdit(i, ci, r[h.name], h.name)">
                <el-input v-if="editing && editing.ri === i && editing.ci === ci"
                  v-model="editing.value" size="small" class="gg-mono"
                  @keydown.stop="keydownCell" @blur="commitEdit" />
                <template v-else>{{ fmt(r[h.name]) }}</template>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <el-alert v-if="cellErr" type="error" :title="cellErr" :closable="false" style="margin-top:8px" />
      <div class="pvd-foot" v-if="rows.length">
        <el-switch v-model="editMode" inline-prompt active-text="编辑" inactive-text="只读" size="small" />
        <el-tooltip content="撤销最近一次编辑">
          <el-button size="small" text :disabled="!editMode || undoing" @click="undoLast">
            <el-icon><RefreshLeft /></el-icon>
          </el-button>
        </el-tooltip>
        <el-pagination layout="prev, pager, next, jumper" :total="total" :page-size="pageSize"
          v-model:current-page="page" :page-count="total_pages" background small />
        <span class="gg-mono pvd-pos">
          {{ (page - 1) * pageSize + 1 }}–{{ Math.min(page * pageSize, total) }} / {{ total }}
        </span>
        <span style="flex:1" />
        <el-button v-if="editMode" size="small" @click="addRow">
          <el-icon><Plus /></el-icon>添加行
        </el-button>
        <span style="font-size:11px;color:var(--el-text-color-secondary)">
          映射目标：第 {{ spec.selectedLayer + 1 }} 层（右栏选中）
        </span>
      </div>
    </div>
  </el-dialog>
</template>

<style scoped>
/* 紧凑排版：行高压到 ~19px，11 列数据一屏能看到更多行 */
.pvd-body { display: flex; flex-direction: column; min-height: 360px; }
.pvd-bar { display: flex; align-items: center; gap: 6px; padding-bottom: 6px; }
.pvd-scroll { flex: 1; min-height: 240px; max-height: calc(90vh - 168px); border: 1px solid var(--gg-border); border-radius: 6px; }
.pvd-table { border-collapse: collapse; font-size: 11.5px; width: 100%; }
.pvd-table th {
  position: sticky; top: 0; z-index: 2; background: var(--gg-panel);
  border-bottom: 1px solid var(--gg-border); text-align: left; white-space: nowrap;
}
.pvd-table th.focus { outline: 2px solid var(--gg-accent); outline-offset: -2px; background: rgba(74,144,217,.08); }
.pvd-table th.sorted { background: rgba(74,144,217,.12); }
.th-in { display: flex; align-items: center; gap: 3px; padding: 3px 5px; }
.dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; display: inline-block; }
.th-name { font-weight: 600; max-width: 104px; overflow: hidden; text-overflow: ellipsis; }
.th-n {
  font-size: 9.5px; color: var(--el-text-color-secondary);
  background: rgba(128,128,128,.10); border-radius: 8px; padding: 0 4px; line-height: 12px;
}
.pvd-sort, .pvd-menu { padding: 0 !important; width: 16px; height: 16px; opacity: .45; transition: opacity .12s; }
.pvd-table th:hover .pvd-sort, .pvd-table th:hover .pvd-menu { opacity: 1; }
.pvd-sort.on { color: var(--gg-accent); opacity: 1; }
.pvd-table td {
  padding: 1px 7px; line-height: 17px; border-bottom: 1px solid var(--gg-border);
  white-space: nowrap; max-width: 148px; overflow: hidden; text-overflow: ellipsis;
}
.pvd-table tbody tr:hover td { background: rgba(74,144,217,.06); }
.pvd-stat { color: var(--el-text-color-secondary); font-size: 11px; padding: 2px 0; }
.pvd-prev { display: flex; gap: 4px; flex-wrap: wrap; }
.pvd-prev code {
  background: rgba(128,128,128,.08); border-radius: 3px; padding: 0 4px;
  font-size: 10.5px; max-width: 88px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.pvd-editrow { display: flex; gap: 6px; padding-top: 5px; margin-top: 5px; border-top: 1px dashed var(--gg-border); }
.pvd-foot { display: flex; align-items: center; gap: 8px; padding-top: 6px; flex-wrap: wrap; font-size: 11.5px; }
.pvd-editable { cursor: cell; }
.pvd-redit { width: 28px; }
</style>

<style>
.pvd-dialog .el-dialog__body { padding-top: 8px; }
</style>
