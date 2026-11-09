# 扩展一键安装：白名单 + 任务状态（不实际联网安装）
# 运行: Rscript tests/test_ext_install.R

if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE)
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

pass <- 0; fail <- 0
ok <- function(label, cond) {
  if (isTRUE(cond)) { cat("[OK]", label, "\n"); pass <<- pass + 1 }
  else { cat("[FAIL]", label, "\n"); fail <<- fail + 1 }
}

# 1) 白名单：扩展包 + 运行期依赖可装，任意包名拒绝
ok("扩展包可安装", ext_install_allowed("ggnewscale"))
ok("运行期依赖可安装", ext_install_allowed("stringi"))
ok("未知包拒绝", !ext_install_allowed("evilpkg"))
err <- tryCatch(ext_install_start("evilpkg"), error = function(e) e)
ok("未知包启动时报错", inherits(err, "error") && grepl("不在可安装清单", conditionMessage(err)))

# 2) 初始状态 idle
st <- ext_install_status()
ok("初始状态为 idle", identical(st$status, "idle"))

# 3) 重复启动会被拒绝：构造一个假的 running 任务
EXT_INSTALL_STATE$job <- list(id = "test", pkg = "ggnewscale", status = "running",
                              started = Sys.time(),
                              log = tempfile(), status_file = tempfile())
err2 <- tryCatch(ext_install_start("stringi"), error = function(e) e)
ok("已有任务时拒绝并发安装", inherits(err2, "error") && grepl("已有安装任务", conditionMessage(err2)))

# 4) 状态文件写 ok → done；写 failed → failed
writeLines("ok", EXT_INSTALL_STATE$job$status_file)
st2 <- ext_install_status()
ok("状态文件 ok → done", identical(st2$status, "done"))
EXT_INSTALL_STATE$job <- list(id = "test2", pkg = "ggnewscale", status = "running",
                              started = Sys.time(),
                              log = tempfile(), status_file = tempfile())
writeLines("failed", EXT_INSTALL_STATE$job$status_file)
ok("状态文件 failed → failed", identical(ext_install_status()$status, "failed"))
EXT_INSTALL_STATE$job <- NULL

cat(sprintf("\n===== 扩展安装测试: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1 else 0)
