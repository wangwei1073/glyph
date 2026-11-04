<script setup>
// 拼图面板：图库（pins）+ 组合序列 + plot_layout / plot_annotation
import { ref, onMounted } from 'vue'
import { ElMessage } from 'element-plus'
import { usePinStore } from '../stores/pins'
import { useSpecStore } from '../stores/spec'

const pins = usePinStore()
const spec = useSpecStore()
const saving = ref(false)

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
  spec.pushHistory()
  const c = cb()
  c.slots.push({ pin: pins.items[0]?.id || '', op: '+' })
  if (c.slots.length && !c.active) c.active = true
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
    <div v-for="p in pins.items" :key="p.id" class="pin-row">
      <span class="pin-badge gg-mono">{{ p.id }}</span>
      <span class="pin-name">{{ p.label }}</span>
      <span class="pin-meta">
        {{ p.layers }} 层
        <template v-if="p.srcType === 'dataset'"> · {{ p.src }}</template>
        <template v-else-if="p.srcType === 'user'"> · 自有数据</template>
      </span>
      <el-popconfirm title="从图库删除该条目？" width="200" @confirm="pins.remove(p.id)">
        <template #reference>
          <el-button size="small" text type="danger"><el-icon><Delete /></el-icon></el-button>
        </template>
      </el-popconfirm>
    </div>
    <div v-if="!pins.items.length && !pins.loading" class="gg-empty-hint" style="padding:10px 12px">
      图库为空：把画布当前图存进来，即可参与拼图组合
    </div>

    <div class="gg-subhead" style="margin-top:14px">组合序列</div>
    <div class="p-row">
      <label>渲染组合图</label>
      <el-switch :model-value="spec.composeActive" size="small"
        @update:model-value="(v) => { const c = cb(); c.active = v; }" />
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
      <el-button size="small" text :disabled="!pins.items.length" @click="addSlot">
        <el-icon><Plus /></el-icon>添加槽位
      </el-button>
    </div>
    <div v-if="spec.composeActive" style="padding:0 12px 8px">
      <el-alert type="success" :closable="false" show-icon>
        <template #title>画布正在渲染组合图（下方序列的 patchwork 结果）</template>
        <span style="font-size:11.5px">关闭「渲染组合图」即可回到单图编辑</span>
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
</template>

<style scoped>
.pin-row {
  display: flex; align-items: center; gap: 7px; padding: 4px 12px; font-size: 12.5px;
}
.pin-badge { font-size: 10.5px; background: rgba(74,144,217,.12); color: var(--gg-accent);
  border-radius: 3px; padding: 1px 5px; }
.pin-name { font-weight: 600; }
.pin-meta { color: var(--el-text-color-secondary); font-size: 11px; margin-right: auto; }
.slot-row {
  display: flex; align-items: center; gap: 5px; padding: 4px 12px;
}
.slot-no {
  width: 18px; height: 18px; border-radius: 50%; flex-shrink: 0;
  background: var(--gg-accent); color: #fff; font-size: 10.5px;
  display: flex; align-items: center; justify-content: center;
}
.op { font-size: 13px; color: var(--el-text-color-secondary); }
</style>
