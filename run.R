#!/usr/bin/env Rscript
# Glyph 启动入口
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

cat("Glyph - ggplot2 全功能 GUI 绘图工具\n")
cat("R:", R.version.string, "| ggplot2:", as.character(packageVersion("ggplot2")), "\n")

suppressPackageStartupMessages({
  library(ggplot2)
  library(jsonlite)
})
# 提前加载可能用到的扩展（缺失则跳过）
# 第一批：ggrepel / ggthemes / ggsci / ggprism + ggpubr / ggbeeswarm / ggtext / ggside
# 第二批：ggstats / ggridges / ggh4x / ggnewscale
# 第三批：ggdist / ggforce / ggbreak / hrbrthemes
for (p in c("ggrepel", "ggsci", "ggthemes", "ggprism", "ggpubr", "ggbeeswarm",
            "ggtext", "ggside", "ggstats", "ggridges", "ggh4x", "ggnewscale",
            "ggdist", "ggforce", "ggbreak", "hrbrthemes",
            "patchwork", "plotly", "ragg",
            "readr", "readxl", "scales")) {
  if (requireNamespace(p, quietly = TRUE)) suppressPackageStartupMessages(do.call(library, list(p)))
}

root <- scriptdir
for (f in sort(list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8", local = FALSE)
}
# 上传/粘贴的数据落盘，重启后仍能打开引用它的项目
DataStore$bind(file.path(root, "userdata"))

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
# 扩展开关状态（只记录被关闭的扩展；文件不存在则全部启用）
ext_state_bind(file.path(root, "extensions.json"))
cat("构建元数据注册表 ...\n")
STATE$meta <- meta_build_lookup(ggspec_build_meta())
cat(sprintf("注册表就绪: %d geoms / %d stats / %d scales / %d coords / %d 主题元素  (%.1fs)\n",
            length(STATE$meta$geoms), length(STATE$meta$stats), length(STATE$meta$scales),
            length(STATE$meta$coords), length(STATE$meta$themeElements),
            as.numeric(difftime(Sys.time(), t0, units = "secs"))))

url <- sprintf("http://%s:%d", HOST, PORT)
cat(sprintf("服务已启动: %s  (Ctrl+C 退出，或在界面左下角点退出按钮)\n", url))
if (!interactive() && !"--no-browser" %in% .args) {
  tryCatch(utils::browseURL(url), error = function(e) NULL)
}

## 主循环：不用 httpuv::runServer（C 层阻塞，无法从请求内部停止），
## 改用 startServer + service() 短超时轮询，收到 /api/shutdown 后优雅退出。
## 三个要点（都已实测，缺一个进程就退不掉）：
##   1) 退出标志用 environment 传递 —— STATE 是 list（值语义），
##      写局部副本主循环读不到；
##   2) service 超时要短（20ms），长超时会让 httpuv 在 C 层久留、读不到标志；
##   3) 命中后仍要再 service 一次，把「正在退出」的响应真正发回浏览器。
STATE$shutdown_flag <- new.env(parent = emptyenv())
STATE$shutdown_flag$requested <- FALSE
srv <- httpuv::startServer(HOST, PORT, ggspec_api_app(STATE))
on.exit(tryCatch(httpuv::stopServer(srv), error = function(e) NULL), add = TRUE)

## 父进程监控（供 IDE 插件使用）：--heartbeat
## 思路：扩展每隔 N 秒调一次 /api/heartbeat；若超过阈值没收到，说明 IDE 已退出，
## 本进程自行结束。之所以不用 PID 判断：扩展宿主只是 IDE 的子孙进程，
## 其 PID 在宿主重启后会变，且 tasklist 在不同会话下结果不可靠。
## 之所以不用 stdin：R 无非阻塞读，阻塞读会卡死 service 循环。
use_heartbeat <- "--heartbeat" %in% .args
.hb_timeout <- {
  i <- match("--heartbeat-timeout", .args)
  if (!is.na(i) && length(.args) >= i + 1) suppressWarnings(as.numeric(.args[i + 1])) else 60
}
if (use_heartbeat) {
  STATE$heartbeat_env <- new.env(parent = emptyenv())
  assign("last", Sys.time(), envir = STATE$heartbeat_env)
  cat(sprintf("已启用心跳监控（%g 秒无心跳即退出）\n", .hb_timeout))
}

.chk <- 0L
repeat {
  for (i in seq_len(5)) tryCatch(httpuv::service(20), error = function(e) NULL)
  if (isTRUE(STATE$shutdown_flag$requested)) break
  if (use_heartbeat) {
    .chk <- .chk + 1L
    if (.chk >= 20L) {          # 约每 2 秒检查一次
      .chk <- 0L
      last <- get("last", envir = STATE$heartbeat_env)
      idle <- as.numeric(difftime(Sys.time(), last, units = "secs"))
      if (idle > .hb_timeout) {
        cat(sprintf("超过 %g 秒未收到心跳，判定宿主已退出，主动停止服务\n", .hb_timeout))
        break
      }
    }
  }
}
tryCatch(httpuv::service(50), error = function(e) NULL)
tryCatch(httpuv::stopServer(srv), error = function(e) NULL)
cat("服务已退出。\n")
