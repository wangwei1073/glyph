# 导出前检查（P0-3）：白底 / dpi / 尺寸 / 矢量 / 字体 / 字号 / 可渲染性
# 运行: Rscript tests/test_export_check.R （项目根目录）

if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE)
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

STATE <- list(version = "1.0.0", data_store = DataStore, raw_data = NULL,
              plot_dir = file.path(tempdir(), "ggcheck"),
              pin_store = Pins, edit_store = EditStore, allowed_hosts = "127.0.0.1")
META <- meta_build_lookup(ggspec_build_meta())
dir.create(STATE$plot_dir, showWarnings = FALSE, recursive = TRUE)

A <- function(...) {
  d <- list(...)
  lapply(d, function(v) list(map = as.character(v)))
}
mk_spec <- function(aes = A(x = "class", y = "hwy", fill = "class"), elements = list(),
                    layers = NULL) {
  list(
    data = list(source = list(type = "dataset", name = "mpg")),
    layers = if (is.null(layers)) list(list(geom = "boxplot", aes = aes,
                                            params = list(), stat = "")) else layers,
    scales = list(list(aes = "fill", type = "prism", params = list(palette = "floral"))),
    theme = list(base = "prism", args = list(palette = "black_and_white", base_size = 12),
                 elements = elements),
    labs = list(), guides = list(), annotations = list()
  )
}

has_issue <- function(res, id, level = NULL) {
  any(vapply(res$issues, function(i) {
    identical(i$id, id) && (is.null(level) || identical(i$level, level))
  }, logical(1)))
}

pass <- 0; fail <- 0
ok <- function(label, cond) {
  if (isTRUE(cond)) { cat("[OK]", label, "\n"); pass <<- pass + 1 }
  else { cat("[FAIL]", label, "\n"); fail <<- fail + 1 }
}

# 1) 正常导出（300dpi PNG）
r <- ggspec_export_check(mk_spec(), META, STATE, 1600, 1000, 300, "png")
ok("正常图：检查通过", isTRUE(r$ok))
ok("正常图：白底", has_issue(r, "background", "pass"))
ok("正常图：dpi 达标", has_issue(r, "dpi", "pass"))
ok("正常图：物理尺寸信息", isTRUE(r$info$widthMm > 100 && r$info$widthMm < 180))

# 2) 150dpi → warn
r <- ggspec_export_check(mk_spec(), META, STATE, 900, 560, 150, "png")
ok("低 dpi：给出 warn", has_issue(r, "dpi", "warn"))

# 3) 透明背景 → fail
r <- ggspec_export_check(
  mk_spec(elements = list(plot.background = list(type = "rect",
                                                props = list(fill = "transparent")))),
  META, STATE, 1600, 1000, 300, "png")
ok("透明背景：判定 fail", !isTRUE(r$ok) && has_issue(r, "background", "fail"))

# 4) 字号过小 → warn
r <- ggspec_export_check(
  mk_spec(elements = list(axis.text = list(type = "text", props = list(size = 3)))),
  META, STATE, 1600, 1000, 300, "png")
ok("小字号：给出 warn", has_issue(r, "textsize", "warn"))

# 5) 空画布 → fail
r <- ggspec_export_check(list(data = list(source = list(type = "none")), layers = list()),
                         META, STATE, 1600, 1000, 300, "png")
ok("空画布：判定 fail", !isTRUE(r$ok) && has_issue(r, "layers", "fail"))

# 6) 能构造但画不出来（离散值喂给数值美学的 boxplot 统计）→ fail
aes <- A(x = "class", y = "hwy", fill = "class")
aes$ymax <- list(map = "class")
r <- ggspec_export_check(mk_spec(aes = aes), META, STATE, 1600, 1000, 300, "png")
ok("渲染期错误：判定 fail", !isTRUE(r$ok) && has_issue(r, "render", "fail"))

# 7) PDF → 矢量通过
r <- ggspec_export_check(mk_spec(), META, STATE, 1600, 1000, 300, "pdf")
ok("PDF：矢量格式通过", has_issue(r, "vector", "pass"))

cat(sprintf("\n===== 导出检查测试: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1 else 0)
