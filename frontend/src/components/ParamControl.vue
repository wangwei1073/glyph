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

// ---- 滑块：只有「范围明确、步进可推」的参数才用滑块 ----
// 规则：
//   1) schema 显式给了 min 和 max → 直接用；
//   2) alpha / 透明度 / 比例类天然 0-1；
//   3) 有 min 无 max 的（size、linewidth…）用 min..min+合理上限，避免无界拖动。
const R0_1 = /(^|[.])(alpha|opacity|transparency|scalewidth|width)$/i
const R0_100 = /(^|[.])(angle|rotation)$/i

function sliderRange(s) {
  const hasMin = s.min !== undefined && s.min !== null
  const hasMax = s.max !== undefined && s.max !== null
  const step = s.step ?? 0.05
  if (hasMin && hasMax) {
    return { min: s.min, max: s.max, step, precision: step < 1 ? 2 : 0 }
  }
  if (R0_1.test(s.name || '')) {
    return { min: hasMin ? s.min : 0, max: 1, step: 0.05, precision: 2 }
  }
  if (R0_100.test(s.name || '')) {
    return { min: -180, max: 180, step: 1, precision: 0 }
  }
  if (hasMin && s.min === 0) {
    // 无上界但下界为 0 的尺寸类：给一个看得见效果的上限
    const max = /(size|stroke|linewidth|width|linemitre|nudge)/i.test(s.name || '') ? 20 : 100
    return { min: 0, max, step: step > 0 ? step : 0.5, precision: step < 1 ? 2 : 0 }
  }
  return null
}
const fmtNum = (v) => (Number.isInteger(Number(v)) ? String(v) : String(Number(v).toFixed(2)))
const numModel = computed({
  get: () => (typeof rawVal.value === 'number' ? rawVal.value : undefined),
  set: (v) => set(v)
})
const strModel = computed({
  get: () => (rawVal.value === null || rawVal.value === undefined ? '' : String(rawVal.value)),
  set: (v) => set(v)
})
const boolModel = computed({
  // 参数缺失时回落到 schema 默认值（例如 boxplot 的 outliers 默认 TRUE），
  // 关闭开关必须写入 false，而不是删掉参数（删掉会回到默认 TRUE）
  get: () => {
    const v = rawVal.value
    if (v === null || v === undefined || v === '') {
      const d = props.schema?.default
      return d === true || d === 1 || String(d).toUpperCase() === 'TRUE'
    }
    return v === true || v === 1 || String(v).toUpperCase() === 'TRUE'
  },
  set: (v) => emit('update:modelValue', !!v)
})
function toHexColor(v) {
  const s = String(v ?? '').trim()
  if (!s) return ''
  if (/^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$/.test(s)) return s.slice(0, 7)
  if (/^#[0-9a-fA-F]{3}$/.test(s)) {
    return '#' + s.slice(1).split('').map(c => c + c).join('')
  }
  const m = s.match(/^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})/i)
  if (m) {
    const hex = [m[1], m[2], m[3]].map(n => Math.max(0, Math.min(255, Number(n))).toString(16).padStart(2, '0'))
    return '#' + hex.join('')
  }
  return ''
}
const colorModel = computed({
  get: () => toHexColor(rawVal.value),
  set: (v) => set(toHexColor(v) || null)
})
const selectModel = computed({
  get: () => (rawVal.value === null || rawVal.value === undefined ? '' : String(rawVal.value)),
  set: (v) => set(v || null)
})
// numberOrExpr 控件的显示文本（数字直接显示，表达式由 exprMode 分支接管）
const numOrExprText = computed(() => (rawVal.value === null || rawVal.value === undefined ? '' : String(rawVal.value)))

// R 的 pch 只有 0-25 是合法绘图符号：>25、非数字字符串在 R 里画不出来或直接报错。
// 0-14 空心（由 colour 决定），15-20 实心（由 colour 决定），21-25 有边框+填充（colour + fill）
const shapeOpts = [
  { v: '0',  l: '0 方块（空）',        g: '空心' },
  { v: '1',  l: '1 圆（空）',          g: '空心' },
  { v: '2',  l: '2 三角↑（空）',       g: '空心' },
  { v: '3',  l: '3 加号',              g: '空心' },
  { v: '4',  l: '4 叉',                g: '空心' },
  { v: '5',  l: '5 菱形（空）',        g: '空心' },
  { v: '6',  l: '6 三角↓（空）',       g: '空心' },
  { v: '7',  l: '7 方叉（空）',        g: '空心' },
  { v: '8',  l: '8 星号',              g: '空心' },
  { v: '9',  l: '9 菱加',              g: '空心' },
  { v: '10', l: '10 圆点圈',           g: '空心' },
  { v: '11', l: '11 双三角',           g: '空心' },
  { v: '12', l: '12 方加',             g: '空心' },
  { v: '13', l: '13 圆叉',             g: '空心' },
  { v: '14', l: '14 方箭',             g: '空心' },
  { v: '15', l: '15 实方块',           g: '实心' },
  { v: '16', l: '16 实圆',             g: '实心' },
  { v: '17', l: '17 实三角',           g: '实心' },
  { v: '18', l: '18 实菱',             g: '实心' },
  { v: '19', l: '19 实圆（大）',       g: '实心' },
  { v: '20', l: '20 实圆（小）',       g: '实心' },
  { v: '21', l: '21 圆（可填填充色）', g: '可填充' },
  { v: '22', l: '22 方（可填填充色）', g: '可填充' },
  { v: '23', l: '23 菱（可填填充色）', g: '可填充' },
  { v: '24', l: '24 三角（可填填充色）', g: '可填充' },
  { v: '25', l: '25 三角↓（可填填充色）', g: '可填充' }
]
const shapeGroups = ['空心', '实心', '可填充']
const shapeByGroup = (g) => shapeOpts.filter(o => o.g === g)
// 非法值（>25、非数字）在 R 里会报错：选择框显示为空，而不是留一个看不懂/画不出的值
const shapeModel = computed({
  get: () => {
    const s = String(rawVal.value ?? '').trim()
    if (!s) return ''
    return /^(1?\d|2[0-5])$/.test(s) ? s : ''
  },
  set: (v) => set(v === '' || v === null ? null : v)
})
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
      <!-- 有明确取值范围的数值参数：滑块 + 数值框并排（拖得动，也能精确输入） -->
      <template v-if="schema.widget === 'number' && sliderRange(schema)">
        <el-slider v-model="numModel" class="p-slider" size="small"
          :min="sliderRange(schema).min" :max="sliderRange(schema).max"
          :step="sliderRange(schema).step" :format-tooltip="fmtNum" />
        <el-input-number v-model="numModel" size="small" class="p-num"
          :min="sliderRange(schema).min" :max="sliderRange(schema).max"
          :step="sliderRange(schema).step" :precision="sliderRange(schema).precision"
          controls-position="right" />
      </template>
      <el-input-number v-else-if="schema.widget === 'number'" v-model="numModel" size="small"
        :min="schema.min" :max="schema.max" :step="schema.step ?? 1"
        :precision="schema.step && schema.step < 1 ? 2 : undefined" controls-position="right"
        style="width:100%" />
      <el-switch v-else-if="schema.widget === 'bool'" v-model="boolModel" size="small" />
      <!-- allow-create：枚举下拉也允许手填。少数参数在不同 geom 下含义不同
           （例如 orientation 在柱状图是 x/y，在 geom_sf 是数值），
           允许自定义可避免下拉把合法取值挡在外面。 -->
      <el-select v-else-if="schema.widget === 'select'" :model-value="selectModel" size="small"
        filterable clearable allow-create default-first-option style="width:100%"
        @update:model-value="set($event || null)">
        <el-option v-for="o in schema.options || []" :key="o"
          :value="typeof o === 'object' ? o.v : o" :label="typeof o === 'object' ? o.l : o" />
      </el-select>
      <el-select v-else-if="schema.widget === 'shape'" v-model="shapeModel" size="small"
        filterable clearable style="width:100%">
        <el-option-group v-for="g in shapeGroups" :key="g" :label="g">
          <el-option v-for="o in shapeByGroup(g)" :key="o.v" :value="o.v" :label="o.l">
            <span style="display:flex;justify-content:space-between;gap:12px">
              <span>{{ o.l }}</span><span class="gg-mono">{{ o.v }}</span>
            </span>
          </el-option>
        </el-option-group>
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
.fx-btn { font-family: Georgia, serif; font-style: italic; flex-shrink: 0; }
/* 滑块 + 数值框：滑块占剩余宽度，数值框固定宽，整行不换行。
   视觉对齐：手柄是 14px 圆，在最小值时手柄中心=轨道起点，
   左边缘会凸出 7px。给滑块容器 padding-left:7px，让手柄在最左时
   其「圆的左边缘」与其他控件的左边框对齐。 */
.p-slider {
  flex: 1; min-width: 80px; margin-right: 10px;
  padding: 0 0 0 7px;
  --el-slider-main-bg-color: var(--gg-brand, #2f6fbf);
}
/* 手柄缩小到与 el-switch 的圆钮相近（14px），轨道压细 */
.p-slider :deep(.el-slider__button) {
  width: 14px; height: 14px; border-width: 1px;
}
/* 手柄垂直居中：wrapper 保持 Element 的 top:-X 逻辑，
   用 margin-top 把 14px 手柄压回 4px 轨道的中线。
   （Element 默认 wrapper 高 36px、top -15px；我们把手柄缩到 14px，
   重新计算：手柄中心应与 runway 中心重合 → top = (4-14)/2 = -5px） */
/* 手柄垂直居中（相对 4px 轨道）：
   Element 把 wrapper 定位在 top:-15px（36px 高 wrapper 时代的公式）。
   我们 wrapper 缩到 14px：手柄中心要落在 runway 顶 + 2px 处，
   即 wrapper 顶 = runway顶 - 5px。按钮在 wrapper 内部顶对齐（无额外偏移）。 */
.p-slider :deep(.el-slider__button-wrapper) {
  width: 14px; height: 14px;
  top: -5px;
  display: block;
}
.p-slider :deep(.el-slider__button-wrapper .el-slider__button) {
  margin-top: 0 !important;
  transform: none !important;
  vertical-align: top;
  display: block;
}
.p-slider :deep(.el-slider__runway) { height: 4px; margin: 8px 0; }
.p-slider :deep(.el-slider__bar) { height: 4px; }
.p-slider :deep(.el-slider__stop) { display: none; }
.p-ctl .p-num { width: 88px; flex-shrink: 0; }
.p-ctl .p-num.el-input-number { width: 88px; }
.p-ctl .p-num :deep(.el-input__inner) { text-align: left; padding-left: 6px; }
/* 有滑块的行加高一点，让圆形手柄有上下呼吸空间 */
.pp-row:has(.el-slider) { min-height: 34px; }
</style>
