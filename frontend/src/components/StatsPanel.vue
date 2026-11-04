<script setup>
// 描述统计（L1 原型）
// 设计：基于「加工 + 手工编辑后」的数据计算（与画布/预览完全一致）；
//      结果同时给出可复现 R 代码，延续「所见即代码」。
import { ref, computed, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useDataStore } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import { statsColumns, statsSummary, downloadBlob } from '../api'

const data = useDataStore()
const spec = useSpecStore()

const loading = ref(false)
const running = ref(false)
const error = ref('')
const numericCols = ref([])
const groupCols = ref([])
const vars = ref([])
const groupBy = ref([])
const result = ref(null)
const showCode = ref(false)

const hasSource = computed(() => !!data.current && data.current.type !== 'none')
const canRun = computed(() => hasSource.value && numericCols.value.length > 0)

// 与画布共用同一份「数据加工」参数
const prep = computed(() => {
  const d = spec.spec.data || {}
  return { filter: d.filter || '', mutate: d.mutate || [], sample: d.sample, seed: d.seed }
})
const source = computed(() => {
  const c = data.current
  if (!c || c.type === 'none') return { type: 'none' }
  return c.type === 'dataset' ? { type: 'dataset', name: c.name } : { type: 'user', id: c.name }
})

// 列变更（换数据源 / 改加工）时重新探测可用列
async function refreshColumns() {
  if (!hasSource.value) {
    numericCols.value = []; groupCols.value = []; vars.value = []; groupBy.value = []
    result.value = null
    return
  }
  loading.value = true
  error.value = ''
  try {
    const res = await statsColumns(source.value, prep.value)
    numericCols.value = res.numeric || []
    groupCols.value = res.groupable || []
    // 保留仍然存在的选择
    vars.value = vars.value.filter(v => numericCols.value.includes(v))
    groupBy.value = groupBy.value.filter(v => groupCols.value.includes(v))
    if (!vars.value.length && numericCols.value.length) vars.value = [numericCols.value[0]]
  } catch (e) {
    error.value = e.message
    numericCols.value = []; groupCols.value = []
  } finally {
    loading.value = false
  }
}

async function run() {
  if (!canRun.value) { ElMessage.warning('先选择数据与至少一个数值列'); return }
  running.value = true
  error.value = ''
  try {
    result.value = await statsSummary(source.value, prep.value, vars.value, groupBy.value)
  } catch (e) {
    error.value = e.message
    result.value = null
  } finally {
    running.value = false
  }
}

// 结果表格的数值格式化（保留 4 位，去掉多余 0）
function num(v) {
  if (v === null || v === undefined || Number.isNaN(v)) return ''
  const n = Number(v)
  return Number.isInteger(n) ? String(n) : n.toFixed(4).replace(/0+$/, '').replace(/\.$/, '')
}

function copyCode() {
  if (!result.value?.code) return
  navigator.clipboard.writeText(result.value.code)
    .then(() => ElMessage.success('统计代码已复制'))
    .catch(() => ElMessage.warning('复制失败，请手动选择'))
}
function downloadCode() {
  if (!result.value?.code) return
  downloadBlob(new Blob([result.value.code], { type: 'text/plain;charset=utf-8' }), 'stats-summary.R')
}

// 数据源或加工参数变化后自动重新探测（防抖）
let timer = null
watch(() => `${data.srcKey}|${prep.value.filter}|${prep.value.sample}|${(prep.value.mutate || []).map(m => m.expr).join('|')}`,
  () => { clearTimeout(timer); timer = setTimeout(refreshColumns, 400) },
  { immediate: true })
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">描述统计（按分组汇总）</div>

    <div v-if="!hasSource" class="gg-empty-hint" style="padding:30px">
      <el-icon class="big"><Coin /></el-icon>
      <div>先在左侧选择数据源</div>
    </div>

    <template v-else>
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
        <el-button size="small" type="primary" :loading="running" :disabled="!canRun" @click="run">
          <el-icon class="el-icon--left"><DataAnalysis /></el-icon>计算
        </el-button>
        <el-button size="small" text @click="refreshColumns" :loading="loading">
          <el-icon><Refresh /></el-icon>
        </el-button>
      </div>

      <div v-if="!numericCols.length && !loading" class="gg-empty-hint" style="padding:16px">
        当前数据没有数值列可汇总
      </div>

      <el-alert v-if="error" type="error" :title="error" :closable="false" show-icon style="margin:8px 12px" />

      <!-- 结果 -->
      <template v-if="result && result.summary && result.summary.length">
        <div class="stat-head">
          <span class="gg-mono">{{ result.nrow }} 行 · {{ result.vars.length }} 变量<template v-if="result.groupBy.length"> · 按 {{ result.groupBy.join(' × ') }} 分组</template></span>
          <span style="flex:1" />
          <el-button size="small" text @click="showCode = !showCode">
            <el-icon><Document /></el-icon>{{ showCode ? '隐藏代码' : '查看代码' }}
          </el-button>
        </div>

        <div class="gg-scroll stat-table-wrap">
          <table class="stat-table">
            <thead>
              <tr>
                <th>变量</th>
                <th>分组</th>
                <th class="n">n</th>
                <th class="n">缺失</th>
                <th class="n">均值</th>
                <th class="n">SD</th>
                <th class="n">中位数</th>
                <th class="n">Q1</th>
                <th class="n">Q3</th>
                <th class="n">最小</th>
                <th class="n">最大</th>
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
            <span>可复现 R 代码</span>
            <span style="flex:1" />
            <el-button size="small" text @click="copyCode"><el-icon><CopyDocument /></el-icon></el-button>
            <el-button size="small" text @click="downloadCode"><el-icon><Download /></el-icon></el-button>
          </div>
          <pre class="gg-mono">{{ result.code }}</pre>
        </div>

        <div class="stat-note">
          基于「数据加工 + 手工编辑后」的 {{ result.nrow }} 行计算，与画布一致；
          均值/SD 等按列忽略缺失值（n 与「缺失」分列显示）。
        </div>
      </template>
    </template>
  </div>
</template>

<style scoped>
.stat-head {
  display: flex; align-items: center; gap: 6px;
  padding: 6px 12px 4px; font-size: 11px; color: var(--gg-text-2, var(--el-text-color-secondary));
}
.stat-table-wrap { max-height: 320px; margin: 0 8px; border: 1px solid var(--gg-border); border-radius: 6px; }
.stat-table { border-collapse: collapse; width: 100%; font-size: 11.5px; }
.stat-table th {
  position: sticky; top: 0; z-index: 1; background: var(--gg-panel);
  text-align: left; font-weight: 600; white-space: nowrap;
  padding: 3px 6px; border-bottom: 1px solid var(--gg-border);
}
.stat-table td {
  padding: 2px 6px; border-bottom: 1px solid var(--gg-border);
  white-space: nowrap; max-width: 120px; overflow: hidden; text-overflow: ellipsis;
}
.stat-table .n { text-align: right; font-variant-numeric: tabular-nums; }
.stat-table tbody tr:hover td { background: rgba(74, 144, 217, .06); }
.stat-table tbody tr.total td { background: rgba(74, 144, 217, .08); font-weight: 600; }
.stat-code { margin: 8px 8px 0; }
.stat-code-head {
  display: flex; align-items: center; gap: 4px;
  font-size: 11px; color: var(--gg-text-2, var(--el-text-color-secondary));
}
.stat-code pre {
  margin: 4px 0 0; padding: 8px; max-height: 220px; overflow: auto;
  background: rgba(128, 128, 128, .08); border-radius: 6px;
  font-size: 11px; line-height: 1.45; white-space: pre-wrap; word-break: break-all;
}
.stat-note {
  padding: 8px 12px 0; font-size: 10.5px; line-height: 1.5;
  color: var(--gg-text-3, var(--el-text-color-secondary));
}
</style>
