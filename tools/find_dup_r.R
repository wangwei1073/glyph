# 找「同名函数在多个文件里重复定义」—— R 里 source 顺序决定谁生效，
# 前面的定义会被静默覆盖，属于最容易藏 bug 的冗余。
root <- normalizePath(".")
files <- c(list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE))
defs <- list()
for (f in files) {
  lines <- readLines(f, warn = FALSE, encoding = "UTF-8")
  for (i in seq_along(lines)) {
    m <- regmatches(lines[i], regexec("^\\s*([A-Za-z_.][A-Za-z0-9_.]*)\\s*(<-|=)\\s*function", lines[i]))[[1]]
    if (length(m) == 3) {
      nm <- m[2]
      defs[[nm]] <- c(defs[[nm]] %||% character(0), sprintf("%s:%d", basename(f), i))
    }
  }
}
`%||%` <- function(a, b) if (is.null(a)) b else a
dups <- names(defs)[vapply(defs, length, integer(1)) > 1]
if (!length(dups)) {
  cat("没有重复定义\n")
} else {
  cat("重复定义:", length(dups), "个\n")
  for (nm in dups) cat(sprintf("  %-40s %s\n", nm, paste(defs[[nm]], collapse = "  vs  ")))
}
