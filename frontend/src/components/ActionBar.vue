<script setup>
// 底部工具区：渲染控制 / 保存状态 / 项目操作 / 暗色模式
// 原先在顶栏，改为挂在左栏底部，让画布获得完整高度。
// compact=true 时用于左栏收起后的侧边浮层。
import { computed } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useUiStore } from '../stores/ui'
import { downloadBlob } from '../api'

const props = defineProps({
  compact: { type: Boolean, default: false }   // 侧边浮层模式：只放核心按钮
})
const emit = defineEmits(['project'])

const spec = useSpecStore()
const ui = useUiStore()

// 保存状态：未改动 / 有改动 / 空画布
const saveLabel = computed(() => {
  if (!spec.spec.layers.length) return '空画布'
  return spec.dirty ? '未保存' : '已保存'
})
const saveHint = computed(() => {
  if (!spec.spec.layers.length) return '还没有图层'
  return spec.dirty ? '有未保存的改动（项目 → 保存）' : '所有改动已保存'
})

function toggleDark() {
  spec.dark = !spec.dark
  document.documentElement.classList.toggle('dark', spec.dark)
}
function cmd(c) { emit('project', c) }
</script>

<template>
  <div class="act-bar" :class="{ compact }">
    <!-- 渲染控制 -->
    <div class="act-row">
      <el-tooltip content="自动渲染：修改后自动出图；关闭后点右侧「渲染」手动出图" placement="top">
        <el-switch v-model="spec.autoRender" size="small" />
      </el-tooltip>
      <span class="act-label" :class="{ off: !spec.autoRender }">
        {{ spec.autoRender ? '自动' : '手动' }}
      </span>
      <span style="flex:1" />
      <el-button type="primary" size="small" :loading="spec.rendering"
        :style="compact ? 'width:100%' : ''" @click="spec.renderNow()">
        <el-icon class="el-icon--left"><MagicStick /></el-icon>渲染
      </el-button>
    </div>

    <!-- 保存状态 + 项目 + 暗色 -->
    <div class="act-row">
      <el-tooltip :content="saveHint" placement="top">
        <span class="gg-save-state" :class="{ dirty: spec.dirty, empty: !spec.spec.layers.length }">
          <i class="dot" />{{ saveLabel }}
        </span>
      </el-tooltip>
      <span style="flex:1; min-width:6px" />
      <el-dropdown trigger="click" @command="cmd">
        <el-button size="small" text class="act-btn">
          <el-icon><FolderOpened /></el-icon>项目<el-icon><ArrowDown /></el-icon>
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item command="save"><el-icon><FolderAdd /></el-icon>保存项目 (JSON)</el-dropdown-item>
            <el-dropdown-item command="load"><el-icon><FolderOpened /></el-icon>载入项目</el-dropdown-item>
            <el-dropdown-item command="clear" divided><el-icon><Delete /></el-icon>清空画布</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
      <el-tooltip :content="spec.dark ? '亮色模式' : '暗色模式'" placement="top">
        <el-button size="small" text class="act-btn act-dark" @click="toggleDark">
          <el-icon><component :is="spec.dark ? 'Sunny' : 'Moon'" /></el-icon>
        </el-button>
      </el-tooltip>
    </div>
  </div>
</template>

<style scoped>
.act-bar {
  flex-shrink: 0; display: flex; flex-direction: column; gap: 5px;
  padding: 6px 10px 8px; border-top: 1px solid var(--gg-border);
  background: var(--gg-panel);
}
.act-bar.compact { border: 1px solid var(--gg-border); border-radius: 8px; padding: 6px; }
.act-row { display: flex; align-items: center; gap: 6px; min-height: 24px; }
.act-label { font-size: 11px; color: var(--gg-text-3, #6b7480); }
.act-label.off { color: #c07f18; }
.act-btn { padding: 0 5px; height: 22px; font-size: 12px; }
/* 第二行：保存状态在左，项目+暗色靠右，留出明确间距 */
.act-row + .act-row { padding-top: 1px; }
.act-row + .act-row .gg-save-state { flex-shrink: 0; }
.act-row + .act-row .act-btn { white-space: nowrap; }

/* 保存状态点（原顶栏样式迁入） */
.gg-save-state {
  display: inline-flex; align-items: center; gap: 5px;
  font-size: 11px; color: var(--gg-text-3, #6b7480);
  cursor: default; white-space: nowrap;
}
.gg-save-state .dot {
  width: 6px; height: 6px; border-radius: 50%; background: #54b28e; display: inline-block;
}
.gg-save-state.dirty { color: #c07f18; }
.gg-save-state.dirty .dot { background: #f0b45a; }
.gg-save-state.empty .dot { background: #9aa5b1; }
</style>
