<script setup>
// 右侧控制面板：图标竖栏 + 内容区（分组表达语义层级）
import { computed } from 'vue'
import { ElMessage } from 'element-plus'
import { useUiStore } from '../stores/ui'
import { useSpecStore } from '../stores/spec'
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
import GalleryPanel from './GalleryPanel.vue'
import ExtensionsPanel from './ExtensionsPanel.vue'

const ui = useUiStore()
const spec = useSpecStore()
const tab = computed({
  get: () => ui.tab,
  set: (v) => ui.setTab(v)
})

// 这些页签编辑的是「绘图规格」，而代码图是由一段 R 代码画出来的，
// 规格对它的画面没有任何影响。此时把面板置灰并给出说明与出口，
// 避免用户改了设置却看不出变化（或以为坏了）。
const SPEC_TABS = ['layers', 'aes', 'params', 'scale', 'coord', 'labs', 'annot', 'theme']
const isCodeImage = computed(() => !!(spec.last && spec.last.renderedFromCode))
const locked = computed(() => isCodeImage.value && SPEC_TABS.includes(tab.value))

function goBackToSpec() {
  if (!spec.backToSpec()) ElMessage.warning('画布没有图层，无法返回；先添加图层或载入项目')
}
// 页签按职责分组（组间显示分隔线）：
//   0 绘图核心：图层 → 美学 → 参数（从「画什么」到「怎么映射」到「细调」）
//   1 图形设置：标度 → 坐标（改变图形本身的呈现规则）
//   2 图上元素：标签 → 注释 → 主题（叠加在图上、影响外观的内容）
//   3 产出：图库 → 拼图（把图存起来、把图组合出去）
//   4 系统：高级 → 扩展（代码模式与能力管理）
const items = [
  { name: 'layers', label: '图层', icon: 'Files', group: 0 },
  { name: 'aes', label: '美学', icon: 'CollectionTag', group: 0 },
  { name: 'params', label: '参数', icon: 'Tools', group: 0 },
  { name: 'scale', label: '标度', icon: 'Odometer', group: 1 },
  { name: 'coord', label: '坐标', icon: 'Grid', group: 1 },
  { name: 'labs', label: '标签', icon: 'EditPen', group: 2 },
  { name: 'annot', label: '注释', icon: 'Location', group: 2 },
  { name: 'theme', label: '主题', icon: 'Brush', group: 2 },
  { name: 'gallery', label: '图库', icon: 'PictureFilled', group: 3 },
  { name: 'patch', label: '拼图', icon: 'Menu', group: 3 },
  { name: 'adv', label: '高级', icon: 'Setting', group: 4 },
  { name: 'ext', label: '扩展', icon: 'Box', group: 4 }
]
</script>

<template>
  <div class="editor-root">
    <nav class="rail">
      <div class="rail-head">
        <button class="rail-btn rail-collapse" title="收起控制面板" @click="ui.toggleRight()">
          <el-icon :size="16"><ArrowRight /></el-icon>
        </button>
      </div>
      <template v-for="(it, i) in items" :key="it.name">
        <div v-if="i > 0 && it.group !== items[i - 1].group" class="rail-sep" />
        <button class="rail-btn" :class="{ active: tab === it.name }" @click="tab = it.name">
          <el-icon :size="17"><component :is="it.icon" /></el-icon>
          <span class="rail-lab">{{ it.label }}</span>
        </button>
      </template>
    </nav>
    <div class="tab-body gg-scroll">
      <!-- 代码图状态下，这 8 个面板的设置对画面不生效：置灰 + 说明 + 出口 -->
      <div v-if="locked" class="lock-bar">
        <el-icon class="lock-ico"><Tickets /></el-icon>
        <span class="lock-txt">当前显示代码图，本页设置对它不生效</span>
        <el-button size="small" text type="primary" @click="goBackToSpec">返回我的图</el-button>
      </div>
      <LayerPanel v-show="tab === 'layers'" :class="{ 'is-locked': locked }" />
      <AesPanel v-show="tab === 'aes'" :class="{ 'is-locked': locked }" />
      <ParamPanel v-show="tab === 'params'" :class="{ 'is-locked': locked }" />
      <ScalePanel v-show="tab === 'scale'" :class="{ 'is-locked': locked }" />
      <CoordFacetPanel v-show="tab === 'coord'" :class="{ 'is-locked': locked }" />
      <LabsGuidePanel v-show="tab === 'labs'" :class="{ 'is-locked': locked }" />
      <AnnotatePanel v-show="tab === 'annot'" :class="{ 'is-locked': locked }" />
      <ThemePanel v-show="tab === 'theme'" :class="{ 'is-locked': locked }" />
      <GalleryPanel v-show="tab === 'gallery'" />
      <PinPanel v-show="tab === 'patch'" />
      <AdvancedPanel v-show="tab === 'adv'" />
      <ExtensionsPanel v-show="tab === 'ext'" />
    </div>
  </div>
</template>

<style scoped>
.editor-root { display: flex; flex-direction: row; height: 100%; overflow: hidden; }
.rail {
  width: 56px; flex-shrink: 0; overflow-y: auto; overflow-x: hidden;
  border-right: 1px solid var(--gg-border); background: var(--gg-panel);
  padding: 0 0 10px; display: flex; flex-direction: column; align-items: stretch;
}
.rail::-webkit-scrollbar { width: 0; }
/* 收起按钮占据与左栏品牌条、画布顶栏等高的头部，让三条分割线在同一水平线上 */
.rail-head {
  height: var(--gg-strip-h); flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  border-bottom: 1px solid var(--gg-border);
  margin-bottom: 4px;
}
.rail-btn {
  display: flex; flex-direction: column; align-items: center; gap: 2px;
  padding: 6px 0 4px; border: none; background: none; cursor: pointer;
  color: var(--el-text-color-secondary); position: relative;
  font-family: inherit; line-height: 1; font-size: inherit;
}
.rail-btn:hover { color: var(--el-text-color-primary); background: rgba(128,128,128,.07); }
.rail-btn.active { color: var(--gg-accent); background: rgba(47, 111, 191,.10); }
.rail-btn.active::before {
  content: ""; position: absolute; left: 0; top: 7px; bottom: 5px;
  width: 2.5px; border-radius: 0 2px 2px 0; background: var(--gg-accent);
}
.rail-lab { font-size: 11px; letter-spacing: .3px; }
.rail-collapse {
  padding: 0; width: 100%; height: 100%; color: var(--gg-text-4);
  justify-content: center;   /* 覆盖 .rail-btn 的默认顶部对齐，让箭头垂直居中 */
}
.rail-collapse:hover { color: var(--gg-brand); background: transparent; }
/* 分组分隔线：比按钮间隙更明显，让「绘图核心 / 图形设置 / 图上元素 / 产出 / 系统」一眼可分 */
.rail-sep {
  height: 1px; margin: 7px 10px; flex-shrink: 0;
  background: var(--gg-border-strong);
}
.tab-body { flex: 1; min-width: 0; min-height: 0; }

/* 代码图状态下锁定的面板：置灰 + 不可交互（滚动也一并禁用，避免误以为可编辑） */
.is-locked {
  opacity: .42; filter: saturate(.35); pointer-events: none; user-select: none;
}
/* 顶部说明条：常驻在内容区顶部，是唯一可点的元素（提供返回出口） */
.lock-bar {
  position: sticky; top: 0; z-index: 5;
  display: flex; align-items: center; gap: 6px;
  padding: 6px 10px; margin-bottom: 4px;
  background: #fff8ec; border-bottom: 1px solid #f0d9b5;
  font-size: 11.5px; color: #8a5a00;
}
html.dark .lock-bar { background: #3a2f18; border-bottom-color: #5a4a25; color: #ddb26a; }
.lock-ico { flex-shrink: 0; }
.lock-txt { flex: 1; min-width: 0; }
.lock-bar :deep(.el-button) { flex-shrink: 0; padding: 0 4px; height: 20px; font-size: 11.5px; }
</style>
