<script setup>
// 高级面板：原始代码模式 / plotly / 扩展状态
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { ElMessage } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { rawRender } from '../api'

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

const extList = [
  { key: 'ggthemes', label: 'ggthemes 主题/标度' },
  { key: 'ggsci', label: 'ggsci 学术配色' },
  { key: 'ggrepel', label: 'ggrepel 防重叠标签' },
  { key: 'patchwork', label: 'patchwork 拼图', note: '库可用（多图面板后续接入）' },
  { key: 'plotly', label: 'plotly 交互预览' }
]
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">原始代码模式（完全自由，直接运行 R 代码；数据通过 df 变量使用）</div>
    <div style="padding: 0 12px">
      <el-button size="small" @click="loadFromSpec">
        <el-icon><Download /></el-icon>载入当前图形的生成代码
      </el-button>
      <el-button size="small" type="primary" :loading="rawRunning" @click="runRaw">
        <el-icon><VideoPlay /></el-icon>运行代码 (Ctrl+Enter)
      </el-button>
    </div>
    <div ref="editorEl" class="cm-editor-box" @keydown.ctrl.enter.prevent="runRaw" />
    <div style="padding:4px 12px; font-size:11.5px; color:var(--el-text-color-secondary)">
      当前数据的加工结果绑定在变量 <code class="gg-mono">df</code> 上；修改代码后点运行即可覆盖预览。
    </div>

    <div class="gg-subhead" style="margin-top:16px">已集成扩展</div>
    <div style="padding: 0 12px">
      <div v-for="e in extList" :key="e.key" class="ext-row">
        <el-tag size="small" :type="meta.ext[e.key] ? 'success' : 'info'">
          {{ meta.ext[e.key] ? '已启用' : '未安装' }}
        </el-tag>
        <span style="margin-left:8px">{{ e.label }}</span>
        <span v-if="e.note" style="margin-left:6px;font-size:11px;color:var(--el-text-color-secondary)">{{ e.note }}</span>
      </div>
      <div style="padding-top:6px;font-size:11.5px;color:var(--el-text-color-secondary)">
        启用方式：ggrepel 的 geom 在「图层」、ggsci/ggthemes 的标度在「标度」、
        ggthemes 主题在「主题」面板中直接选择；plotly 在画布「交互预览」使用。
      </div>
    </div>

    <div class="gg-subhead" style="margin-top:16px">渲染设置</div>
    <div class="p-row">
      <label>预览尺寸</label>
      <span style="font-size:12px">
        {{ spec.renderOpts.width }} × {{ spec.renderOpts.height }} @ {{ spec.renderOpts.dpi }} dpi
        （在画布顶部工具栏调整）
      </span>
    </div>
    <div class="p-row">
      <label>数据行数</label>
      <span style="font-size:12px">当前渲染使用的 df 已应用筛选/新增列/抽样</span>
    </div>
  </div>
</template>

<style scoped>
.cm-editor-box {
  margin: 8px 12px; border: 1px solid var(--gg-border); border-radius: 6px;
  overflow: hidden; max-height: 340px; font-size: 12.5px;
}
.cm-editor-box :deep(.cm-editor) { max-height: 340px; }
.cm-editor-box :deep(.cm-scroller) { overflow: auto; }
.ext-row { display: flex; align-items: center; padding: 4px 0; font-size: 12.5px; }
</style>
