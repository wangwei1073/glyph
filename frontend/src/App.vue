<script setup>
// App：三段式顶栏（身份 / 中置渲染主控簇 / 项目与视图）
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useMetaStore } from './stores/meta'
import { useDataStore } from './stores/data'
import { useSpecStore } from './stores/spec'
import { usePinStore } from './stores/pins'
import { useUiStore } from './stores/ui'
import { downloadBlob, snapshotData, getEdits, importEdits, pasteData } from './api'
import DataPanel from './components/DataPanel.vue'
import Canvas from './components/Canvas.vue'
import EditorTabs from './components/EditorTabs.vue'

const meta = useMetaStore()
const data = useDataStore()
const spec = useSpecStore()
const pins = usePinStore()
const ui = useUiStore()

// ---- 自动渲染（深度 watch spec + 渲染设置，550ms 防抖） ----
let debounceTimer = null
function scheduleRender() {
  if (!spec.autoRender) return
  clearTimeout(debounceTimer)
  spec.renderQueued = true
  debounceTimer = setTimeout(() => {
    spec.renderQueued = false
    spec.renderNow()
  }, 550)
}
watch(() => spec.spec, scheduleRender, { deep: true })
watch(() => spec.renderOpts, scheduleRender, { deep: true })

// ---- 草稿自动保存（崩溃 / 误关恢复）----
let draftTimer = null
function scheduleDraft() {
  clearTimeout(draftTimer)
  draftTimer = setTimeout(() => { spec.saveDraft() }, 1500)
}
watch(() => spec.spec, () => { if (meta.loaded) scheduleDraft() }, { deep: true })
watch(() => spec.renderOpts, () => { if (meta.loaded) scheduleDraft() }, { deep: true })

const draftOffer = ref(null)
const draftTime = computed(() => {
  if (!draftOffer.value) return ''
  const d = new Date(draftOffer.value.at)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
})
const saveLabel = computed(() => {
  if (!spec.spec.layers.length) return '新建'
  return spec.dirty ? '未保存' : '已保存'
})
const saveHint = computed(() => {
  if (!spec.spec.layers.length) return '新项目：添加图层后开始'
  return spec.dirty
    ? '有未保存的修改（草稿已自动存到本机，可随时恢复）'
    : '当前内容已保存到项目文件'
})
function onBeforeUnload() { if (spec.dirty) spec.saveDraft() }

async function restoreDraft() {
  const d = draftOffer.value
  draftOffer.value = null
  if (!d) return
  spec.restoreDraft(d)
  const src = spec.spec.data && spec.spec.data.source
  try {
    if (src && src.type === 'dataset') await data.select(`dataset:${src.name}`)
    else if (src && src.type === 'user' &&
             data.sources.some(s => s.type === 'user' && s.name === src.id)) {
      await data.select(`user:${src.id}`)
    } else if (src && src.type === 'user') {
      ElMessage.warning('草稿引用的上传数据已不存在，请重新选择数据')
    }
  } catch (e) {
    ElMessage.warning('草稿数据恢复失败：' + e.message)
  }
  spec.renderNow()
  ElMessage.success('草稿已恢复，记得「项目 → 保存项目」')
}
function discardDraft() {
  draftOffer.value = null
  spec.clearDraft()
  ElMessage.info('草稿已丢弃')
}

// ---- 全局快捷键：Ctrl+Z / Ctrl+Y（在输入框、CodeMirror 内不拦截） ----
function onKeydown(e) {
  if (!(e.ctrlKey || e.metaKey) || e.altKey) return
  const key = (e.key || '').toLowerCase()
  const t = e.target
  const inEditor = t && (t.isContentEditable ||
    /^(input|textarea|select)$/i.test(t.tagName || '') ||
    (t.closest && t.closest('.cm-editor')))
  if (inEditor) return
  if (key === 'z' && !e.shiftKey) {
    e.preventDefault()
    spec.undo()
  } else if (key === 'y' || (key === 'z' && e.shiftKey)) {
    e.preventDefault()
    spec.redo()
  }
}

// 启动加载（元数据 + 数据源）；失败时停在启动页，可重试
async function boot() {
  // 后端刚启动 / 代理尚未就绪时重试
  const retry = async (fn, tries = 4, delay = 700) => {
    let err
    for (let i = 0; i < tries; i++) {
      try { return await fn() } catch (e) { err = e; await new Promise(r => setTimeout(r, delay)) }
    }
    throw err
  }
  try {
    await retry(() => meta.load())
    await retry(() => data.load())
    spec.ensureDefaultTheme()
    spec.renderNow()
    // 有未保存草稿（上次异常退出/误关）→ 顶部条提示，不自动覆盖当前空白项目
    const d = spec.readDraft()
    if (d && !spec.spec.layers.length) draftOffer.value = d
  } catch (e) {
    ElMessage.error('后端服务不可用: ' + e.message)
  }
}

onMounted(async () => {
  window.addEventListener('keydown', onKeydown)
  window.addEventListener('beforeunload', onBeforeUnload)
  await boot()
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown)
  window.removeEventListener('beforeunload', onBeforeUnload)
  clearTimeout(draftTimer)
})

function toggleDark() {
  spec.dark = !spec.dark
  document.documentElement.classList.toggle('dark', spec.dark)
}

// ---- 项目操作 ----
// 项目文件 = { app, format, savedAt, spec, data? }
// data 仅在数据源为「上传/粘贴」时内嵌：CSV 快照 + 手工编辑 ops，
// 这样换机器/重启后仍能打开；内置数据集只靠名字复现。
const PROJECT_FORMAT = 2
const EMBED_LIMIT = 8 * 1024 * 1024   // 8MB：超过则项目文件不内嵌，退化为本机持久化

async function collectEmbeddedData() {
  const src = spec.spec.data && spec.spec.data.source
  if (!src || src.type !== 'user') return null
  try {
    const snap = await snapshotData(src)
    if (!snap.ok || !snap.csv) return null
    if (snap.csv.length > EMBED_LIMIT) {
      ElMessage.warning('数据超过 8MB，项目文件未内嵌；请在本机打开（数据已落盘）或先导出 CSV')
      return null
    }
    let ops = []
    try {
      const ed = await getEdits(`user:${src.id}`)
      ops = ed.ops || []
    } catch { /* 编辑读取失败不影响保存 */ }
    return { sourceKey: `user:${src.id}`, label: snap.label, csv: snap.csv, edits: ops }
  } catch (e) {
    ElMessage.warning('数据快照失败：' + e.message)
    return null
  }
}

async function saveProject() {
  const embedded = await collectEmbeddedData()
  const payload = {
    app: 'ggplotgui',
    format: PROJECT_FORMAT,
    savedAt: new Date().toISOString(),
    spec: spec.spec,
    data: embedded
  }
  const blob = new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' })
  downloadBlob(blob, `ggplotgui-project-${Date.now()}.json`)
  spec.markSaved()
  ElMessage.success(embedded ? '项目已保存（含数据与手工编辑）' : '项目已保存')
}

function loadProjectClick() {
  const input = document.createElement('input')
  input.type = 'file'
  input.accept = '.json'
  input.onchange = async () => {
    const f = input.files[0]
    if (!f) return
    try {
      const obj = JSON.parse(await f.text())
      const isEnvelope = !!(obj && obj.app === 'ggplotgui' && obj.spec)
      const project = isEnvelope ? obj : { spec: obj, data: null }
      const src = project.spec && project.spec.data && project.spec.data.source
      const embedded = project.data

      // 内嵌数据且本地没有这条数据记录（换机器 / 清过上传缓存）→ 自动重建
      const known = src && src.type === 'user' &&
        data.sources.some(s => s.type === 'user' && s.name === src.id)
      if (embedded && embedded.csv && src && src.type === 'user' && !known) {
        const res = await pasteData(embedded.csv, embedded.label || '项目内嵌数据')
        const newId = res.source && res.source.id
        if (!newId) throw new Error(res.error || '内嵌数据恢复失败')
        project.spec.data.source = { type: 'user', id: newId }
        if (Array.isArray(embedded.edits) && embedded.edits.length) {
          await importEdits(project.spec.data.source, embedded.edits)
        }
        await data.load()
      }

      spec.loadProject(project.spec)
      // 项目里的数据源要同步到左侧数据面板，否则列/预览与 spec 不一致
      const finalSrc = spec.spec.data && spec.spec.data.source
      if (finalSrc && finalSrc.type === 'dataset') await data.select(`dataset:${finalSrc.name}`)
      else if (finalSrc && finalSrc.type === 'user' &&
               data.sources.some(s => s.type === 'user' && s.name === finalSrc.id)) {
        await data.select(`user:${finalSrc.id}`)
      }
      spec.markSaved()   // 载入即视为当前内容与文件一致
      ElMessage.success(embedded ? '项目已载入（含内嵌数据）' : '项目已载入')
      spec.renderNow()
    } catch (e) {
      ElMessage.error('载入失败: ' + e.message)
    }
  }
  input.click()
}
async function clearCanvas() {
  try {
    await ElMessageBox.confirm('将清空图层、标度、主题等全部绘图设置（保留当前数据选择），且可通过撤销恢复。', '清空画布', {
      type: 'warning', confirmButtonText: '清空', cancelButtonText: '取消'
    })
  } catch { return }
  spec.pushHistory()
  const keep = JSON.parse(JSON.stringify(spec.spec.data))
  spec.reset()
  spec.spec.data = keep
  spec.markSaved()
  ElMessage.success('画布已恢复空白（可 Ctrl+Z 撤销）')
}
function onProjectCmd(cmd) {
  if (cmd === 'save') saveProject()
  else if (cmd === 'load') loadProjectClick()
  else if (cmd === 'clear') clearCanvas()
}
</script>

<template>
  <!-- 启动加载页：元数据枚举约 0.5–1s，避免整屏白闪；失败时停留在此并可重试 -->
  <div v-if="!meta.loaded" class="gg-boot">
    <div class="gg-boot-logo">ggplotGUI</div>
    <template v-if="!meta.error">
      <div class="gg-boot-row">
        <el-icon class="is-loading" :size="18"><Loading /></el-icon>
        <span>正在加载绘图能力…</span>
      </div>
    </template>
    <template v-else>
      <div class="gg-boot-row">后端服务不可用</div>
      <el-button size="small" @click="boot">重试</el-button>
    </template>
  </div>

  <div v-else class="gg-layout">
    <header class="gg-header">
      <div class="h-left">
        <div class="gg-logo" :title="`ggplot2 ${meta.ggplot2Version}`">
          <b>ggplotGUI</b>
        </div>
      </div>

      <div class="h-mid" title="渲染控制">
        <el-tooltip content="自动渲染：修改后自动出图；关闭后用右侧按钮手动渲染">
          <el-switch v-model="spec.autoRender" size="small" />
        </el-tooltip>
        <span class="h-mid-label" :class="{ off: !spec.autoRender }">
          {{ spec.autoRender ? '自动渲染' : '手动渲染' }}
        </span>
        <el-button type="primary" size="small" :loading="spec.rendering" @click="spec.renderNow()">
          <el-icon class="el-icon--left"><MagicStick /></el-icon>渲染
        </el-button>
      </div>

      <div class="h-right">
        <el-tooltip :content="saveHint">
          <span class="gg-save-state" :class="{ dirty: spec.dirty, empty: !spec.spec.layers.length }">
            <i class="dot" />{{ saveLabel }}
          </span>
        </el-tooltip>
        <el-dropdown trigger="click" @command="onProjectCmd">
          <el-button text class="h-dd">
            <el-icon><FolderOpened /></el-icon>项目<el-icon><ArrowDown /></el-icon>
          </el-button>
          <template #dropdown>
            <el-dropdown-menu>
              <el-dropdown-item command="save">
                <el-icon><FolderAdd /></el-icon>保存项目 (JSON)
              </el-dropdown-item>
              <el-dropdown-item command="load">
                <el-icon><FolderOpened /></el-icon>载入项目
              </el-dropdown-item>
              <el-dropdown-item command="clear" divided>
                <el-icon><Delete /></el-icon>清空画布（恢复默认）
              </el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <el-tooltip content="暗色模式"><el-button text @click="toggleDark">
          <el-icon><component :is="spec.dark ? 'Sunny' : 'Moon'" /></el-icon></el-button>
        </el-tooltip>
      </div>
    </header>

    <!-- 未保存草稿恢复条：上次异常退出/误关时出现 -->
    <div v-if="draftOffer" class="gg-recover">
      <el-icon><WarningFilled /></el-icon>
      <span>发现上次未保存的草稿（{{ draftTime }}）</span>
      <span class="gg-recover-sub">恢复后会以「未保存」状态打开</span>
      <el-button size="small" type="primary" @click="restoreDraft">恢复草稿</el-button>
      <el-button size="small" text @click="discardDraft">丢弃</el-button>
    </div>

    <div class="gg-main">
      <div v-show="ui.leftOpen" class="gg-left"><DataPanel /></div>
      <button v-show="!ui.leftOpen" class="gg-side-strip" title="展开数据面板"
        @click="ui.toggleLeft()">
        <el-icon><ArrowRight /></el-icon>
      </button>

      <div class="gg-center"><Canvas /></div>

      <button v-show="!ui.rightOpen" class="gg-side-strip" title="展开控制面板"
        @click="ui.toggleRight()">
        <el-icon><ArrowLeft /></el-icon>
      </button>
      <div v-show="ui.rightOpen" class="gg-right"><EditorTabs /></div>
    </div>
  </div>
</template>
