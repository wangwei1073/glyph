<script setup>
// 共享代码编辑器（CodeMirror 6，R 语法）
// 两处复用：
//   - 画布「代码」页签：只读展示生成的代码（readonly=true）
//   - 高级页「原始代码模式」：可编辑、可运行（readonly=false）
// 组件只负责「编辑/展示 + 高亮/行号/换行」，具体动作（运行/格式化/存图库）由父组件决定。
import { ref, computed, watch, onMounted, onBeforeUnmount } from 'vue'

const props = defineProps({
  modelValue: { type: String, default: '' },
  readonly: { type: Boolean, default: false },
  // 高度策略：'fill' 撑满父容器（高级页），'auto' 按内容高度（代码页签）
  height: { type: String, default: 'fill' },
  placeholder: { type: String, default: '' }
})
const emit = defineEmits(['update:modelValue', 'ready', 'run', 'save'])

const host = ref(null)
let view = null
let initPromise = null
let mods = null

const wrapClass = computed(() => ['cm-host', `cm-host--${props.height}`, { 'cm-host--ro': props.readonly }])

async function init() {
  if (view) return view
  if (!initPromise) initPromise = build()
  return initPromise
}

async function build() {
  const [{ EditorState }, { EditorView, keymap, lineNumbers, highlightActiveLine, drawSelection }, { StreamLanguage }, { r }, { oneDark }, { defaultKeymap, history, historyKeymap, indentWithTab, toggleComment }] = await Promise.all([
    import('@codemirror/state'),
    import('@codemirror/view'),
    import('@codemirror/language'),
    import('@codemirror/legacy-modes/mode/r'),
    import('@codemirror/theme-one-dark'),
    import('@codemirror/commands')
  ])
  mods = { EditorState, EditorView, toggleComment }

  const extensions = [
    lineNumbers(),
    highlightActiveLine(),
    drawSelection(),
    StreamLanguage.define(r),
    EditorView.lineWrapping,
    oneDark,
    EditorView.theme({
      '&': { fontSize: '13px', height: '100%' },
      '.cm-scroller': { overflow: 'auto', fontFamily: 'Consolas, "JetBrains Mono", monospace' },
      '.cm-content': { padding: '8px 0' }
    })
  ]

  if (props.readonly) {
    // 只读：可选择、可复制，但不能改
    extensions.push(EditorState.readOnly.of(true))
    extensions.push(EditorView.editable.of(false))
  } else {
    extensions.push(history())
    extensions.push(keymap.of([
      ...defaultKeymap, ...historyKeymap, indentWithTab,
      { key: 'Mod-/', run: (v) => { mods.toggleComment(v); return true } },
      { key: 'Mod-Enter', run: () => { emit('run'); return true } },
      { key: 'Mod-s', run: () => { emit('save'); return true } }
    ]))
  }

  if (!props.readonly) {
    extensions.push(EditorView.updateListener.of((u) => {
      if (u.docChanged) emit('update:modelValue', u.state.doc.toString())
    }))
  }

  view = new EditorView({
    parent: host.value,
    state: EditorState.create({ doc: props.modelValue, extensions })
  })
  // 应用初始化期间被挂起的值（父组件可能在 view 就绪前就赋过值）
  if (pendingValue !== null && pendingValue !== view.state.doc.toString()) {
    view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: pendingValue } })
    pendingValue = null
  }
  emit('ready', view)
  return view
}

// 外部值变化 → 同步到编辑器（避免光标跳动：仅当内容确实不同才 dispatch）
// 注意：初始化是异步的（动态 import CodeMirror），若父组件在 view 就绪前就改了值，
// 这里必须把值挂起，等 build() 完成后再应用，否则会丢内容。
let pendingValue = null

watch(() => props.modelValue, (val) => {
  if (!view) { pendingValue = val; return }
  if (val === view.state.doc.toString()) return
  view.dispatch({ changes: { from: 0, to: view.state.doc.length, insert: val || '' } })
})

defineExpose({
  getView: () => view,
  focus: () => view?.focus(),
  scrollToTop: () => view?.dispatch({ selection: { anchor: 0 }, scrollIntoView: true }),
  // 全选全文，便于「复制」按钮在无法访问剪贴板时降级
  selectAll: () => { if (view) view.dispatch({ selection: { anchor: 0, head: view.state.doc.length } }) }
})

onMounted(() => { init().catch(() => {}) })
onBeforeUnmount(() => {
  if (view) { view.destroy(); view = null; initPromise = null }
})
</script>

<template>
  <div ref="host" :class="wrapClass" />
</template>

<style scoped>
.cm-host { width: 100%; min-width: 0; overflow: hidden; }
/* 撑满父容器（高级页）：父级需有确定高度 */
.cm-host--fill { height: 100%; }
/* 按内容高度（代码页签）：外层滚动 */
.cm-host--auto :deep(.cm-editor) { height: auto; }
.cm-host--auto :deep(.cm-scroller) { overflow: visible; }
.cm-host :deep(.cm-editor) { height: 100%; }
.cm-host :deep(.cm-editor.cm-focused) { outline: none; }
</style>
