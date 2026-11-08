# ggplotGUI - 扩展包注册与启用开关
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
  list(id = "ggrepel", label = "ggrepel 防重叠标签", kind = c("geom"),
       desc = "自动避让的文本与标签",
       pkg = "ggrepel"),
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
    out[[length(out) + 1]] <- list(
      id = e$id, label = e$label, desc = e$desc, pkg = e$pkg,
      kind = as.list(e$kind),
      installed = inst,
      enabled = inst && ext_is_enabled(e$id)
    )
  }
  out
}
