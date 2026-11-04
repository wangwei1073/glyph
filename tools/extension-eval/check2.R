options(width = 250)
`%||%` <- function(a, b) if (is.null(a)) b else a
db <- installed.packages()
for (p in c("ggplot2", "ggprism", "ggpubr", "ggstatsplot")) {
  deps <- tools::package_dependencies(p, db = db, recursive = TRUE)[[p]]
  cat(sprintf("%-12s recursive deps: %3d\n", p, length(deps)))
}
cat("\n-- beyond ggplot2 closure --\n")
g2 <- tools::package_dependencies("ggplot2", db = db, recursive = TRUE)$ggplot2
for (p in c("ggprism", "ggpubr", "ggstatsplot")) {
  deps <- tools::package_dependencies(p, db = db, recursive = TRUE)[[p]]
  extra <- setdiff(deps, g2)
  cat(sprintf("%-12s extra: %2d | %s\n", p, length(extra), paste(sort(extra), collapse = ", ")))
}

cat("\n-- theme-element side effects of loading --\n")
suppressPackageStartupMessages(library(ggplot2))
base_el <- names(ggplot2:::get_element_tree())
cat("baseline:", length(base_el), "\n")
for (p in c("ggprism", "ggpubr", "ggstatsplot")) {
  before <- names(ggplot2:::get_element_tree())
  suppressPackageStartupMessages(library(p, character.only = TRUE))
  after <- names(ggplot2:::get_element_tree())
  cat(sprintf("%-12s +%d elements: %s\n", p, length(setdiff(after, before)),
              paste(setdiff(after, before), collapse = ", ")))
}
cat("final:", length(ggplot2:::get_element_tree()), "\n")

cat("\n-- cold namespace load timing (this fresh session) --\n")
for (p in c("ggprism", "ggpubr", "ggstatsplot")) {
  if (p %in% loadedNamespaces()) next
  t <- system.time(loadNamespace(p))
  cat(sprintf("%-12s %.2fs\n", p, t[["elapsed"]]))
}
