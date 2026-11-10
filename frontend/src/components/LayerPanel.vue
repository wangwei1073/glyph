<script setup>
// 图层面板（手风琴）：卡片头部 = 概要 + 快捷操作；展开即选中，卡内直接编辑
// 美学映射与 geom/stat/position 参数（原「美学」「参数」页签已收编进卡片）。
// 单开：展开的卡片就是选中的图层；添加/复制/外部选中变化会同步展开位置。
import { ref, watch, nextTick } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import GeomChipPicker from './GeomChipPicker.vue'
import AesPanel from './AesPanel.vue'
import ParamPanel from './ParamPanel.vue'

const meta = useMetaStore()
const spec = useSpecStore()

const addVisible = ref(false)
const changeVis = ref({})   // 每张卡片的"更换类型"popover 开合
const expanded = ref(-1)    // 展开的卡片下标（跟随 selectedLayer，收起不改选中）
const secOpen = ref({ aes: true, params: false })  // 卡内分区：映射默认展开，参数默认收起
const cardEls = ref([])

// 外部改动选中层（添加/复制图层、删除后的 clamp）→ 同步展开位置并滚入视野
watch(() => spec.selectedLayer, (v) => {
  expanded.value = v
  if (v >= 0) nextTick(() => cardEls.value[v]?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }))
}, { immediate: true })

function toggle(i) {
  if (expanded.value === i) { expanded.value = -1; return }  // 收起不改选中
  spec.selectLayer(i)  // watch 会展开并滚动
}

function describe(l) {
  const kv = []
  for (const k of Object.keys(l.aes || {})) {
    const v = l.aes[k]
    const val = v && typeof v === 'object'
      ? (v.map ? String(v.map) : v.expr ? enc(v.expr) : String(v.value ?? ''))
      : ''
    if (val) kv.push(`${k}=${val}`)
  }
  const parts = kv.slice(0, 4)
  if (kv.length > 4) parts.push('…')
  if (l.stat && l.stat !== 'identity') parts.push(`stat=${l.stat}`)
  if (l.position && l.position.type && l.position.type !== 'identity') parts.push(`pos=${l.position.type}`)
  if (nParams(l)) parts.push(`${nParams(l)} 项参数`)
  return parts.join(' · ') || '未设置映射'
}
function enc(s) {
  const t = String(s).replace(/\s+/g, ' ').trim()
  return t.length > 14 ? t.slice(0, 13) + '…' : t
}
function aesCount(l) {
  return Object.values(l.aes || {}).filter(Boolean).length
}
function nParams(l) {
  return Object.keys(l.params || {}).length + Object.keys(l.aesParams || {}).length +
    Object.keys(l.position?.params || {}).length + (l.stat ? 1 : 0)
}

function add(geomName) {
  spec.addLayer(geomName)  // addLayer 会选中新层 → watch 自动展开
  addVisible.value = false
}
function change(i, geomName) {
  spec.changeGeom(i, geomName)
  changeVis.value[i] = false
}
// 该层是否已启用多重标度
function hasReset(l) {
  const r = l.resetScale
  if (!r) return false
  return Array.isArray(r) ? r.includes('fill') : r === 'fill'
}
</script>

<template>
  <div class="layer-panel-root gg-scroll">
    <div class="layer-head">
      <span class="layer-count">{{ spec.spec.layers.length ? `共 ${spec.spec.layers.length} 层` : '' }}</span>
      <el-popover v-model:visible="addVisible" placement="left-start" :width="404" trigger="click">
        <template #reference>
          <el-button size="small" type="primary"><el-icon><Plus /></el-icon>添加图层</el-button>
        </template>
        <GeomChipPicker @pick="add" />
      </el-popover>
    </div>

    <div v-for="(l, i) in spec.spec.layers" :key="i" :ref="el => (cardEls[i] = el)"
      class="layer-card layer-acc" :class="{ active: i === spec.selectedLayer, hidden: l.visible === false }">
      <div class="layer-headrow" @click="toggle(i)">
        <el-icon class="tw" :class="{ open: expanded === i }"><CaretRight /></el-icon>
        <div class="drag-no">{{ i + 1 }}</div>
        <div style="min-width:0">
          <div class="layer-name">
            {{ meta.geomByName[l.geom]?.label || l.geom }}
            <span v-if="l.visible === false" class="hidden-tag">已隐藏</span>
          </div>
          <div class="layer-sub gg-mono">{{ describe(l) }}</div>
        </div>
        <div class="layer-ops" @click.stop>
          <el-tooltip :content="l.visible === false ? '显示此图层' : '隐藏此图层'" placement="top">
            <el-button size="small" text class="eye-btn" :class="{ off: l.visible === false }"
              @click="spec.toggleLayerVisible(i)">
              <el-icon><component :is="l.visible === false ? 'Hide' : 'View'" /></el-icon>
            </el-button>
          </el-tooltip>
          <!-- 多重标度：让这一层重新开始一套 fill 标度（需要 ggnewscale）-->
          <el-tooltip v-if="i > 0" placement="top"
            :content="hasReset(l) ? '取消多重标度（本层沿用上层标度）' : '从本层重新开始 fill 标度（多重标度）'">
            <el-button size="small" text class="reset-btn" :class="{ on: hasReset(l) }"
              :disabled="!meta.ext.ggnewscale" @click="spec.toggleLayerResetScale(i, 'fill')">
              <el-icon><Brush /></el-icon>
            </el-button>
          </el-tooltip>
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

      <!-- 展开体：只有展开的卡片会挂载 AesPanel/ParamPanel（全页始终仅一份实例） -->
      <div v-if="expanded === i" class="layer-body" @click.stop>
        <button class="sec-head" @click="secOpen.aes = !secOpen.aes">
          <el-icon class="sec-tw" :class="{ open: secOpen.aes }"><CaretRight /></el-icon>
          <span>美学映射</span>
          <span class="sec-n">{{ aesCount(l) }}</span>
        </button>
        <div v-show="secOpen.aes" class="sec-body"><AesPanel /></div>

        <button class="sec-head" @click="secOpen.params = !secOpen.params">
          <el-icon class="sec-tw" :class="{ open: secOpen.params }"><CaretRight /></el-icon>
          <span>参数（geom / stat / position）</span>
          <span class="sec-n">{{ nParams(l) }}</span>
        </button>
        <div v-show="secOpen.params" class="sec-body"><ParamPanel /></div>
      </div>
    </div>

    <div v-if="!spec.spec.layers.length" class="gg-empty-hint" style="padding:24px 12px">
      使用右上按钮添加图层
    </div>
  </div>
</template>

<style scoped>
.layer-panel-root { height: 100%; min-height: 0; overflow-y: auto; overflow-x: hidden; }
/* 头部吸顶：展开长卡片后「添加图层」仍可达 */
.layer-head {
  position: sticky; top: 0; z-index: 4;
  display: flex; align-items: center; justify-content: space-between;
  padding: 9px 10px; border-bottom: 1px solid var(--gg-border);
  background: var(--gg-panel);
}
.layer-count { font-size: 11px; color: var(--el-text-color-secondary); }
/* 手风琴卡片：纵向容器（覆盖全局 .layer-card 的横向行布局） */
.layer-acc { display: block; padding: 0; cursor: default; }
.layer-headrow {
  display: flex; align-items: center; gap: 8px;
  padding: 8px 10px; cursor: pointer; min-width: 0;
}
.layer-headrow:hover { border-radius: var(--gg-r-md); }
.tw { color: var(--el-text-color-secondary); transition: transform .15s; flex-shrink: 0; }
.tw.open { transform: rotate(90deg); }
.layer-name {
  font-size: 13px; font-weight: 600;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.layer-sub {
  font-size: 11px; color: var(--el-text-color-secondary);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap; max-width: 220px;
}
.layer-ops { margin-left: auto; display: flex; gap: 2px; }
/* 展开体 */
.layer-body {
  border-top: 1px dashed var(--gg-border);
  padding: 4px 0 6px;
  background: rgba(128, 128, 128, .04);
}
.sec-head {
  display: flex; align-items: center; gap: 5px; width: 100%;
  padding: 6px 12px; border: none; background: none; cursor: pointer;
  font-size: 11.5px; font-weight: 600; color: var(--el-text-color-regular);
  font-family: inherit; text-align: left;
}
.sec-head:hover { color: var(--gg-accent); }
.sec-tw { color: var(--el-text-color-secondary); transition: transform .15s; flex-shrink: 0; }
.sec-tw.open { transform: rotate(90deg); }
.sec-n {
  margin-left: auto; font-size: 10px; font-weight: 400;
  color: var(--el-text-color-secondary);
  background: rgba(128, 128, 128, .14); border-radius: 8px; padding: 0 6px; line-height: 15px;
}
.sec-body { padding-bottom: 2px; }
</style>
