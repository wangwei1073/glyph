options(width = 250)
suppressPackageStartupMessages({ library(ggplot2); library(ggpubr) })
base <- ggplot(mpg, aes(class, hwy)) + geom_boxplot()
cmp <- list(c("compact", "suv"))

t1 <- tryCatch({ print(base + stat_compare_means(comparisons = cmp, method = "t.test", label = "p.signif")); "OK" }, error = function(e) paste("ERROR:", conditionMessage(e)))
cat("inherit mapping:", t1, "\n")

t2 <- tryCatch({ print(base + stat_compare_means(mapping = aes(x = class, y = hwy), comparisons = cmp, method = "t.test", label = "p.signif")); "OK" }, error = function(e) paste("ERROR:", conditionMessage(e)))
cat("explicit mapping:", t2, "\n")

t3 <- tryCatch({ print(base + stat_compare_means(mapping = aes(x = class, y = hwy, group = class), comparisons = cmp, method = "t.test", label = "p.signif")); "OK" }, error = function(e) paste("ERROR:", conditionMessage(e)))
cat("explicit mapping + group:", t3, "\n")
