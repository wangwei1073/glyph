import io
p = 'src/components/DataPreviewDialog.vue'
s = io.open(p, encoding='utf-8').read()

s = s.replace("import { previewData, exportPreparedCSV } from '../api'",
              "import { previewData, exportPreparedCSV, editAdd, editUndo } from '../api'")

s = s.replace("""const loading = ref(false)
const exporting = ref(false)""",
"""const loading = ref(false)
const exporting = ref(false)
const editMode = ref(false)
const rowIds = ref([])
const editCount = ref(0)
const editing = ref(null)
const undoing = ref(false)
const scheduleTimer = ref(null)
const cellErr = ref('')""")

s = s.replace("""  total.value = d.nrow || 0
  } catch (e) {""",
"""  total.value = d.nrow || 0
    rowIds.value = d.rowIds || []
    editCount.value = (await (await fetch('/api/edits')).ok) ? 0 : 0
  } catch (e) {""")

s = s.replace("""function doInsert(name) {
  const r = insertExpr(name)
  if (!r.ok) ElMessage.info(r.msg)
}""",
"""function doInsert(name) {
  const r = insertExpr(name)
  if (!r.ok) ElMessage.info(r.msg)
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
  const r = await ElMessageBox.prompt('将列 ' + colName + ' 改名为：', '列改名', {
    inputValue: colName, inputPattern: /^[A-Za-z][A-Za-z0-9._]*$/,
    inputErrorMessage: '以字母开头，可含字母/数字/点/下划线'
  })
  menuVis.value = {}
  await commitOp({ kind: 'colRen', from: colName, to: (r.value || '').trim() })
  ElMessage.success('已改名')
}
async function deleteCol(colName) {
  await commitOp({ kind: 'colDel', col: colName })
  ElMessage.success('列已删除')
}
async function undoLast() {
  cellErr.value = ''
  try {
    const res = await editUndo(srcObj.value)
    if (res.ok) {
      await load()
      scheduleRender()
      var cc = await fetch('/api/edits?key=' + encodeURIComponent(JSON.stringify(srcObj.value)))
      var jj = await cc.json()
      editCount.value = jj.count || 0
    }
  } catch (e) { ElMessage.error(e.message) }
}""")

s = s.replace("""      <div class="pvd-foot" v-if="rows.length">
        <el-pagination layout="prev, pager, next, jumper" :total="total" :page-size="pageSize"
          v-model:current-page="page" :page-count="total_pages" background small />""",
"""      <el-alert v-if="cellErr" type="error" :title="cellErr" :closable="false" style="margin-top:8px" />
      <div class="pvd-foot" v-if="rows.length">
        <el-switch v-model="editMode" inline-prompt active-text="编辑" inactive-text="只读" size="small" />
        <el-tooltip content="撤销最近一次编辑">
          <el-button size="small" text :disabled="!editMode || undoing" @click="undoLast">
            <el-icon><RefreshLeft /></el-icon>
          </el-button>
        </el-tooltip>
        <el-pagination layout="prev, pager, next, jumper" :total="total" :page-size="pageSize"
          v-model:current-page="page" :page-count="total_pages" background small />""")

s = s.replace("""        <span style="flex:1" />
        <span style="font-size:11px;color:var(--el-text-color-secondary)">
          映射目标：第 {{ spec.selectedLayer + 1 }} 层（右栏选中）
        </span>
      </div>""",
"""        <span style="flex:1" />
        <el-button v-if="editMode" size="small" @click="addRow">
          <el-icon><Plus /></el-icon>添加行
        </el-button>
        <span style="font-size:11px;color:var(--el-text-color-secondary)">
          映射目标：第 {{ spec.selectedLayer + 1 }} 层（右栏选中）
        </span>
      </div>""")

s = s.replace("""                      <div style="display:flex;gap:6px;align-items:center">
                        <el-button size="small" text @click="doInsert(h.name)">
                          <el-icon><EditPen /></el-icon>插入列名
                        </el-button>
                        <span style="flex:1" />
                        <span class="dot" :style="{ background: dotFor(h) }" />
                      </div>""",
"""                      <div style="display:flex;gap:6px;align-items:center">
                        <el-button size="small" text @click="doInsert(h.name)">
                          <el-icon><EditPen /></el-icon>插入列名
                        </el-button>
                        <span v-if="editMode">
                          <el-button size="small" text @click="() => { menuVis[h.name] = false; renameCol(h.name) }">
                            <el-icon><Edit /></el-icon>改名
                          </el-button>
                          <el-button size="small" text type="danger"
                            @click="() => { menuVis[h.name] = false; deleteCol(h.name) }">
                            <el-icon><Delete /></el-icon>删除列
                          </el-button>
                        </span>
                        <span style="flex:1" />
                        <span class="dot" :style="{ background: dotFor(h) }" />
                      </div>""")

s = s.replace("""          <tbody>
            <tr v-for="(r, i) in rows" :key="i">
              <td v-for="h in cols" :key="h.name" :title="fmt(r[h.name])">
                <span class="dot" :style="{ background: dotFor(h) }" style="width:0" v-if="false" />
                {{ fmt(r[h.name]) }}
              </td>
            </tr>
          </tbody>""",
"""          <tbody>
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
          </tbody>""")

s = s.replace(""".pvd-foot { display: flex; align-items: center; gap: 12px; padding-top: 10px; }""",
""".pvd-foot { display: flex; align-items: center; gap: 12px; padding-top: 10px; flex-wrap: wrap; }
.pvd-editable { cursor: cell; }
.pvd-redit { width: 30px; }""")

io.open(p, 'w', encoding='utf-8').write(s)
print('dialog edit ok')
