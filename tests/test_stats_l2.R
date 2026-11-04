# ggplotGUI - L2 统计检验测试
# 运行: Rscript tests/test_stats_l2.R
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
near <- function(a, b, tol = 1e-4) {
  if (length(a) == 0 || length(b) == 0) return(FALSE)
  isTRUE(all.equal(as.numeric(a), as.numeric(b), tolerance = tol))
}
run_code <- function(code, data) {
  env <- new.env(parent = globalenv())
  assign("df", data, envir = env)
  tryCatch(eval(parse(text = code), envir = env), error = function(e) e)
}

# ============================================================
# 1) 两独立样本 t 检验
# ============================================================
d1 <- data.frame(
  y = c(5.1, 5.5, 5.9, 6.2, 5.8, 4.9, 5.3, 6.5, 6.8, 7.1, 6.9, 7.3),
  g = factor(rep(c("A", "B"), each = 6))
)
r1 <- .ggspec_stats_test(d1, y = "y", group = "g", method = "t.test")
ref1 <- stats::t.test(d1$y[d1$g == "A"], d1$y[d1$g == "B"])
chk("t 检验 method 正确", identical(r1$method, "t.test"))
chk("t 统计量与 R 一致", near(r1$statistic, as.numeric(ref1$statistic)))
chk("p 值与 R 一致", near(r1$p, ref1$p.value, 1e-6))
chk("df 与 R 一致", near(r1$df, as.numeric(ref1$parameter), 1e-3))
chk("n = 12", r1$n == 12)
chk("效应量 Cohen's d 已计算", is.finite(r1$estimate))
chk("有假设检查提示", length(r1$notes) > 0)
chk("t 检验代码可执行", !inherits(run_code(r1$code, d1), "error"))
ev1 <- run_code(r1$code, d1)
chk("代码结果 p 与后端一致", !inherits(ev1, "error") && near(ev1$p.value, r1$p, 1e-6))

# ============================================================
# 2) Welch 修正（方差不齐）
# ============================================================
d2 <- data.frame(
  y = c(1, 1.1, 1.2, 1.3, 10, 20, 30, 40),
  g = factor(rep(c("低", "高"), each = 4))
)
r2 <- .ggspec_stats_test(d2, y = "y", group = "g", method = "t.test")
chk("方差不齐时提示 Welch", any(grepl("Welch|方差不齐", unlist(r2$notes))))
ref2 <- stats::t.test(d2$y[d2$g == "低"], d2$y[d2$g == "高"])
chk("Welch p 值与 R 一致", near(r2$p, ref2$p.value, 1e-6))

# ============================================================
# 3) Mann-Whitney（非参数）
# ============================================================
r3 <- .ggspec_stats_test(d1, y = "y", group = "g", method = "wilcox.test")
ref3 <- suppressWarnings(stats::wilcox.test(d1$y[d1$g == "A"], d1$y[d1$g == "B"]))
chk("Mann-Whitney 统计量一致", near(r3$statistic, as.numeric(ref3$statistic)))
chk("Mann-Whitney p 一致", near(r3$p, ref3$p.value, 1e-6))
chk("Mann-Whitney 代码可执行", !inherits(run_code(r3$code, d1), "error"))

# ============================================================
# 4) 单因素方差分析（3 组）
# ============================================================
d4 <- data.frame(
  y = c(5, 6, 7, 6, 7, 8, 9, 10, 11, 10, 11, 12),
  g = factor(rep(c("A", "B", "C"), each = 4))
)
r4 <- .ggspec_stats_test(d4, y = "y", group = "g", method = "aov")
ref4 <- summary(stats::aov(y ~ g, data = d4))[[1]]
chk("ANOVA F 值与 R 一致", near(r4$statistic, ref4[["F value"]][1], 1e-4))
chk("ANOVA p 值与 R 一致", near(r4$p, ref4[["Pr(>F)"]][1], 1e-8))
chk("ANOVA df 与 R 一致", near(r4$df, ref4[["Df"]][1], 1e-6))
chk("eta² 在 0-1 之间", is.finite(r4$estimate) && r4$estimate >= 0 && r4$estimate <= 1)
chk("ANOVA 代码可执行", !inherits(run_code(r4$code, d4), "error"))

# ============================================================
# 5) Kruskal-Wallis
# ============================================================
r5 <- .ggspec_stats_test(d4, y = "y", group = "g", method = "kruskal.test")
ref5 <- stats::kruskal.test(d4$y, d4$g)
chk("KW 统计量一致", near(r5$statistic, as.numeric(ref5$statistic)))
chk("KW p 值一致", near(r5$p, ref5$p.value, 1e-8))
chk("KW 代码可执行", !inherits(run_code(r5$code, d4), "error"))

# ============================================================
# 6) 卡方检验
# ============================================================
d6 <- data.frame(
  a = c(rep("是", 30), rep("否", 20), rep("是", 10), rep("否", 40)),
  b = c(rep("男", 50), rep("女", 50))
)
r6 <- .ggspec_stats_test(d6, y = "a", group = "b", method = "chisq.test")
ref6 <- suppressWarnings(stats::chisq.test(table(d6$a, d6$b)))
chk("卡方统计量一致", near(r6$statistic, as.numeric(ref6$statistic)))
chk("卡方 p 值一致", near(r6$p, ref6$p.value, 1e-8))
chk("Cramér's V 已计算", is.finite(r6$estimate))
chk("卡方代码可执行", !inherits(run_code(r6$code, d6), "error"))

# ============================================================
# 7) Fisher 精确检验
# ============================================================
d7 <- data.frame(
  a = c(rep("是", 3), rep("否", 5), rep("是", 1), rep("否", 7)),
  b = c(rep("X", 8), rep("Y", 8))
)
r7 <- .ggspec_stats_test(d7, y = "a", group = "b", method = "fisher.test")
ref7 <- stats::fisher.test(table(d7$a, d7$b))
chk("Fisher p 值一致", near(r7$p, ref7$p.value, 1e-8))
chk("Fisher 代码可执行", !inherits(run_code(r7$code, d7), "error"))

# ============================================================
# 8) Pearson / Spearman 相关
# ============================================================
d8 <- data.frame(y = c(1, 2, 3, 4, 5, 6, 7, 8), x = c(2, 4, 5, 4, 5, 7, 8, 9))
r8 <- .ggspec_stats_test(d8, y = "y", x = "x", method = "cor.test")
ref8 <- stats::cor.test(d8$y, d8$x)
chk("Pearson r 一致", near(r8$statistic, as.numeric(ref8$statistic)))
chk("Pearson p 一致", near(r8$p, ref8$p.value, 1e-8))
chk("效应量名为 r", identical(r8$estimateName, "r"))
chk("相关代码可执行", !inherits(run_code(r8$code, d8), "error"))

r9 <- .ggspec_stats_test(d8, y = "y", x = "x", method = "cor.test.spearman")
ref9 <- suppressWarnings(stats::cor.test(d8$y, d8$x, method = "spearman"))
chk("Spearman rho 一致", near(r9$statistic, as.numeric(ref9$estimate)))
chk("Spearman 效应量名 rho", identical(r9$estimateName, "rho"))
chk("Spearman p 一致", near(r9$p, ref9$p.value, 1e-8))
chk("Spearman 代码可执行", !inherits(run_code(r9$code, d8), "error"))

# ============================================================
# 9) 配对 t 检验
# ============================================================
d10 <- data.frame(
  y = c(10, 12, 14, 16, 18, 20, 11, 12, 17, 15, 22, 21),
  g = factor(rep(c("前", "后"), each = 6))
)
r10 <- .ggspec_stats_test(d10, y = "y", group = "g", method = "t.test.paired")
chk("配对 t 检验已执行", identical(r10$method, "t.test.paired"))
chk("配对 p 值有效", is.finite(r10$p))
ref10 <- stats::t.test(d10$y[1:6], d10$y[7:12], paired = TRUE)
chk("配对 t 统计量一致", near(r10$statistic, as.numeric(ref10$statistic)))

# 配对差值为常量时应给出明确错误（而不是崩溃）
d10b <- data.frame(y = c(1, 2, 3, 2, 3, 4), g = factor(rep(c("前", "后"), each = 3)))
e_pair <- tryCatch(.ggspec_stats_test(d10b, y = "y", group = "g", method = "t.test.paired"),
                   error = function(e) e)
chk("配对差值常量时报明确错误", inherits(e_pair, "error") &&
      grepl("常数|无定义", conditionMessage(e_pair)))

# ============================================================
# 10) 自动选法
# ============================================================
r_auto2 <- .ggspec_stats_test(d1, y = "y", group = "g")
chk("2 组自动选 t 检验", identical(r_auto2$method, "t.test"))
r_auto3 <- .ggspec_stats_test(d4, y = "y", group = "g")
chk("3 组自动选方差分析", identical(r_auto3$method, "aov"))

# ============================================================
# 11) 边界与错误处理
# ============================================================
e1 <- tryCatch(.ggspec_stats_test(d1, y = "y", group = "g", method = "aov"), error = function(e) e)
chk("2 组用 ANOVA 不报错（可执行）", !inherits(e1, "error"))
e2 <- tryCatch(.ggspec_stats_test(d1, y = "nope", group = "g", method = "t.test"), error = function(e) e)
chk("不存在的列应报错", inherits(e2, "error"))
d11 <- data.frame(y = c(1, 2, 3, 4), g = factor(c("A", "A", "B", "B")))
e3 <- tryCatch(.ggspec_stats_test(d11, y = "y", group = "g", method = "chisq.test"), error = function(e) e)
chk("数值变量误用卡方应报错", inherits(e3, "error"))

# ============================================================
# 12) 真实数据：iris
# ============================================================
r_iris <- .ggspec_stats_test(iris, y = "Sepal.Length", group = "Species", method = "aov")
ref_iris <- summary(stats::aov(Sepal.Length ~ Species, data = iris))[[1]]
chk("iris ANOVA F 值一致", near(r_iris$statistic, ref_iris[["F value"]][1], 1e-4))
chk("iris ANOVA p 值一致", near(r_iris$p, ref_iris[["Pr(>F)"]][1], 1e-10))
chk("iris 组数为 3+", length(r_iris$groups) == 3)

r_iris2 <- .ggspec_stats_test(iris[iris$Species != "virginica", ],
                              y = "Sepal.Length", group = "Species", method = "wilcox.test")
chk("iris 两组非参数检验 p 有效", is.finite(r_iris2$p) && r_iris2$p < 0.05)

# ============================================================
# 13) 方法推荐
# ============================================================
sug <- .ggspec_stats_suggest(iris)
chk("iris 推荐含 ANOVA", any(vapply(sug$methods, function(m) identical(m$id, "aov"), logical(1))))
chk("iris 推荐含相关检验", any(vapply(sug$methods, function(m) identical(m$id, "cor.test"), logical(1))))
chk("推荐结果含角色信息", length(sug$roles$numeric) == 4)

cat(sprintf("\n===== L2 统计检验: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
