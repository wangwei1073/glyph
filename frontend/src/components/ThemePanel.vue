<script setup>
// 主题面板：内置主题 + 全部 theme() 元素编辑
import { ref, computed } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import ParamControl from './ParamControl.vue'

const meta = useMetaStore()
const spec = useSpecStore()

const search = ref('')
const openGroups = ref(['plot'])
const showAll = ref(false)

const baseGroups = computed(() => {
  const g2 = meta.themes.filter(t => (t.package || 'ggplot2') === 'ggplot2')
  const ext = meta.themes.filter(t => t.package && t.package !== 'ggplot2')
  const groups = [{ label: 'ggplot2 内置', options: g2 }]
  if (ext.length) groups.push({ label: 'ggthemes 扩展', options: ext })
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

function elementState(name) {
  return spec.spec.theme.elements[name] ?? null
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
    <template v-if="spec.spec.theme.base">
      <div v-for="p in themeArgs" :key="p.name" class="p-row">
        <label>{{ p.label }}</label>
        <ParamControl v-if="p.widget === 'number'" :schema="p"
          :model-value="spec.spec.theme.args[p.name] ?? null"
          @update:model-value="setArg(p.name, $event)" />
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

    <el-collapse v-model="openGroups">
      <el-collapse-item v-for="g in filteredGroups" :key="g.key" :name="g.key">
        <template #title><span style="font-size:12.5px">{{ g.label }}（{{ g.elements.length }}）</span></template>
        <div v-for="e in g.elements" :key="e.name" class="el-box">
          <div class="el-head">
            <el-checkbox size="small" :model-value="isBlank(e.name)"
              @update:model-value="toggleBlank(e.name, $event)">blank</el-checkbox>
            <span class="el-name gg-mono" :title="e.name">{{ e.name }}</span>
            <span class="el-type">{{ e.type }}</span>
            <el-button v-if="elementState(e.name)" size="small" text type="danger"
              @click="setElement(e.name, null)">
              <el-icon><Delete /></el-icon>
            </el-button>
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
  </div>
</template>

<style scoped>
.theme-toolbar {
  display: flex; align-items: center; gap: 10px; padding: 8px 12px 4px;
}
.el-box { border-top: 1px dashed var(--gg-border); padding: 5px 12px 7px; }
.el-head { display: flex; align-items: center; gap: 8px; }
.el-name { font-size: 12px; }
.el-type { font-size: 10px; color: var(--el-text-color-secondary); border: 1px solid var(--gg-border); border-radius: 3px; padding: 0 4px; }
.el-props { padding: 4px 0 0 26px; }
.ep-row { display: flex; align-items: center; gap: 6px; padding: 2px 0; }
.ep-row > label { width: 84px; font-size: 11.5px; color: var(--el-text-color-secondary); flex-shrink: 0; }
.el-addhint { padding-left: 26px; }
.margin-item { display: flex; align-items: center; gap: 4px; font-size: 11.5px; }
.margin-inline { display: flex; gap: 4px; }
</style>
