# 审查：哪些参数仍是自由文本，而官方文档有有限取值
suppressMessages(library(ggplot2))
cat("=== theme_* 函数的参数与当前控件类型 ===\n")
meta_fun <- function(fn, pkg = "ggplot2") {
  f <- tryCatch(get(fn, envir = if (pkg == "ggplot2") asNamespace("ggplot2") else asNamespace(pkg)),
                error = function(e) NULL)
  if (is.null(f)) return(NULL)
  names(formals(f))
}

themes <- list(
  c("theme_gray", "ggplot2"), c("theme_bw", "ggplot2"), c("theme_minimal", "ggplot2"),
  c("theme_prism", "ggprism"), c("theme_pubr", "ggpubr")
)
for (th in themes) {
  a <- tryCatch(meta_fun(th[1], th[2]), error = function(e) NULL)
  if (!is.null(a)) cat(sprintf("%-14s: %s\n", th[1], paste(setdiff(a, "..."), collapse = ", ")))
}

cat("\n=== ggprism 调色板名称 ===\n")
if (requireNamespace("ggprism", quietly = TRUE)) {
  pf <- tryCatch(ggprism::prism_palettes, error = function(e) NULL)
  if (!is.null(pf)) cat(names(pf), sep = ", ")
  cat("\n")
  cat("数量:", if (is.null(pf)) "NA" else length(pf), "\n")
} else {
  cat("ggprism 未安装\n")
}

cat("\n=== 字体样式可选值 ===\n")
cat("plain / bold / italic / bold.italic （ggplot2 文档）\n")
