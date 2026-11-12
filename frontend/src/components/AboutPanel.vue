<script setup>
// 关于：项目简介 / 版本 / 作者与联系方式。
// 纯静态信息页，不读写 spec 或数据。
import { ElMessage } from 'element-plus'

const VERSION = '0.1.0'
const AUTHOR = 'DoctorW'
const EMAIL = 'wangwei1073@gmail.com'
const REPO = 'https://github.com/wangwei1073/glyph'

async function copyEmail() {
  try {
    await navigator.clipboard.writeText(EMAIL)
    ElMessage.success('邮箱已复制')
  } catch {
    ElMessage.warning('复制失败，请手动选择')
  }
}

async function copyRepo() {
  try {
    await navigator.clipboard.writeText(REPO)
    ElMessage.success('仓库地址已复制')
  } catch {
    ElMessage.warning('复制失败，请手动选择')
  }
}

const highlights = [
  { icon: 'Files', title: '图层化构图', desc: '箱线、散点、密度、地图等 180+ geom，逐层设置美学与参数' },
  { icon: 'PictureFilled', title: '实时渲染', desc: '改动即出图，PNG / SVG / PDF / TIFF / EMF 一键导出' },
  { icon: 'Menu', title: '图库与拼图', desc: '把满意的图存进图库，再组合成多面板图' },
  { icon: 'DataAnalysis', title: '统计与检验', desc: '描述统计、假设检验、回归、显著性标注直接画到图上' },
  { icon: 'Coin', title: '数据准备', desc: '类型转换、缺失值、离群值、筛选、去重、抽样可视化配置' },
  { icon: 'Link', title: '多数据源', desc: 'CSV / Excel / RDS / SQLite / PostgreSQL / MySQL / ODBC / 剪贴板' }
]
</script>

<template>
  <div class="about-root">
    <!-- 品牌区 -->
    <div class="ab-hero">
      <div class="ab-mark">Glyph</div>
      <div class="ab-tagline">ggplot2 的可视化工作台</div>
      <div class="ab-ver">
        <el-tag size="small" effect="plain" type="info">v{{ VERSION }}</el-tag>
      </div>
    </div>

    <!-- 简介 -->
    <div class="ab-sec">
      <div class="gg-subhead">项目简介</div>
      <p class="ab-p">
        Glyph 是一个面向科研绘图的 ggplot2 图形界面：不用记 R 语法，也能通过图层、
        美学映射和参数面板拼出符合期刊要求的图。所有图形都由真实 R 代码渲染，
        代码随时可查看、复制、带走。
      </p>
    </div>

    <!-- 能做什么 -->
    <div class="ab-sec">
      <div class="gg-subhead">主要能力</div>
      <div class="ab-list">
        <div v-for="h in highlights" :key="h.title" class="ab-item">
          <el-icon class="ab-ico"><component :is="h.icon" /></el-icon>
          <div class="ab-item-body">
            <div class="ab-item-title">{{ h.title }}</div>
            <div class="ab-item-desc">{{ h.desc }}</div>
          </div>
        </div>
      </div>
    </div>

    <!-- 作者 -->
    <div class="ab-sec">
      <div class="gg-subhead">作者</div>
      <div class="ab-author">
        <div class="ab-avatar">D</div>
        <div class="ab-author-body">
          <div class="ab-author-name">{{ AUTHOR }}</div>
          <div class="ab-author-role">设计与开发</div>
        </div>
      </div>
      <div class="ab-row">
        <span class="ab-k">邮箱</span>
        <a class="ab-mail" :href="`mailto:${EMAIL}`">{{ EMAIL }}</a>
        <el-button size="small" text type="primary" @click="copyEmail">复制</el-button>
      </div>
      <div class="ab-row">
        <el-icon class="ab-gh-ico"><Link /></el-icon>
        <span class="ab-k">GitHub</span>
        <a class="ab-mail" :href="REPO" target="_blank" rel="noopener">wangwei1073/glyph</a>
        <el-button size="small" text type="primary" @click="copyRepo">复制</el-button>
      </div>
    </div>

    <!-- 技术栈 -->
    <div class="ab-sec">
      <div class="gg-subhead">技术栈</div>
      <div class="ab-tags">
        <el-tag size="small" effect="plain">R</el-tag>
        <el-tag size="small" effect="plain">ggplot2</el-tag>
        <el-tag size="small" effect="plain">httpuv</el-tag>
        <el-tag size="small" effect="plain">Vue 3</el-tag>
        <el-tag size="small" effect="plain">Element Plus</el-tag>
        <el-tag size="small" effect="plain">CodeMirror 6</el-tag>
      </div>
    </div>

    <div class="ab-foot">
      图形由 ggplot2 渲染 · 界面与代码生成由 Glyph 提供
    </div>
  </div>
</template>

<style scoped>
.about-root { padding-bottom: 16px; }

/* 品牌区 */
.ab-hero {
  padding: 22px 16px 18px;
  border-bottom: 1px solid var(--gg-border);
  background: linear-gradient(180deg, var(--gg-brand-weak) 0%, transparent 100%);
}
.ab-mark {
  font-size: 30px; font-weight: 800; letter-spacing: .4px; line-height: 1.25;
  display: inline-block;
  background: linear-gradient(90deg, var(--gg-brand) 0%, #54b28e 100%);
  -webkit-background-clip: text; background-clip: text;
  color: var(--gg-brand);
}
@supports ((background-clip: text) or (-webkit-background-clip: text)) {
  .ab-mark {
    color: transparent;
    -webkit-text-fill-color: transparent;
  }
}
.ab-tagline { margin-top: 4px; font-size: 12.5px; color: var(--gg-text-3); }
.ab-ver { margin-top: 10px; }

/* 小节 */
.ab-sec { padding: 12px 14px 2px; }
.ab-p { margin: 6px 0 2px; font-size: 12.5px; line-height: 1.75; color: var(--gg-text-2); }

/* 能力列表 */
.ab-list { display: flex; flex-direction: column; gap: 8px; margin-top: 8px; }
.ab-item { display: flex; gap: 9px; align-items: flex-start; }
.ab-ico {
  flex-shrink: 0; margin-top: 1px;
  width: 22px; height: 22px; border-radius: 6px;
  display: inline-flex; align-items: center; justify-content: center;
  background: var(--gg-brand-weak); color: var(--gg-brand); font-size: 13px;
}
.ab-item-body { min-width: 0; }
.ab-item-title { font-size: 12.5px; font-weight: 600; color: var(--gg-text-1); }
.ab-item-desc { font-size: 11.5px; line-height: 1.6; color: var(--gg-text-3); margin-top: 1px; }

/* 作者 */
.ab-author { display: flex; align-items: center; gap: 10px; margin-top: 10px; }
.ab-avatar {
  width: 36px; height: 36px; border-radius: 50%; flex-shrink: 0;
  display: flex; align-items: center; justify-content: center;
  background: linear-gradient(135deg, var(--gg-brand) 0%, #54b28e 100%);
  color: #fff; font-size: 16px; font-weight: 700;
}
.ab-author-name { font-size: 13px; font-weight: 600; color: var(--gg-text-1); }
.ab-author-role { font-size: 11.5px; color: var(--gg-text-3); margin-top: 1px; }
.ab-row {
  display: flex; align-items: center; gap: 6px;
  margin-top: 10px; padding: 7px 9px;
  border: 1px solid var(--gg-border); border-radius: 6px;
  background: var(--gg-panel);
}
.ab-k { font-size: 11.5px; color: var(--gg-text-3); flex-shrink: 0; }
.ab-gh-ico { flex-shrink: 0; font-size: 13px; color: var(--gg-text-3); margin-right: -2px; }
.ab-mail {
  font-size: 12px; color: var(--gg-brand); text-decoration: none;
  min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
}
.ab-mail:hover { text-decoration: underline; }

/* 技术栈 */
.ab-tags { display: flex; flex-wrap: wrap; gap: 6px; margin-top: 9px; }

.ab-foot {
  margin: 18px 14px 0; padding-top: 10px;
  border-top: 1px dashed var(--gg-border);
  font-size: 11px; color: var(--gg-text-4); text-align: center;
}
</style>
