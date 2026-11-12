<script setup>
// 参数行：标签列 + 控件列，严格两列对齐。
// 布局规则（解决"每个设置项和控件摆放乱"）：
//   - 左列固定宽度、右对齐，过长省略号 + tooltip，不让标签把控件挤歪；
//   - 右列控件从同一 x 起对齐，统一高度 26px；
//   - fx（R 表达式）与「清除」固定在控件列右端，不随控件类型跳动；
//   - 布尔开关单独一行左对齐（没有标签宽度问题，避免控件挤在右侧）。
import { computed } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import ParamControl from './ParamControl.vue'
import ParamLabel from './ParamLabel.vue'

const meta = useMetaStore()
const spec = useSpecStore()

const curLayerParams = computed(() => meta.layerParams(spec.curLayer?.geom))
const curLayerStatParams = computed(() => meta.layerStatParams(spec.curLayer?.geom))
const chosenStatParams = computed(() => {
  const st = spec.curLayer?.stat
  return st ? meta.statParamsOf(st) : []
})
const positionParams = computed(() => {
  const p = spec.curLayer?.position?.type
  return p ? meta.positionParamsOf(p) : []
})

const usedParams = computed(() => {
  const l = spec.curLayer
  if (!l) return []
  const out = []
  for (const p of [...curLayerParams.value, ...curLayerStatParams.value, ...chosenStatParams.value]) {
    if (out.find(x => x.name === p.name)) continue
    out.push(p)
  }
  return out
})

function getP(obj, name) { return obj?.[name] ?? null }
function setParam(name, v) { spec.setLayerParam(spec.selectedLayer, name, v) }
function setPositionParam(name, v) {
  const pos = spec.spec.layers[spec.selectedLayer].position
  if (!pos) return
  if (v === null) delete pos.params[name]
  else pos.params[name] = v
}
</script>

<template>
  <div v-if="spec.curLayer" class="param-embedded">
    <!-- 顶部两列：stat / position，与下方参数行同一套对齐 -->
    <div class="pp-sec">
      <div class="pp-row">
        <div class="pp-lab"><label>stat</label></div>
        <div class="pp-ctl">
          <el-select :model-value="spec.curLayer.stat" size="small" filterable class="pp-fill"
            placeholder="geom 默认" @update:model-value="spec.spec.layers[spec.selectedLayer].stat = $event || ''">
            <el-option value="" :label="`默认 (${meta.geomByName[spec.curLayer.geom]?.defaultStat || 'identity'})`" />
            <el-option v-for="s in meta.stats" :key="s.name" :value="s.name" :label="s.label">
              <span class="opt-row">
                <span>{{ s.label }}</span>
                <span class="opt-fn gg-mono">{{ s.fn }}</span>
              </span>
            </el-option>
          </el-select>
        </div>
      </div>
      <div class="pp-row">
        <div class="pp-lab"><label>position</label></div>
        <div class="pp-ctl">
          <el-select :model-value="spec.curLayer.position?.type || ''" size="small" class="pp-fill"
            :placeholder="`默认 (${meta.geomByName[spec.curLayer.geom]?.defaultPosition || 'identity'})`"
            @update:model-value="(v) => { spec.spec.layers[spec.selectedLayer].position = { type: v || '', params: {} } }">
            <el-option value="" label="（geom 默认）" />
            <el-option v-for="p in meta.positions" :key="p.name" :value="p.name" :label="p.label" />
          </el-select>
        </div>
      </div>
    </div>

    <!-- position 参数 -->
    <template v-if="positionParams.length">
      <div class="pp-divider">position 参数</div>
      <div v-for="p in positionParams" :key="'pos-' + p.name" class="pp-row">
        <div class="pp-lab"><ParamLabel :label="p.label" :name="p.name" :desc="p.desc" :def="p.default" /></div>
        <div class="pp-ctl">
          <ParamControl :schema="p" :model-value="getP(spec.curLayer.position?.params, p.name)"
            @update:model-value="setPositionParam(p.name, $event)" />
        </div>
      </div>
    </template>

    <!-- geom / stat 参数 -->
    <div v-if="!usedParams.length" class="pp-empty">该 geom 无额外参数</div>
    <div v-for="p in usedParams" :key="p.name" class="pp-row">
      <div class="pp-lab"><ParamLabel :label="p.label" :name="p.name" :desc="p.desc" :def="p.default" /></div>
      <div class="pp-ctl">
        <ParamControl :schema="p" :model-value="getP(spec.curLayer.params, p.name)"
          @update:model-value="setParam(p.name, $event)" />
      </div>
    </div>
    <!-- 常量美学已移除：与美学映射的「常量」模式重复（那里控件更全），常量一律走美学面板 -->
  </div>
</template>

<style scoped>
.param-embedded { padding: 2px 0 6px; }
.opt-row { display: flex; justify-content: space-between; gap: 14px; align-items: center; }
.opt-fn { font-size: 11px; color: var(--el-text-color-secondary); }

/* 统一两列：左列固定 92px 右对齐，右列从同一 x 起 */
.pp-row {
  display: grid;
  grid-template-columns: 92px minmax(0, 1fr);
  align-items: center;
  gap: 8px;
  padding: 3px 10px;
  min-height: 30px;
}
.pp-lab {
  display: flex; align-items: center; justify-content: flex-end;
  min-width: 0; text-align: right;
}
.pp-lab > label,
.pp-lab :deep(.param-label-wrap) {
  font-size: var(--gg-fs-sm, 12px);
  color: var(--gg-text-2);
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
  justify-content: flex-end;
}
.pp-ctl {
  display: flex; align-items: center; gap: 4px;
  min-width: 0;
}
/* 控件自己撑满右列，宽度一致 */
.pp-ctl :deep(.p-ctl) { display: flex; align-items: center; gap: 4px; min-width: 0; flex: 1; }
.pp-ctl :deep(.el-select),
.pp-ctl :deep(.el-input),
.pp-ctl :deep(.el-input-number) { width: 100%; }
/* 开关/颜色这类窄控件不撑满，左对齐贴住列起点 */
.pp-ctl :deep(.el-switch),
.pp-ctl :deep(.el-color-picker) { flex-shrink: 0; }
.pp-fill { width: 100%; }

/* 小节标题：整行 + 分隔线，和参数行左对齐 */
.pp-divider {
  display: flex; align-items: center; gap: 6px;
  margin: 8px 0 2px;
  padding: 5px 10px 4px;
  border-top: 1px dashed var(--gg-border, rgba(128,128,128,.2));
  font-size: 11px; font-weight: 600;
  color: var(--gg-text-3, #6b7480);
}
.pp-tip { font-weight: 400; color: var(--gg-text-4, #98a1ab); }
.pp-empty { padding: 8px 12px; font-size: 12px; color: var(--el-text-color-secondary); }

/* 滑块行加高，圆形手柄不贴上下边 */
.pp-row:has(.el-slider) { min-height: 32px; }
@media (max-width: 340px) {
  .pp-row { grid-template-columns: 76px minmax(0, 1fr); }
}
</style>
