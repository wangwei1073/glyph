<script setup>
// L1 描述统计页签（轻拆：模板与私有逻辑在此；输入变量/结果经 defineModel 与壳共享，
// 壳的 refreshColumns 也读写这两个 model）
import { computed, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { statsSummary, downloadBlob } from '../api'
import { copyText, num } from '../statsShared'

const props = defineProps({
  numericCols: { type: Array, default: () => [] },
  groupCols: { type: Array, default: () => [] },
  source: { type: Object, default: null },
  prep: { type: Object, default: () => ({}) },
  hasSource: { type: Boolean, default: false },
  loading: { type: Boolean, default: false },
  err: { type: String, default: '' }       // 列加载等共用错误（壳的 error）
})
const emit = defineEmits(['refresh'])

const vars = defineModel('vars', { type: Array, default: () => [] })
const groupBy = defineModel('groupBy', { type: Array, default: () => [] })
const result = defineModel('result', { type: Object, default: null })

const tabError = ref('')
const descRunning = ref(false)
const showCode = ref(false)
const canRunDesc = computed(() => props.hasSource && props.numericCols.length > 0)

async function runDesc() {
  if (!canRunDesc.value) { ElMessage.warning('先选择数据与至少一个数值列'); return }
  descRunning.value = true
  tabError.value = ''
  try {
    result.value = await statsSummary(props.source, props.prep, vars.value, groupBy.value)
  } catch (e) {
    tabError.value = e.message
    result.value = null
  } finally {
    descRunning.value = false
  }
}
</script>
<template>
  <div class="sd-pane">
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
        <el-button size="small" text @click="emit('refresh')" :loading="loading">
          <el-icon><Refresh /></el-icon>
        </el-button>
      </div>
      <div v-if="!numericCols.length && !loading" class="sp-hint">当前数据没有数值列可汇总</div>
      <div v-else class="sp-hint">
        均值 / SD 按列忽略缺失；有分组时自动追加「合计」行。
      </div>
    </aside>

    <section class="sd-result">
      <el-alert v-if="err || tabError" type="error" :title="tabError || err" :closable="false" show-icon />
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
</template>
