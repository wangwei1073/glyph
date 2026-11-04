// 图表推荐引擎测试（Node 环境，纯函数）
// 运行: node tests/test_chart_suggest.mjs
import { suggestCharts } from '../frontend/src/chartSuggest.js'

let pass = 0, fail = 0
function chk(label, cond) {
  if (cond) { console.log(`[OK] ${label}`); pass++ }
  else { console.log(`[FAIL] ${label}`); fail++ }
}

const col = (name, type, nUnique = 10, extra = {}) => ({ name, type, nUnique, ...extra })

// ---------- 1) 空输入 ----------
chk('空列返回空建议', suggestCharts([]).length === 0)
chk('null 输入不崩溃', suggestCharts(null).length === 0)

// ---------- 2) 单连续变量 → 直方图 ----------
const cols1 = [col('mpg', 'numeric', 25)]
const r1 = suggestCharts(cols1)
chk('单连续变量：非空', r1.length > 0)
chk('单连续变量：首选直方图', r1[0].geom === 'histogram')
chk('单连续变量：说明非空', typeof r1[0].reason === 'string' && r1[0].reason.length > 5)

// ---------- 3) 两连续变量 → 散点 ----------
const cols2 = [col('wt', 'numeric', 29), col('mpg', 'numeric', 25)]
const r2 = suggestCharts(cols2)
chk('两连续变量：首选散点图', r2[0].geom === 'point')
chk('两连续变量：含 x 与 y 映射', !!(r2[0].aes.x && r2[0].aes.y))
chk('两连续变量：提供拟合线建议', r2.some(s => s.addLayer && s.addLayer.geom === 'smooth'))

// ---------- 4) 分类 + 连续 → 箱线图 ----------
const cols3 = [col('Species', 'factor', 3), col('Sepal.Length', 'numeric', 35)]
const r3 = suggestCharts(cols3)
chk('分类+连续：首选箱线图', r3[0].geom === 'boxplot')
chk('分类+连续：x 为分类列', r3[0].aes.x.map === 'Species')
chk('分类+连续：y 为数值列', r3[0].aes.y.map === 'Sepal.Length')
chk('分类+连续：含条形图建议', r3.some(s => s.geom === 'bar'))
chk('分类+连续：箱线图带 fill', (r3.find(s => s.geom === 'boxplot')?.aes?.fill?.map) === 'Species')

// ---------- 5) 时间 + 数值 → 折线 ----------
const cols4 = [col('date', 'date', 500), col('unemploy', 'numeric', 500)]
const r4 = suggestCharts(cols4)
chk('时间序列：首选折线图', r4[0].geom === 'line')
chk('时间序列：x 为时间列', r4[0].aes.x.map === 'date')

// ---------- 6) 两分类 → 堆叠条形 ----------
const cols5 = [col('drv', 'character', 3), col('class', 'character', 7)]
const r5 = suggestCharts(cols5)
chk('两分类：含条形图', r5.some(s => s.geom === 'bar'))

// ---------- 7) 有检验结果 → 优先展示组间差异 ----------
const cols6 = [col('Species', 'factor', 3), col('Sepal.Length', 'numeric', 35)]
const testRes = {
  methodLabel: '单因素方差分析',
  vars: ['Sepal.Length', 'Species'],
  groups: ['setosa (n=50)', 'versicolor (n=50)', 'virginica (n=50)'],
  p: 1.6e-31
}
const r6 = suggestCharts(cols6, { testRes })
chk('有检验结果：首位建议与检验相关', r6[0].geom === 'boxplot')
chk('有检验结果：理由提到检验方法', /方差分析|检验/.test(r6[0].reason))
chk('有检验结果：提示图上标注', r6.some(s => s.extra && /标注/.test(s.extra)))
chk('有检验结果：分数高于无统计时', r6[0].score >= 100)

// ---------- 8) 有回归结果 → 散点+拟合线且带 R² ----------
const cols7 = [col('wt', 'numeric', 29), col('mpg', 'numeric', 25)]
const regRes = {
  method: 'lm',
  vars: ['mpg', 'wt'],
  fitStats: { r2: 0.75 }
}
const r7 = suggestCharts(cols7, { regRes })
chk('有回归结果：首位含拟合线', r7[0].addLayer && r7[0].addLayer.geom === 'smooth')
chk('有回归结果：理由含 R²', /R²=0\.75/.test(r7[0].reason))
chk('有回归结果：拟合线用 lm', r7[0].addLayer.params.method === 'lm')

// ---------- 9) 描述统计偏态 → 直方图推荐 ----------
const cols8 = [col('income', 'numeric', 100)]
const summary = {
  summary: [
    { variable: 'income', group: '（全部）', n: 100, mean: 100, median: 50, sd: 80 }
  ]
}
const r8 = suggestCharts(cols8, { summary })
chk('偏态检测：推荐直方图', r8.some(s => s.geom === 'histogram'))
chk('偏态检测：理由提到均值与中位数', r8.some(s => /均值|中位数/.test(s.reason)))
chk('偏态检测：推荐密度曲线', r8.some(s => s.geom === 'density'))

// ---------- 10) 去重与上限 ----------
const many = [
  col('a', 'numeric', 30), col('b', 'numeric', 30),
  col('c', 'numeric', 30), col('g', 'factor', 3),
  col('h', 'factor', 4), col('t', 'date', 100)
]
const r10 = suggestCharts(many)
chk('多列：结果不超过 6 条', r10.length <= 6)
const keys = r10.map(s => `${s.geom}|${JSON.stringify(s.aes)}`)
chk('多列：无重复建议', new Set(keys).size === keys.length)
chk('多列：按分数降序', r10.every((s, i) => i === 0 || r10[i - 1].score >= s.score))

// ---------- 11) 低基数数值按分类处理 ----------
const cols11 = [col('am', 'numeric', 2), col('mpg', 'numeric', 25)]
const r11 = suggestCharts(cols11)
chk('低基数数值：可作为分组', r11.some(s => s.aes && s.aes.x && s.aes.x.map === 'am'))
chk('低基数数值：不当作连续 x', !r11.some(s => s.aes && s.aes.x && s.aes.x.map === 'am' && s.aes.y && s.aes.y.map === 'mpg' && s.geom === 'point'))

// ---------- 12) 内部锚列应被忽略 ----------
const withRid = [col('.gg_rid', 'numeric', 100), col('x', 'numeric', 20)]
const r12 = suggestCharts(withRid)
chk('忽略 .gg_rid 列', !JSON.stringify(r12).includes('.gg_rid'))

// ---------- 13) 回归自变量含分类列时，不得推荐拟合线（回归 bug） ----------
// 复现场景：mpg 的 hwy ~ drv + displ，如果 regRes.vars 顺序里 drv 在前，
// 旧实现会把 drv（分类）当 x，导致 geom_smooth 静默画不出线
const colsMpg = [
  col('hwy', 'numeric', 27),
  col('drv', 'character', 3),
  col('displ', 'numeric', 35)
]
const regWithCat = {
  method: 'lm',
  vars: ['hwy', 'drv', 'displ'],   // drv 在 displ 之前
  fitStats: { r2: 0.73 }
}
const r13 = suggestCharts(colsMpg, { regRes: regWithCat })
const smoothIdea = r13.find(s => s.addLayer && s.addLayer.geom === 'smooth')
chk('分类自变量：拟合线的 x 必须是连续列',
    !smoothIdea || (smoothIdea.aes.x.map !== 'drv' && smoothIdea.aes.x.map === 'displ'))
chk('分类自变量：不把分类列当 x 叠加 smooth',
    !r13.some(s => s.addLayer && s.addLayer.geom === 'smooth' && s.aes.x.map === 'drv'))

// 回归自变量全是分类时，应改推箱线图而不是拟合线
const regAllCat = {
  method: 'lm',
  vars: ['hwy', 'drv'],
  fitStats: { r2: 0.5 }
}
const r14 = suggestCharts(colsMpg, { regRes: regAllCat })
// 注意：通用分支「两连续变量 + loess」仍可出现拟合线（x/y 都是连续列，合理）；
// 要断言的是「没有把分类列 drv 当 x 的拟合线」，且不出现 lm 拟合线
chk('全分类自变量：无分类 x 的拟合线',
    !r14.some(s => s.addLayer && s.addLayer.geom === 'smooth' && s.aes.x.map === 'drv'))
chk('全分类自变量：无 lm 拟合线', !r14.some(s => s.addLayer && s.addLayer.params?.method === 'lm'))
chk('全分类自变量：改推箱线图', r14.some(s => s.geom === 'boxplot'))
chk('全分类自变量：理由提到分类', r14.some(s => /分类/.test(s.reason)))

// 低基数数值列（如 am=0/1）也不能作为拟合线 x
const colsAm = [col('mpg', 'numeric', 25), col('am', 'numeric', 2), col('wt', 'numeric', 29)]
const regAm = { method: 'lm', vars: ['mpg', 'am', 'wt'], fitStats: { r2: 0.8 } }
const r15 = suggestCharts(colsAm, { regRes: regAm })
chk('低基数数值自变量：拟合线 x 不为 am',
    !r15.some(s => s.addLayer && s.addLayer.geom === 'smooth' && s.aes.x.map === 'am'))

// 纯连续自变量时仍正常推荐拟合线
const colsPure = [col('mpg', 'numeric', 25), col('wt', 'numeric', 29)]
const r16 = suggestCharts(colsPure, { regRes: { method: 'lm', vars: ['mpg', 'wt'], fitStats: { r2: 0.75 } } })
chk('纯连续自变量：仍推荐拟合线', r16.some(s => s.addLayer && s.addLayer.geom === 'smooth'))

// ---------- 15) 检验结果的建议必须排在通用建议之前（回归 bug） ----------
// 用户场景：mpg 上做了「hwy ~ drv 单因素方差分析」，图表建议第一位却是「时间序列折线图」。
// 根因：后端检验结果没有返回 vars，前端取不到 x/y，箱线图建议没生成，通用建议胜出。
const colsMpgFull = [
  col('displ', 'numeric', 35), col('year', 'numeric', 2), col('cyl', 'numeric', 4),
  col('cty', 'numeric', 21), col('hwy', 'numeric', 27),
  col('manufacturer', 'character', 15), col('drv', 'character', 3), col('class', 'character', 7)
]
const anovaRes = {
  methodLabel: '单因素方差分析',
  vars: ['hwy', 'drv'],           // 后端现在会返回这个字段
  groups: ['4 (n=103)', 'f (n=106)', 'r (n=25)'],
  p: 0.00001
}
const r19 = suggestCharts(colsMpgFull, { testRes: anovaRes })
chk('检验结果：第一条是箱线图', r19[0].geom === 'boxplot')
chk('检验结果：x 为分组列 drv', r19[0].aes.x.map === 'drv')
chk('检验结果：y 为数值列 hwy', r19[0].aes.y.map === 'hwy')
// 箱线图必须带 fill 映射，否则是空心黑白框（用户反馈「没用上默认主题」的真实原因）
chk('检验结果：箱线图带 fill 映射', r19[0].aes.fill?.map === 'drv')
chk('检验结果：箱线图分数高于折线图',
    r19[0].score > (r19.find(s => s.geom === 'line')?.score ?? 0))

// 无 vars 的旧结果也不应崩溃，且不应推错
const r20 = suggestCharts(colsMpgFull, { testRes: { methodLabel: '方差分析', groups: ['a (n=10)', 'b (n=12)'] } })
chk('缺 vars 时不崩溃', Array.isArray(r20) && r20.length > 0)

// vars 顺序颠倒（分类在前）时应自动纠正
const swapped = { methodLabel: '方差分析', vars: ['drv', 'hwy'], groups: ['4 (n=103)', 'f (n=106)'] }
const r21 = suggestCharts(colsMpgFull, { testRes: swapped })
chk('vars 顺序颠倒：x 仍为分类列', r21[0].aes.x.map === 'drv')
chk('vars 顺序颠倒：y 仍为数值列', r21[0].aes.y.map === 'hwy')

// ---------- 14) 时期/序号型低基数列（如 year）不应被当作分组 ----------
const colsYear = [col('year', 'numeric', 2), col('displ', 'numeric', 35), col('hwy', 'numeric', 27)]
const r17 = suggestCharts(colsYear)
chk('year 不被当作分类分组',
    !r17.some(s => s.geom === 'boxplot' && s.aes.x?.map === 'year'))
chk('year 可作为时间轴推荐折线', r17.some(s => s.geom === 'line' && s.aes.x?.map === 'year'))

// 真正该当分类的低基数列（cyl=4/6/8）仍应可分组
const colsCyl = [col('cyl', 'numeric', 3), col('hwy', 'numeric', 27)]
const r18 = suggestCharts(colsCyl)
chk('cyl 仍可作分类分组', r18.some(s => s.geom === 'boxplot' && s.aes.x?.map === 'cyl'))

console.log(`\n===== 图表推荐: ${pass} 通过 / ${fail} 失败 =====`)
process.exit(fail > 0 ? 1 : 0)
