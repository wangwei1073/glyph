<script setup>
// 导入数据弹层 v2：顶部标签（文件 / SQLite / 远程数据库 / 剪贴板），无步骤条
import { ref, computed, watch, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import {
  getImportDrivers, importUpload, importPreview, importCommit,
  sqliteTables, sqlitePreview, sqliteCommit,
  installExtension, getInstallStatus, MAX_UPLOAD_BYTES
} from '../api'
import { useRemoteDbStore } from '../stores/remoteDb'
import RemoteDbPane from './RemoteDbPane.vue'

const props = defineProps({ modelValue: { type: Boolean, default: false } })
const emit = defineEmits(['update:modelValue', 'imported'])
const db = useRemoteDbStore()

const visible = computed({
  get: () => props.modelValue,
  set: (v) => emit('update:modelValue', v)
})

const TABS = [
  { id: 'file', label: '文件', icon: 'Document' },
  { id: 'sqlite', label: 'SQLite', icon: 'Coin' },
  { id: 'remote', label: '远程数据库', icon: 'Connection' },
  { id: 'clip', label: '剪贴板', icon: 'DocumentCopy' }
]
const activeTab = ref('file')
const TYPE_CLASS = { num: 'num', chr: 'chr', fct: 'fct', lgl: 'lgl', date: 'date', dttm: 'date' }

// ---------------- 文件 ----------------
const fileInput = ref(null)
const fileName = ref('')
const fileSession = ref(null)
const fileLabel = ref('')
const fileOpts = ref({ delim: 'auto', encoding: 'UTF-8', header: true, skip: 0, na: 'NA' })
const filePreview = ref(null)
const filePvTab = ref('preview')
const fileColTypes = ref({})
const fileLoading = ref(false)
const fileSize = computed(() => {
  const n = fileSession.value?.size || 0
  if (!n) return ''
  return n >= 1024 * 1024 ? (n / 1024 / 1024).toFixed(1) + ' MB' : (n / 1024).toFixed(1) + ' KB'
})
const fileStatRows = computed(() => {
  const p = filePreview.value
  if (!p) return []
  return p.columns.map(c => {
    const s = (p.stats && p.stats[c.name]) || {}
    return {
      name: c.name, type: c.type, missing: s.missing ?? '', unique: s.unique ?? '',
      min: s.min ?? '', max: s.max ?? '', top: s.top ?? ''
    }
  })
})
const fileImportCount = computed(() => filePreview.value?.totalRows ?? null)

let fileTimer = null
function debouncePreview() {
  if (fileTimer) clearTimeout(fileTimer)
  fileTimer = setTimeout(() => { if (activeTab.value === 'file') loadFilePreview() }, 400)
}
watch([fileOpts, fileColTypes], debouncePreview, { deep: true })

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

async function onFilePicked(e) {
  const f = e.target.files?.[0]
  e.target.value = ''
  if (!f) return
  // 与 api.js uploadData / 后端请求体上限（50MB，base64 膨胀 4/3）对齐，
  // 否则大文件能进预览却死在提交，报晦涩的服务端错误
  if (f.size > MAX_UPLOAD_BYTES) {
    return ElMessage.error(`文件超过 ${MAX_UPLOAD_BYTES / 1048576} MB（后端请求体上限），请先拆分`)
  }
  fileLoading.value = true
  try {
    const res = await importUpload(f.name, extOf(f.name), await toBase64(f))
    fileSession.value = res.session
    fileName.value = f.name
    fileLabel.value = baseName(f.name)
    filePreview.value = null
    fileColTypes.value = {}
    filePvTab.value = 'preview'
    await loadFilePreview()
  } catch (e) {
    ElMessage.error('读取文件失败：' + e.message)
  } finally {
    fileLoading.value = false
  }
}

async function loadFilePreview() {
  if (!fileSession.value) return
  fileLoading.value = true
  try {
    const res = await importPreview(fileSession.value.token,
      { ...fileOpts.value, colTypes: fileColTypes.value }, 50)
    filePreview.value = res.preview
  } catch (e) {
    ElMessage.error('预览失败：' + e.message)
  } finally {
    fileLoading.value = false
  }
}

function setFileType(name, v) {
  const next = { ...fileColTypes.value }
  const inferred = filePreview.value?.columns.find(c => c.name === name)?.type
  if (!v || v === inferred) delete next[name]
  else next[name] = v
  fileColTypes.value = next
}

// ---------------- SQLite ----------------
const dbInput = ref(null)
const dbFileName = ref('')
const dbSize = ref(0)
const dbSession = ref(null)
const dbTables = ref([])
const dbTable = ref('')
const dbPreview = ref(null)
const dbLabel = ref('')
const dbLoading = ref(false)

function toSize(n) {
  return n >= 1024 * 1024 ? (n / 1024 / 1024).toFixed(1) + ' MB' : (n / 1024).toFixed(1) + ' KB'
}

async function onDbPicked(e) {
  const f = e.target.files?.[0]
  e.target.value = ''
  if (!f) return
  if (!/\.(db|sqlite|sqlite3)$/i.test(f.name)) return ElMessage.warning('请选择 .db / .sqlite 文件')
  dbLoading.value = true
  try {
    const res = await importUpload(f.name, extOf(f.name), await toBase64(f))
    dbSession.value = res.session
    dbFileName.value = f.name
    dbSize.value = f.size
    dbPreview.value = null
    await loadDbTables()
  } catch (e) {
    ElMessage.error('打开数据库失败：' + e.message)
  } finally {
    dbLoading.value = false
  }
}

async function loadDbTables() {
  if (!dbSession.value) return
  dbLoading.value = true
  try {
    const res = await sqliteTables(dbSession.value.token)
    dbTables.value = res.tables || []
    if (dbTables.value.length) {
      dbTable.value = dbTables.value[0].name
      dbLabel.value = dbTable.value
      await loadDbPreview()
    }
  } catch (e) {
    ElMessage.error('读取表失败：' + e.message)
  } finally {
    dbLoading.value = false
  }
}

async function loadDbPreview() {
  if (!dbSession.value || !dbTable.value) return
  dbLoading.value = true
  try {
    const res = await sqlitePreview(dbSession.value.token, dbTable.value, 100)
    dbPreview.value = res.preview
    dbLabel.value = dbTable.value
  } catch (e) {
    ElMessage.error('预览表失败：' + e.message)
  } finally {
    dbLoading.value = false
  }
}

// ---------------- 剪贴板 ----------------
const clipText = ref('')
const clipPreview = ref(null)
const clipSession = ref(null)
const clipLabel = ref('')
const clipLoading = ref(false)
const clipRows = computed(() => clipPreview.value?.rows || [])

async function previewClip() {
  if (!clipText.value.trim()) return ElMessage.warning('粘贴内容为空')
  clipLoading.value = true
  try {
    const raw = new TextEncoder().encode(clipText.value)
    let bin = ''
    raw.forEach(b => { bin += String.fromCharCode(b) })
    const b64 = btoa(bin)
    const up = await importUpload('paste.csv', 'csv', b64)
    clipSession.value = up.session
    const res = await importPreview(up.session.token, { delim: 'auto', encoding: 'UTF-8', header: true }, 50)
    clipPreview.value = res.preview
    clipLabel.value = clipLabel.value || '粘贴数据'
  } catch (e) {
    ElMessage.error('解析失败：' + e.message)
  } finally {
    clipLoading.value = false
  }
}
watch(clipText, () => { clipPreview.value = null })

// ---------------- 按钮状态 ----------------
const busy = computed(() =>
  fileLoading.value || dbLoading.value || clipLoading.value || db.importing || db.loading)
const currentName = computed({
  get() {
    if (activeTab.value === 'file') return fileLabel.value
    if (activeTab.value === 'sqlite') return dbLabel.value
    if (activeTab.value === 'remote') return db.label
    return clipLabel.value
  },
  set(v) {
    if (activeTab.value === 'file') fileLabel.value = v
    else if (activeTab.value === 'sqlite') dbLabel.value = v
    else if (activeTab.value === 'remote') db.label = v
    else clipLabel.value = v
  }
})
const importCount = computed(() => {
  if (activeTab.value === 'file') return fileImportCount.value
  if (activeTab.value === 'sqlite') {
    const t = dbTables.value.find(x => x.name === dbTable.value)
    return t?.rows ?? null
  }
  if (activeTab.value === 'remote') return db.importCount
  return clipPreview.value?.previewRows ?? null
})
const canImport = computed(() => {
  if (activeTab.value === 'file') return !!filePreview.value
  if (activeTab.value === 'sqlite') return !!dbPreview.value
  if (activeTab.value === 'remote') return !!db.preview
  return !!clipPreview.value
})
const footSource = computed(() => {
  if (activeTab.value === 'file') {
    if (!fileName.value) return '来源：文件 · 未选择'
    return `来源：文件 · ${fileName.value}` + (fileImportCount.value != null ? ` · 将导入 ${fileImportCount.value} 行` : '')
  }
  if (activeTab.value === 'sqlite') {
    if (!dbFileName.value) return '来源：SQLite · 未选择'
    const cnt = dbTables.value.find(x => x.name === dbTable.value)?.rows
    return `来源：SQLite · ${dbFileName.value}` +
      (dbTable.value ? ` · 表 ${dbTable.value}` : '') +
      (cnt != null ? ` · 将导入 ${cnt} 行` : '')
  }
  if (activeTab.value === 'remote') {
    if (!db.connId) return '来源：未连接'
    const t = db.sqlMode ? '自定义查询' : (db.tableSel?.name || '')
    return `来源：${db.driverDef?.label || ''} · ${db.form.host}/${db.form.dbname}` + (t ? ` · ${t}` : '')
  }
  return '来源：剪贴板' + (clipPreview.value ? ` · 将导入 ${clipPreview.value.previewRows} 行` : '')
})

async function doImport() {
  try {
    if (activeTab.value === 'file') {
      const res = await importCommit(fileSession.value.token,
        { ...fileOpts.value, colTypes: fileColTypes.value }, fileLabel.value)
      emit('imported', res.source)
    } else if (activeTab.value === 'sqlite') {
      const res = await sqliteCommit(dbSession.value.token, dbTable.value, dbLabel.value)
      emit('imported', res.source)
    } else if (activeTab.value === 'remote') {
      const src = await db.importData()
      if (!src) return
      emit('imported', src)
    } else {
      const res = await importCommit(clipSession.value.token, {}, clipLabel.value)
      emit('imported', res.source)
    }
    visible.value = false
  } catch (e) {
    ElMessage.error('导入失败：' + e.message)
  }
}

onMounted(() => { if (activeTab.value === 'remote') db.loadDrivers() })
</script>

<template>
  <el-dialog v-model="visible" title="导入数据" width="1040px" top="5vh"
    class="imp-dialog" :close-on-click-modal="false">
    <input ref="fileInput" type="file" hidden
      accept=".csv,.tsv,.txt,.xlsx,.xls,.rds,.rdata,.rda,.json" @change="onFilePicked" />
    <input ref="dbInput" type="file" hidden accept=".db,.sqlite,.sqlite3"
      @change="onDbPicked" />

    <div class="tabs">
      <button v-for="t in TABS" :key="t.id" class="tab" :class="{ active: activeTab === t.id }"
        @click="activeTab = t.id">
        <el-icon><component :is="t.icon" /></el-icon>{{ t.label }}
      </button>
      <span style="flex:1" />
      <span class="hint tab-hint">切换标签不会丢失已配置内容</span>
    </div>

    <!-- 文件 -->
    <div v-if="activeTab === 'file'" class="cols">
      <div class="col cfg">
        <div class="fileline">
          <el-icon class="f-ic"><Document /></el-icon>
          <span class="fname">{{ fileName || '未选择文件' }}</span>
          <span class="meta">{{ fileSize }}</span>
          <el-button v-if="!fileName" type="primary" @click="fileInput.click()">选择文件…</el-button>
          <el-button v-else text class="swap" @click="fileInput.click()">更换…</el-button>
        </div>
        <div class="r2">
          <div><span class="lbl">分隔符</span>
            <el-select v-model="fileOpts.delim" style="width:100%">
              <el-option value="auto" label="自动检测" />
              <el-option value="comma" label="逗号" />
              <el-option value="tab" label="制表符" />
              <el-option value="semicolon" label="分号" />
            </el-select>
          </div>
          <div><span class="lbl">编码</span>
            <el-select v-model="fileOpts.encoding" style="width:100%">
              <el-option value="UTF-8" label="UTF-8" />
              <el-option value="GBK" label="GBK" />
              <el-option value="GB18030" label="GB18030" />
              <el-option value="latin1" label="Latin-1" />
            </el-select>
          </div>
        </div>
        <div class="r2">
          <div><span class="lbl">跳过行</span>
            <el-input-number v-model="fileOpts.skip" :min="0" :max="10000" controls-position="right" style="width:100%" />
          </div>
          <div><span class="lbl">NA 标记</span><el-input v-model="fileOpts.na" /></div>
        </div>
        <el-checkbox v-model="fileOpts.header">首行作为列名</el-checkbox>
        <div class="hint">预览只读前 50 行；导入时按同一组选项读取整表。</div>
      </div>
      <div class="col right">
        <div class="pv-head">
          <span class="t">预览</span>
          <span v-if="filePreview" class="hint">{{ filePreview.columns.length }} 列 · {{ filePreview.previewRows }} 行</span>
          <span style="flex:1" />
          <div class="pv-tabs">
            <button :class="{ on: filePvTab === 'preview' }" @click="filePvTab = 'preview'">预览</button>
            <button :class="{ on: filePvTab === 'stats' }" @click="filePvTab = 'stats'">列统计</button>
            <button :class="{ on: filePvTab === 'raw' }" @click="filePvTab = 'raw'"
              :disabled="!filePreview?.rawText">原始文本</button>
          </div>
        </div>
        <template v-if="filePvTab === 'preview'">
          <el-table v-if="filePreview" :data="filePreview.rows" size="small" height="340" border v-loading="fileLoading">
            <el-table-column v-for="c in filePreview.columns" :key="c.name" :prop="c.name" min-width="120">
              <template #header><span class="cn">{{ c.name }}</span><span class="tp" :class="TYPE_CLASS[c.type] || 'chr'">{{ c.type }}</span></template>
            </el-table-column>
          </el-table>
          <div v-else class="empty">选择文件后显示预览</div>
        </template>
        <el-table v-else-if="filePvTab === 'stats'" :data="fileStatRows" size="small" height="340" border>
          <el-table-column prop="name" label="列名" min-width="120" />
          <el-table-column label="类型" width="112">
            <template #default="{ row }">
              <el-select :model-value="fileColTypes[row.name] || row.type"
                @update:model-value="(v) => setFileType(row.name, v)">
                <el-option value="num" label="num" /><el-option value="chr" label="chr" />
                <el-option value="fct" label="fct" /><el-option value="lgl" label="lgl" />
                <el-option value="date" label="date" />
              </el-select>
            </template>
          </el-table-column>
          <el-table-column prop="missing" label="缺失" width="70" />
          <el-table-column prop="unique" label="唯一" width="70" />
          <el-table-column prop="min" label="最小" min-width="90" />
          <el-table-column prop="max" label="最大" min-width="90" />
          <el-table-column prop="top" label="常见值" min-width="130" />
        </el-table>
        <pre v-else class="raw-box">{{ filePreview?.rawText || '（该格式不提供原始文本预览）' }}</pre>
      </div>
    </div>

    <!-- SQLite -->
    <div v-else-if="activeTab === 'sqlite'" class="cols">
      <div class="col cfg">
        <div class="fileline">
          <el-icon class="f-ic"><Coin /></el-icon>
          <span class="fname">{{ dbFileName || '未选择数据库' }}</span>
          <span class="meta">{{ dbSize ? toSize(dbSize) : '' }}</span>
          <el-button v-if="!dbFileName" type="primary" @click="dbInput.click()">选择文件…</el-button>
          <el-button v-else text class="swap" @click="dbInput.click()">更换…</el-button>
        </div>
        <div class="col-h" style="margin-top:4px">表（{{ dbTables.length }}）</div>
        <div class="tbl-list">
          <button v-for="t in dbTables" :key="t.name" class="tbl-item" :class="{ on: dbTable === t.name }"
            @click="dbTable = t.name; loadDbPreview()">
            <span class="tn">{{ t.name }}</span><span class="tr">{{ t.rows ?? '' }} 行</span>
          </button>
        </div>
        <div class="hint">只读打开；导入时最多读取 100 万行。</div>
      </div>
      <div class="col right">
        <div class="pv-head"><span class="t">预览</span>
          <span v-if="dbPreview" class="hint">{{ dbPreview.columns.length }} 列 · {{ dbPreview.previewRows }} 行</span>
        </div>
        <el-table v-if="dbPreview" :data="dbPreview.rows" size="small" height="380" border v-loading="dbLoading">
          <el-table-column v-for="c in dbPreview.columns" :key="c.name" :prop="c.name" min-width="120">
            <template #header><span class="cn">{{ c.name }}</span><span class="tp" :class="TYPE_CLASS[c.type] || 'chr'">{{ c.type }}</span></template>
          </el-table-column>
        </el-table>
        <div v-else class="empty">选择数据库文件后显示表与预览</div>
      </div>
    </div>

    <!-- 远程数据库 -->
    <RemoteDbPane v-else-if="activeTab === 'remote'" />

    <!-- 剪贴板 -->
    <div v-else class="cols">
      <div class="col cfg">
        <span class="lbl">粘贴 CSV / TSV 文本（第一行为列名）</span>
        <el-input v-model="clipText" type="textarea" :rows="10" class="gg-mono"
          placeholder="a,b,c&#10;1,2,x" />
        <el-button type="primary" :loading="clipLoading" @click="previewClip">解析预览</el-button>
        <div class="hint">解析后可在右侧预览；确认后导入。</div>
      </div>
      <div class="col right">
        <div class="pv-head"><span class="t">预览</span>
          <span v-if="clipPreview" class="hint">{{ clipPreview.columns.length }} 列 · {{ clipPreview.previewRows }} 行</span>
        </div>
        <el-table v-if="clipPreview" :data="clipRows" size="small" height="340" border>
          <el-table-column v-for="c in clipPreview.columns" :key="c.name" :prop="c.name" min-width="120">
            <template #header><span class="cn">{{ c.name }}</span><span class="tp" :class="TYPE_CLASS[c.type] || 'chr'">{{ c.type }}</span></template>
          </el-table-column>
        </el-table>
        <div v-else class="empty">点「解析预览」查看结果</div>
      </div>
    </div>

    <template #footer>
      <div class="foot">
        <div class="sum">{{ footSource }}</div>
        <div class="name-inline">
          <span>数据源名称</span>
          <el-input v-model="currentName" placeholder="导入后的名称" />
        </div>
        <el-button @click="visible = false">取消</el-button>
        <el-button type="primary" :loading="busy" :disabled="!canImport" @click="doImport">
          {{ importCount != null ? `导入 ${importCount} 行` : '导入数据' }}
        </el-button>
      </div>
    </template>
  </el-dialog>
</template>

<style scoped>
.tabs { display: flex; align-items: center; gap: 4px; padding: 0 4px 8px; border-bottom: 1px solid var(--gg-border); margin-bottom: 12px; }
.tab {
  border: 0; background: transparent; padding: 7px 14px 9px; font-size: 12.5px; color: var(--gg-text-3);
  cursor: pointer; border-bottom: 2px solid transparent; display: flex; align-items: center; gap: 6px;
  border-radius: 6px 6px 0 0;
}
.tab.active { color: var(--gg-brand); border-bottom-color: var(--gg-brand); background: #fff; font-weight: 600; }
.tab-hint { padding-bottom: 6px; }
.cols { display: flex; min-height: 470px; }
.col { display: flex; flex-direction: column; gap: 9px; }
.cfg { width: 330px; border-right: 1px solid var(--gg-border); padding-right: 14px; }
.right { flex: 1; min-width: 0; padding-left: 14px; }
.lbl { display: block; font-size: 11px; color: var(--gg-text-3); margin-bottom: 4px; }
.hint { font-size: 11.5px; color: var(--gg-text-4); }
.r2 { display: flex; gap: 8px; }
.r2 > div { flex: 1; min-width: 0; }
.fileline { display: flex; align-items: center; gap: 8px; border: 1px solid var(--gg-border); border-radius: 6px; padding: 7px 9px; background: #fbfcfe; }
.fileline .f-ic { color: var(--gg-brand); }
.fname { font-size: 12.5px; font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.fileline .meta { margin-left: auto; font-size: 11px; color: var(--gg-text-4); }
.fileline .swap { padding: 0 4px; height: 20px; font-size: 11px; }
.tbl-list { display: flex; flex-direction: column; gap: 2px; max-height: 220px; overflow: auto; }
.tbl-item { display: flex; align-items: center; gap: 6px; border: 0; background: transparent; border-radius: 4px; padding: 4px 7px; font-size: 12px; color: var(--gg-text-2); cursor: pointer; text-align: left; }
.tbl-item:hover { background: rgba(47,111,191,.07); }
.tbl-item.on { background: var(--gg-brand-2, #eaf1fb); color: var(--gg-brand); font-weight: 600; }
.tbl-item .tn { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.tbl-item .tr { margin-left: auto; font-size: 10.5px; color: var(--gg-text-4); }
.pv-head { display: flex; align-items: center; gap: 8px; }
.pv-head .t { font-size: 12px; font-weight: 600; }
.pv-tabs { display: flex; gap: 10px; }
.pv-tabs button { border: 0; background: transparent; font-size: 11.5px; color: var(--gg-text-4); padding: 2px 0; cursor: pointer; border-bottom: 2px solid transparent; }
.pv-tabs button.on { color: var(--gg-brand); border-bottom-color: var(--gg-brand); font-weight: 600; }
.pv-tabs button:disabled { opacity: .5; cursor: default; }
.cn { margin-right: 5px; }
.tp { font-size: 10px; border-radius: 3px; padding: 0 3px; line-height: 14px; }
.tp.num { background: #e8f1fa; color: #2170b5; }
.tp.chr { background: #fdf3e3; color: #c07f18; }
.tp.fct { background: #eaf5e6; color: #3e8929; }
.tp.lgl { background: #f3eaf8; color: #8d3fb0; }
.tp.date { background: #fdeee3; color: #c55a11; }
.raw-box { margin: 0; height: 340px; overflow: auto; background: #fbfcfe; border: 1px solid var(--gg-border); border-radius: 6px; padding: 10px; font-family: Consolas, monospace; font-size: 11.5px; color: var(--gg-text-2); white-space: pre-wrap; }
.empty { color: var(--gg-text-4); font-size: 12px; padding: 36px; text-align: center; border: 1px dashed var(--gg-border); border-radius: 6px; }
/* 弹窗内控件统一高度 32px（default 尺寸天然一致，这里兜底微调） */
.imp-dialog :deep(.el-select__wrapper),
.imp-dialog :deep(.el-input__wrapper),
.imp-dialog :deep(.el-input-number) { --el-component-size: 32px; }
.imp-dialog :deep(.el-input__wrapper),
.imp-dialog :deep(.el-select__wrapper) { min-height: 32px; }
.imp-dialog :deep(.el-input-number .el-input__inner) { height: 30px; line-height: 30px; }
.imp-dialog :deep(.el-checkbox) { height: 32px; }
.imp-dialog :deep(.el-checkbox .el-checkbox__label) { font-size: 13px; }
.imp-dialog :deep(.el-button) { height: 32px; }
.foot { display: flex; align-items: center; gap: 12px; width: 100%; }
.foot .sum { font-size: 11.5px; color: var(--gg-text-3); margin-right: auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.foot .sum b { color: var(--gg-text-2); }
/* 底栏统一高度：名称输入框、取消/导入按钮都用 32px（default 尺寸），视觉一条线 */
.name-inline { display: flex; align-items: center; gap: 8px; font-size: 11.5px; color: var(--gg-text-3); white-space: nowrap; flex-shrink: 0; }
.name-inline :deep(.el-input) { width: 200px; }
.foot :deep(.el-input__wrapper) { padding-top: 1px; padding-bottom: 1px; }
.foot :deep(.el-input__inner) { height: 28px; line-height: 28px; }
.foot :deep(.el-button) { height: 30px; padding-left: 18px; padding-right: 18px; }
</style>
