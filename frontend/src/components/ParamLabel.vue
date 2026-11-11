<script setup>
// 参数行标签：label + 可选「?」说明图标（tooltip 显示中文说明与默认值）。
// 说明来自 registry 的 PARAM_DESC / pv(desc)，未收录的参数只显示名字。
import { computed } from 'vue'

const props = defineProps({
  label: { type: String, required: true },
  name: { type: String, default: '' },
  desc: { type: String, default: '' },
  def: { default: null }   // 默认值（后端 formals 内省）
})

const hasTip = computed(() => !!(props.desc || (props.def !== null && props.def !== undefined)))
const defText = computed(() => {
  if (props.def === null || props.def === undefined) return ''
  if (Array.isArray(props.def)) return `c(${props.def.map(v => JSON.stringify(v)).join(', ')})`
  return String(props.def)
})
</script>
<template>
  <span class="param-label-wrap">
    <span :title="name">{{ label }}</span>
    <el-tooltip v-if="hasTip" placement="top" effect="light">
      <template #content>
        <div style="max-width:240px;line-height:1.5">
          <div v-if="desc">{{ desc }}</div>
          <div v-if="defText" style="opacity:.75;margin-top:2px">默认：{{ defText }}</div>
        </div>
      </template>
      <el-icon class="param-help"><QuestionFilled /></el-icon>
    </el-tooltip>
  </span>
</template>
<style scoped>
.param-label-wrap { display: inline-flex; align-items: center; gap: 2px; min-width: 0; }
.param-help { color: var(--el-text-color-secondary); cursor: help; font-size: 12px; flex-shrink: 0; }
.param-help:hover { color: var(--gg-accent); }
</style>
