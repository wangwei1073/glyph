<script setup>
// 扩展管理：安装 / 启用 / 关闭（独立面板，代码运行留在「高级」）
import { ref, onBeforeUnmount } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { toggleExtension, installExtension, getInstallStatus } from '../api'

const spec = useSpecStore()
const meta = useMetaStore()

const extToggling = ref('')
const installing = ref('')
let installTimer = null

async function toggleExt(ext, on) {
  if (!ext.installed) return
  extToggling.value = ext.id
  try {
    const res = await toggleExtension(ext.id, on)
    if (res.meta) meta.applyMeta(res.meta)
    ElMessage.success(`${ext.label} 已${on ? '启用' : '关闭'}`)
    spec.renderNow()
  } catch (e) {
    ElMessage.error('切换失败: ' + e.message)
  } finally {
    extToggling.value = ''
  }
}

function extWhere(e) {
  const map = { geom: '图层', scale: '标度', theme: '主题', guide: '标签 · 图例', annotation: '注释' }
  const parts = (e.kind || []).map(k => map[k]).filter(Boolean)
  if (e.id === 'patchwork') return '拼图（先「存入图库」）'
  if (e.id === 'plotly') return '画布「交互预览」'
  return parts.length ? [...new Set(parts)].join(' · ') : '—'
}

async function pollInstall() {
  installTimer = null
  try {
    const res = await getInstallStatus()
    const job = res.job || {}
    if (job.status === 'running') { installTimer = setTimeout(pollInstall, 1200); return }
    installing.value = ''
    if (job.status === 'done') {
      if (res.meta) meta.applyMeta(res.meta)
      ElMessage.success(`${job.pkg} 安装完成，扩展已可用`)
    } else if (job.status === 'failed') {
      ElMessageBox.alert(
        (job.message ? job.message + '\n\n' : '') + (job.log || '（无日志）'),
        `${job.pkg} 安装失败`, { customClass: 'install-log-box', confirmButtonText: '知道了' })
    }
  } catch (e) {
    installing.value = ''
    ElMessage.error('查询安装状态失败：' + e.message)
  }
}

async function installPkg(pkg) {
  if (installing.value) return
  installing.value = pkg
  try {
    await installExtension(pkg)
    ElMessage.info(`开始安装 ${pkg}，完成后会自动刷新`)
    pollInstall()
  } catch (e) {
    installing.value = ''
    ElMessage.error('安装失败：' + e.message)
  }
}

onBeforeUnmount(() => { if (installTimer) clearTimeout(installTimer) })
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">扩展管理（安装 / 启用）</div>
    <div class="adv-pad">
      <div v-for="e in (meta.extensionCatalog || [])" :key="e.id" class="ext-row">
        <el-switch :model-value="e.enabled" size="small"
          :disabled="!e.installed || extToggling === e.id"
          :loading="extToggling === e.id"
          @update:model-value="(v) => toggleExt(e, v)" />
        <span class="ext-name" :class="{ off: !e.enabled }">{{ e.label }}</span>
        <template v-if="!e.installed">
          <el-tag size="small" type="info" :disable-transitions="true">未安装</el-tag>
          <el-button size="small" text class="ext-install" :loading="installing === e.pkg"
            :disabled="!!installing && installing !== e.pkg" @click="installPkg(e.pkg)">安装</el-button>
        </template>
        <template v-else-if="e.missingDeps && e.missingDeps.length">
          <el-tag size="small" type="warning" :disable-transitions="true">
            缺依赖：{{ e.missingDeps.join('、') }}
          </el-tag>
          <el-button size="small" text class="ext-install" :loading="installing === e.missingDeps[0]"
            :disabled="!!installing && installing !== e.missingDeps[0]"
            @click="installPkg(e.missingDeps[0])">安装 {{ e.missingDeps[0] }}</el-button>
        </template>
        <span v-else class="ext-where">{{ extWhere(e) }}</span>
      </div>
      <div class="gg-hint" style="padding-top: 6px">
        关闭扩展只会把它提供的组件从面板中移除（并重新生成注册表），不会卸载 R 包；
        生成代码时仍会自动带 <code class="gg-mono">library(pkg)</code> 与
        <code class="gg-mono">pkg::</code> 前缀。
      </div>
    </div>
  </div>
</template>

<style scoped>
.adv-pad { padding: 0 12px; }
.ext-row { display: flex; align-items: center; gap: 7px; padding: 6px 0; border-bottom: 1px dashed var(--gg-border); }
.ext-name { font-size: 12.5px; color: var(--gg-text-2); }
.ext-name.off { color: var(--gg-text-4); }
.ext-where { margin-left: auto; font-size: 11px; color: var(--gg-text-4); }
.ext-install { margin-left: auto; }
</style>
