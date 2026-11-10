<script setup>
// App：三段式顶栏（身份 / 中置渲染主控簇 / 项目与视图）
import { computed, onMounted, onBeforeUnmount, ref, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useMetaStore } from './stores/meta'
import { useDataStore, buildPrep } from './stores/data'
import { useSpecStore } from './stores/spec'
import { usePinStore } from './stores/pins'
import { useUiStore } from './stores/ui'
import { downloadBlob, snapshotData, getEdits, importEdits, pasteData, rawRender, setWorkspace, takePendingCode } from './api'
import DataPanel from './components/DataPanel.vue'
import Canvas from './components/Canvas.vue'
import EditorTabs from './components/EditorTabs.vue'
import ActionBar from './components/ActionBar.vue'

const meta = useMetaStore()
const data = useDataStore()
const spec = useSpecStore()
const pins = usePinStore()
const ui = useUiStore()

// ---- 右侧栏宽度拖拽（持久化） ----
const rightWidth = ref(Number(localStorage.getItem('gg-right-w')) || 400)
const rightResizing = ref(false)
function startResize() {
  rightResizing.value = true
  document.body.style.cursor = 'col-resize'
  const move = (ev) => {
    const max = Math.round(window.innerWidth * 0.65)
    rightWidth.value = Math.min(max, Math.max(300, window.innerWidth - ev.clientX))
  }
  const up = () => {
    rightResizing.value = false
    document.body.style.cursor = ''
    localStorage.setItem('gg-right-w', String(rightWidth.value))
    window.removeEventListener('mousemove', move)
    window.removeEventListener('mouseup', up)
  }
  window.addEventListener('mousemove', move)
  window.addEventListener('mouseup', up)
}

// ---- 自动渲染（深度 watch spec + 渲染设置，550ms 防抖） ----
// 两种情况要区分开：
//   A) 只改了「画幅 / 尺寸」→ 当前代码图保持代码，按新尺寸重渲染
//   B) 改动了「绘图规格（图层/映射/主题/标度…）」→ 不影响正在展示的代码图
//
// 关于 B：代码图是由一段 R 代码绘制出来的，主题、配色、标度这些设置对它**完全无效**。
// 所以此时不应该按 spec 重新渲染 —— 那样只会把代码图替换掉（甚至因为 spec 没有图层
// 或参数不匹配而报错，画面直接空白）。
// 退出「代码图」状态改为显式动作：画布顶栏的「返回我的图」按钮。
let debounceTimer = null
// 项目载入流程自己管理渲染（载入 spec / rawRender / 收尾），期间抑制 watcher 触发的防抖渲染，
// 否则载入中途会与项目渲染并发，既浪费一次渲染也可能闪一下旧画面
let loadingProject = false
function scheduleRender(fromSpec = false) {
  if (!spec.autoRender) return
  if (loadingProject) return
  // 代码图状态下忽略 spec 改动（设置仍会保存进 spec，只是不改画面）
  if (fromSpec && spec.last && spec.last.renderedFromCode) return
  clearTimeout(debounceTimer)
  spec.renderQueued = true
  debounceTimer = setTimeout(() => {
    spec.renderQueued = false
    spec.renderNow()
  }, 550)
}
watch(() => spec.spec, () => scheduleRender(true), { deep: true })
watch(() => spec.renderOpts, () => scheduleRender(false), { deep: true })

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
    // 工作区存在时，项目标识由目录派生，保证「一个目录 = 一个项目」
    if (meta.workspace && meta.workspace.id) spec.setProjectId(meta.workspace.id)
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
  startCodePoll()
})
onBeforeUnmount(() => {
  window.removeEventListener('keydown', onKeydown)
  window.removeEventListener('beforeunload', onBeforeUnload)
  clearTimeout(draftTimer)
  clearInterval(codePollTimer)
})

// ---- 外部代码推送轮询 ----
// IDE / AI 等外部进程 POST /api/code/push 后，这里取走并填进「高级」页编辑器。
// 之所以用轮询而不是 WebSocket：后端 httpuv 单线程、无长连接机制，
// 1.5s 一次的空请求开销可以忽略，实现却简单得多。
let codePollTimer = null
let codePolling = false
// 后端失联检测：连续失败才提示（瞬时重启/卡顿不打扰），恢复时也告知一次
let pollFails = 0
let downNotified = false
function startCodePoll() {
  if (codePollTimer) return
  codePollTimer = setInterval(async () => {
    if (codePolling) return
    codePolling = true
    try {
      const res = await takePendingCode()
      pollFails = 0
      if (downNotified) {
        downNotified = false
        ElMessage.success('已重新连接 Glyph 后端')
      }
      if (res && res.ok && res.code) {
        // 走既有的 pendingCode 通道：AdvancedPanel 会把它填进编辑器
        spec.pendingCodeRun = !!res.run
        spec.pendingCode = res.code
        ui.setTab('adv')
        ElMessage.success(res.run
          ? '已接收外部推送的代码并运行'
          : '已接收外部推送的代码，可在「高级」页查看并运行')
      }
    } catch {
      pollFails++
      if (pollFails >= 4 && !downNotified) {
        downNotified = true
        pollFails = 0
        ElMessage.error('与 Glyph 后端失去联系（服务可能已退出）——请重新运行 run_app.bat 或 Rscript run.R')
      }
    }
    finally { codePolling = false }
  }, 1500)
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
  // mode 判定必须看 renderedFromCode：spec 模式渲染也会回填 last.code（后端生成的代码），
  // 只看 code 存在与否会把所有项目都存成 'code'，载入时走错分支
  const isCodePlot = !!(spec.last && spec.last.renderedFromCode && spec.last.code)
  const payload = {
    app: 'ggplotgui',
    format: PROJECT_FORMAT,
    savedAt: new Date().toISOString(),
    projectId: spec.projectId,
    mode: isCodePlot ? 'code' : 'spec',
    code: (spec.last && spec.last.code) || null,
    renderOpts: isCodePlot ? { ...spec.renderOpts } : null,
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
    loadingProject = true
    try {
      const obj = JSON.parse(await f.text())
      const isEnvelope = !!(obj && obj.app === 'ggplotgui' && obj.spec)
      const project = isEnvelope ? obj : { spec: obj, data: null }
      const src = project.spec && project.spec.data && project.spec.data.source
      const embedded = project.data
      if (isEnvelope && project.projectId) spec.setProjectId(project.projectId)

      // 内嵌数据且本地没有这条数据记录（换机器 / 清过上传缓存）→ 自动重建
      const known = src && src.type === 'user' &&
        data.sources.some(s => s.type === 'user' && s.name === src.id)
      if (embedded && embedded.csv && src && src.type === 'user' && !known) {
        const res = await pasteData(embedded.csv, embedded.label || '项目内嵌数据')
        const newId = res.source && res.source.id
        if (!newId) throw new Error(res.error || '内嵌数据恢复失败')
        project.spec.data.source = { type: 'user', id: newId }
        if (Array.isArray(embedded.edits) && embedded.edits.length) {
          // 带上当前加工参数：行锚基于「原始数据 + prep」的行序，校验语义与编辑时一致
          await importEdits(project.spec.data.source, embedded.edits, buildPrep(spec.spec.data))
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
      let renderedCode = false
      if (project.mode === 'code' && project.code) {
        spec.renderOpts = { ...spec.renderOpts, ...(project.renderOpts || {}) }
        spec.pendingCode = project.code
        const rr = await rawRender(project.code, spec.spec, spec.renderOpts)
        if (rr.ok) {
          spec.last = { ok: true, pngUrl: rr.pngUrl || null, png: rr.png || null,
            code: project.code, warnings: rr.warnings || [], messages: [], error: null,
            elapsed: rr.elapsedMs || 0,
            // 标记来源：否则后续的 resize/尺寸改动会按 spec 重渲染，把代码图顶掉
            renderedFromCode: true }
          renderedCode = true
        } else {
          ElMessage.warning('代码图渲染失败：' + (rr.error || '未知错误'))
        }
      }
      spec.markSaved()   // 载入即视为当前内容与文件一致
      ElMessage.success(embedded ? '项目已载入（含内嵌数据）' : '项目已载入')
      if (renderedCode) {
        // 代码图已按原样渲染完成：取消载入 spec 触发的防抖渲染，
        // 也不要再用 spec（空的/旧配置）渲染覆盖它
        clearTimeout(debounceTimer)
      } else {
        spec.renderNow()
      }
    } catch (e) {
      ElMessage.error('载入失败: ' + e.message)
    } finally {
      loadingProject = false
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
  else if (cmd === 'workspace') switchWorkspace()
}

// 切换工作区（项目目录）：图库、上传数据、编辑记录都跟着目录走
async function switchWorkspace() {
  const cur = meta.workspace?.root || ''
  let dir
  try {
    const r = await ElMessageBox.prompt(
      '输入项目目录的绝对路径。图库、上传的数据与编辑记录都会存放在该目录下。\n留空表示退回 Glyph 安装目录。',
      '切换工作目录',
      {
        confirmButtonText: '切换', cancelButtonText: '取消',
        inputValue: cur, inputPlaceholder: 'C:\\my-project 或 /home/me/project',
        inputValidator: () => true
      }
    )
    dir = r.value
  } catch { return }
  if (dir === undefined || dir === null) return
  try {
    const res = await setWorkspace(String(dir).trim())
    if (!res.ok) throw new Error(res.error || '切换失败')
    meta.workspace = res.workspace
    // projectId 跟随工作区：同一目录在任何浏览器上都对应同一份图库视图
    if (res.workspace?.id) spec.setProjectId(res.workspace.id)
    pins.all = res.pins || []
    // 画布来源的图库条目属于旧工作区：清掉，否则「存入图库」会去更新一条不在新项目里的旧图
    //（后端会兜底新建，但标签对不上，用户看不出发生了什么）
    spec.sourcePinId = ''
    spec.sourcePinLabel = ''
    await data.load()
    // 目录变了，画布上引用旧数据源的图需要用户重新选择，这里只提示不自动改
    ElMessage.success(`工作区已切换到：${res.workspace.root}`)
  } catch (e) {
    ElMessage.error('切换工作区失败：' + e.message)
  }
}
</script>

<template>
  <!-- 启动加载页：元数据枚举约 0.5–1s，避免整屏白闪；失败时停留在此并可重试 -->
  <div v-if="!meta.loaded" class="gg-boot">
    <div class="gg-boot-logo">Glyph</div>
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
    <!-- 未保存草稿恢复条：上次异常退出/误关时出现 -->
    <div v-if="draftOffer" class="gg-recover">
      <el-icon><WarningFilled /></el-icon>
      <span>发现上次未保存的草稿（{{ draftTime }}）</span>
      <span class="gg-recover-sub">恢复后会以「未保存」状态打开</span>
      <el-button size="small" type="primary" @click="restoreDraft">恢复草稿</el-button>
      <el-button size="small" text @click="discardDraft">丢弃</el-button>
    </div>

    <div class="gg-main">
      <div v-show="ui.leftOpen" class="gg-left">
        <DataPanel @project="onProjectCmd" />
      </div>
      <div v-show="!ui.leftOpen" class="gg-left-mini">
        <button class="gg-mini-toggle" title="展开数据面板" @click="ui.toggleLeft()">
          <el-icon><ArrowRight /></el-icon>
        </button>
        <div class="gg-mini-spacer" />
        <!-- 左栏收起时：工具区停靠在窄栏底部，图标纵向排列 -->
        <ActionBar mini @project="onProjectCmd" />
      </div>

      <div class="gg-center"><Canvas /></div>

      <button v-show="!ui.rightOpen" class="gg-side-strip" title="展开控制面板"
        @click="ui.toggleRight()">
        <el-icon><ArrowLeft /></el-icon>
      </button>
      <div v-show="ui.rightOpen" class="gg-resizer" :class="{ active: rightResizing }" title="拖动调整宽度" @mousedown.prevent="startResize"><span class="gg-rbar" /></div>
      <div v-show="ui.rightOpen" class="gg-right" :style="{ width: rightWidth + 'px' }"><EditorTabs /></div>
    </div>
  </div>
</template>
