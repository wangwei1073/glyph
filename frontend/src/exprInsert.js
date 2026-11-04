// 表达式插入（共享模块）：DataPanel 注册聚焦的表达式输入框，其他组件也可插入列名
let current = null // el-input 组件实例（有内部 .input/.textarea）或原生元素

export function setExprEl(c) { current = c }
export function clearExprEl() { current = null }

export function insertExpr(name) {
  if (!current) return { ok: false, msg: '先点击筛选或新增列的表达式框' }
  const dom = current.input || current.textarea || current
  if (!dom || typeof dom.value === 'undefined') return { ok: false, msg: '表达式框未就绪' }
  const pos = dom.selectionStart ?? dom.value.length
  const before = dom.value.slice(0, pos)
  const after = dom.value.slice(pos)
  const sep = before && !/\s$/.test(before) ? ' ' : ''
  dom.value = before + sep + name + ' ' + after
  dom.dispatchEvent(new Event('input', { bubbles: true }))
  const caret = (before + sep + name + ' ').length
  try { dom.setSelectionRange(caret, caret) } catch { /* */ }
  try { dom.focus() } catch { /* */ }
  return { ok: true }
}
