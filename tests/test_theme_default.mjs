// 主题默认值回归测试：确保「新建 / 清空 / 载入旧项目」都不会丢失默认 Prism 主题
// 运行: node tests/test_theme_default.mjs
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const __dirname = dirname(fileURLToPath(import.meta.url))
const src = readFileSync(join(__dirname, '..', 'frontend', 'src', 'stores', 'spec.js'), 'utf8')

let pass = 0, fail = 0
function chk(label, cond) {
  if (cond) { console.log(`[OK] ${label}`); pass++ }
  else { console.log(`[FAIL] ${label}`); fail++ }
}

// ---------- 静态检查：默认 spec 必须带 prism 主题 ----------
// 2026-11 起 defaultSpec 支持用户自定义默认（主题面板「存为我的默认」）：
// base 变为条件表达式，无用户默认时仍回落 prism
chk('defaultSpec 含 prism 主题（无用户默认时回落）',
  /base:\s*udTheme \? udTheme\.base : 'prism'/.test(src))
chk('defaultSpec 带 palette 参数', /palette:\s*'black_and_white'/.test(src))

// ---------- 静态检查：ensureDefaultTheme 不应在 meta 未加载时降级 ----------
chk('ensureDefaultTheme 检查 meta.loaded', /if\s*\(!meta\.loaded/.test(src))
chk('ensureDefaultTheme 保留 prisim 判断', /themeByName\['prism'\]/.test(src))

// ---------- 静态检查：loadProject 对空主题回落默认 ----------
chk('loadProject 有空白主题回落逻辑', /noBase && noArgs && noEls/.test(src))
chk('loadProject 回落时用 base.theme', /merged\.theme\s*=\s*JSON\.parse\(JSON\.stringify\(base\.theme\)\)/.test(src))

// ---------- 行为模拟：复刻 loadProject 的合并规则，验证各种输入 ----------
const DEFAULT_THEME = { base: 'prism', args: { palette: 'black_and_white', base_size: 12 }, elements: {} }

function mergeTheme(objTheme) {
  const base = { theme: JSON.parse(JSON.stringify(DEFAULT_THEME)) }
  const mergedTheme = { ...base.theme, ...(objTheme || {}) }
  const o = objTheme || {}
  const noBase = !o.base
  const noArgs = !o.args || !Object.keys(o.args).length
  const noEls = !o.elements || !Object.keys(o.elements).length
  if (noBase && noArgs && noEls) return JSON.parse(JSON.stringify(base.theme))
  return mergedTheme
}

// 1) 全新项目（无 theme 字段）→ 应为 prism
const t1 = mergeTheme(undefined)
chk('全新项目：得到 prism', t1.base === 'prism')
chk('全新项目：带 palette', t1.args.palette === 'black_and_white')

// 2) 旧草稿带空主题 → 应回落 prism（这是本次修复的 bug）
const t2 = mergeTheme({ base: '', args: {}, elements: {} })
chk('旧草稿空主题：回落 prism', t2.base === 'prism')
chk('旧草稿空主题：带默认参数', t2.args.base_size === 12)

// 3) 用户明确选了 minimal → 必须保留
const t3 = mergeTheme({ base: 'minimal', args: { base_size: 10 }, elements: {} })
chk('用户选 minimal：保留', t3.base === 'minimal')
chk('用户选 minimal：保留参数', t3.args.base_size === 10)

// 4) 用户没选基础主题但改了元素 → 必须保留元素、且不应强塞 prism 覆盖
const t4 = mergeTheme({ base: '', args: {}, elements: { 'panel.grid': { blank: true } } })
chk('仅改元素：保留元素', !!(t4.elements && t4.elements['panel.grid']))

// 5) 用户显式清空主题（base:''）但同时改过 args → 保留用户意图
const t5 = mergeTheme({ base: '', args: { base_size: 14 }, elements: {} })
chk('仅改参数：保留参数', t5.args.base_size === 14)

console.log(`\n===== 主题默认值: ${pass} 通过 / ${fail} 失败 =====`)
process.exit(fail > 0 ? 1 : 0)
