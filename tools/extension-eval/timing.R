options(width = 250)
suppressPackageStartupMessages({ library(ggplot2); library(ragg) })
tmp <- tempfile(fileext = ".png")
timeit <- function(tag, expr, reps = 3) {
  ts <- numeric(reps)
  for (i in seq_len(reps)) {
    t <- system.time({
      agg_png(tmp, width = 900, height = 520, units = "px", res = 110)
      print(force(expr)); dev.off()
    })
    ts[i] <- t[["elapsed"]]
  }
  cat(sprintf("%-42s %.2fs (median of %d)\n", tag, median(ts), reps))
  unlink(tmp)
}
base <- ggplot(mpg, aes(class, hwy)) + geom_boxplot()
timeit("baseline ggplot2 boxplot", base)

suppressPackageStartupMessages(library(ggprism))
timeit("ggprism theme_prism + scale_fill_prism",
       ggplot(mpg, aes(class, hwy, fill = class)) + geom_boxplot() +
         theme_prism(palette = "floral") + scale_fill_prism(palette = "floral"))

suppressPackageStartupMessages(library(ggpubr))
dd <- ToothGrowth; dd$dose <- factor(dd$dose)
timeit("ggpubr stat_compare_means (3 groups x 2)",
       ggplot(dd, aes(dose, len, fill = supp)) + geom_boxplot() +
         stat_compare_means(aes(group = supp), method = "t.test", label = "p.signif"))

suppressPackageStartupMessages(library(ggstatsplot))
timeit("ggstatsplot ggbetweenstats",
       ggbetweenstats(data = mpg, x = class, y = hwy, type = "parametric"),
       reps = 2)
timeit("ggstatsplot ggscatterstats",
       ggscatterstats(data = mpg, x = displ, y = hwy),
       reps = 2)
