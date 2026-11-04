<script setup>
// 参数面板：选中图层的 geom 参数 / stat 参数 / position 参数
import { computed } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import ParamControl from './ParamControl.vue'
import EmptyState from './EmptyState.vue'

const meta = useMetaStore()
const spec = useSpecStore()
const ui = useUiStore()

const curLayerParams = computed(() => meta.layerParams(spec.curLayer?.geom))
const curLayerStatParams = computed(() => meta.layerStatParams(spec.curLayer?.geom))

const chosenStatParams = computed(() => {
  const st = spec.curLayer?.stat
  return st ? meta.statParamsOf(st) : []
})

const positionParams = computed(() => {
  const p = spec.curLayer?.position?.type
  return p ? meta.positionParamsOf(p) : []
})

const usedParams = computed(() => {
  const l = spec.curLayer
  if (!l) return []
  const out = []
  for (const p of [...curLayerParams.value, ...curLayerStatParams.value, ...chosenStatParams.value]) {
    if (out.find(x => x.name === p.name)) continue
    out.push(p)
  }
  return out
})

const usedAesParams = computed(() => {
  const l = spec.curLayer
  if (!l) return []
  const known = new Set([...meta.layerAes(l.geom)])
  const out = []
  for (const name of Object.keys(l.aesParams || {})) out.push(name)
  // 常用附加常量（geom 接受的 aes 之外不显示）
  for (const name of known) {
    if (!out.includes(name)) out.push(name)
  }
  return out
})

function getP(obj, name) { return obj?.[name] ?? null }
function setParam(name, v) { spec.setLayerParam(spec.selectedLayer, name, v) }
function setAesParam(name, v) { spec.setLayerAesParam(spec.selectedLayer, name, v) }

const aesParamSchema = (name) => {
  const am = meta.aesByName[name] || {}
  const kind = am.kind || 'text'
  const widget = { color: 'color', number: 'number', shape: 'shape', linetype: 'linetype', text: 'text' }[kind] || 'text'
  return { name, widget, label: name, exprOk: true }
}
</script>

<template>
  <div v-if="spec.curLayer" class="gg-tab-scroll">
    <div class="gg-subhead">geom / stat 参数 · {{ meta.geomByName[spec.curLayer.geom]?.fn }}</div>

    <div v-if="!usedParams.length" style="padding:10px 12px;font-size:12px;color:var(--el-text-color-secondary)">
      该 geom 无额外参数
    </div>
    <div v-for="p in usedParams" :key="p.name" class="p-row">
      <label :title="p.name">{{ p.label }}</label>
      <ParamControl :schema="p" :model-value="getP(spec.curLayer.params, p.name)"
        @update:model-value="setParam(p.name, $event)" />
    </div>

    <div class="gg-subhead" style="margin-top:14px">stat 选择</div>
    <div class="p-row">
      <label>stat</label>
      <el-select :model-value="spec.curLayer.stat" size="small" filterable style="width:100%"
        placeholder="geom 默认" @update:model-value="spec.spec.layers[spec.selectedLayer].stat = $event || ''">
        <el-option value="" :label="`默认 (${meta.geomByName[spec.curLayer.geom]?.defaultStat || 'identity'})`" />
        <el-option v-for="s in meta.stats" :key="s.name" :value="s.name" :label="s.label">
          <span class="opt-row">
            <span>{{ s.label }}</span>
            <span class="opt-fn gg-mono">{{ s.fn }}</span>
          </span>
        </el-option>
      </el-select>
    </div>

    <div class="gg-subhead" style="margin-top:14px">position 调整</div>
    <div class="p-row">
      <label>position</label>
      <el-select :model-value="spec.curLayer.position?.type || ''" size="small" style="width:100%"
        :placeholder="`默认 (${meta.geomByName[spec.curLayer.geom]?.defaultPosition || 'identity'})`"
        @update:model-value="(v) => { spec.spec.layers[spec.selectedLayer].position = { type: v || '', params: {} } }">
        <el-option value="" label="（geom 默认）" />
        <el-option v-for="p in meta.positions" :key="p.name" :value="p.name" :label="p.label" />
      </el-select>
    </div>
    <template v-if="positionParams.length">
      <div v-for="p in positionParams" :key="p.name" class="p-row">
        <label :title="p.name">{{ p.label }}</label>
        <ParamControl :schema="p"
          :model-value="getP(spec.curLayer.position?.params, p.name)"
          @update:model-value="(v) => {
            const pos = spec.spec.layers[spec.selectedLayer].position
            if (v === null) delete pos.params[p.name]
            else pos.params[p.name] = v
          }" />
      </div>
    </template>

    <div class="gg-subhead" style="margin-top:14px">常量美学（不进入 aes）</div>
    <div v-for="name in usedAesParams" :key="name" class="p-row">
      <label>{{ meta.aesByName[name]?.label || name }}</label>
      <ParamControl :schema="aesParamSchema(name)"
        :model-value="getP(spec.curLayer.aesParams, name)"
        @update:model-value="setAesParam(name, $event)" />
    </div>
  </div>
  <EmptyState v-else icon="Tools" title="还没有可调参数"
    desc="参数跟着选中的图层走：先在「图层」里添加并选中一个 geom。">
    <el-button size="small" type="primary" @click="ui.setTab('layers')">去添加图层</el-button>
  </EmptyState>
</template>

<style scoped>
.opt-row { display: flex; justify-content: space-between; gap: 14px; align-items: center; }
.opt-fn { font-size: 11px; color: var(--el-text-color-secondary); }
</style>
