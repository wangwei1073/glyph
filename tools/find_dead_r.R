# 找出「定义了但全仓库没有引用」的 R 函数。
# 注意：R 有动态调用（get/do.call/switch 按字符串），所以零引用只是「候选」，
# 必须人工确认后才可删。
root <- normalizePath(".")
files <- c(
  list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE),
  file.path(root, "run.R")
)
testFiles <- list.files(file.path(root, "tests"), pattern = "\\.R$", full.names = TRUE)
toolFiles <- list.files(file.path(root, "tools"), pattern = "\\.R$", full.names = TRUE)
allRefFiles <- c(files, testFiles, toolFiles)

# 1) 收集函数定义
defs <- list()  # name -> file
for (f in files) {
  lines <- readLines(f, warn = FALSE, encoding = "UTF-8")
  for (i in seq_along(lines)) {
    m <- regmatches(lines[i], regexec("^\\s*([A-Za-z_.][A-Za-z0-9_.]*)\\s*(<-|=)\\s*function", lines[i]))[[1]]
    if (length(m) == 3) defs[[m[2]]] <- basename(f)
    # S3 方法（如 print.xxx / format.xxx）与赋值给列表元素的不算
  }
}
cat("R 函数定义总数:", length(defs), "\n\n")

# 2) 统计引用（排除定义行本身）
refCount <- setNames(integer(length(defs)), names(defs))
for (f in allRefFiles) {
  txt <- readLines(f, warn = FALSE, encoding = "UTF-8")
  for (nm in names(defs)) {
    # 用词边界匹配调用/引用；定义行会在下面的循环里扣掉
    hits <- length(grep(paste0("(?<![A-Za-z0-9_.])", gsub("\\.", "\\\\.", nm), "(?![A-Za-z0-9_.])"),
                        txt, perl = TRUE))
    refCount[[nm]] <- refCount[[nm]] + hits
  }
}
# 扣掉定义处自身那一次
for (f in files) {
  txt <- readLines(f, warn = FALSE, encoding = "UTF-8")
  for (i in seq_along(txt)) {
    m <- regmatches(txt[i], regexec("^\\s*([A-Za-z_.][A-Za-z0-9_.]*)\\s*(<-|=)\\s*function", txt[i]))[[1]]
    if (length(m) == 3 && !is.na(refCount[m[2]])) refCount[[m[2]]] <- refCount[[m[2]]] - 1L
  }
}

zero <- names(refCount)[refCount <= 0]
cat("零引用（候选）:", length(zero), "\n")
for (nm in sort(zero)) cat(sprintf("  %-46s 定义于 %s\n", nm, defs[[nm]]))

# 3) 只被自身文件引用的（可能内部私有但仍有用），信息性输出
one <- names(refCount)[refCount == 1]
cat("\n仅 1 处引用:", length(one), "（多为同文件内部调用，不必处理）\n")
