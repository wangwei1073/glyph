options(width = 250)
suppressPackageStartupMessages({ library(ggplot2); library(ggpubr) })
cmp <- list(c("compact", "suv"))

f <- function(tag, expr) {
  r <- tryCatch({ print(force(expr)); "OK" }, error = function(e) paste("ERROR:", conditionMessage(e)))
  cat(tag, ":", r, "\n")
}

f("A ggplot(df) + layer mappings", ggplot(mpg) +
    geom_boxplot(mapping = aes(x = class, y = hwy, fill = class)) +
    stat_compare_means(mapping = aes(x = class, y = hwy), method = "t.test",
                       label = "p.signif", comparisons = cmp))

f("B no fill on boxplot", ggplot(mpg) +
    geom_boxplot(mapping = aes(x = class, y = hwy)) +
    stat_compare_means(mapping = aes(x = class, y = hwy), method = "t.test",
                       label = "p.signif", comparisons = cmp))

f("C global mapping", ggplot(mpg, aes(x = class, y = hwy)) +
    geom_boxplot(aes(fill = class)) +
    stat_compare_means(method = "t.test", label = "p.signif", comparisons = cmp))

f("D no comparisons", ggplot(mpg) +
    geom_boxplot(mapping = aes(x = class, y = hwy, fill = class)) +
    stat_compare_means(mapping = aes(x = class, y = hwy), method = "t.test", label = "p.signif"))
