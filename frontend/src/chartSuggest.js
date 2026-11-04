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
  const categorical = cols.filter(c => kindOf(c) === 'categorical' || isLowCardinality(c))
  const temporal = cols.filter(c => kindOf(c) === 'temporal')
  const out = []

  const push = (score, item) => out.push({ score, ...item })

  // ---------- 1) 有检验结果：优先给能直接展示结论的图 ----------
  if (testRes && testRes.groups && testRes.groups.length >= 2) {
    const gv = testRes.vars && testRes.vars[0]
    const xcol = testRes.vars && testRes.vars[1]
    // 从检验结果反查变量名
    const groupVar = findGroupVar(testRes, categorical, numeric)
    if (gv && groupVar) {
      const isTwo = testRes.groups.length === 2
      push(100, {
        geom: isTwo ? 'boxplot' : 'boxplot',
        title: isTwo ? '箱线图（两组对比）' : '箱线图（多组对比）',
        reason: `刚才的「${testRes.methodLabel}」比较了 ${testRes.groups.length} 组，箱线图能同时展示分布形状与中位数差异，并在图上标注显著性`,
        aes: { x: { map: groupVar }, y: { map: gv } },
        extra: '建议切到「图上标注」页签，一键把检验结果画到图上',
        score: 100
      })
      push(92, {
        geom: 'violin',
        title: '小提琴图（分布对比）',
        reason: '小提琴图额外显示各组的概率密度，比箱线图更能看出分布形状差异',
        aes: { x: { map: groupVar }, y: { map: gv } }
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
  if (regRes && regRes.method === 'lm' && regRes.vars && regRes.vars.length >= 2) {
    const yv = regRes.vars[0]
    const xv = regRes.vars[1]
    push(98, {
      geom: 'point',
      title: '散点图 + 回归拟合线',
      reason: `线性回归显示 ${yv} 与 ${xv} 显著相关（R²=${regRes.fitStats?.r2 ?? '—'}），散点加拟合线是标准呈现方式`,
      aes: { x: { map: xv }, y: { map: yv } },
      addLayer: { geom: 'smooth', aes: { x: { map: xv }, y: { map: yv } }, params: { method: 'lm', se: true } },
      score: 98
    })
    push(80, {
      geom: 'point',
      title: '散点图 + 分组着色',
      reason: '若存在分组变量，用颜色区分可以看到每组各自的趋势',
      aes: { x: { map: xv }, y: { map: yv } }
    })
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
      push(88, {
        geom: 'histogram',
        title: '直方图（检查偏态）',
        reason: `「${skewed[0].variable}」的均值(${skewed[0].mean})与中位数(${skewed[0].median})差距较大，分布可能偏态，直方图可直接确认`,
        aes: { x: { map: skewed[0].variable } }
      })
      push(84, {
        geom: 'density',
        title: '核密度曲线',
        reason: '密度曲线比直方图更平滑，适合展示偏态与双峰',
        aes: { x: { map: skewed[0].variable } }
      })
    }
  }

  // ---------- 4) 无统计结果：按数据形态给通用建议 ----------
  // 4a. 时间序列：时间 + 数值
  if (temporal.length && numeric.length) {
    const tv = temporal[0].name, nv = numeric[0].name
    push(95, {
      geom: 'line',
      title: '时间序列折线图',
      reason: `检测到时间列「${tv}」与数值列「${nv}」，折线图是展示随时间变化的默认选择`,
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
      aes: { x: { map: cv }, y: { map: nv } }
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
