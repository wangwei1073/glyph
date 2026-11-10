<script setup>
// 美学面板：选中图层的 aes 映射 / 常量设定（双模）。
// 由 LayerPanel 手风琴在展开的图层卡片内嵌使用（原独立页签已撤销）。
import { ref, computed, watch } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useDataStore } from '../stores/data'
import { useSpecStore } from '../stores/spec'
import ParamControl from './ParamControl.vue'

const meta = useMetaStore()
const data = useDataStore()
const spec = useSpecStore()

const mode = ref({}) // aesName -> 'map' | 'value'

const aesRows = computed(() => {
  const l = spec.curLayer
  if (!l) return []
  const metaAes = meta.layerAes(l.geom)
  const known = new Set(metaAes)
  const rows = metaAes.map(name => ({
    name,
    label: meta.aesByName[name]?.label || name,
    kind: meta.aesByName[name]?.kind || 'auto',
    required: (meta.geomByName[l.geom]?.aes.required || []).includes(name)
  }))
  // 用户通过表达式引入的额外 aes
  for (const k of Object.keys(l.aes || {})) {
    if (!known.has(k)) rows.push({ name: k, label: k, kind: 'auto', required: false })
  }
  return rows
})

function curValue(name) {
  return spec.curLayer?.aes?.[name] ?? null
}
function curMode(name) {
  // 本地选择优先：切到「常量」后值为空，不能被推断回「映射」
  if (mode.value[name]) return mode.value[name]
  const v = curValue(name)
  if (!v) return 'map'
  if (typeof v === 'object' && 'map' in v) return 'map'
  return 'value'
}
function setMode(name, m) {
  mode.value[name] = m
  const cur = curValue(name)
  if (!cur || typeof cur !== 'object') return
  // 映射 ↔ 常量 无法语义互转（列名不是常量，常量也不是列），切换时清空让用户重选
  if (m === 'map' && 'value' in cur) spec.setLayerAes(spec.selectedLayer, name, null)
  else if (m === 'value' && 'map' in cur) spec.setLayerAes(spec.selectedLayer, name, null)
}
function setMap(name, col) {
  spec.setLayerAes(spec.selectedLayer, name, col ? { map: col } : null)
}
function setValue(name, v) {
  spec.setLayerAes(spec.selectedLayer, name, (v === null || v === '') ? null : { value: v })
}
function setExpr(name, code) {
  spec.setLayerAes(spec.selectedLayer, name, code && code.trim() ? { expr: code } : null)
}
function isExpr(name) {
  const v = curValue(name)
  return !!(v && typeof v === 'object' && 'expr' in v)
}
function exprVal(name) {
  return isExpr(name) ? curValue(name).expr : ''
}

const kindWidget = (kind) => {
  switch (kind) {
    case 'color': return 'color'
    case 'number': return 'number'
    case 'shape': return 'shape'
    case 'linetype': return 'linetype'
    case 'text': return 'text'
    default: return 'text'
  }
}

// 常量值 schema（用于 ParamControl）
const constSchema = computed(() => (kind) => ({
  name: 'aes', widget: kind === 'auto' ? 'text' : kindWidget(kind), label: '', exprOk: true
}))

// after_stat 提示
const afterStatHint = ref('')
watch(() => spec.selectedLayer, () => { afterStatHint.value = ''; mode.value = {} })
</script>

<template>
  <div v-if="spec.curLayer" class="aes-embedded">
    <div v-for="row in aesRows" :key="row.name" class="aes-row">
      <label class="aes-lab" :title="row.name">
        {{ row.label }}<span v-if="row.required" class="req">*</span>
      </label>
      <el-radio-group size="small" class="mode-sw"
        :model-value="curMode(row.name)" @update:model-value="setMode(row.name, $event)">
        <el-radio-button value="map">映射</el-radio-button>
        <el-radio-button value="value">常量</el-radio-button>
      </el-radio-group>

      <div class="aes-ctl">
        <!-- 映射模式：选列 或 表达式 -->
        <template v-if="!isExpr(row.name) && curMode(row.name) === 'map'">
          <el-select :model-value="curValue(row.name)?.map || ''" size="small" filterable clearable
            style="width:100%" placeholder="选择列" @update:model-value="setMap(row.name, $event || null)">
            <el-option v-for="c in data.columnOptions" :key="c.value" :value="c.value" :label="c.label">
              <span style="display:flex;justify-content:space-between;gap:10px;align-items:center">
                <span>{{ c.label }}</span>
                <span class="col-type" :class="c.type">{{ c.type.slice(0, 3) }}</span>
              </span>
            </el-option>
          </el-select>
        </template>

        <!-- 常量模式：按类型渲染控件 -->
        <template v-else-if="curMode(row.name) === 'value'">
          <ParamControl :schema="constSchema(row.kind)"
            :model-value="curValue(row.name)?.value ?? null"
            @update:model-value="setValue(row.name, $event)" />
        </template>

        <!-- 表达式模式（aes 内 R 表达式 / after_stat） -->
        <template v-else>
          <el-input :model-value="exprVal(row.name)" size="small" class="gg-mono"
            placeholder="R 表达式，如 after_stat(count) 或 hwy / displ"
            @update:model-value="setExpr(row.name, $event)" />
        </template>

        <el-tooltip content="R 表达式模式（支持 after_stat()、列运算）" placement="top">
          <el-button size="small" text class="fx-btn" :class="{ on: isExpr(row.name) }"
            @click="isExpr(row.name)
              ? setExpr(row.name, '')
              : setExpr(row.name, String(curValue(row.name)?.map || curValue(row.name)?.value || ''))">
            fx
          </el-button>
        </el-tooltip>
      </div>
    </div>

    <div class="gg-subhead" style="margin-top:10px">图层开关</div>
    <div class="p-row">
      <label>inherit.aes</label>
      <el-select :model-value="spec.curLayer.inheritAes === undefined ? '' : String(spec.curLayer.inheritAes)"
        size="small" style="width:120px" placeholder="默认"
        @update:model-value="spec.spec.layers[spec.selectedLayer].inheritAes = $event === '' ? undefined : $event === 'true'">
        <el-option value="" label="默认 (TRUE)" />
        <el-option value="true" label="TRUE" />
        <el-option value="false" label="FALSE" />
      </el-select>
    </div>
    <div class="p-row">
      <label>show.legend</label>
      <el-select :model-value="spec.curLayer.showLegend === undefined ? '' : String(spec.curLayer.showLegend)"
        size="small" style="width:120px" placeholder="默认"
        @update:model-value="spec.spec.layers[spec.selectedLayer].showLegend = $event === '' ? undefined : $event === 'true'">
        <el-option value="" label="默认" />
        <el-option value="true" label="TRUE" />
        <el-option value="false" label="FALSE" />
      </el-select>
    </div>

    <div v-if="spec.curLayer.stat" class="gg-subhead" style="margin-top:10px">
      stat_{{ spec.curLayer.stat }} 计算变量（after_stat）
    </div>
    <div v-if="spec.curLayer.stat" style="padding: 2px 12px; font-size: 12px; color:var(--el-text-color-secondary)">
      {{ (meta.statByName[spec.curLayer.stat]?.aes || []).join(' · ') }}
    </div>
  </div>
</template>

<style scoped>
.aes-embedded { padding: 2px 0 4px; }
.aes-row {
  display: flex; align-items: center; gap: 7px;
  padding: 4px 12px; min-height: 36px;
}
.aes-lab { width: 96px; flex-shrink: 0; font-size: 12px; }
.req { color: #e8734a; margin-left: 2px; font-weight: 700; }
.mode-sw { flex-shrink: 0; }
.mode-sw .el-radio-button__inner { padding: 4px 8px; font-size: 11px; }
.aes-ctl { flex: 1; display: flex; align-items: center; gap: 5px; min-width: 0; }
.fx-btn { font-family: Georgia, serif; font-style: italic; }
.fx-btn.on { color: var(--gg-accent); font-weight: 700; }
</style>
