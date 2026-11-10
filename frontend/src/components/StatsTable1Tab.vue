<script setup>
// L5 基线特征表页签（轻拆）：汇总变量/结果经 defineModel 与壳共享，
// 列选项（t1Cols/t1StatOptions）由本组件在页签激活或手动刷新时加载。
import { computed, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { table1Columns, table1Build, table1Export, downloadBlob } from '../api'
import { copyText } from '../statsShared'

const props = defineProps({
  active: { type: Boolean, default: false },
  source: { type: Object, default: null },
  prep: { type: Object, default: () => ({}) },
  hasSource: { type: Boolean, default: false },
  err: { type: String, default: '' }
})

const t1Vars = defineModel('t1Vars', { type: Array, default: () => [] })
const t1By = defineModel('t1By', { type: String, default: '' })
const t1Stat = defineModel('t1Stat', { type: String, default: 'mean_sd' })
const t1AddP = defineModel('t1AddP', { type: Boolean, default: true })
const t1Overall = defineModel('t1Overall', { type: Boolean, default: false })
const t1Digits = defineModel('t1Digits', { type: Number, default: 2 })
const result = defineModel('result', { type: Object, default: null })

const tabError = ref('')
const t1Running = ref(false)
const t1Exporting = ref('')
const t1CodeOpen = ref(false)
const t1Cols = ref({ all: [], groupable: [] })
const t1StatOptions = ref([])
const canT1 = computed(() => props.hasSource && t1Vars.value.length > 0)

async function loadT1Columns() {
  if (!props.hasSource) { t1Cols.value = { all: [], groupable: [] }; return }
  try {
    const r = await table1Columns(props.source, props.prep)
    t1Cols.value = { all: r.all || [], groupable: r.groupable || [] }
    t1StatOptions.value = r.stats || []
    t1Vars.value = t1Vars.value.filter(v => t1Cols.value.all.includes(v))
    if (t1By.value && !t1Cols.value.groupable.includes(t1By.value)) t1By.value = ''
    if (!t1Vars.value.length) t1Vars.value = t1Cols.value.all.filter(v => v !== t1By.value)
  } catch (e) {
    tabError.value = e.message
  }
}

// 页签激活时加载（与原 watch(tab) 语义一致）
watch(() => props.active, (v) => { if (v) loadT1Columns() })

const t1Opts = () => ({
  vars: t1Vars.value, by: t1By.value, statId: t1Stat.value,
  addP: t1AddP.value, includeOverall: t1Overall.value, digits: t1Digits.value
})

async function runT1() {
  if (!canT1.value) { ElMessage.warning('请至少选择一个变量'); return }
  t1Running.value = true
  tabError.value = ''
  try {
    result.value = await table1Build(props.source, props.prep, t1Opts())
    t1CodeOpen.value = false
  } catch (e) {
    tabError.value = e.message
    result.value = null
  } finally {
    t1Running.value = false
  }
}

async function exportT1(format) {
  if (!result.value) return
  t1Exporting.value = format
  try {
    const res = await table1Export(props.source, props.prep, t1Opts(), format)
    if (!res.ok || !res.url) throw new Error(res.error || '导出失败')
    const r = await fetch(res.url)
    if (!r.ok) throw new Error(`下载失败: HTTP ${r.status}`)
    downloadBlob(await r.blob(), res.filename)
    ElMessage.success(`已导出 ${res.filename}`)
  } catch (e) {
    ElMessage.error('导出失败: ' + e.message)
  } finally {
    t1Exporting.value = ''
  }
}
</script>
<template>
  <div class="sd-pane">
    <aside class="sd-params">
      <div class="sp-field">
        <label>汇总变量</label>
        <el-select v-model="t1Vars" size="small" multiple filterable collapse-tags
          collapse-tags-tooltip placeholder="选择变量（默认全部）" style="width:100%">
          <el-option v-for="c in t1Cols.all" :key="c" :value="c" :label="c" />
        </el-select>
      </div>
      <div class="sp-field">
        <label>分组变量</label>
        <el-select v-model="t1By" size="small" filterable clearable
          placeholder="（可选）按组比较" style="width:100%">
          <el-option v-for="c in t1Cols.groupable" :key="c" :value="c" :label="c" />
        </el-select>
      </div>
      <div class="sp-field">
        <label>连续变量统计量</label>
        <el-select v-model="t1Stat" size="small" style="width:100%">
          <el-option v-for="s in t1StatOptions" :key="s.id" :value="s.id" :label="s.label" />
        </el-select>
      </div>
      <div class="sp-field">
        <label>小数位</label>
        <el-input-number v-model="t1Digits" size="small" :min="0" :max="4" :step="1"
          controls-position="right" style="width:100%" />
      </div>
      <div class="sp-actions" style="gap:12px">
        <el-checkbox v-model="t1AddP" size="small" :disabled="!t1By">组间 p 值</el-checkbox>
        <el-checkbox v-model="t1Overall" size="small" :disabled="!t1By">合计列</el-checkbox>
      </div>
      <div class="sp-actions">
        <el-button size="small" type="primary" :loading="t1Running" :disabled="!canT1" @click="runT1">
          <el-icon class="el-icon--left"><Grid /></el-icon>生成
        </el-button>
        <el-button size="small" text @click="loadT1Columns"><el-icon><Refresh /></el-icon></el-button>
      </div>
      <div class="sp-hint">
        连续变量按所选统计量，分类变量按 n (%)；缺失值单独统计。
      </div>
    </aside>

    <section class="sd-result">
      <el-alert v-if="err || tabError" type="error" :title="tabError || err" :closable="false" show-icon />
      <template v-if="result">
        <div class="res-head">
          <span class="gg-mono">
            {{ result.n }} 行 · {{ result.vars.length }} 变量<template v-if="result.by"> · 按 {{ result.by }} 分组</template>
            · 引擎 {{ result.engine }}
          </span>
          <span style="flex:1" />
          <el-button size="small" text @click="t1CodeOpen = !t1CodeOpen">
            <el-icon><Document /></el-icon>{{ t1CodeOpen ? '隐藏代码' : '代码' }}
          </el-button>
          <el-dropdown size="small" :disabled="!!t1Exporting" @command="exportT1">
            <el-button size="small" text :loading="!!t1Exporting">
              <el-icon><Download /></el-icon>导出
            </el-button>
            <template #dropdown>
              <el-dropdown-menu>
                <el-dropdown-item command="docx">Word (.docx)</el-dropdown-item>
                <el-dropdown-item command="xlsx">Excel (.xlsx)</el-dropdown-item>
                <el-dropdown-item command="csv">CSV</el-dropdown-item>
              </el-dropdown-menu>
            </template>
          </el-dropdown>
        </div>

        <div class="gg-scroll res-table-wrap">
          <table class="stat-table">
            <thead>
              <tr>
                <th v-for="(c, i) in result.columns" :key="i" :class="{ n: i > 0 }">{{ c }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="(row, ri) in result.table" :key="ri">
                <td v-for="(c, ci) in result.columns" :key="ci"
                  :class="{ 'gg-mono': ci === 0, n: ci > 0 }">{{ row[c] }}</td>
              </tr>
            </tbody>
          </table>
        </div>

        <div v-if="result.notes && result.notes.length" class="reg-notes">
          <div v-for="(n, i) in result.notes" :key="i" class="note-line">· {{ n }}</div>
        </div>

        <div v-if="t1CodeOpen" class="res-code">
          <div class="res-code-head">
            <span>可复现 R 代码</span><span style="flex:1" />
            <el-button size="small" text @click="copyText(result.code, '基线表代码已复制')">
              <el-icon><CopyDocument /></el-icon>
            </el-button>
          </div>
          <pre class="gg-mono code-pre">{{ result.code }}</pre>
        </div>
      </template>
      <div v-else class="gg-empty-hint" style="padding:24px">
        选择变量后点「生成」（可选分组变量做组间比较）
      </div>
    </section>
  </div>
</template>
