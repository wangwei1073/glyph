// 统计抽屉各页签共用的格式化与小工具（轻拆时从 StatsPanel 抽出）
import { ElMessage } from 'element-plus'

// 数值格式化：整数原样，小数最多 4 位并去掉尾零
export function num(v) {
  if (v === null || v === undefined || Number.isNaN(v)) return ''
  const n = Number(v)
  return Number.isInteger(n) ? String(n) : n.toFixed(4).replace(/0+$/, '').replace(/\.$/, '')
}

export function pval(p) {
  if (p === null || p === undefined || Number.isNaN(p)) return ''
  const n = Number(p)
  if (n < 0.0001) return '< 0.0001'
  return n.toFixed(4)
}

export function stars(p) {
  if (p === null || p === undefined || Number.isNaN(p)) return ''
  const n = Number(p)
  if (n < 0.001) return '***'
  if (n < 0.01) return '**'
  if (n < 0.05) return '*'
  return 'n.s.'
}

export function copyText(text, okMsg) {
  if (!text) return
  navigator.clipboard.writeText(text)
    .then(() => ElMessage.success(okMsg))
    .catch(() => ElMessage.warning('复制失败，请手动选择'))
}
