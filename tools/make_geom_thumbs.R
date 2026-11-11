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

# ---- 扩展包 geom 需要的专用数据 ----
# ggridges 的 ridgeline 需要 height 列（脊线高度）
set.seed(3)
dridge <- do.call(rbind, lapply(1:3, function(g) {
  n <- 18
  data.frame(x = seq_len(n), y = g, h = abs(sin(seq_len(n) / 4 + g)) * 0.9 + 0.1)
}))
dridge$cat <- factor(dridge$y)
# vridgeline：x 为分类、y 为连续、height 沿 x
dridge2 <- do.call(rbind, lapply(1:3, function(g) {
  n <- 18
  data.frame(x = g, y = seq_len(n), h = abs(cos(seq_len(n) / 4 + g)) * 0.9 + 0.1)
}))
dridge2$cat <- factor(dridge2$x)
# ggstats 的 prop/likert 需要「长表」：每行一个观测，不预先汇总
set.seed(5)
dprop <- data.frame(
  cat = factor(sample(c("Q1", "Q2", "Q3"), 120, TRUE)),
  cat2 = factor(sample(c("低", "中", "高"), 120, TRUE), levels = c("低", "中", "高"))
)
dprop$y <- 1
dprop$z <- 1
dprop$x <- seq_len(nrow(dprop))
dprop$lab <- "p"; dprop$sample <- 1; dprop$group <- dprop$cat
dprop$xmin <- 0; dprop$xmax <- 1; dprop$ymin <- 0; dprop$ymax <- 1
# ggforce 的圆/椭圆/弧需要半径列
dprop$radius <- 0.6
# arc_bar 需要 r0 / r 与外半径
darcbar <- data.frame(
  x = c(1, 1, 1), y = c(1, 1, 1),
  r0 = c(0.3, 0.3, 0.3), r = c(1, 1, 1),
  start = c(0, 2 * pi / 3, 4 * pi / 3),
  end = c(2 * pi / 3, 4 * pi / 3, 2 * pi),
  cat = factor(c("A", "B", "C"))
)
darcbar$radius <- 0.6
darcbar$group <- darcbar$cat; darcbar$lab <- "p"; darcbar$sample <- 1
darcbar$xmin <- 0; darcbar$xmax <- 1; darcbar$ymin <- 0; darcbar$ymax <- 1; darcbar$z <- 1

# 第三批专用数据
# rad：给 ggforce 的 circle/ellipse/arc/spiro（x0/y0 + 半径 + 角度）
drad <- data.frame(
  x = c(1, 2, 3), cat = factor(c("A", "B", "C")),
  radius = c(0.35, 0.3, 0.25), start = 0, end = 5.5, angle = 0
)
drad$group <- drad$cat; drad$lab <- "p"; drad$sample <- 1
drad$xmin <- 0; drad$xmax <- 1; drad$ymin <- 0; drad$ymax <- 1; drad$z <- 1
# scatter：Voronoi / Delaunay / autopoint 需要有一定散开度的点
set.seed(9)
dscatter <- data.frame(x = runif(45, 1, 5), y = runif(45, 1, 5))
dscatter$cat <- factor(sample(c("A", "B"), 45, TRUE))
dscatter$group <- dscatter$cat; dscatter$lab <- "p"; dscatter$sample <- 1
dscatter$xmin <- 0; dscatter$xmax <- 1; dscatter$ymin <- 0; dscatter$ymax <- 1
dscatter$z <- 1; dscatter$radius <- 0.3
# real：三组不同均值/方差的正态混合，给箱线/小提琴/密度/雨云「真实数据形状」
set.seed(42)
dreal <- data.frame(
  y = c(rnorm(40, 10, 1.2), rnorm(40, 14, 2.2), rnorm(40, 12, 0.9)),
  cat = factor(rep(c("A", "B", "C"), each = 40))
)
dreal$lab <- paste0("p", seq_len(nrow(dreal)))
# diag：对角线网格需要 group 且每格有对角端点
ddiag <- do.call(rbind, lapply(1:3, function(i) {
  data.frame(x = c(i, i + 0.8), y = c(i, i + 0.8), cat = factor(LETTERS[i]))
}))
ddiag$group <- ddiag$cat; ddiag$lab <- "p"; ddiag$sample <- 1
ddiag$xmin <- 0; ddiag$xmax <- 1; ddiag$ymin <- 0; ddiag$ymax <- 1; ddiag$z <- 1; ddiag$radius <- 0.2
# pset：平行集需要 key（集合成员）与 x（类别轴）
dpset <- data.frame(
  x = factor(rep(c("A", "B", "C"), each = 3)),
  cat = factor(rep(c("g1", "g2", "g3"), 3)),
  key = factor(rep(c("s1", "s2", "s3"), 3))
)
dpset$group <- dpset$key; dpset$lab <- "p"; dpset$sample <- 1
dpset$xmin <- 0; dpset$xmax <- 1; dpset$ymin <- 0; dpset$ymax <- 1; dpset$z <- 1; dpset$radius <- 0.2

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
  histogram      = list(aes = c(x = "y"), data = "real"),
  freqpoly       = list(aes = c(x = "y", colour = "cat"), data = "real"),
  dotplot        = list(aes = c(x = "cat"), data = "d"),
  density        = list(aes = c(x = "y", colour = "cat"), data = "real"),
  area           = list(aes = c(x = "x", y = "y", fill = "cat")),
  boxplot        = list(aes = c(x = "cat", y = "y", fill = "cat"), data = "real"),
  violin         = list(aes = c(x = "cat", y = "y", fill = "cat"), data = "real"),
  tufteboxplot   = list(aes = c(x = "cat", y = "y"), data = "real"),
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
  exec           = list(aes = c(x = "x", y = "y", label = "lab")),

  # ---- 扩展包 geom（第二批）----
  # ggridges：density_ridges 只需 x/y（自动算密度）；ridgeline 还需 height
  density_ridges         = list(aes = c(x = "y", y = "cat")),
  density_ridges2        = list(aes = c(x = "y", y = "cat")),
  density_ridges_gradient = list(aes = c(x = "y", y = "cat", fill = "y")),
  density_line           = list(aes = c(x = "y", y = "cat")),
  ridgeline              = list(aes = c(x = "x", y = "y", height = "h"), data = "ridge"),
  ridgeline_gradient     = list(aes = c(x = "x", y = "y", height = "h", fill = "h"), data = "ridge"),
  vridgeline             = list(aes = c(y = "x", x = "cat"), data = "ridge2"),
  # ggstats：长表 + 分组，自动统计比例
  # prop_bar 需要「分类 y + fill 分组」，x 由 stat 计算；不能用完全空的 aes
  prop_bar               = list(aes = c(y = "cat", fill = "cat2"), data = "prop"),
  prop_text              = list(aes = c(y = "cat", fill = "cat2"), data = "prop"),
  prop_connector         = list(aes = c(y = "cat", fill = "cat2"), data = "prop"),
  likert                 = list(aes = c(y = "cat", fill = "cat2"), data = "prop", position = "likert"),
  likert_text            = list(aes = c(y = "cat", fill = "cat2"), data = "prop", position = "likert"),
  diverging              = list(aes = c(y = "cat", fill = "cat2"), data = "prop", position = "diverging"),
  diverging_text         = list(aes = c(y = "cat", fill = "cat2"), data = "prop", position = "diverging"),
  pyramid                = list(aes = c(y = "cat", fill = "cat2"), data = "prop", position = "diverging"),
  pyramid_text           = list(aes = c(y = "cat", fill = "cat2"), data = "prop", position = "diverging"),
  bar_connector          = list(aes = c(x = "cat", y = "y")),
  connector              = list(aes = c(x = "cat", y = "y")),
  # stripped_* 是「背景底纹」，需要配合其他图层才有意义，单独渲染几乎是空白
  stripped_cols          = list(aes = c(x = "cat", y = "y"), data = "prop", side = TRUE),
  stripped_rows          = list(aes = c(x = "cat", y = "y"), data = "prop", side = TRUE),
  # ggh4x
  pointpath              = list(aes = c(x = "x", y = "y")),
  outline_point          = list(aes = c(x = "x", y = "y")),
  text_aimed             = list(aes = c(x = "x", y = "y", label = "lab")),
  box                    = list(aes = c(xmin = "xmin", xmax = "xmax", ymin = "ymin", ymax = "ymax"), data = "grid"),
  tilemargin             = list(aes = c(x = "x", y = "y", fill = "z"), data = "grid"),
  rectmargin             = list(aes = c(xmin = "xmin", xmax = "xmax", ymin = "ymin", ymax = "ymax", fill = "cat"), data = "grid"),
  polygonraster          = list(aes = c(x = "x", y = "y", fill = "z"), data = "grid"),

  # ---- 扩展包 geom（第三批）----
  # ggdist：x 为分布值 + y 为分组（半小提琴风格）
  slab          = list(aes = c(x = "y", y = "cat")),
  slabinterval  = list(aes = c(x = "y", y = "cat")),
  interval      = list(aes = c(x = "y", y = "cat"), params = list(.width = 0.5)),
  pointinterval = list(aes = c(x = "y", y = "cat"), params = list(.width = 0.5)),
  dots          = list(aes = c(x = "y", y = "cat")),
  dotsinterval  = list(aes = c(x = "y", y = "cat")),
  swarm         = list(aes = c(x = "cat", y = "y")),
  blur_dots     = list(aes = c(x = "y", y = "cat")),
  spike         = list(aes = c(x = "y", y = "cat")),
  weave         = list(aes = c(x = "x", y = "y")),
  lineribbon    = list(aes = c(x = "x", ymin = "ymin", ymax = "ymax")),
  # ggforce：多为专用坐标美学
  circle        = list(aes = c(x0 = "x", y0 = "x", r = "radius"), data = "rad"),
  ellipse       = list(aes = c(x0 = "x", y0 = "cat", a = "radius", b = "radius"), data = "rad"),
  arc           = list(aes = c(x0 = "x", y0 = "cat", r = "radius", start = "start", end = "end"), data = "rad"),
  arc_bar       = list(aes = c(r0 = "r0", r = "r", start = "start", end = "end", fill = "cat"), data = "arcbar"),
  sina          = list(aes = c(x = "cat", y = "y")),
  link          = list(aes = c(x = "x", y = "y", xend = "xend", yend = "yend")),
  bezier        = list(aes = c(x = "x", y = "y", xend = "xend", yend = "yend")),
  bspline       = list(aes = c(x = "x", y = "y")),
  spiro         = list(aes = c(x0 = "x", y0 = "cat", r = "radius"), data = "rad"),
  shape         = list(aes = c(x = "x", y = "y")),
  voronoi_tile  = list(aes = c(x = "x", y = "y"), data = "scatter"),
  voronoi_segment = list(aes = c(x = "x", y = "y"), data = "scatter"),
  delaunay_tile = list(aes = c(x = "x", y = "y"), data = "scatter"),
  delaunay_segment = list(aes = c(x = "x", y = "y"), data = "scatter"),
  mark_hull     = list(aes = c(x = "x", y = "y", label = "lab")),
  mark_circle   = list(aes = c(x = "x", y = "y", label = "lab")),
  mark_ellipse  = list(aes = c(x = "x", y = "y", label = "lab")),
  mark_rect     = list(aes = c(x = "x", y = "y", label = "lab")),
  mark_regon    = list(aes = c(x = "x", y = "y", label = "lab")),
  regon         = list(aes = c(x = "x", y = "y", group = "group"), data = "poly"),
  parallel_sets = list(aes = c(x = "x", y = "cat", group = "key"), data = "pset"),
  diagonal      = list(aes = c(x = "x", y = "y", group = "cat"), data = "diag"),
  diagonal_wide = list(aes = c(x = "x", y = "y", group = "cat"), data = "diag"),
  autopoint     = list(aes = c(x = "x", y = "y"), data = "scatter"),
  autodensity   = list(aes = c(x = "y"), data = "d"),
  autohistogram = list(aes = c(x = "x")),
  # ---- 第四批扩展（科研绘图 A 级）----
  rain          = list(aes = c(x = "cat", y = "y", fill = "cat"), data = "real",
                       noBlank = TRUE),
  pointdensity  = list(aes = c(x = "x", y = "y"), data = "scatter"),
  point_rast    = list(aes = c(x = "x", y = "y", colour = "cat"), data = "scatter"),
  line_rast     = list(aes = c(x = "x", y = "y", colour = "cat"), data = "d"),
  tile_rast     = list(aes = c(x = "x", y = "y", fill = "y")),
  boxplot_jitter= list(aes = c(x = "cat", y = "y")),
  violin_rast   = list(aes = c(x = "cat", y = "y")),
  quasirandom_rast = list(aes = c(x = "cat", y = "y", colour = "cat")),
  jitter_rast   = list(aes = c(x = "cat", y = "y", colour = "cat")),
  beeswarm_rast = list(aes = c(x = "cat", y = "y", colour = "cat")),
  dl            = list(aes = c(x = "x", y = "y", label = "lab", colour = "cat"),
                       params = list(method = list(expr = "list('first.points')")))
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
          "bracket",
          # bar_connector 需要特定的 stat 参数组合；vridgeline 需要 height 与方向对齐，
          # 合成数据难以通用示意，用占位图
          "bar_connector", "vridgeline",
          # ggrastr 的 line_rast 在小尺寸栅格设备下输出空文件，用占位图
          # （功能本身可用，已由 A 级扩展探针验证）
          "line_rast",
          # regon / diagonal / parallel_sets 需要特定拓扑的数据组织方式，
          # 合成数据无法通用示意；功能本身可用（见 test_ext_batch3）
          "regon", "diagonal", "diagonal_wide", "parallel_sets",
          "parallel_sets_axes", "parallel_sets_labels", "arc_bar",
          "autopoint", "autodensity", "autohistogram",
          "interval", "pointinterval",
          # circle / ellipse / arc / spiro 用独立的 x0/y0/r 坐标系，
          # 与 thumbnail 脚本「先垫 blank 层」的做法冲突（几何被算到面板外）；
          # 功能本身可用，已由 test_ext_batch3 与专项验证覆盖
          "circle", "ellipse", "arc", "spiro")

# ---- 第二轮：把能画出来的 geom 从占位图里捞回来，并修正统计变换类的坐标范围 ----
for (k in c("density", "freqpoly", "histogram", "dotplot", "qq", "qq_line",
            "density_ridges", "density_ridges2", "density_ridges_gradient", "density_line",
            "likert", "likert_text", "pyramid", "pyramid_text", "proportion", "proportion_text",
            "bin_2d", "bin2d", "hex", "density_2d", "density_2d_filled",
            "density2d", "density2d_filled")) {
  if (!is.null(T[[k]])) T[[k]]$noBlank <- TRUE
}
T$interval <- list(aes = c(x = "y", y = "cat"), params = list(.width = 0.5), noBlank = TRUE)
T$pointinterval <- list(aes = c(x = "y", y = "cat"), params = list(.width = 0.5), noBlank = TRUE)
T$vridgeline <- list(aes = c(x = "cat", y = "y", height = "h"), data = "ridge2", noBlank = TRUE)
T$arc_bar <- list(aes = c(r0 = "r0", r = "r", start = "start", end = "end", fill = "cat"),
                  data = "arcbar", noBlank = TRUE)
T$circle <- list(aes = c(x0 = "x", y0 = "cat", r = "radius"), data = "rad", noBlank = TRUE)
T$ellipse <- list(aes = c(x0 = "x", y0 = "cat", a = "radius", b = "radius"), data = "rad", noBlank = TRUE)
T$arc <- list(aes = c(x0 = "x", y0 = "cat", r = "radius", start = "start", end = "end"), data = "rad", noBlank = TRUE)
T$spiro <- list(aes = c(x0 = "x", y0 = "cat", r = "radius"), data = "rad", noBlank = TRUE)
T$diagonal <- list(aes = c(x = "x", y = "y", group = "cat"), data = "diag", noBlank = TRUE)
T$diagonal_wide <- list(aes = c(x = "x", y = "y", group = "cat"), data = "diag", noBlank = TRUE)
T$regon <- list(aes = c(x = "x", y = "y", group = "group"), data = "poly", noBlank = TRUE)
T$parallel_sets <- list(aes = c(x = "x", y = "cat", group = "key"), data = "pset", noBlank = TRUE)
T$parallel_sets_axes <- list(aes = c(x = "x", y = "cat", group = "key"), data = "pset", noBlank = TRUE)
T$parallel_sets_labels <- list(aes = c(x = "x", y = "cat", group = "key"), data = "pset", noBlank = TRUE)
T$bracket <- list(aes = c(x = "cat", y = "y"),
                  params = list(comparisons = list(c("A", "B")), y.position = 11), noBlank = TRUE)
T$bar_connector <- list(aes = c(x = "cat", y = "y"), noBlank = TRUE)
T$autopoint <- list(aes = c(x = "x", y = "y"), data = "scatter", noBlank = TRUE)
T$autodensity <- list(aes = c(x = "y"), data = "real", noBlank = TRUE)
T$autohistogram <- list(aes = c(x = "y"), data = "real", noBlank = TRUE)
T$line_rast <- list(aes = c(x = "x", y = "y", colour = "cat"), data = "d", noBlank = TRUE)
SKIP <- setdiff(SKIP, c("bracket", "bar_connector", "vridgeline", "line_rast", "map", "sf", "sf_label", "sf_text", "hex", "blank",
                        "regon", "diagonal", "diagonal_wide", "parallel_sets",
                        "parallel_sets_axes", "parallel_sets_labels", "arc_bar",
                        "autopoint", "autodensity", "autohistogram",
                        "interval", "pointinterval",
                        "circle", "ellipse", "arc", "spiro"))
# 自定义渲染代码（专用数据/stat 的 geom 走这里，避免空图）
dbz <- data.frame(
  x = c(1, 2, 4, 5,   1, 3, 3, 5,   1, 2, 4, 5),
  y = c(1, 3, 3, 1,   2, 2, 4, 4,   4, 5, 5, 4),
  cat = factor(rep(c("A", "B", "C"), each = 4))
)
dmark <- d[1:6, ]
ddiag4 <- do.call(rbind, lapply(1:3, function(i) {
  data.frame(x = c(i, i + 0.8, i + 0.8, i),
             y = c(i, i, i + 0.8, i + 0.8),
             cat = factor(LETTERS[i]))
}))
T$slab$code <- "p <- ggplot(df, aes(x = y, y = cat)) + ggdist::stat_slab(); p"
T$slab$data <- "real"
T$slabinterval$code <- "p <- ggplot(df, aes(x = y, y = cat)) + ggdist::stat_slabinterval(); p"
T$slabinterval$data <- "real"
T$spike$code <- "p <- ggplot(df, aes(x = y, y = cat)) + ggdist::stat_spike(); p"
T$spike$data <- "real"
T$bezier$code <- "p <- ggplot(df, aes(x, y, group = cat, colour = cat)) + ggforce::geom_bezier(); p"
T$bezier$data <- "bz"
T$mark_circle$code <- "h <- df[chull(df$x, df$y), ]; p <- ggplot(df, aes(x, y, label = lab)) + geom_polygon(data = h, aes(x, y), fill = NA, colour = '#2f6fbf', size = .7) + geom_point(size = 1.4, colour = '#2f6fbf') + geom_text(size = 2, nudge_y = .25); p"
T$mark_circle$data <- "mark"
T$mark_rect$code <- "xr <- range(df$x); yr <- range(df$y); p <- ggplot(df, aes(x, y, label = lab)) + annotate('rect', xmin = xr[1] - .2, xmax = xr[2] + .2, ymin = yr[1] - .2, ymax = yr[2] + .2, fill = NA, colour = '#2f6fbf', size = .7) + geom_point(size = 1.4, colour = '#2f6fbf') + geom_text(size = 2, nudge_y = .25); p"
T$mark_rect$data <- "mark"
T$bracket$code <- "p <- ggplot(df, aes(cat, y)) + geom_boxplot(width = .5) + ggpubr::geom_bracket(xmin = 'A', xmax = 'B', y.position = 17, label = 'p < 0.05'); p"
T$bracket$data <- "real"
T$interval$code <- "p <- ggplot(df, aes(x = y, y = cat)) + ggdist::stat_interval(); p"
T$interval$data <- "real"
T$pointinterval$code <- "p <- ggplot(df, aes(x = y, y = cat)) + ggdist::stat_pointinterval(); p"
T$pointinterval$data <- "real"
T$circle$code <- "p <- ggplot(df, aes(x0 = x, y0 = as.numeric(cat), r = radius)) + ggforce::geom_circle() + coord_fixed(); p"
T$circle$data <- "rad"
T$ellipse$code <- "p <- ggplot(df, aes(x0 = x, y0 = as.numeric(cat), a = radius, b = radius)) + ggforce::geom_ellipse() + coord_fixed(); p"
T$ellipse$data <- "rad"
T$arc$code <- "p <- ggplot(df, aes(x0 = x, y0 = as.numeric(cat), r = radius, start = start, end = end)) + ggforce::geom_arc() + coord_fixed(); p"
T$arc$data <- "rad"
T$arc_bar$code <- "p <- ggplot(df, aes(x0 = 0, y0 = 0, r0 = 0, r = 1, start = start, end = end, fill = cat)) + ggforce::geom_arc_bar() + coord_fixed(); p"
T$arc_bar$data <- "arcbar"
T$diagonal$code <- "p <- ggplot(df, aes(x, y, group = cat)) + ggforce::geom_diagonal_wide(fill = '#9ec5fe'); p"
T$diagonal$data <- "diag4"
T$diagonal_wide$code <- "p <- ggplot(df, aes(x, y, group = cat)) + ggforce::geom_diagonal_wide(fill = '#c8e6c9'); p"
T$diagonal_wide$data <- "diag4"
T$regon$code <- "p <- ggplot(df, aes(x0 = x, y0 = y, r = .45, sides = 6)) + ggforce::geom_regon(fill = '#9ec5fe'); p"
T$regon$data <- "grid"
T$line_rast$code <- "p <- ggplot(df, aes(x, y, colour = cat)) + ggrastr::rasterise(geom_line(size = .9), dpi = 300); p"
T$line_rast$data <- "d"
# 图形近似（原包缺依赖或 geom 在小尺寸下不出图时，用等效图形示意）
dmark2 <- data.frame(x = c(2, 2.5, 2.2, 2.8), y = c(3, 3.4, 3.8, 3.5), lab = c("a","b","c","d"))
T$mark_circle$code <- "h <- df[chull(df$x, df$y), ]; p <- ggplot(df, aes(x, y, label = lab)) + geom_polygon(data = h, aes(x, y), fill = NA, colour = '#2f6fbf', size = .7) + geom_point(size = 1.4, colour = '#2f6fbf') + geom_text(size = 2, nudge_y = .25); p"
T$mark_circle$data <- "mark2"
T$mark_rect$code <- "xr <- range(df$x); yr <- range(df$y); p <- ggplot(df, aes(x, y, label = lab)) + annotate('rect', xmin = xr[1] - .2, xmax = xr[2] + .2, ymin = yr[1] - .2, ymax = yr[2] + .2, fill = NA, colour = '#2f6fbf', size = .7) + geom_point(size = 1.4, colour = '#2f6fbf') + geom_text(size = 2, nudge_y = .25); p"
T$mark_rect$data <- "mark"
T$ellipse$code <- "p <- ggplot(df, aes(x0 = x, y0 = as.numeric(cat), a = radius, b = radius * .6, angle = 0)) + ggforce::geom_ellipse() + coord_fixed(); p"
T$ellipse$data <- "rad"
T$link$code <- "p <- ggplot(df, aes(x, y, xend = xend, yend = yend, colour = cat)) + ggforce::geom_link(); p"
T$link$data <- "d"
T$link0$code <- "p <- ggplot(df, aes(x, y, xend = xend, yend = yend, colour = cat)) + ggforce::geom_link0(); p"
T$link0$data <- "d"
T$link2$code <- "p <- ggplot(df, aes(x, y, xend = xend, yend = yend, colour = cat)) + ggforce::geom_link2(); p"
T$link2$data <- "d"
T$vridgeline$code <- "p <- ggplot(df, aes(x = y, fill = cat)) + geom_density(alpha = .55, colour = NA) + coord_flip() + theme(legend.position = 'none'); p"
T$vridgeline$data <- "real"
T$parallel_sets$code <- "p <- ggplot(df, aes(x = x, y = cat, group = key, colour = key)) + geom_line(size = .7) + geom_point(size = 1.6) + theme(legend.position = 'none'); p"
T$parallel_sets$data <- "pset"
T$parallel_sets_axes$code <- T$parallel_sets$code
T$parallel_sets_axes$data <- "pset"
T$parallel_sets_labels$code <- T$parallel_sets$code
T$parallel_sets_labels$data <- "pset"
T$autopoint$code <- "p <- ggplot(df, aes(x = x, y = y, colour = cat)) + geom_point(size = 1.4) + theme(legend.position = 'none'); p"
T$autopoint$data <- "d"
T$autodensity$code <- "p <- ggplot(df, aes(x = y, fill = cat)) + geom_density(alpha = .5, colour = NA) + theme(legend.position = 'none'); p"
T$autodensity$data <- "real"
T$autohistogram$code <- "p <- ggplot(df, aes(x = y, fill = cat)) + geom_histogram(bins = 12, alpha = .6, colour = 'white') + theme(legend.position = 'none'); p"
T$autohistogram$data <- "real"
T$bar_connector$code <- "p <- ggplot(df, aes(x = cat, y = y, fill = cat)) + geom_col(width = .5, alpha = .45) + geom_point(size = 1.6) + geom_segment(aes(x = cat, xend = cat, y = 0, yend = y), colour = '#2f6fbf') + theme(legend.position = 'none'); p"
T$bar_connector$data <- "real"
T$regon$code <- "p <- ggplot(df, aes(x, y, group = group)) + geom_polygon(fill = '#9ec5fe', colour = '#2f6fbf'); p"
T$regon$data <- "poly"
T$spiro$code <- "df2 <- data.frame(t = seq(0, 6 * pi, length.out = 120)); df2$x <- df2$t * cos(df2$t); df2$y <- df2$t * sin(df2$t); p <- ggplot(df2, aes(x, y)) + geom_path(colour = '#2f6fbf') + coord_fixed(); p"
T$spiro$data <- "d"
T$line_rast$code <- "p <- ggplot(df, aes(x, y, colour = cat)) + ggrastr::rasterise(geom_line(size = .9), dpi = 300); p"
T$line_rast$data <- "d"
# 收尾：自定义代码统一隐藏图例；拼图轴/标签做区分；bracket 下移避免出界
T$bracket$code <- "p <- ggplot(df, aes(cat, y)) + geom_boxplot(width = .5) + ggpubr::geom_bracket(xmin = 'A', xmax = 'B', y.position = 15, label = 'p < 0.05'); p"
T$parallel_sets_axes$code <- "p <- ggplot(df, aes(x = x, y = cat)) + geom_vline(xintercept = c(1, 2, 3), colour = '#c8d3e0') + geom_text(data = subset(df, x == 1), aes(x = x, y = cat, label = cat), nudge_x = -.12, size = 2.4, colour = '#6b7480', inherit.aes = FALSE) + theme(legend.position = 'none'); p"
T$parallel_sets_labels$code <- "p <- ggplot(df, aes(x = x, y = cat, group = key, colour = key)) + geom_line(size = .7, linetype = 'dashed') + geom_point(size = 1.6) + geom_text(data = subset(df, x == 3), aes(x = x, y = cat, label = key), nudge_x = .15, size = 2.2, inherit.aes = FALSE) + theme(legend.position = 'none'); p"
# 无 sf/hexbin 时的示意：地图块面 / 六边形网格
dmap <- do.call(rbind, lapply(1:3, function(i) {
  a <- seq(0, 2 * pi, length.out = 8)
  data.frame(x = i * 2.2 + cos(a) * (1 + 0.2 * i),
             y = 1 + sin(a) * (0.8 + 0.1 * i), group = factor(i))
}))
dhex <- do.call(rbind, lapply(1:12, function(i) {
  cx <- ((i - 1) %% 4) * 1.5; cy <- ((i - 1) %/% 4) * 1.3
  a <- seq(0, 2 * pi, length.out = 7)
  data.frame(x = cx + cos(a) * .5, y = cy + sin(a) * .45, group = factor(i))
}))
dmark3 <- d[1:10, ]
T$mark_circle$data <- "mark"
T$mark_rect$code <- "xr <- range(df$x); yr <- range(df$y); p <- ggplot(df, aes(x, y, label = lab)) + annotate('rect', xmin = xr[1] - .2, xmax = xr[2] + .2, ymin = yr[1] - .2, ymax = yr[2] + .2, fill = NA, colour = '#2f6fbf', size = .7) + geom_point(size = 1.4, colour = '#2f6fbf') + geom_text(size = 2, nudge_y = .25); p"
T$mark_rect$data <- "mark3"
T$map$code <- "p <- ggplot(df, aes(x, y, group = group, fill = group)) + geom_polygon(colour = 'white', size = .4) + coord_fixed() + theme_void() + theme(legend.position = 'none'); p"
T$map$data <- "map"
T$sf$code <- "p <- ggplot(df, aes(x, y, group = group, fill = group)) + geom_polygon(colour = 'white', size = .4) + geom_point(size = .8, colour = '#4a5560') + coord_fixed() + theme_void() + theme(legend.position = 'none'); p"
T$sf$data <- "map"
T$sf_text$code <- "p <- ggplot(df, aes(x, y, group = group, fill = group)) + geom_polygon(colour = 'white', size = .4) + geom_text(aes(label = group), size = 2.6, colour = '#4a5560') + coord_fixed() + theme_void() + theme(legend.position = 'none'); p"
T$sf_text$data <- "map"
T$sf_label$code <- "p <- ggplot(df, aes(x, y, group = group, fill = group)) + geom_polygon(colour = 'white', size = .4) + geom_label(aes(label = group), size = 2.2, label.size = .1, fill = 'white') + coord_fixed() + theme_void() + theme(legend.position = 'none'); p"
T$sf_label$data <- "map"
T$hex$code <- "p <- ggplot(df, aes(x, y, group = group, fill = as.numeric(group))) + geom_polygon(colour = 'white', size = .3) + coord_fixed() + theme_void() + theme(legend.position = 'none'); p"
T$hex$data <- "hex"
T$blank$code <- "p <- ggplot(df, aes(x, y)) + geom_blank() + theme_void(); p"
T$blank$data <- "d"

# 别名/同族几何做视觉区分
T$line$code <- "p <- ggplot(df, aes(x, y, colour = cat)) + geom_line(size = .8); p"
T$line$data <- "d"
T$path$code <- "p <- ggplot(df, aes(x, y, colour = cat)) + geom_path(arrow = arrow(type = 'closed', length = unit(.07, 'inches')), size = .8); p"
T$path$data <- "d"
T$xsideline$code <- "p <- ggplot(df, aes(x, y)) + geom_point(size = 1) + ggside::geom_xsideline(aes(colour = cat)); p"
T$xsideline$data <- "d"
T$xsidepath$code <- "p <- ggplot(df, aes(x, y)) + geom_point(size = 1) + ggside::geom_xsidepath(aes(colour = cat)); p"
T$xsidepath$data <- "d"
T$dots$code <- "p <- ggplot(df, aes(x = y, fill = cat)) + ggdist::stat_dots(); p"
T$dots$data <- "real"
T$dotsinterval$code <- "p <- ggplot(df, aes(x = y, y = cat)) + ggdist::stat_dotsinterval(.width = .5); p"
T$dotsinterval$data <- "real"
# 几何类图强制等比例，避免斜线/多边形被拉扁
T$diagonal$code <- sub("; p$", " + coord_fixed(); p", T$diagonal$code)
T$diagonal_wide$code <- sub("; p$", " + coord_fixed(); p", T$diagonal_wide$code)
T$bezier$code <- sub("; p$", " + coord_fixed(); p", T$bezier$code)
T$regon$code <- sub("; p$", " + coord_fixed(); p", T$regon$code)
pick_data <- function(key) {
  switch(if (is.null(T[[key]]$data)) "d" else T[[key]]$data,
         d = d, grid = dg, poly = dpoly, many = dmany,
         ridge = dridge, ridge2 = dridge2, prop = dprop, arcbar = darcbar,
         rad = drad, scatter = dscatter, diag = ddiag, pset = dpset, real = dreal,
         bz = dbz, mark = dmark, mark2 = dmark2, mark3 = dmark3, diag4 = ddiag4,
         map = dmap, hex = dhex)
}

build_spec <- function(key) {
  # ggside 的边际 geom 定义在 GG_SIDE_THUMBS 里
  cfg <- T[[key]] %||% GG_SIDE_THUMBS[[key]] %||% list()
  aes_map <- if (isTRUE(cfg$noaes)) list() else (cfg$aes %||% c(x = "x", y = "y"))
  aes_list <- lapply(aes_map, function(col) list(map = as.character(col)))
  layer <- list(geom = key, stat = "",
                position = list(type = cfg$position %||% "", params = list()),
                aes = aes_list, params = cfg$params %||% list(), aesParams = list())
  # 垫一层不可见的 geom_blank：为「参考线 / 函数曲线」这类不吃数据的 geom 建立坐标范围。
  # 必须沿用主图层的 x/y 列（例如柱状图的 x 是离散列），否则两层的标度类型会冲突。
  # 例外：自带复杂 stat 的扩展 geom（如 ggrain 的 stat_half_ydensity）会被 blank 层
  # 干扰 orientation 推断而报错 —— 配置 noBlank = TRUE 跳过垫层。
  col_of <- function(nm, default) {
    if (!is.null(names(aes_map)) && nm %in% names(aes_map)) as.character(aes_map[[nm]]) else default
  }
  blank_aes <- list(x = list(map = col_of("x", "x")),
                    y = list(map = col_of("y", "y")))
  blank <- list(geom = "blank", stat = "", position = list(type = "", params = list()),
                aes = blank_aes, params = list(), aesParams = list())
  layers <- if (isTRUE(cfg$noBlank) || isTRUE(cfg$noaes)) list(layer) else list(blank, layer)
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
    # minimal + 坐标轴：保留轴语境，图形更像「一张图」而不是悬浮形状
    theme = list(base = cfg$theme %||% "minimal", args = list(base_size = 9),
                  elements = list(
                    legend.position = "none",
                    axis.title = list(blank = TRUE),
                    axis.text = list(type = "text", props = list(size = 6, colour = "#8a94a0")),
                    plot.margin = list(margins = list(t = 2, r = 2, b = 2, l = 2))
                  ))
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
  # 与主渲染同尺寸（192×144），避免占位图与真图混排时尺寸不一致
  rf <- ggspec_render_file(gen$eval_code, data.frame(), width = 192, height = 144, dpi = 96, format = "png")
  file.copy(rf$path, path, overwrite = TRUE); unlink(rf$path)
}

# 命名占位：画不出的 geom 也给出不同缩略图（名字 + 浅底），避免几十个条目共用一张灰图
make_named_fallback <- function(key, path) {
  d <- data.frame(x = 0, y = 0, label = key)
  code <- paste(
    "p <- ggplot(df, aes(x, y, label = label)) +",
    "  geom_text(size = 5, colour = '#6b7480') +",
    "  theme_void() +",
    "  theme(plot.background = element_rect(fill = '#f7f9fc', colour = NA),",
    "        plot.margin = margin(6, 6, 6, 6)) +",
    "  coord_cartesian(xlim = c(-1, 1), ylim = c(-1, 1))",
    sep = "\n")
  rf <- ggspec_render_file(code, list(df = d), width = 192, height = 144, dpi = 96, format = "png")
  file.copy(rf$path, path, overwrite = TRUE)
  unlink(rf$path)
}
# ---- 批量渲染 ---------------------------------------------------------------
make_placeholder(file.path(out_dir, "_placeholder.png"))

ok <- 0L; fail <- 0L
for (g in META$geoms) {
  key <- g$name
  dst <- file.path(out_dir, paste0(key, ".png"))
  if (key %in% SKIP || (is.null(T[[key]]) && is.null(GG_SIDE_THUMBS[[key]]))) {
    make_named_fallback(key, dst)
    cat(sprintf("  [占位] %s\n", key))
    next
  }
  res <- tryCatch({
    rf <- if (!is.null(T[[key]]$code)) {
      code <- T[[key]]$code
      if (!grepl("legend.position", code, fixed = TRUE)) {
        code <- sub("; p$", " + theme(legend.position = 'none', axis.title = element_blank(), axis.text = element_text(size = 6, colour = '#8a94a0'), plot.margin = margin(2, 2, 2, 2)); p", code)
      }
      ggspec_render_file(code, pick_data(key),
                         width = 192, height = 144, dpi = 96, format = "png")
    } else {
      spec <- build_spec(key)
      gen <- spec_to_code(spec, META, STATE, include_data = FALSE, with_final = TRUE)
      ggspec_render_file(gen$eval_code, pick_data(key),
                         width = 192, height = 144, dpi = 96, format = "png")
    }
    file.copy(rf$path, dst, overwrite = TRUE)
    unlink(rf$path)
    TRUE
  }, error = function(e) { cat(sprintf("  [失败] %s: %s\n", key, conditionMessage(e))); FALSE })
  if (isTRUE(res)) ok <- ok + 1L else { fail <- fail + 1L; make_named_fallback(key, dst) }
}

cat(sprintf("\n生成完成: %d 张示意图 / %d 失败 -> %s\n", ok, fail, normalizePath(out_dir)))
