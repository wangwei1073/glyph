#!/usr/bin/env Rscript
# 生成 geom 示意图（96×72 PNG）→ frontend/public/geom-thumbs/
# 用法（项目根目录）: Rscript tools/make_geom_thumbs.R
#
# 思路：给每个 geom 配一份「最小的合适映射」+ 合成数据，走与界面完全相同的
# spec → 代码 → 渲染 管线出图，因此示意图和用户实际点出来的图形一致。

if (.Platform$OS.type == "windows") {
  invisible(try(Sys.setlocale("LC_CTYPE", ".UTF-8"), silent = TRUE))
}
options(warn = -1)
for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f, encoding = "UTF-8")
suppressPackageStartupMessages(library(ggplot2))

META <- meta_build_lookup(ggspec_build_meta())
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tempfile())
out_dir <- file.path("frontend", "public", "geom-thumbs")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# ---- 合成数据 ---------------------------------------------------------------
set.seed(7)
d <- data.frame(
  x = 1:24,
  y = c(3, 5, 4, 6, 5, 7, 6, 8, 2, 4, 3, 5, 4, 6, 5, 7, 4, 6, 5, 7, 6, 8, 7, 9),
  cat = factor(rep(c("A", "B", "C"), each = 8)),
  lab = paste0("p", 1:24)
)
d$xmin <- d$x - 0.35; d$xmax <- d$x + 0.35
d$ymin <- d$y - 0.7;  d$ymax <- d$y + 0.7
d$xend <- d$x + 0.8;  d$yend <- d$y + 0.8
d$angle <- seq(0, 2 * pi, length.out = nrow(d))
d$radius <- 0.55
d$z <- with(d, sin(x / 4) * cos(y / 4))
d$sample <- d$y
d$group <- d$cat

# 3×3 网格（瓦片 / 等高线 / 矩形）
dg <- expand.grid(x = 1:3, y = 1:3)
dg$z <- c(1, 2, 3, 2, 3, 4, 3, 4, 5)
dg$cat <- factor(rep(c("A", "B", "C"), 3))
dg$xmin <- dg$x - 0.45; dg$xmax <- dg$x + 0.45
dg$ymin <- dg$y - 0.45; dg$ymax <- dg$y + 0.45
dg$lab <- "p"; dg$sample <- dg$z; dg$group <- dg$cat

# 多边形（闭合五边形）
th <- seq(0, 2 * pi, length.out = 6)
dpoly <- data.frame(x = 2.5 + 1.1 * cos(th), y = 2.5 + 1.1 * sin(th), group = "A", cat = "A")

# 密集散点（二维分箱 / 六边形 / 2D 密度需要足够点数才看得出形状）
set.seed(11)
dmany <- data.frame(x = c(rnorm(300, 4, 1.4), rnorm(120, 7, 0.9)),
                    y = c(rnorm(300, 4, 1.2), rnorm(120, 7.5, 1.1)))
dmany$cat <- factor(sample(c("A", "B", "C"), nrow(dmany), replace = TRUE))
dmany$z <- with(dmany, sin(x) * cos(y))
dmany$lab <- "p"; dmany$sample <- dmany$y; dmany$group <- dmany$cat

# ---- 每个 geom 的「最小合适映射」 -------------------------------------------
# aes: 名称 = 美学, 值 = 列名；params: 常量参数；data: d / grid / poly；theme: 主题覆盖
T <- list(
  point          = list(aes = c(x = "x", y = "y", colour = "cat")),
  jitter         = list(aes = c(x = "x", y = "y", colour = "cat")),
  line           = list(aes = c(x = "x", y = "y", colour = "cat")),
  path           = list(aes = c(x = "x", y = "y", colour = "cat")),
  step           = list(aes = c(x = "x", y = "y", colour = "cat")),
  smooth         = list(aes = c(x = "x", y = "y")),
  rug            = list(aes = c(x = "x", y = "y")),
  quantile       = list(aes = c(x = "x", y = "y")),
  qq             = list(aes = c(sample = "y")),
  qq_line        = list(aes = c(sample = "y")),
  `function`     = list(params = list(fun = list(expr = "~ .x^2"))),
  curve          = list(aes = c(x = "x", y = "y", xend = "xend", yend = "yend")),
  abline         = list(params = list(slope = 0.5, intercept = 0.15)),
  hline          = list(params = list(yintercept = 6)),
  vline          = list(params = list(xintercept = 12)),
  rangeframe     = list(aes = c(x = "x", y = "y"), theme = "minimal"),
  bar            = list(aes = c(x = "cat", fill = "cat")),
  col            = list(aes = c(x = "cat", y = "y", fill = "cat")),
  count          = list(aes = c(x = "x", y = "y")),
  histogram      = list(aes = c(x = "x")),
  freqpoly       = list(aes = c(x = "x", colour = "cat")),
  dotplot        = list(aes = c(x = "x")),
  density        = list(aes = c(x = "x", colour = "cat")),
  area           = list(aes = c(x = "x", y = "y", fill = "cat")),
  boxplot        = list(aes = c(x = "cat", y = "y", fill = "cat")),
  violin         = list(aes = c(x = "cat", y = "y", fill = "cat")),
  tufteboxplot   = list(aes = c(x = "cat", y = "y")),
  crossbar       = list(aes = c(x = "x", y = "y", ymin = "ymin", ymax = "ymax")),
  errorbar       = list(aes = c(x = "x", ymin = "ymin", ymax = "ymax")),
  errorbarh      = list(aes = c(y = "y", xmin = "xmin", xmax = "xmax")),
  pointrange     = list(aes = c(x = "x", y = "y", ymin = "ymin", ymax = "ymax")),
  linerange      = list(aes = c(x = "x", ymin = "ymin", ymax = "ymax")),
  ribbon         = list(aes = c(x = "x", ymin = "ymin", ymax = "ymax", fill = "cat")),
  text           = list(aes = c(x = "x", y = "y", label = "lab")),
  label          = list(aes = c(x = "x", y = "y", label = "lab")),
  text_repel     = list(aes = c(x = "x", y = "y", label = "lab")),
  label_repel    = list(aes = c(x = "x", y = "y", label = "lab")),
  marquee_repel  = list(aes = c(x = "x", y = "y", label = "lab")),
  bin_2d         = list(aes = c(x = "x", y = "y"), data = "many"),
  bin2d          = list(aes = c(x = "x", y = "y"), data = "many"),
  hex            = list(aes = c(x = "x", y = "y"), data = "many"),
  density_2d     = list(aes = c(x = "x", y = "y"), data = "many"),
  density_2d_filled = list(aes = c(x = "x", y = "y"), data = "many"),
  density2d      = list(aes = c(x = "x", y = "y"), data = "many"),
  density2d_filled = list(aes = c(x = "x", y = "y"), data = "many"),
  contour        = list(aes = c(x = "x", y = "y", z = "z"), data = "grid"),
  contour_filled = list(aes = c(x = "x", y = "y", z = "z"), data = "grid"),
  tile           = list(aes = c(x = "x", y = "y", fill = "z"), data = "grid"),
  raster         = list(aes = c(x = "x", y = "y", fill = "z"), data = "grid"),
  rect           = list(aes = c(xmin = "xmin", xmax = "xmax", ymin = "ymin", ymax = "ymax", fill = "cat"), data = "grid"),
  polygon        = list(aes = c(x = "x", y = "y", group = "group"), data = "poly"),
  segment        = list(aes = c(x = "x", y = "y", xend = "xend", yend = "yend")),
  spoke          = list(aes = c(x = "x", y = "y", angle = "angle", radius = "radius")),

  # ---- 扩展包 geom（第一批）----
  beeswarm       = list(aes = c(x = "cat", y = "y", colour = "cat")),
  quasirandom    = list(aes = c(x = "cat", y = "y", colour = "cat")),
  richtext       = list(aes = c(x = "x", y = "y", label = "lab")),
  textbox        = list(aes = c(x = "x", y = "y", label = "lab")),
  signif         = list(aes = c(x = "cat", y = "y")),
  # bracket 的默认 comparisons 依赖分组，需显式给 y.position 才能出图
  bracket        = list(aes = c(x = "cat", y = "y"), params = list(y.position = 40)),
  pwc            = list(aes = c(x = "cat", y = "y")),
  exec           = list(aes = c(x = "x", y = "y", label = "lab"))
)
# ggside 的 36 个边际 geom：统一用「主图散点 + 边际层」示意，
# 否则只有边际图层会因缺少主图而看不出效果。
# 注意：部分边际类型有必需参数（vline/hline 要 intercept、text/label 要 label、
# function 要 fun、segment 要端点），缺参数会 setup geom 失败，需逐个给出。
GG_SIDE_THUMBS <- local({
  # 每类需要的额外参数（缺失则为空）
  extra <- list(
    vline = list(xintercept = 12),
    hline = list(yintercept = 6),
    text = list(label = "p"),
    label = list(label = "p"),
    `function` = list(fun = list(expr = "~ .x")),
    segment = list(xend = 20, yend = 8)
  )
  kinds <- c("histogram", "density", "boxplot", "violin", "point", "line", "bar",
             "col", "tile", "text", "label", "path", "segment", "hline", "vline",
             "abline", "function", "freqpoly")
  out <- list()
  for (sd in c("xside", "yside")) {
    for (kd in kinds) {
      nm <- paste0(sd, kd)
      out[[nm]] <- list(aes = c(x = "x", y = "y"), data = "d", side = TRUE,
                        params = extra[[kd]] %||% list())
    }
  }
  out
})
# 需要专用数据、无法用合成数据示意的 geom → 生成占位图
SKIP <- c("map", "sf", "sf_label", "sf_text", "blank", "hex",
          # hex 需要 hexbin 包；ggrepel 的富文本标签需要 marquee 包 —— 未安装时用占位图
          "marquee_repel",
          # ggpubr::geom_bracket 必须在 comparisons 里给出具体的组名，
          # 合成数据无法通用示意，用占位图（实际使用时由用户指定比较组）
          "bracket")

pick_data <- function(key) {
  switch(if (is.null(T[[key]]$data)) "d" else T[[key]]$data,
         d = d, grid = dg, poly = dpoly, many = dmany)
}

build_spec <- function(key) {
  # ggside 的边际 geom 定义在 GG_SIDE_THUMBS 里
  cfg <- T[[key]] %||% GG_SIDE_THUMBS[[key]] %||% list()
  aes_map <- cfg$aes %||% c(x = "x", y = "y")
  aes_list <- lapply(aes_map, function(col) list(map = as.character(col)))
  layer <- list(geom = key, stat = "", position = list(type = "", params = list()),
                aes = aes_list, params = cfg$params %||% list(), aesParams = list())
  # 垫一层不可见的 geom_blank：为「参考线 / 函数曲线」这类不吃数据的 geom 建立坐标范围。
  # 必须沿用主图层的 x/y 列（例如柱状图的 x 是离散列），否则两层的标度类型会冲突。
  col_of <- function(nm, default) {
    if (!is.null(names(aes_map)) && nm %in% names(aes_map)) as.character(aes_map[[nm]]) else default
  }
  blank_aes <- list(x = list(map = col_of("x", "x")),
                    y = list(map = col_of("y", "y")))
  blank <- list(geom = "blank", stat = "", position = list(type = "", params = list()),
                aes = blank_aes, params = list(), aesParams = list())
  layers <- list(blank, layer)
  # ggside 的边际 geom 必须配一个主图图层，否则看不出「边际」效果
  # （它们画在面板外侧，单独存在时是一片空白）
  if (isTRUE(cfg$side)) {
    main <- list(geom = "point", stat = "", position = list(type = "", params = list()),
                 aes = list(x = list(map = col_of("x", "x")),
                            y = list(map = col_of("y", "y"))),
                 params = list(), aesParams = list())
    layers <- list(blank, main, layer)
  }
  list(
    data = list(source = list(type = "none")),
    layers = layers,
    scales = list(),
    labs = list(),
    theme = list(base = cfg$theme %||% "void", args = list(base_size = 8),
                  elements = list(legend.position = "none"))
  )
}

# ---- 占位图 ----------------------------------------------------------------
make_placeholder <- function(path) {
  spec <- list(data = list(source = list(type = "none")),
               layers = list(list(geom = "rect", stat = "",
                                  position = list(type = "", params = list()),
                                  aes = list(xmin = list(value = 0), xmax = list(value = 1),
                                             ymin = list(value = 0), ymax = list(value = 1)),
                                  params = list(fill = "#f2f4f6", colour = "#dfe4ea"),
                                  aesParams = list())),
               theme = list(base = "void", args = list(), elements = list()))
  gen <- spec_to_code(spec, META, STATE, include_data = FALSE, with_final = TRUE)
  rf <- ggspec_render_file(gen$eval_code, data.frame(), width = 96, height = 72, dpi = 96, format = "png")
  file.copy(rf$path, path, overwrite = TRUE); unlink(rf$path)
}

# ---- 批量渲染 ---------------------------------------------------------------
make_placeholder(file.path(out_dir, "_placeholder.png"))

ok <- 0L; fail <- 0L
for (g in META$geoms) {
  key <- g$name
  dst <- file.path(out_dir, paste0(key, ".png"))
  if (key %in% SKIP || (is.null(T[[key]]) && is.null(GG_SIDE_THUMBS[[key]]))) {
    file.copy(file.path(out_dir, "_placeholder.png"), dst, overwrite = TRUE)
    cat(sprintf("  [占位] %s\n", key))
    next
  }
  res <- tryCatch({
    spec <- build_spec(key)
    gen <- spec_to_code(spec, META, STATE, include_data = FALSE, with_final = TRUE)
    rf <- ggspec_render_file(gen$eval_code, pick_data(key),
                             width = 96, height = 72, dpi = 96, format = "png")
    file.copy(rf$path, dst, overwrite = TRUE)
    unlink(rf$path)
    TRUE
  }, error = function(e) { cat(sprintf("  [失败] %s: %s\n", key, conditionMessage(e))); FALSE })
  if (isTRUE(res)) ok <- ok + 1L else { fail <- fail + 1L; file.copy(file.path(out_dir, "_placeholder.png"), dst, overwrite = TRUE) }
}

cat(sprintf("\n生成完成: %d 张示意图 / %d 失败 -> %s\n", ok, fail, normalizePath(out_dir)))
