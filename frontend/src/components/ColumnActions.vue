<script setup>
// 列操作面板：映射到当前图层 / 插入列名 / 类型统计 / 取值预览
// 左栏列列表（点击列展开）与数据预览弹窗的列菜单共用同一份，避免两处实现漂移
import { computed } from 'vue'
import { ElMessage } from 'element-plus'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import { insertExpr } from '../exprInsert'

const props = defineProps({
  col: { type: Object, required: true },
  compact: { type: Boolean, default: false }
})

const meta = useMetaStore()
const spec = useSpecStore()

// 常用映射目标；实际显示时会按当前 geom 接受的美学过滤
const PREFERRED = ['x', 'y', 'colour', 'fill', 'size', 'alpha', 'shape', 'linetype', 'label', 'group']

const layer = computed(() => spec.curLayer)
const geomMeta = computed(() => (layer.value ? meta.geomByName[layer.value.geom] : null))

const aesOptions = computed(() => {
  if (!layer.value) return ['x', 'y', 'colour', 'fill', 'group']
  const allowed = new Set(meta.layerAes(layer.value.geom))
  const opts = PREFERRED.filter(a => allowed.has(a)).slice(0, 8)
  return opts.length ? opts : ['x', 'y']
})

// 该列当前被映射到哪些美学（用于高亮）
const mappedAs = computed(() => {
  const l = layer.value
  if (!l) return []
  return Object.keys(l.aes || {}).filter(k => {
    const v = l.aes[k]
    return v && typeof v === 'object' && v.map === props.col.name
  })
})

function mapTo(aesName) {
  if (!spec.spec.layers.length) {
    ElMessage.warning('先在右侧「图层」添加一个图层再映射')
    return
  }
  spec.setLayerAes(spec.selectedLayer, aesName, { map: props.col.name })
  ElMessage.success(`${props.col.name} → 第 ${spec.selectedLayer + 1} 层 ${aesName}`)
}

function doInsert() {
  const r = insertExpr(props.col.name)
  if (!r.ok) ElMessage.info(r.msg)
}

const rangeText = computed(() => {
  const r = props.col.range
  return r && r[0] !== null && r[0] !== undefined ? `${r[0]} ~ ${r[1]}` : ''
})
const previewVals = computed(() => (props.col.preview || []).slice(0, props.compact ? 5 : 10))
const fmt = (v) => (v === null || v === undefined ? '' : String(v))
</script>

<template>
  <div class="ca">
    <div class="ca-target">
      映射到第 {{ spec.selectedLayer + 1 }} 层
      <span v-if="geomMeta" class="gg-mono">· {{ geomMeta.fn }}</span>
      <span v-else class="ca-warn">· 尚未添加图层</span>
    </div>
    <div class="ca-aes">
      <el-button v-for="a in aesOptions" :key="a" size="small"
        :type="mappedAs.includes(a) ? 'primary' : 'default'"
        :plain="mappedAs.includes(a)" @click="mapTo(a)">{{ a }}</el-button>
    </div>
    <div class="ca-actions">
      <el-button size="small" text class="ca-ins" @click="doInsert">
        <el-icon><EditPen /></el-icon>插入列名
      </el-button>
      <span class="ca-stat">
        {{ col.type }} · 缺失 {{ col.nMissing }} · 唯一 {{ col.nUnique }}<template v-if="rangeText"> · {{ rangeText }}</template>
      </span>
    </div>
    <div v-if="previewVals.length" class="ca-prev">
      <code v-for="(v, i) in previewVals" :key="i" class="gg-mono">{{ fmt(v) }}</code>
    </div>
  </div>
</template>

<style scoped>
.ca { display: flex; flex-direction: column; gap: 5px; min-width: 0; }
.ca-target { font-size: 11px; color: var(--el-text-color-secondary); }
.ca-warn { color: #e8734a; }
.ca-aes { display: flex; flex-wrap: wrap; gap: 4px; }
.ca-aes .el-button { margin: 0; height: 22px; padding: 0 8px; font-size: 12px; }
.ca-actions { display: flex; align-items: center; gap: 8px; flex-wrap: wrap; }
.ca-ins { padding: 0 2px; height: 20px; font-size: 12px; }
.ca-stat { font-size: 11px; color: var(--el-text-color-secondary); }
.ca-prev { display: flex; gap: 4px; flex-wrap: wrap; }
.ca-prev code {
  background: rgba(128, 128, 128, .08); border-radius: 4px; padding: 0 4px;
  font-size: 11px; max-width: 88px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
</style>
