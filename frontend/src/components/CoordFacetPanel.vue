<script setup>
// 坐标系 + 分面 面板（合并为一个面板便于使用）
import { computed } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import { useDataStore } from '../stores/data'
import ParamControl from './ParamControl.vue'

const meta = useMetaStore()
const spec = useSpecStore()
const data = useDataStore()

const coord = computed(() => spec.spec.coord)
const coordParams = computed(() =>
  coord.value.type ? (meta.coordByName[coord.value.type]?.params || []) : [])

function setCoordType(t) {
  spec.setCoord({ type: t, params: {} })
}
function setCoordParam(name, v) {
  const params = { ...coord.value.params }
  if (v === null) delete params[name]
  else params[name] = v
  spec.setCoord({ params })
}

const facet = computed(() => spec.spec.facet || { type: '', vars: [], rows: [], cols: [], params: {} })
const facetParams = computed(() =>
  facet.value.type && facet.value.type !== 'none'
    ? Object.values(meta.facets[facet.value.type]?.params || {}) : [])

function setFacetType(t) {
  if (!t) spec.setFacet(null)
  else spec.setFacet({ type: t, vars: [], rows: [], cols: [], params: {} })
}
function patchFacet(patch) {
  spec.setFacet({ ...JSON.parse(JSON.stringify(facet.value)), ...patch })
}
function setFacetParam(name, v) {
  const params = { ...facet.value.params }
  if (v === null) delete params[name]
  else params[name] = v
  patchFacet({ params })
}
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">坐标系</div>
    <div class="p-row">
      <label>类型</label>
      <el-select :model-value="coord.type" size="small" style="width:100%" clearable
        placeholder="默认 cartesian" @update:model-value="setCoordType($event || '')">
        <el-option v-for="c in meta.coords" :key="c.name" :value="c.name" :label="c.label" />
      </el-select>
    </div>
    <template v-if="coord.type">
      <div v-for="p in coordParams" :key="p.name" class="p-row">
        <label>{{ p.label }}</label>
        <ParamControl :schema="p" :model-value="coord.params[p.name] ?? null"
          @update:model-value="setCoordParam(p.name, $event)" />
      </div>
    </template>
    <div v-if="coord.type" class="p-row">
      <label>翻转轴（flip）</label>
      <el-switch :model-value="coord.flip" size="small"
        @update:model-value="spec.setCoord({ flip: $event })" />
    </div>

    <div class="gg-subhead" style="margin-top:16px">分面</div>
    <div class="p-row">
      <label>类型</label>
      <el-select :model-value="facet.type" size="small" style="width:100%" clearable
        placeholder="不分面" @update:model-value="setFacetType($event || '')">
        <el-option value="wrap" label="facet_wrap 一维序列" />
        <el-option value="grid" label="facet_grid 行列交叉" />
      </el-select>
    </div>

    <template v-if="facet.type === 'wrap'">
      <div class="p-row">
        <label>分面变量</label>
        <el-select :model-value="facet.vars" size="small" multiple style="width:100%"
          placeholder="选择一列（可多选）" @update:model-value="patchFacet({ vars: $event })">
          <el-option v-for="c in data.columnOptions" :key="c.value" :value="c.value" :label="c.label" />
        </el-select>
      </div>
    </template>
    <template v-if="facet.type === 'grid'">
      <div class="p-row">
        <label>行变量 rows</label>
        <el-select :model-value="facet.rows" size="small" multiple style="width:100%"
          @update:model-value="patchFacet({ rows: $event })">
          <el-option v-for="c in data.columnOptions" :key="c.value" :value="c.value" :label="c.label" />
        </el-select>
      </div>
      <div class="p-row">
        <label>列变量 cols</label>
        <el-select :model-value="facet.cols" size="small" multiple style="width:100%"
          @update:model-value="patchFacet({ cols: $event })">
          <el-option v-for="c in data.columnOptions" :key="c.value" :value="c.value" :label="c.label" />
        </el-select>
      </div>
    </template>

    <template v-if="['wrap', 'grid'].includes(facet.type)">
      <div v-for="p in facetParams" :key="p.name" class="p-row">
        <label>{{ p.label }}</label>
        <ParamControl :schema="p" :model-value="facet.params[p.name] ?? null"
          @update:model-value="setFacetParam(p.name, $event)" />
      </div>
    </template>
  </div>
</template>
