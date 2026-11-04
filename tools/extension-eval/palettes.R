suppressPackageStartupMessages(library(ggprism))
d <- ggprism::ggprism_data
cat("top:", paste(names(d), collapse = ", "), "\n")
cat("colour palettes:", paste(names(d$colour_palettes), collapse = ", "), "\n")
cat("fill palettes:", paste(names(d$fill_palettes), collapse = ", "), "\n")
cat("shape palettes:", paste(names(d$shape_palettes), collapse = ", "), "\n")
cat("n colour palettes:", length(d$colour_palettes), "\n")
