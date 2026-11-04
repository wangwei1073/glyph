<script setup>
// App：三段式顶栏（身份 / 中置渲染主控簇 / 项目与视图）
import { onMounted, onBeforeUnmount, watch } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useMetaStore } from './stores/meta'
import { useDataStore } from './stores/data'
import { useSpecStore } from './stores/spec'
import { usePinStore } from './stores/pins'
import { useUiStore } from './stores/ui'
import { downloadBlob } from './api'
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
  } catch (e) {
    ElMessage.error('后端服务不可用: ' + e.message)
  }
}

onMounted(async () => {
  window.addEventListener('keydown', onKeydown)
  await boot()
})
onBeforeUnmount(() => window.removeEventListener('keydown', onKeydown))

function toggleDark() {
  spec.dark = !spec.dark
  document.documentElement.classList.toggle('dark', spec.dark)
}

// ---- 项目操作 ----
function saveProject() {
  const blob = new Blob([spec.exportProject()], { type: 'application/json' })
  downloadBlob(blob, `ggplotgui-project-${Date.now()}.json`)
  ElMessage.success('项目已保存')
}
function loadProjectClick() {
  const input = document.createElement('input')
  input.type = 'file'
  input.accept = '.json'
  input.onchange = async () => {
    const f = input.files[0]
    if (!f) return
    try {
      spec.loadProject(JSON.parse(await f.text()))
      // 项目里的数据源要同步到左侧数据面板，否则列/预览与 spec 不一致
      const src = spec.spec.data && spec.spec.data.source
      if (src && src.type === 'dataset') await data.select(`dataset:${src.name}`)
      else if (src && src.type === 'user' && data.sources.some(s => s.type === 'user' && s.name === src.id)) {
        await data.select(`user:${src.id}`)
      }
      ElMessage.success('项目已载入')
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
