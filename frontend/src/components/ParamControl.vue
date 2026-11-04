<script setup>
// ParamControl：按参数 schema 渲染对应控件；支持"表达式模式"({expr:"code"})
import { computed } from 'vue'

const props = defineProps({
  schema: { type: Object, required: true },   // {name, widget, label, options, min, max, step, exprOk}
  modelValue: { default: null }
})
const emit = defineEmits(['update:modelValue'])

const isExpr = computed(() => props.modelValue && typeof props.modelValue === 'object' && !Array.isArray(props.modelValue) && 'expr' in props.modelValue)
const exprMode = computed({
  get: () => isExpr.value,
  set: (on) => {
    if (on) emit('update:modelValue', { expr: String(rawVal.value ?? '') })
    else emit('update:modelValue', rawPrimitiveFromExpr())
  }
})
function rawPrimitiveFromExpr() {
  const code = String(props.modelValue?.expr ?? '').trim()
  if (code === 'TRUE' || code === 'true') return true
  if (code === 'FALSE' || code === 'false') return false
  if (/^-?\d+(\.\d+)?$/.test(code)) return Number(code)
  return code === '' ? null : code
}
const rawVal = computed(() => (isExpr.value ? props.modelValue.expr : props.modelValue))

function set(v) {
  if (v === '' || v === undefined || v === null) emit('update:modelValue', null)
  else emit('update:modelValue', v)
}
// 数字或 R 表达式：能解析成数字就发数字，否则发 {expr}（用于注释坐标等）
function setNumOrExpr(v) {
  const s = String(v ?? '').trim()
  if (!s) return emit('update:modelValue', null)
  if (/^[-+]?(\d+(\.\d*)?|\.\d+)([eE][-+]?\d+)?$/.test(s)) return emit('update:modelValue', Number(s))
  emit('update:modelValue', { expr: s })
}
function setExpr(code) {
  if (!String(code).trim()) emit('update:modelValue', null)
  else emit('update:modelValue', { expr: code })
}

const numModel = computed({
  get: () => (typeof rawVal.value === 'number' ? rawVal.value : undefined),
  set: (v) => set(v)
})
const strModel = computed({
  get: () => (rawVal.value === null || rawVal.value === undefined ? '' : String(rawVal.value)),
  set: (v) => set(v)
})
const boolModel = computed({
  get: () => rawVal.value === true,
  set: (v) => set(v ? true : null)
})
const colorModel = computed({
  get: () => (/^#[0-9a-fA-F]{3,8}$/.test(String(rawVal.value)) ? String(rawVal.value) : ''),
  set: (v) => set(v || null)
})
const selectModel = computed({
  get: () => (rawVal.value === null || rawVal.value === undefined ? '' : String(rawVal.value)),
  set: (v) => set(v || null)
})
// numberOrExpr 控件的显示文本（数字直接显示，表达式由 exprMode 分支接管）
const numOrExprText = computed(() => (rawVal.value === null || rawVal.value === undefined ? '' : String(rawVal.value)))

const shapeOpts = [
  { v: '0', l: '0 方块' }, { v: '1', l: '1 圆' }, { v: '2', l: '2 三角↑' }, { v: '3', l: '3 加号' },
  { v: '4', l: '4 叉' }, { v: '5', l: '5 菱形' }, { v: '6', l: '6 倒三角' }, { v: '7', l: '7 方叉' },
  { v: '8', l: '8 星号' }, { v: '9', l: '9 菱加' }, { v: '10', l: '10 圆点圈' }, { v: '11', l: '11 双三角' },
  { v: '12', l: '12 方加' }, { v: '13', l: '13 方叉' }, { v: '14', l: '14 方箭' }, { v: '15', l: '15 实方块' },
  { v: '16', l: '16 实圆' }, { v: '17', l: '17 实三角' }, { v: '18', l: '18 实菱' }, { v: '19', l: '19 实圆大' },
  { v: '20', l: '20 小实圆' }, { v: '21', l: '21 圆(可填充)' }, { v: '22', l: '22 方(可填充)' },
  { v: '23', l: '23 菱(可填充)' }, { v: '24', l: '24 三角(可填充)' }, { v: '25', l: '25 倒三角(可填充)' }
]
const linetypeOpts = ['blank', 'solid', 'dashed', 'dotted', 'dotdash', 'longdash', 'twodash']
  .map(v => ({ v, l: v }))
</script>

<template>
  <div class="p-ctl">
    <!-- 表达式模式 -->
    <template v-if="exprMode">
      <el-input :model-value="rawVal" size="small" class="gg-mono" placeholder="R 表达式"
        @update:model-value="setExpr" />
    </template>

    <template v-else>
      <el-input-number v-if="schema.widget === 'number'" v-model="numModel" size="small"
        :min="schema.min" :max="schema.max" :step="schema.step ?? 1"
        :precision="schema.step && schema.step < 1 ? 2 : undefined" controls-position="right"
        style="width:100%" />
      <el-switch v-else-if="schema.widget === 'bool'" v-model="boolModel" size="small" />
      <el-select v-else-if="schema.widget === 'select'" :model-value="selectModel" size="small"
        filterable clearable style="width:100%" @update:model-value="set($event || null)">
        <el-option v-for="o in schema.options || []" :key="o"
          :value="typeof o === 'object' ? o.v : o" :label="typeof o === 'object' ? o.l : o" />
      </el-select>
      <el-select v-else-if="schema.widget === 'shape'" :model-value="selectModel" size="small"
        filterable clearable style="width:100%" @update:model-value="set($event || null)">
        <el-option v-for="o in shapeOpts" :key="o.v" :value="o.v" :label="o.l">
          <span style="display:flex;justify-content:space-between;gap:12px">
            <span>{{ o.l }}</span><span class="gg-mono">{{ o.v }}</span>
          </span>
        </el-option>
      </el-select>
      <el-select v-else-if="schema.widget === 'linetype'" :model-value="selectModel" size="small"
        clearable style="width:100%" @update:model-value="set($event || null)">
        <el-option v-for="o in linetypeOpts" :key="o.v" :value="o.v" :label="o.l">
          <span style="display:flex;justify-content:space-between;gap:12px">
            <span>{{ o.l }}</span>
            <svg width="40" height="8">
              <line x1="0" y1="4" x2="40" y2="4" stroke="#888" stroke-width="2"
                :stroke-dasharray="{ solid: '0', dashed: '6 3', dotted: '2 2', dotdash: '6 2 1 2', longdash: '10 3', twodash: '6 3 2 3', blank: '0 10' }[o.v]" />
            </svg>
          </span>
        </el-option>
      </el-select>
      <el-color-picker v-else-if="schema.widget === 'color'" v-model="colorModel" size="small" show-alpha
        :predefine="['#4a90d9', '#e8734a', '#54b28e', '#2C3E50', '#c0392b', '#8e44ad', '#f1c40f']" />
      <el-input v-else-if="schema.widget === 'numberOrExpr'" :model-value="numOrExprText" size="small"
        class="gg-mono" placeholder="数字或 R 表达式，如 5 / mean(df$x)"
        @update:model-value="setNumOrExpr" />
      <el-input v-else v-model="strModel" size="small" clearable />
    </template>

    <el-tooltip v-if="schema.exprOk" :content="exprMode ? '切回普通值' : '切换为 R 表达式'" placement="top">
      <el-button size="small" text class="fx-btn" :class="{ on: exprMode }"
        @click="exprMode = !exprMode">fx</el-button>
    </el-tooltip>
  </div>
</template>

<style scoped>
.fx-btn { font-family: Georgia, serif; font-style: italic; }
</style>
