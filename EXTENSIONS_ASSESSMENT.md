# ggplot2 扩展引入评估

> 评估对象：<https://exts.ggplot2.tidyverse.org/gallery/>（170 个已注册扩展）
> 评估日期：2026-11-08
> 结论：**当前架构已具备成熟接入条件，建议分 3 批引入 8–10 个，L1 批次几乎零成本。**
>
> 配套文档：[EXTENSIONS.md](EXTENSIONS.md) 对 ggprism / ggpubr / ggstatsplot 做过逐包深度分析与依赖闭包测算，
> 本文侧重**全量候选筛选**与**接入技术约束**，两者互补。

## 一、结论摘要

本项目已有 **4 个扩展**在用（ggrepel / ggsci / ggthemes / ggprism），且注册表自省机制已验证可自动发现扩展能力。实测发现存在**两个技术障碍**，都是代码生成层面的小改动（详见第二节）：① 扩展函数需加包名前缀；② ggsignif 要求 aes 提升到 plot 级。

| 优先级 | 扩展 | 价值 | 接入成本 | 建议 |
|---|---|---|---|---|
| **P0** | ggpubr | 统计标注（stat_compare_means） | 极低（已装） | ✅ 立即 |
| **P0** | ggsignif | 显著性括号 | 极低（已装） | ✅ 立即 |
| **P0** | ggbeeswarm | 蜂群散点（避免点重叠） | 极低（已装） | ✅ 立即 |
| **P0** | ggtext | 富文本标签（markdown/HTML 样式） | 极低（已装） | ✅ 立即 |
| **P1** | ggside | 边际分布（36 个 geom + 9 主题） | 低（已装） | ✅ 第二批 |
| **P1** | ggstatsplot | 一体化统计图 | 低（已装） | ✅ 第二批 |
| **P1** | ggExtra | 散点边际直方/密度 | 低（需装 0.3MB） | ✅ 第二批 |
| **P2** | ggdist | 分布与不确定性可视化 | 中（需装） | ⭕ 按需 |
| **P2** | ggforce | 补充 geom（扇形、椭圆、标签） | 中（需装） | ⭕ 按需 |
| **P2** | ggridges | 山脊图 | 中（需装） | ⭕ 按需 |
| **P3** | ggraph / ggtree / ggnetwork | 网络/树/层次结构 | 高（数据结构不同） | ❌ 不建议 |
| **P3** | gganimate / ggiraph | 动画/交互 | 高（输出形态不同） | ❌ 不建议 |

## 二、可行性实测（关键发现）

### 2.1 好消息：自省能自动发现扩展能力

注册表的 `.ggspec_scan_pkg_*` 无需改动即可扫描任意扩展包：

| 扩展 | 发现 geom | 发现 scale | 发现 theme |
|---|---|---|---|
| ggrepel | 3 | 0 | 0 |
| ggthemes | 2 | 66 | 22 |
| ggsci | 0 | 87 | 0 |
| ggprism | 0 | 3 | 1 |
| **ggpubr** | **4** | 0 | 5 |
| **ggbeeswarm** | **2** | 0 | 0 |
| **ggtext** | **2** | 0 | 0 |
| **ggside** | **36** | 0 | **9** |
| ggstatsplot | 0 | 0 | 1 |
| cowplot | 0 | 0 | 7 |

### 2.2 拦路石之一：裸函数名

实测（这是本次评估最重要的发现之一）：

```
裸函数名（当前行为）：
  geom_beeswarm()          → FAIL: 没有"geom_beeswarm"这个函数
  geom_richtext()          → FAIL: 没有"geom_richtext"这个函数

加包前缀后：
  ggbeeswarm::geom_beeswarm()  → OK
  ggtext::geom_richtext()      → OK
  ggpubr::stat_compare_means() → OK
  ggside::geom_xsidedensity()  → OK

library() 加载后裸名同样可用：
  library(ggbeeswarm); geom_beeswarm()  → OK
```

**根因**：[R/spec_to_code.R](R/spec_to_code.R) 的 `.layer_call()` 只输出 `gmeta$fn`（如 `geom_beeswarm`），而该函数不在 ggplot2 命名空间里。注册表其实已经记录了 `package` 字段，只是代码生成没用上。

**修复方案（二选一，都只需改一行）**：
- 方案 A（推荐）：`.layer_call()` 里对非 ggplot2 的函数加 `pkg::` 前缀
- 方案 B：在 `.package_lines()` 里已生成的 `library(pkg)` 基础上，保证渲染环境的 library 调用先执行

> 实测方案 A/B 都可行。方案 A 生成的代码更明确（`ggbeeswarm::geom_beeswarm()`），且不依赖 library 副作用。

### 2.3 拦路石之二：aes 必须在 plot 级（仅 ggsignif 严格）

这一条与 [EXTENSIONS.md](EXTENSIONS.md) 的既有结论相互印证并做了细化。实测三种扩展对映射层级的要求**并不相同**：

| 扩展 | 图层级映射 `ggplot(df) + geom_x(aes(...))` | plot 级映射 `ggplot(df, aes(...)) + geom_x()` |
|---|---|---|
| **ggsignif** | ❌ `Can only handle data with groups that are plotted on the x-axis` | ✅ OK |
| ggpubr (`stat_compare_means`) | ✅ OK | ✅ OK |
| ggbeeswarm | ✅ OK | ✅ OK |
| ggtext (`geom_richtext`) | ✅ OK | ✅ OK |

**结论**：
- 只有 **ggsignif** 严格要求 x 轴分组来自 `ggplot()` 级映射
- 好消息是本项目已有 `.ggplot_aes()` 提升逻辑：**单图层时会自动把 aes 提升到 `ggplot()`**（实测确认），所以最常见的「箱线图 + 显著性」场景天然满足
- 但「多层且 aes 不同」时不会提升 → ggsignif 会失败。因此接入时应对**含 ggsignif 图层的 spec 强制走 plot 级映射分支**（或提示用户）

> 注：L3 的图上标注目前是通过 `sigMarks` 生成 `ggsignif::geom_signif(comparisons=...)`，走的正是这条路径，已实测可用。

### 2.4 无命名冲突

| 扩展 | 新增 geom | 与现有 58 个重名 |
|---|---|---|
| ggpubr | 4 | 无 |
| ggbeeswarm | 2 | 无 |
| ggtext | 2 | 无 |
| ggside | 36 | 无 |

### 2.5 全部候选都能正常渲染

已装且实测出图成功：ggpubr、ggsignif、ggstatsplot、ggcorrplot、ggtext、ggbeeswarm、ggside、survminer、cowplot（9/9 通过）。

## 三、分批次建议

### 第一批（P0，零安装成本，约 0.5 天）

这 4 个包**本机已装**，只差代码生成的 `pkg::` 前缀修复。

| 扩展 | 提供能力 | 对项目的具体价值 |
|---|---|---|
| **ggpubr** | `stat_compare_means` / `stat_pvalue_manual` / `stat_cor` | 直接补强 L3 图上标注（已复用其 `stat_pvalue_manual`） |
| **ggsignif** | `geom_signif` 括号 | L3 已在用；正式纳入图层选择器 |
| **ggbeeswarm** | `geom_beeswarm` / `geom_quasirandom` | 解决小样本散点的严重重叠，是箱线图/小提琴图的标配补充 |
| **ggtext** | `geom_richtext` / `geom_textbox` | 图上文字支持 **加粗/斜体/颜色/上下标**，期刊图注刚需 |

**改动清单**：
1. `R/spec_to_code.R`：`.layer_call()` 对非 ggplot2 包函数加 `pkg::` 前缀（1 行）
2. `R/spec_to_code.R`：含 ggsignif 图层的 spec 强制走 plot 级映射（见 2.3）
3. `R/registry_core.R`：扩展 geom 扫描的包列表加入这 4 个
4. `R/registry_meta.R`：给新 geom 补中文标签与分组
5. `run.R`：预加载列表补充

> 说明：ggpubr / ggsignif 的深度分析（依赖闭包 85 个包、`stat_*` 属于「图层函数」而非 `stat=` 可选值等）见既有文档 [EXTENSIONS.md](EXTENSIONS.md)，此处不重复。

### 第二批（P1，约 1 天）

| 扩展 | 提供能力 | 价值 |
|---|---|---|
| **ggside** | 36 个边际 geom + 9 主题 | 散点图边际分布（比 ggExtra 更灵活），纳入图层即可用 |
| **ggstatsplot** | `ggbetweenstats` 等一体化统计图 | 可作为「图表建议」里的一键模板 |
| **ggExtra** | `ggMarginal` | 需新装（0.3MB），边际直方/箱线，轻量替代 |

**注意**：ggExtra 的 `ggMarginal()` 是**包装函数**（返回 grob 而非图层），与本项目「图层组合」模型不符，需要作为特殊函数处理或跳过。建议优先 ggside。

### 第三批（P2，按需）

| 扩展 | 适合场景 | 成本 |
|---|---|---|
| **ggdist** | 分布/不确定性（半小提琴、雨云图） | 中：几何体参数复杂 |
| **ggforce** | 扇形、椭圆、标注区域 | 中：8+ geom |
| **ggridges** | 山脊图（多组分布叠加） | 低–中 |
| **ggbreak** | 坐标轴断轴 | 中：影响坐标系统 |
| **ggnewscale** | 同一图多套配色 | 中：与现有标度面板冲突 |
| **ggh4x** | 嵌套分面、多种轴 | 中：与 facet 面板耦合 |

### 不建议引入（P3）

| 扩展 | 原因 |
|---|---|
| **ggraph / ggtree / ggnetwork** | 需要 igraph/tidygraph/phylo 等**独立数据结构**，与本项目「data.frame + aes 映射」模型不兼容 |
| **gganimate** | 输出动画（gif/mp4），与当前 PNG/SVG/PDF 静态渲染管线不同 |
| **ggiraph** | 输出 htmlwidget，交互层与现有 plotly 方案重复 |
| **ggrepel 的 marquee_repel** | 依赖 `marquee` 包（未装），且中文支持待验证 |
| **survminer** | 需要 `survival::Surv` 对象，不是普通 data.frame |
| **ggpmisc** | 价值高但依赖 `ggpp`/`ggspectra` 整条链，体积大 |
| **ggVennDiagram / ggalluvial / ggmosaic** | 需要特定数据形态（集合/流向/列联），宜作为独立功能而非通用图层 |

## 四、成本估算

| 工作项 | 工时 |
|---|---|
| 第一批（4 个包，含 `pkg::` 修复） | **0.5 天** |
| 第二批（3 个包 + 面板适配） | 1 天 |
| 第三批（按需，每个） | 0.5–1 天 |
| 扩展管理 UI（启用/禁用扩展） | 0.5 天 |
| 测试（每个扩展 5–10 项断言） | 0.3 天/批 |

**第一批 + 测试 ≈ 0.8 天**，投入产出比最高。

## 五、需要注意的问题

### 5.1 打包体积

| 扩展 | 体积 |
|---|---|
| ggpubr | 2.3 MB |
| ggstatsplot | 3.7 MB |
| ggside | 3.7 MB |
| survminer | 5.9 MB |
| ggtext / ggbeeswarm | 1.5 / 1.8 MB |

第一批 4 个包合计约 **6.6 MB**。相对 R 运行时（139 MB）影响很小；但若走 Tauri 打包（见 [TAURI_ASSESSMENT.md](TAURI_ASSESSMENT.md)），建议只纳入第一批。

### 5.2 依赖链风险

`ggstatsplot` 依赖 `ggpubr` → `ggsignif` → `rstatix` → `effectsize` 等十余个包，安装体积实际约 20 MB。若只需「图上显著性」，用 ggpubr/ggsignif 即可，不必引入 ggstatsplot。

### 5.3 包缺失时的降级

现有代码已具备降级模式（如 L3 标注在 ggsignif 缺失时退回 `annotate("text")`）。接入新扩展时应沿用此模式：**扩展不可用时隐藏对应 geom，而非报错**。

### 5.4 与现有功能的边界

- **ggpubr / ggsignif** 与 L3「图上标注」功能重叠 → 应作为 L3 的**底层实现**，而非并列的第二套入口
- **ggstatsplot** 与 L2「统计检验」重叠 → 作为「图表建议」的模板，不新增检验入口
- **ggbeeswarm** 与现有 `geom_jitter` 近义 → 在中文标签里说明差异（抖动是随机偏移，蜂群是算法避让）

## 六、推荐执行路径

```
第 1 步（0.5 天）修 pkg:: 前缀 + 接入第一批 4 个包
  → 立即可见效果：蜂群图、富文本标签、显著性标注全部可用

第 2 步（0.3 天）扩展管理开关
  → 注册表只扫描「已启用」的扩展，避免装了未用也出现在列表里

第 3 步（1 天）第二批：ggside（边际分布）
  → 与现有 ggExtra 场景二选一，优先 ggside

第 4 步（按需）P2 逐个评估
  → 每个扩展单独评估「数据形态是否兼容 + 面板是否需要新增控件」
```

## 七、附：完整候选清单（按 gallery 标签）

| 类别 | 扩展 |
|---|---|
| 已集成 | ggrepel, ggsci, ggthemes, ggprism |
| 统计标注 | ggpubr, ggsignif, ggstatsplot, ggpmisc, ggQQunif |
| 分布可视化 | ggdist, ggridges, ggbeeswarm, ggExtra, ggside |
| 文本标签 | ggtext, ggfittext, ggwordcloud, ggpage |
| 几何补充 | ggforce, ggalt, ggstance, ggpattern, ggimage, ggfx |
| 布局组合 | cowplot, gridExtra, egg, patchwork（已集） |
| 坐标轴 | ggbreak, ggh4x, ggnewscale |
| 关系图 | ggraph, ggnetwork, ggtree, ggVennDiagram, ggsankey |
| 特殊图表 | ggalluvial, ggmosaic, ggupset, ggbump, ggradar, ggTimeSeries |
| 交互动画 | gganimate, ggiraph, ggedit |
| 领域专用 | survminer, gganatogram, ggspectra, plotROC, ggpca |

> 说明：gallery 页面为 JS 动态渲染，web_fetch 只能取到前 45 个条目，其余基于 CRAN 索引与本地实测补充。表中标注「已装」的均经实际渲染验证。
