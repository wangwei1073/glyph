<script setup>
// 高级面板：原始代码模式 / plotly / 扩展状态
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { usePinStore } from '../stores/pins'
import { rawRender, formatCode } from '../api'

const spec = useSpecStore()
const meta = useMetaStore()
const pins = usePinStore()
const saveVisible = ref(false)
const saveLabel = ref('')
const savingPin = ref(false)

// ---- CodeMirror 原始代码编辑器 ----
const editorEl = ref(null)
let editor = null
let EditorView, rMode, oneDark

const rawCode = ref('')
const rawRunning = ref(false)
const consoleClass = computed(() => ({ hasErr: !!(spec.last && spec.last.error) }))

async function initEditor() {
  if (editor) return editor
  if (!initPromise) initPromise = buildEditor()
  return initPromise
}

let initPromise = null
async function buildEditor() {
  const [{ EditorState }, { EditorView: EV, keymap, lineNumbers, highlightActiveLine }, { StreamLanguage }, { r }, { oneDark: od }, { defaultKeymap, history, historyKeymap, indentWithTab, undo, redo, toggleComment }] = await Promise.all([
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
        keymap.of([...defaultKeymap, ...historyKeymap, indentWithTab,
          { key: 'Mod-/', run: (v) => { toggleCommentLines(v); return true } },
          { key: 'Mod-Shift-f', run: () => { formatNow(); return true } }]),
        StreamLanguage.define(r),
        EditorView.lineWrapping,
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

async function copyCode() {
  if (!rawCode.value.trim()) return ElMessage.warning('代码为空')
  try {
    await navigator.clipboard.writeText(rawCode.value)
    ElMessage.success('代码已复制')
  } catch { ElMessage.error('复制失败（浏览器不允许剪贴板）') }
}

async function formatNow() {
  if (!rawCode.value.trim()) return ElMessage.warning('代码为空')
  try {
    const res = await formatCode(rawCode.value)
    rawCode.value = res.code
    await initEditor()
    editor.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: res.code } })
    ElMessage.success('已格式化（styler）')
  } catch (e) { ElMessage.error('格式化失败：' + e.message) }
}

function downloadCode() {
  const blob = new Blob([rawCode.value], { type: 'text/plain;charset=utf-8' })
  const a = document.createElement('a')
  a.href = URL.createObjectURL(blob)
  a.download = 'plot.R'
  a.click()
  setTimeout(() => URL.revokeObjectURL(a.href), 2000)
}

watch(() => spec.pendingCode, async (code) => {
  if (!code) return
  rawCode.value = code
  await initEditor()
  editor.dispatch({ changes: { from: 0, to: editor.state.doc.length, insert: code } })
  spec.pendingCode = ''
})

function packagesFromCode(code) {
  return [...String(code).matchAll(/library\(\s*["']?([A-Za-z0-9._]+)/g)].map(m => m[1])
}

async function saveToGallery() {
  if (!rawCode.value.trim()) return ElMessage.warning('代码为空')
  if (!spec.last || !spec.last.pngUrl) return ElMessage.warning('先运行一次代码，生成可保存的预览图')
  savingPin.value = true
  try {
    const sd = spec.spec.data
    await pins.saveCode({
      label: saveLabel.value || '代码图',
      code: rawCode.value,
      packages: packagesFromCode(rawCode.value),
      source: sd.source,
      prep: {
        filter: sd.filter || '', filterDisabled: !!sd.filterDisabled,
        mutate: sd.mutate || [], sample: sd.sample, sampleDisabled: !!sd.sampleDisabled,
        seed: sd.seed, types: sd.types || [], text: sd.text || [],
        outliers: sd.outliers || [], fillna: sd.fillna || [],
        dropnaCols: sd.dropnaCols || [], dropnaHow: sd.dropnaHow || 'any',
        dropnaDisabled: !!sd.dropnaDisabled, dedupCols: sd.dedupCols || [],
        dedupEnabled: !!sd.dedupEnabled
      },
      renderOpts: { ...spec.renderOpts },
      pngUrl: spec.last.pngUrl
    })
    saveVisible.value = false
    ElMessage.success('已存入图库（代码图）')
  } catch (e) {
    ElMessage.error('保存失败：' + e.message)
  } finally { savingPin.value = false }
}

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

async function runCode(code, successMsg = '渲染成功') {
  if (!code.trim()) {
    ElMessage.warning('代码为空：先「载入当前图形的生成代码」或直接输入 R 代码')
    return
  }
  rawRunning.value = true
  try {
    const res = await rawRender(code, spec.spec, spec.renderOpts)
    if (res.ok) {
      spec.last = { ok: true, pngUrl: res.pngUrl || null, png: res.png || null, code, warnings: res.warnings || [], messages: [], error: null, elapsed: res.elapsedMs || 0 }
      ElMessage.success(`${successMsg} (${res.elapsedMs}ms)`)
    } else {
      ElMessage.error(String(res.error).slice(0, 300))
    }
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    rawRunning.value = false
  }
}

function runRaw() { return runCode(rawCode.value) }

function runSelection() {
  const sel = editor && editor.state.selection.main
  const text = sel ? editor.state.sliceDoc(sel.from, sel.to) : ''
  if (!text.trim()) return ElMessage.warning('先在编辑器里选中要运行的代码')
  runCode(text, '选中代码渲染成功')
}

function doUndo() { if (editor) undo(editor) }
function doRedo() { if (editor) redo(editor) }

function toggleCommentLines(view) {
  if (!view) return
  const sel = view.state.selection.main
  const first = view.state.doc.lineAt(sel.from)
  const last = view.state.doc.lineAt(sel.to)
  const lines = []
  for (let n = first.number; n <= last.number; n++) lines.push(view.state.doc.line(n))
  const allCommented = lines.every(l => /^\s*#/.test(l.text))
  view.dispatch({
    changes: lines.map(l => ({
      from: l.from,
      to: l.to,
      insert: allCommented
        ? l.text.replace(/^(\s*)#\s?/, '$1')
        : l.text.replace(/^(\s*)/, '$1# ')
    }))
  })
}
function doComment() { toggleCommentLines(editor) }

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
  <div class="gg-tab-scroll adv-root">
    <div class="gg-subhead">原始代码模式（完全自由，直接运行 R 代码；数据通过 df 变量使用）</div>
    <div class="adv-pad">
      <el-button size="small" @click="loadFromSpec">
        <el-icon><Download /></el-icon>载入当前图形的生成代码
      </el-button>
      <el-button size="small" type="primary" :loading="rawRunning" @click="runRaw">
        <el-icon><VideoPlay /></el-icon>运行代码 (Ctrl+Enter)
      </el-button>
      <el-button size="small" @click="runSelection" title="运行选中的代码">运行选中</el-button>
      <el-button size="small" text @click="doUndo" title="撤销">撤销</el-button>
      <el-button size="small" text @click="doRedo" title="重做">重做</el-button>
      <el-button size="small" text @click="doComment" title="注释 / 取消注释 (Ctrl+/)">注释</el-button>
      <el-button size="small" @click="copyCode">复制</el-button>
      <el-button size="small" @click="formatNow">格式化</el-button>
      <el-button size="small" @click="downloadCode">下载 .R</el-button>
      <el-button size="small" type="primary" plain @click="saveVisible = true">存入图库</el-button>
    </div>
    <div ref="editorEl" class="cm-editor-box" @keydown.ctrl.enter.prevent="runRaw" />
    <div class="adv-console" :class="consoleClass">
      <div class="adv-console-head">
        <span>输出</span>
        <span class="gg-hint">
          {{ spec.last && spec.last.ok ? `运行成功 · ${spec.last.elapsed}ms` : '尚未运行' }}
          · 图形显示在中间画布
        </span>
      </div>
      <div v-if="spec.last && spec.last.error" class="adv-line err">{{ spec.last.error }}</div>
      <div v-for="(w, i) in (spec.last && spec.last.warnings) || []" :key="'w' + i" class="adv-line warn">警告：{{ w }}</div>
      <div v-for="(m, i) in (spec.last && spec.last.messages) || []" :key="'m' + i" class="adv-line">{{ m }}</div>
      <div v-if="!spec.last || (!spec.last.error && !(spec.last.warnings || []).length)" class="adv-line muted">
        {{ spec.last && spec.last.ok ? '无错误、无警告。' : '运行后可在此查看错误与警告。' }}
      </div>
    </div>

    <div class="adv-meta-line">
      {{ spec.renderOpts.width }} × {{ spec.renderOpts.height }} @ {{ spec.renderOpts.dpi }} dpi
      · 尺寸在画布顶部工具栏调整 · 当前 df 已应用数据准备
    </div>

    <el-dialog v-model="saveVisible" title="存入图库（代码图）" width="420" append-to-body>
      <div class="gg-hint" style="margin-bottom:8px">将保存：代码 + 当前数据快照 + 预览图。</div>
      <el-input v-model="saveLabel" size="small" placeholder="名称" />
      <template #footer>
        <el-button @click="saveVisible = false">取消</el-button>
        <el-button type="primary" :loading="savingPin" @click="saveToGallery">保存</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.adv-pad { padding: 0 12px; display: flex; flex-wrap: wrap; gap: 6px; }
.adv-pad .el-button { margin-left: 0; }
.cm-editor-box {
  margin: 8px 12px; border: 1px solid var(--gg-border); border-radius: var(--gg-r-ctl);
  overflow: hidden; flex: 1 1 auto; min-height: 240px; font-size: 13px;
}
.cm-editor-box :deep(.cm-editor) { height: 100%; }
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
.adv-console { margin: 8px 12px 4px; border: 1px solid var(--gg-border); border-radius: var(--gg-r-ctl); background: #fbfcfe; padding: 6px 8px; }
.adv-console.hasErr { border-color: #f3c4c0; background: #fef7f6; }
.adv-console-head { display: flex; align-items: center; gap: 8px; font-size: 11.5px; color: var(--gg-text-3); font-weight: 600; }
.adv-line { font-family: Consolas, monospace; font-size: 11.5px; color: var(--gg-text-2); padding: 3px 0; white-space: pre-wrap; }
.adv-line.err { color: #c0392b; }
.adv-line.warn { color: #b7791f; }
.adv-line.muted { color: var(--gg-text-4); font-family: inherit; }
.adv-meta { margin: 4px 12px 8px; }
.adv-root { display: flex; flex-direction: column; height: 100%; }
.adv-root .cm-editor-box { margin-bottom: 4px; }
.adv-meta-line { margin: 0 12px 8px; font-size: 11px; color: var(--gg-text-4); }
</style>
