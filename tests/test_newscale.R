# 多重标度（ggnewscale）测试
# 运行: Rscript tests/test_newscale.R
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) invisible(try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE))
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

# 可选扩展：未安装时跳过
if (!requireNamespace("ggnewscale", quietly = TRUE)) {
  cat("[SKIP] 缺少可选包：ggnewscale（安装后再跑本套件）\n")
  quit(status = 0)
}

META <- meta_build_lookup(ggspec_build_meta())
tmp <- file.path(tempdir(), paste0("ns-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}
L <- function(geom, aes, reset = NULL, params = list()) {
  l <- list(geom = geom, stat = "", position = list(type = "", params = list()),
            aes = aes, params = params, aesParams = list())
  if (!is.null(reset)) l$resetScale <- reset
  l
}
spec_of <- function(layers) list(
  data = list(source = list(type = "dataset", name = "mpg")),
  layers = layers, scales = list(), labs = list(),
  theme = list(base = "", args = list(), elements = list()))

A <- list(x = list(map = "displ"), y = list(map = "hwy"))

# ---------- 1) 无 resetScale：不产生 new_scale ----------
cat("--- 基础 ---\n")
g0 <- spec_to_code(spec_of(list(L("point", c(A, list(fill = list(map = "drv")))))), META, STATE)
chk("无 resetScale 不产生 new_scale", !grepl("new_scale", g0$code, fixed = TRUE))
chk("无 resetScale 不含 library(ggnewscale)", !grepl("library(ggnewscale)", g0$code, fixed = TRUE))

# ---------- 2) 单层 resetScale = fill ----------
cat("\n--- 两层多重标度 ---\n")
g1 <- spec_to_code(spec_of(list(
  L("point", c(A, list(fill = list(map = "drv"))), params = list(shape = 21)),
  L("point", c(A, list(fill = list(map = "class"))), reset = list("fill"), params = list(shape = 22))
)), META, STATE)
chk("含 library(ggnewscale)", grepl("library(ggnewscale)", g1$code, fixed = TRUE))
chk("含 ggnewscale::new_scale_fill()", grepl("ggnewscale::new_scale_fill()", g1$code, fixed = TRUE))

# 位置必须在两个 geom 之间
lines <- strsplit(g1$code, "\n")[[1]]
i_first <- grep("geom_point", lines)[1]
i_reset <- grep("new_scale_fill", lines)[1]
i_last <- grep("geom_point", lines)[2]
chk("new_scale 位于两个图层之间", !is.na(i_reset) && i_reset > i_first && i_reset < i_last)

chk("代码可解析", !inherits(tryCatch(parse(text = g1$eval_code), error = function(e) e), "error"))

# ---------- 3) 渲染验证 ----------
cat("\n--- 渲染 ---\n")
sp1 <- spec_of(list(
  L("point", c(A, list(fill = list(map = "drv"))), params = list(shape = 21, size = 2)),
  L("point", c(A, list(fill = list(map = "class"))), reset = list("fill"), params = list(shape = 22, size = 2))
))
rf1 <- tryCatch(ggspec_render_file(g1$eval_code, ggspec_resolve_data(sp1, STATE), 400, 300, 96, "png"),
                error = function(e) e)
chk("多重标度渲染成功", !inherits(rf1, "error"))
if (!inherits(rf1, "error")) unlink(rf1$path)
if (inherits(rf1, "error")) cat("     ", substr(conditionMessage(rf1), 1, 90), "\n")

# ---------- 4) 多个标度同时重置 ----------
cat("\n--- 多标度 ---\n")
g2 <- spec_to_code(spec_of(list(
  L("point", c(A, list(fill = list(map = "drv"), colour = list(map = "drv")))),
  L("point", c(A, list(fill = list(map = "class"), colour = list(map = "class"))),
    reset = list("fill", "colour"))
)), META, STATE)
chk("同时含 new_scale_fill", grepl("new_scale_fill", g2$code, fixed = TRUE))
chk("同时含 new_scale_colour", grepl("new_scale_colour", g2$code, fixed = TRUE))

# ---------- 5) 字符串形式的 resetScale（兼容）----------
cat("\n--- 兼容性 ---\n")
g3 <- spec_to_code(spec_of(list(
  L("point", c(A, list(fill = list(map = "drv")))),
  L("point", c(A, list(fill = list(map = "class"))), reset = "fill")
)), META, STATE)
chk("字符串形式 resetScale 也支持", grepl("new_scale_fill", g3$code, fixed = TRUE))

# ---------- 6) 空数组 / 空字符串不产生 ----------
g4 <- spec_to_code(spec_of(list(
  L("point", c(A, list(fill = list(map = "drv")))),
  L("point", c(A, list(fill = list(map = "class"))), reset = list())
)), META, STATE)
chk("空 resetScale 不产生 new_scale", !grepl("new_scale", g4$code, fixed = TRUE))

g5 <- spec_to_code(spec_of(list(
  L("point", c(A, list(fill = list(map = "drv")))),
  L("point", c(A, list(fill = list(map = "class"))), reset = list(""))
)), META, STATE)
chk("空字符串不产生 new_scale", !grepl("new_scale", g5$code, fixed = TRUE))

# ---------- 7) 与图层显隐共存 ----------
cat("\n--- 与显隐共存 ---\n")
g6 <- spec_to_code(spec_of(list(
  L("point", c(A, list(fill = list(map = "drv")))),
  L("point", c(A, list(fill = list(map = "class"))), reset = list("fill"))
)), META, STATE)
sp6 <- spec_of(list(
  L("point", c(A, list(fill = list(map = "drv")))),
  L("point", c(A, list(fill = list(map = "class"))), reset = list("fill"))
))
sp6$layers[[1]]$visible <- FALSE
g7 <- spec_to_code(sp6, META, STATE)
chk("隐藏首层后仍可生成", !inherits(tryCatch(parse(text = g7$eval_code), error = function(e) e), "error"))

# ---------- 8) 扩展状态 ----------
cat("\n--- 扩展状态 ---\n")
chk("extensions 含 ggnewscale", !is.null(META$extensions$ggnewscale))
chk("ggnewscale 已安装", .ggspec_has_pkg("ggnewscale"))

cat(sprintf("\n===== 多重标度: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
