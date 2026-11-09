<script setup>
// 拼图面板：组合序列 + plot_layout / plot_annotation
// 图库（素材管理）已拆到 GalleryPanel.vue；此页只负责"把选中的图组合成一张"。
import { ref, computed, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { usePinStore } from '../stores/pins'
import { useSpecStore } from '../stores/spec'
import { useMetaStore } from '../stores/meta'
import { checkPackages } from '../api'

const pins = usePinStore()
const spec = useSpecStore()
const meta = useMetaStore()

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

// 缩略图带 rev：条目更新后 URL 变化才会重新取图（与图库面板一致）
function thumbUrl(p) { return `/api/pins/thumb/${p.id}.png?v=${p.rev || 0}` }

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

// 标注样式（字号/加粗/颜色）单独放在 annotation.style，避免污染内容字段
const styleOpen = ref(false)
function styleOf() {
  const c = cb()
  if (!c.annotation.style) c.annotation.style = {}
  return c.annotation.style
}
function setStyle(name, v) {
  const s = styleOf()
  if (v === null || v === '' || v === undefined) delete s[name]
  else s[name] = v
  // 空对象就整体删掉，保持 spec 干净
  if (!Object.keys(s).length) delete cb().annotation.style
}
// 「恢复默认」：一次清掉所有标注样式
function resetStyle() {
  const c = cb()
  if (c.annotation.style) delete c.annotation.style
}

onMounted(() => { pins.load() })
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">组合序列</div>
    <div class="patch-tip">
      从「图库」页签管理素材；此处负责把选中的图组合成一张。
    </div>
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

    <!-- 标注样式：只作用于 plot_annotation 的标题/副标题/注释/标签，不影响子图 -->
    <div class="sty-head" @click="styleOpen = !styleOpen">
      <el-icon :size="12"><component :is="styleOpen ? 'ArrowDown' : 'ArrowRight'" /></el-icon>
      <span>标注样式</span>
      <span class="sty-hint">字号 / 加粗 / 颜色</span>
      <span style="flex:1" />
      <el-button size="small" text class="sty-reset" @click.stop="resetStyle">恢复默认</el-button>
    </div>
    <template v-if="styleOpen">
      <div class="sty-block">
      <div class="p-row">
        <label>标题</label>
        <el-input-number :model-value="styleOf().title_size ?? null" :min="6" :max="48" :step="1"
          size="small" controls-position="right" style="width:88px" placeholder="自动"
          @update:model-value="setStyle('title_size', $event)" />
        <el-checkbox :model-value="styleOf().title_bold === true" size="small"
          @update:model-value="setStyle('title_bold', $event || null)">加粗</el-checkbox>
        <el-color-picker :model-value="styleOf().title_color || ''" size="small"
          @update:model-value="setStyle('title_color', $event)" />
      </div>
      <div class="p-row">
        <label>副标题</label>
        <el-input-number :model-value="styleOf().subtitle_size ?? null" :min="6" :max="40" :step="1"
          size="small" controls-position="right" style="width:88px" placeholder="自动"
          @update:model-value="setStyle('subtitle_size', $event)" />
        <el-color-picker :model-value="styleOf().subtitle_color || ''" size="small"
          @update:model-value="setStyle('subtitle_color', $event)" />
      </div>
      <div class="p-row">
        <label>注释</label>
        <el-input-number :model-value="styleOf().caption_size ?? null" :min="6" :max="32" :step="1"
          size="small" controls-position="right" style="width:88px" placeholder="自动"
          @update:model-value="setStyle('caption_size', $event)" />
        <el-color-picker :model-value="styleOf().caption_color || ''" size="small"
          @update:model-value="setStyle('caption_color', $event)" />
      </div>
      <div class="p-row">
        <label>标签 tag</label>
        <el-input-number :model-value="styleOf().tag_size ?? null" :min="6" :max="32" :step="1"
          size="small" controls-position="right" style="width:88px" placeholder="自动"
          @update:model-value="setStyle('tag_size', $event)" />
        <el-checkbox :model-value="styleOf().tag_bold === true" size="small"
          @update:model-value="setStyle('tag_bold', $event || null)">加粗</el-checkbox>
        <el-color-picker :model-value="styleOf().tag_color || ''" size="small"
          @update:model-value="setStyle('tag_color', $event)" />
      </div>
      <div class="p-row">
        <label>字体</label>
        <el-select :model-value="styleOf().family || ''" size="small" clearable style="width:170px"
          placeholder="继承主题" @update:model-value="setStyle('family', $event || null)">
          <el-option value="sans" label="sans（无衬线）" />
          <el-option value="serif" label="serif（衬线）" />
          <el-option value="mono" label="mono（等宽）" />
        </el-select>
      </div>
      <div class="sty-tip">仅影响上方标题/副标题/注释/标签，不改变各子图内部字号。</div>
      </div>
    </template>

  <el-dialog v-model="pickerVisible" title="从图库选择（按选择顺序入槽）"
    width="min(1100px, 82vw)" top="6vh" append-to-body class="pick-dialog">
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
  </div>
</template>

<style scoped>
.patch-tip {
  padding: 0 12px 8px; font-size: 11px; line-height: 1.5; color: var(--gg-text-4);
}
/* 标注样式折叠区 */
.sty-head {
  display: flex; align-items: center; gap: 5px;
  padding: 8px 12px 4px; cursor: pointer; user-select: none;
  font-size: 12px; font-weight: 600; color: var(--gg-text-3);
}
.sty-head:hover { color: var(--gg-text-1); }
.sty-hint { font-weight: 400; font-size: 11px; color: var(--gg-text-4); }
.sty-reset { padding: 0 4px; height: 20px; font-size: 11px; color: var(--gg-text-4); }
.sty-reset:hover { color: var(--gg-brand); }
.sty-tip {
  padding: 2px 12px 8px; font-size: 11px; line-height: 1.5; color: var(--gg-text-4);
}
/* 样式行的控件较窄，覆盖全局 .p-row 的 240px 上限；
   标签缩窄到 76px，给「字号 + 加粗 + 颜色」留出空间 */
.p-row .el-input-number, .p-row .el-select { max-width: none; }
.p-row .el-checkbox { margin-right: 0; }
.p-row .el-color-picker { flex-shrink: 0; }
.sty-block .p-row { gap: 6px; padding-right: 14px; }
.sty-block .p-row > label { width: 76px; }
.sty-block .el-input-number { width: 82px !important; }

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
/* 图库卡片：紧凑两层（缩略图 + 名称/元信息），删除按钮内联在名称行 */
/* 自适应列数：卡片保持约 150px 的稳定尺寸，右栏变宽时自动增加列数，
   而不是把两张卡片撑大（否则缩略图会被拉伸、信息密度反而下降） */
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
/* 缩略图用 4:3 比例而不是固定高度：卡片变宽时图跟着变高，
   避免出现「宽而扁」的挤压缩略图（列数固定后卡片宽度基本稳定，此处只兜底） */
.pc-thumb {
  position: relative; aspect-ratio: 4 / 3; max-height: 108px;
  background: #f6f8fb;
  display: flex; align-items: center; justify-content: center;
  border-bottom: 1px solid var(--gg-border);
}
/* contain：科研图以完整可见为准，不裁掉坐标轴与图例 */
.pc-thumb img { width: 100%; height: 100%; object-fit: contain; display: block; }
/* 徽标改为小色块，比 el-tag 省空间 */
.pc-badge {
  position: absolute; top: 3px; left: 3px;
  font-size: 10px; line-height: 14px; padding: 0 4px; border-radius: 3px;
  background: #fff5e6; color: #a4700f; border: 1px solid #f0d9b5;
}
/* 名称行：名称 + 删除按钮，单行不换行 */
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
/* 选择器弹窗：弹窗已放大，卡片最小宽度同步提高，避免出现过小的碎图 */
.pick-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(168px, 1fr));
  gap: 10px; max-height: 62vh; overflow: auto; align-content: start;
}
.pick-card { border: 1px solid var(--gg-border); border-radius: 6px; overflow: hidden; cursor: pointer; background: #fff; }
.pick-card:hover { border-color: var(--gg-brand-weak); }
.pick-card.on { border-color: var(--gg-brand); box-shadow: 0 0 0 1px var(--gg-brand) inset; }
/* contain：与图库卡片一致，保证坐标轴/图例完整可见 */
.pick-thumb { position: relative; aspect-ratio: 4 / 3; max-height: 150px; background: #f6f8fb; display: flex; align-items: center; justify-content: center; }
.pick-thumb img { width: 100%; height: 100%; object-fit: contain; display: block; }
.pick-no { position: absolute; top: 4px; right: 4px; min-width: 18px; height: 18px; border-radius: 9px;
  background: var(--gg-brand); color: #fff; font-size: 11px; display: flex; align-items: center; justify-content: center; padding: 0 4px; }
.pick-name { font-size: 12px; padding: 4px 6px 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.pick-meta { padding: 2px 6px 5px; font-size: 10.5px; color: var(--gg-text-4); }
</style>
