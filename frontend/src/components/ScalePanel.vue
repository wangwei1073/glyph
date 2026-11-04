<script setup>
// 标度面板：按 aesthetic 管理全部 scale（含次轴）
import { computed, ref } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import { useDataStore } from '../stores/data'
import ParamControl from './ParamControl.vue'

const meta = useMetaStore()
const spec = useSpecStore()
const data = useDataStore()

const activeAes = ref('')
const showAdd = ref(false)

const scaleByAes = computed(() => {
  const m = {}
  spec.spec.scales.forEach((s, i) => { m[s.aes] = { ...s, _i: i } })
  return m
})

const availableAes = computed(() => {
  // 当前图层用到的 aes + x/y 常备
  const used = new Set(['x', 'y'])
  for (const l of spec.spec.layers) {
    for (const k of Object.keys(l.aes || {})) used.add(k)
    for (const k of Object.keys(l.aesParams || {})) used.add(k)
  }
  return [...used].filter(a => meta.scalesByAes[a]?.length)
})

const commonParams = computed(() => meta.scaleCommonParams)

function addScale(aes) {
  spec.addScale(aes)
  showAdd.value = false
}
function setType(sc, type) {
  sc.type = type
  sc.params = {}
}
function setParam(sc, name, v) {
  if (v === null) delete sc.params[name]
  else sc.params[name] = v
}
function removeScale(sc) {
  spec.removeScale(sc._i)
}

// 次轴
function toggleSec(sc) {
  sc.secAxis = sc.secAxis ? null : { transform: '~ .', name: '', breaks: null, labels: null }
}

const label = (sc) => {
  const t = meta.scaleTypesOf(sc.aes).find(x => x.type === sc.type)
  return t ? `${t.label}` : sc.type
}
</script>

<template>
  <div class="gg-tab-scroll">
    <div class="scale-add">
      <el-popover v-model:visible="showAdd" placement="bottom-start" :width="220" trigger="click">
        <template #reference>
          <el-button size="small" type="primary" plain>
            <el-icon><Plus /></el-icon>为 aesthetic 添加标度
          </el-button>
        </template>
        <div class="gg-scroll" style="max-height:300px">
          <div v-for="a in availableAes" :key="a" class="geom-chip" style="margin:4px"
            @click="addScale(a)">
            {{ meta.aesByName[a]?.label || a }}
            <span v-if="scaleByAes[a]" style="color:#e8734a">（已有）</span>
          </div>
        </div>
      </el-popover>
    </div>

    <el-collapse v-model="activeAes">
      <el-collapse-item v-for="sc in spec.spec.scales" :key="sc.aes" :name="sc.aes">
        <template #title>
          <span class="sc-title">
            {{ meta.aesByName[sc.aes]?.label || sc.aes }}
            <span class="sc-type gg-mono">{{ label(sc) || '未选类型' }}</span>
          </span>
        </template>

        <div class="p-row">
          <label>标度函数</label>
          <el-select :model-value="sc.type" size="small" filterable style="width:100%"
            placeholder="选择 scale 类型" @update:model-value="setType(sc, $event)">
            <el-option-group v-for="pkg in ['ggplot2', 'ggsci', 'ggthemes']" :key="pkg"
              :label="pkg === 'ggplot2' ? 'ggplot2 核心' : pkg">
              <el-option v-for="t in meta.scaleTypesOf(sc.aes).filter(x => x.package === pkg)"
                :key="t.fn" :value="t.type" :label="t.label">
                <span class="gg-mono" style="font-size:11px">{{ t.fn }}</span>
              </el-option>
            </el-option-group>
          </el-select>
          <el-button size="small" text type="danger" @click="removeScale(sc)">
            <el-icon><Delete /></el-icon>
          </el-button>
        </div>

        <template v-if="sc.type">
          <div class="gg-subhead">该标度专属参数</div>
          <div v-for="p in (meta.scaleTypesOf(sc.aes).find(x => x.type === sc.type)?.params || [])"
            :key="p.name" class="p-row">
            <label>{{ p.label }}</label>
            <ParamControl :schema="p" :model-value="sc.params[p.name] ?? null"
              @update:model-value="setParam(sc, p.name, $event)" />
          </div>

          <div class="gg-subhead">通用参数</div>
          <div v-for="p in commonParams.filter(p => !['position', 'sec.axis'].includes(p.name))"
            :key="p.name" class="p-row">
            <label>{{ p.label }}</label>
            <ParamControl :schema="p" :model-value="sc.params[p.name] ?? null"
              @update:model-value="setParam(sc, p.name, $event)" />
          </div>

          <div v-if="['x', 'y'].includes(sc.aes)" class="p-row">
            <label>轴位置</label>
            <el-select :model-value="sc.position || ''" size="small" style="width:120px" clearable
              placeholder="默认" @update:model-value="sc.position = $event || ''">
              <el-option v-for="p in (sc.aes === 'x' ? ['top', 'bottom'] : ['left', 'right'])"
                :key="p" :value="p" :label="p" />
            </el-select>
          </div>

          <div v-if="['x', 'y', 'colour', 'fill'].includes(sc.aes)" class="p-row">
            <label>次轴 sec.axis</label>
            <el-switch :model-value="!!sc.secAxis" size="small" @update:model-value="toggleSec(sc)" />
          </div>
          <template v-if="sc.secAxis">
            <div class="p-row">
              <label>变换公式</label>
              <el-input :model-value="sc.secAxis.transform" size="small" class="gg-mono"
                placeholder="~ . * 2" @update:model-value="sc.secAxis.transform = $event" />
            </div>
            <div class="p-row">
              <label>名称</label>
              <el-input :model-value="sc.secAxis.name" size="small" clearable
                @update:model-value="sc.secAxis.name = $event" />
            </div>
            <div class="p-row">
              <label>breaks</label>
              <ParamControl :schema="{ name: 'breaks', widget: 'text', exprOk: true }"
                :model-value="sc.secAxis.breaks"
                @update:model-value="sc.secAxis.breaks = $event" />
            </div>
            <div class="p-row">
              <label>labels</label>
              <ParamControl :schema="{ name: 'labels', widget: 'text', exprOk: true }"
                :model-value="sc.secAxis.labels"
                @update:model-value="sc.secAxis.labels = $event" />
            </div>
          </template>
        </template>
        <div v-else style="padding:6px 12px;font-size:12px;color:var(--el-text-color-secondary)">
          请先选择标度函数
        </div>
      </el-collapse-item>
    </el-collapse>

    <div v-if="!spec.spec.scales.length" class="gg-empty-hint" style="padding:22px">
      尚未添加标度。示例：y 轴对数变换 → 添加 y → continuous → trans = log10
    </div>
  </div>
</template>

<style scoped>
.scale-add { padding: 9px 12px; border-bottom: 1px solid var(--gg-border); }
.sc-title { display: flex; align-items: center; gap: 8px; }
.sc-type { font-size: 11px; color: var(--gg-accent); }
</style>
