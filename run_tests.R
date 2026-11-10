#!/usr/bin/env Rscript
# Glyph 测试统一入口 —— 依次以子进程运行 tests/ 下的全部测试，汇总结果并给出退出码。
#
# 用法（在项目根目录）:
#   Rscript run_tests.R            # 全部测试
#   Rscript run_tests.R db         # 只跑文件名含 "db" 的测试（子串过滤）
#   Rscript run_tests.R --list     # 只列出要跑的文件，不运行
#
# 套件约定：只认 tests/test_*.R 与 tests/test_*.mjs。
# tests/ 下的 diag_*、e2e_*、review_findings.R 是一次性诊断脚本，不属于套件。

# ---- 定位仓库根（插件/IDE 可能以任意 CWD 启动）----
argsfile <- grep("^--file=", commandArgs(FALSE), value = TRUE)
scriptdir <- if (length(argsfile)) dirname(sub("^--file=", "", argsfile[1])) else getwd()
scriptdir <- normalizePath(scriptdir, winslash = "/", mustWork = FALSE)
setwd(scriptdir)

args <- commandArgs(trailingOnly = TRUE)
filter <- ""
if (length(args)) {
  nf <- args[!startsWith(args, "--")]
  if (length(nf)) filter <- nf[1]
}
list_only <- "--list" %in% args

r_tests <- sort(list.files("tests", pattern = "^test_.+\\.R$", full.names = TRUE))
mjs_tests <- sort(list.files("tests", pattern = "^test_.+\\.mjs$", full.names = TRUE))
if (nzchar(filter)) {
  r_tests <- grep(filter, r_tests, value = TRUE)
  mjs_tests <- grep(filter, mjs_tests, value = TRUE)
}

node_path <- Sys.which("node")
node_ok <- nzchar(node_path)

cat("Glyph 测试套件\n")
cat(sprintf("R: %s\nnode: %s\n",
            R.version.string,
            if (node_ok) "可用" else "未找到（.mjs 测试记为 SKIP）"))
cat(sprintf("待运行: %d 个 R 测试 + %d 个前端测试\n\n",
            length(r_tests), length(mjs_tests)))

if (list_only) {
  for (f in c(r_tests, mjs_tests)) cat(" ", f, "\n")
  quit(status = 0)
}

results <- list()   # list(file, status, secs)；status=0L 通过 / NA 表示 SKIP
t_all <- Sys.time()

run_one <- function(cmd, f) {
  cat(sprintf("───── %s\n", f))
  t0 <- Sys.time()
  status <- suppressWarnings(system2(cmd, shQuote(f)))
  dt <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  if (is.na(status)) status <- 1L
  results[[length(results) + 1L]] <<- list(file = f, status = status, secs = dt)
  cat(sprintf("  → %s (%.1fs)\n\n",
              if (identical(status, 0L)) "PASS" else sprintf("FAIL (exit %d)", status), dt))
}

rspec <- file.path(R.home("bin"), "Rscript")
for (f in r_tests) run_one(rspec, f)

for (f in mjs_tests) {
  if (node_ok) run_one(node_path, f) else {
    cat(sprintf("───── %s\n  → SKIP（未找到 node）\n\n", f))
    results[[length(results) + 1L]] <<- list(file = f, status = NA, secs = NA)
  }
}

## ---- 汇总 ----
npass <- sum(vapply(results, function(r) identical(r$status, 0L), TRUE))
nskip <- sum(vapply(results, function(r) is.na(r$status), TRUE))
nfail <- length(results) - npass - nskip
elapsed <- as.numeric(difftime(Sys.time(), t_all, units = "secs"))

cat("════════════════════════════════════════\n")
if (nfail) for (r in results) if (!identical(r$status, 0L) && !is.na(r$status))
  cat(sprintf("  失败: %s\n", r$file))
if (nskip) for (r in results) if (is.na(r$status)) cat(sprintf("  跳过: %s\n", r$file))
cat(sprintf("总计: %d 通过 / %d 失败 / %d 跳过，耗时 %.0fs\n",
            npass, nfail, nskip, elapsed))
quit(status = if (nfail > 0) 1 else 0)
