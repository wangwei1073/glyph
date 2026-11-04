<script setup>
// 统计面板：L1 描述统计 + L2 统计检验
// 两者都基于「数据加工 + 手工编辑后」的数据（与画布一致），并给出可复现 R 代码。
import { ref, computed, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useDataStore } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import { statsColumns, statsSummary, statsSuggest, statsTest, downloadBlob } from '../api'

const data = useDataStore()
const spec = useSpecStore()
const ui = useUiStore()

// ---- 共用 ----
const loading = ref(false)
const error = ref('')
const numericCols = ref([])
const groupCols = ref([])
const catCols = ref([])
const openSections = ref(['desc', 'test'])

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
</script>

<template>
  <div class="stats-drawer" :class="{ open: ui.statsOpen }">
    <div class="sd-head" @click="ui.toggleStats()">
      <el-icon :size="13"><component :is="ui.statsOpen ? 'ArrowDown' : 'ArrowRight'" /></el-icon>
      <span class="sd-title">数据统计</span>
      <span v-if="testResult" class="sd-badge" :class="sigClass">
        {{ testResult.methodLabel }} · p = {{ pval(testResult.p) }}
      </span>
      <span v-else-if="result && result.summary" class="sd-badge">
        描述统计 · {{ result.summary.length }} 行
      </span>
      <span v-else class="sd-hint">描述统计 / 统计检验</span>
      <span style="flex:1" />
      <span class="sd-toggle">{{ ui.statsOpen ? '收起' : '展开' }}</span>
    </div>

    <div v-if="ui.statsOpen" class="sd-body gg-scroll">
    <div v-if="!hasSource" class="gg-empty-hint" style="padding:30px">
      <el-icon class="big"><Coin /></el-icon>
      <div>先在左侧选择数据源</div>
    </div>

    <template v-else>
      <el-alert v-if="error" type="error" :title="error" :closable="false" show-icon style="margin:8px 12px" />

      <el-collapse v-model="openSections">
        <!-- ================= L1 描述统计 ================= -->
        <el-collapse-item name="desc" title="描述统计">
          <div class="p-row">
            <label>统计变量</label>
            <el-select v-model="vars" size="small" multiple filterable collapse-tags
              collapse-tags-tooltip placeholder="选择数值列" style="width:100%">
              <el-option v-for="c in numericCols" :key="c" :value="c" :label="c" />
            </el-select>
          </div>
          <div class="p-row">
            <label>分组变量</label>
            <el-select v-model="groupBy" size="small" multiple filterable clearable collapse-tags
              collapse-tags-tooltip placeholder="（可选）按列分组" style="width:100%">
              <el-option v-for="c in groupCols" :key="c" :value="c" :label="c" />
            </el-select>
          </div>
          <div class="p-row" style="padding-top:2px">
            <label />
            <el-button size="small" type="primary" :loading="descRunning" :disabled="!canRunDesc" @click="runDesc">
              <el-icon class="el-icon--left"><DataAnalysis /></el-icon>计算
            </el-button>
            <el-button size="small" text @click="refreshColumns" :loading="loading">
              <el-icon><Refresh /></el-icon>
            </el-button>
          </div>

          <div v-if="!numericCols.length && !loading" class="gg-empty-hint" style="padding:16px">
            当前数据没有数值列可汇总
          </div>

          <template v-if="result && result.summary && result.summary.length">
            <div class="stat-head">
              <span class="gg-mono">{{ result.nrow }} 行 · {{ result.vars.length }} 变量<template v-if="result.groupBy.length"> · 按 {{ result.groupBy.join(' × ') }} 分组</template></span>
              <span style="flex:1" />
              <el-button size="small" text @click="showCode = !showCode">
                <el-icon><Document /></el-icon>{{ showCode ? '隐藏代码' : '代码' }}
              </el-button>
            </div>

            <div class="gg-scroll stat-table-wrap">
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

            <div v-if="showCode" class="stat-code">
              <div class="stat-code-head">
                <span>可复现 R 代码</span><span style="flex:1" />
                <el-button size="small" text @click="copyText(result.code, '统计代码已复制')">
                  <el-icon><CopyDocument /></el-icon>
                </el-button>
                <el-button size="small" text
                  @click="downloadBlob(new Blob([result.code], { type: 'text/plain;charset=utf-8' }), 'stats-summary.R')">
                  <el-icon><Download /></el-icon>
                </el-button>
              </div>
              <pre class="gg-mono">{{ result.code }}</pre>
            </div>
          </template>
        </el-collapse-item>

        <!-- ================= L2 统计检验 ================= -->
        <el-collapse-item name="test" title="统计检验">
          <div class="p-row">
            <label>检验方法</label>
            <el-select v-model="testMethod" size="small" filterable clearable
              placeholder="自动选择" style="width:100%">
              <el-option v-for="m in methods" :key="m.id" :value="m.id" :label="m.label">
                <span class="opt-row"><span>{{ m.label }}</span><span class="opt-fn gg-mono">{{ m.id }}</span></span>
              </el-option>
            </el-select>
          </div>
          <div class="p-row">
            <label>{{ isCorr ? '变量 Y' : '数值变量' }}</label>
            <el-select v-model="testY" size="small" filterable clearable placeholder="选择列" style="width:100%">
              <el-option v-for="c in numericCols" :key="c" :value="c" :label="c" />
            </el-select>
          </div>
          <div v-if="isCorr" class="p-row">
            <label>变量 X</label>
            <el-select v-model="testX" size="small" filterable clearable placeholder="选择列" style="width:100%">
              <el-option v-for="c in numericCols.filter(c => c !== testY)" :key="c" :value="c" :label="c" />
            </el-select>
          </div>
          <div v-else class="p-row">
            <label>分组变量</label>
            <el-select v-model="testGroup" size="small" filterable clearable placeholder="选择分组列" style="width:100%">
              <el-option v-for="c in groupCols" :key="c" :value="c" :label="c" />
            </el-select>
          </div>
          <div v-if="needPair" class="stat-tip-inline">
            配对检验按分组变量的水平顺序，逐位置配对；
            <b>请确认分组恰好是「同一样本的两次测量」</b>。
          </div>
          <div class="p-row" style="padding-top:2px">
            <label />
            <el-button size="small" type="primary" :loading="testRunning" :disabled="!canRunTest" @click="runTest">
              <el-icon class="el-icon--left"><TrendCharts /></el-icon>运行检验
            </el-button>
          </div>

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
                  <span class="tm-v gg-mono">{{ num(testResult.statistic) }}<template v-if="testResult.df"> , df={{ num(testResult.df) }}</template></span>
                </div>
                <div class="tm">
                  <span class="tm-l">样本量</span>
                  <span class="tm-v gg-mono">n = {{ testResult.n }}</span>
                </div>
              </div>

              <div v-if="testResult.groups && testResult.groups.length" class="test-groups">
                <span v-for="(g, i) in testResult.groups" :key="i" class="tg">{{ g }}</span>
              </div>

              <el-alert v-if="testResult.notes && testResult.notes.length" type="info" :closable="false"
                class="test-notes">
                <div v-for="(n, i) in testResult.notes" :key="i" class="note-line">· {{ n }}</div>
              </el-alert>

              <div class="stat-code-head" style="margin-top:6px">
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
        </el-collapse-item>
      </el-collapse>

      <div class="stat-note">
        两项统计都基于「数据加工 + 手工编辑后」的 {{ data.preview.nrow }} 行计算，与画布一致。
        检验结果会同时给出假设检查提示，请结合前提选择方法。
      </div>
    </template>
    </div>
  </div>
</template>

<style scoped>
/* 底栏抽屉：占据画布下方，可折叠；与右栏面板解耦 */
.stats-drawer {
  flex-shrink: 0; display: flex; flex-direction: column;
  border-top: 1px solid var(--gg-border);
  background: var(--gg-panel); min-height: 0;
}
.stats-drawer.open { height: 300px; }
.sd-head {
  display: flex; align-items: center; gap: 6px; flex-shrink: 0;
  padding: 5px 10px; cursor: pointer; user-select: none;
  border-bottom: 1px solid var(--gg-border);
  font-size: 12px;
}
.sd-head:hover { background: rgba(74, 144, 217, .06); }
.sd-title { font-weight: 600; }
.sd-hint, .sd-toggle { font-size: 11px; color: var(--el-text-color-secondary); }
.sd-badge {
  font-size: 10.5px; padding: 1px 7px; border-radius: 9px;
  background: rgba(128, 128, 128, .12); color: var(--el-text-color-secondary);
  font-variant-numeric: tabular-nums;
}
.sd-badge.sig { background: rgba(84, 178, 142, .16); color: #2f8b68; }
.sd-body { flex: 1; min-height: 0; padding: 2px 4px 8px; }
</style>

<style scoped>
.stat-head {
  display: flex; align-items: center; gap: 6px;
  padding: 6px 4px 4px; font-size: 11px; color: var(--el-text-color-secondary);
}
.stat-table-wrap { max-height: 300px; border: 1px solid var(--gg-border); border-radius: 6px; }
.stat-table { border-collapse: collapse; width: 100%; font-size: 11.5px; }
.stat-table th {
  position: sticky; top: 0; z-index: 1; background: var(--gg-panel);
  text-align: left; font-weight: 600; white-space: nowrap;
  padding: 3px 6px; border-bottom: 1px solid var(--gg-border);
}
.stat-table td {
  padding: 2px 6px; border-bottom: 1px solid var(--gg-border);
  white-space: nowrap; max-width: 110px; overflow: hidden; text-overflow: ellipsis;
}
.stat-table .n { text-align: right; font-variant-numeric: tabular-nums; }
.stat-table tbody tr:hover td { background: rgba(74, 144, 217, .06); }
.stat-table tbody tr.total td { background: rgba(74, 144, 217, .08); font-weight: 600; }

.stat-code { margin-top: 6px; }
.stat-code-head {
  display: flex; align-items: center; gap: 4px;
  font-size: 11px; color: var(--el-text-color-secondary);
}
.code-pre, .stat-code pre {
  margin: 4px 0 0; padding: 8px; max-height: 200px; overflow: auto;
  background: rgba(128, 128, 128, .08); border-radius: 6px;
  font-size: 11px; line-height: 1.45; white-space: pre-wrap; word-break: break-all;
}

.test-card {
  margin-top: 8px; padding: 8px 10px;
  border: 1px solid var(--gg-border); border-left-width: 3px; border-radius: 6px;
  background: var(--gg-panel);
}
.test-card.sig { border-left-color: #54b28e; }
.test-card.ns { border-left-color: #b0b8c0; }
.test-title { display: flex; align-items: center; gap: 6px; font-size: 12px; font-weight: 600; }
.test-metrics {
  display: grid; grid-template-columns: repeat(2, 1fr); gap: 4px 10px; margin-top: 6px;
}
.tm { display: flex; align-items: baseline; gap: 6px; font-size: 11.5px; }
.tm-l { color: var(--el-text-color-secondary); min-width: 42px; }
.tm-v { font-variant-numeric: tabular-nums; }
.stars { color: #e8734a; font-weight: 700; margin-left: 3px; }
.test-groups { display: flex; flex-wrap: wrap; gap: 4px; margin-top: 6px; }
.tg {
  font-size: 10.5px; padding: 1px 6px; border-radius: 8px;
  background: rgba(128, 128, 128, .1); color: var(--el-text-color-secondary);
}
.test-notes { margin-top: 6px; }
.test-notes :deep(.el-alert__content) { padding: 0; }
.note-line { font-size: 10.5px; line-height: 1.5; }
.stat-tip-inline {
  padding: 2px 12px 4px; font-size: 10.5px; line-height: 1.5;
  color: var(--el-text-color-secondary);
}
.opt-row { display: flex; justify-content: space-between; gap: 14px; align-items: center; }
.opt-fn { font-size: 10.5px; color: var(--el-text-color-secondary); }
.stat-note {
  padding: 8px 6px 0; font-size: 10.5px; line-height: 1.5;
  color: var(--el-text-color-secondary);
}
:deep(.el-collapse-item__header) { font-size: 12px; font-weight: 600; }
:deep(.el-collapse-item__content) { padding-bottom: 8px; }
</style>
