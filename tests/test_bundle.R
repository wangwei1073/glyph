# 可复现包（P1-3）：图 + 数据 + 代码 + sessionInfo + 图注 + 项目文件
# 运行: Rscript tests/test_bundle.R （项目根目录）

if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE)
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

dir <- file.path(tempdir(), paste0("ggbundle-test-", as.integer(runif(1, 1, 1e9))))
DataStore$bind(dir)
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = file.path(tempdir(), "ggbundle-out"),
              allowed_hosts = "127.0.0.1")
dir.create(STATE$plot_dir, showWarnings = FALSE, recursive = TRUE)
META <- meta_build_lookup(ggspec_build_meta())

pass <- 0; fail <- 0
ok <- function(label, cond) {
  if (isTRUE(cond)) { cat("[OK]", label, "\n"); pass <<- pass + 1 }
  else { cat("[FAIL]", label, "\n"); fail <<- fail + 1 }
}

A <- function(...) {
  d <- list(...)
  lapply(d, function(v) list(map = as.character(v)))
}

mk <- function(src, layers) {
  list(data = list(source = src),
       layers = layers,
       scales = list(), theme = list(base = "prism", args = list(), elements = list()),
       labs = list(title = "测试图"), guides = list(), annotations = list())
}

# ---- 1. 上传数据：应带 data.csv，代码读它 ----
d <- data.frame(group = c("A", "B", "A", "B"), value = c(1, 2, 3, 4))
id <- DataStore$add(d, "小数据")
spec <- mk(list(type = "user", id = id),
           list(list(geom = "col", aes = A(x = "group", y = "value"), params = list(), stat = "")))
res <- tryCatch(ggspec_bundle(spec, META, STATE, 900, 560, 300, "png"), error = function(e) e)
ok("用户数据：打包成功", !inherits(res, "error"))
if (!inherits(res, "error")) {
  files <- utils::unzip(res$path, list = TRUE)$Name
  ok("包含 figure.png", "figure.png" %in% files)
  ok("包含 figure.pdf", "figure.pdf" %in% files)
  ok("包含 data.csv", "data.csv" %in% files)
  ok("包含 figure.R", "figure.R" %in% files)
  ok("包含 sessionInfo/caption/README/project",
     all(c("sessionInfo.txt", "caption.md", "README.txt", "project.json") %in% files))
  exdir <- file.path(tempdir(), paste0("unz-", as.integer(runif(1, 1, 1e9))))
  utils::unzip(res$path, exdir = exdir)
  code <- paste(readLines(file.path(exdir, "figure.R"), warn = FALSE), collapse = "\n")
  ok("代码从 data.csv 读数据", grepl('read.csv("data.csv"', code, fixed = TRUE))
  ok("代码含主题调用", grepl("theme_prism(", code, fixed = TRUE))
  cap <- paste(readLines(file.path(exdir, "caption.md"), warn = FALSE), collapse = "\n")
  ok("图注含数据来源", grepl("数据来源", cap, fixed = TRUE))
  ok("图注含尺寸", grepl("mm @ 300 dpi", cap, fixed = TRUE))
  pj <- jsonlite::fromJSON(file.path(exdir, "project.json"), simplifyVector = FALSE)
  ok("项目文件可解析", identical(pj$app, "ggplotgui") && !is.null(pj$spec))
  ok("项目文件内嵌数据", !is.null(pj$data$csv) && nzchar(pj$data$csv))
  unlink(exdir, recursive = TRUE)
}

# ---- 2. 内置数据集：不需要 data.csv ----
spec2 <- mk(list(type = "dataset", name = "mpg"),
            list(list(geom = "point", aes = A(x = "displ", y = "hwy"), params = list(), stat = "")))
res2 <- tryCatch(ggspec_bundle(spec2, META, STATE, 800, 500, 300, "png"), error = function(e) e)
ok("数据集：打包成功", !inherits(res2, "error"))
if (!inherits(res2, "error")) {
  files2 <- utils::unzip(res2$path, list = TRUE)$Name
  ok("数据集：不含 data.csv", !"data.csv" %in% files2)
  ok("数据集：代码用 mpg", {
    ex <- file.path(tempdir(), paste0("unz2-", as.integer(runif(1, 1, 1e9))))
    utils::unzip(res2$path, exdir = ex)
    code <- paste(readLines(file.path(ex, "figure.R"), warn = FALSE), collapse = "\n")
    unlink(ex, recursive = TRUE)
    grepl("df <- mpg", code, fixed = TRUE)
  })
}

# ---- 3. 拼图模式应明确拒绝 ----
spec3 <- list(data = list(source = list(type = "none")), layers = list(),
              combine = list(active = TRUE, slots = list(list(pin = "P1", op = "+"))))
err <- tryCatch(ggspec_bundle(spec3, META, STATE, 800, 500, 300, "png"), error = function(e) e)
ok("拼图模式：给出明确错误", inherits(err, "error") && grepl("拼图", conditionMessage(err)))

cat(sprintf("\n===== 可复现包测试: %d 通过 / %d 失败 =====\n", pass, fail))
unlink(dir, recursive = TRUE)
quit(status = if (fail > 0) 1 else 0)
