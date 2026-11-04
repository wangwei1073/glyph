<script setup>
// 统一空状态：图标 + 标题 + 说明 + 操作按钮
defineProps({
  icon: { type: String, default: 'InfoFilled' },
  title: { type: String, default: '' },
  desc: { type: String, default: '' }
})
</script>

<template>
  <div class="empty-state">
    <el-icon class="es-icon" :size="26"><component :is="icon" /></el-icon>
    <div class="es-title">{{ title }}</div>
    <div v-if="desc" class="es-desc">{{ desc }}</div>
    <div v-if="$slots.default" class="es-actions"><slot /></div>
  </div>
</template>

<style scoped>
.empty-state {
  display: flex; flex-direction: column; align-items: center;
  text-align: center; padding: 36px 20px 28px;
}
.es-icon { color: var(--gg-text-4); margin-bottom: 10px; }
.es-title { font-size: 13px; font-weight: 600; color: var(--gg-text-2); }
.es-desc {
  font-size: 12px; color: var(--gg-text-3); line-height: 1.6;
  margin-top: 4px; max-width: 260px;
}
.es-actions { display: flex; gap: 8px; margin-top: 14px; flex-wrap: wrap; justify-content: center; }
</style>
