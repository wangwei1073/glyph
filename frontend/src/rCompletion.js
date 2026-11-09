// R 代码补全（最小版）：函数名 + library() 包名
//
// 设计取舍：
//   - 只做「词表补全」：不解析语法树，靠光标前文本的正则判断上下文
//   - 词表来自后端 /api/completions（geom/stat/scale/coord/theme + 已安装包）
//   - 素材一次性拉取并缓存，避免每次按键请求后端
//
// 覆盖场景：
//   geom_|            → geom_point, geom_line, ...
//   stat_| scale_|    → 对应函数
//   theme_|           → theme_minimal, theme_prism, ...
//   theme(|           → theme_* 函数
//   library(|         → 已安装包名（项目常用包前置）

const CACHE_KEY = 'gg-completions-v1'
let cache = null      // { geoms, stats, ..., packages, geom_params, stat_params }
let loading = null
// 当前数据列名（由 CodeEditor 注入）：aes() 内补列名用
let dataColumns = []
export function setDataColumns(cols) {
  dataColumns = Array.isArray(cols) ? cols.filter(Boolean) : []
}

async function loadTables() {
  if (cache) return cache
  if (loading) return loading
  loading = (async () => {
    // 先试 sessionStorage（同一标签页内复用，避免每次开面板都请求）
    try {
      const raw = sessionStorage.getItem(CACHE_KEY)
      if (raw) { cache = JSON.parse(raw); return cache }
    } catch { /* 隐私模式忽略 */ }
    try {
      const r = await fetch('/api/completions')
      if (!r.ok) throw new Error(`HTTP ${r.status}`)
      const j = await r.json()
      const c = j.completions || {}
      if (c.error) throw new Error(c.error)
      cache = c
      try { sessionStorage.setItem(CACHE_KEY, JSON.stringify(c)) } catch { /* 忽略超限 */ }
      return cache
    } catch (e) {
      // 失败时给空表，补全功能降级但不影响编辑
      cache = { geoms: [], stats: [], scales: [], coords: [], themes: [], theme_elements: [], annotations: [], packages: [] }
      return cache
    } finally {
      loading = null
    }
  })()
  return loading
}

// 词表 → CodeMirror 选项
function mkOptions(list, type, opts = {}) {
  if (!Array.isArray(list)) return []
  const { boostFirst = 0, detail = '' } = opts
  return list.map((name, i) => ({
    label: name,
    type,                                  // 'function' 显示 f 图标，'variable' 显示 v
    detail: detail || undefined,
    // boost：让列表前列的项排得更靠前（CodeMirror 按 boost 加权排序）
    // 包名列表已由后端按「常用优先」排好，这里把前 boostFirst 个提升权重
    boost: i < boostFirst ? 99 - i : 0,
    // 函数名后补 ( 更顺手；包名原样插入
    apply: type === 'function' ? `${name}(` : name
  }))
}

// 上下文判断：返回 { from, options } 或 null
function contextFor(docText, pos) {
  const before = docText.slice(0, pos)
  // 取光标所在行、光标之前的部分（补全只在本行内判断，够用且不易误判）
  const lineStart = before.lastIndexOf('\n') + 1
  const line = before.slice(lineStart)
  const relPos = pos - lineStart

  if (!cache) return null

  // 0) aes(...) 内 → 数据列名（P2）
  //    匹配 `aes(` 且光标在该括号内，未闭合。
  //    用「统计括号深度」判断，避免 `aes(x = displ) +` 之后误触发。
  const aesOpen = /aes\s*\(([^()]*)$/.exec(line)
  if (aesOpen && dataColumns.length) {
    const inner = aesOpen[1] || ''
    // 光标前最后一个「标识符」（可能是列名或 aes 参数名）
    const m = /([A-Za-z0-9._]*)$/.exec(inner)
    const word = m ? m[1] : ''
    // aes 参数名 + 数据列名一起给：用户可能想写 x =、也可能直接填列名
    const aesKeys = ['x', 'y', 'colour', 'color', 'fill', 'size', 'shape', 'alpha', 'group', 'linetype', 'stroke', 'label']
    const opts = [
      ...mkOptions(dataColumns, 'variable', { detail: '列' }),
      ...mkOptions(aesKeys, 'property', { detail: 'aes' })
    ]
    return { from: pos - word.length, options: opts }
  }

  // 1) library(...) / require(...) 内 → 包名
  const libMatch = /(?:library|require)\s*\(\s*["']?([A-Za-z0-9._]*)$/.exec(line)
  if (libMatch) {
    const word = libMatch[1] || ''
    return {
      // 包名用 'variable' 类型，apply 时不会补 (（见 mkOptions）
      // boostFirst 让后端排好的「常用包」优先出现在列表顶部
      from: pos - word.length,
      options: mkOptions(cache.packages, 'variable', { boostFirst: 26 })
    }
  }

  // 2) 主题函数：theme( 内、或 theme_ 前缀
  //    注意不要用 \b：theme_ 结尾是下划线（非单词字符），\b 在多数位置反而匹配不上
  if (/(?:^|[^A-Za-z0-9._])theme\s*\(\s*[A-Za-z0-9._]*$/.test(line)
      || /(?:^|[^A-Za-z0-9._])theme_[A-Za-z0-9._]*$/.test(line)) {
    const m = /([A-Za-z0-9._]*)$/.exec(line)
    const word = m ? m[1] : ''
    return { from: pos - word.length, options: mkOptions(cache.themes, 'function') }
  }

  // 3) 已输入「函数名(」→ 补该函数的参数（P2）
  //    必须放在「函数名前缀」判断之前，否则 geom_point( 会被当成还在选函数。
  //    用「未闭合的左括号 + 括号前的函数名」判断，且该函数在参数表里有记录。
  const inCall = /([A-Za-z][A-Za-z0-9._]*)\s*\(([^()]*)$/.exec(line)
  if (inCall) {
    const fnName = inCall[1]
    const argsText = inCall[2] || ''
    const paramTable =
      (cache.geom_params && cache.geom_params[fnName]) ||
      (cache.stat_params && cache.stat_params[fnName]) ||
      null
    if (paramTable) {
      // 已经写过的参数不再提示（按 `name =` 逐个剔除）
      const used = new Set([...argsText.matchAll(/([A-Za-z][A-Za-z0-9._]*)\s*=/g)].map((m) => m[1]))
      // 光标前正在输入的标识符
      const m = /([A-Za-z0-9._]*)$/.exec(argsText)
      const word2 = m ? m[1] : ''

      // 参数补 `name = `，aes 映射补 `name = `
      const mkParams = (names, detail) => names
        .filter((n) => !used.has(n))
        .filter((n) => !word2 || n.startsWith(word2))
        .map((n) => ({ label: n, type: 'property', detail, apply: `${n} = ` }))

      const opts = [
        ...mkParams(paramTable.params || [], '参数'),
        ...mkParams(paramTable.aes || [], 'aes')
      ]
      if (opts.length) return { from: pos - word2.length, options: opts }
    }
    // 不在参数表里（如 aes( 已单独处理）→ 继续往下走函数名补全
  }

  // 4) 按前缀分派函数组
  const tokens = {
    geom_: [cache.geoms],
    stat_: [cache.stats],
    scale_: [cache.scales],
    coord_: [cache.coords],
    position_: [cache.positions],
    facet_: [cache.facets],
    guide_: [cache.guides],
    annotate: [cache.annotations]
  }

  // 找出光标前的「标识符」（含下划线、点、数字字母）
  const idMatch = /([A-Za-z][A-Za-z0-9._]*)$/.exec(line)
  const word = idMatch ? idMatch[1] : ''

  for (const [prefix, groups] of Object.entries(tokens)) {
    if (word.startsWith(prefix) || (prefix === 'annotate' && word === 'annotate')) {
      const opts = groups.flatMap((g) => mkOptions(g, 'function'))
      if (opts.length) return { from: pos - word.length, options: opts }
    }
  }

  // 5) 空输入或通用标识符：给一份「常用函数」清单（限首字母匹配，避免选项爆炸）
  if (word.length >= 2) {
    const all = [
      ...mkOptions(cache.geoms, 'function'),
      ...mkOptions(cache.themes, 'function'),
      ...mkOptions(cache.scales, 'function')
    ]
    const matched = all.filter((o) => o.label.startsWith(word))
    if (matched.length) return { from: pos - word.length, options: matched }
  }

  return null
}

// 构造 CodeMirror 的补全源
export function rCompletionSource(context) {
  if (!cache) return null   // 未加载完时不补全，避免阻塞输入
  const doc = context.state.doc.toString()
  const pos = context.pos
  const ctx = contextFor(doc, pos)
  if (!ctx || !ctx.options.length) return null
  return {
    from: ctx.from,
    options: ctx.options,
    // 明确指定 validFor，避免输入时反复重新计算
    validFor: /^[A-Za-z0-9._]*$/
  }
}

// 预加载（在编辑器初始化时调用，异步、不阻塞）
export function preloadCompletions() {
  loadTables().catch(() => {})
}

export function completionsReady() {
  return !!cache
}
