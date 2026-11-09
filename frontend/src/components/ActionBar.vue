<script setup>
// 底部工具区：保存状态 / 项目操作 / 暗色模式 / 退出服务
// 渲染与自动/手动切换已移到画布顶栏（Canvas.vue），此处不再重复。
// compact=true 时用于左栏收起后的侧边浮层。
import { computed } from 'vue'
import { ElMessageBox } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { shutdownServer } from '../api'

const props = defineProps({
  compact: { type: Boolean, default: false },  // 侧边浮层模式：只放核心按钮
  mini: { type: Boolean, default: false }     // 左窄栏模式：图标纵向排列
})
const emit = defineEmits(['project'])

const spec = useSpecStore()

// 保存状态：这里只表达「项目有没有未保存的改动」。
// 「空画布」属于画布自身状态，已移到画布底栏（Canvas.vue 的 statusParts）。
const hasCanvas = computed(() => spec.hasContent)
const saveLabel = computed(() => (spec.dirty ? '未保存' : '已保存'))
const saveHint = computed(() => (spec.dirty ? '有未保存的改动（项目 → 保存）' : '所有改动已保存'))

function toggleDark() {
  spec.dark = !spec.dark
  document.documentElement.classList.toggle('dark', spec.dark)
}
function cmd(c) { emit('project', c) }

// 退出服务：先确认，再请求后端优雅停止；成功后页面变成「已退出」提示页
const quitting = computed(() => false)
async function quitApp() {
  const dirtyTip = spec.dirty ? '\n\n注意：项目有未保存的改动，退出后会丢失。' : ''
  try {
    await ElMessageBox.confirm(
      `将停止本地 R 服务并关闭 Glyph。之后需要重新双击 run_app.bat 才能再次使用。${dirtyTip}`,
      '退出 Glyph',
      { type: 'warning', confirmButtonText: '退出', cancelButtonText: '取消' }
    )
  } catch { return }
  try {
    await shutdownServer()
    document.body.classList.add('gg-quit')
    // 用最简提示页替换整个界面：服务已停，继续操作只会报错
    document.getElementById('app').innerHTML =
      '<div class="gg-quit-screen">'
      + '<div class="gg-quit-title">Glyph 已退出</div>'
      + '<div class="gg-quit-sub">本地服务已停止，可以关闭此页面了。</div>'
      + '<div class="gg-quit-sub">下次使用请重新双击 <code>run_app.bat</code>。</div>'
      + '</div>'
    document.title = 'Glyph 已退出'
  } catch (e) {
    // 服务可能已经先一步退出（请求未及返回），这种情况同样视为成功
    document.getElementById('app').innerHTML =
      '<div class="gg-quit-screen">'
      + '<div class="gg-quit-title">Glyph 已退出</div>'
      + '<div class="gg-quit-sub">本地服务已停止，可以关闭此页面了。</div>'
      + '</div>'
  }
}
</script>

<template>
  <div class="act-bar" :class="{ compact, mini }">
    <!-- 左：项目保存状态 -->
    <el-tooltip :content="saveHint" placement="top">
      <span class="gg-save-state" :class="{ dirty: spec.dirty, empty: !hasCanvas }">
        <i class="dot" /><span class="save-txt">{{ saveLabel }}</span>
      </span>
    </el-tooltip>
    <span class="act-spacer" />

    <!-- 右：暗色 + 退出 + 项目（项目固定在最右）。三个动作间距保持一致 -->
    <div class="act-actions">
      <el-tooltip :content="spec.dark ? '亮色模式' : '暗色模式'" placement="top">
        <el-button size="small" text class="act-btn act-dark" @click="toggleDark">
          <el-icon><component :is="spec.dark ? 'Sunny' : 'Moon'" /></el-icon>
        </el-button>
      </el-tooltip>
      <el-tooltip content="停止本地服务并退出 Glyph" placement="top">
        <el-button size="small" text class="act-btn act-quit" :loading="quitting" @click="quitApp">
          <el-icon><SwitchButton /></el-icon>
        </el-button>
      </el-tooltip>
      <el-dropdown trigger="click" @command="cmd">
        <el-button size="small" text class="act-btn">
          <el-icon><FolderOpened /></el-icon><span class="act-label">项目</span><el-icon><ArrowDown /></el-icon>
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item command="save"><el-icon><FolderAdd /></el-icon>保存项目 (JSON)</el-dropdown-item>
            <el-dropdown-item command="load"><el-icon><FolderOpened /></el-icon>载入项目</el-dropdown-item>
            <el-dropdown-item command="clear" divided><el-icon><Delete /></el-icon>清空画布</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>
  </div>
</template>

<style scoped>
.act-bar {
  flex-shrink: 0; display: flex; align-items: center; gap: 4px;
  height: var(--gg-foot-h); padding: 0 10px;
  border-top: 1px solid var(--gg-border);
  background: var(--gg-panel);
  overflow: hidden;
}
.act-bar.compact {
  height: auto; flex-direction: column; align-items: stretch; gap: 5px;
  border: 1px solid var(--gg-border); border-radius: 8px; padding: 6px;
}
.act-spacer { flex: 1 1 auto; min-width: 4px; }
/* 右侧动作组：统一间距。Element 默认给相邻按钮加 12px margin-left，必须清掉 */
.act-actions { display: flex; align-items: center; gap: 2px; flex-shrink: 0; }
.act-actions :deep(.el-button + .el-button) { margin-left: 0; }
.act-btn { padding: 0 5px; height: 22px; font-size: 12px; flex-shrink: 0; }
.act-label { white-space: nowrap; }
/* 退出按钮：hover 才显警示色，平时与会话其它次要按钮同级 */
.act-quit:hover { color: #c0392b; background: rgba(192, 57, 43, .08); }
@media (max-width: 1240px) {
  .act-bar:not(.compact) .act-label { display: none; }
}

/* 保存状态点（提示信息靠左） */
.gg-save-state {
  display: inline-flex; align-items: center; gap: 5px; flex-shrink: 0;
  font-size: 11px; color: var(--gg-text-3, #6b7480);
  cursor: default; white-space: nowrap;
}
.gg-save-state .dot {
  width: 6px; height: 6px; border-radius: 50%; background: #54b28e; display: inline-block;
}
.gg-save-state.dirty { color: #c07f18; }
.gg-save-state.dirty .dot { background: #f0b45a; }
.gg-save-state.empty .dot { background: #9aa5b1; }
.act-bar.mini {
  height: auto; flex-direction: column; align-items: center; gap: 4px;
  padding: 0; border: 0; background: transparent; overflow: visible;
}
.act-bar.mini .save-txt { display: none; }
.act-bar.mini .gg-save-state { justify-content: center; padding: 2px 0; }
.act-bar.mini .act-actions { flex-direction: column; gap: 4px; }
.act-bar.mini .act-btn { width: 30px; height: 28px; justify-content: center; padding: 0; }
.act-bar.mini .act-label { display: none; }
</style>
