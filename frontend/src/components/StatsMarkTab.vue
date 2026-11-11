<script setup>
// L3 图上标注页签（轻拆）：标注状态全在本组件（sigPlan_/sigPick 等），
// 显著性结果来自壳（最近一次检验），标注条目直接读写 spec store。
import { ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import { sigPlan } from '../api'
import { num } from '../statsShared'

const props = defineProps({
  active: { type: Boolean, default: false },   // 本页签是否处于打开状态
  testResult: { type: Object, default: null }  // L2 的检验结果（labelFor 的 p 值来源）
})

const spec = useSpecStore()
const ui = useUiStore()

const sigPlan_ = ref(null)
const sigLoading = ref(false)
const sigPick = ref([])             // 待添加的比较对（字符串 "A||B"）
const sigKind = ref('bracket')      // bracket | text
const sigLabelMode = ref('stars')   // stars | p | custom
const sigCustomLabel = ref('*')
const sigMarks = ref([])            // spec.spec.sigMarks 的镜像（模板遍历用）

// 同步 spec store 里的标注列表（壳与画布读写同一份）
watch(() => spec.spec.sigMarks, (v) => { sigMarks.value = v || [] }, { immediate: true, deep: false })

const canMark = ref(false)
function evalCanMark() {
  canMark.value = !!sigPlan_.value && sigPlan_.value.ok && (spec.spec.layers || []).length > 0
}
watch([sigPlan_, () => spec.spec.layers.length], evalCanMark, { immediate: true, deep: false })

async function loadSigPlan() {
  if (!(spec.spec.layers || []).length) { sigPlan_.value = null; evalCanMark(); return }
  sigLoading.value = true
  try {
    sigPlan_.value = await sigPlan(spec.spec)
  } catch (e) {
    sigPlan_.value = { ok: false, reason: e.message }
  } finally {
    sigLoading.value = false
    evalCanMark()
  }
}

// 图层 x/y 映射变化时重新规划；本页签被打开时也规划一次
let sigTimer = null
watch(() => JSON.stringify((spec.spec.layers || []).map(l => [l.geom, l.aes?.x?.map, l.aes?.y?.map])),
  () => {
    if (!ui.statsOpen) return
    clearTimeout(sigTimer); sigTimer = setTimeout(loadSigPlan, 350)
  },
  { immediate: true })
watch(() => props.active, (v) => { if (v) loadSigPlan() })

// 依据 L2 的检验结果或统一模板生成标注文字（逻辑与原 StatsPanel 完全一致）
function starOf(p) {
  if (p === null || p === undefined || Number.isNaN(Number(p))) return 'n.s.'
  const n = Number(p)
  if (n < 0.001) return '***'
  if (n < 0.01) return '**'
  if (n < 0.05) return '*'
  return 'n.s.'
}

function labelFor(pair) {
  if (sigLabelMode.value === 'custom') return sigCustomLabel.value || '*'
  const [g1, g2] = String(pair || '').split('||')
  const hit = (props.testResult?.pairs || []).find(x =>
    (String(x.group1) === g1 && String(x.group2) === g2) ||
    (String(x.group1) === g2 && String(x.group2) === g1))
  const p = hit ? hit.p : props.testResult?.p
  if (sigLabelMode.value === 'p') {
    if (p === null || p === undefined) return 'p = ?'
    return p < 0.0001 ? 'p < 0.0001' : `p = ${Number(p).toFixed(4)}`
  }
  // stars：优先用两两比较的 p；没有则退回整体检验 p
  return starOf(p)
}

// 切换「标注形态」后，已添加的标注也同步（括号 <-> 文字）
watch(sigKind, (k) => {
  const marks = spec.spec.sigMarks || []
  if (!marks.length) return
  marks.forEach(m => { m.kind = k })
  spec.renderNow()
})
// 切换「标签内容」后，已添加的标注同步更新（之前只对新加的生效）
watch([sigLabelMode, sigCustomLabel, () => props.testResult], () => {
  const marks = spec.spec.sigMarks || []
  if (!marks.length) return
  marks.forEach(m => { m.label = labelFor(`${m.group1}||${m.group2}`) })
  spec.renderNow()
})

function addPicked() {
  if (!sigPick.value.length) { ElMessage.warning('先选择要比较的分组对'); return }
  if (sigLabelMode.value === 'p' && !props.testResult) {
    ElMessage.warning('还没有检验结果：先到「统计检验」运行一次，p 值会显示为 p = ?')
  }
  const start = sigPlan_.value?.yStart ?? 0
  const step = sigPlan_.value?.yStep ?? 1
  let n = (spec.spec.sigMarks || []).length
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
  let n = (spec.spec.sigMarks || []).length
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
  ;(spec.spec.sigMarks || []).forEach((m, i) => spec.setSigMark(i, { yPos: Number((start + step * i).toFixed(3)) }))
  spec.renderNow()
}
</script>
<template>
  <div class="sd-pane">
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
</template>
