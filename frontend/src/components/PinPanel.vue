<script setup>
// 拼图面板：图库（pins）+ 组合序列 + plot_layout / plot_annotation
import { ref, computed, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { usePinStore } from '../stores/pins'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { checkPackages } from '../api'

const pins = usePinStore()
const spec = useSpecStore()
const meta = useMetaStore()
const saving = ref(false)
const q = ref('')
const typeFilter = ref('all')
const filteredPins = computed(() => {
  const kw = q.value.trim().toLowerCase()
  return pins.items.filter(p => {
    if (typeFilter.value !== 'all' && (p.type || 'spec') !== typeFilter.value) return false
    if (!kw) return true
    return (p.label || '').toLowerCase().includes(kw) || (p.src || '').toLowerCase().includes(kw)
  })
})
function thumbUrl(p) { return `/api/pins/thumb/${p.id}.png` }

// 拼图组合依赖 patchwork；关闭后禁用组合相关操作（图库存取本身不受影响）
const patchworkOn = computed(() => !!(meta.ext && meta.ext.patchwork))

function ensurePatchwork() {
  if (patchworkOn.value) return true
  ElMessage.warning('patchwork 扩展已在「高级 → 扩展管理」中关闭，无法拼图')
  return false
}

const cb = () => {
  const c = spec.spec.combine
  if (!c.slots) c.slots = []
  if (!c.layout) c.layout = {}
  if (!c.annotation) c.annotation = {}
  return c
}

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

function addSlot() {
  if (!ensurePatchwork()) return
  spec.pushHistory()
  const c = cb()
  c.slots.push({ pin: pins.items[0]?.id || '', op: '+' })
  if (c.slots.length && !c.active) c.active = true
}

const pickerVisible = ref(false)
const pickerSel = ref([])

function openPicker() {
  if (!ensurePatchwork()) return
  pickerSel.value = []
  pickerVisible.value = true
}
function togglePick(id) {
  const i = pickerSel.value.indexOf(id)
  if (i >= 0) pickerSel.value.splice(i, 1)
  else pickerSel.value.push(id)
}
function confirmPicker() {
  if (!pickerSel.value.length) return
  spec.pushHistory()
  const c = cb()
  for (const id of pickerSel.value) c.slots.push({ pin: id, op: '+' })
  if (c.slots.length) c.active = true
  pickerVisible.value = false
}
function removeSlot(i) {
  spec.pushHistory()
  const c = cb()
  c.slots.splice(i, 1)
  if (!c.slots.length) c.active = false
}
function moveSlot(i, dir) {
  const c = cb()
  const j = i + dir
  if (j < 0 || j >= c.slots.length) return
  spec.pushHistory()
  const arr = c.slots
  ;[arr[i], arr[j]] = [arr[j], arr[i]]
}
const opOpts = [
  { v: '+', l: '+ 并排拼接' },
  { v: '|', l: '| 水平嵌套' },
  { v: '-', l: '- 垂直嵌套' }
]

// layout / annotation 编辑
function setLayout(name, v) {
  const c = cb()
  if (v === null || v === '' || v === undefined) delete c.layout[name]
  else c.layout[name] = v
}
function setAnnot(name, v) {
  const c = cb()
  if (v === null || v === '' || v === undefined) delete c.annotation[name]
  else c.annotation[name] = v
}

onMounted(() => { pins.load() })

async function openCode(p) {
  try {
    const res = await pins.openCode(p.id)
    if (res.type !== 'code') return
    spec.last = { ...(spec.last || {}), ok: true, pngUrl: res.pngUrl || null, png: null,
      code: res.code, warnings: [], messages: [], error: null, elapsed: 0 }
    if (res.renderOpts && res.renderOpts.width) {
      spec.renderOpts = { ...spec.renderOpts, ...res.renderOpts }
    }
    spec.pendingCode = res.code
    if (!res.pngUrl) ElMessage.warning('该条目没有预览图，已在高级页载入代码，运行后可重新生成')
    else ElMessage.success('已打开代码图，可在「高级」中查看与运行')
  } catch (e) { ElMessage.error('打开失败：' + e.message) }
}
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">图库（把画布当前图存档复用）</div>
    <div style="padding: 0 12px 6px">
      <el-button size="small" type="primary" plain :loading="saving"
        :disabled="!spec.spec.layers.length || spec.composeActive" @click="saveCurrent">
        <el-icon><AddFilled /></el-icon>存入当前绘图
      </el-button>
      <span v-if="spec.composeActive" style="font-size:11px;color:var(--el-text-color-secondary);margin-left:8px">
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
      <div v-for="p in filteredPins" :key="p.id" class="pin-card" :class="{ code: p.type === 'code' }">
        <div class="pc-thumb">
          <img :src="thumbUrl(p)" loading="lazy" alt="" />
          <el-tag v-if="p.type === 'code'" size="small" type="warning" class="pc-badge">代码</el-tag>
        </div>
        <div class="pc-name" :title="p.label">{{ p.label }}</div>
        <div class="pc-meta">
          {{ p.type === 'code' ? '代码图' : (p.layers + ' 层') }}
          <template v-if="p.srcType === 'dataset'"> · {{ p.src }}</template>
          <template v-else-if="p.srcType === 'user'"> · 自有数据</template>
        </div>
        <div class="pc-actions">
          <el-button v-if="p.type === 'code'" size="small" text type="primary" @click="openCode(p)">打开</el-button>
          <el-popconfirm title="从图库删除该条目？" width="200" @confirm="pins.remove(p.id)">
            <template #reference>
              <el-button size="small" text type="danger"><el-icon><Delete /></el-icon></el-button>
            </template>
          </el-popconfirm>
        </div>
      </div>
    </div>
    <div v-if="!pins.items.length && !pins.loading" class="gg-empty-hint" style="padding:10px 12px">
      图库为空：把画布当前图存进来，即可参与拼图组合
    </div><div class="gg-subhead" style="margin-top:14px">组合序列</div>
    <el-alert v-if="!patchworkOn" type="warning" :closable="false" show-icon
      style="margin:0 12px 6px" title="patchwork 扩展已关闭">
      拼图组合不可用。可在「高级 → 扩展管理」中重新启用；图库的存取不受影响。
    </el-alert>
    <div class="p-row">
      <label>渲染组合图</label>
      <el-switch :model-value="spec.composeActive" size="small" :disabled="!patchworkOn"
        @update:model-value="(v) => { if (!ensurePatchwork()) return; const c = cb(); c.active = v; }" />
    </div>

    <div v-for="(sl, i) in cb().slots" :key="i" class="slot-row">
      <span class="slot-no gg-mono">{{ i + 1 }}</span>
      <el-select v-model="sl.pin" size="small" filterable style="flex:1" placeholder="选择图库条目">
        <el-option v-for="p in pins.items" :key="p.id" :value="p.id"
          :label="`${p.id} ${p.label}（${p.layers} 层）`" />
      </el-select>
      <template v-if="i < cb().slots.length - 1">
        <span class="op gg-mono">{{ (cb().slots[i + 1].op) || '+' }}</span>
        <el-select v-model="cb().slots[i + 1].op" size="small" style="width:52px">
          <el-option v-for="o in opOpts" :key="o.v" :value="o.v" :label="o.v" />
        </el-select>
      </template>
      <el-button size="small" text :disabled="i === 0" @click="moveSlot(i, -1)">
        <el-icon><ArrowUp /></el-icon>
      </el-button>
      <el-button size="small" text :disabled="i === cb().slots.length - 1" @click="moveSlot(i, 1)">
        <el-icon><ArrowDown /></el-icon>
      </el-button>
      <el-button size="small" text type="danger" @click="removeSlot(i)">
        <el-icon><Delete /></el-icon>
      </el-button>
    </div>
    <div style="padding: 2px 12px 8px">
      <el-button size="small" text :disabled="!pins.items.length || !patchworkOn" @click="addSlot">
        <el-icon><Plus /></el-icon>添加槽位
      </el-button>
      <el-button size="small" text :disabled="!pins.items.length || !patchworkOn" @click="openPicker">
        <el-icon><Grid /></el-icon>从图库选择…
      </el-button>
    </div>
    <div v-if="spec.composeActive" style="padding:0 12px 8px">
      <el-alert type="success" :closable="false" show-icon>
        <template #title>画布正在渲染组合图（下方序列的 patchwork 结果）</template>
        <span style="font-size: 12px">关闭「渲染组合图」即可回到单图编辑</span>
      </el-alert>
    </div>

    <div class="gg-subhead" style="margin-top:10px">plot_layout 布局</div>
    <div class="p-row">
      <label>ncol 列数</label>
      <el-input-number :model-value="cb().layout.ncol" size="small" :min="1" :step="1"
        controls-position="right" style="width:110px"
        @update:model-value="setLayout('ncol', $event)" />
    </div>
    <div class="p-row">
      <label>nrow 行数</label>
      <el-input-number :model-value="cb().layout.nrow" size="small" :min="1" :step="1"
        controls-position="right" style="width:110px"
        @update:model-value="setLayout('nrow', $event)" />
    </div>
    <div class="p-row">
      <label>widths 宽度比</label>
      <el-input :model-value="typeof cb().layout.widths === 'object' ? (cb().layout.widths.expr || '') : (cb().layout.widths || '')"
        size="small" class="gg-mono" placeholder="如 c(2, 1)"
        @update:model-value="setLayout('widths', $event ? { expr: $event } : null)" />
    </div>
    <div class="p-row">
      <label>heights 高度比</label>
      <el-input :model-value="typeof cb().layout.heights === 'object' ? (cb().layout.heights.expr || '') : (cb().layout.heights || '')"
        size="small" class="gg-mono" placeholder="如 c(1, 2)"
        @update:model-value="setLayout('heights', $event ? { expr: $event } : null)" />
    </div>
    <div class="p-row">
      <label>guides</label>
      <el-select :model-value="typeof cb().layout.guides === 'string' ? cb().layout.guides : ''"
        size="small" clearable filterable style="width:130px" placeholder="默认"
        @update:model-value="setLayout('guides', $event || null)">
        <el-option v-for="g in ['auto', 'collect', 'keep']" :key="g" :value="g" :label="g" />
      </el-select>
    </div>
    <div class="p-row">
      <label>byrow</label>
      <el-switch :model-value="!!cb().layout.byrow" size="small"
        @update:model-value="setLayout('byrow', $event || null)" />
    </div>
    <div class="p-row">
      <label>design</label>
      <el-input :model-value="typeof cb().layout.design === 'object' ? (cb().layout.design.expr || '') : (cb().layout.design || '')"
        size="small" class="gg-mono" placeholder="布局字符串（R 表达式）"
        @update:model-value="setLayout('design', $event ? { expr: $event } : null)" />
    </div>

    <div class="gg-subhead" style="margin-top:12px">plot_annotation 标注</div>
    <div class="p-row">
      <label>主标题</label>
      <el-input :model-value="cb().annotation.title || ''" size="small" clearable
        @update:model-value="setAnnot('title', $event || null)" />
    </div>
    <div class="p-row">
      <label>副标题</label>
      <el-input :model-value="cb().annotation.subtitle || ''" size="small" clearable
        @update:model-value="setAnnot('subtitle', $event || null)" />
    </div>
    <div class="p-row">
      <label>注释 caption</label>
      <el-input :model-value="cb().annotation.caption || ''" size="small" clearable
        @update:model-value="setAnnot('caption', $event || null)" />
    </div>
    <div class="p-row">
      <label>tag_levels</label>
      <el-select :model-value="typeof cb().annotation.tag_levels === 'string' ? cb().annotation.tag_levels : ''"
        size="small" clearable style="width:130px" placeholder="默认"
        @update:model-value="setAnnot('tag_levels', $event || null)">
        <el-option v-for="t in ['A', 'a', '1', 'i']" :key="t" :value="t" :label="t" />
      </el-select>
    </div>
  </div>

  <el-dialog v-model="pickerVisible" title="从图库选择（按选择顺序入槽）" width="560" append-to-body>
    <div class="pick-grid">
      <div v-for="p in pins.items" :key="p.id" class="pick-card"
        :class="{ on: pickerSel.includes(p.id) }" @click="togglePick(p.id)">
        <div class="pick-thumb">
          <img :src="thumbUrl(p)" loading="lazy" alt="" />
          <span v-if="pickerSel.includes(p.id)" class="pick-no">{{ pickerSel.indexOf(p.id) + 1 }}</span>
        </div>
        <div class="pick-name" :title="p.label">{{ p.label }}</div>
        <div class="pick-meta">
          <el-tag v-if="p.type === 'code'" size="small" type="warning">代码</el-tag>
          <span v-else>{{ p.layers }} 层</span>
        </div>
      </div>
    </div>
    <div v-if="!pins.items.length" class="gg-empty-hint" style="padding:12px">图库为空</div>
    <template #footer>
      <el-button @click="pickerVisible = false">取消</el-button>
      <el-button type="primary" :disabled="!pickerSel.length" @click="confirmPicker">
        加入 {{ pickerSel.length }} 个槽位
      </el-button>
    </template>
  </el-dialog>
</template>

<style scoped>
.pin-row {
  display: flex; align-items: center; gap: 7px; padding: 4px 12px; font-size: 13px;
}
.pin-badge { font-size: 11px; background: rgba(47, 111, 191,.12); color: var(--gg-accent);
  border-radius: 4px; padding: 1px 5px; }
.pin-name { font-weight: 600; }
.pin-meta { color: var(--el-text-color-secondary); font-size: 11px; margin-right: auto; }
.slot-row {
  display: flex; align-items: center; gap: 5px; padding: 4px 12px;
}
.slot-no {
  width: 18px; height: 18px; border-radius: 50%; flex-shrink: 0;
  background: var(--gg-accent); color: #fff; font-size: 11px;
  display: flex; align-items: center; justify-content: center;
}
.op { font-size: 13px; color: var(--el-text-color-secondary); }
.pin-tools { display: flex; gap: 6px; padding: 0 12px 8px; }
.pin-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px; padding: 0 12px 8px; }
.pin-card { border: 1px solid var(--gg-border); border-radius: 6px; overflow: hidden; background: #fff; }
.pin-card.code { border-color: #f0d9b5; }
.pc-thumb { position: relative; height: 84px; background: #f6f8fb; display: flex; align-items: center; justify-content: center; }
.pc-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
.pc-badge { position: absolute; top: 4px; left: 4px; }
.pc-name { font-size: 12px; font-weight: 600; padding: 4px 6px 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pc-meta { font-size: 10.5px; color: var(--gg-text-4); padding: 1px 6px 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pc-actions { display: flex; justify-content: flex-end; padding: 2px 4px 4px; }
.pick-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; max-height: 420px; overflow: auto; }
.pick-card { border: 1px solid var(--gg-border); border-radius: 6px; overflow: hidden; cursor: pointer; background: #fff; }
.pick-card.on { border-color: var(--gg-brand); box-shadow: 0 0 0 1px var(--gg-brand) inset; }
.pick-thumb { position: relative; height: 88px; background: #f6f8fb; }
.pick-thumb img { width: 100%; height: 100%; object-fit: cover; display: block; }
.pick-no { position: absolute; top: 4px; right: 4px; min-width: 18px; height: 18px; border-radius: 9px;
  background: var(--gg-brand); color: #fff; font-size: 11px; display: flex; align-items: center; justify-content: center; padding: 0 4px; }
.pick-name { font-size: 12px; padding: 4px 6px 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pick-meta { padding: 2px 6px 5px; font-size: 10.5px; color: var(--gg-text-4); }
</style>
