<script setup>
// 统计面板：L1 描述统计 + L2 统计检验
// 两者都基于「数据加工 + 手工编辑后」的数据（与画布一致），并给出可复现 R 代码。
import { ref, computed, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useDataStore } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import { statsColumns, statsSummary, statsSuggest, statsTest, sigPlan, regColumns, regFit, downloadBlob } from '../api'

const data = useDataStore()
const spec = useSpecStore()
const ui = useUiStore()

// ---- 共用 ----
const loading = ref(false)
const error = ref('')
const numericCols = ref([])
const groupCols = ref([])
const catCols = ref([])
// 抽屉内的页签：desc 描述统计 / test 统计检验
const tab = ref('desc')

const hasSource = computed(() => !!data.current && data.current.type !== 'none')

const prep = computed(() => {
  const d = spec.spec.data || {}
  return { filter: d.filter || '', mutate: d.mutate || [], sample: d.sample, seed: d.seed }
})
const source = computed(() => {
  const c = data.current
  if (!c || c.type === 'none') return { type: 'none' }
  return c.type === 'dataset' ? { type: 'dataset', name: c.name } : { type: 'user', id: c.name }
})

// ---- L1 描述统计 ----
const vars = ref([])
const groupBy = ref([])
const result = ref(null)
const showCode = ref(false)
const descRunning = ref(false)
const canRunDesc = computed(() => hasSource.value && numericCols.value.length > 0)

// ---- L2 统计检验 ----
const testY = ref('')
const testX = ref('')
const testGroup = ref('')
const testMethod = ref('')
const testResult = ref(null)
const testRunning = ref(false)
const testCode = ref(false)
const methods = ref([])
const needPair = computed(() => ['t.test.paired'].includes(testMethod.value))

// ---- L3 图上标注 ----
const sigPlan_ = ref(null)          // 后端给的规划：xCol/yCol/levels/pairs/yStart/yStep
const sigLoading = ref(false)
const sigPick = ref([])             // 待添加的比较对（字符串 "A||B"）
const sigKind = ref('bracket')      // bracket | text
const sigLabelMode = ref('stars')   // stars | p | custom
const sigCustomLabel = ref('*')
const sigMarks = computed(() => spec.spec.sigMarks || [])
const canMark = computed(() => !!sigPlan_.value && sigPlan_.value.ok && spec.spec.layers.length > 0)

async function loadSigPlan() {
  if (!spec.spec.layers.length) { sigPlan_.value = null; return }
  sigLoading.value = true
  try {
    sigPlan_.value = await sigPlan(spec.spec)
  } catch (e) {
    sigPlan_.value = { ok: false, reason: e.message }
  } finally {
    sigLoading.value = false
  }
}

// 依据 L2 的检验结果或统一模板生成标注文字
function labelFor(pair) {
  if (sigLabelMode.value === 'custom') return sigCustomLabel.value || '*'
  if (sigLabelMode.value === 'p' && testResult.value) {
    const p = testResult.value.p
    if (p === null || p === undefined) return 'p = ?'
    return p < 0.0001 ? 'p < 0.0001' : `p = ${Number(p).toFixed(4)}`
  }
  // stars：用同一套阈值，但这里没有逐对 p，给最常用的三档
  return '***'
}

function addPicked() {
  if (!sigPick.value.length) { ElMessage.warning('先选择要比较的分组对'); return }
  const start = sigPlan_.value?.yStart ?? 0
  const step = sigPlan_.value?.yStep ?? 1
  let n = sigMarks.value.length
  for (const key of sigPick.value) {
    const [g1, g2] = key.split('||')
    spec.addSigMark({
      kind: sigKind.value,
      group1: g1, group2: g2,
      label: labelFor(key),
      yPos: Number((start + step * n).toFixed(3))
    })
    n++
  }
  sigPick.value = []
  spec.renderNow()
}

function autoAll() {
  const pairs = sigPlan_.value?.pairs || []
  if (!pairs.length) { ElMessage.warning('当前图没有可比较的离散分组'); return }
  const start = sigPlan_.value?.yStart ?? 0
  const step = sigPlan_.value?.yStep ?? 1
  let n = sigMarks.value.length
  for (const p of pairs) {
    spec.addSigMark({
      kind: sigKind.value, group1: p.group1, group2: p.group2,
      label: labelFor(p), yPos: Number((start + step * n).toFixed(3))
    })
    n++
  }
  spec.renderNow()
  ElMessage.success(`已添加 ${pairs.length} 个标注`)
}

function resetY() {
  const start = sigPlan_.value?.yStart ?? 0
  const step = sigPlan_.value?.yStep ?? 1
  sigMarks.value.forEach((m, i) => spec.setSigMark(i, { yPos: Number((start + step * i).toFixed(3)) }))
  spec.renderNow()
}

// ---- L4 回归分析 ----
const regMethod = ref('lm')
const regY = ref('')
const regXs = ref([])
const regResult = ref(null)
const regRunning = ref(false)
const regCodeOpen = ref(false)
const regCols = ref({ numeric: [], categorical: [], binary: [], count: [] })
const regXOptions = computed(() => {
  const c = regCols.value
  if (regMethod.value === 'corr') return c.numeric
  // 线性回归：数值 + 分类都可；逻辑/泊松同理
  return [...(c.numeric || []), ...(c.categorical || [])].filter(v => v !== regY.value)
})
const regYOptions = computed(() => {
  const c = regCols.value
  if (regMethod.value === 'logistic') return c.binary
  if (regMethod.value === 'poisson') return c.count
  return [...(c.numeric || []), ...(c.categorical || [])]
})
const canReg = computed(() => hasSource.value && !!regY.value &&
  (regMethod.value === 'corr' ? regXs.value.length >= 1 : regXs.value.length >= 1))

async function loadRegColumns() {
  if (!hasSource.value) { regCols.value = { numeric: [], categorical: [], binary: [], count: [] }; return }
  try {
    const r = await regColumns(source.value, prep.value)
    regCols.value = { numeric: r.numeric || [], categorical: r.categorical || [],
                      binary: r.binary || [], count: r.count || [] }
    // 清理失效选择
    regXs.value = regXs.value.filter(v => regXOptions.value.includes(v))
    if (regY.value && !regYOptions.value.includes(regY.value)) regY.value = ''
    if (!regY.value && regYOptions.value.length) regY.value = regYOptions.value[0]
  } catch (e) {
    error.value = e.message
  }
}

async function runReg() {
  if (!canReg.value) { ElMessage.warning('请选择因变量与至少一个自变量'); return }
  regRunning.value = true
  error.value = ''
  try {
    regResult.value = await regFit(source.value, prep.value, {
      y: regY.value, xs: regXs.value, method: regMethod.value
    })
    regCodeOpen.value = false
  } catch (e) {
    error.value = e.message; regResult.value = null
  } finally {
    regRunning.value = false
  }
}

// 切换方法时重置不适用的选择
watch(regMethod, () => {
  if (!regYOptions.value.includes(regY.value)) regY.value = regYOptions.value[0] || ''
  regXs.value = regXs.value.filter(v => regXOptions.value.includes(v))
  regResult.value = null
})
const isCorr = computed(() => testMethod.value.startsWith('cor.test'))
const canRunTest = computed(() => {
  if (!hasSource.value) return false
  if (isCorr.value) return !!(testY.value && testX.value)
  if (!testY.value) return false
  return !!(testGroup.value || isCorr.value)
})

// ---- 列探测 ----
async function refreshColumns() {
  if (!hasSource.value) {
    numericCols.value = []; groupCols.value = []; catCols.value = []
    vars.value = []; groupBy.value = []; methods.value = []
    result.value = null; testResult.value = null
    return
  }
  loading.value = true
  error.value = ''
  try {
    const [cols, sug] = await Promise.all([
      statsColumns(source.value, prep.value),
      statsSuggest(source.value, prep.value).catch(() => ({ methods: [], roles: {} }))
    ])
    numericCols.value = cols.numeric || []
    groupCols.value = cols.groupable || []
    catCols.value = (sug.roles && sug.roles.categorical) || []
    methods.value = sug.methods || []

    vars.value = vars.value.filter(v => numericCols.value.includes(v))
    groupBy.value = groupBy.value.filter(v => groupCols.value.includes(v))
    if (!vars.value.length && numericCols.value.length) vars.value = [numericCols.value[0]]

    // 检验变量槽位：失效则清空
    if (testY.value && !numericCols.value.includes(testY.value) && !catCols.value.includes(testY.value)) testY.value = ''
    if (testX.value && !numericCols.value.includes(testX.value)) testX.value = ''
    if (testGroup.value && !groupCols.value.includes(testGroup.value)) testGroup.value = ''
    if (!testY.value && numericCols.value.length) testY.value = numericCols.value[0]
    if (!testGroup.value && groupCols.value.length) testGroup.value = groupCols.value[0]
  } catch (e) {
    error.value = e.message
  } finally {
    loading.value = false
  }
}

// ---- L1 执行 ----
async function runDesc() {
  if (!canRunDesc.value) { ElMessage.warning('先选择数据与至少一个数值列'); return }
  descRunning.value = true
  error.value = ''
  try {
    result.value = await statsSummary(source.value, prep.value, vars.value, groupBy.value)
  } catch (e) {
    error.value = e.message; result.value = null
  } finally {
    descRunning.value = false
  }
}

// ---- L2 执行 ----
async function runTest() {
  if (!canRunTest.value) { ElMessage.warning('请先选择检验所需的变量'); return }
  testRunning.value = true
  error.value = ''
  try {
    testResult.value = await statsTest(source.value, prep.value, {
      y: isCorr.value ? testY.value : testY.value,
      x: isCorr.value ? testX.value : '',
      group: isCorr.value ? '' : testGroup.value,
      method: testMethod.value
    })
  } catch (e) {
    error.value = e.message; testResult.value = null
  } finally {
    testRunning.value = false
  }
}

// ---- 格式化 ----
function num(v) {
  if (v === null || v === undefined || Number.isNaN(v)) return ''
  const n = Number(v)
  return Number.isInteger(n) ? String(n) : n.toFixed(4).replace(/0+$/, '').replace(/\.$/, '')
}
function pval(p) {
  if (p === null || p === undefined || Number.isNaN(p)) return ''
  const n = Number(p)
  if (n < 0.0001) return '< 0.0001'
  return n.toFixed(4)
}
function stars(p) {
  if (p === null || p === undefined || Number.isNaN(p)) return ''
  const n = Number(p)
  if (n < 0.001) return '***'
  if (n < 0.01) return '**'
  if (n < 0.05) return '*'
  return 'n.s.'
}
const sigClass = computed(() => {
  const p = testResult.value?.p
  if (p === null || p === undefined || Number.isNaN(p)) return ''
  return Number(p) < 0.05 ? 'sig' : 'ns'
})

function copyText(text, okMsg) {
  if (!text) return
  navigator.clipboard.writeText(text)
    .then(() => ElMessage.success(okMsg))
    .catch(() => ElMessage.warning('复制失败，请手动选择'))
}

let timer = null
watch(() => `${data.srcKey}|${prep.value.filter}|${prep.value.sample}|${(prep.value.mutate || []).map(m => m.expr).join('|')}`,
  () => { clearTimeout(timer); timer = setTimeout(refreshColumns, 400) },
  { immediate: true })

// 图层 x/y 映射变化时，重新规划显著性标注
let sigTimer = null
watch(() => JSON.stringify((spec.spec.layers || []).map(l => [l.geom, l.aes?.x?.map, l.aes?.y?.map])),
  () => { clearTimeout(sigTimer); sigTimer = setTimeout(loadSigPlan, 350) },
  { immediate: true })
watch(tab, (v) => {
  if (v === 'mark') loadSigPlan()
  if (v === 'reg') loadRegColumns()
})
</script>
<template>
  <div class="stats-drawer" :class="{ open: ui.statsOpen }">
    <!-- 标题栏：折叠 + 页签 + 结果摘要 -->
    <div class="sd-head">
      <span class="sd-collapse" @click="ui.toggleStats()">
        <el-icon :size="13"><component :is="ui.statsOpen ? 'ArrowDown' : 'ArrowRight'" /></el-icon>
        <span class="sd-title">数据统计</span>
      </span>

      <template v-if="ui.statsOpen">
        <el-radio-group v-model="tab" size="small" class="sd-tabs">
          <el-radio-button value="desc">描述统计</el-radio-button>
          <el-radio-button value="test">统计检验</el-radio-button>
          <el-radio-button value="mark">图上标注</el-radio-button>
          <el-radio-button value="reg">回归分析</el-radio-button>
        </el-radio-group>
      </template>

      <span v-if="testResult" class="sd-badge" :class="sigClass">
        {{ testResult.methodLabel }} · p = {{ pval(testResult.p) }}
      </span>
      <span v-else-if="result && result.summary" class="sd-badge">
        描述统计 · {{ result.summary.length }} 行
      </span>
      <span v-else class="sd-hint">描述统计 / 统计检验</span>

      <span style="flex:1" />
      <span class="sd-toggle" @click="ui.toggleStats()">{{ ui.statsOpen ? '收起' : '展开' }}</span>
    </div>

    <div v-if="ui.statsOpen" class="sd-body">
      <div v-if="!hasSource" class="gg-empty-hint" style="padding:30px">
        <el-icon class="big"><Coin /></el-icon>
        <div>先在左侧选择数据源</div>
      </div>

      <template v-else>
        <!-- ================= 描述统计 ================= -->
        <div v-show="tab === 'desc'" class="sd-pane">
          <aside class="sd-params">
            <div class="sp-field">
              <label>统计变量</label>
              <el-select v-model="vars" size="small" multiple filterable collapse-tags
                collapse-tags-tooltip placeholder="选择数值列" style="width:100%">
                <el-option v-for="c in numericCols" :key="c" :value="c" :label="c" />
              </el-select>
            </div>
            <div class="sp-field">
              <label>分组变量</label>
              <el-select v-model="groupBy" size="small" multiple filterable clearable collapse-tags
                collapse-tags-tooltip placeholder="（可选）按列分组" style="width:100%">
                <el-option v-for="c in groupCols" :key="c" :value="c" :label="c" />
              </el-select>
            </div>
            <div class="sp-actions">
              <el-button size="small" type="primary" :loading="descRunning" :disabled="!canRunDesc" @click="runDesc">
                <el-icon class="el-icon--left"><DataAnalysis /></el-icon>计算
              </el-button>
              <el-button size="small" text @click="refreshColumns" :loading="loading">
                <el-icon><Refresh /></el-icon>
              </el-button>
            </div>
            <div v-if="!numericCols.length && !loading" class="sp-hint">当前数据没有数值列可汇总</div>
            <div v-else class="sp-hint">
              均值 / SD 按列忽略缺失；有分组时自动追加「合计」行。
            </div>
          </aside>

          <section class="sd-result">
            <el-alert v-if="error" type="error" :title="error" :closable="false" show-icon />
            <template v-if="result && result.summary && result.summary.length">
              <div class="res-head">
                <span class="gg-mono">
                  {{ result.nrow }} 行 · {{ result.vars.length }} 变量<template v-if="result.groupBy.length"> · 按 {{ result.groupBy.join(' × ') }} 分组</template>
                </span>
                <span style="flex:1" />
                <el-button size="small" text @click="showCode = !showCode">
                  <el-icon><Document /></el-icon>{{ showCode ? '隐藏代码' : '代码' }}
                </el-button>
              </div>

              <div class="gg-scroll res-table-wrap">
                <table class="stat-table">
                  <thead>
                    <tr>
                      <th>变量</th><th>分组</th>
                      <th class="n">n</th><th class="n">缺失</th><th class="n">均值</th>
                      <th class="n">SD</th><th class="n">中位数</th><th class="n">Q1</th>
                      <th class="n">Q3</th><th class="n">最小</th><th class="n">最大</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr v-for="(r, i) in result.summary" :key="i" :class="{ total: r.group === '（合计）' }">
                      <td class="gg-mono">{{ r.variable }}</td>
                      <td>{{ r.group }}</td>
                      <td class="n">{{ r.n }}</td>
                      <td class="n">{{ r.nMissing }}</td>
                      <td class="n">{{ num(r.mean) }}</td>
                      <td class="n">{{ num(r.sd) }}</td>
                      <td class="n">{{ num(r.median) }}</td>
                      <td class="n">{{ num(r.q1) }}</td>
                      <td class="n">{{ num(r.q3) }}</td>
                      <td class="n">{{ num(r.min) }}</td>
                      <td class="n">{{ num(r.max) }}</td>
                    </tr>
                  </tbody>
                </table>
              </div>

              <div v-if="showCode" class="res-code">
                <div class="res-code-head">
                  <span>可复现 R 代码</span><span style="flex:1" />
                  <el-button size="small" text @click="copyText(result.code, '统计代码已复制')">
                    <el-icon><CopyDocument /></el-icon>
                  </el-button>
                  <el-button size="small" text
                    @click="downloadBlob(new Blob([result.code], { type: 'text/plain;charset=utf-8' }), 'stats-summary.R')">
                    <el-icon><Download /></el-icon>
                  </el-button>
                </div>
                <pre class="gg-mono code-pre">{{ result.code }}</pre>
              </div>
            </template>
            <div v-else class="gg-empty-hint" style="padding:24px">
              选择变量后点「计算」
            </div>
          </section>
        </div>

        <!-- ================= 统计检验 ================= -->
        <div v-show="tab === 'test'" class="sd-pane">
          <aside class="sd-params">
            <div class="sp-field">
              <label>检验方法</label>
              <el-select v-model="testMethod" size="small" filterable clearable
                placeholder="自动选择" style="width:100%">
                <el-option v-for="m in methods" :key="m.id" :value="m.id" :label="m.label">
                  <span class="opt-row"><span>{{ m.label }}</span><span class="opt-fn gg-mono">{{ m.id }}</span></span>
                </el-option>
              </el-select>
            </div>
            <div class="sp-field">
              <label>{{ isCorr ? '变量 Y' : '数值变量' }}</label>
              <el-select v-model="testY" size="small" filterable clearable placeholder="选择列" style="width:100%">
                <el-option v-for="c in numericCols" :key="c" :value="c" :label="c" />
              </el-select>
            </div>
            <div v-if="isCorr" class="sp-field">
              <label>变量 X</label>
              <el-select v-model="testX" size="small" filterable clearable placeholder="选择列" style="width:100%">
                <el-option v-for="c in numericCols.filter(c => c !== testY)" :key="c" :value="c" :label="c" />
              </el-select>
            </div>
            <div v-else class="sp-field">
              <label>分组变量</label>
              <el-select v-model="testGroup" size="small" filterable clearable placeholder="选择分组列" style="width:100%">
                <el-option v-for="c in groupCols" :key="c" :value="c" :label="c" />
              </el-select>
            </div>
            <div class="sp-actions">
              <el-button size="small" type="primary" :loading="testRunning" :disabled="!canRunTest" @click="runTest">
                <el-icon class="el-icon--left"><TrendCharts /></el-icon>运行检验
              </el-button>
            </div>
            <div v-if="needPair" class="sp-hint warn">
              配对检验按分组水平顺序逐位置配对，请确认是「同一样本的两次测量」。
            </div>
            <div v-else class="sp-hint">
              不选方法时按变量角色自动推荐；结果附带正态性 / 方差齐性检查。
            </div>
          </aside>

          <section class="sd-result">
            <el-alert v-if="error" type="error" :title="error" :closable="false" show-icon />
            <template v-if="testResult">
              <div class="test-card" :class="sigClass">
                <div class="test-title">
                  <span class="gg-mono">{{ testResult.methodLabel }}</span>
                  <span style="flex:1" />
                  <el-tag :type="sigClass === 'sig' ? 'success' : 'info'" size="small" :disable-transitions="true">
                    {{ sigClass === 'sig' ? '显著' : '不显著' }}
                  </el-tag>
                </div>

                <div class="test-metrics">
                  <div class="tm">
                    <span class="tm-l">{{ testResult.estimateName || '统计量' }}</span>
                    <span class="tm-v gg-mono">
                      {{ testResult.estimateName ? num(testResult.estimate) : num(testResult.statistic) }}
                    </span>
                  </div>
                  <div class="tm">
                    <span class="tm-l">p 值</span>
                    <span class="tm-v gg-mono">
                      {{ pval(testResult.p) }}<span class="stars">{{ stars(testResult.p) }}</span>
                    </span>
                  </div>
                  <div v-if="testResult.statistic !== null && testResult.estimateName" class="tm">
                    <span class="tm-l">{{ isCorr ? 't 值' : '统计量' }}</span>
                    <span class="tm-v gg-mono">
                      {{ num(testResult.statistic) }}<template v-if="testResult.df">, df={{ num(testResult.df) }}</template>
                    </span>
                  </div>
                  <div class="tm">
                    <span class="tm-l">样本量</span>
                    <span class="tm-v gg-mono">n = {{ testResult.n }}</span>
                  </div>
                </div>

                <div v-if="testResult.groups && testResult.groups.length" class="test-groups">
                  <span v-for="(g, i) in testResult.groups" :key="i" class="tg">{{ g }}</span>
                </div>

                <div v-if="testResult.notes && testResult.notes.length" class="test-notes">
                  <div v-for="(n, i) in testResult.notes" :key="i" class="note-line">· {{ n }}</div>
                </div>

                <div class="res-code-head" style="margin-top:6px">
                  <span>可复现 R 代码</span><span style="flex:1" />
                  <el-button size="small" text @click="testCode = !testCode">
                    <el-icon><Document /></el-icon>{{ testCode ? '隐藏' : '查看' }}
                  </el-button>
                  <el-button size="small" text @click="copyText(testResult.code, '检验代码已复制')">
                    <el-icon><CopyDocument /></el-icon>
                  </el-button>
                </div>
                <pre v-if="testCode" class="gg-mono code-pre">{{ testResult.code }}</pre>
              </div>
            </template>
            <div v-else class="gg-empty-hint" style="padding:24px">
              选择变量后点「运行检验」
            </div>
          </section>
        </div>

        <!-- ================= 图上标注（L3）================= -->
        <div v-show="tab === 'mark'" class="sd-pane">
          <aside class="sd-params">
            <div v-if="!spec.spec.layers.length" class="sp-hint">
              先在右侧添加图层并映射 x / y，才能添加标注。
            </div>
            <template v-else>
              <div class="sp-field">
                <label>标注形态</label>
                <el-radio-group v-model="sigKind" size="small">
                  <el-radio-button value="bracket">括号</el-radio-button>
                  <el-radio-button value="text">文字</el-radio-button>
                </el-radio-group>
              </div>
              <div class="sp-field">
                <label>标签内容</label>
                <el-select v-model="sigLabelMode" size="small" style="width:100%">
                  <el-option value="stars" label="星号（* / ** / ***）" />
                  <el-option value="p" label="p 值（用最近一次检验结果）" />
                  <el-option value="custom" label="自定义文字" />
                </el-select>
              </div>
              <div v-if="sigLabelMode === 'custom'" class="sp-field">
                <el-input v-model="sigCustomLabel" size="small" placeholder="如 n.s. 或 p&lt;0.05" />
              </div>
              <div class="sp-field">
                <label>比较分组对</label>
                <el-select v-model="sigPick" size="small" multiple filterable collapse-tags
                  collapse-tags-tooltip placeholder="选择分组对" style="width:100%">
                  <el-option v-for="p in (sigPlan_?.pairs || [])" :key="p.group1 + '||' + p.group2"
                    :value="p.group1 + '||' + p.group2" :label="`${p.group1} vs ${p.group2}`" />
                </el-select>
              </div>
              <div class="sp-actions">
                <el-button size="small" type="primary" :disabled="!canMark || !sigPick.length" @click="addPicked">
                  <el-icon class="el-icon--left"><Plus /></el-icon>添加
                </el-button>
                <el-button size="small" :disabled="!canMark" @click="autoAll">全部分组两两比较</el-button>
              </div>
              <div v-if="sigMarks.length" class="sp-actions">
                <el-button size="small" text @click="resetY"><el-icon><Refresh /></el-icon>重排 y 位置</el-button>
                <el-button size="small" text type="danger" @click="spec.clearSigMarks(); spec.renderNow()">清空</el-button>
              </div>
              <div class="sp-hint">
                {{ sigPlan_?.discrete ? '当前 x 轴为离散分组，可用括号标注。' : '当前 x 轴为连续值，建议用文字标注。' }}
              </div>
              <div v-if="sigPlan_ && !sigPlan_.ok" class="sp-hint warn">{{ sigPlan_.reason }}</div>
            </template>
          </aside>

          <section class="sd-result">
            <template v-if="sigMarks.length">
              <div class="res-head">
                <span class="gg-mono">{{ sigMarks.length }} 个标注 · 自动 y 起点 {{ num(sigPlan_?.yStart) }}</span>
              </div>
              <div class="gg-scroll mark-list">
                <div v-for="(m, i) in sigMarks" :key="i" class="mark-row">
                  <el-select v-model="m.kind" size="small" style="width:78px"
                    @change="spec.renderNow()">
                    <el-option value="bracket" label="括号" />
                    <el-option value="text" label="文字" />
                  </el-select>
                  <span class="mk-g gg-mono">{{ m.group1 || '—' }}</span>
                  <span class="mk-vs">vs</span>
                  <span class="mk-g gg-mono">{{ m.group2 || '—' }}</span>
                  <el-input v-model="m.label" size="small" class="mk-label" placeholder="*"
                    @change="spec.renderNow()" />
                  <el-input-number :model-value="m.yPos" size="small" :step="0.1" :controls="false"
                    class="mk-y" placeholder="y"
                    @update:model-value="(v) => { spec.setSigMark(i, { yPos: v }); spec.renderNow() }" />
                  <el-button size="small" text type="danger" @click="spec.removeSigMark(i); spec.renderNow()">
                    <el-icon><Delete /></el-icon>
                  </el-button>
                </div>
              </div>
              <div class="res-note">
                括号标注需要 ggsignif，文字标注需要 ggpubr；缺失时自动退化为 annotate("text")。
                生成的 R 代码会包含对应的 <span class="gg-mono">library()</span>。
              </div>
            </template>
            <div v-else class="gg-empty-hint" style="padding:24px">
              选择比较对后点「添加」，或直接「全部分组两两比较」
            </div>
          </section>
        </div>

        <!-- ================= 回归分析（L4）================= -->
        <div v-show="tab === 'reg'" class="sd-pane">
          <aside class="sd-params">
            <div class="sp-field">
              <label>模型类型</label>
              <el-select v-model="regMethod" size="small" style="width:100%">
                <el-option value="lm" label="线性回归（连续 y）" />
                <el-option value="logistic" label="逻辑回归（二分类 y）" />
                <el-option value="poisson" label="泊松回归（计数 y）" />
                <el-option value="corr" label="相关矩阵" />
              </el-select>
            </div>
            <div class="sp-field">
              <label>{{ regMethod === 'corr' ? '首个变量' : '因变量' }}</label>
              <el-select v-model="regY" size="small" filterable clearable
                placeholder="选择列" style="width:100%">
                <el-option v-for="c in regYOptions" :key="c" :value="c" :label="c" />
              </el-select>
            </div>
            <div class="sp-field">
              <label>{{ regMethod === 'corr' ? '其余变量' : '自变量' }}</label>
              <el-select v-model="regXs" size="small" multiple filterable collapse-tags
                collapse-tags-tooltip placeholder="可多选" style="width:100%">
                <el-option v-for="c in regXOptions" :key="c" :value="c" :label="c" />
              </el-select>
            </div>
            <div class="sp-actions">
              <el-button size="small" type="primary" :loading="regRunning" :disabled="!canReg" @click="runReg">
                <el-icon class="el-icon--left"><TrendCharts /></el-icon>拟合
              </el-button>
              <el-button size="small" text @click="loadRegColumns"><el-icon><Refresh /></el-icon></el-button>
            </div>
            <div class="sp-hint">
              分类自变量会自动转为因子；分类因变量在逻辑回归里同样自动处理。
            </div>
          </aside>

          <section class="sd-result">
            <el-alert v-if="error" type="error" :title="error" :closable="false" show-icon />
            <template v-if="regResult">
              <!-- 拟合优度 -->
              <div class="reg-fit">
                <template v-if="regResult.method === 'lm'">
                  <span class="rf-item"><b>R²</b> {{ num(regResult.fitStats.r2) }}</span>
                  <span class="rf-item"><b>调整R²</b> {{ num(regResult.fitStats.adjR2) }}</span>
                  <span v-if="regResult.fitStats.fstat" class="rf-item">
                    <b>F</b> {{ num(regResult.fitStats.fstat) }}
                    <span class="gg-mono">({{ regResult.fitStats.df1 }},{{ regResult.fitStats.df2 }})</span>
                  </span>
                  <span v-if="regResult.fitStats.p" class="rf-item">
                    <b>p</b> {{ pval(regResult.fitStats.p) }}<span class="stars">{{ stars(regResult.fitStats.p) }}</span>
                  </span>
                </template>
                <template v-else-if="regResult.method !== 'corr'">
                  <span class="rf-item"><b>AIC</b> {{ num(regResult.fitStats.aic) }}</span>
                  <span class="rf-item"><b>伪R²</b> {{ num(regResult.fitStats.pseudoR2) }}</span>
                  <span class="rf-item"><b>偏差</b> {{ num(regResult.fitStats.deviance) }}</span>
                </template>
                <span class="rf-item"><b>n</b> {{ regResult.n }}</span>
                <span style="flex:1" />
                <el-button size="small" text @click="regCodeOpen = !regCodeOpen">
                  <el-icon><Document /></el-icon>{{ regCodeOpen ? '隐藏代码' : '代码' }}
                </el-button>
              </div>

              <!-- 系数表 -->
              <div class="gg-scroll res-table-wrap">
                <table class="stat-table">
                  <thead>
                    <tr v-if="regResult.method === 'corr'">
                      <th>变量 1</th>
                      <th>变量 2</th>
                      <th class="n">r</th>
                      <th class="n">p</th>
                      <th class="n">n</th>
                    </tr>
                    <tr v-else>
                      <th>项</th>
                      <th class="n">估计</th>
                      <th v-if="regResult.method !== 'lm'" class="n">exp</th>
                      <th class="n">SE</th>
                      <th class="n">t / z</th>
                      <th class="n">p</th>
                      <th class="n">95% CI</th>
                    </tr>
                  </thead>
                  <tbody>
                    <template v-if="regResult.method === 'corr'">
                      <tr v-for="(row, i) in regResult.coefs" :key="i">
                        <td class="gg-mono">{{ row.var1 }}</td>
                        <td class="gg-mono">{{ row.var2 }}</td>
                        <td class="n">{{ num(row.r) }}<span class="stars">{{ row.stars }}</span></td>
                        <td class="n">{{ pval(row.p) }}</td>
                        <td class="n">{{ row.n }}</td>
                      </tr>
                    </template>
                    <template v-else>
                      <tr v-for="(row, i) in regResult.coefs" :key="i">
                        <td class="gg-mono">{{ row.term }}</td>
                        <td class="n">{{ num(row.estimate) }}</td>
                        <td v-if="regResult.method !== 'lm'" class="n">{{ num(row.expEstimate) }}</td>
                        <td class="n">{{ num(row.se) }}</td>
                        <td class="n">{{ num(row.stat) }}</td>
                        <td class="n">{{ pval(row.p) }}<span class="stars">{{ row.stars }}</span></td>
                        <td class="n">{{ num(row.ciLow) }} ~ {{ num(row.ciHigh) }}</td>
                      </tr>
                    </template>
                  </tbody>
                </table>
              </div>

              <!-- 诊断提示 -->
              <div v-if="regResult.notes && regResult.notes.length" class="reg-notes">
                <div v-for="(n, i) in regResult.notes" :key="i" class="note-line">· {{ n }}</div>
              </div>

              <!-- 代码 -->
              <div v-if="regCodeOpen" class="res-code">
                <div class="res-code-head">
                  <span>可复现 R 代码</span><span style="flex:1" />
                  <el-button size="small" text @click="copyText(regResult.code, '回归代码已复制')">
                    <el-icon><CopyDocument /></el-icon>
                  </el-button>
                </div>
                <pre class="gg-mono code-pre">{{ regResult.code }}</pre>
              </div>
            </template>
            <div v-else class="gg-empty-hint" style="padding:24px">
              选择因变量与自变量后点「拟合」
            </div>
          </section>
        </div>
      </template>
    </div>
  </div>
</template>

<style scoped>
/* ---------- 抽屉外壳 ---------- */
.stats-drawer {
  flex-shrink: 0; display: flex; flex-direction: column;
  border-top: 1px solid var(--gg-border);
  background: var(--gg-panel); min-height: 0;
}
.stats-drawer.open { height: 304px; }

.sd-head {
  display: flex; align-items: center; gap: 10px; flex-shrink: 0;
  padding: 4px 10px; border-bottom: 1px solid var(--gg-border);
  font-size: 12px;
}
.sd-collapse {
  display: flex; align-items: center; gap: 6px;
  cursor: pointer; user-select: none; padding: 2px 4px; border-radius: 4px;
}
.sd-collapse:hover { background: rgba(74, 144, 217, .08); }
.sd-title { font-weight: 600; }
.sd-tabs :deep(.el-radio-button__inner) { padding: 4px 12px; font-size: 11.5px; }
.sd-hint, .sd-toggle { font-size: 11px; color: var(--el-text-color-secondary); }
.sd-toggle { cursor: pointer; }
.sd-toggle:hover { color: var(--gg-accent); }
.sd-badge {
  font-size: 10.5px; padding: 1px 7px; border-radius: 9px;
  background: rgba(128, 128, 128, .12); color: var(--el-text-color-secondary);
  font-variant-numeric: tabular-nums; white-space: nowrap;
}
.sd-badge.sig { background: rgba(84, 178, 142, .16); color: #2f8b68; }

/* ---------- 内容区：左参数 + 右结果 ---------- */
.sd-body { flex: 1; min-height: 0; display: flex; }
.sd-pane { flex: 1; min-width: 0; display: flex; }

.sd-params {
  width: 264px; flex-shrink: 0; display: flex; flex-direction: column; gap: 8px;
  padding: 10px 12px; border-right: 1px solid var(--gg-border);
  overflow-y: auto;
}
.sp-field { display: flex; flex-direction: column; gap: 3px; }
.sp-field > label { font-size: 11px; color: var(--el-text-color-secondary); }
.sp-actions { display: flex; align-items: center; gap: 6px; padding-top: 2px; }
.sp-hint {
  font-size: 10.5px; line-height: 1.5; color: var(--el-text-color-secondary);
  padding-top: 2px;
}
.sp-hint.warn { color: #c07f18; }

.sd-result {
  flex: 1; min-width: 0; display: flex; flex-direction: column;
  padding: 8px 12px 10px; overflow: hidden;
}
.res-head {
  display: flex; align-items: center; gap: 6px; flex-shrink: 0;
  padding-bottom: 5px; font-size: 11px; color: var(--el-text-color-secondary);
}
.res-table-wrap {
  flex: 1; min-height: 0; border: 1px solid var(--gg-border); border-radius: 6px;
}
.res-code { flex-shrink: 0; margin-top: 6px; }
.res-code-head {
  display: flex; align-items: center; gap: 4px; flex-shrink: 0;
  font-size: 11px; color: var(--el-text-color-secondary);
}

/* ---------- 表格 ---------- */
.stat-table { border-collapse: collapse; width: 100%; font-size: 11.5px; }
.stat-table th {
  position: sticky; top: 0; z-index: 1; background: var(--gg-panel);
  text-align: left; font-weight: 600; white-space: nowrap;
  padding: 4px 8px; border-bottom: 1px solid var(--gg-border);
}
.stat-table td {
  padding: 2px 8px; border-bottom: 1px solid var(--gg-border);
  white-space: nowrap; max-width: 140px; overflow: hidden; text-overflow: ellipsis;
}
.stat-table .n { text-align: right; font-variant-numeric: tabular-nums; }
.stat-table tbody tr:hover td { background: rgba(74, 144, 217, .06); }
.stat-table tbody tr.total td { background: rgba(74, 144, 217, .09); font-weight: 600; }

/* ---------- 代码块 ---------- */
.code-pre {
  margin: 4px 0 0; padding: 8px; max-height: 150px; overflow: auto;
  background: rgba(128, 128, 128, .08); border-radius: 6px;
  font-size: 11px; line-height: 1.45; white-space: pre-wrap; word-break: break-all;
}

/* ---------- 检验结果卡片 ---------- */
.test-card {
  flex: 1; min-height: 0; overflow-y: auto;
  padding: 9px 11px; border: 1px solid var(--gg-border);
  border-left-width: 3px; border-radius: 6px; background: var(--gg-panel);
}
.test-card.sig { border-left-color: #54b28e; }
.test-card.ns { border-left-color: #b0b8c0; }
.test-title { display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 600; }
.test-metrics {
  display: grid; grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 4px 16px; margin-top: 7px;
}
.tm { display: flex; align-items: baseline; gap: 6px; font-size: 11.5px; }
.tm-l { color: var(--el-text-color-secondary); min-width: 46px; flex-shrink: 0; }
.tm-v { font-variant-numeric: tabular-nums; }
.stars { color: #e8734a; font-weight: 700; margin-left: 3px; }
.test-groups { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 7px; }
.tg {
  font-size: 10.5px; padding: 1px 6px; border-radius: 8px;
  background: rgba(128, 128, 128, .1); color: var(--el-text-color-secondary);
}
.test-notes { margin-top: 7px; padding-top: 6px; border-top: 1px dashed var(--gg-border); }
.note-line { font-size: 10.5px; line-height: 1.55; color: var(--el-text-color-secondary); }
.opt-row { display: flex; justify-content: space-between; gap: 14px; align-items: center; }
.opt-fn { font-size: 10.5px; color: var(--el-text-color-secondary); }

/* ---------- 图上标注 ---------- */
.mark-list { flex: 1; min-height: 0; }
.mark-row {
  display: flex; align-items: center; gap: 6px;
  padding: 3px 4px; border-bottom: 1px solid var(--gg-border);
}
.mk-g { font-size: 11.5px; max-width: 78px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.mk-vs { font-size: 10.5px; color: var(--el-text-color-secondary); }
.mk-label { width: 92px; }
.mk-y { width: 74px; }
.res-note {
  flex-shrink: 0; padding-top: 6px; font-size: 10.5px; line-height: 1.5;
  color: var(--el-text-color-secondary);
}

/* ---------- 回归 ---------- */
.reg-fit {
  display: flex; align-items: center; gap: 14px; flex-wrap: wrap; flex-shrink: 0;
  padding: 0 0 6px; font-size: 11.5px;
}
.rf-item { color: var(--el-text-color-secondary); font-variant-numeric: tabular-nums; }
.rf-item b { color: var(--el-text-color-primary); font-weight: 600; margin-right: 3px; }
.reg-notes {
  flex-shrink: 0; max-height: 62px; overflow-y: auto;
  padding: 5px 0 2px; border-top: 1px dashed var(--gg-border); margin-top: 5px;
}
</style>
