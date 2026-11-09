# Glyph - 代码补全词表
# 从元数据注册表 + 已安装包生成静态补全素材，供前端 CodeMirror 使用。
# 设计取舍：只做「词表补全」，不做语义分析（不解析语法树）。
#   覆盖最高频的两个场景：函数名（geom_/stat_/scale_/theme_…）与 library() 包名。

# 函数按类型分组返回，前端据此决定触发时机与排序。
ggspec_build_completions <- function(meta) {
  meta <- meta %||% list()

  # 注册表里 `fn` 才是可直接调用的函数名（如 geom_abline / scale_alpha_binned），
  # `name` 多为短名（abline）。优先取 fn，缺失时回退 name。
  # 返回 list(fn, pkg)，便于前端按包分组展示。
  fns_of <- function(x) {
    if (!length(x)) return(list())
    out <- lapply(x, function(it) {
      fn <- it$fn
      if (is.null(fn) || !length(fn) || is.na(fn) || !nzchar(fn)) {
        fn <- it$name
      }
      if (is.null(fn) || !length(fn) || is.na(fn) || !nzchar(fn)) return(NULL)
      list(fn = as.character(fn), pkg = as.character(it$package %||% ""))
    })
    out <- Filter(Negate(is.null), out)
    if (!length(out)) return(list())
    # 按 fn 去重（同一函数可能因多参数注册多次）
    keys <- vapply(out, function(o) o$fn, character(1))
    out[!duplicated(keys)]
  }

  fns <- function(x) vapply(fns_of(x), function(o) o$fn, character(1))
  fns_pkg <- function(x) vapply(fns_of(x), function(o) o$pkg, character(1))

  geoms   <- fns(meta$geoms)
  stats   <- fns(meta$stats)
  scales  <- fns(meta$scales)
  coords  <- fns(meta$coords)
  positions <- fns(meta$positions)
  facets  <- fns(meta$facets)
  guides  <- fns(meta$guides)
  themes  <- fns(meta$themes)
  # 主题「元素」名（axis.text.x 这类），与主题函数分开
  theme_elements <- {
    te <- meta$themeElements %||% list()
    if (!length(te)) character(0) else {
      v <- vapply(te, function(it) {
        n <- it$name %||% it$fn
        if (is.null(n) || !length(n) || is.na(n)) return(NA_character_)
        as.character(n)
      }, character(1))
      unique(stats::na.omit(v))
    }
  }
  annotations <- fns(meta$annotations)

  # 已安装包：library() 补全用。427 个包左右，按字母序，常用包前置
  pkgs <- tryCatch(rownames(utils::installed.packages()), error = function(e) character(0))
  pkgs <- sort(unique(pkgs))

  # 本项目常用/推荐的包前置，便于优先选中
  preferred <- c(
    "ggplot2", "patchwork", "ggrepel", "ggsci", "ggthemes", "ggprism", "ggpubr",
    "ggbeeswarm", "ggtext", "ggside", "ggstats", "ggridges", "ggh4x", "ggnewscale",
    "ggdist", "ggforce", "ggbreak", "hrbrthemes", "plotly", "ragg",
    "readr", "readxl", "scales", "dplyr", "tidyr", "stringr", "jsonlite"
  )
  pkgs_ordered <- c(intersect(preferred, pkgs), setdiff(pkgs, preferred))

  # ---- 函数参数表（P2：geom_point( 内补 size/alpha 等）----
  # 只输出「函数名 -> 参数名数组」，保持精简；不带默认值与文档。
  # 来源：meta.geoms[].params（函数形式参数）+ meta.geoms[].aes（aes 映射名）。
  # 约定：params 与 aes 分开返回，前端在 aes(...) 与函数参数位置给不同建议。
  params_of <- function(items) {
    if (!length(items)) return(list())
    out <- list()
    for (it in items) {
      fn <- it$fn %||% it$name
      if (is.null(fn) || !length(fn) || is.na(fn) || !nzchar(fn)) next
      pr <- it$params %||% list()
      pn <- if (length(pr)) names(pr) else character(0)
      a <- it$aes %||% list()
      an <- unique(c(a$required %||% character(0), a$optional %||% character(0)))
      # 去掉 ggplot2 的通用参数，避免名单过长（这些用户基本不用改）
      common <- c("mapping", "data", "stat", "position", "show.legend", "inherit.aes", "...")
      pn <- setdiff(pn, common)
      if (length(pn) || length(an)) {
        out[[fn]] <- list(params = as.list(pn), aes = as.list(an))
      }
    }
    out
  }

  geom_params <- params_of(meta$geoms)
  stat_params <- params_of(meta$stats)

  list(
    version = meta$ggplot2Version %||% "",
    geoms      = geoms,
    geoms_pkg  = fns_pkg(meta$geoms),
    stats      = stats,
    scales     = scales,
    coords     = coords,
    positions  = positions,
    facets     = facets,
    guides     = guides,
    themes     = themes,
    themes_pkg = fns_pkg(meta$themes),
    theme_elements = theme_elements,
    annotations = annotations,
    packages   = pkgs_ordered,
    scale_aes  = names(meta$scaleAesOrder %||% list()),
    # P2：函数参数与 aes 映射名
    geom_params = geom_params,
    stat_params = stat_params
  )
}
