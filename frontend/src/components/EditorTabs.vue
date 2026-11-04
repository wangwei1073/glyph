<script setup>
// 右侧控制面板：图标竖栏 + 内容区（分组表达语义层级）
import { ref } from 'vue'
import LayerPanel from './LayerPanel.vue'
import AesPanel from './AesPanel.vue'
import ParamPanel from './ParamPanel.vue'
import ScalePanel from './ScalePanel.vue'
import CoordFacetPanel from './CoordFacetPanel.vue'
import LabsGuidePanel from './LabsGuidePanel.vue'
import AnnotatePanel from './AnnotatePanel.vue'
import ThemePanel from './ThemePanel.vue'
import AdvancedPanel from './AdvancedPanel.vue'
import PinPanel from './PinPanel.vue'

const tab = ref('layers')
const items = [
  { name: 'layers', label: '图层', icon: 'Files', group: 0 },
  { name: 'aes', label: '美学', icon: 'CollectionTag', group: 0 },
  { name: 'params', label: '参数', icon: 'Tools', group: 0 },
  { name: 'scale', label: '标度', icon: 'Odometer', group: 1 },
  { name: 'coord', label: '坐标', icon: 'Grid', group: 1 },
  { name: 'patch', label: '拼图', icon: 'Menu', group: 1 },
  { name: 'labs', label: '标签', icon: 'EditPen', group: 2 },
  { name: 'annot', label: '注释', icon: 'Location', group: 2 },
  { name: 'theme', label: '主题', icon: 'Brush', group: 2 },
  { name: 'adv', label: '高级', icon: 'Setting', group: 3 }
]
</script>

<template>
  <div class="editor-root">
    <nav class="rail">
      <template v-for="(it, i) in items" :key="it.name">
        <div v-if="i > 0 && it.group !== items[i - 1].group" class="rail-sep" />
        <button class="rail-btn" :class="{ active: tab === it.name }" @click="tab = it.name">
          <el-icon :size="17"><component :is="it.icon" /></el-icon>
          <span class="rail-lab">{{ it.label }}</span>
        </button>
      </template>
    </nav>
    <div class="tab-body gg-scroll">
      <LayerPanel v-show="tab === 'layers'" />
      <AesPanel v-show="tab === 'aes'" />
      <ParamPanel v-show="tab === 'params'" />
      <ScalePanel v-show="tab === 'scale'" />
      <CoordFacetPanel v-show="tab === 'coord'" />
      <LabsGuidePanel v-show="tab === 'labs'" />
      <AnnotatePanel v-show="tab === 'annot'" />
      <ThemePanel v-show="tab === 'theme'" />
      <PinPanel v-show="tab === 'patch'" />
      <AdvancedPanel v-show="tab === 'adv'" />
    </div>
  </div>
</template>

<style scoped>
.editor-root { display: flex; flex-direction: row; height: 100%; overflow: hidden; }
.rail {
  width: 56px; flex-shrink: 0; overflow-y: auto; overflow-x: hidden;
  border-right: 1px solid var(--gg-border); background: var(--gg-panel);
  padding: 4px 0 10px; display: flex; flex-direction: column; align-items: stretch;
}
.rail::-webkit-scrollbar { width: 0; }
.rail-btn {
  display: flex; flex-direction: column; align-items: center; gap: 2px;
  padding: 7px 0 5px; border: none; background: none; cursor: pointer;
  color: var(--el-text-color-secondary); position: relative;
  font-family: inherit; line-height: 1; font-size: inherit;
}
.rail-btn:hover { color: var(--el-text-color-primary); background: rgba(128,128,128,.07); }
.rail-btn.active { color: var(--gg-accent); background: rgba(74,144,217,.10); }
.rail-btn.active::before {
  content: ""; position: absolute; left: 0; top: 7px; bottom: 5px;
  width: 2.5px; border-radius: 0 2px 2px 0; background: var(--gg-accent);
}
.rail-lab { font-size: 10.5px; letter-spacing: .5px; }
.rail-sep { height: 1px; margin: 6px 12px; background: var(--gg-border); flex-shrink: 0; }
.tab-body { flex: 1; min-width: 0; min-height: 0; }
</style>
