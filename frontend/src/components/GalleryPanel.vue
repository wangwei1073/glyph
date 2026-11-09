<script setup>
// 图库面板：管理已存档的图（存入 / 搜索 / 筛选 / 删除 / 打开）
// 从拼图页拆出——图库是「资产」，拼图是「编辑」，分开后各自一屏可见。
// 拼图页通过「从图库选择…」弹窗消费这里的内容。
//
// 两类条目都能打开：
//   code 图 → 还原代码到画布（不碰编辑器，需手动「载入编辑器」）
//   spec 图 → 还原整个 spec（含数据源与加工步骤）到画布，可直接继续编辑
import { ref, computed, onMounted, nextTick, onBeforeUnmount } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { usePinStore } from '../stores/pins'
import { useSpecStore } from '../stores/spec'
import { useDataStore } from '../stores/data'

// ---- 卡片内联重命名 ----
// 卡片本身可点击（打开该图），所以重命名走「铅笔按钮 → 就地变输入框」，
// 不用双击（双击会先触发两次 click，把图打开）。
const renamingId = ref('')
const renameText = ref('')
let renameEl = null
let renameCancelled = false

function setRenameRef(el) { if (el) renameEl = el }

async function startRename(p) {
  renamingId.value = p.id
  renameText.value = p.label || ''
  renameCancelled = false
  await nextTick()
  renameEl?.focus?.()
  renameEl?.select?.()
}

function cancelRename() {
  renameCancelled = true
  renamingId.value = ''
  renameText.value = ''
}

async function commitRename() {
  if (renameCancelled) { renameCancelled = false; return }
  const id = renamingId.value
  if (!id) return
  const label = (renameText.value || '').trim()
  const cur = pins.byId[id]
  // 空名或没改动：直接退出，不打扰
  if (!label || (cur && label === cur.label)) {
    renamingId.value = ''
    return
  }
  try {
    const saved = await pins.rename(id, label)
    // 画布若正编辑这条，顶栏/按钮上的名字要跟着变
    if (spec.sourcePinId === id) spec.sourcePinLabel = saved || label
  } catch (e) {
    ElMessage.error(e.message)
  }
  renamingId.value = ''
  renameText.value = ''
}

// 组件卸载时结束编辑态，避免 blur 回调打到已销毁的引用
onBeforeUnmount(() => { renamingId.value = '' })

const pins = usePinStore()
const spec = useSpecStore()
const data = useDataStore()

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

// 缩略图地址带上 rev：条目被「更新」后 rev 变化，URL 才会变，
// 浏览器才会重新取图（只删后端缓存文件、加 no-store 都不够 —— URL 不变就不发请求）
function thumbUrl(p) {
  return `/api/pins/thumb/${p.id}.png?v=${p.rev || 0}`
}

// 存入图库：编辑自某条图库条目时默认覆盖更新（标签不变），否则新建。
// mode='new' 用于「另存为新条目」。
async function saveCurrent(mode = 'auto') {
  if (!spec.spec.layers.length) {
    ElMessage.warning('当前没有图层，先在画布上构建一个图')
    return
  }
  saving.value = true
  try {
    const res = await pins.saveCurrent(null, mode)
    const label = pins.byId[res.id]?.label || res.id
    if (res.created) ElMessage.success(`已另存为新条目：${label}`)
    else ElMessage.success(`已更新图库条目：${label}`)
  } catch (e) {
    ElMessage.error(e.message)
  } finally {
    saving.value = false
  }
}

function onSaveCommand(cmd) {
  saveCurrent(cmd === 'new' ? 'new' : 'update')
}

const saving = ref(false)

// 打开「代码图」：把存档的代码还原到画布（不碰「高级」页编辑器）
// 设计：编辑器内容只由用户主动动作改变（点「载入当前」或代码视图的「载入编辑器」），
// 避免用户只是浏览/参与拼图时，编辑器被悄悄覆盖。
async function openCode(p) {
  try {
    const res = await pins.openCode(p.id)
    if (res.type !== 'code') return
    // 画布现在是代码图，不再对应任何 spec 条目
    spec.sourcePinId = ''
    spec.sourcePinLabel = ''
    spec.last = { ...(spec.last || {}), ok: true, pngUrl: res.pngUrl || null, png: null,
      code: res.code, warnings: [], messages: [], error: null, elapsed: 0,
      renderedFromCode: true }
    // 不再写 spec.pendingCode —— 避免自动填进高级页编辑器
    // 尺寸交给画布自适应：不覆盖 renderOpts，否则会把画幅钉死成存档时的值，
    // 导致后续拖窗口/改尺寸时图不跟着变（自适应失效）。
    // 先显示存档的预览图（立刻有反馈），再按当前画布尺寸重渲染一次（保证清晰度匹配）。
    spec.renderNow()
    if (!res.pngUrl) {
      ElMessage.warning('该条目没有预览图，可在「代码」视图点「载入编辑器」后重新运行')
    } else {
      ElMessage.success('已打开代码图；如需编辑，在「代码」视图点「载入编辑器」')
    }
  } catch (e) { ElMessage.error('打开失败：' + e.message) }
}

// 打开「spec 图」：还原整个绘图规格（含数据源与加工步骤）到画布，可直接继续编辑。
//
// 为什么连数据源一起切：图层映射只对生成它的那个数据集有意义。
// 只还原绘图设置、沿用当前数据集，会出现「列名恰好相同但含义不同」→ 静默画错。
// 因此这里按「打开的就是那张图，包括它的数据」来做，仅在数据源失效时才阻断。
async function openSpec(p) {
  let pinSpec
  try {
    const res = await pins.openCode(p.id)     // /api/pins/open 对 spec 类型返回 specJson
    if (res.type !== 'spec' || !res.specJson) {
      return ElMessage.error('该条目不是可编辑的图')
    }
    pinSpec = JSON.parse(res.specJson)
  } catch (e) {
    return ElMessage.error('打开失败：' + e.message)
  }

  // 1) 空图没有意义
  if (!Array.isArray(pinSpec.layers) || !pinSpec.layers.length) {
    return ElMessage.warning('该条目没有图层，无法打开')
  }

  // 2) 数据源可用性预检：内置数据集一定在；用户上传数据可能已被清理
  const src = (pinSpec.data && pinSpec.data.source) || { type: 'none' }
  let srcLabel = ''
  if (src.type === 'dataset') {
    const hit = data.sources.find((s) => s.type === 'dataset' && s.name === src.name)
    if (!hit) return ElMessage.error(`该图使用的内置数据集 ${src.name} 不存在，无法打开`)
    srcLabel = hit.label || src.name
  } else if (src.type === 'user') {
    const hit = data.sources.find((s) => s.type === 'user' && s.name === src.id)
    if (!hit) {
      return ElMessage.error('该图使用的上传数据已不存在（可能已被清理），无法打开')
    }
    srcLabel = hit.label || hit.name
  } else {
    return ElMessage.warning('该图没有绑定数据源，无法还原')
  }

  // 3) 覆盖当前画布前确认（数据源会被一起切换）
  if (spec.spec.layers.length && spec.dirty) {
    try {
      await ElMessageBox.confirm(
        `打开该图会替换当前画布内容，并切换到它使用的数据集「${srcLabel}」。\n当前改动尚未保存，可用 Ctrl+Z 撤销。`,
        '打开图库中的图',
        { type: 'warning', confirmButtonText: '打开', cancelButtonText: '取消' }
      )
    } catch { return }
  }

  // 4) 还原 spec + 同步左侧数据面板
  // 顺序不能反：data.select() 会读 spec.spec.data 的加工步骤来算列，
  // 所以先 loadProject 再 select，列才是这张图对应的列。
  spec.loadProject(pinSpec)
  // 记住来源：之后「存入图库」会默认覆盖更新这一条（标签不变）
  spec.sourcePinId = p.id
  spec.sourcePinLabel = p.label
  // 图谱条目永远是单图，清掉可能残留的拼图状态与代码图标记
  spec.spec.combine = { ...(spec.spec.combine || {}), active: false, slots: [] }
  if (spec.last) spec.last.renderedFromCode = false

  const key = src.type === 'dataset' ? `dataset:${src.name}` : `user:${src.id}`
  try {
    await data.select(key)
  } catch (e) {
    return ElMessage.error('切换数据源失败：' + e.message)
  }

  spec.renderNow()
  ElMessage.success(`已打开「${p.label}」，数据源已切换到 ${srcLabel}`)
}

// 卡片点击：按类型分派
function onOpenPin(p) {
  if (p.type === 'code') return openCode(p)
  return openSpec(p)
}

onMounted(() => { pins.load() })
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">图库（把画布当前图存档复用）</div>
    <div style="padding: 0 12px 6px">
      <!-- 编辑自某条图库条目时：主按钮覆盖更新那条，下拉里保留「另存为新条目」 -->
      <el-dropdown v-if="spec.sourcePinId" split-button size="small" type="primary" plain
        :disabled="!spec.spec.layers.length || spec.composeActive || saving"
        @click="onSaveCommand('update')" @command="onSaveCommand">
        <el-icon style="margin-right:4px"><Refresh /></el-icon>
        更新到「{{ spec.sourcePinLabel || spec.sourcePinId }}」
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item command="update">
              更新到「{{ spec.sourcePinLabel || spec.sourcePinId }}」
            </el-dropdown-item>
            <el-dropdown-item command="new" divided>
              另存为新条目
            </el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
      <el-button v-else size="small" type="primary" plain :loading="saving"
        :disabled="!spec.spec.layers.length || spec.composeActive" @click="saveCurrent('new')">
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
        :class="{ code: p.type === 'code', clickable: true }"
        :title="p.type === 'code'
          ? `${p.label}（点击打开代码图）`
          : `${p.label}（点击打开并继续编辑，会切换到它使用的数据集）`"
        @click="onOpenPin(p)">
        <div class="pc-thumb">
          <img :src="thumbUrl(p)" loading="lazy" alt="" />
          <span v-if="p.type === 'code'" class="pc-badge">代码</span>
        </div>
        <div class="pc-line">
          <template v-if="renamingId === p.id">
            <!-- 重命名：回车确认，Esc 取消，失焦按确认处理 -->
            <el-input :ref="setRenameRef" v-model="renameText" size="small" class="pc-rename"
              maxlength="40" placeholder="名称" @click.stop
              @keyup.enter="commitRename" @keyup.esc="cancelRename" @blur="commitRename" />
          </template>
          <template v-else>
            <span class="pc-name" :title="p.label">{{ p.label }}</span>
            <button class="pc-edit" title="重命名" @click.stop="startRename(p)">
              <el-icon><EditPen /></el-icon>
            </button>
            <el-popconfirm title="从图库删除该条目？" width="200" @confirm="pins.remove(p.id)">
              <template #reference>
                <button class="pc-del" title="从图库删除" @click.stop>
                  <el-icon><Delete /></el-icon>
                </button>
              </template>
            </el-popconfirm>
          </template>
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
      共 {{ pins.items.length }} 条 · 点击卡片可打开并继续编辑 ·
      也可在「拼图」页签通过「从图库选择…」组合
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
/* 重命名按钮：常显但弱化。用户此前反馈「找不到改名入口」，
   所以不做成 hover 才出现；悬停卡片时提亮，避免抢注意力。 */
.pc-edit {
  flex-shrink: 0; width: 18px; height: 18px; padding: 0; border: 0; background: none;
  color: var(--gg-text-4); cursor: pointer; border-radius: 3px;
  display: inline-flex; align-items: center; justify-content: center; font-size: 12px;
  opacity: .5; transition: opacity .12s, color .12s;
}
.pin-card:hover .pc-edit { opacity: 1; }
.pc-edit:hover { color: var(--gg-brand); background: rgba(47,111,191,.10); }
/* 输入框占满名称那一行；卡片宽度有限，去掉默认内边距让它更紧凑 */
.pc-rename { flex: 1; min-width: 0; }
.pc-rename :deep(.el-input__wrapper) { padding: 0 4px; }
.pc-meta {
  font-size: 10.5px; color: var(--gg-text-4); padding: 0 6px 4px;
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
</style>
