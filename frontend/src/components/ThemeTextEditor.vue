<script setup>
// 主题文本元素精编：给 plot.title / plot.subtitle / plot.caption 等提供
// "字体/字号/样式/颜色/对齐/角度/行距/边距" 的一站式编辑（写入 spec.theme.elements）
import { computed } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import ParamControl from './ParamControl.vue'

const props = defineProps({
  element: { type: String, required: true }  // 如 plot.title
})
const meta = useMetaStore()
const spec = useSpecStore()

const state = computed(() => spec.spec.theme.elements[props.element] ?? null)
const setState = (val) => {
  const els = { ...spec.spec.theme.elements }
  if (val === null) delete els[props.element]
  else els[props.element] = val
  spec.setTheme({ elements: els })
}
const isBlank = computed(() => !!(state.value && state.value.blank))
const curProps = computed(() => (state.value && !state.value.blank ? (state.value.props || {}) : {}))

function ensureText() {
  if (!state.value || state.value.blank || !state.value.props) {
    setState(state.value && state.value.props ? state.value : { type: 'text', props: {} })
  }
}
function toggleBlank(on) {
  if (!on) {
    if (state.value && state.value.props && Object.keys(state.value.props).length) {
      setState({ type: 'text', props: state.value.props })
    } else setState(null)
  } else setState({ blank: true })
}
function setProp(name, v) {
  ensureText()
  const p = { ...state.value.props }
  if (v === null || v === '' || v === undefined) delete p[name]
  else p[name] = v
  if (Object.keys(p).length) setState({ type: 'text', props: p })
  else setState(null)
}
function setMargin(k, v) {
  ensureText()
  const p = { ...state.value.props }
  const m = { ...(p.margin || {}) }
  if (v === null || v === undefined) delete m[k]
  else m[k] = v
  if (Object.keys(m).length) p.margin = m
  else delete p.margin
  if (Object.keys(p).length) setState({ type: 'text', props: p })
  else setState(null)
}

const schema = computed(() => {
  const s = meta.themeElementsOf('text').map(p => ({ ...p, exprOk: p.name === 'family' }))
  return s.filter(p => p.name !== 'margin' && p.name !== 'debug')
})
const marginKeys = [['t', '上'], ['r', '右'], ['b', '下'], ['l', '左']]
</script>

<template>
  <div class="tedit">
    <div class="tedit-head">
      <span class="gg-mono" style="font-size:11px">{{ element }}</span>
      <el-checkbox size="small" :model-value="isBlank" @update:model-value="toggleBlank">
        blank（无）
      </el-checkbox>
    </div>

    <template v-if="!isBlank">
      <div v-for="p in schema" :key="p.name" class="p-row" style="padding: 3px 0">
        <label style="width:78px">{{ p.label }}</label>
        <ParamControl :schema="p" :model-value="curProps[p.name] ?? null"
          @update:model-value="setProp(p.name, $event)" />
      </div>
      <div class="p-row" style="padding: 3px 0">
        <label style="width:78px">margin</label>
        <div style="display:flex; gap:4px">
          <div v-for="mk in marginKeys" :key="mk[0]" class="marg">
            <span>{{ mk[1] }}</span>
            <el-input-number size="small" :model-value="curProps.margin?.[mk[0]]"
              controls-position="right" style="width:62px"
              @update:model-value="setMargin(mk[0], $event)" />
          </div>
        </div>
      </div>
    </template>
    <div v-else style="padding:6px 0;font-size:12px;color:var(--el-text-color-secondary)">
      已设为 element_blank()（隐藏该元素）
    </div>
  </div>
</template>

<style scoped>
.tedit-head {
  display: flex; align-items: center; justify-content: space-between;
  padding-bottom: 6px; border-bottom: 1px dashed var(--gg-border); margin-bottom: 6px;
}
.marg { display: flex; align-items: center; gap: 3px; font-size: 11px; }
</style>
