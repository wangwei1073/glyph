# ggplotGUI - L1 描述统计测试
# 运行: Rscript tests/test_stats_l1.R
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) invisible(try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE))
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}
near <- function(a, b, tol = 1e-6) isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = tol))

# ---- 1) 基础：无分组 ----
d1 <- data.frame(a = c(1, 2, 3, 4, 5), b = c(10, 20, 30, 40, NA))
r1 <- .ggspec_stats_summary(d1)
chk("无分组返回 2 行", nrow(r1$summary) == 2)
chk("识别到 2 个数值列", length(r1$vars) == 2)
ra <- r1$summary[r1$summary$variable == "a", ]
chk("a 的 n = 5", ra$n == 5)
chk("a 的均值 = 3", near(ra$mean, 3))
chk("a 的中位数 = 3", near(ra$median, 3))
chk("a 的 Q1 = 2", near(ra$q1, 2))
chk("a 的 Q3 = 4", near(ra$q3, 4))
chk("a 的 SD（保留 4 位）", near(ra$sd, round(stats::sd(1:5), 4)))
rb <- r1$summary[r1$summary$variable == "b", ]
chk("b 的缺失数 = 1", rb$nMissing == 1)
chk("b 的 n = 4（忽略缺失）", rb$n == 4)
chk("b 的均值 = 25", near(rb$mean, 25))

# ---- 2) 分组 ----
d2 <- data.frame(
  y = c(1, 2, 3, 10, 20, 30),
  g = factor(c("A", "A", "A", "B", "B", "B")),
  h = c("x", "y", "x", "y", "x", "y")
)
r2 <- .ggspec_stats_summary(d2, vars = "y", groupBy = "g")
chk("分组：A/B 各 1 行 + 合计 1 行", nrow(r2$summary) == 3)
a_row <- r2$summary[r2$summary$group == "A", ]
b_row <- r2$summary[r2$summary$group == "B", ]
tot_row <- r2$summary[r2$summary$group == "（合计）", ]
chk("A 组均值 = 2", near(a_row$mean, 2))
chk("B 组均值 = 20", near(b_row$mean, 20))
chk("合计均值 = 11", near(tot_row$mean, 11))
chk("合计 n = 6", tot_row$n == 6)

# ---- 3) 多列分组 ----
r3 <- .ggspec_stats_summary(d2, vars = "y", groupBy = c("g", "h"))
chk("多列分组产生组合标签", any(grepl("\\|", r3$summary$group)))
chk("多列分组行数 = 4 + 合计", nrow(r3$summary) == 5)

# ---- 4) 数值列作分组（低基数） ----
d4 <- data.frame(y = c(1, 2, 3, 4), k = c(1, 1, 2, 2))
r4 <- .ggspec_stats_summary(d4, vars = "y", groupBy = "k")
chk("低基数数值可作分组", nrow(r4$summary) == 3)

# ---- 5) 边界：无数值列 / 空数据 ----
e1 <- tryCatch(.ggspec_stats_summary(data.frame(s = c("a", "b"))), error = function(e) e)
chk("无数值列应报错", inherits(e1, "error"))
e2 <- tryCatch(.ggspec_stats_summary(d1[0, ]), error = function(e) e)
chk("空数据应报错", inherits(e2, "error"))

# ---- 6) .gg_rid 不参与统计 ----
d6 <- d1; d6$.gg_rid <- 1:5
r6 <- .ggspec_stats_summary(d6)
chk("内部锚列被排除", !".gg_rid" %in% r6$summary$variable)

# ---- 7) 生成代码可执行且结果一致 ----
code <- paste(r1$code, collapse = "\n")
env <- new.env(parent = globalenv())
assign("df", d1, envir = env)
ev <- tryCatch({ eval(parse(text = code), envir = env); TRUE }, error = function(e) e)
chk("无分组代码可执行", isTRUE(ev))
if (isTRUE(ev)) {
  res <- eval(parse(text = code), envir = env)
  # sapply 返回矩阵：行 = 统计量，列 = 变量
  chk("代码结果是矩阵", is.matrix(res))
  chk("代码结果含 mean 行", "mean" %in% rownames(res))
  chk("代码结果与后端一致（a 的均值=3）", near(res["mean", "a"], 3))
  chk("代码结果与后端一致（a 的 n=5）", near(res["n", "a"], 5))
}

code2 <- paste(r2$code, collapse = "\n")
env2 <- new.env(parent = globalenv()); assign("df", d2, envir = env2)
ev2 <- tryCatch({ eval(parse(text = code2), envir = env2); TRUE }, error = function(e) e)
chk("分组代码可执行", isTRUE(ev2))
if (isTRUE(ev2)) {
  res2 <- eval(parse(text = code2), envir = env2)
  chk("分组代码返回 data.frame", is.data.frame(res2))
  chk("分组代码含 g 列", "g" %in% names(res2))
  chk("分组代码行数 = 2 组", nrow(res2) == 2)
}

# ---- 8) 列角色识别 ----
cols <- .ggspec_stats_columns(d2)
chk("y 是数值列", "y" %in% unlist(cols$numeric))
chk("g 可分组", "g" %in% unlist(cols$groupable))
chk("h 可分组", "h" %in% unlist(cols$groupable))
chk("y 不可分组（6 个唯一值 ≤ 30，按规则可分组）", "y" %in% unlist(cols$groupable))

# ---- 9) 真实数据：iris ----
r_iris <- .ggspec_stats_summary(iris, vars = "Sepal.Length", groupBy = "Species")
chk("iris 分组统计行数 = 4（3 组 + 合计）", nrow(r_iris$summary) == 4)
setosa <- r_iris$summary[r_iris$summary$group == "setosa", ]
chk("setosa 均值 = 5.006", near(setosa$mean, mean(iris$Sepal.Length[iris$Species == "setosa"]), 1e-4))

cat(sprintf("\n===== L1 描述统计: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
