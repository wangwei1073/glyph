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

console.log(`\n===== 图表推荐: ${pass} 通过 / ${fail} 失败 =====`)
process.exit(fail > 0 ? 1 : 0)
