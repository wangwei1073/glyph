# Glyph - 扩展包一键安装（后台任务）
# 设计：
#   1) 只允许安装「扩展清单 + 运行期依赖」里的包，杜绝任意包名；
#   2) 用独立 Rscript 进程安装，避免阻塞 httpuv 单线程服务；
#   3) 子进程把状态写进 status.txt，主进程轮询文件判断完成/失败；
#   4) 安装输出重定向到 install.log，失败时前端可直接展示。

EXT_INSTALL_STATE <- new.env(parent = emptyenv())
EXT_INSTALL_STATE$job <- NULL
EXT_INSTALL_STATE$rebuilt <- FALSE

.ext_install_pkgs <- function() {
  pkgs <- vapply(GGSPEC_EXTENSIONS, function(e) e$pkg, character(1))
  extra <- if (exists("DATA_DRIVER_PKGS", inherits = TRUE)) DATA_DRIVER_PKGS else character(0)
  unique(c(pkgs, unlist(EXT_RUNTIME_DEPS, use.names = FALSE), extra))
}

ext_install_allowed <- function(pkg) {
  pkg %in% .ext_install_pkgs()
}

ext_install_start <- function(pkg, repos = "https://cloud.r-project.org") {
  pkg <- as.character(pkg)[1]
  if (!nzchar(pkg)) stop("缺少包名")
  if (!ext_install_allowed(pkg)) stop(sprintf("不在可安装清单内：%s", pkg))
  cur <- EXT_INSTALL_STATE$job
  if (!is.null(cur) && identical(cur$status, "running")) {
    stop("已有安装任务在进行，请等待完成")
  }

  lib <- .libPaths()[1]
  dir.create(lib, showWarnings = FALSE, recursive = TRUE)
  dir <- file.path(tempdir(), paste0("glyph-install-", as.integer(stats::runif(1, 1, 1e9))))
  dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  status_file <- file.path(dir, "status.txt")
  log_file <- file.path(dir, "install.log")
  script <- file.path(dir, "install.R")

  writeLines(c(
    sprintf('pkg <- %s', deparse(pkg)),
    sprintf('lib <- %s', deparse(lib)),
    sprintf('log_file <- %s', deparse(log_file)),
    'con <- file(log_file, open = "wt", encoding = "UTF-8")',
    'sink(con, type = "output"); sink(con, type = "message")',
    'on.exit({ try(sink(type = "message"), silent = TRUE); try(sink(type = "output"), silent = TRUE); try(close(con), silent = TRUE) }, add = TRUE)',
    sprintf('cat("安装 ", pkg, " 到 ", lib, "\\n")'),
    'ok <- FALSE',
    'tryCatch({',
    sprintf('  utils::install.packages(pkg, lib = lib, repos = %s, quiet = FALSE)', deparse(repos)),
    '  ok <- requireNamespace(pkg, lib.loc = lib, quietly = TRUE)',
    '}, error = function(e) cat("ERROR:", conditionMessage(e), "\\n"))',
    sprintf('writeLines(if (ok) "ok" else "failed", %s)', deparse(status_file)),
    'cat("DONE\\n")'
  ), script, useBytes = TRUE)

  rscript <- file.path(R.home("bin"),
                       if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  ok_spawn <- tryCatch({
    system2(rscript, c("--vanilla", shQuote(script)), stdout = FALSE, stderr = FALSE, wait = FALSE)
    TRUE
  }, error = function(e) FALSE)
  if (!ok_spawn) stop("无法启动安装进程（Rscript 不可用）")

  job <- list(
    id = sprintf("I%d", as.integer(Sys.time())),
    pkg = pkg,
    status = "running",
    started = Sys.time(),
    dir = dir,
    log = log_file,
    status_file = status_file
  )
  EXT_INSTALL_STATE$job <- job
  EXT_INSTALL_STATE$rebuilt <- FALSE
  job
}

ext_install_status <- function() {
  job <- EXT_INSTALL_STATE$job
  if (is.null(job)) return(list(status = "idle"))
  if (identical(job$status, "running")) {
    if (file.exists(job$status_file)) {
      res <- tryCatch(readLines(job$status_file, warn = FALSE)[1], error = function(e) "")
      if (identical(res, "ok")) job$status <- "done"
      else if (identical(res, "failed")) job$status <- "failed"
    } else if (as.numeric(difftime(Sys.time(), job$started, units = "mins")) > 20) {
      job$status <- "failed"
      job$message <- "安装超时（20 分钟）"
    }
    EXT_INSTALL_STATE$job <- job
  }
  tail_lines <- if (file.exists(job$log)) {
    utils::tail(readLines(job$log, warn = FALSE), 30)
  } else character(0)
  list(
    id = job$id, pkg = job$pkg, status = job$status,
    message = job$message %||% NULL,
    log = paste(tail_lines, collapse = "\n")
  )
}

# 安装完成后重建注册表（只做一次）
ext_install_meta <- function(state) {
  job <- EXT_INSTALL_STATE$job
  if (is.null(job) || !identical(job$status, "done") || isTRUE(EXT_INSTALL_STATE$rebuilt)) return(NULL)
  m <- tryCatch(meta_build_lookup(ggspec_build_meta()), error = function(e) e)
  EXT_INSTALL_STATE$rebuilt <- TRUE
  if (inherits(m, "error")) {
    # 重建失败保留旧注册表，但把原因记到 job 上随状态轮询透出，不再吞掉装作成功。
    # 注意 R 值语义：job 是 EXT_INSTALL_STATE$job 的副本，必须写回去
    EXT_INSTALL_STATE$job$warning <- paste0("注册表重建失败，新装扩展可能不可见：", conditionMessage(m))
  } else {
    state$meta <- m
  }
  state$meta
}
