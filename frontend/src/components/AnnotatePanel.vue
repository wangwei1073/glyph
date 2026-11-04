<script setup>
// 注释面板：annotate() / annotation_* 函数
import { ref } from 'vue'
import { useMetaStore } from '../stores/meta'
import { useSpecStore } from '../stores/spec'
import ParamControl from './ParamControl.vue'

const meta = useMetaStore()
const spec = useSpecStore()

const annotateGeoms = ['text', 'label', 'point', 'rect', 'segment', 'curve', 'pointrange', 'linerange', 'polygon', 'vline', 'hline', 'abline']
// 坐标类参数用 numberOrExpr：输入 5 生成 5，输入 mean(df$x) 生成表达式
const coordWidget = { widget: 'numberOrExpr', step: 1 }
const annotateParams = [
  { name: 'x', ...coordWidget, label: 'x' },
  { name: 'y', ...coordWidget, label: 'y' },
  { name: 'xmin', ...coordWidget, label: 'xmin' },
  { name: 'xmax', ...coordWidget, label: 'xmax' },
  { name: 'ymin', ...coordWidget, label: 'ymin' },
  { name: 'ymax', ...coordWidget, label: 'ymax' },
  { name: 'xend', ...coordWidget, label: 'xend' },
  { name: 'yend', ...coordWidget, label: 'yend' },
  { name: 'label', widget: 'text', label: 'label 文本' },
  { name: 'angle', widget: 'number', label: 'angle 角度', step: 5 },
  { name: 'colour', widget: 'color', label: 'colour 颜色' },
  { name: 'fill', widget: 'color', label: 'fill 填充' },
  { name: 'size', widget: 'number', label: 'size 大小', step: 0.5 },
  { name: 'alpha', widget: 'number', label: 'alpha 透明度', min: 0, max: 1, step: 0.05 },
  { name: 'hjust', widget: 'number', label: 'hjust', step: 0.05 },
  { name: 'vjust', widget: 'number', label: 'vjust', step: 0.05 },
  { name: 'linewidth', widget: 'number', label: 'linewidth', min: 0, step: 0.1 },
  { name: 'linetype', widget: 'linetype', label: 'linetype' },
  { name: 'slope', widget: 'number', label: 'slope 斜率', step: 0.1 },
  { name: 'intercept', widget: 'number', label: 'intercept 截距', step: 0.5 },
  { name: 'curvature', widget: 'number', label: 'curvature 曲率', step: 0.1 },
  { name: 'arrow', widget: 'text', label: 'arrow', exprOk: true }
]
const constParams = annotateParams

function addAnnotate() {
  spec.pushHistory()
  spec.spec.annotations.push({ kind: 'annotate', geom: 'text', params: { x: 0, y: 0 } })
}
function addFn(name) {
  spec.pushHistory()
  spec.spec.annotations.push({ kind: 'fn', name, params: {} })
}
function remove(i) {
  spec.pushHistory()
  spec.spec.annotations.splice(i, 1)
}
function setParam(a, name, v) {
  if (v === null) delete a.params[name]
  else a.params[name] = v
}
</script>

<template>
  <div class="gg-tab-scroll">
    <div style="padding: 9px 12px; display: flex; gap: 6px; flex-wrap: wrap">
      <el-button size="small" type="primary" plain @click="addAnnotate">
        <el-icon><Plus /></el-icon>annotate 标注
      </el-button>
      <el-dropdown @command="addFn">
        <el-button size="small">
          <el-icon><Plus /></el-icon>annotation 函数
        </el-button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item v-for="a in meta.annotations" :key="a.name" :command="a.name">
              {{ a.label }}
            </el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>

    <div v-for="(a, i) in spec.spec.annotations" :key="i" class="ann-card">
      <div class="ann-head">
        <b v-if="a.kind === 'annotate'">annotate("{{ a.geom }}")</b>
        <b v-else class="gg-mono">{{ a.fn || ('annotation_' + a.name) }}</b>
        <span style="flex:1" />
        <template v-if="a.kind === 'annotate'">
          <el-select v-model="a.geom" size="small" style="width:120px" filterable>
            <el-option v-for="g in annotateGeoms" :key="g" :value="g" :label="g" />
          </el-select>
        </template>
        <el-button size="small" text type="danger" @click="remove(i)">
          <el-icon><Delete /></el-icon>
        </el-button>
      </div>
      <div v-for="p in (a.kind === 'annotate' ? constParams : (meta.annotations.find(x => x.name === a.name)?.params || []))"
        :key="p.name" class="p-row">
        <label>{{ p.label }}</label>
        <ParamControl :schema="p" :model-value="a.params[p.name] ?? null"
          @update:model-value="setParam(a, p.name, $event)" />
      </div>
    </div>

    <div v-if="!spec.spec.annotations.length" class="gg-empty-hint" style="padding:18px">
      添加文字标注、参考线、对数刻度等。坐标值支持 R 表达式（如 mean(df$x)）
    </div>
  </div>
</template>

<style scoped>
.ann-card {
  border: 1px solid var(--gg-border); border-radius: 7px;
  margin: 7px 10px; padding: 6px 0 8px;
}
.ann-head {
  display: flex; align-items: center; gap: 6px;
  padding: 4px 9px 6px; border-bottom: 1px dashed var(--gg-border); margin-bottom: 4px;
  font-size: 12.5px;
}
</style>
