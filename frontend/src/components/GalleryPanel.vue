<script setup>
// 图库面板：管理已存档的图（存入 / 搜索 / 筛选 / 删除 / 打开代码图）
// 从拼图页拆出——图库是「资产」，拼图是「编辑」，分开后各自一屏可见。
// 拼图页通过「从图库选择…」弹窗消费这里的内容。
import { ref, computed, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { usePinStore } from '../stores/pins'
import { useSpecStore } from '../stores/spec'

const pins = usePinStore()
const spec = useSpecStore()

const q = ref('')
const typeFilter = ref('all')

const filteredPins = computed(() => {
  const kw = q.value.trim().toLowerCase()
  return pins.items.filter((p) => {
    if (typeFilter.value !== 'all' && p.type !== typeFilter.value) return false
    if (!kw) return true
    return (p.label || '').toLowerCase().includes(kw) || (p.src || '').toLowerCase().includes(kw)
  })
})

function thumbUrl(p) { return `/api/pins/thumb/${p.id}.png` }

async function saveCurrent() {
  if (!spec.spec.layers.length) {
    ElMessage.warning('当前没有图层，先在画布上构建一个图')
    return
  }
  saving.value = true
  try {
    const id = await pins.saveCurrent()
    ElMessage.success(`已存入图库：${pins.byId[id]?.label || id}`)
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    saving.value = false
  }
}

const saving = ref(false)

// 打开「代码图」：把存档的代码还原到画布（不碰「高级」页编辑器）
// 设计：编辑器内容只由用户主动动作改变（点「载入当前」或代码视图的「载入编辑器」），
// 避免用户只是浏览/参与拼图时，编辑器被悄悄覆盖。
async function openCode(p) {
  try {
    const res = await pins.openCode(p.id)
    if (res.type !== 'code') return
    spec.last = { ...(spec.last || {}), ok: true, pngUrl: res.pngUrl || null, png: null,
      code: res.code, warnings: [], messages: [], error: null, elapsed: 0,
      renderedFromCode: true }
    if (res.renderOpts && res.renderOpts.width) {
      spec.renderOpts = { ...spec.renderOpts, ...res.renderOpts }
    }
    // 不再写 spec.pendingCode —— 避免自动填进高级页编辑器
    if (!res.pngUrl) {
      ElMessage.warning('该条目没有预览图，可在「代码」视图点「载入编辑器」后重新运行')
    } else {
      ElMessage.success('已打开代码图；如需编辑，在「代码」视图点「载入编辑器」')
    }
  } catch (e) { ElMessage.error('打开失败：' + e.message) }
}

onMounted(() => { pins.load() })
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">图库（把画布当前图存档复用）</div>
    <div style="padding: 0 12px 6px">
      <el-button size="small" type="primary" plain :loading="saving"
        :disabled="!spec.spec.layers.length || spec.composeActive" @click="saveCurrent">
        <el-icon><AddFilled /></el-icon>存入当前绘图
      </el-button>
      <span v-if="spec.composeActive" class="gal-hint">
        拼图模式下先关闭组合再存图
      </span>
    </div>

    <div v-if="pins.loading" v-loading="true" style="min-height:40px" />
    <div class="pin-tools">
      <el-input v-model="q" size="small" placeholder="搜索图库…" clearable />
      <el-select v-model="typeFilter" size="small" style="width:104px">
        <el-option value="all" label="全部" />
        <el-option value="spec" label="图" />
        <el-option value="code" label="代码" />
      </el-select>
    </div>

    <div class="pin-grid">
      <div v-for="p in filteredPins" :key="p.id" class="pin-card"
        :class="{ code: p.type === 'code', clickable: p.type === 'code' }"
        :title="p.type === 'code' ? `${p.label}（点击打开代码图）` : p.label"
        @click="p.type === 'code' && openCode(p)">
        <div class="pc-thumb">
          <img :src="thumbUrl(p)" loading="lazy" alt="" />
          <span v-if="p.type === 'code'" class="pc-badge">代码</span>
        </div>
        <div class="pc-line">
          <span class="pc-name">{{ p.label }}</span>
          <el-popconfirm title="从图库删除该条目？" width="200" @confirm="pins.remove(p.id)">
            <template #reference>
              <button class="pc-del" title="从图库删除" @click.stop>
                <el-icon><Delete /></el-icon>
              </button>
            </template>
          </el-popconfirm>
        </div>
        <div class="pc-meta">
          {{ p.type === 'code' ? '代码图' : (p.layers + ' 层') }}
          <template v-if="p.srcType === 'dataset'"> · {{ p.src }}</template>
          <template v-else-if="p.srcType === 'user'"> · 自有数据</template>
        </div>
      </div>
    </div>

    <div v-if="!pins.items.length && !pins.loading" class="gg-empty-hint" style="padding:10px 12px">
      图库为空：把画布当前图存进来，即可参与拼图组合
    </div>
    <div v-else-if="!filteredPins.length" class="gg-empty-hint" style="padding:10px 12px">
      没有匹配「{{ q }}」的条目
    </div>
    <div class="gal-tip">
      共 {{ pins.items.length }} 条 · 存入后可在「拼图」页签通过「从图库选择…」组合
    </div>
  </div>
</template>

<style scoped>
.gal-hint { font-size: 11px; color: var(--el-text-color-secondary); margin-left: 8px; }
.gal-tip { padding: 2px 12px 12px; font-size: 11px; color: var(--gg-text-4); }

.pin-tools { display: flex; gap: 6px; padding: 0 12px 6px; align-items: center; }
.pin-tools .el-select { flex-shrink: 0; }

/* 自适应列数：卡片保持约 150px 的稳定尺寸，右栏变宽时自动增加列数 */
.pin-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(148px, 1fr));
  gap: 6px; padding: 0 12px 8px;
}
.pin-card {
  border: 1px solid var(--gg-border); border-radius: 6px; overflow: hidden;
  background: #fff; min-width: 0;
}
.pin-card.code { border-color: #f0d9b5; }
.pin-card.clickable { cursor: pointer; }
.pin-card.clickable:hover { border-color: var(--gg-brand); box-shadow: 0 1px 4px rgba(47,111,191,.12); }
/* 缩略图用 4:3 比例：卡片变宽时图跟着变高，避免「宽而扁」的裁切 */
.pc-thumb {
  position: relative; aspect-ratio: 4 / 3; max-height: 108px;
  background: #f6f8fb;
  display: flex; align-items: center; justify-content: center;
  border-bottom: 1px solid var(--gg-border);
}
/* contain：科研图以完整可见为准，不裁掉坐标轴与图例 */
.pc-thumb img { width: 100%; height: 100%; object-fit: contain; display: block; }
.pc-badge {
  position: absolute; top: 3px; left: 3px;
  font-size: 10px; line-height: 14px; padding: 0 4px; border-radius: 3px;
  background: #fff5e6; color: #a4700f; border: 1px solid #f0d9b5;
}
.pc-line { display: flex; align-items: center; gap: 2px; padding: 3px 4px 0 6px; }
.pc-name {
  flex: 1; min-width: 0; font-size: 12px; font-weight: 600; color: var(--gg-text-1);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.pc-del {
  flex-shrink: 0; width: 18px; height: 18px; padding: 0; border: 0; background: none;
  color: var(--gg-text-4); cursor: pointer; border-radius: 3px;
  display: inline-flex; align-items: center; justify-content: center; font-size: 12px;
}
.pc-del:hover { color: #c0392b; background: rgba(192,57,43,.08); }
.pc-meta {
  font-size: 10.5px; color: var(--gg-text-4); padding: 0 6px 4px;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
</style>
