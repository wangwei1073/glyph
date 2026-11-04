options(width = 250)
`%||%` <- function(a, b) if (is.null(a)) b else a
base_pkgs <- rownames(installed.packages(priority = "base"))
rec_deps <- function(pkg) {
  seen <- character(0)
  walk <- function(p) {
    if (p %in% seen || p %in% base_pkgs) return()
    seen <<- c(seen, p)
    d <- tryCatch(packageDescription(p), error = function(e) NULL)
    if (is.null(d) || length(d) == 0 || is.na(d[1])) return()
    for (fld in c("Depends", "Imports", "LinkingTo")) {
      v <- d[fld]
      if (length(v) != 1 || is.na(v) || !is.character(v)) next
      for (el in trimws(strsplit(v, ",")[[1]])) {
        nm <- trimws(sub("\\(.*", "", el))
        if (nzchar(nm) && nm != "R") walk(nm)
      }
    }
  }
  walk(pkg)
  seen
}
g2 <- rec_deps("ggplot2")
cat("ggplot2 closure:", length(g2), "\n")
for (p in c("ggprism", "ggpubr", "ggstatsplot")) {
  cl <- rec_deps(p)
  extra <- setdiff(cl, g2)
  cat("\n==", p, "==\n")
  cat("total deps (excl. base):", length(cl), "| beyond ggplot2 closure:", length(extra), "\n")
  cat("extra:", paste(sort(extra), collapse = ", "), "\n")
  imp <- packageDescription(p)$Imports %||% ""
  cat("direct Imports:", length(Filter(nzchar, trimws(strsplit(imp, ",")[[1]]))), "\n")
  cat("Depends:", packageDescription(p)$Depends %||% "", "\n")
}

cat("\n== conflicts after attaching all three ==\n")
suppressPackageStartupMessages(library(ggplot2))
for (p in c("ggprism", "ggpubr", "ggstatsplot")) suppressPackageStartupMessages(library(p, character.only = TRUE))
cf <- conflicts()
for (nm in names(cf)) cat(sprintf("%-16s %s\n", nm, paste(cf[[nm]], collapse = " | ")))

cat("\n== search path ==\n")
cat(paste(head(search(), 8), collapse = " > "), "\n")
et <- tryCatch(ggplot2:::get_element_tree(), error = function(e) list())
cat("theme elements now:", length(et), "\n")
cat("side-panel elements:", paste(grep("side", names(et), value = TRUE), collapse = ", "), "\n")
