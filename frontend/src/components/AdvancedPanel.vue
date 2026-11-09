<script setup>
// 高级面板：原始代码模式 / plotly / 扩展状态
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { rawRender, toggleExtension, installExtension, getInstallStatus } from '../api'

const spec = useSpecStore()
const meta = useMetaStore()

// ---- CodeMirror 原始代码编辑器 ----
const editorEl = ref(null)
let editor = null
let EditorView, rMode, oneDark

const rawCode = ref('')
const rawRunning = ref(false)

async function initEditor() {
  if (editor) return editor
  if (!initPromise) initPromise = buildEditor()
  return initPromise
}

let initPromise = null
async function buildEditor() {
  const [{ EditorState }, { EditorView: EV, keymap, lineNumbers, highlightActiveLine }, { StreamLanguage }, { r }, { oneDark: od }, { defaultKeymap, history, historyKeymap, indentWithTab }] = await Promise.all([
    import('@codemirror/state'),
    import('@codemirror/view'),
    import('@codemirror/language'),
    import('@codemirror/legacy-modes/mode/r'),
    import('@codemirror/theme-one-dark'),
    import('@codemirror/commands')
  ])
  EditorView = EV
  rMode = r
  oneDark = od
  editor = new EditorView({
    parent: editorEl.value,
    state: EditorState.create({
      doc: rawCode.value,
      extensions: [
        lineNumbers(),
        highlightActiveLine(),
        history(),
        keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab]),
        StreamLanguage.define(r),
        oneDark,
        EditorView.updateListener.of((u) => {
          if (u.docChanged) rawCode.value = u.state.doc.toString()
        })
      ]
    })
  })
  return editor
}

// 面板由 EditorTabs 用 v-show 挂载，DOM 一开始就在，可直接初始化
onMounted(() => { initEditor().catch((e) => ElMessage.error('代码编辑器初始化失败: ' + e.message)) })
onBeforeUnmount(() => {
  if (editor) { editor.destroy(); editor = null; initPromise = null }
})

async function loadFromSpec() {
  const code = spec.last.code
  if (!code) {
    ElMessage.warning('当前没有可载入的生成代码，先渲染一次图形')
    return
  }
  rawCode.value = code
  await initEditor()
  editor.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: code } })
}

async function runRaw() {
  if (!rawCode.value.trim()) {
    ElMessage.warning('代码为空：先「载入当前图形的生成代码」或直接输入 R 代码')
    return
  }
  rawRunning.value = true
  try {
    const res = await rawRender(rawCode.value, spec.spec, spec.renderOpts)
    if (res.ok) {
      spec.last = { ok: true, pngUrl: res.pngUrl || null, png: res.png || null, code: rawCode.value, warnings: res.warnings || [], messages: [], error: null, elapsed: res.elapsedMs || 0 }
      ElMessage.success(`渲染成功 (${res.elapsedMs}ms)`)
    } else {
      ElMessage.error(String(res.error).slice(0, 300))
    }
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    rawRunning.value = false
  }
}

// 扩展清单：来自后端 /api/meta 的 extensionCatalog（含安装/启用状态与说明）
// 开关只对「已安装」的扩展可用；关闭后后端会重建注册表，其组件从各面板消失
const extToggling = ref('')

async function toggleExt(ext, on) {
  if (!ext.installed) return
  extToggling.value = ext.id
  try {
    const res = await toggleExtension(ext.id, on)
    // 后端已返回重建后的 meta，直接套用避免二次请求
    if (res.meta) meta.applyMeta(res.meta)
    ElMessage.success(`${ext.label} 已${on ? '启用' : '关闭'}`)
    // 组件来源变了，需要重渲染以反映标度/主题等变化
    spec.renderNow()
  } catch (e) {
    ElMessage.error('切换失败: ' + e.message)
  } finally {
    extToggling.value = ''
  }
}

// 「入口」说明：按扩展提供的组件类型推导
function extWhere(e) {
  const map = {
    geom: '图层', scale: '标度', theme: '主题', guide: '标签 · 图例', annotation: '注释'
  }
  const parts = (e.kind || []).map(k => map[k]).filter(Boolean)
  if (e.id === 'patchwork') return '拼图（先「存入图库」）'
  if (e.id === 'plotly') return '画布「交互预览」'
  return parts.length ? [...new Set(parts)].join(' · ') : '—'
}

// ---- 一键安装（后台任务 + 轮询）----
const installing = ref('')       // 正在安装的包名
let installTimer = null

async function pollInstall() {
  installTimer = null
  try {
    const res = await getInstallStatus()
    const job = res.job || {}
    if (job.status === 'running') {
      installTimer = setTimeout(pollInstall, 1200)
      return
    }
    installing.value = ''
    if (job.status === 'done') {
      if (res.meta) meta.applyMeta(res.meta)
      ElMessage.success(`${job.pkg} 安装完成，扩展已可用`)
    } else if (job.status === 'failed') {
      ElMessageBox.alert(
        (job.message ? job.message + '\n\n' : '') + (job.log || '（无日志）'),
        `${job.pkg} 安装失败`, { customClass: 'install-log-box', confirmButtonText: '知道了' }
      )
    }
  } catch (e) {
    installing.value = ''
    ElMessage.error('查询安装状态失败：' + e.message)
  }
}

async function installPkg(pkg) {
  if (installing.value) return
  installing.value = pkg
  try {
    await installExtension(pkg)
    ElMessage.info(`开始安装 ${pkg}，完成后会自动刷新`)
    pollInstall()
  } catch (e) {
    installing.value = ''
    ElMessage.error('安装失败：' + e.message)
  }
}

onBeforeUnmount(() => { if (installTimer) clearTimeout(installTimer) })
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">原始代码模式（完全自由，直接运行 R 代码；数据通过 df 变量使用）</div>
    <div class="adv-pad">
      <el-button size="small" @click="loadFromSpec">
        <el-icon><Download /></el-icon>载入当前图形的生成代码
      </el-button>
      <el-button size="small" type="primary" :loading="rawRunning" @click="runRaw">
        <el-icon><VideoPlay /></el-icon>运行代码 (Ctrl+Enter)
      </el-button>
    </div>
    <div ref="editorEl" class="cm-editor-box" @keydown.ctrl.enter.prevent="runRaw" />
    <div class="gg-hint" style="padding: 4px 12px">
      当前数据的加工结果绑定在变量 <code class="gg-mono">df</code> 上；修改代码后点运行即可覆盖预览。
    </div>

    <div class="gg-subhead gg-section-gap">扩展管理</div>
    <div class="adv-pad">
      <div v-for="e in (meta.extensionCatalog || [])" :key="e.id" class="ext-row">
        <el-switch :model-value="e.enabled" size="small"
          :disabled="!e.installed || extToggling === e.id"
          :loading="extToggling === e.id"
          @update:model-value="(v) => toggleExt(e, v)" />
        <span class="ext-name" :class="{ off: !e.enabled }">{{ e.label }}</span>
        <template v-if="!e.installed">
          <el-tag size="small" type="info" :disable-transitions="true">未安装</el-tag>
          <el-button size="small" text class="ext-install" :loading="installing === e.pkg"
            :disabled="!!installing && installing !== e.pkg" @click="installPkg(e.pkg)">安装</el-button>
        </template>
        <template v-else-if="e.missingDeps && e.missingDeps.length">
          <el-tooltip :content="`缺少运行期依赖：${e.missingDeps.join('、')}；安装后才能正常出图`" placement="top">
            <el-tag size="small" type="warning" :disable-transitions="true">
              缺依赖 {{ e.missingDeps.join('、') }}
            </el-tag>
          </el-tooltip>
          <el-button size="small" text class="ext-install" :loading="installing === e.missingDeps[0]"
            :disabled="!!installing && installing !== e.missingDeps[0]"
            @click="installPkg(e.missingDeps[0])">安装 {{ e.missingDeps[0] }}</el-button>
        </template>
        <span v-else class="ext-where">{{ extWhere(e) }}</span>
      </div>
      <div class="gg-hint" style="padding-top: 6px">
        关闭扩展只会把它提供的组件从面板中移除（并重新生成注册表），不会卸载 R 包；
        生成的代码仍会自动带上 <code class="gg-mono">library(pkg)</code> 与
        <code class="gg-mono">pkg::</code> 前缀。
      </div>
    </div>

    <div class="gg-subhead gg-section-gap">渲染设置</div>
    <div class="p-row">
      <label>预览尺寸</label>
      <span class="gg-hint-md">
        {{ spec.renderOpts.width }} × {{ spec.renderOpts.height }} @ {{ spec.renderOpts.dpi }} dpi
        （在画布顶部工具栏调整）
      </span>
    </div>
    <div class="p-row">
      <label>数据行数</label>
      <span class="gg-hint-md">当前渲染使用的 df 已应用筛选/新增列/抽样</span>
    </div>
  </div>
</template>

<style scoped>
.adv-pad { padding: 0 12px; }
.cm-editor-box {
  margin: 8px 12px; border: 1px solid var(--gg-border); border-radius: var(--gg-r-ctl);
  overflow: hidden; max-height: 340px; font-size: 13px;
}
.cm-editor-box :deep(.cm-editor) { max-height: 340px; }
.cm-editor-box :deep(.cm-scroller) { overflow: auto; }
.ext-row { display: flex; align-items: center; gap: 4px; padding: 4px 0; font-size: 13px; }
.ext-name { margin-left: 4px; }
.ext-name.off { color: var(--el-text-color-secondary); }
.ext-where {
  margin-left: auto; padding-left: 10px; font-size: 11px; text-align: right;
  color: var(--gg-text-3); white-space: nowrap;
}
.ext-install {
  margin-left: auto; padding: 0 5px; height: 20px; font-size: 11px;
  color: var(--gg-brand); flex-shrink: 0;
}
</style>
