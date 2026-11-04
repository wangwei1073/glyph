#!/usr/bin/env Rscript
# ggplotGUI 启动入口
# 用法: Rscript run.R [--port 4321] [--host 127.0.0.1] [--dist <dir>] [--no-browser]

# ---- 编码自举（必须最先执行，纯 ASCII） ----
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE)
  invisible(try(Sys.setlocale("LC_COLLATE", "C"), silent = TRUE))
}

.args <- commandArgs(trailingOnly = TRUE)
.getarg <- function(flag, default) {
  i <- match(flag, .args)
  if (!is.na(i) && length(.args) >= i + 1) return(.args[i + 1])
  default
}
PORT <- as.integer(.getarg("--port", "4321"))
HOST <- .getarg("--host", "127.0.0.1")
argsfile <- grep("^--file=", commandArgs(FALSE), value = TRUE)
scriptdir <- if (length(argsfile)) dirname(sub("^--file=", "", argsfile[1])) else getwd()
DIST <- normalizePath(file.path(scriptdir, "dist"), mustWork = FALSE)
if (!dir.exists(DIST)) DIST <- "dist"

options(stringsAsFactors = FALSE)
Sys.setenv(TZ = "UTC")

cat("ggplotGUI - ggplot2 全功能 GUI 绘图工具\n")
cat("R:", R.version.string, "| ggplot2:", as.character(packageVersion("ggplot2")), "\n")

suppressPackageStartupMessages({
  library(ggplot2)
  library(jsonlite)
})
# 提前加载可能用到的扩展（缺失则跳过）
for (p in c("ggrepel", "ggsci", "ggthemes", "patchwork", "plotly", "ragg",
            "readr", "readxl", "scales")) {
  if (requireNamespace(p, quietly = TRUE)) suppressPackageStartupMessages(do.call(library, list(p)))
}

root <- scriptdir
for (f in sort(list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8", local = FALSE)
}

t0 <- Sys.time()
STATE <- list(
  version = "1.0.0",
  meta = NULL,
  data_store = DataStore,
  pin_store = Pins,
  edit_store = EditStore,
  dist_dir = DIST,
  raw_data = NULL,
  plot_dir = file.path(tempdir(), "ggplotgui-plots"),
  pin_file = file.path(root, "pins.json"),
  # 请求来源校验：只接受本机回环地址访问（--host 指定具体地址时一并加入）
  allowed_hosts = unique(c("127.0.0.1", "localhost", "::1", HOST)),
  allow_any_host = identical(HOST, "0.0.0.0")
)
dir.create(STATE$plot_dir, showWarnings = FALSE, recursive = TRUE)
Pins$bind(STATE$pin_file)
EditStore$bind(file.path(root, "edits.json"))
cat("构建元数据注册表 ...\n")
STATE$meta <- meta_build_lookup(ggspec_build_meta())
cat(sprintf("注册表就绪: %d geoms / %d stats / %d scales / %d coords / %d 主题元素  (%.1fs)\n",
            length(STATE$meta$geoms), length(STATE$meta$stats), length(STATE$meta$scales),
            length(STATE$meta$coords), length(STATE$meta$themeElements),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

url <- sprintf("http://%s:%d", HOST, PORT)
cat(sprintf("服务已启动: %s  (Ctrl+C 退出)\n", url))
if (!interactive() && !"--no-browser" %in% .args) {
  tryCatch(utils::browseURL(url), error = function(e) NULL)
}

httpuv::runServer(HOST, PORT, ggspec_api_app(STATE))
