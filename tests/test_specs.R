# ggplotGUI 冒烟测试：20+ 代表性 spec 全部走 生成代码 -> parse -> 渲染 PNG
# 运行: Rscript tests/test_specs.R  （在项目根目录）

if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE)
}

options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}

suppressPackageStartupMessages(library(ggplot2))

cat("== 构建注册表 ==\n")
t0 <- Sys.time()
META <- meta_build_lookup(ggspec_build_meta())
cat(sprintf("geoms=%d stats=%d scales=%d coords=%d positions=%d guides=%d themeEls=%d themes=%d anns=%d (%.1fs)\n",
            length(META$geoms), length(META$stats), length(META$scales), length(META$coords),
            length(META$positions), length(META$guides), length(META$themeElements),
            length(META$themes), length(META$annotations),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

stopifnot("geoms 应 >= 50" = length(META$geoms) >= 50)
stopifnot("scales 应 >= 100" = length(META$scales) >= 100)
stopifnot("themeElements 应 >= 120" = length(META$themeElements) >= 120)
stopifnot("themes 应 >= 9" = length(META$themes) >= 9)

STATE <- list(data_store = DataStore, raw_data = NULL)

# ---- spec 构造辅助（扁平化嵌套） --------------------------------------------
E <- function(code) list(expr = code)                               # R 表达式
A <- function(...) {  # aes 映射: A(x = "displ", colour = "class") 或 A(x = E("mean(hwy)"))
  dots <- list(...)
  lapply(dots, function(v) if (is.list(v) && !is.null(v$expr)) v else list(map = as.character(v)))
}
G <- function(geom, ...) mk_layer(geom, ...)
mk_layer <- function(geom, aes = list(), params = list(), stat = "", position = NULL,
                     aesParams = list(), showLegend = NULL, inheritAes = NULL) {
  out <- list(geom = geom, aes = aes, params = params, stat = stat)
  if (!is.null(position)) out$position <- position
  if (length(aesParams)) out$aesParams <- aesParams
  if (!is.null(showLegend)) out$showLegend <- showLegend
  if (!is.null(inheritAes)) out$inheritAes <- inheritAes
  out
}
POS <- function(type, params = list()) list(type = type, params = params)
SC <- function(aes, type, params = list(), position = NULL, secAxis = NULL) {
  out <- list(aes = aes, type = type, params = params)
  if (!is.null(position)) out$position <- position
  if (!is.null(secAxis)) out$secAxis <- secAxis
  out
}
SPECS <- list()

add_spec <- function(name, data = "mpg", layers = list(), scales = list(), coord = NULL,
                     facet = NULL, labs = list(), guides = list(), theme = NULL,
                     annotations = list(), prep = list()) {
  src <- if (identical(data, "__user__")) list(type = "user", id = "__TEST__")
         else if (is.null(data)) list(type = "none")
         else list(type = "dataset", name = data)
  spc <- list(data = c(list(source = src), prep),
              layers = layers, scales = scales,
              labs = labs, guides = guides)
  if (!is.null(coord)) spc$coord <- coord
  if (!is.null(facet)) spc$facet <- facet
  if (!is.null(theme)) spc$theme <- theme
  if (length(annotations)) spc$annotations <- annotations
  SPECS[[length(SPECS) + 1]] <<- list(name = name, spec = spc)
  invisible(NULL)
}

# ---- 定义 27 个测试用例 ------------------------------------------------------
add_spec("散点+颜色映射+平滑",
  layers = list(
    G("point", A(x = "displ", y = "hwy", colour = "class"), params = list(alpha = 0.8),
      aesParams = list(size = 2)),
    G("smooth", A(x = "displ", y = "hwy"), params = list(se = TRUE, method = "loess"))),
  labs = list(title = "发动机排量 vs 高速油耗", x = "排量 (L)", y = "MPG"))

add_spec("分组条形图+并列",
  layers = list(G("col", A(x = "class", y = "hwy", fill = "year"),
                  position = POS("dodge", list(width = 0.9)))),
  theme = list(base = "minimal", args = list(base_size = 12)))

add_spec("堆叠百分比条形",
  layers = list(G("bar", A(x = "class", fill = "drv"), position = POS("fill"))),
  theme = list(base = "bw"))

add_spec("直方图+密度",
  layers = list(
    G("histogram", A(x = "hwy"), params = list(bins = 20),
      aesParams = list(fill = "steelblue", colour = "white")),
    G("density", A(x = "hwy"), aesParams = list(colour = "red"))),
  labs = list(title = "直方图 + 核密度"))

add_spec("箱线图+小提琴+抖动点",
  layers = list(
    G("violin", A(x = "class", y = "hwy"), aesParams = list(fill = "grey90")),
    G("boxplot", A(x = "class", y = "hwy"), aesParams = list(width = 0.2),
      position = POS("dodge2")),
    G("jitter", A(x = "class", y = "hwy"), aesParams = list(width = 0.15, alpha = 0.5))))

add_spec("对数轴+次轴",
  data = "economics",
  layers = list(G("line", A(x = "date", y = "unemploy"))),
  scales = list(SC("y", "continuous", list(trans = "log10"),
                   secAxis = list(transform = "~ . / 10", name = "十分之一"))))

add_spec("分面 wrap+自由标度",
  layers = list(G("point", A(x = "displ", y = "hwy"))),
  facet = list(type = "wrap", vars = list("class"), params = list(nrow = 2, scales = "free")))

add_spec("分面 grid+边际",
  layers = list(G("point", A(x = "displ", y = "hwy"))),
  facet = list(type = "grid", rows = list("drv"), cols = list("year"),
               params = list(margins = TRUE)))

add_spec("极坐标饼图",
  layers = list(G("col", A(x = "class", y = "hwy", fill = "class"), position = POS("stack"))),
  coord = list(type = "polar", params = list(theta = "y")),
  theme = list(base = "void"))

add_spec("热力图 tile+双向渐变",
  data = "faithfuld",
  layers = list(G("tile", A(x = "eruptions", y = "waiting", fill = "density"))),
  scales = list(SC("fill", "gradient2",
                   list(low = "blue", mid = "white", high = "red",
                        midpoint = E("median(df$density)")))))

add_spec("2D 密度等高线",
  data = "faithful",
  layers = list(
    G("point", A(x = "eruptions", y = "waiting"), aesParams = list(alpha = 0.3)),
    G("density_2d", A(x = "eruptions", y = "waiting"), aesParams = list(colour = "red"))))

add_spec("误差条+pointrange",
  layers = list(G("pointrange", A(x = "class", y = E("mean(hwy)"),
                                  ymin = E("mean(hwy) - sd(hwy)"),
                                  ymax = E("mean(hwy) + sd(hwy)")))))

add_spec("stat_summary 汇总",
  layers = list(G("point", A(x = "class", y = "hwy"), stat = "summary",
                  params = list(fun = E("mean"), size = 3))))

add_spec("annotate+logticks 注释",
  layers = list(G("point", A(x = "displ", y = "hwy"))),
  annotations = list(
    list(kind = "annotate", geom = "text",
         params = list(x = 5, y = 40, label = "高油耗区", colour = "red", size = 6)),
    list(kind = "fn", name = "logticks", params = list(sides = "bl"))))

add_spec("完整主题定制+中文字体",
  data = "mtcars",
  layers = list(G("point", A(x = "wt", y = "mpg"), aesParams = list(colour = "darkred", size = 3))),
  labs = list(title = "重量与油耗", subtitle = "mtcars 数据", caption = "ggplotGUI 测试", tag = "图 1"),
  theme = list(base = "minimal", args = list(base_size = 13, base_family = "Microsoft YaHei 微软雅黑"),
               elements = list(
                 `plot.title` = list(type = "text", props = list(size = 18, face = "bold", colour = "#2C3E50")),
                 `panel.grid.minor` = list(blank = TRUE),
                 `legend.position` = "bottom",
                 `plot.margin` = list(margins = list(t = 20, r = 20, b = 10, l = 10)),
                 `axis.text.x` = list(type = "text", props = list(angle = 45, hjust = 1)))))

add_spec("reverse+sqrt 标度+固定比例",
  data = "mtcars",
  layers = list(G("point", A(x = "mpg", y = "wt"))),
  scales = list(SC("x", "reverse"), SC("y", "sqrt")),
  coord = list(type = "fixed", params = list(ratio = 1.2)))

add_spec("viridis 分箱色+size 连续标度",
  layers = list(G("point", A(x = "cty", y = "hwy", colour = "displ", size = "displ"))),
  scales = list(
    SC("colour", "viridis_b", list(option = "C")),
    SC("size", "continuous", list(range = E("c(1, 6)")))))

add_spec("ggsci 配色+ggrepel 防重叠",
  data = "mtcars",
  layers = list(
    G("point", A(x = "wt", y = "mpg")),
    G("text_repel", A(x = "wt", y = "mpg", label = E("rownames(df)")),
      params = list(max.overlaps = 20))),
  scales = list(SC("fill", "npg")))

add_spec("guides 图例隐藏",
  layers = list(G("point", A(x = "displ", y = "hwy", colour = "class"), showLegend = FALSE)),
  guides = list(colour = "none"))

add_spec("ggthemes 主题",
  data = "economics",
  layers = list(G("line", A(x = "date", y = "unemploy"))),
  theme = list(base = "economist"))

add_spec("面积图堆叠",
  data = "economics_long",
  layers = list(G("area", A(x = "date", y = "value01", fill = "variable"),
                  params = list(alpha = 0.6))))

add_spec("用户上传数据内联",
  data = "__user__",
  layers = list(G("point", A(x = "a", y = "b", colour = "c"))))

add_spec("数据加工:筛选+新增列+抽样",
  prep = list(filter = "hwy > 20", mutate = list(list(name = "ratio", expr = "hwy / displ")),
              sample = 100, seed = 42),
  layers = list(G("point", A(x = "displ", y = "ratio"))))

add_spec("多边形+路径+rug",
  data = "seals",
  layers = list(
    G("polygon", A(x = "delta_long", y = "delta_lat"), aesParams = list(fill = NA, colour = "grey50")),
    G("path", A(x = "delta_long", y = "delta_lat", group = E("1"))),
    G("rug", A(x = "delta_long"))))

add_spec("dotplot+频率多边形",
  layers = list(
    G("dotplot", A(x = "hwy"), params = list(binwidth = 1)),
    G("freqpoly", A(x = "hwy"), params = list(binwidth = 1), aesParams = list(colour = "red"))))

add_spec("QQ 图+参考线",
  layers = list(
    G("qq", A(sample = "hwy")),
    G("qq_line", A(sample = "hwy"))))

add_spec("线段+箭头",
  data = "seals",
  layers = list(
    G("segment", A(x = "long", y = "lat", xend = E("long + delta_long"), yend = E("lat + delta_lat")),
      aesParams = list(arrow = E("arrow(length = unit(0.1, 'cm'))")))))

add_spec("coord_radial 径向",
  layers = list(G("col", A(x = "class", y = "hwy", fill = "class"))),
  coord = list(type = "radial"))

add_spec("主题 value 元素",
  layers = list(G("point", A(x = "displ", y = "hwy", colour = "class"))),
  theme = list(base = "light",
               elements = list(`legend.position` = "top",
                               `panel.spacing` = list(value = 5, unit = "pt"),
                               `axis.ticks.length.x` = list(value = 4, unit = "mm"))))

# ---- 注入测试用户数据 --------------------------------------------------------
test_df <- data.frame(a = c(1, 2, 3, 4, 5), b = c(2.2, 4.1, 5.9, 8.2, 10.1),
                      c = c("甲", "乙", "甲", "乙", "甲"))
test_id <- DataStore$add(test_df, "测试数据")
for (i in seq_along(SPECS)) {
  if (identical(SPECS[[i]]$spec$data$source$type, "user")) SPECS[[i]]$spec$data$source$id <- test_id
}

# ---- 执行 -------------------------------------------------------------------
out_dir <- file.path(getwd(), "tests", "out")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

pass <- 0; fail <- 0
for (tc in SPECS) {
  cat(sprintf("\n--- %s\n", tc$name))
  gen <- tryCatch(spec_to_code(tc$spec, META, STATE), error = function(e) e)
  if (inherits(gen, "error")) {
    cat("  [生成失败]", conditionMessage(gen), "\n"); fail <- fail + 1; next
  }
  parsed <- tryCatch(parse(text = gen$code), error = function(e) e)
  if (inherits(parsed, "error")) {
    cat("  [解析失败]", conditionMessage(parsed), "\n")
    cat(gen$code, "\n"); fail <- fail + 1; next
  }
  rf <- tryCatch(ggspec_render_file(gen$eval_code, ggspec_resolve_data(tc$spec, STATE),
                                    width = 640, height = 400, dpi = 96, format = "png"),
                 error = function(e) e)
  if (inherits(rf, "error")) {
    cat("  [渲染失败]", conditionMessage(rf), "\n")
    cat(gen$code, "\n"); fail <- fail + 1; next
  }
  safe_name <- gsub("[^a-zA-Z0-9]+", "_", tc$name)
  file.copy(rf$path, file.path(out_dir, paste0(safe_name, ".png")), overwrite = TRUE)
  unlink(rf$path)
  if (length(rf$warnings)) cat("  (warnings:", paste(head(rf$warnings, 3), collapse = " | "), ")\n")
  cat("  [OK]", nchar(gen$code), "chars\n")
  pass <- pass + 1
}

cat(sprintf("\n===== 结果: %d 通过 / %d 失败 =====\n", pass, fail))
cat("输出目录:", out_dir, "\n")
quit(status = if (fail > 0) 1 else 0)
