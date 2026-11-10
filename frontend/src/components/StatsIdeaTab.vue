<script setup>
// 图表建议页签（轻拆）：候选图由壳的 chartIdeas 计算后经 props 传入，应用动作回传壳执行
defineProps({
  ideas: { type: Array, default: () => [] },
  hasDesc: { type: Boolean, default: false },
  hasTest: { type: Boolean, default: false },
  hasReg: { type: Boolean, default: false }
})
const emit = defineEmits(['apply'])
</script>
<template>
  <div class="sd-pane">
    <aside class="sd-params">
      <div class="sp-hint" style="padding-top:0">
        依据数据列类型与已有的统计结果推导候选图。做过的统计越多，建议越贴合：
        跑过检验 → 推荐能展示组间差异的图；跑过回归 → 推荐散点加拟合线。
      </div>
      <div class="idea-tags">
        <el-tag v-if="hasDesc" size="small" type="success" :disable-transitions="true">描述统计</el-tag>
        <el-tag v-if="hasTest" size="small" type="success" :disable-transitions="true">检验</el-tag>
        <el-tag v-if="hasReg" size="small" type="success" :disable-transitions="true">回归</el-tag>
        <el-tag v-if="!hasDesc && !hasTest && !hasReg" size="small" type="info"
          :disable-transitions="true">仅按列类型推荐</el-tag>
      </div>
      <div class="sp-hint">
        点击「应用」会直接在当前画布上创建对应图层（可撤销）。
      </div>
    </aside>

    <section class="sd-result">
      <template v-if="ideas.length">
        <div class="gg-scroll idea-list">
          <div v-for="(it, i) in ideas" :key="i" class="idea-card">
            <div class="idea-rank">{{ i + 1 }}</div>
            <div class="idea-main">
              <div class="idea-title">
                {{ it.title }}
                <el-tag size="small" :type="i === 0 ? 'success' : 'info'"
                  :disable-transitions="true" class="idea-geom">{{ it.geom }}</el-tag>
              </div>
              <div class="idea-reason">{{ it.reason }}</div>
              <div v-if="it.extra" class="idea-extra">💡 {{ it.extra }}</div>
              <div class="idea-aes">
                <span v-for="(v, k) in it.aes" :key="k" class="aes-chip">
                  <b>{{ k }}</b><span class="aes-eq">=</span>
                  <span class="gg-mono">{{ v.map ?? v.value ?? '' }}</span>
                </span>
                <template v-if="it.stat">
                  <span class="aes-chip stat"><b>stat</b><span class="aes-eq">=</span>
                    <span class="gg-mono">{{ it.stat }}</span></span>
                </template>
                <template v-if="it.addLayer">
                  <span class="aes-plus">+</span>
                  <span class="aes-chip layer">
                    <span class="gg-mono">{{ it.addLayer.geom }}</span>
                    <template v-if="it.addLayer.params?.method">
                      <span class="aes-eq">/</span>
                      <span class="gg-mono">{{ it.addLayer.params.method }}</span>
                    </template>
                  </span>
                </template>
              </div>
            </div>
            <el-button size="small" type="primary" plain @click="emit('apply', it)">应用</el-button>
          </div>
        </div>
      </template>
      <div v-else class="gg-empty-hint" style="padding:24px">
        先在左侧选择数据源，或跑一次统计
      </div>
    </section>
  </div>
</template>
