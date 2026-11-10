# Glyph - 扩展包注册与启用开关
# 设计：
#   1) 单一事实来源：所有支持的扩展在这里登记（名称/类型/说明/依赖包）
#   2) 开关持久化：启停写入 extensions.json，重启后保持
#   3) 扫描尊重开关：注册表构建时只扫描「已安装且已启用」的扩展
#   4) 缺失可诊断：未安装的扩展也出现在列表里，标注「未安装」供用户参考

## ---- 扩展清单 ---------------------------------------------------------------
# kind: 该扩展提供什么组件（决定它被接入到注册表的哪个环节）
#   geom / scale / theme / guide / annotation
# 可多选；顺序即扫描顺序。
GGSPEC_EXTENSIONS <- list(
  list(id = "ggpubr", label = "ggpubr 统计标注", kind = c("geom", "theme"),
       desc = "统计检验标注图层（显著性括号、p 值、成对比较）+ 出版级主题",
       pkg = "ggpubr"),
  list(id = "ggbeeswarm", label = "ggbeeswarm 蜂群图", kind = c("geom"),
       desc = "用算法错开重叠的点，小样本散点的标准替代方案",
       pkg = "ggbeeswarm"),
  list(id = "ggtext", label = "ggtext 富文本", kind = c("geom"),
       desc = "图上文字支持加粗/斜体/颜色/上下标（markdown 与 HTML 片段）",
       pkg = "ggtext"),
  list(id = "ggside", label = "ggside 边际分布", kind = c("geom", "theme"),
       desc = "在坐标轴外侧追加边际直方图/密度/箱线图等 36 种图层",
       pkg = "ggside"),
  # ---- 第二批 ----
  list(id = "ggstats", label = "ggstats 统计图", kind = c("geom", "scale"),
       desc = "比例条、Likert 图、金字塔图、`stripped` 分组背景等统计图形",
       pkg = "ggstats"),
  list(id = "ggridges", label = "ggridges 山脊图", kind = c("geom", "scale", "theme"),
       desc = "山脊图（多组分布叠加）与配套的循环配色标度",
       pkg = "ggridges"),
  list(id = "ggh4x", label = "ggh4x 分面增强", kind = c("geom", "scale"),
       desc = "嵌套分面、多轴、截断轴、图例扩展与点路径等几何",
       pkg = "ggh4x"),
  list(id = "ggnewscale", label = "ggnewscale 多重标度", kind = c("layerfn"),
       desc = "在同一张图里叠加多套 fill/colour 标度（new_scale_* 系列）",
       pkg = "ggnewscale"),
  # ---- 第三批 ----
  list(id = "ggdist", label = "ggdist 分布可视化", kind = c("geom", "scale", "theme"),
       desc = "半小提琴、点区间、雨云图等分布与不确定性可视化（11 geom + 6 ramp 标度）",
       pkg = "ggdist"),
  list(id = "ggforce", label = "ggforce 几何扩展", kind = c("geom", "scale", "theme"),
       desc = "圆形/椭圆/弧线/泰森多边形/平行集等 40 种几何与 zoom 分面",
       pkg = "ggforce"),
  list(id = "ggbreak", label = "ggbreak 断轴", kind = c("scale"),
       desc = "坐标轴打断（scale_x_break / scale_y_break），大跨度数据常用",
       pkg = "ggbreak"),
  list(id = "hrbrthemes", label = "hrbrthemes 排版主题", kind = c("scale", "theme"),
       desc = "出版级排版主题（ipsum/modern_rc 系列）与配色（32 scale + 9 主题）",
       pkg = "hrbrthemes"),
  list(id = "ggrepel", label = "ggrepel 防重叠标签", kind = c("geom"),
       desc = "自动避让的文本与标签",
       pkg = "ggrepel"),
  # ---- 第四批（科研绘图 A 级：轻依赖 + 高频）----
  # （gghalves 已从 CRAN 归档、R 4.6 不可用，移出清单；雨云可由 ggrain/ggdist 覆盖）
  list(id = "ggrain", label = "ggrain 雨云图", kind = c("geom"),
       desc = "雨云图（半小提琴 + 抖动点 + 箱线合一），多组分布对比的科研标配",
       pkg = "ggrain"),
  list(id = "ggpointdensity", label = "ggpointdensity 点密度", kind = c("geom"),
       desc = "散点与二维密度合体，大数据散点不再互相糊成一团",
       pkg = "ggpointdensity"),
  list(id = "ggrastr", label = "ggrastr 层栅格化", kind = c("geom"),
       desc = "把指定图层（大点阵）转成位图、其余保持矢量——导出 PDF 体积与期刊要求兼得",
       pkg = "ggrastr"),
  list(id = "directlabels", label = "directlabels 直接标注", kind = c("geom"),
       desc = "把组名直接标在分组线上/点簇旁，替代图例（geom_dl）",
       pkg = "directlabels"),
  list(id = "ggthemes", label = "ggthemes 额外主题", kind = c("geom", "scale", "theme"),
       desc = "经济学人/Tufte 等经典主题与配色",
       pkg = "ggthemes"),
  list(id = "ggsci", label = "ggsci 学术配色", kind = c("scale"),
       desc = "Nature/Lancet/JAMA 等期刊配色方案（87 套）",
       pkg = "ggsci"),
  list(id = "ggprism", label = "ggprism Prism 风格", kind = c("scale", "theme", "guide", "annotation"),
       desc = "GraphPad Prism 期刊风主题、配色与轴样式",
       pkg = "ggprism"),
  # 仅影响导出的扩展（不提供 ggplot 组件，但需要在界面上可见）
  list(id = "patchwork", label = "patchwork 拼图", kind = c(),
       desc = "多图组合（图库/拼图面板使用）", pkg = "patchwork"),
  list(id = "plotly", label = "plotly 交互预览", kind = c(),
       desc = "把静态图转换为可缩放、可悬停的交互图", pkg = "plotly")
)

.ext_by_id <- function(id) {
  for (e in GGSPEC_EXTENSIONS) if (identical(e$id, id)) return(e)
  NULL
}

## ---- 安装状态 ---------------------------------------------------------------
.ext_installed <- function(pkg) {
  isTRUE(tryCatch(requireNamespace(pkg, quietly = TRUE), error = function(e) FALSE))
}

## ---- 运行期依赖 -------------------------------------------------------------
# 有些包 requireNamespace() 能通过，但真正用起来还缺运行期依赖
# （典型：ggtext 的 gridtext 渲染依赖 stringi）。这里显式登记，
# 供 UI 标注「缺依赖」，避免误报「已安装、可用」。
EXT_RUNTIME_DEPS <- list(
  ggtext = c("stringi")
)

.ext_missing_deps <- function(pkg) {
  need <- EXT_RUNTIME_DEPS[[pkg]] %||% character(0)
  if (!length(need)) return(character(0))
  need[!vapply(need, function(p) requireNamespace(p, quietly = TRUE), logical(1))]
}

## ---- 启停状态持久化 ---------------------------------------------------------
# 文件格式：{"disabled": ["ggsci", ...]}  —— 默认全部启用
# 只记录「关闭」的项，这样新增扩展默认可用，不需迁移配置。
GGSPEC_EXT_STATE <- new.env(parent = emptyenv())
GGSPEC_EXT_STATE$file <- NULL
GGSPEC_EXT_STATE$disabled <- character(0)

ext_state_bind <- function(file) {
  GGSPEC_EXT_STATE$file <- file
  GGSPEC_EXT_STATE$disabled <- character(0)
  if (!is.null(file) && file.exists(file)) {
    obj <- tryCatch(jsonlite::fromJSON(file, simplifyVector = FALSE), error = function(e) NULL)
    if (is.list(obj) && length(obj$disabled)) {
      GGSPEC_EXT_STATE$disabled <- as.character(unlist(obj$disabled))
    }
  }
  invisible(GGSPEC_EXT_STATE$disabled)
}

ext_state_save <- function() {
  f <- GGSPEC_EXT_STATE$file
  if (is.null(f)) return(invisible(FALSE))
  txt <- jsonlite::toJSON(list(disabled = as.list(GGSPEC_EXT_STATE$disabled)),
                          auto_unbox = TRUE, pretty = TRUE)
  write_file_atomic(txt, f)
}

ext_is_enabled <- function(id) {
  !(as.character(id) %in% GGSPEC_EXT_STATE$disabled)
}

ext_set_enabled <- function(id, on) {
  id <- as.character(id)
  if (is.null(.ext_by_id(id))) stop(sprintf("未知扩展: %s", id))
  d <- setdiff(GGSPEC_EXT_STATE$disabled, id)
  if (!isTRUE(on)) d <- c(d, id)
  GGSPEC_EXT_STATE$disabled <- unique(d)
  ext_state_save()
  invisible(ext_is_enabled(id))
}

## ---- 供扫描使用的「已启用扩展」列表 -----------------------------------------
# 返回已安装且已启用的扩展 id
ext_active_ids <- function() {
  ids <- character(0)
  for (e in GGSPEC_EXTENSIONS) {
    if (!.ext_installed(e$pkg)) next
    if (!ext_is_enabled(e$id)) next
    ids <- c(ids, e$id)
  }
  ids
}

# 按组件类型筛选，供各扫描环节调用
ext_active_for <- function(kind) {
  ids <- character(0)
  for (e in GGSPEC_EXTENSIONS) {
    if (!(kind %in% e$kind)) next
    if (!.ext_installed(e$pkg)) next
    if (!ext_is_enabled(e$id)) next
    ids <- c(ids, e$id)
  }
  ids
}

## ---- 供前端展示的清单 -------------------------------------------------------
ext_catalog <- function() {
  out <- list()
  for (e in GGSPEC_EXTENSIONS) {
    inst <- .ext_installed(e$pkg)
    miss <- if (inst) .ext_missing_deps(e$pkg) else character(0)
    out[[length(out) + 1]] <- list(
      id = e$id, label = e$label, desc = e$desc, pkg = e$pkg,
      kind = as.list(e$kind),
      installed = inst,
      enabled = inst && ext_is_enabled(e$id),
      missingDeps = as.list(miss),
      usable = inst && !length(miss)
    )
  }
  out
}
