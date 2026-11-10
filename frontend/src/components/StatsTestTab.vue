<script setup>
// L2 统计检验页签（轻拆）：输入变量/结果经 defineModel 与壳共享；方法清单由壳的 refreshColumns 提供
import { computed, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { statsTest } from '../api'
import { copyText, num, pval, stars } from '../statsShared'

const props = defineProps({
  numericCols: { type: Array, default: () => [] },
  groupCols: { type: Array, default: () => [] },
  methods: { type: Array, default: () => [] },   // statsSuggest 给出的可选方法
  source: { type: Object, default: null },
  prep: { type: Object, default: () => ({}) },
  hasSource: { type: Boolean, default: false },
  pairedLoading: { type: Boolean, default: false },
  err: { type: String, default: '' }
})
const emit = defineEmits(['paired'])

const testMethod = defineModel('testMethod', { type: String, default: '' })
const testY = defineModel('testY', { type: String, default: '' })
const testX = defineModel('testX', { type: String, default: '' })
const testGroup = defineModel('testGroup', { type: String, default: '' })
const result = defineModel('result', { type: Object, default: null })

const tabError = ref('')
const testRunning = ref(false)
const testCode = ref(false)

const isCorr = computed(() => testMethod.value.startsWith('cor.test'))
const needPair = computed(() => ['t.test.paired'].includes(testMethod.value))
const canRunTest = computed(() => {
  if (!props.hasSource) return false
  if (isCorr.value) return !!(testY.value && testX.value)
  if (!testY.value) return false
  return !!(testGroup.value || isCorr.value)
})
// 方法清单：suggest 不主动推荐配对检验，但它是常用方法 —— 始终补在列表末尾
const methodOptions = computed(() => {
  const list = [...props.methods]
  if (!list.some(m => m.id === 't.test.paired')) {
    list.push({ id: 't.test.paired', label: '配对 t 检验（逐位置）' })
  }
  return list
})
const sigClass = computed(() => {
  const p = result.value?.p
  if (p === null || p === undefined || Number.isNaN(p)) return ''
  return Number(p) < 0.05 ? 'sig' : 'ns'
})

async function runTest() {
  if (!canRunTest.value) { ElMessage.warning('请先选择检验所需的变量'); return }
  testRunning.value = true
  tabError.value = ''
  try {
    result.value = await statsTest(props.source, props.prep, {
      y: testY.value,
      x: isCorr.value ? testX.value : '',
      group: isCorr.value ? '' : testGroup.value,
      method: testMethod.value
    })
  } catch (e) {
    tabError.value = e.message
    result.value = null
  } finally {
    testRunning.value = false
  }
}
</script>
<template>
  <div class="sd-pane">
    <aside class="sd-params">
      <div class="sp-field">
        <label>检验方法</label>
        <el-select v-model="testMethod" size="small" filterable clearable
          placeholder="自动选择" style="width:100%">
          <el-option v-for="m in methodOptions" :key="m.id" :value="m.id" :label="m.label">
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
      <div v-if="testMethod === 't.test.paired' && result" class="sp-actions">
        <el-tooltip content="把配对的两列按行位置转成长表（id/variable/value），并在画布生成 配线+散点 图层；当前图会被替换，可撤销"
          placement="top">
          <el-button size="small" type="primary" plain :loading="pairedLoading" @click="emit('paired')">
            <el-icon class="el-icon--left"><Share /></el-icon>生成配对线图层
          </el-button>
        </el-tooltip>
      </div>
      <div v-if="needPair" class="sp-hint warn">
        配对检验按分组水平顺序逐位置配对，请确认是「同一样本的两次测量」。
      </div>
      <div v-else class="sp-hint">
        不选方法时按变量角色自动推荐；结果附带正态性 / 方差齐性检查。
      </div>
    </aside>

    <section class="sd-result">
      <el-alert v-if="err || tabError" type="error" :title="tabError || err" :closable="false" show-icon />
      <template v-if="result">
        <div class="test-card" :class="sigClass">
          <div class="test-title">
            <span class="gg-mono">{{ result.methodLabel }}</span>
            <span style="flex:1" />
            <el-tag :type="sigClass === 'sig' ? 'success' : 'info'" size="small" :disable-transitions="true">
              {{ sigClass === 'sig' ? '显著' : '不显著' }}
            </el-tag>
          </div>

          <div class="test-metrics">
            <div class="tm">
              <span class="tm-l">{{ result.estimateName || '统计量' }}</span>
              <span class="tm-v gg-mono">
                {{ result.estimateName ? num(result.estimate) : num(result.statistic) }}
              </span>
            </div>
            <div class="tm">
              <span class="tm-l">p 值</span>
              <span class="tm-v gg-mono">
                {{ pval(result.p) }}<span class="stars">{{ stars(result.p) }}</span>
              </span>
            </div>
            <div v-if="result.statistic !== null && result.estimateName" class="tm">
              <span class="tm-l">{{ isCorr ? 't 值' : '统计量' }}</span>
              <span class="tm-v gg-mono">
                {{ num(result.statistic) }}<template v-if="result.df">, df={{ num(result.df) }}</template>
              </span>
            </div>
            <div class="tm">
              <span class="tm-l">样本量</span>
              <span class="tm-v gg-mono">n = {{ result.n }}</span>
            </div>
          </div>

          <div v-if="result.groups && result.groups.length" class="test-groups">
            <span v-for="(g, i) in result.groups" :key="i" class="tg">{{ g }}</span>
          </div>

          <div v-if="result.notes && result.notes.length" class="test-notes">
            <div v-for="(n, i) in result.notes" :key="i" class="note-line">· {{ n }}</div>
          </div>

          <div class="res-code-head" style="margin-top:6px">
            <span>可复现 R 代码</span><span style="flex:1" />
            <el-button size="small" text @click="testCode = !testCode">
              <el-icon><Document /></el-icon>{{ testCode ? '隐藏' : '查看' }}
            </el-button>
            <el-button size="small" text @click="copyText(result.code, '检验代码已复制')">
              <el-icon><CopyDocument /></el-icon>
            </el-button>
          </div>
          <pre v-if="testCode" class="gg-mono code-pre">{{ result.code }}</pre>
        </div>
      </template>
      <div v-else class="gg-empty-hint" style="padding:24px">
        选择变量后点「运行检验」
      </div>
    </section>
  </div>
</template>
