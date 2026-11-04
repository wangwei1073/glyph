<script setup>
// geom 选择器：搜索 + 示意图缩略图，支持两种分组（按图形族 / 按数据形态）
import { ref, computed, watch } from 'vue'
import { useMetaStore } from '../stores/meta'

const meta = useMetaStore()
const emit = defineEmits(['pick'])
const q = ref('')

const base = import.meta.env.BASE_URL || '/'
const thumb = (name) => `${base}geom-thumbs/${name}.png`

// 分组模式记忆（默认图形族）
const MODE_KEY = 'ggplotgui-geom-mode'
const mode = ref('family')
try { mode.value = localStorage.getItem(MODE_KEY) || 'family' } catch { /* */ }
watch(mode, (v) => { try { localStorage.setItem(MODE_KEY, v) } catch { /* */ } })

const allGroups = computed(() => (mode.value === 'shape' ? meta.geomShapeGroups : meta.geomGroups))

const filteredGroups = computed(() => {
  const s = q.value.trim().toLowerCase()
  if (!s) return allGroups.value
  return allGroups.value
    .map(g => ({ ...g, geoms: g.geoms.filter(x =>
      x.name.toLowerCase().includes(s) || x.label.toLowerCase().includes(s) || x.fn.includes(s)) }))
    .filter(g => g.geoms.length)
})

function reqAes(g) {
  const r = (g.aes && g.aes.required) || []
  return r.length ? r.join(', ') : '无（只看参数）'
}
function tip(g) {
  return [g.desc, g.fn, `需要映射：${reqAes(g)}`].filter(Boolean).join(' · ')
}
</script>

<template>
  <div>
    <div class="picker-head">
      <el-radio-group v-model="mode" size="small">
        <el-radio-button value="family">按图形族</el-radio-button>
        <el-radio-button value="shape">按数据形态</el-radio-button>
      </el-radio-group>
    </div>
    <div style="margin:6px 0">
      <el-input v-model="q" size="small" placeholder="搜索：中文名 / 英文名 / 函数名" clearable>
        <template #prefix><el-icon><Search /></el-icon></template>
      </el-input>
    </div>
    <div class="gg-scroll geom-scroll" style="max-height:410px">
      <div v-for="g in filteredGroups" :key="g.name">
        <div class="gg-subhead">{{ g.name }}<span class="cnt">{{ g.geoms.length }}</span></div>
        <div class="geom-grid">
          <div v-for="x in g.geoms" :key="x.name" class="geom-card" :title="tip(x)"
            @click="emit('pick', x.name)">
            <img :src="thumb(x.name)" :alt="x.label" loading="lazy" draggable="false" />
            <div class="lbl">{{ x.label }}</div>
          </div>
        </div>
      </div>
      <div v-if="!filteredGroups.length" class="gg-empty-hint" style="padding:20px">
        没有匹配的 geom
      </div>
    </div>
  </div>
</template>

<style scoped>
.picker-head { display: flex; align-items: center; gap: 8px; }
.picker-head :deep(.el-radio-button__inner) { padding: 4px 8px; font-size: 12px; }
.cnt {
  margin-left: 6px; font-weight: 400; font-size: 11px; color: var(--el-text-color-placeholder);
}
.geom-grid {
  display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; padding: 0 2px 6px;
}
.geom-card {
  border: 1px solid var(--gg-border); border-radius: 6px; padding: 3px 3px 2px;
  cursor: pointer; background: #fff; display: flex; flex-direction: column; align-items: center;
  transition: border-color .12s, box-shadow .12s, transform .12s; user-select: none;
}
.geom-card:hover {
  border-color: var(--gg-accent); box-shadow: 0 2px 8px rgba(47, 111, 191, .22);
  transform: translateY(-1px);
}
.geom-card img { width: 100%; height: 52px; object-fit: contain; display: block; }
.geom-card .lbl {
  font-size: 11px; line-height: 1.25; margin-top: 2px; color: #333; text-align: center;
  height: 2.5em; overflow: hidden; display: -webkit-box;
  -webkit-line-clamp: 2; -webkit-box-orient: vertical; word-break: break-all;
}

/* 隐藏滚动条（滚轮 / 触控板仍可滚动）：宽度固定、内容一眼能看出还可下滑 */
.geom-scroll { scrollbar-width: none; -ms-overflow-style: none; }
.geom-scroll::-webkit-scrollbar { width: 0; height: 0; }
</style>
