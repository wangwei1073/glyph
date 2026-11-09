#!/usr/bin/env Rscript
# Glyph 启动入口
# 用法: Rscript run.R [--port 4321] [--host 127.0.0.1] [--dist <dir>]
#                     [--data-dir <项目目录>] [--no-browser]

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
# 归一化为绝对路径：插件/IDE 可能以任意 CWD 启动本进程，相对路径会解析错
scriptdir <- normalizePath(scriptdir, winslash = "/", mustWork = FALSE)
# --data-dir：把数据/图库/编辑记录落到指定项目目录（DSH 插件会传工作区路径）
# 不传则退回安装目录，与旧版行为一致
DATA_DIR <- .getarg("--data-dir", "")
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

# 工作区：决定数据/图库/编辑记录写到哪里。
# APP_ROOT（root）= 安装目录，只放代码与前端资源；WS_ROOT = 项目目录。
ws_layout <- WORKSPACE$init(DATA_DIR, root)
if (!nzchar(DATA_DIR %||% "")) {
  cat(sprintf("工作区: %s（未指定 --data-dir，使用安装目录）\n", ws_layout$root))
} else {
  cat(sprintf("工作区: %s\n", ws_layout$root))
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
  pin_file = ws_layout$pins_file,
  # 工作区信息（供 /api/meta 返回，前端据此显示当前项目目录）
  workspace = list(
    root = ws_layout$root,
    id = WORKSPACE$id(),
    explicit = WORKSPACE$is_explicit(),
    appRoot = root
  ),
  # 请求来源校验：只接受本机回环地址访问（--host 指定具体地址时一并加入）
  allowed_hosts = unique(c("127.0.0.1", "localhost", "::1", HOST)),
  allow_any_host = identical(HOST, "0.0.0.0")
)
# 用 environment 承载 STATE：list 是值语义，请求处理函数里的 state$meta <- ...
# 只会改局部副本，导致「安装扩展 / 启停扩展」后 /api/meta 仍返回旧注册表。
STATE <- list2env(STATE, parent = emptyenv())
dir.create(STATE$plot_dir, showWarnings = FALSE, recursive = TRUE)
# 三个 store 统一绑到工作区（并把旧的 P*.png 从根目录迁进 pins/）
bind_workspace(STATE, ws_layout$root)
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
