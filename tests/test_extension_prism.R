# ggplotGUI 扩展测试：ggprism 集成（主题 / 标度 / guide / 注释）
# 运行: Rscript tests/test_extension_prism.R （项目根目录）
# 未安装 ggprism 时应静默跳过（只断言注册表里没有 prism 条目）。

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
META <- meta_build_lookup(ggspec_build_meta())
has_pkg <- requireNamespace("ggprism", quietly = TRUE)

is_prism <- function(x) identical(x$package %||% "", "ggprism")
scales <- Filter(is_prism, META$scales)
themes <- Filter(is_prism, META$themes)
guides <- Filter(is_prism, META$guides)
anns <- Filter(is_prism, META$annotations)

if (!has_pkg) {
  stopifnot("未装 ggprism 时不应有 prism 条目" =
              length(scales) == 0 && length(themes) == 0 &&
              length(guides) == 0 && length(anns) == 0)
  cat("ggprism 未安装：跳过集成断言（降级路径正常）\n")
  quit(status = 0)
}

cat(sprintf("prism: %d scales / %d themes / %d guides / %d annotations\n",
            length(scales), length(themes), length(guides), length(anns)))

# ---- 1. 注册表条目 -----------------------------------------------------------
stopifnot("应有 3 个 prism 标度（colour + fill + shape，color 别名已去重）" = length(scales) == 3)
aes_kinds <- vapply(scales, function(s) s$aes, "")
stopifnot("colour 标度" = sum(aes_kinds == "colour") == 1)
stopifnot("fill 标度" = sum(aes_kinds == "fill") == 1)
stopifnot("shape 标度" = sum(aes_kinds == "shape") == 1)

pal_n <- vapply(scales, function(s) length(s$params$palette$options %||% list()), 0L)
names(pal_n) <- vapply(scales, function(s) s$fn, "")
cat("palette options:", paste(names(pal_n), pal_n, sep = "=", collapse = ", "), "\n")
stopifnot("fill 调色板应 >= 40" = pal_n[["scale_fill_prism"]] >= 40)
stopifnot("colour 调色板应 >= 60" = pal_n[["scale_colour_prism"]] >= 60)
stopifnot("shape 调色板应为 3" = pal_n[["scale_shape_prism"]] == 3)
stopifnot("palette 应为下拉控件" = all(vapply(scales, function(s) s$params$palette$widget == "select", TRUE)))

stopifnot("应有 theme_prism" = length(themes) == 1 && themes[[1]]$name == "prism")
targs <- themes[[1]]$args
pal_arg <- Filter(function(a) identical(a$name, "palette"), targs)
stopifnot("theme_prism 的 palette 应为 65 选 1" =
            length(pal_arg) == 1 && pal_arg[[1]]$widget == "select" &&
            length(pal_arg[[1]]$options) >= 60)
stopifnot("theme_prism 应保留 border / axis_text_angle 参数" =
            any(vapply(targs, function(a) a$name == "border", TRUE)) &&
            any(vapply(targs, function(a) a$name == "axis_text_angle", TRUE)))

stopifnot("应有 4 个 prism guide" = length(guides) == 4)
stopifnot("prism guide 名称" =
            setequal(vapply(guides, function(g) g$name, ""),
                     c("prism_minor", "prism_offset", "prism_offset_minor", "prism_bracket")))
stopifnot("prism_bracket 应有 width/outside 参数" =
            all(c("width", "outside") %in% names(
              Filter(function(g) g$name == "prism_bracket", guides)[[1]]$params)))

stopifnot("应有 annotation_ticks" = length(anns) == 1 && anns[[1]]$name == "ticks")
stopifnot("annotation_ticks 的 type 是下拉" =
            anns[[1]]$params$type$widget == "select")
stopifnot("annotation_ticks 不暴露需要 unit() 的参数" =
            !any(c("tick.length", "minor.length") %in%
                   names(anns[[1]]$params)))

stopifnot("extensions.ggprism 应为 TRUE" = isTRUE(META$extensions$ggprism %||% FALSE))
stopifnot("prism 主题元素应进注册表" =
            any(grepl("^prism\\.ticks\\.length", vapply(META$themeElements, function(e) e$name, ""))))

# ---- 2. 代码生成 -------------------------------------------------------------
STATE <- list(data_store = DataStore, raw_data = NULL)
A <- function(...) {
  dots <- list(...)
  lapply(dots, function(v) if (is.list(v) && !is.null(v$expr)) v else list(map = as.character(v)))
}
base_spec <- function(...) {
  s <- list(
    data = list(source = list(type = "dataset", name = "ToothGrowth")),
    layers = list(list(geom = "boxplot",
                       aes = A(x = "dose", y = "len", fill = "supp"),
                       params = list(), stat = "")),
    scales = list(), labs = list(), guides = list(), annotations = list()
  )
  over <- list(...)
  for (nm in names(over)) s[[nm]] <- over[[nm]]
  s
}

spec1 <- base_spec(
  scales = list(list(aes = "fill", type = "prism", params = list(palette = "floral"))),
  theme = list(base = "prism", args = list(palette = "floral", base_size = 12))
)
gen1 <- spec_to_code(spec1, META, STATE)
needles <- c("library(ggprism)", 'scale_fill_prism(palette = "floral")',
             'theme_prism(palette = "floral", base_size = 12)')
missing <- needles[!vapply(needles, grepl, logical(1), x = gen1$code, fixed = TRUE)]
if (length(missing)) {
  cat(gen1$code, "\n")
  stop("生成代码缺少: ", paste(missing, collapse = ", "))
}
cat("codegen theme+scale: OK\n")

spec2 <- base_spec(guides = list(x = list(type = "prism_minor", params = list())))
gen2 <- spec_to_code(spec2, META, STATE)
stopifnot("guide 代码缺少" = grepl("guide_prism_minor()", gen2$code, fixed = TRUE))
stopifnot("guide 代码缺少 library(ggprism)" = grepl("library(ggprism)", gen2$code, fixed = TRUE))
cat("codegen guide: OK\n")

spec3 <- base_spec(annotations = list(list(kind = "fn", name = "ticks",
                                           params = list(sides = "bl", type = "both"))))
gen3 <- spec_to_code(spec3, META, STATE)
stopifnot("注释代码缺少" = grepl('annotation_ticks(sides = "bl", type = "both")',
                                gen3$code, fixed = TRUE))
cat("codegen annotation: OK\n")

# ---- 3. 渲染 ---------------------------------------------------------------
out_dir <- file.path(getwd(), "tests", "out")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)
cases <- list(
  list(name = "prism_theme_scale", gen = gen1, spec = spec1),
  list(name = "prism_guide_minor", gen = gen2, spec = spec2),
  list(name = "prism_annotation_ticks", gen = gen3, spec = spec3)
)
pass <- 0; fail <- 0
for (cs in cases) {
  cat(sprintf("\n--- %s\n", cs$name))
  rf <- tryCatch(ggspec_render_file(cs$gen$eval_code, ggspec_resolve_data(cs$spec, STATE),
                                    width = 640, height = 400, dpi = 96, format = "png"),
                 error = function(e) e)
  if (inherits(rf, "error")) {
    cat("  [渲染失败]", conditionMessage(rf), "\n"); fail <- fail + 1; next
  }
  file.copy(rf$path, file.path(out_dir, paste0(cs$name, ".png")), overwrite = TRUE)
  unlink(rf$path)
  cat("  [OK] warnings:", length(rf$warnings), "\n")
  pass <- pass + 1
}

cat(sprintf("\n===== 结果: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1 else 0)
