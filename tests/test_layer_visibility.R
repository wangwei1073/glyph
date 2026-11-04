# ggplotGUI - 图层显隐测试
# 运行: Rscript tests/test_layer_visibility.R
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) invisible(try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE))
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

META <- meta_build_lookup(ggspec_build_meta())
tmp <- file.path(tempdir(), paste0("vis-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}

layer <- function(geom, aes, visible = NULL) {
  l <- list(geom = geom, stat = "", position = list(type = "", params = list()),
            aes = aes, params = list(), aesParams = list())
  if (!is.null(visible)) l$visible <- visible
  l
}
spec_of <- function(layers) list(
  data = list(source = list(type = "dataset", name = "iris")),
  layers = layers, scales = list(), labs = list(),
  theme = list(base = "classic", args = list(), elements = list())
)
A <- function(...) lapply(list(...), function(v) list(map = v))

# ---------- 1) 两层都可见：都应出现在代码里 ----------
s1 <- spec_of(list(
  layer("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width"))),
  layer("smooth", list(x = list(map = "Petal.Length"), y = list(map = "Petal.Width")))
))
g1 <- spec_to_code(s1, META, STATE)
chk("都可见：含 geom_point", grepl("geom_point(", g1$code, fixed = TRUE))
chk("都可见：含 geom_smooth", grepl("geom_smooth(", g1$code, fixed = TRUE))

# ---------- 2) 隐藏第二层：不应出现在代码里 ----------
s2 <- spec_of(list(
  layer("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width"))),
  layer("smooth", list(x = list(map = "Petal.Length"), y = list(map = "Petal.Width")), visible = FALSE)
))
g2 <- spec_to_code(s2, META, STATE)
chk("隐藏第二层：保留 geom_point", grepl("geom_point(", g2$code, fixed = TRUE))
chk("隐藏第二层：不含 geom_smooth", !grepl("geom_smooth(", g2$code, fixed = TRUE))
chk("隐藏第二层：代码可解析", !inherits(tryCatch(parse(text = g2$eval_code), error = function(e) e), "error"))

# ---------- 3) 隐藏第一层、保留第二层 ----------
s3 <- spec_of(list(
  layer("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")), visible = FALSE),
  layer("smooth", list(x = list(map = "Petal.Length"), y = list(map = "Petal.Width")))
))
g3 <- spec_to_code(s3, META, STATE)
chk("隐藏第一层：不含 geom_point", !grepl("geom_point(", g3$code, fixed = TRUE))
chk("隐藏第一层：保留 geom_smooth", grepl("geom_smooth(", g3$code, fixed = TRUE))

# ---------- 4) 全部隐藏：应输出 geom_blank 占位且可渲染 ----------
s4 <- spec_of(list(
  layer("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")), visible = FALSE)
))
g4 <- spec_to_code(s4, META, STATE)
chk("全部隐藏：输出 geom_blank 占位", grepl("geom_blank(", g4$code, fixed = TRUE))
chk("全部隐藏：代码可解析", !inherits(tryCatch(parse(text = g4$eval_code), error = function(e) e), "error"))
rf4 <- tryCatch(ggspec_render_file(g4$eval_code, ggspec_resolve_data(s4, STATE),
                                   400, 300, 96, "png"), error = function(e) e)
chk("全部隐藏：仍可渲染（不报错）", !inherits(rf4, "error"))
if (!inherits(rf4, "error")) unlink(rf4$path)

# ---------- 5) 隐藏层不应参与 ggplot 级 aes 提升 ----------
# 两层 aes 不同 → 本就不提升；这里验证隐藏后不会因「层数变化」而误提升
s5 <- spec_of(list(
  layer("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width"))),
  layer("line", list(x = list(map = "Sepal.Length"), y = list(map = "Petal.Width")), visible = FALSE)
))
g5 <- spec_to_code(s5, META, STATE)
chk("隐藏层不参与 aes 提升：只剩 point", grepl("geom_point(", g5$code, fixed = TRUE) &&
      !grepl("geom_line(", g5$code, fixed = TRUE))
chk("隐藏层不参与 aes 提升：aes 仍正确", grepl("Sepal.Length", g5$code, fixed = TRUE))

# ---------- 6) 正常渲染（含隐藏层）不报错 ----------
s6 <- spec_of(list(
  layer("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width"))),
  layer("smooth", list(x = list(map = "Sepal.Length"), y = list(map = "Petal.Width")), visible = FALSE)
))
g6 <- spec_to_code(s6, META, STATE)
rf6 <- tryCatch(ggspec_render_file(g6$eval_code, ggspec_resolve_data(s6, STATE),
                                   400, 300, 96, "png"), error = function(e) e)
chk("含隐藏层：渲染成功", !inherits(rf6, "error"))
if (!inherits(rf6, "error")) unlink(rf6$path)

# ---------- 7) visible = TRUE 与缺省等价 ----------
s7 <- spec_of(list(
  layer("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")), visible = TRUE)
))
g7 <- spec_to_code(s7, META, STATE)
chk("visible=TRUE 等价于缺省", grepl("geom_point(", g7$code, fixed = TRUE))

# ---------- 8) 兼容旧数据（无 visible 字段）----------
s8 <- spec_of(list(
  layer("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")))
))
g8 <- spec_to_code(s8, META, STATE)
chk("无 visible 字段：正常出图", grepl("geom_point(", g8$code, fixed = TRUE))

cat(sprintf("\n===== 图层显隐: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
