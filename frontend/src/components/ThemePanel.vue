<script setup>
// 主题面板：内置主题 + 全部 theme() 元素编辑
import { ref, computed } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import ParamControl from './ParamControl.vue'
import EmptyState from './EmptyState.vue'

const meta = useMetaStore()
const spec = useSpecStore()

const search = ref('')
const openGroups = ref(['plot'])
const showAll = ref(false)

const PKG_LABELS = {
  ggthemes: 'ggthemes 扩展', ggprism: 'ggprism 扩展', ggpubr: 'ggpubr 扩展'
}

const baseGroups = computed(() => {
  const g2 = meta.themes.filter(t => (t.package || 'ggplot2') === 'ggplot2')
  const ext = meta.themes.filter(t => t.package && t.package !== 'ggplot2')
  const groups = [{ label: 'ggplot2 内置', options: g2 }]
  const pkgs = []
  for (const t of ext) if (!pkgs.includes(t.package)) pkgs.push(t.package)
  for (const p of pkgs) {
    groups.push({ label: PKG_LABELS[p] || `${p} 扩展`, options: ext.filter(t => t.package === p) })
  }
  return groups.filter(g => g.options.length)
})

const themeArgs = computed(() => {
  const base = spec.spec.theme.base
  return base ? (meta.themeByName[base]?.args || []) : []
})

function setBase(name) {
  spec.setTheme({ base: name || '', args: {} })
}
function setArg(name, v) {
  const args = { ...spec.spec.theme.args }
  if (v === null || v === '' || v === undefined) delete args[name]
  else args[name] = v
  spec.setTheme({ args })
}

// ---- 元素 ----
const setElements = computed(() => Object.keys(spec.spec.theme.elements))
const filteredGroups = computed(() => {
  const q = search.value.trim().toLowerCase()
  const res = []
  for (const g of meta.themeElementsGrouped) {
    const els = g.elements.filter(e =>
      showAll.value || setElements.value.includes(e.name) ||
      (q && (e.name.toLowerCase().includes(q) || e.label.toLowerCase().includes(q))))
    if (els.length) res.push({ ...g, elements: els })
  }
  return res
})
const totalShown = computed(() => filteredGroups.value.reduce((n, g) => n + g.elements.length, 0))
const totalElements = computed(() => meta.themeElements.length)

function elementState(name) {
  return spec.spec.theme.elements[name] ?? null
}
// 元素显示名：优先中文标签；没有中文标签时直接显示 R 元素名
// （此前一律只显示 legend.key.spacing.y 这种裸名字，扫读很费劲）
function dispLabel(e) {
  const l = (e.label || '').trim()
  return (!l || l === e.name) ? e.name : l
}
// 有中文标签时，把英文元素名作为次要信息跟在后面
function hasAltName(e) {
  const l = (e.label || '').trim()
  return !!l && l !== e.name
}
function setElement(name, val) {
  const els = { ...spec.spec.theme.elements }
  if (val === null) delete els[name]
  else els[name] = val
  spec.setTheme({ elements: els })
}
function isBlank(name) {
  const el = elementState(name)
  return !!(el && el.blank)
}
function toggleBlank(name, on) {
  if (!on) {
    const cur = elementState(name)
    if (cur && cur.props && Object.keys(cur.props).length) setElement(name, { type: cur.type || 'text', props: cur.props })
    else setElement(name, null)
  } else {
    setElement(name, { blank: true })
  }
}
function elType(name) {
  const meta1 = meta.themeElements.find(e => e.name === name)
  const el = elementState(name)
  return (el && el.type) || (meta1 ? meta1.type : 'text')
}

function setType(name, t) {
  const el = elementState(name) || {}
  setElement(name, { type: t, props: el.props || {} })
}
function setProp(name, prop, v) {
  const el = elementState(name)
  if (!el) return
  const props = { ...(el.props || {}) }
  if (v === null || v === '' || v === undefined) delete props[prop]
  else props[prop] = v
  if (Object.keys(props).length) setElement(name, { type: elType(name), props })
  else setElement(name, null)
}

function propSchemaFor(type, prop) {
  return (meta.themePropSchema[type] || []).find(p => p.name === prop) || { name: prop, widget: 'text' }
}

// value 型元素编辑
function setRawValue(name, v) {
  setElement(name, v === null ? null : v)
}
function setMargins(name, key, v) {
  const cur = elementState(name) || { margins: {} }
  const m = { ...(cur.margins || {}) }
  if (v === null || v === undefined) delete m[key]
  else m[key] = v
  setElement(name, Object.keys(m).length ? { margins: m } : null)
}
const marginKeys = [['t', '上'], ['r', '右'], ['b', '下'], ['l', '左']]
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="gg-subhead">基础主题</div>
    <div class="p-row">
      <el-select :model-value="spec.spec.theme.base" size="small" filterable style="width:100%"
        clearable placeholder="（无，使用默认 theme_gray）" @update:model-value="setBase($event || '')">
        <el-option-group v-for="g in baseGroups" :key="g.label" :label="g.label">
          <el-option v-for="t in g.options" :key="t.name" :value="t.name" :label="t.label" />
        </el-option-group>
      </el-select>
    </div>
    <EmptyState v-if="!spec.spec.theme.base && !Object.keys(spec.spec.theme.elements).length"
      icon="Brush" title="当前使用默认主题"
      desc="一键套用内置或扩展主题，也可以只微调个别元素。">
      <el-button size="small" @click="setBase('minimal')">极简主题</el-button>
      <el-button v-if="meta.ext.ggprism" size="small" @click="setBase('prism')">Prism 主题</el-button>
    </EmptyState>
    <template v-if="spec.spec.theme.base">
      <div v-for="p in themeArgs" :key="p.name" class="p-row">
        <label>{{ p.label }}</label>
        <ParamControl v-if="p.widget === 'number'" :schema="p"
          :model-value="spec.spec.theme.args[p.name] ?? null"
          @update:model-value="setArg(p.name, $event)" />
        <!-- 开关：官方文档里就是 TRUE/FALSE 的参数 -->
        <el-switch v-else-if="p.widget === 'bool'" size="small"
          :model-value="!!spec.spec.theme.args[p.name]"
          @update:model-value="setArg(p.name, $event)" />
        <!-- 下拉：字形、字体、调色板、图例位置、线型等有限取值 -->
        <el-select v-else-if="p.widget === 'select'"
          :model-value="String(spec.spec.theme.args[p.name] ?? '')" size="small" filterable
          clearable style="width:100%" @update:model-value="setArg(p.name, $event || null)">
          <el-option v-for="o in (p.options || [])" :key="o" :value="o" :label="o" />
        </el-select>
        <el-select v-else-if="p.widget === 'color' || p.name === 'base_family'"
          :model-value="String(spec.spec.theme.args[p.name] ?? '')" size="small" filterable
          clearable style="width:100%" @update:model-value="setArg(p.name, $event || null)">
          <template v-if="p.name === 'base_family'">
            <el-option v-for="f in meta.fonts" :key="f" :value="f" :label="f" />
          </template>
          <template v-else>
            <el-option v-for="c in ['#000000', '#2C3E50', '#4a90d9', '#e8734a', '#FFFFFF', '#f7f7f7']"
              :key="c" :value="c" :label="c" />
          </template>
        </el-select>
        <el-input v-else :model-value="String(spec.spec.theme.args[p.name] ?? '')" size="small"
          @update:model-value="setArg(p.name, $event || null)" />
      </div>
    </template>

    <div class="theme-toolbar">
      <el-input v-model="search" size="small" clearable placeholder="搜索主题元素，如 plot.title">
        <template #prefix><el-icon><Search /></el-icon></template>
      </el-input>
      <el-checkbox v-model="showAll" size="small">显示全部</el-checkbox>
    </div>
    <div class="gg-subhead" style="padding-top:2px">
      元素编辑（已设置 {{ setElements.length }} / 显示 {{ totalShown }}）
    </div>

    <el-collapse v-model="openGroups" class="theme-groups">
      <el-collapse-item v-for="g in filteredGroups" :key="g.key" :name="g.key">
        <template #title>
          <span class="grp-title">{{ g.label }}</span>
          <span class="grp-count">{{ g.elements.length }}</span>
        </template>
        <div v-for="e in g.elements" :key="e.name" class="el-box"
          :class="{ set: !!elementState(e.name), blanked: isBlank(e.name) }">
          <div class="el-head">
            <span class="el-dot" :class="'t-' + e.type" :title="'类型：' + e.type" />
            <span class="el-label" :class="{ 'gg-mono': !hasAltName(e) }" :title="e.name">{{ dispLabel(e) }}</span>
            <span v-if="hasAltName(e)" class="el-name gg-mono" :title="e.name">{{ e.name }}</span>
            <el-tooltip content="不显示该元素（element_blank）" placement="left">
              <button class="el-icon-btn" :class="{ on: isBlank(e.name) }"
                @click.stop="toggleBlank(e.name, !isBlank(e.name))">
                <el-icon><component :is="isBlank(e.name) ? 'Hide' : 'View'" /></el-icon>
              </button>
            </el-tooltip>
            <el-tooltip v-if="elementState(e.name)" content="清除该元素的设置" placement="left">
              <button class="el-icon-btn danger" @click.stop="setElement(e.name, null)">
                <el-icon><Delete /></el-icon>
              </button>
            </el-tooltip>
          </div>

          <!-- value 型 -->
          <template v-if="e.type === 'value' && !isBlank(e.name)">
            <template v-if="e.widget && e.widget.widget === 'margins'">
              <div class="el-props">
                <div v-for="mk in marginKeys" :key="mk[0]" class="margin-item">
                  <span>{{ mk[1] }}</span>
                  <el-input-number size="small" :model-value="elementState(e.name)?.margins?.[mk[0]]"
                    controls-position="right" style="width:70px"
                    @update:model-value="setMargins(e.name, mk[0], $event)" />
                </div>
              </div>
            </template>
            <template v-else-if="e.widget && e.widget.widget === 'unit'">
              <div class="el-props">
                <el-input-number size="small" :model-value="elementState(e.name)?.value"
                  controls-position="right" style="width:92px"
                  @update:model-value="setRawValue(e.name, { value: $event, unit: elementState(e.name)?.unit || 'pt' })" />
                <el-select size="small" :model-value="elementState(e.name)?.unit || 'pt'"
                  style="width:76px"
                  @update:model-value="setRawValue(e.name, { value: elementState(e.name)?.value ?? 0, unit: $event })">
                  <el-option v-for="u in meta.themeUnitOptions" :key="u" :value="u" :label="u" />
                </el-select>
              </div>
            </template>
            <template v-else>
              <div class="el-props">
                <ParamControl :schema="e.widget || { name: e.name, widget: 'text', exprOk: true }"
                  :model-value="elementState(e.name)"
                  @update:model-value="setRawValue(e.name, $event)" />
              </div>
            </template>
          </template>

          <!-- element_* 型 -->
          <template v-else-if="!isBlank(e.name) && e.type !== 'value'">
            <div v-if="!elementState(e.name) || !(elementState(e.name).props)" class="el-addhint">
              <el-button size="small" text @click="setType(e.name, e.type === 'value' ? 'text' : e.type)">
                <el-icon><Plus /></el-icon>设置 element_{{ e.type === 'title' ? 'text' : e.type }}
              </el-button>
            </div>
            <div v-else class="el-props">
              <div v-for="p in meta.themeElementsOf(elType(e.name))" :key="p.name" class="ep-row">
                <label>{{ p.label }}</label>
                <ParamControl :schema="p"
                  :model-value="elementState(e.name)?.props?.[p.name] ?? null"
                  @update:model-value="setProp(e.name, p.name, $event)" />
              </div>
              <div v-if="elType(e.name) === 'text'" class="ep-row">
                <label>margin 边距</label>
                <div class="margin-inline">
                  <el-input-number v-for="mk in marginKeys" :key="mk[0]" size="small"
                    :model-value="elementState(e.name)?.props?.margin?.[mk[0]]"
                    controls-position="right" style="width:64px" :placeholder="mk[1]"
                    @update:model-value="setProp(e.name, 'margin',
                      (() => {
                        const cur = elementState(e.name)?.props?.margin || {}
                        const v = $event
                        const next = { ...cur }
                        if (v === null || v === undefined) delete next[mk[0]]
                        else next[mk[0]] = v
                        return Object.keys(next).length ? next : null
                      })())" />
                </div>
              </div>
            </div>
          </template>
        </div>
      </el-collapse-item>
    </el-collapse>

    <!-- 空状态：默认只列「已设置」的元素，没有设置过时给出明确指引，
         否则会看到一片空白 + 「显示 0」，不知道是没设置还是加载失败 -->
    <div v-if="!filteredGroups.length" class="th-empty">
      <template v-if="search.trim()">
        没有匹配「{{ search }}」的主题元素
      </template>
      <template v-else>
        还没有自定义的主题元素<br>
        <span class="th-empty-sub">勾选上方「显示全部」可浏览全部 {{ totalElements }} 项</span>
      </template>
    </div>
  </div>
</template>

<style scoped>
.theme-toolbar {
  display: flex; align-items: center; gap: 10px; padding: 8px 12px 4px;
}

/* ---- 分组标题 ---- */
.theme-groups { border-top: 0; }
.theme-groups :deep(.el-collapse-item__header) {
  height: 34px; line-height: 34px; padding-left: 12px; gap: 6px;
  font-size: 12.5px; font-weight: 600; color: var(--gg-text-2);
  border-bottom: 1px solid var(--gg-border);
}
.theme-groups :deep(.el-collapse-item__header:hover) { background: rgba(128,128,128,.05); }
.theme-groups :deep(.el-collapse-item__wrap) { border-bottom: 0; }
.theme-groups :deep(.el-collapse-item__content) { padding-bottom: 6px; }
.theme-groups :deep(.el-collapse) { border: 0; }
.grp-title { flex-shrink: 0; }
/* 计数做成小胶囊，比「坐标轴 axis（58）」的括号读起来清爽 */
.grp-count {
  flex-shrink: 0; min-width: 20px; height: 16px; padding: 0 5px;
  border-radius: 8px; background: rgba(128,128,128,.12); color: var(--gg-text-3);
  font-size: 10.5px; font-weight: 600; line-height: 16px; text-align: center;
}

/* ---- 元素行 ---- */
.el-box {
  position: relative; margin: 2px 8px; padding: 6px 8px 7px 10px;
  border-radius: 4px; border: 1px solid transparent;
}
.el-box:hover { background: rgba(128,128,128,.055); border-color: var(--gg-border); }
/* 已设置的元素：左侧竖条 + 轻微底色，方便一眼找出改过哪些 */
.el-box.set { background: rgba(47,111,191,.055); border-color: rgba(47,111,191,.16); }
.el-box.set::before {
  content: ""; position: absolute; left: 0; top: 6px; bottom: 7px; width: 2px;
  border-radius: 0 2px 2px 0; background: var(--gg-brand);
}
.el-box.blanked .el-label { color: var(--gg-text-4); text-decoration: line-through; }

.el-head { display: flex; align-items: center; gap: 6px; }
/* 类型圆点：替代原来英文小方块徽标，颜色区分 value/text/line/rect */
.el-dot { flex-shrink: 0; width: 6px; height: 6px; border-radius: 50%; background: var(--gg-text-4); }
.el-dot.t-value { background: #2f6fbf; }
.el-dot.t-text { background: #8a5cd6; }
.el-dot.t-line { background: #2fa06a; }
.el-dot.t-rect { background: #d08a1a; }
.el-label {
  flex-shrink: 0; max-width: 45%; font-size: 12px; font-weight: 500; color: var(--gg-text-1);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.el-name {
  flex: 1; min-width: 0; font-size: 10.5px; color: var(--gg-text-4);
  overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
/* 图标按钮：平时弱化，hover 提亮；blank 生效时高亮为橙 */
.el-icon-btn {
  flex-shrink: 0; width: 18px; height: 18px; padding: 0; border: 0; background: none;
  color: var(--gg-text-4); cursor: pointer; border-radius: 3px;
  display: inline-flex; align-items: center; justify-content: center; font-size: 12px;
  opacity: .45; transition: opacity .12s, color .12s, background .12s;
}
.el-box:hover .el-icon-btn { opacity: 1; }
.el-icon-btn:hover { color: var(--gg-brand); background: rgba(47,111,191,.10); }
.el-icon-btn.danger:hover { color: #c0392b; background: rgba(192,57,43,.08); }
.el-icon-btn.on { opacity: 1; color: #c98a1a; background: rgba(201,138,26,.12); }

.el-props { padding: 5px 0 0 12px; }
.ep-row { display: flex; align-items: center; gap: 6px; padding: 2px 0; }
.ep-row > label { width: 84px; font-size: 12px; color: var(--el-text-color-secondary); flex-shrink: 0; }
.el-addhint { padding-left: 12px; padding-top: 3px; }
.margin-item { display: flex; align-items: center; gap: 4px; font-size: 12px; }
.margin-inline { display: flex; gap: 4px; }

/* 空状态提示 */
.th-empty {
  padding: 26px 18px; text-align: center; font-size: 12px; color: var(--gg-text-3); line-height: 1.9;
}
.th-empty-sub { font-size: 11px; color: var(--gg-text-4); }
</style>
