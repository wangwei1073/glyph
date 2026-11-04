options(width = 250, warn = 1)
cat("ggplot2:", as.character(packageVersion("ggplot2")), "\n")
suppressPackageStartupMessages({ library(ggplot2); library(ragg) })
outdir <- "C:/Users/doctorww/AppData/Local/Temp/ggpkg_eval"
dir.create(outdir, showWarnings = FALSE, recursive = TRUE)

save_png <- function(p, file, w = 800, h = 500) {
  if (is.null(p)) { cat("   (no plot) ", file, "\n", sep = ""); return(FALSE) }
  tryCatch({
    agg_png(file.path(outdir, file), width = w, height = h, units = "px", res = 100)
    print(p); dev.off(); TRUE
  }, error = function(e) { try(dev.off(), silent = TRUE); cat("   render ERROR:", conditionMessage(e), "\n"); FALSE })
}
try_load <- function(pkg) {
  t0 <- Sys.time()
  ok <- tryCatch({ suppressPackageStartupMessages(library(pkg, character.only = TRUE)); TRUE },
                 error = function(e) { cat("load ERROR:", conditionMessage(e), "\n"); FALSE })
  cat("attach", pkg, ":", ok, "|", round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 2), "s\n")
  ok
}

## ---------------- ggprism ----------------
cat("\n==== ggprism ====\n")
if (try_load("ggprism")) {
  cat("all exports:", paste(sort(getNamespaceExports("ggprism")), collapse = ", "), "\n")
  cat("theme_prism palette default:", as.character(formals(theme_prism)$palette), "\n")
  cat("scale_fill_prism formals:", paste(names(formals(scale_fill_prism)), collapse = ", "), "\n")
  pal_names <- tryCatch(names(ggprism:::prism_colors), error = function(e) NULL)
  cat("prism palettes:", if (is.null(pal_names)) "n/a" else paste(pal_names, collapse = ", "), "\n")

  p1 <- tryCatch(ggplot(mpg, aes(class, hwy, fill = class)) + geom_boxplot() +
                   theme_prism(palette = "floral", base_size = 12) +
                   scale_fill_prism(palette = "floral") + theme(legend.position = "none"),
                 error = function(e) { cat("p1 ERROR:", conditionMessage(e), "\n"); NULL })
  cat("theme_prism + scale_fill_prism:", save_png(p1, "ggprism_box.png"), "\n")

  p2 <- tryCatch({
    df <- data.frame(xmin = 1, xmax = 2, y.position = 44, label = "p = 0.01")
    ggplot(mpg, aes(class, hwy)) + geom_boxplot() +
      add_pvalue(df, label = "label", xmin = "xmin", xmax = "xmax", y.position = "y.position") +
      theme_prism()
  }, error = function(e) { cat("add_pvalue ERROR:", conditionMessage(e), "\n"); NULL })
  cat("add_pvalue:", save_png(p2, "ggprism_pvalue.png"), "\n")

  p3 <- tryCatch(ggplot(mpg, aes(displ, hwy)) + geom_point() +
                   scale_colour_prism(palette = "floral") +
                   scale_shape_prism(palette = "default") + guide_prism_minor(),
                 error = function(e) { cat("guide_prism ERROR:", conditionMessage(e), "\n"); NULL })
  cat("guide_prism_minor:", save_png(p3, "ggprism_guide.png"), "\n")
}

## ---------------- ggpubr ----------------
cat("\n==== ggpubr ====\n")
if (try_load("ggpubr")) {
  p3 <- tryCatch(ggboxplot(mpg, x = "class", y = "hwy", color = "class", add = "jitter",
                           palette = "jco", ggtheme = theme_pubr()),
                 error = function(e) { cat("ggboxplot ERROR:", conditionMessage(e), "\n"); NULL })
  cat("ggboxplot:", save_png(p3, "ggpubr_box.png"), "\n")

  p4 <- tryCatch({
    dd <- ToothGrowth; dd$dose <- factor(dd$dose)
    ggboxplot(dd, x = "dose", y = "len", fill = "supp", palette = "npg") +
      stat_compare_means(aes(group = supp), method = "t.test", label = "p.signif")
  }, error = function(e) { cat("stat_compare_means ERROR:", conditionMessage(e), "\n"); NULL })
  cat("stat_compare_means:", save_png(p4, "ggpubr_pvalue.png"), "\n")

  p5 <- tryCatch(ggscatter(mpg, x = "displ", y = "hwy", color = "class", add = "reg.line") +
                   stat_cor(aes(color = class), label.x = 3),
                 error = function(e) { cat("stat_cor ERROR:", conditionMessage(e), "\n"); NULL })
  cat("stat_cor:", save_png(p5, "ggpubr_statcor.png"), "\n")

  comp <- tryCatch(ggarrange(p3, p5, ncol = 2, common.legend = TRUE), error = function(e) { cat("ggarrange ERROR:", conditionMessage(e), "\n"); NULL })
  cat("ggarrange:", save_png(comp, "ggpubr_arrange.png", 1100, 450), "\n")

  p6 <- tryCatch({
    ggplot(mpg, aes(class, hwy)) + geom_boxplot() +
      geom_signif(comparisons = list(c("compact", "suv")), map_signif_level = TRUE)
  }, error = function(e) { cat("geom_signif ERROR:", conditionMessage(e), "\n"); NULL })
  cat("geom_signif:", save_png(p6, "ggpubr_signif.png"), "\n")

  cat("theme_pubr args:", paste(names(formals(theme_pubr)), collapse = ", "), "\n")
  cat("exports:", length(getNamespaceExports("ggpubr")), "\n")
}

## ---------------- ggstatsplot ----------------
cat("\n==== ggstatsplot ====\n")
if (try_load("ggstatsplot")) {
  p7 <- tryCatch(ggbetweenstats(data = mpg, x = class, y = hwy, type = "parametric",
                                pairwise.display = "significant"),
                 error = function(e) { cat("ggbetweenstats ERROR:", conditionMessage(e), "\n"); NULL })
  cat("ggbetweenstats:", save_png(p7, "ggstats_box.png"), "\n")

  p8 <- tryCatch(ggscatterstats(data = mpg, x = displ, y = hwy),
                 error = function(e) { cat("ggscatterstats ERROR:", conditionMessage(e), "\n"); NULL })
  cat("ggscatterstats:", save_png(p8, "ggstats_scatter.png"), "\n")

  cat("exports total:", length(getNamespaceExports("ggstatsplot")), "\n")
  cat("theme_ggstatsplot args:", paste(names(formals(theme_ggstatsplot)), collapse = ", "), "\n")
  cat("search path after attach:", paste(head(search(), 12), collapse = " > "), "\n")
}
cat("\nDONE\n")
