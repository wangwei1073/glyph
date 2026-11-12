<script setup>
// 列操作面板：映射到当前图层 / 插入列名 / 类型统计 / 取值预览
// 左栏列列表（点击列展开）与数据预览弹窗的列菜单共用同一份，避免两处实现漂移
import { computed } from 'vue'
import { ElMessage } from 'element-plus'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'

// 列操作面板：映射到当前图层 / 插入列名 / 类型统计 / 取值预览
// 左栏列列表（点击列展开）与数据预览弹窗的列菜单共用同一份，避免两处实现漂移
const props = defineProps({
  col: { type: Object, required: true },
  compact: { type: Boolean, default: false },
  // 插入列名的处理函数。只有「数据准备」对话框里的用法会传（它知道当前聚焦的
  // 表达式框）；数据预览弹窗是只读查看，没有可插入的目标，所以不传 ——
  // 此时不显示插入按钮，而不是显示一个点了会报「先点击…表达式框」的坏按钮。
  insert: { type: Function, default: null }
})

const meta = useMetaStore()
const spec = useSpecStore()

// 常用映射目标；实际显示时会按当前 geom 接受的美学过滤
const PREFERRED = ['x', 'y', 'colour', 'fill', 'size', 'alpha', 'shape', 'linetype', 'label', 'group']

const layer = computed(() => spec.curLayer)
const geomMeta = computed(() => (layer.value ? meta.geomByName[layer.value.geom] : null))

// 该列当前被映射到哪些美学（用于高亮 / 排序）
const mappedAs = computed(() => {
  const l = layer.value
  if (!l) return []
  return Object.keys(l.aes || {}).filter(k => {
    const v = l.aes[k]
    return v && typeof v === 'object' && v.map === props.col.name
  })
})

const aesOptions = computed(() => {
  const base = (() => {
    if (!layer.value) return ['x', 'y', 'colour', 'fill', 'group']
    const allowed = new Set(meta.layerAes(layer.value.geom))
    const opts = PREFERRED.filter(a => allowed.has(a)).slice(0, 8)
    return opts.length ? opts : ['x', 'y']
  })()
  // 已映射的排前面，一眼看到"这列用在哪"
  const used = mappedAs.value
  return [...base.filter(a => used.includes(a)), ...base.filter(a => !used.includes(a))]
})

const TYPE_LABEL = {
  numeric: '数值', character: '字符', factor: '因子',
  logical: '逻辑', date: '日期', datetime: '时间'
}

function mapTo(aesName) {
  if (!spec.spec.layers.length) {
    ElMessage.warning('先在右侧「图层」添加一个图层再映射')
    return
  }
  spec.setLayerAes(spec.selectedLayer, aesName, { map: props.col.name })
  ElMessage.success(`${props.col.name} → 第 ${spec.selectedLayer + 1} 层 ${aesName}`)
}

const insertable = computed(() => typeof props.insert === 'function')

function doInsert() {
  if (insertable.value) props.insert(props.col.name)
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
    <div class="ca-head">
      <span class="ca-target">
        映射到第 {{ spec.selectedLayer + 1 }} 层
        <code v-if="geomMeta" class="gg-mono">{{ geomMeta.fn }}</code>
        <span v-else class="ca-warn">尚未添加图层</span>
      </span>
      <el-tooltip v-if="insertable" content="插入列名到表达式" placement="top">
        <el-button size="small" text class="ca-ins" @click="doInsert">
          <el-icon><EditPen /></el-icon>
        </el-button>
      </el-tooltip>
    </div>

    <div class="ca-aes">
      <span class="ca-lab">映射</span>
      <el-button v-for="a in aesOptions" :key="a" size="small" class="ca-aes-btn"
        :class="{ on: mappedAs.includes(a) }"
        @click="mapTo(a)">{{ a }}</el-button>
    </div>

    <div class="ca-meta">
      <span>{{ TYPE_LABEL[col.type] || col.type }}</span>
      <span>缺失 {{ col.nMissing }}</span>
      <span>唯一 {{ col.nUnique }}</span>
      <span v-if="rangeText">范围 {{ rangeText }}</span>
    </div>

    <div v-if="previewVals.length" class="ca-prev">
      <span class="ca-lab">预览</span>
      <code v-for="(v, i) in previewVals" :key="i" class="gg-mono" :title="fmt(v)">{{ fmt(v) }}</code>
      <span v-if="(col.preview || []).length > previewVals.length" class="ca-more">…</span>
    </div>
  </div>
</template>

<style scoped>
.ca { display: flex; flex-direction: column; gap: 7px; min-width: 0; }
.ca-head { display: flex; align-items: center; gap: 6px; }
.ca-target {
  font-size: 11px; color: var(--gg-text-3); min-width: 0;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.ca-target code { font-size: 11px; color: var(--gg-text-2); }
.ca-warn { color: #c9731f; }
.ca-ins { margin-left: auto; padding: 0 4px; height: 20px; flex-shrink: 0; }
.ca-lab { font-size: 11px; color: var(--gg-text-4); flex-shrink: 0; width: 24px; }
.ca-aes { display: flex; flex-wrap: wrap; gap: 4px; align-items: center; }
.ca-aes-btn {
  margin: 0 !important; height: 22px; padding: 0 7px; font-size: 11.5px;
  border-radius: 4px; color: var(--gg-text-2);
}
.ca-aes-btn.on {
  color: #fff; background: var(--gg-brand); border-color: var(--gg-brand);
}
.ca-meta {
  display: flex; flex-wrap: wrap; gap: 4px 8px;
  font-size: 11px; color: var(--gg-text-4);
}
.ca-meta span + span::before {
  content: "·"; margin-right: 6px; color: var(--gg-text-4); opacity: .7;
}
.ca-prev { display: flex; align-items: center; gap: 4px; flex-wrap: wrap; }
.ca-prev code {
  background: rgba(128, 128, 128, .09); border-radius: 4px; padding: 0 5px;
  font-size: 11px; line-height: 16px; color: var(--gg-text-2);
  max-width: 64px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.ca-more { font-size: 11px; color: var(--gg-text-4); }
</style>
