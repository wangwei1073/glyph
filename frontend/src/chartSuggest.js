// 图表推荐引擎（前端，纯规则推理，不依赖后端）
// 输入：数据列画像 + 统计结果（描述统计/检验/回归）
// 输出：按匹配度排序的图表建议，每条含：图形、理由、一键应用所需的 spec 片段

const NUMERIC = new Set(['numeric'])
const CATEGORICAL = new Set(['character', 'factor', 'logical'])
const TEMPORAL = new Set(['date', 'datetime'])

function kindOf(col) {
  if (!col) return 'unknown'
  if (NUMERIC.has(col.type)) return 'numeric'
  if (CATEGORICAL.has(col.type)) return 'categorical'
  if (TEMPORAL.has(col.type)) return 'temporal'
  return 'unknown'
}

// 判断数值列是否「低基数」（更像类别）
function isLowCardinality(col) {
  return col && col.type === 'numeric' && (col.nUnique ?? 99) <= 8
}

// 名称像「时期/序号」的列：即使低基数也不适合当分类分组（如 year、id、index）
const TIME_OR_INDEX_NAME = /^(year|yr|month|week|day|quarter|q|time|date|id|index|idx|seq|no|num|code)$/i
function looksLikeTimeOrIndex(name) {
  const n = String(name || '').trim()
  if (TIME_OR_INDEX_NAME.test(n)) return true
  // 形如 year_2020、t1、x1 之类的编号列
  return /^(year|yr|t|x|v|g)_?\d+$/i.test(n)
}

/**
 * 分析数据画像，给出候选图表
 * @param {Array} columns 列信息 [{name,type,nUnique,nMissing,range,preview}]
 * @param {Object} summary 描述统计结果（可空）
 * @param {Object} testRes 检验结果（可空）
 * @param {Object} regRes 回归结果（可空）
 */
export function suggestCharts(columns = [], { summary = null, testRes = null, regRes = null } = {}) {
  const cols = (columns || []).filter(c => c && !String(c.name).startsWith('.gg'))
  if (!cols.length) return []

  const numeric = cols.filter(c => kindOf(c) === 'numeric' && !isLowCardinality(c))
  // 低基数值列可分两类：真·分类（如 am/cyl）+ 「时期/序号」型（如 year）
  // 后者不宜作为分组变量，否则会推出「按年份分组的箱线图」这种没有意义的图
  const categorical = cols.filter(c => {
    if (kindOf(c) === 'categorical') return true
    if (isLowCardinality(c) && !looksLikeTimeOrIndex(c.name)) return true
    return false
  })
  // 时期/序号型数值列：既可作连续变量，也可作为时间轴
  const ordinalLike = cols.filter(c => isLowCardinality(c) && looksLikeTimeOrIndex(c.name))
  // 这些列也是合法的 y（如按年份统计的数值），纳入数值候选
  const numericAll = [...numeric, ...ordinalLike]
  const temporal = cols.filter(c => kindOf(c) === 'temporal')
  const out = []

  const push = (score, item) => out.push({ score, ...item })

  // ---------- 1) 有检验结果：优先给能直接展示结论的图 ----------
  if (testRes && testRes.groups && testRes.groups.length >= 2) {
    // 后端约定 vars = [被比较的变量, 分组变量]；用列画像核对类型，
    // 兼容旧数据里顺序不确定的情况
    const tvars = (testRes.vars || []).map(String)
    const colOfName = (n) => cols.find(c => c.name === n)
    let gv = tvars[0]
    let groupVar = tvars[1]
    // 若顺序反了（第一个是分类、第二个是数值/连续），交换
    const firstKind = gv ? kindOf(colOfName(gv)) : 'unknown'
    const secondKind = groupVar ? kindOf(colOfName(groupVar)) : 'unknown'
    if (firstKind === 'categorical' && secondKind === 'numeric') {
      ;[gv, groupVar] = [groupVar, gv]
    }
    // 兜底：groupVar 缺失时从分类列里找
    if (!groupVar) groupVar = findGroupVar(testRes, categorical, numeric)
    // 只在类型真的支持时推荐（y 需数值/分类，x 需分类）
    const gvCol = gv ? colOfName(gv) : null
    const okPair = gv && groupVar && gvCol && groupVar !== gv
    if (okPair) {
      const isTwo = testRes.groups.length === 2
      push(120, {
        geom: 'boxplot',
        title: isTwo ? '箱线图（两组对比）' : '箱线图（多组对比）',
        reason: `刚才的「${testRes.methodLabel}」比较了 ${testRes.groups.length} 组，箱线图能同时展示分布形状与中位数差异，并可在图上标注显著性`,
        aes: { x: { map: groupVar }, y: { map: gv }, fill: { map: groupVar } },
        extra: '建议切到「图上标注」页签，一键把检验结果画到图上',
        score: 120
      })
      push(112, {
        geom: 'violin',
        title: '小提琴图（分布对比）',
        reason: '小提琴图额外显示各组的概率密度，比箱线图更能看出分布形状差异',
        aes: { x: { map: groupVar }, y: { map: gv }, fill: { map: groupVar } }
      })
      push(86, {
        geom: 'point',
        title: '均值点图（含误差条）',
        reason: '用 stat_summary 画均值 ± 标准误，比箱线图更紧凑，适合期刊小图',
        aes: { x: { map: groupVar }, y: { map: gv } },
        stat: 'summary'
      })
    }
  }

  // ---------- 2) 有回归结果：给散点 + 拟合线 ----------
  // 注意：regRes.vars 的顺序不可靠（可能是 [y, x] 也可能是 [y, 分类列, ...]），
  // 必须用列画像核对类型 —— 否则会把分类列当 x，导致 geom_smooth 静默画不出线。
  if (regRes && regRes.method === 'lm' && regRes.vars && regRes.vars.length >= 2) {
    const colOf = (name) => cols.find(c => c.name === name)
    const yv = regRes.vars[0]
    const yCol = colOf(yv)
    // 只在「真实连续」的数值列里挑 x（低基数数值/分类列都要排除）
    const contXs = regRes.vars
      .slice(1)
      .filter(v => {
        const c = colOf(v)
        return c && kindOf(c) === 'numeric' && !isLowCardinality(c)
      })
    const xv = contXs[0]

    if (xv && yCol) {
      push(98, {
        geom: 'point',
        title: '散点图 + 回归拟合线',
        reason: `线性回归显示 ${yv} 与 ${xv} 相关（R²=${regRes.fitStats?.r2 ?? '—'}），散点加拟合线是标准呈现方式`,
        aes: { x: { map: xv }, y: { map: yv } },
        addLayer: { geom: 'smooth', aes: { x: { map: xv }, y: { map: yv } }, params: { method: 'lm', se: true } },
        score: 118
      })
    } else {
      // 没有连续自变量（全是分类）→ 推荐分组对比类图，而不是拟合线
      const catX = regRes.vars.slice(1).find(v => {
        const c = colOf(v)
        return c && (kindOf(c) === 'categorical' || isLowCardinality(c))
      })
      if (catX && yCol) {
        push(96, {
          geom: 'boxplot',
          title: '箱线图（回归中的分类自变量）',
          reason: `回归里 ${yv} 的自变量「${catX}」是分类变量，用分组箱线图展示各组分布比拟合线更合适`,
          aes: { x: { map: catX }, y: { map: yv }, fill: { map: catX } },
          score: 116
        })
        push(90, {
          geom: 'point',
          title: '均值点图（分类自变量各组均值）',
          reason: `直接比较「${catX}」各组 ${yv} 的均值与标准误`,
          aes: { x: { map: catX }, y: { map: yv } },
          stat: 'summary',
          score: 108
        })
      }
    }
  }
  // ---------- 3) 有描述统计：根据分布特征推荐 ----------
  // summary 兼容两种形态：{summary:[...]} 或直接 [...]
  const srows = Array.isArray(summary) ? summary : (summary && Array.isArray(summary.summary) ? summary.summary : null)
  if (srows && srows.length) {
    // 只排除「合计」行；「（全部）」是未分组时的正常标签，必须保留
    const rows = srows.filter(r => !String(r.group).includes('合计'))
    const firstVar = rows[0]?.variable
    // 偏度粗判：均值与中位数差距
    const skewed = rows.filter(r => {
      const m = Number(r.mean), md = Number(r.median)
      if (!isFinite(m) || !isFinite(md) || m === 0) return false
      return Math.abs(m - md) / Math.abs(m) > 0.08
    })
    if (skewed.length) {
      push(105, {
        geom: 'histogram',
        title: '直方图（检查偏态）',
        reason: `「${skewed[0].variable}」的均值(${skewed[0].mean})与中位数(${skewed[0].median})差距较大，分布可能偏态，直方图可直接确认`,
        aes: { x: { map: skewed[0].variable } }
      })
      push(100, {
        geom: 'density',
        title: '核密度曲线',
        reason: '密度曲线比直方图更平滑，适合展示偏态与双峰',
        aes: { x: { map: skewed[0].variable } }
      })
    }
  }

  // ---------- 4) 无统计结果：按数据形态给通用建议 ----------
  // 4a. 时间序列：时间列（date/datetime）+ 数值，或「年份/序号」型数值 + 数值
  const timeAxis = temporal.length ? temporal[0]
    : (ordinalLike.length && numeric.length >= 2 ? ordinalLike[0] : null)
  if (timeAxis && numeric.length) {
    const tv = timeAxis.name
    const nv = (numeric.find(c => c.name !== tv) || numeric[0]).name
    push(95, {
      geom: 'line',
      title: '时间序列折线图',
      reason: `检测到时间/序列列「${tv}」与数值列「${nv}」，折线图是展示随时间变化的默认选择`,
      aes: { x: { map: tv }, y: { map: nv } }
    })
  }

  // 4b. 一个分类 + 一个数值：分组比较
  if (categorical.length && numeric.length) {
    const cv = categorical[0].name, nv = numeric[0].name
    push(93, {
      geom: 'boxplot',
      title: '箱线图（分类 vs 数值）',
      reason: `按「${cv}」分组比较「${nv}」的分布，箱线图能同时显示中位数、四分位与异常值`,
      aes: { x: { map: cv }, y: { map: nv }, fill: { map: cv } }
    })
    push(87, {
      geom: 'bar',
      title: '条形图（分类计数）',
      reason: `「${cv}」是分类变量，条形图展示各类别的样本量，常作为基线表配图`,
      aes: { x: { map: cv } }
    })
    if (numeric.length >= 2) {
      push(82, {
        geom: 'point',
        title: '分组散点图',
        reason: '用颜色区分分组，可同时观察两个连续变量的关系与组间差异',
        aes: { x: { map: numeric[0].name }, y: { map: numeric[1].name }, colour: { map: cv } }
      })
    }
  }

  // 4c. 两个数值：散点/相关
  if (numeric.length >= 2) {
    const [a, b] = numeric
    push(90, {
      geom: 'point',
      title: '散点图（两连续变量）',
      reason: `「${a.name}」与「${b.name}」都是连续变量，散点图是展示相关性的标准方式`,
      aes: { x: { map: a.name }, y: { map: b.name } }
    })
    push(78, {
      geom: 'point',
      title: '散点图 + 平滑趋势',
      reason: '在散点图上叠加 loess 平滑线，可发现非线性关系',
      aes: { x: { map: a.name }, y: { map: b.name } },
      addLayer: { geom: 'smooth', aes: { x: { map: a.name }, y: { map: b.name } }, params: { method: 'loess' } }
    })
  }

  // 4d. 单个数值：分布
  if (numeric.length === 1 && !categorical.length) {
    const nv = numeric[0].name
    push(85, {
      geom: 'histogram',
      title: '直方图（单变量分布）',
      reason: `数据只有一个连续变量「${nv}」，直方图展示其分布`,
      aes: { x: { map: nv } }
    })
  }

  // 4e. 两个分类：列联表可视化
  if (categorical.length >= 2) {
    const [a, b] = categorical
    push(80, {
      geom: 'bar',
      title: '堆叠条形图（两分类）',
      reason: `「${a.name}」与「${b.name}」都是分类变量，堆叠条形图可展示交叉分布`,
      aes: { x: { map: a.name }, fill: { map: b.name } },
      position: { type: 'fill' }
    })
  }

  // 4f. 全部分类：频数
  if (categorical.length && !numeric.length && !temporal.length && categorical.length < 2) {
    push(75, {
      geom: 'bar',
      title: '条形图（频数）',
      reason: '数据以分类变量为主，条形图统计各类频数',
      aes: { x: { map: categorical[0].name } }
    })
  }

  // 去重（同 geom + 同 aes + 同叠加层才算重复；同图不同叠加属于不同建议）
  const seen = new Set()
  const uniq = []
  for (const s of out.sort((a, b) => b.score - a.score)) {
    const key = `${s.geom}|${JSON.stringify(s.aes)}|${s.addLayer ? s.addLayer.geom : ''}`
    if (seen.has(key)) continue
    seen.add(key)
    uniq.push(s)
  }
  return uniq.slice(0, 6)
}

// 从检验结果里推断分组变量名
function findGroupVar(testRes, categorical, numeric) {
  const g = testRes.groups || []
  // 组名形如「setosa (n=50)」，取括号前部分
  const names = g.map(x => String(x).replace(/\s*\(n=.*\)$/, '').trim())
  for (const c of categorical) {
    const col = c.name
    if (names.length && names.every(n => n.length <= 40) && testRes.vars) {
      // 检验结果的 vars 一般含分组列名
      const v = testRes.vars.find(v => v === col)
      if (v) return v
    }
  }
  // 退化：从 vars 里挑第一个分类列
  if (testRes.vars) {
    for (const v of testRes.vars) {
      if (categorical.some(c => c.name === v)) return v
    }
  }
  return null
}
