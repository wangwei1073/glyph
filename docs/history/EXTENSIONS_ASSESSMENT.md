# ggplot2 扩展引入评估（全量 170 个）

> 评估对象：<https://exts.ggplot2.tidyverse.org/gallery/> —— **170 个已注册扩展**
> 评估日期：2026-11-08
>
> **数据来源说明**：gallery 页面是 JS 动态渲染，`web_fetch` 抓取时正文会被截断在前 45 条。
> 本文的完整清单直接从页面 HTML 的 `.card grid-item` 结构解析得到 **170 条**（含名称、作者、
> 描述、标签、CRAN 状态），并用 CRAN 索引核对依赖闭包。可复现脚本见第五节。
>
> 配套文档：[EXTENSIONS.md](EXTENSIONS.md) 对 ggprism / ggpubr / ggstatsplot 做过逐包深度分析。

## 一、结论摘要

| 分类 | 数量 | 能否接入本项目 |
|---|---|---|
| 统计与建模 | 16 | ⭕ **高价值**，部分已接入 |
| 主题与排版 | 13 | ⭕ 高价值（纯 theme，接入成本最低） |
| 标度与配色 | 7 | ⭕ 高价值（纯 scale） |
| 轴/分面/图例 | 4 | ⭕ 中高价值 |
| 分类数据 | 6 | ⭕ 中（几何类，可接入） |
| 几何补充 | 15 | ⭕ 中（几何类，可接入） |
| 时间序列 | 8 | ⭕ 中 |
| 热图 | 3 | ⭕ 中 |
| 空间与地图 | 23 | ❌ **低**（需 sf 空间对象，与 data.frame 模型不符） |
| 生物/基因 | 8 | ❌ 低（领域专用数据结构） |
| 网络与流程 | 7 | ❌ 低（需 graph/tree/flow 对象） |
| 生存分析 | 1(+1) | ❌ 低（需 Surv 对象） |
| 交互/界面 | 3 | ❌ 不适配（输出形态不同） |
| 其他/通用 | 69 | 需逐个判断，多数为成品图函数或语法糖 |

**核心判断**：170 个里**真正适合本项目架构的约 45–55 个**，其余受限于「数据模型不兼容」或「输出形态不同」。

## 二、按类别逐项评估

### 2.1 统计与建模（16 个）—— 最高价值

本项目已有完整的 L1–L5 统计模块（描述统计/检验/标注/回归/基线表），这批是直接补强。

| 扩展 | 提供能力 | CRAN | 建议 |
|---|---|---|---|
| **ggpubr** | 统计检验标注、出版主题 | ✅ | ✅ **已接入** |
| **ggsignif** | 显著性括号 | ✅ | ✅ **已接入**（L3 底层） |
| **ggstats** | p 值、森林图、Likert 图 geom | ✅ | ⭐ **强烈推荐**（本机已装，见 2.9） |
| **ggstatsplot** | 一体化统计图 | ✅ | ⭕ 已装，可作为「图表建议」模板 |
| **ggpmisc** | 模型方程、R²、P/F/AIC、多重比较标注 | ✅ | ⭕ 价值高但依赖 58 个包 |
| **ggpp** | 标注、inset、密度过滤标签 | ✅ | ⭕ ggpmisc 的前置依赖（42 包） |
| **qqplotr** | Q-Q / P-P 图 | ✅ | ⭕ 依赖 47 包 |
| **ggdensity** | 带边际分布的密度图 | ✅ | ⭕ 依赖 29 包 |
| **gglm** | 模型诊断图 | ✅ | ⭕ 与 L4 回归联动 |
| **lindia** | 回归诊断图 | ✅ | ⭕ 与 L4 联动 |
| **ggfortify** | 统计对象统一 autoplot | ✅ | ❌ 需模型对象，非 data.frame |
| **ggRandomForests** | 随机森林可视化 | ✅ | ❌ 领域专用 |
| **ggQQunif** | 均匀分布 QQ 图（p 值） | ✅ | ⭕ 场景窄 |
| **ggfourfold** | 四格表图 | ✅ | ⭕ 依赖 64 包（偏重） |
| **gglorenz** | 洛伦兹曲线 | ✅ | ⭕ 场景窄 |
| **ggprop.test** | 比例检验 | ❌ 仅 GitHub | ❌ 非 CRAN |

### 2.2 主题与排版（13 个）—— 性价比最高

纯 `theme_*` / `element_*`，接入无需改数据模型，与本项目已有的 ggthemes/ggprism 同构。

| 扩展 | 提供能力 | 建议 |
|---|---|---|
| **ggtext** | 富文本（已接入） | ✅ 已接入 |
| **hrbrthemes** | 出版级排版主题 | ⭐ 推荐（依赖 23 包，最轻） |
| **mdthemes** | markdown 主题 | ❌ 仅 GitHub |
| **ggdark** | 暗色主题 | ⭕ 与现有暗色模式重叠 |
| **ggthemr** | 主题管理器 | ❌ 仅 GitHub |
| **ggtech** | 科技风主题 | ❌ 仅 GitHub |
| **tvthemes** | 电视剧配色主题 | ⭕ 趣味性 |
| **gguapo** | 艺术风格主题 | ❌ 仅 GitHub |
| **ggautothemes** | 自动生成主题 | ❌ 仅 GitHub |
| **geomtextpath** | 沿路径排布文字 | ⭕ 排版增强 |
| **ggfittext** | 文字自适应框内 | ⭕ 依赖 37 包 |
| **ggwordcloud** | 词云 | ⭕ 依赖 37 包 |
| **ggpage** | 书页式文本布局 | ⭕ 场景窄 |

### 2.3 标度与配色（7 个）

| 扩展 | 提供能力 | 建议 |
|---|---|---|
| **ggsci** | 期刊配色（已接入，87 套） | ✅ 已接入 |
| **ggthemes** | 主题+配色（已接入，66 scale） | ✅ 已接入 |
| **ggprism** | Prism 配色（已接入） | ✅ 已接入 |
| **ggnewscale** | 同图多套配色 | ⭐ 推荐（依赖 23 包，与标度面板天然契合） |
| **ggchromatic** | 色彩空间操作 | ❌ 仅 GitHub |
| **ggtintshade** | 明暗/饱和调整 | ⭕ 场景窄 |
| **ggasym** | 非对称矩阵图 | ❌ 仅 GitHub |

### 2.4 轴 / 分面 / 图例（4 个）

| 扩展 | 提供能力 | 建议 |
|---|---|---|
| **ggh4x** | 嵌套分面、多轴、strip 控制 | ⭐ 推荐（依赖 23 包，补强分面面板） |
| **ggbreak** | 坐标轴断轴 | ⭐ 推荐（依赖 41 包，科研刚需） |
| **legendry** | 图例与轴的高级控制 | ⭕ 依赖 23 包 |
| **lemon** | 括号、轴刻度 | ⭕ 依赖 33 包 |

### 2.5 几何补充（15 个）

| 扩展 | 提供能力 | 建议 |
|---|---|---|
| **ggbeeswarm** | 蜂群图 | ✅ 已接入 |
| **ggside** | 边际分布（36 geom） | ✅ 已接入 |
| **ggdist** | 分布与不确定性（半小提琴、雨云图） | ⭐ 推荐（依赖 33 包） |
| **ggridges** | 山脊图 | ⭐ 推荐（依赖 23 包，最轻） |
| **ggforce** | 扇形、椭圆、标注区域 | ⭕ 依赖 32 包 |
| **ggExtra** | 散点边际直方/密度 | ⭕ 依赖 59 包（偏重，ggside 已覆盖） |
| **ggstance** | 水平版 geom | ⭕ 已被 ggplot2 4.0 吸收 |
| **ggbump** | Bump 图 / S 曲线 | ⭕ 场景特定 |
| **ggstar** | 更多点形状 | ⭕ 依赖 64 包（偏重） |
| **ggpattern** | 图案填充（印刷风） | ⭕ 依赖 40 包 |
| **ggpol** | 议会图等 | ❌ 仅 GitHub |
| **ggpie** | 饼图 | ❌ 仅 GitHub |
| **ggpath** | 按数据嵌入图片 | ⭕ 依赖 30 包 |
| **ggbraid** | 编织带 | ❌ 仅 GitHub |
| **oblicubes** | 立方体 3D | ⭕ 场景特定 |

### 2.6 时间序列（8 个）

| 扩展 | 建议 |
|---|---|
| **ggTimeSeries** | ⭕ 日历热图、河流图 |
| **ggseas** | ⭕ 季节调整 |
| **sugrrants** | ⭕ 日历布局 |
| **calendR** | ⭕ 日历图 |
| **ggHoriPlot** | ⭕ 地平线图（依赖 36 包） |
| **gglinedensity** | ⭕ 线密度热图 |
| **ichimoku** | ❌ 金融专用（K 线） |
| **clockplot** | ⭕ 环形时间图 |

### 2.7 空间与地图（23 个）—— 不建议

**共同障碍**：全部需要 `sf` 空间对象或 GeoJSON，而本项目的数据模型是 `data.frame + aes 映射`。接入需要先建立「空间数据导入 + 几何列识别」子系统，成本远超单个扩展。

代表：`tidyterra`、`ggmapinset`、`ggfields`、`ggincerta`、`ggspatial`、`ggOceanMaps`、`geom_sf` 系列等。

### 2.8 明确不兼容的类别

| 类别 | 数量 | 根本原因 |
|---|---|---|
| 空间与地图 | 23 | 需 sf/terra 空间对象 |
| 生物/基因 | 8 | 需序列/系统发育/基因组数据结构 |
| 网络与流程 | 7 | 需 igraph/tidygraph/flow 对象 |
| 生存分析 | 2 | 需 `survival::Surv` 对象 |
| 交互/界面 | 3 | 输出 htmlwidget / shiny app |
| 成品图函数类 | ~30 | `ggboxplot`/`ggbarplot` 这类不接受 aes，与 spec 模型冲突 |

### 2.9 本次新发现的高价值项（之前遗漏）

完整清单暴露了三个之前没看到的候选，均已在本机验证或依赖可接受：

| 扩展 | 为什么值得 | 状态 |
|---|---|---|
| **ggstats** | 提供森林图、Likert 图、p 值 geom，与本项目 L2/L5 直接互补 | **本机已装 1.9MB** |
| **ggh4x** | 嵌套分面、多轴，补强现有分面面板 | 依赖 23 包（最轻档） |
| **ggridges** | 山脊图，多组分布叠加的标准做法 | 依赖 23 包（最轻档） |

## 三、推荐路线（按投入产出比排序）

### 已完成的
- ✅ 第一批：ggpubr / ggsignif / ggbeeswarm / ggtext
- ✅ 扩展管理开关（可启停 + 持久化 + 功能门禁）

### 第二批（建议，约 1 天）

| 扩展 | 理由 | 成本 |
|---|---|---|
| **ggstats** | 已装，森林图/Likert 补强统计模块 | 极低 |
| **ggridges** | 依赖最轻（23 包），山脊图刚需 | 低 |
| **ggnewscale** | 依赖最轻（23 包），标度面板天然契合 | 低 |
| **ggh4x** | 依赖最轻（23 包），分面能力大幅提升 | 低 |

### 第三批（按需）

`ggdist`（分布可视化）、`ggbreak`（断轴）、`ggforce`（几何补充）、`hrbrthemes`（排版）

### 不建议

空间类（23）、生物类（8）、网络类（7）、生存类（2）、交互类（3）、成品图函数类（~30）
—— 合计 **73 个（43%）**，占 170 中的近一半。

## 四、成本与风险

### 依赖闭包（实测）

| 扩展 | 递归依赖数 |
|---|---|
| ggh4x / ggridges / ggnewscale / legendry | **23**（最轻） |
| ggdist | 33 |
| ggbreak | 41 |
| ggstats | 未实测（已装） |
| ggpmisc | 58 |
| ggExtra | 59 |
| ggstar | 64 |
| ggfourfold | 64 |

> 参考：ggpubr 为 85 个（见 [EXTENSIONS.md](EXTENSIONS.md)）。**依赖数是最重要的成本指标**，23 档的包几乎无额外风险。

### 打包体积

已接入的 4 个约 6.6 MB。后续每批建议控制在 5 MB 内；若走 Tauri 打包（见 [TAURI_ASSESSMENT.md](TAURI_ASSESSMENT.md)），只纳入前两批。

### 通用风险

1. **aes 映射层级**：ggsignif 要求 plot 级映射（已实现）；其他包多为图层级即可
2. **包名前缀**：非 ggplot2 函数必须 `pkg::fn`（已实现 `.qualified_fn`）
3. **降级策略**：包缺失时隐藏对应组件，而非报错（扩展管理已支持）

## 五、复现方式

gallery 页面 HTML 里包含全部 170 个卡片，可直接解析：

```powershell
$r = Invoke-WebRequest -Uri 'https://exts.ggplot2.tidyverse.org/gallery/' -UseBasicParsing
$parts = $r.Content -split '<div class="card grid-item"'
# 每段取 card-title / widget-shortdesc / widget-tags / widget-cran
```

（`web_fetch` 工具因正文截断只能看到前 45 条，需改用 HTTP 直取 + HTML 解析。）

## 六、附录：170 个完整清单

见仓库中 `tests/_ext_all.csv`（名称 / 作者 / 标签 / CRAN / 描述 / URL）。
按主类统计：

| 类别 | 数量 |
|---|---|
| 其他/通用 | 69 |
| 空间与地图 | 23 |
| 统计与建模 | 16 |
| 主题与排版 | 13 |
| 生物/基因 | 8 |
| 时间序列 | 8 |
| 网络与流程 | 7 |
| 标度与配色 | 7 |
| 分类数据 | 6 |
| 轴/分面/图例 | 4 |
| 热图 | 3 |
| 交互/界面 | 3 |
| 图片与图标 | 1 |
| 图组合 | 1 |
| 生存分析 | 1 |

> CRAN 状态：145 个在 CRAN，25 个仅 GitHub。
