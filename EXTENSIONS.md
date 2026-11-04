# 扩展包集成评估：ggprism / ggpubr / ggstatsplot

> 评估环境：R 4.6.1、ggplot2 4.0.3、ggprism 1.0.7、ggpubr 1.0.0、ggstatsplot 1.0.0（均已安装）。
> 方法：不只读文档，而是把三个包分别接入项目自身的注册表／代码生成／渲染管线做端到端模拟
> （`ggspec_build_meta()` → 追加扩展条目 → `meta_build_lookup()` → `spec_to_code()` →
> `ggspec_render_preview()`），再测依赖闭包、附着副作用与渲染耗时。复现脚本见文末。

## 结论速览

| 包 | 能为 GUI 增加什么 | 架构契合度 | 依赖代价 | 建议 | 预估工作量 |
|---|---|---|---|---|---|
| **ggprism** | 1 主题（Prism 期刊风）、4 个标度函数（65 套配色，别名去重后 3 项）、4 个 guide（次刻度/轴偏移）、1 个 annotation（轴刻度） | **高**：全是 theme/scale/guide 级组件，正好落在现有扩展点 | +7 个包 | **推荐集成**（可全量） | 0.5–1 人日 |
| **ggpubr** | 5 主题（theme_pubr 系）、16 个「图层型」统计函数（p 值/相关性/检验）、3 个可用 geom（signif/pwc/bracket） | **中**：几何与主题可接入；高层 `ggboxplot()` 等与 spec 模型重复；`stat_*` 是图层构造器而非 `stat=` 参数 | +63 个包（car/lme4/quantreg/forecast…） | **部分推荐**：只做「统计标注层」子集，放弃 ggarrange/ggboxplot | 4–6 人日 |
| **ggstatsplot** | 仅 1 个无参主题；9 个成品图函数（ggbetweenstats 等） | **低**：成品图不是可组合组件，接入等于内嵌第二套绘图系统，图层/标度/主题面板全部失效 | +102 个包（BayesFactor/afex/WRS2…），且强制 ggplot2 ≥ 4.0.2、R ≥ 4.3 | **不推荐作为扩展**；如要，另做「分析图模板」功能 | 2 周+ |

一句话：**ggprism 是「加装饰」，成本低、契合度高；ggpubr 是「加能力」，值得挑子集；ggstatsplot 是「换范式」，不适合塞进现有扩展机制。**

> **实施状态（2026-11-04）**：**ggprism 已按本文 P1 方案集成完毕**（见文末「九、已实施内容」）。
> ggpubr / ggstatsplot 仍为评估结论，未动代码。

## 一、先看本项目现有的扩展机制（决定集成成本）

现有扩展能力是**按包硬编码**的，一共 5 类钩子：

| 扩展点 | 实现位置 | 现状 |
|---|---|---|
| geom | `R/registry_core.R:278` | 只扫 `c("ggrepel","ggthemes")`，零参调用取 `LayerInstance` 拿 aes |
| scale | `R/registry_core.R:397` + `:198` | 只扫 `c("ggsci","ggthemes")`，label 分支按包写死（ggsci/ggthemes 各一段） |
| theme | `R/registry_core.R:402`、`:408` | ggplot2 内置 9 个 + ggthemes 的 `theme_*` 全扫 |
| guide | `R/registry_core.R:355` | **只扫 ggplot2 命名空间**，扩展 guide 无入口 |
| stat | `R/registry_core.R:300` | **只从 ggplot2 命名空间的 `Stat` 对象反推**，扩展 stat 无入口 |
| annotation | `R/registry_core.R:427` | 只扫 ggplot2 的 `annotation_*`；且 `spec_to_code.R:627` 把 annotation 的包写死为 ggplot2 |

两个关键机制（对集成有利）：

1. **代码里自动带 `library(pkg)`**：`meta_build_lookup()`（`R/spec_to_code.R:623`）建立「函数 → 包」映射，
   `.package_lines()`（`:385`）据此在生成代码顶部插入 `library()`。所以扩展**不需要在服务启动时 attach**，
   渲染时 `eval` 到那行 `library()` 才加载 —— 可以保持「装了才可用、没装不报错」。
2. **参数表单是自省的**：`formals()` + `PARAM_WIDGETS` 自动生成控件，包升级改参数时 UI 自动跟随
   （label 与枚举值仍需人工补）。

三个必须知道的**限制**（实测踩到）：

- `R/registry_core.R:157` 的 `.ggspec_theme_args()` 用 `get(fn, envir = asNamespace("ggplot2"))` 取函数，
  **扩展主题会直接报错** `object 'theme_prism' not found`；需要改成支持传包名的版本。
- `R/spec_to_code.R:420` 的 `.ggplot_aes()` 只有在「所有图层 aes 完全一致」时才把映射提升到 `ggplot()`；
  否则映射留在各图层。**ggpubr 的 `stat_compare_means()` 依赖 plot 级 x 映射**，留在图层级就报
  `Can only handle data with groups that are plotted on the x-axis`（下文有实测复现）。
- 前端 `frontend/src/components/ThemePanel.vue:19` 把所有非 ggplot2 主题硬编码显示为「ggthemes 扩展」；
  `GeomChipPicker.vue:58` 的缩略图路径是 `geom-thumbs/<name>.png`，**没有 fallback**，新 geom 必须有图。

## 二、ggprism：推荐，性价比最高

### 它提供什么（`getNamespaceExports()` 实测，共 19 个导出）

- 标度 4 个：`scale_colour_prism` / `scale_color_prism` / `scale_fill_prism` / `scale_shape_prism`
- 主题 1 个：`theme_prism(palette, base_size, base_family, base_fontface, base_line_size,
  base_rect_size, axis_text_angle, border)`，默认 `black_and_white`
- guide 4 个：`guide_prism_minor` / `guide_prism_offset` / `guide_prism_offset_minor` / `guide_prism_bracket`
- annotation 1 个：`annotation_ticks`；外加 p 值工具 `add_pvalue()`（**注意：不是 geom，需要单独的数据框参数**）
- 配色资源：`ggprism_data` 里 **65 套 colour 调色板 / 45 套 fill / 3 套 shape**
  （`floral`、`pearl`、`autumn_leaves`、`prism_light`、`colorblind_safe`…）

### 接入模拟结果

把 4 个标度 + `theme_prism` 注册进 meta 后，走项目自己的管线：

```r
p <- ggplot(df) +
  geom_boxplot(mapping = aes(x = class, y = hwy, fill = class)) +
  scale_fill_prism(palette = "floral") +
  theme_prism(palette = "floral", base_size = 12)
```

渲染成功、0 warning，出图就是 Prism 风格的粗轴线 + 内向刻度 + 期刊配色。
`/api/meta` 的 `scale_fn` 键（`aes|type`）对 4 个函数都解析为 `fill|prism`、`colour|prism`、`shape|prism`，
无冲突；`library(ggprism)` 由 `.package_lines()` 自动带出。

### 集成缺口（都是小活）

1. `R/registry_core.R:198` 的 label 分支只有 ggsci/ggthemes 两段，ggprism 会被错标成「(ggthemes)」→ 加一段。
2. 65 套调色板需要做成 `select` 控件（`pv("palette","select",...,options=...)`，
   `ParamControl.vue:94` 已支持）—— 否则用户得背调色板名字。
3. 4 个 `guide_prism_*` 要进 guide 注册表（现在 guide 只扫 ggplot2）＋ `fn_package` 里补包名。
4. `annotation_ticks` 若要暴露，annotation 扫描要支持扩展包（且 `:627` 的包名写死要改）。
5. **p 值括号**：`add_pvalue(df, ...)` 的第一参数是独立数据框，当前 spec 只允许一个 `df`，
   没有「p 值表」这一概念 → 建议一期不做，引导用户到「高级模式」写代码；
   `geom_bracket` 在 ggprism 里**未导出**，不能直接用。
6. 加载副作用：ggprism attach 后会向 ggplot2 注册 7 个主题元素（`prism.ticks.length*`），
   主题元素总数 160 → 167。这其实是「白送」的可编辑元素，但会让 `/api/meta` 随包安装情况变化，
   测试快照要留容差。

### 代价实测

- 依赖：递归 29 个包，仅比 ggplot2 闭包多 **7 个**（digest、tibble、pillar、magrittr、pkgconfig、utf8）
- 渲染耗时：0.16s（基线）→ 0.21s（主题+标度），几乎无感
- 命名空间加载：0.63s（首次），服务启动时若只做 `requireNamespace` 可忽略

**结论：适合，且可以一次做全。** 对「科研出图」定位是纯增量：配色 + 期刊风主题 + 次刻度 guide。

## 三、ggpubr：部分适合，只做「统计标注层」

### 它提供什么（127 个导出，实测分类）

| 类别 | 数量 | 内容 |
|---|---|---|
| 高层成品图函数 | 20+ | `ggboxplot` / `ggscatter` / `ggbarplot` / `ggviolin` / `ggarrange` / `ggtexttable` … |
| 图层型统计函数（`stat_*`） | 16 | `stat_compare_means`、`stat_cor`、`stat_pvalue_manual`、`stat_pwc`、`stat_regline_equation`、`stat_mean`、`stat_chull`、`stat_bracket` … |
| 可用 geom | 3（+1 伪） | `geom_signif`、`geom_pwc`、`geom_bracket`（零参调用失败）；`geom_exec` 是工具函数不是 geom |
| 主题 | 5 | `theme_pubr`、`theme_pubclean`、`theme_classic2`、`theme_cleveland`、`theme_transparent` |
| 标度 / guide | 0 / 0 | — |

### 关键判断：高层函数不要接

`ggboxplot(df, x, y, add="jitter", palette="jco")` 这类函数与 ggplotGUI 的定位**正面重复**：
GUI 本身就是「点选生成 `geom_boxplot() + theme()` 代码」。把它接进来意味着再造一套
「函数式出图」面板，且这些函数返回的图无法再用图层/标度/主题面板编辑（它的参数是字符串列名）。
更关键的是：生成的代码会变成 `ggboxplot(...)`，与项目「spec → 规范 ggplot2 代码」的唯一事实来源冲突。

`ggarrange()` 也不必接：项目已有 patchwork 拼图（`R/pins.R` + `ggspec_compose_code()`）。

### 值得接的部分：统计标注层

实测把 `geom_signif`、`geom_bracket`、`stat_compare_means` 注册成「图层」后：

| 场景 | 结果 |
|---|---|
| `geom_signif(comparisons=list(c("compact","suv")), map_signif_level=TRUE)` | ✅ 渲染成功，代码规范 |
| `geom_bracket(xmin=1, xmax=2, y.position=44, label="p < 0.05")` | ✅ 渲染成功（但**零参调用失败**，注册表拿不到 aes，需兜底） |
| `stat_compare_means(...)` 作为图层 | ❌ 复现失败：`Can only handle data with groups that are plotted on the x-axis` |

失败根因不是数据，而是**代码生成习惯**：

```r
# 项目生成的形态（图层级映射）：ggpubr 报错
ggplot(df) + geom_boxplot(aes(class, hwy, fill=class)) +
  stat_compare_means(mapping = aes(x=class, y=hwy), comparisons = ...)

# ggpubr 需要的形态（plot 级映射）：正常
ggplot(df, aes(x=class, y=hwy)) + geom_boxplot(aes(fill=class)) +
  stat_compare_means(comparisons = ...)
```

所以集成 ggpubr 的统计层不是「加个 meta 条目」，而是要动三处：

1. **注册表新增「图层函数（layer fn）」概念**：现在的 `stats` 是「`stat=` 参数的可选值」，
   而 ggpubr 的 `stat_*` 是**追加一个图层**（`+ stat_compare_means()`），语义不同，混进 `stats` 会出错。
2. **代码生成**：对图层函数，必要时把共享 x/y 提升到 `ggplot()`（或给这类图层单独走「plot 级映射」分支）。
3. **前端**：新增「统计标注」面板（选函数 + 参数 + `comparisons` 这类列表参数用 fx 表达式输入），
   以及缩略图（`tools/make_geom_thumbs.R` 的 `T` 表里补 3 个条目，否则自动生成占位图）。

### 代价实测（这是主要减分项）

- 递归依赖 **85 个包**，比 ggplot2 闭包多 **63 个**：`car`、`lme4`、`nlme`、`quantreg`、`forecast`、
  `urca`、`rstatix`、`broom`、`dplyr`、`tidyr`、`cowplot`、`gridExtra`…（多数来自 `rstatix`）
- 安装体积/编译时间显著，与 README 宣称的「纯 R，零额外安装」冲突 → 必须保持**可选安装 + 装不上就降级**
- 版本地板：ggpubr 1.0.0 要求 ggplot2 ≥ 3.5.2、R ≥ 4.1.0（与项目现状兼容）
- 渲染耗时：0.20s，可接受

### 建议范围

**做**：`theme_pubr` 系 5 个主题 + `stat_compare_means` / `stat_cor` / `stat_pvalue_manual` / `stat_pwc` +
`geom_signif` / `geom_pwc` / `geom_bracket`。
**不做**：`ggboxplot` 等 20 多个成品图函数、`ggarrange`、`ggtexttable`、`ggexport`。

## 四、ggstatsplot：不适合作为「扩展」

### 它提供什么（22 个导出）

- 9 个成品图：`ggbetweenstats`、`ggscatterstats`、`ggcorrmat`、`ggpiestats`、`ggbarstats`、
  `ggwithinstats`、`gghistostats`、`ggdotplotstats`、`ggcoefstats`
- 主题 1 个：`theme_ggstatsplot()`（**零参数**）
- **geom / scale / stat / guide：0 个**

也就是说：从「扩展注册表」的角度看，它只有一个无参主题可接，等于没有。

### 实测效果（很好看，但不可组合）

`ggbetweenstats(mpg, x=class, y=hwy)` 一张图里同时给出方差分析结果、效应量、贝叶斯因子、
成对比较、样本量、离群点标记 —— 这恰恰证明它是**成品图**：图的每个部分都由函数参数控制，
而不是由 `geom_*` 图层堆叠。接入 GUI 后：

- 图层面板：无图层可编辑（整图是一次函数调用）
- 标度/主题面板：部分参数能映射，但大部分样式由内部主题决定，改了会与函数内置布局打架
- 代码面板：生成的是 `ggbetweenstats(...)`，不再是「规范可复制的 ggplot2 代码」，违背项目核心设计
- 与现有 patchwork 拼图勉强能拼（它返回 ggplot 对象），但拼完不能再改内部

### 代价实测

- 递归依赖 **124 个包**，多出 **102 个**：`BayesFactor`、`afex`、`WRS2`、`PMCMRplus`、`effectsize`、
  `performance`、`parameters`、`insight`、`paletteer`、`ggside`、`correlation`、`statsExpressions`…
  （含需编译与 `gmp`/`Rmpfr` 的包，安装成本和对 Windows 工具链的依赖都不低）
- **强制 ggplot2 ≥ 4.0.2**，而项目宣称支持 ggplot2 ≥ 3.5；**R ≥ 4.3**，项目写的是 ≥ 4.2
- 渲染耗时：`ggbetweenstats` 约 **1.2s/图**（`ggscatterstats` 0.36s），是普通图的 3–8 倍，
  与「实时自动渲染」体验有冲突（单线程 httpuv 会整段阻塞）
- 加载后由 `ggside` 注册额外主题元素，进一步扰动注册表快照

### 如果真的很想要

把它当成**独立功能**而不是扩展包：新增「分析图模板」面板 —— 选模板（9 个）、选数据列、少量统计参数，
生成 `ggbetweenstats(...)` 代码并渲染，产物**不进入** spec，也不参与图层编辑；同时单独标注
「需要 ggstatsplot 且 ggplot2 ≥ 4.0.2」。这是一个 2 周量级的新功能，与本次「扩展集成」不是一件事。

## 五、横向对比

| 维度 | ggprism | ggpubr | ggstatsplot |
|---|---|---|---|
| 可接入的组件数 | 1 主题 + 3 标度（去重后）+ 4 guide + 1 annotation | 5 主题 + 3 geom + 16 图层函数 | 1 无参主题 |
| 依赖增量（相对 ggplot2） | **+7** | +63 | +102 |
| 版本地板 | ggplot2 ≥ 3.4 | ggplot2 ≥ 3.5.2 / R ≥ 4.1 | **ggplot2 ≥ 4.0.2 / R ≥ 4.3** |
| 渲染开销 | +0.05s | +0.04s | +0.2～1.0s |
| 架构冲突 | 无 | 中（图层函数 + plot 级 aes 约定） | **高**（成品图 vs 声明式 spec） |
| 需要改前端 | 主题分组标签 1 处 | 新增统计标注面板 | 需新增整套模板面板 |
| 与现有功能重叠 | 低 | 中（成品图/拼图） | 低，但范式冲突 |
| 维护负担 | 低（枚举值人工同步） | 中（16 个函数的参数语义） | 高 |

## 六、实施建议（分阶段）

### P1：ggprism（0.5–1 人日）

1. `R/registry_core.R`
   - 把 `"ggprism"` 加进 scale 扫描（`:397`），并在 `:207` 的 label 分支加一段（`Prism 配色 · <palette>`）。
   - 主题：新增「按包扫 `theme_*`」的通用函数（替掉 `:408` 的 ggthemes 专用分支），`theme_prism` 走它。
   - guide：把 guide 扫描从 ggplot2 命名空间扩展到扩展包（`:355`），补 `fn_package`。
   - annotation：如需 `annotation_ticks`，同法扩展 `:427` 并修 `spec_to_code.R:627` 的包名写死。
2. `R/registry_meta.R`：补 `GGPRISM_PALETTES`（65 个名字 → 中文/英文标签）与 `theme_prism` 的 palette 枚举。
3. `frontend/src/components/ThemePanel.vue:19`：分组标签按 `package` 显示（ggprism / ggpubr / ggthemes）。
4. 测试：`tests/test_extension_prism.R` —— 断言 4 个标度可生成代码、`theme_prism()` 参数进代码、渲染成功；
   无 ggprism 时 `/api/meta` 仍正常（降级路径）。

### P2：ggpubr 子集（4–6 人日）

1. 注册表新增 `layerFns`（或 `statLayers`）类别：`fn`、`label`、`group`、`params`、`requiredArgs`、`package`；
   前端在「注释」旁新增「统计标注」面板。
2. `spec_to_code.R`：`spec$layers` 支持 `kind = "fn"` 的条目（或新增 `spec$statLayers`），
   并解决 plot 级 aes 提升问题（对含 `stat_compare_means` 的图，把共享 x/y 提到 `ggplot()`）。
3. `geom_bracket` 这类**零参调用失败**的 geom：在 `.ggspec_scan_pkg_geoms()` 里对失败项用
   `formals()` 推导 required aes（或维护白名单补 `aes = list(required = c("xmin","xmax","y.position"))`）。
4. 缩略图：`tools/make_geom_thumbs.R` 的 `T` 表补 `signif` / `pwc` / `bracket`；
   顺带在 UI 给缺失缩略图加 fallback（现在会显示破图）。
5. 依赖策略：继续 `requireNamespace()` 可选加载；README 增加「若要 p 值标注，install.packages('ggpubr')」。

### P3：ggstatsplot（不排期）

若产品上确实需要，另立「分析图模板」需求，独立于扩展注册表；同时明确版本地板
（ggplot2 ≥ 4.0.2、R ≥ 4.3）与「每图 1s+」的性能预期。

## 七、顺带的架构建议：把「扩展清单」数据化

现在是 5 处 `for (pkg in c(...))` + 每个包一段 if/else label。每加一个包改 4–6 个文件，
再加 3 个包就会失控。建议抽一份清单：

```r
EXT_PKGS <- list(
  ggprism = list(
    package = "ggprism",
    scales  = list(parse = "aes_prefix", label = "Prism · %s", palette = "ggprism_data$colour_palettes"),
    themes  = list(scan = TRUE, label = "Prism"),
    guides  = list(scan = TRUE),
    annotations = list(scan = TRUE)
  ),
  ggpubr = list(
    package = "ggpubr",
    geoms   = list(names = c("signif", "pwc", "bracket")),
    layerFns = list(scan = "^stat_", exclude = c("stat_anova_test", "stat_friedman_test")),
    themes  = list(scan = TRUE)
  )
)
```

`ggspec_build_meta()` 遍历这份清单生成条目，label / 枚举 / 白名单都放数据里。
以后接 ggsci、ggthemes、ggprism、ggpubr 乃至 ggtext 都是「加一条配置」，而不是「改 6 个文件」。

## 八、复现与证据

脚本已放进仓库，从项目根目录直接跑（`Rscript tools/extension-eval/xxx.R`）：

- `introspect.R` —— 导出分类、DESCRIPTION 依赖、`/api/meta` 扫描模拟
- `integration_sim.R` —— 把 ggprism/ggpubr/ggstatsplot 条目注入 meta，跑 `spec_to_code()` + 渲染
- `deps.R` / `check2.R` —— 依赖闭包、附着冲突、主题元素副作用
- `smoke2.R` —— 三个包在 ggplot2 4.0.3 下的出图冒烟
- `check4.R` / `check5.R` —— 复现 `stat_compare_means` 的 plot 级 aes 依赖
- `timing.R` / `palettes.R` —— 渲染耗时、ggprism 调色板清单

关键实测数字（逐包累加，`/api/meta` 计数）：

| 指标 | 基线 | +ggprism | +ggpubr | +ggstatsplot |
|---|---|---|---|---|
| geoms | 58 | 58 | 58 + 3（另 +1 图层函数） | 61 |
| scales | 285 | 288（color 别名去重后） | 289 | 289 |
| themes | 32 | 33 | 38 | 39 |
| 主题元素 | 160 | **167**（ggprism 注册 `prism.ticks.length*`） | 167 | 167 |
| 递归依赖 | 22 | 29 | 85 | 124 |
| 单图渲染（900×520） | 0.16s | 0.21s | 0.20s | 0.36–1.20s |

> 注意：主题元素 160 → 167 是**加载副作用**，与是否在 UI 中启用无关；
> 若测试里对 `/api/meta` 做快照，需要允许该差异（或把 prism 元素显式纳入元数据）。

## 九、已实施内容（ggprism，2026-11-04）

### 9.1 改动清单

| 文件 | 改动 |
|---|---|
| `R/registry_core.R` | 新增 `.ggprism_palette_names()`（从 `ggprism_data` 读 65/45/3 套调色板，**不硬编码**）、`.ggprism_theme_args()`、`.ggspec_scan_pkg_themes()` / `_guides()` / `_annotations()` 三个通用扫描器；`.ggspec_theme_args()` 与 `.ggspec_formals_params()` 增加 `pkg` 参数；标度扫描加入 `ggprism` 分支；guide / annotation / theme 扫描接入；`ANNOTATION_META` 增 `ticks`；`extensions.ggprism` |
| `R/registry_meta.R` | `GGPRISM_THEME_LABELS`；4 个 prism guide 的中文标签；`prism.ticks.length*` 的中文标签与 unit 控件；`GUIDE_PARAM_WIDGETS` 增 `check.overlap` / `n.dodge` / `width` / `outside` |
| `R/spec_to_code.R` | `meta_build_lookup()` 的「函数→包」映射改为尊重 `package` 字段（原先 guide / annotation 一律写死 ggplot2），使 `library(ggprism)` 能自动出现在生成代码里 |
| `frontend/src/components/ThemePanel.vue` | 扩展主题按包分组（ggthemes / ggprism / …），不再统一显示为「ggthemes 扩展」 |
| `run.R` | 预加载列表加入 `ggprism`（缺失自动跳过） |
| `tests/test_extension_prism.R` | 新增：3 标度（别名去重）+ 调色板枚举、theme_prism 控件、4 guide、annotation_ticks、代码生成、3 个渲染用例；未安装时走降级断言 |

### 9.2 实测结果

- `/api/meta`：`58 geoms / 30 stats / 288 scales / 33 themes / 16 guides / 7 annotations / 167 themeElements`
- prism 标度：`fill|prism`（45 套）、`colour|prism`（65 套，`scale_color_*` 别名已去重）、`shape|prism`（3 套）
- `theme_prism`：8 个参数全部有合适控件，`palette` 为 65 项下拉
- prism guide：`prism_minor` / `prism_offset` / `prism_offset_minor` / `prism_bracket`
- 生成代码示例：

```r
library(ggprism)
p <- ggplot(df, aes(x = dose, y = len, fill = supp)) +
  geom_boxplot() +
  scale_fill_prism(palette = "floral") +
  guides(x = guide_prism_minor()) +
  theme_prism(palette = "floral", base_size = 12)
```

- 回归：`test_specs` 29/29、`test_codegen_exec` 9/9、`test_api_guard` 全过、`test_extension_prism` 3/3 渲染

### 9.3 有意留下的边界

1. **`annotation_ticks` 的 `tick.length` / `minor.length` 未暴露**：这两个参数需要 `unit()`，
   而参数面板目前只支持标量 / 表达式，传裸数字会渲染失败。默认值 4.8pt / 2.4pt 保留，
   需要自定义时走「高级模式」。
2. **prism guide 基于 ggplot2 的旧 S3 guide 系统**：ggplot2 4.0.3 仍可用，但会打印
   `The S3 guide system was deprecated in ggplot2 3.5.0` 警告。若未来 ggplot2 移除兼容层，
   这几个 guide 会失效 —— 属于上游风险，不影响标度与主题。
3. **prism guide 只对 x / y 轴有意义**（`guide_prism_bracket` 给 fill 会报 `guide_old() cannot be used for fill`）。
   指南面板允许任意组合，这一点与 ggplot2 自带 guide 的约束一致，未额外拦截。
4. **`add_pvalue()` 未接入**：它需要独立数据框，当前 spec 只有单个 `df`；构成 P2「统计标注」需求的一部分。
5. 标度下拉按来源包分组（ggplot2 / ggsci / ggprism / ggthemes 动态生成）；`scale_color_prism`
   与其 `scale_colour_prism` 是别名，扫描时已去重。

### 9.4 下一步

- 若继续 P2（ggpubr 统计标注层），建议先把第 7 节的 `EXT_PKGS` 清单化落地，否则每加一个包仍要改 4–6 处。
