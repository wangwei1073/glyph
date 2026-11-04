<script setup>
// 标签 + 图例 面板
import { computed } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import ParamControl from './ParamControl.vue'
import ThemeTextEditor from './ThemeTextEditor.vue'

const meta = useMetaStore()
const spec = useSpecStore()

const labsFields = [
  { key: 'title', label: '主标题 title', ph: '图表标题' },
  { key: 'subtitle', label: '副标题 subtitle', ph: '副标题' },
  { key: 'caption', label: '注释 caption', ph: '右下角数据来源等' },
  { key: 'tag', label: '角标 tag', ph: '如 图 1' },
  { key: 'x', label: 'x 轴标题', ph: '留空 = 使用列名' },
  { key: 'y', label: 'y 轴标题', ph: '留空 = 使用列名' }
]

const usedAes = computed(() => {
  const used = new Set()
  for (const l of spec.spec.layers) {
    for (const k of Object.keys(l.aes || {})) used.add(k)
  }
  return [...used].filter(k => !['x', 'y', 'group'].includes(k))
})

const ELEM_FOR = {
  title: 'plot.title', subtitle: 'plot.subtitle', caption: 'plot.caption',
  tag: 'plot.tag', x: 'axis.title.x', y: 'axis.title.y'
}
function elemFor(key) { return ELEM_FOR[key] || key }
function hasFont(key) {
  const el = spec.spec.theme.elements[elemFor(key)]
  return !!(el && (el.props && Object.keys(el.props).length))
}
function setLab(key, v) {
  if (!v || !String(v).trim()) delete spec.spec.labs[key]
  else spec.spec.labs[key] = v
}
function labVal(key) { return spec.spec.labs[key] ?? '' }

// guides
const guideAes = computed(() => {
  const used = new Set(usedAes.value)
  for (const s of spec.spec.scales) used.add(s.aes)
  return [...used]
})
function guideOf(aes) { return spec.spec.guides[aes] ?? null }
function setGuideType(aes, t) {
  if (!t) delete spec.spec.guides[aes]
  else if (['none', 'legend'].includes(t)) spec.spec.guides[aes] = t
  else spec.spec.guides[aes] = { type: t, params: {} }
}
function guideParams(aes) {
  const g = guideOf(aes)
  if (!g || typeof g === 'string') return []
  return meta.guideByName[g.type]?.params || []
}
function setGuideParam(aes, name, v) {
  const g = spec.spec.guides[aes]
  if (!g || typeof g === 'string') return
  if (v === null) delete g.params[name]
  else g.params[name] = v
}
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">图表标签（labs）</div>
    <div v-for="f in labsFields" :key="f.key" class="p-row">
      <label>{{ f.label }}</label>
      <el-input :model-value="labVal(f.key)" size="small" clearable :placeholder="f.ph"
        @update:model-value="setLab(f.key, $event)" />
      <el-popover placement="left" :width="300" trigger="click">
        <template #reference>
          <el-button size="small" text class="font-btn" :class="{ on: hasFont(f.key) }"
            title="字体 / 字号 / 颜色">Aa</el-button>
        </template>
        <ThemeTextEditor :element="elemFor(f.key)" />
      </el-popover>
    </div>

    <div class="gg-subhead" style="margin-top:14px">图例标题（映射的 aes 标题）</div>
    <div v-for="a in usedAes" :key="'lt' + a" class="p-row">
      <label>{{ meta.aesByName[a]?.label || a }}</label>
      <el-input :model-value="labVal(a)" size="small" clearable placeholder="留空 = 默认"
        @update:model-value="setLab(a, $event)" />
      <el-popover placement="left" :width="300" trigger="click">
        <template #reference>
          <el-button size="small" text class="font-btn" :class="{ on: hasFont(a) }"
            title="图例标题字体">Aa</el-button>
        </template>
        <ThemeTextEditor element="legend.title" />
      </el-popover>
    </div>

    <div class="gg-subhead" style="margin-top:18px">图例/引导（guides）</div>
    <div v-for="a in guideAes" :key="'g' + a" style="border-bottom:1px dashed var(--gg-border); padding-bottom:6px; margin-bottom:6px">
      <div class="p-row">
        <label>{{ meta.aesByName[a]?.label || a }}</label>
        <el-select :model-value="typeof guideOf(aes) === 'string' ? guideOf(aes) : (guideOf(aes)?.type || '')"
          size="small" style="width:100%" clearable placeholder="默认" @update:model-value="setGuideType(a, $event || '')">
          <el-option v-for="g in meta.guides" :key="g.name" :value="g.name" :label="g.label" />
        </el-select>
      </div>
      <template v-if="guideOf(aes) && typeof guideOf(aes) !== 'string'">
        <div v-for="p in guideParams(a)" :key="p.name" class="p-row">
          <label>{{ p.label }}</label>
          <ParamControl :schema="p" :model-value="guideOf(aes).params[p.name] ?? null"
            @update:model-value="setGuideParam(a, p.name, $event)" />
        </div>
      </template>
    </div>
    <div v-if="!guideAes.length" class="gg-empty-hint" style="padding:16px">
      添加带颜色/填充等映射的图层后，可在此定制图例
    </div>
  </div>
</template>
