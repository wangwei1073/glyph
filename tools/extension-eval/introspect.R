options(width = 250, warn = 1)
pkgs <- c("ggprism", "ggpubr", "ggstatsplot")
`%||%` <- function(a, b) if (is.null(a)) b else a

for (p in pkgs) {
  cat("\n==== ", p, " ", as.character(packageVersion(p)), " ====\n", sep = "")
  ex <- getNamespaceExports(p)
  cat("exports:", length(ex), "\n")
  cat("geom_*:", paste(sort(grep("^geom_", ex, value = TRUE)), collapse = ", "), "\n")
  cat("stat_*:", paste(sort(grep("^stat_", ex, value = TRUE)), collapse = ", "), "\n")
  cat("scale_*:", paste(sort(grep("^scale_", ex, value = TRUE)), collapse = ", "), "\n")
  cat("theme_*:", paste(sort(grep("^theme_", ex, value = TRUE)), collapse = ", "), "\n")
  cat("guide_*:", paste(sort(grep("^guide_", ex, value = TRUE)), collapse = ", "), "\n")
  cat("annotation_*:", paste(sort(grep("^annotation_", ex, value = TRUE)), collapse = ", "), "\n")
  cat("gg-prefixed:", paste(sort(grep("^gg", ex, value = TRUE)), collapse = ", "), "\n")
  d <- packageDescription(p)
  cat("Depends:", d$Depends %||% "-", "\n")
  cat("Imports:", d$Imports %||% "-", "\n")
  sug <- d$Suggests %||% ""
  cat("Suggests count:", length(Filter(nzchar, trimws(strsplit(sug, ",")[[1]]))), "\n")
  cat("Date/Publication:", d$Date %||% d$`Date/Publication` %||% "-", "\n")
}

cat("\n==== registry integration simulation ====\n")
suppressPackageStartupMessages({ library(ggplot2); library(jsonlite) })
setwd("E:/Desktop/ggplot-gui")
for (f in c("R/utils.R", "R/registry_meta.R", "R/registry_core.R")) source(f, encoding = "UTF-8", local = FALSE)

for (p in pkgs) {
  cat("\n-- ", p, " --\n", sep = "")
  gs <- tryCatch(.ggspec_scan_pkg_geoms(p, NULL), error = function(e) e)
  if (inherits(gs, "error")) { cat("geom scan ERROR:", conditionMessage(gs), "\n"); gs <- list() }
  cat("geom_* scanned:", length(gs), "\n")
  for (x in gs) {
    f <- tryCatch(get(x$fn, envir = asNamespace(p)), error = function(e) NULL)
    layer <- if (is.null(f)) NULL else tryCatch(suppressWarnings(f()), error = function(e) NULL)
    cat(sprintf("   %-28s layer=%-6s geom=%s\n", x$fn,
                if (is.null(layer)) "NO" else "yes",
                if (is.null(layer)) "-" else class(layer$geom)[1]))
  }
  ss <- tryCatch(.ggspec_scan_pkg_scales(p), error = function(e) e)
  if (inherits(ss, "error")) { cat("scale scan ERROR:", conditionMessage(ss), "\n"); ss <- list() }
  cat("scale_* scanned:", length(ss), "\n")
  if (length(ss)) {
    tab <- table(vapply(ss, function(s) s$aes, ""))
    cat("   by aes:", paste(sprintf("%s=%d", names(tab), as.integer(tab)), collapse = " "), "\n")
    cat("   types:", paste(vapply(ss, function(s) s$type, ""), collapse = ", "), "\n")
  }
  th <- grep("^theme_", getNamespaceExports(p), value = TRUE)
  th <- th[vapply(th, function(fn) is.function(get(fn, envir = asNamespace(p))), logical(1))]
  cat("theme_* functions:", length(th), "->", paste(th, collapse = ", "), "\n")
  for (fn in th) {
    fm <- names(formals(get(fn, envir = asNamespace(p))))
    cat("   ", fn, "args:", paste(setdiff(fm, "..."), collapse = ", "), "\n")
  }
}
