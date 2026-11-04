<script setup>
// 图层面板：图层列表 + geom 分组选择（添加/更换共用 GeomChipPicker）
import { ref, computed } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import GeomChipPicker from './GeomChipPicker.vue'

const meta = useMetaStore()
const spec = useSpecStore()

const addVisible = ref(false)
const changeVis = ref({})   // 每张卡片的"更换类型"popover 开合

function describe(l) {
  const kv = []
  for (const k of Object.keys(l.aes || {})) {
    const v = l.aes[k]
    const val = v && typeof v === 'object'
      ? (v.map ? String(v.map) : v.expr ? enc(v.expr) : String(v.value ?? ''))
      : ''
    if (val) kv.push(`${k}=${val}`)
  }
  const parts = kv.slice(0, 3)
  if (kv.length > 3) parts.push('…')
  if (l.stat && l.stat !== 'identity') parts.push(`stat=${l.stat}`)
  if (l.position && l.position.type && l.position.type !== 'identity') parts.push(`pos=${l.position.type}`)
  const nParams = Object.keys(l.params || {}).length + Object.keys(l.aesParams || {}).length
  if (nParams) parts.push(`${nParams} 项参数`)
  return parts.join(' · ') || '未设置映射'
}
function enc(s) {
  const t = String(s).replace(/\s+/g, ' ').trim()
  return t.length > 14 ? t.slice(0, 13) + '…' : t
}

function add(geomName) {
  spec.addLayer(geomName)
  addVisible.value = false
}
function change(i, geomName) {
  spec.changeGeom(i, geomName)
  changeVis.value[i] = false
}
</script>

<template>
  <div class="layer-panel-root">
    <div class="layer-head">
    <span class="layer-count">{{ spec.spec.layers.length ? `共 ${spec.spec.layers.length} 层` : '' }}</span>
    <el-popover v-model:visible="addVisible" placement="left-start" :width="404" trigger="click">
      <template #reference>
        <el-button size="small" type="primary"><el-icon><Plus /></el-icon>添加图层</el-button>
      </template>
      <GeomChipPicker @pick="add" />
    </el-popover>
  </div>

  <div class="gg-scroll">
    <div v-for="(l, i) in spec.spec.layers" :key="i" class="layer-card" :class="{ active: i === spec.selectedLayer }"
      @click="spec.selectLayer(i)">
      <div class="drag-no">{{ i + 1 }}</div>
      <div style="min-width:0">
        <div class="layer-name">
          {{ meta.geomByName[l.geom]?.label || l.geom }}
          <span v-if="l.geom !== (meta.geomByName[l.geom]?.name)" class="gg-mono" style="font-size: 11px;color:var(--el-text-color-secondary)"></span>
        </div>
        <div class="layer-sub gg-mono">{{ describe(l) }}</div>
      </div>
      <div class="layer-ops" @click.stop>
        <el-button size="small" text :disabled="i === 0" @click="spec.moveLayer(i, -1)">
          <el-icon><ArrowUp /></el-icon></el-button>
        <el-button size="small" text :disabled="i === spec.spec.layers.length - 1" @click="spec.moveLayer(i, 1)">
          <el-icon><ArrowDown /></el-icon></el-button>
        <el-popover v-model:visible="changeVis[i]" placement="left-start" :width="404" trigger="click">
          <template #reference>
            <el-button size="small" text title="更换图层类型">
              <el-icon><Switch /></el-icon>
            </el-button>
          </template>
          <GeomChipPicker @pick="(g) => change(i, g)" />
        </el-popover>
        <el-button size="small" text @click="spec.dupLayer(i)"><el-icon><CopyDocument /></el-icon></el-button>
        <el-button size="small" text type="danger" @click="spec.removeLayer(i)"><el-icon><Delete /></el-icon></el-button>
      </div>
    </div>
    <div v-if="!spec.spec.layers.length" class="gg-empty-hint" style="padding:24px 12px">
      使用右上按钮添加图层
    </div>
  </div>
  </div>
</template>

<style scoped>
.layer-panel-root { display: flex; flex-direction: column; height: 100%; min-height: 0; overflow: hidden; }
.layer-head {
  display: flex; align-items: center; justify-content: space-between;
  padding: 9px 10px; border-bottom: 1px solid var(--gg-border); flex-shrink: 0;
}
.layer-count { font-size: 11px; color: var(--el-text-color-secondary); }
.layer-name { font-size: 13px; font-weight: 600; }
.layer-sub {
  font-size: 11px; color: var(--el-text-color-secondary);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 220px;
}
</style>
