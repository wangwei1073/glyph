<script setup>
// 数据导入向导（P0）：文件 / SQLite / 剪贴板
// 文件先上传到会话（token），预览只读前 50 行，确认后整表导入并记录来源。
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import { ElMessage } from 'element-plus'
import {
  getImportDrivers, importUpload, importPreview, importCommit,
  sqliteTables, sqlitePreview, sqliteCommit, pasteData,
  installExtension, getInstallStatus
} from '../api'

const props = defineProps({ modelValue: { type: Boolean, default: false } })
const emit = defineEmits(['update:modelValue', 'imported'])

const visible = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v)
})

const step = ref(0)
const source = ref('file')          // file | db | clip
const fileInput = ref(null)
const dbInput = ref(null)
const fileName = ref('')
const session = ref(null)
const label = ref('')
const opts = ref({ delim: 'auto', encoding: 'UTF-8', header: true, skip: 0, na: 'NA' })
const preview = ref(null)
const loading = ref(false)
const importing = ref(false)

const drivers = ref([])
const sqliteInstalled = computed(() =>
  !!drivers.value.find(d => d.pkg === 'RSQLite' && d.installed))
const tables = ref([])
const table = ref('')
const tablePreview = ref(null)
const installingDriver = ref(false)
const pvTab = ref('preview')       // preview | stats | raw
const colTypes = ref({})           // 手动类型覆盖：列名 -> num/chr/fct/lgl/date
const fileSize = computed(() => {
  const n = session.value?.size || 0
  if (!n) return ''
  return n >= 1024 * 1024 ? (n / 1024 / 1024).toFixed(1) + ' MB' : (n / 1024).toFixed(1) + ' KB'
})

const curPreview = computed(() => source.value === 'db' ? tablePreview.value : preview.value)
const statRows = computed(() => {
  const p = curPreview.value
  if (!p) return []
  return p.columns.map(c => {
    const s = (p.stats && p.stats[c.name]) || {}
    return {
      name: c.name, type: c.type,
      missing: s.missing ?? '', unique: s.unique ?? '',
      min: s.min ?? '', max: s.max ?? '', top: s.top ?? ''
    }
  })
})
const importCount = computed(() => {
  if (source.value === 'db') {
    const t = tables.value.find(x => x.name === table.value)
    return t && t.rows != null ? t.rows : null
  }
  const p = preview.value
  return p && p.totalRows != null ? p.totalRows : null
})

const clipText = ref('')
const TYPE_CLASS = { num: 'num', chr: 'chr', fct: 'fct', lgl: 'lgl', date: 'date', dttm: 'date' }

let timer = null
function debounce(fn, ms = 400) {
  return (...args) => {
    if (timer) clearTimeout(timer)
    timer = setTimeout(() => fn(...args), ms)
  }
}

function extOf(name) {
  const i = String(name).lastIndexOf('.')
  return i >= 0 ? name.slice(i + 1).toLowerCase() : ''
}
function baseName(name) {
  const i = String(name).lastIndexOf('.')
  return i > 0 ? name.slice(0, i) : name
}
function toBase64(file) {
  return new Promise((resolve, reject) => {
    const r = new FileReader()
    r.onload = () => resolve(String(r.result).split(',')[1] || '')
    r.onerror = reject
    r.readAsDataURL(file)
  })
}

async function refreshPreview() {
  if (!session.value) return
  loading.value = true
  try {
    const res = await importPreview(session.value.token,
      { ...opts.value, colTypes: colTypes.value }, 50)
    preview.value = res.preview
  } catch (e) {
    ElMessage.error('预览失败：' + e.message)
  } finally {
    loading.value = false
  }
}
const refreshPreviewDebounced = debounce(refreshPreview)

watch([opts, colTypes], () => {
  if (step.value === 1 && session.value && source.value === 'file') refreshPreviewDebounced()
}, { deep: true })

async function onFilePicked(e) {
  const f = e.target.files?.[0]
  e.target.value = ''
  if (!f) return
  await loadFile(f)
}

async function loadFile(f) {
  if (f.size > 100 * 1024 * 1024) return ElMessage.error('文件超过 100 MB，请先拆分')
  loading.value = true
  try {
    const b64 = await toBase64(f)
    const res = await importUpload(f.name, extOf(f.name), b64)
    session.value = res.session
    fileName.value = f.name
    label.value = baseName(f.name)
    source.value = 'file'
    preview.value = null
    pvTab.value = 'preview'
    colTypes.value = {}
    step.value = 1
    await refreshPreview()
  } catch (e) {
    ElMessage.error('读取文件失败：' + e.message)
  } finally {
    loading.value = false
  }
}

function openDbPicker() {
  if (!sqliteInstalled.value) {
    ElMessage.warning('SQLite 驱动未安装，请先点下方「立即安装」')
    return
  }
  dbInput.value?.click()
}

async function chooseDb(file) {  if (!file) return
  if (!/\.(db|sqlite|sqlite3)$/i.test(file.name)) return ElMessage.warning('请选择 .db / .sqlite 文件')
  loading.value = true
  try {
    const b64 = await toBase64(file)
    const res = await importUpload(file.name, extOf(file.name), b64)
    session.value = res.session
    fileName.value = file.name
    label.value = baseName(file.name)
    source.value = 'db'
    pvTab.value = 'preview'
    step.value = 1
    await loadTables()
  } catch (e) {
    ElMessage.error('打开数据库失败：' + e.message)
  } finally {
    loading.value = false
  }
}

async function loadDrivers() {
  try {
    const res = await getImportDrivers()
    drivers.value = res.drivers || []
  } catch { /* 忽略 */ }
}

async function loadTables() {
  if (!session.value) return
  loading.value = true
  try {
    const res = await sqliteTables(session.value.token)
    tables.value = res.tables || []
    if (tables.value.length) {
      table.value = tables.value[0].name
      await loadTablePreview()
    } else {
      tablePreview.value = null
    }
  } catch (e) {
    ElMessage.error('读取表失败：' + e.message)
  } finally {
    loading.value = false
  }
}

async function loadTablePreview() {
  if (!table.value) return
  loading.value = true
  try {
    const res = await sqlitePreview(session.value.token, table.value, 100)
    tablePreview.value = res.preview
    label.value = table.value
  } catch (e) {
    ElMessage.error('预览表失败：' + e.message)
  } finally {
    loading.value = false
  }
}

async function installSqlite() {
  if (installingDriver.value) return
  installingDriver.value = true
  try {
    await installExtension('RSQLite')
    const poll = async () => {
      const st = await getInstallStatus()
      if (st.job?.status === 'running') return setTimeout(poll, 1200)
      installingDriver.value = false
      if (st.job?.status === 'done') {
        ElMessage.success('SQLite 驱动安装完成')
        await loadDrivers()
        if (session.value) await loadTables()
      } else {
        ElMessage.error('安装失败：' + (st.job?.log || '未知错误'))
      }
    }
    poll()
  } catch (e) {
    installingDriver.value = false
    ElMessage.error('安装失败：' + e.message)
  }
}

function setColType(name, v) {
  const next = { ...colTypes.value }
  const inferred = preview.value?.columns.find(c => c.name === name)?.type
  if (!v || v === inferred) delete next[name]
  else next[name] = v
  colTypes.value = next
}

async function doImport() {
  if (importing.value) return
  importing.value = true
  try {
    if (source.value === 'clip') {
      if (!clipText.value.trim()) throw new Error('粘贴内容为空')
      const res = await pasteData(clipText.value, label.value || undefined)
      emit('imported', res.source)
    } else if (source.value === 'db') {
      const res = await sqliteCommit(session.value.token, table.value, label.value)
      emit('imported', res.source)
    } else {
      const res = await importCommit(session.value.token,
        { ...opts.value, colTypes: colTypes.value }, label.value)
      emit('imported', res.source)
    }
    ElMessage.success('数据已导入')
    visible.value = false
  } catch (e) {
    ElMessage.error('导入失败：' + e.message)
  } finally {
    importing.value = false
  }
}

function reset() {
  step.value = 0
  source.value = 'file'
  fileName.value = ''
  session.value = null
  label.value = ''
  preview.value = null
  tables.value = []
  table.value = ''
  tablePreview.value = null
  clipText.value = ''
  pvTab.value = 'preview'
  colTypes.value = {}
  opts.value = { delim: 'auto', encoding: 'UTF-8', header: true, skip: 0, na: 'NA' }
}

watch(visible, (v) => {
  if (v) { loadDrivers(); reset() }
})
onBeforeUnmount(() => { if (timer) clearTimeout(timer) })
</script>

<template>
  <el-dialog v-model="visible" title="导入数据" width="980px" top="5vh"
    :close-on-click-modal="false" destroy-on-close>
    <input ref="fileInput" type="file" hidden
      accept=".csv,.tsv,.txt,.xlsx,.xls,.rds,.rdata,.rda,.json" @change="onFilePicked" />
    <input ref="dbInput" type="file" hidden accept=".db,.sqlite,.sqlite3"
      @change="chooseDb($event.target.files?.[0]); $event.target.value = ''" />
    <el-steps :active="step" simple style="margin-bottom:14px">
      <el-step title="选择来源" />
      <el-step title="配置与预览" />
    </el-steps>

    <!-- 步骤 1：来源 -->
    <div v-if="step === 0" class="src-grid">
      <button class="src-card" :class="{ on: source === 'file' }" @click="source = 'file'">
        <div class="ic">▤</div>
        <div class="t">文件</div>
        <div class="d">CSV / TSV / Excel / RDS / JSON</div>
      </button>
      <button class="src-card" :class="{ on: source === 'db' }" @click="source = 'db'">
        <div class="ic">▦</div>
        <div class="t">数据库 · SQLite</div>
        <div class="d">选择 .db / .sqlite 文件，浏览表并导入</div>
      </button>
      <button class="src-card" :class="{ on: source === 'clip' }" @click="source = 'clip'">
        <div class="ic">◫</div>
        <div class="t">剪贴板</div>
        <div class="d">直接粘贴 CSV / TSV 文本</div>
      </button>
    </div>

    <div v-if="step === 0" class="src-actions">
      <template v-if="source === 'file'">
        <el-button type="primary" :loading="loading" @click="fileInput.click()">选择文件…</el-button>
        <span class="hint">CSV / TSV / Excel / RDS / JSON；单文件 ≤100 MB</span>
      </template>
      <template v-else-if="source === 'db'">
        <el-button type="primary" :loading="loading" @click="openDbPicker">
          选择数据库文件…
        </el-button>
        <el-alert v-if="!sqliteInstalled" type="warning" :closable="false" style="margin-top:10px">
          <template #title>
            SQLite 驱动（RSQLite）未安装
            <el-button size="small" text type="primary" :loading="installingDriver" @click="installSqlite">立即安装</el-button>
          </template>
        </el-alert>
        <span v-else class="hint">只读打开；导入后数据会快照到项目，断开数据库不影响已有图表</span>
      </template>
      <template v-else>
        <el-input v-model="clipText" type="textarea" :rows="8" class="gg-mono"
          placeholder="粘贴 CSV / TSV 文本（第一行为列名）" />
      </template>
    </div>

    <!-- 步骤 2：配置 + 预览 -->
    <div v-if="step === 1" class="import-body">
      <div class="cfg">
        <div class="file-line">
          <span class="fname">{{ fileName }}</span>
          <span class="hint">{{ source === 'db' ? 'SQLite' : extOf(fileName).toUpperCase() }}<template v-if="fileSize"> · {{ fileSize }}</template></span>
          <el-button text size="small" class="swap"
            @click="source === 'db' ? dbInput.click() : fileInput.click()">更换…</el-button>
        </div>

        <template v-if="source === 'file'">
          <div class="r2">
            <div><span class="lbl">分隔符</span>
              <el-select v-model="opts.delim" size="small" style="width:100%">
                <el-option value="auto" label="自动检测" />
                <el-option value="comma" label="逗号" />
                <el-option value="tab" label="制表符" />
                <el-option value="semicolon" label="分号" />
              </el-select>
            </div>
            <div><span class="lbl">编码</span>
              <el-select v-model="opts.encoding" size="small" style="width:100%">
                <el-option value="UTF-8" label="UTF-8" />
                <el-option value="GBK" label="GBK" />
                <el-option value="GB18030" label="GB18030" />
                <el-option value="latin1" label="Latin-1" />
              </el-select>
            </div>
          </div>
          <div class="r2">
            <div><span class="lbl">跳过行</span>
              <el-input-number v-model="opts.skip" :min="0" :max="10000" size="small" controls-position="right" style="width:100%" />
            </div>
            <div><span class="lbl">NA 标记</span>
              <el-input v-model="opts.na" size="small" />
            </div>
          </div>
          <el-checkbox v-model="opts.header" size="small">首行作为列名</el-checkbox>
          <div class="hint">预览只读前 50 行；导入时按同一组选项读取整表。</div>
        </template>

        <template v-else-if="source === 'db'">
          <div class="lbl">数据表（{{ tables.length }}）</div>
          <div class="tbl-list">
            <button v-for="t in tables" :key="t.name" class="tbl-item"
              :class="{ on: table === t.name }" @click="table = t.name; loadTablePreview()">
              <span class="tn">{{ t.name }}</span>
              <span class="tr">{{ t.rows ?? '?' }} 行</span>
            </button>
          </div>
          <div class="hint">只读预览前 100 行；导入时最多读取 100 万行。</div>
        </template>
      </div>

      <div class="pvw">
        <div class="pv-head">
          <span class="t">预览</span>
          <span v-if="curPreview" class="hint">{{ curPreview.columns.length }} 列 · 预览 {{ curPreview.previewRows }} 行</span>
          <span style="flex:1" />
          <div class="pv-tabs">
            <button :class="{ on: pvTab === 'preview' }" @click="pvTab = 'preview'">预览</button>
            <button :class="{ on: pvTab === 'stats' }" @click="pvTab = 'stats'">列统计</button>
            <button :class="{ on: pvTab === 'raw' }" @click="pvTab = 'raw'"
              :disabled="!preview || !preview.rawText">原始文本</button>
          </div>
        </div>

        <template v-if="pvTab === 'preview'">
          <el-table v-if="curPreview" :data="curPreview.rows" size="small" height="340" border v-loading="loading">
            <el-table-column v-for="c in curPreview.columns" :key="c.name" :prop="c.name" min-width="120">
              <template #header>
                <span class="col-name">{{ c.name }}</span>
                <span class="tp" :class="TYPE_CLASS[c.type] || 'chr'">{{ c.type }}</span>
              </template>
            </el-table-column>
          </el-table>
          <div v-else class="empty">选择文件或数据表后显示预览</div>
        </template>

        <el-table v-else-if="pvTab === 'stats'" :data="statRows" size="small" height="340" border>
          <el-table-column prop="name" label="列名" min-width="120" />
          <el-table-column label="类型" width="112">
            <template #default="{ row }">
              <el-select v-if="source === 'file'" size="small"
                :model-value="colTypes[row.name] || row.type"
                @update:model-value="(v) => setColType(row.name, v)">
                <el-option value="num" label="num" />
                <el-option value="chr" label="chr" />
                <el-option value="fct" label="fct" />
                <el-option value="lgl" label="lgl" />
                <el-option value="date" label="date" />
              </el-select>
              <span v-else class="tp" :class="TYPE_CLASS[row.type] || 'chr'">{{ row.type }}</span>
            </template>
          </el-table-column>
          <el-table-column prop="missing" label="缺失" width="70" />
          <el-table-column prop="unique" label="唯一" width="70" />
          <el-table-column prop="min" label="最小" min-width="90" />
          <el-table-column prop="max" label="最大" min-width="90" />
          <el-table-column prop="top" label="常见值" min-width="130" />
        </el-table>

        <pre v-else class="raw-box">{{ (preview && preview.rawText) || '（该格式不提供原始文本预览）' }}</pre>
      </div>
    </div>

    <template #footer>
      <div class="foot">
        <div class="foot-name">
          <span class="lbl">数据源名称</span>
          <el-input v-model="label" size="small" style="width:180px" placeholder="导入后的名称" />
        </div>
        <div v-if="step === 1 && curPreview" class="foot-sum">
          来源：<b>{{ source === 'db' ? 'SQLite' : extOf(fileName).toUpperCase() }}</b> · {{ fileName }}
          <span v-if="source === 'db'"> · 表 {{ table }}</span>
        </div>
        <span style="flex:1" />
        <el-button v-if="step === 1" @click="step = 0">上一步</el-button>
        <el-button @click="visible = false">取消</el-button>
        <el-button v-if="step === 0 && source === 'clip'" type="primary" :loading="importing"
          :disabled="!clipText.trim()" @click="doImport">导入</el-button>
        <el-button v-else-if="step === 1" type="primary" :loading="importing"
          :disabled="source === 'db' ? !table : !preview" @click="doImport">
          {{ importCount != null ? `导入 ${importCount} 行` : '导入数据' }}
        </el-button>
      </div>
    </template>
  </el-dialog>
</template>

<style scoped>
.src-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
.src-card {
  text-align: left; border: 1px solid var(--gg-border); background: #fff; border-radius: 8px;
  padding: 14px; cursor: pointer; transition: .15s; height: 118px;
}
.src-card:hover { border-color: var(--gg-brand); background: #fbfdff; }
.src-card.on { border-color: var(--gg-brand); box-shadow: 0 0 0 2px rgba(47,111,191,.10); }
.src-card .ic { font-size: 20px; color: var(--gg-brand); }
.src-card .t { font-size: 13.5px; font-weight: 700; margin-top: 6px; color: var(--gg-text-1); }
.src-card .d { font-size: 11.5px; color: var(--gg-text-3); margin-top: 4px; line-height: 1.5; }
.src-actions { display: flex; align-items: center; gap: 10px; margin-top: 14px; flex-wrap: wrap; }
.hint { font-size: 11.5px; color: var(--gg-text-4); }
.import-body { display: flex; gap: 0; min-height: 440px; }
.cfg { width: 340px; border-right: 1px solid var(--gg-border); padding-right: 14px; display: flex; flex-direction: column; gap: 9px; }
.file-line { display: flex; align-items: center; gap: 8px; border: 1px solid var(--gg-border); border-radius: 6px; padding: 7px 9px; background: #fbfcfe; }
.fname { font-size: 12.5px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.file-line .hint { margin-left: auto; flex-shrink: 0; }
.swap { padding: 0 4px; height: 20px; font-size: 11px; }
.r2 { display: flex; gap: 8px; }
.r2 > div { flex: 1; min-width: 0; }
.lbl { display: block; font-size: 11px; color: var(--gg-text-3); margin-bottom: 4px; }
.nm-row { margin-top: 2px; }
.tbl-list { display: flex; flex-direction: column; gap: 2px; max-height: 220px; overflow: auto; }
.tbl-item {
  display: flex; align-items: center; gap: 6px; border: 0; background: transparent;
  border-radius: 4px; padding: 4px 7px; font-size: 12px; color: var(--gg-text-2); cursor: pointer; text-align: left;
}
.tbl-item:hover { background: rgba(47,111,191,.07); }
.tbl-item.on { background: var(--gg-brand-2, #eaf1fb); color: var(--gg-brand); font-weight: 600; }
.tbl-item .tn { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tbl-item .tr { margin-left: auto; font-size: 10.5px; color: var(--gg-text-4); flex-shrink: 0; }
.pv-tabs { display: flex; gap: 10px; }
.pv-tabs button {
  border: 0; background: transparent; font-size: 11.5px; color: var(--gg-text-4);
  padding: 2px 0; cursor: pointer; border-bottom: 2px solid transparent;
}
.pv-tabs button:hover { color: var(--gg-text-2); }
.pv-tabs button.on { color: var(--gg-brand); border-bottom-color: var(--gg-brand); font-weight: 600; }
.pv-tabs button:disabled { color: var(--gg-text-4); opacity: .5; cursor: default; }
.raw-box {
  margin: 0; height: 340px; overflow: auto; background: #fbfcfe; border: 1px solid var(--gg-border);
  border-radius: 6px; padding: 10px; font-family: Consolas, monospace; font-size: 11.5px;
  color: var(--gg-text-2); white-space: pre-wrap;
}
.foot { display: flex; align-items: center; gap: 12px; width: 100%; }
.foot-name .lbl { margin-bottom: 2px; }
.foot-sum { font-size: 11.5px; color: var(--gg-text-3); min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.foot-sum b { color: var(--gg-text-2); }
.pvw { flex: 1; min-width: 0; padding-left: 14px; display: flex; flex-direction: column; gap: 8px; }
.pv-head { display: flex; align-items: baseline; gap: 8px; }
.pv-head .t { font-size: 12px; font-weight: 600; }
.col-name { margin-right: 5px; }
.tp { font-size: 10px; border-radius: 3px; padding: 0 3px; line-height: 14px; }
.tp.num { background: #e8f1fa; color: #2170b5; }
.tp.chr { background: #fdf3e3; color: #c07f18; }
.tp.fct { background: #eaf5e6; color: #3e8929; }
.tp.lgl { background: #f3eaf8; color: #8d3fb0; }
.tp.date { background: #fdeee3; color: #c55a11; }
.empty { color: var(--gg-text-4); font-size: 12px; padding: 40px; text-align: center; border: 1px dashed var(--gg-border); border-radius: 6px; }
</style>
