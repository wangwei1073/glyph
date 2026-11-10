<script setup>
// L4 回归分析页签（轻拆）：模型/变量选择与结果经 defineModel 与壳共享，
// regCols 选项列由本组件在页签激活或手动刷新时加载。
import { computed, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { regColumns, regFit } from '../api'
import { copyText, num, pval, stars } from '../statsShared'

const props = defineProps({
  active: { type: Boolean, default: false },
  numericCols: { type: Array, default: () => [] },
  groupCols: { type: Array, default: () => [] },
  catCols: { type: Array, default: () => [] },
  source: { type: Object, default: null },
  prep: { type: Object, default: () => ({}) },
  hasSource: { type: Boolean, default: false },
  err: { type: String, default: '' }
})

const regMethod = defineModel('regMethod', { type: String, default: 'lm' })
const regY = defineModel('regY', { type: String, default: '' })
const regXs = defineModel('regXs', { type: Array, default: () => [] })
const result = defineModel('result', { type: Object, default: null })

const tabError = ref('')
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
const canReg = computed(() => props.hasSource && !!regY.value &&
  (regMethod.value === 'corr' ? regXs.value.length >= 1 : regXs.value.length >= 1))

async function loadRegColumns() {
  if (!props.hasSource) { regCols.value = { numeric: [], categorical: [], binary: [], count: [] }; return }
  try {
    const r = await regColumns(props.source, props.prep)
    regCols.value = { numeric: r.numeric || [], categorical: r.categorical || [],
                      binary: r.binary || [], count: r.count || [] }
    // 清理失效选择
    regXs.value = regXs.value.filter(v => regXOptions.value.includes(v))
    if (regY.value && !regYOptions.value.includes(regY.value)) regY.value = ''
    if (!regY.value && regYOptions.value.length) regY.value = regYOptions.value[0]
  } catch (e) {
    tabError.value = e.message
  }
}

// 页签激活时加载（与原 watch(tab) 语义一致）
watch(() => props.active, (v) => { if (v) loadRegColumns() })

// 切换方法时重置不适用的选择（与原 watch(regMethod) 一致，含清空结果）
watch(regMethod, () => {
  if (!regYOptions.value.includes(regY.value)) regY.value = regYOptions.value[0] || ''
  regXs.value = regXs.value.filter(v => regXOptions.value.includes(v))
  result.value = null
})

async function runReg() {
  if (!canReg.value) { ElMessage.warning('请选择因变量与至少一个自变量'); return }
  regRunning.value = true
  tabError.value = ''
  try {
    result.value = await regFit(props.source, props.prep, {
      y: regY.value, xs: regXs.value, method: regMethod.value
    })
    regCodeOpen.value = false
  } catch (e) {
    tabError.value = e.message
    result.value = null
  } finally {
    regRunning.value = false
  }
}
</script>
<template>
  <div class="sd-pane">
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
      <el-alert v-if="err || tabError" type="error" :title="tabError || err" :closable="false" show-icon />
      <template v-if="result">
        <!-- 拟合优度 -->
        <div class="reg-fit">
          <template v-if="result.method === 'lm'">
            <span class="rf-item"><b>R²</b> {{ num(result.fitStats.r2) }}</span>
            <span class="rf-item"><b>调整R²</b> {{ num(result.fitStats.adjR2) }}</span>
            <span v-if="result.fitStats.fstat" class="rf-item">
              <b>F</b> {{ num(result.fitStats.fstat) }}
              <span class="gg-mono">({{ result.fitStats.df1 }},{{ result.fitStats.df2 }})</span>
            </span>
            <span v-if="result.fitStats.p" class="rf-item">
              <b>p</b> {{ pval(result.fitStats.p) }}<span class="stars">{{ stars(result.fitStats.p) }}</span>
            </span>
          </template>
          <template v-else-if="result.method !== 'corr'">
            <span class="rf-item"><b>AIC</b> {{ num(result.fitStats.aic) }}</span>
            <span class="rf-item"><b>伪R²</b> {{ num(result.fitStats.pseudoR2) }}</span>
            <span class="rf-item"><b>偏差</b> {{ num(result.fitStats.deviance) }}</span>
          </template>
          <span class="rf-item"><b>n</b> {{ result.n }}</span>
          <span style="flex:1" />
          <el-button size="small" text @click="regCodeOpen = !regCodeOpen">
            <el-icon><Document /></el-icon>{{ regCodeOpen ? '隐藏代码' : '代码' }}
          </el-button>
        </div>

        <!-- 系数表 -->
        <div class="gg-scroll res-table-wrap">
          <table class="stat-table">
            <thead>
              <tr v-if="result.method === 'corr'">
                <th>变量 1</th>
                <th>变量 2</th>
                <th class="n">r</th>
                <th class="n">p</th>
                <th class="n">n</th>
              </tr>
              <tr v-else>
                <th>项</th>
                <th class="n">估计</th>
                <th v-if="result.method !== 'lm'" class="n">exp</th>
                <th class="n">SE</th>
                <th class="n">t / z</th>
                <th class="n">p</th>
                <th class="n">95% CI</th>
              </tr>
            </thead>
            <tbody>
              <template v-if="result.method === 'corr'">
                <tr v-for="(row, i) in result.coefs" :key="i">
                  <td class="gg-mono">{{ row.var1 }}</td>
                  <td class="gg-mono">{{ row.var2 }}</td>
                  <td class="n">{{ num(row.r) }}<span class="stars">{{ row.stars }}</span></td>
                  <td class="n">{{ pval(row.p) }}</td>
                  <td class="n">{{ row.n }}</td>
                </tr>
              </template>
              <template v-else>
                <tr v-for="(row, i) in result.coefs" :key="i">
                  <td class="gg-mono">{{ row.term }}</td>
                  <td class="n">{{ num(row.estimate) }}</td>
                  <td v-if="result.method !== 'lm'" class="n">{{ num(row.expEstimate) }}</td>
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
        <div v-if="result.notes && result.notes.length" class="reg-notes">
          <div v-for="(n, i) in result.notes" :key="i" class="note-line">· {{ n }}</div>
        </div>

        <!-- 代码 -->
        <div v-if="regCodeOpen" class="res-code">
          <div class="res-code-head">
            <span>可复现 R 代码</span><span style="flex:1" />
            <el-button size="small" text @click="copyText(result.code, '回归代码已复制')">
              <el-icon><CopyDocument /></el-icon>
            </el-button>
          </div>
          <pre class="gg-mono code-pre">{{ result.code }}</pre>
        </div>
      </template>
      <div v-else class="gg-empty-hint" style="padding:24px">
        选择因变量与自变量后点「拟合」
      </div>
    </section>
  </div>
</template>
