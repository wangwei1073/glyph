# ggplotGUI - L4 回归分析测试
# 运行: Rscript tests/test_reg_l4.R
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
  if (!length(a) || !length(b)) return(FALSE)
  if (length(a) != length(b)) return(FALSE)
  # 系数保留 5 位小数，用绝对容差比较，避免 all.equal 的相对容差在接近 0 时过于严格
  isTRUE(all(abs(as.numeric(a) - as.numeric(b)) <= tol))
}
run_code <- function(code, data) {
  env <- new.env(parent = globalenv())
  assign("df", data, envir = env)
  tryCatch(eval(parse(text = code), envir = env), error = function(e) e)
}

# ============================================================
# 1) 线性回归（与 lm 逐项比对）
# ============================================================
d1 <- data.frame(
  y = c(2.1, 3.9, 6.1, 8.2, 9.8, 12.1, 13.9, 16.2, 18.1, 20.2),
  x1 = 1:10,
  x2 = c(5, 3, 8, 2, 9, 4, 7, 1, 6, 10)
)
r1 <- .ggspec_reg_fit(d1, y = "y", xs = c("x1", "x2"), method = "lm")
ref1 <- summary(stats::lm(y ~ x1 + x2, data = d1))
chk("线性回归：方法正确", identical(r1$method, "lm"))
chk("线性回归：系数数量 = 3（含截距）", nrow(r1$coefs) == 3)
chk("线性回归：截距一致", near(r1$coefs$estimate[1], ref1$coefficients[1, 1]))
chk("线性回归：x1 系数一致", near(r1$coefs$estimate[2], ref1$coefficients[2, 1]))
chk("线性回归：x2 系数一致", near(r1$coefs$estimate[3], ref1$coefficients[3, 1]))
chk("线性回归：R² 一致", near(r1$fitStats$r2, round(ref1$r.squared, 4), 1e-3))
chk("线性回归：调整 R² 一致", near(r1$fitStats$adjR2, round(ref1$adj.r.squared, 4), 1e-3))
chk("线性回归：F 统计量一致", near(r1$fitStats$fstat, round(ref1$fstatistic[1], 3), 1e-2))
chk("线性回归：n 正确", r1$n == 10)
chk("线性回归：有置信区间", all(c("ciLow", "ciHigh") %in% names(r1$coefs)))
chk("线性回归：显著性星号已算", "stars" %in% names(r1$coefs))

# 代码可执行且结果一致
ev1 <- run_code(r1$code, d1)
chk("线性回归：代码可执行", !inherits(ev1, "error"))
if (!inherits(ev1, "error")) {
  # 代码最后一行是 confint，倒数第二是 summary
  fit_obj <- get("fit", envir = {
    e <- new.env(parent = globalenv()); assign("df", d1, envir = e)
    eval(parse(text = r1$code), envir = e); e
  })
  chk("线性回归：代码拟合系数一致", near(stats::coef(fit_obj), r1$coefs$estimate, 1e-3))
}

# ============================================================
# 2) 逻辑回归
# ============================================================
set.seed(42)
n <- 120
d2 <- data.frame(
  x1 = rnorm(n),
  x2 = rnorm(n)
)
d2$y <- as.integer(plogis(-0.5 + 1.2 * d2$x1 - 0.8 * d2$x2) > runif(n))
r2 <- .ggspec_reg_fit(d2, y = "y", xs = c("x1", "x2"), method = "logistic")
ref2 <- summary(stats::glm(y ~ x1 + x2, data = d2, family = stats::binomial()))
chk("逻辑回归：方法正确", identical(r2$method, "logistic"))
chk("逻辑回归：系数一致", near(r2$coefs$estimate, ref2$coefficients[, 1], 1e-3))
chk("逻辑回归：提供 exp(Est) 优势比", all(!is.na(r2$coefs$expEstimate)))
chk("逻辑回归：OR 与 exp(coef) 一致", near(r2$coefs$expEstimate, exp(ref2$coefficients[, 1]), 1e-2))
chk("逻辑回归：伪 R² 在 [0,1]", is.finite(r2$fitStats$pseudoR2) &&
      r2$fitStats$pseudoR2 >= 0 && r2$fitStats$pseudoR2 <= 1)
chk("逻辑回归：有 AIC", is.finite(r2$fitStats$aic))
chk("逻辑回归：代码可执行", !inherits(run_code(r2$code, d2), "error"))
chk("逻辑回归代码含 family = binomial", grepl("binomial()", r2$code, fixed = TRUE))

# ============================================================
# 3) 泊松回归
# ============================================================
set.seed(7)
d3 <- data.frame(x = rnorm(100))
d3$y <- stats::rpois(100, exp(1 + 0.5 * d3$x))
r3 <- .ggspec_reg_fit(d3, y = "y", xs = "x", method = "poisson")
ref3 <- summary(stats::glm(y ~ x, data = d3, family = stats::poisson()))
chk("泊松回归：方法正确", identical(r3$method, "poisson"))
chk("泊松回归：系数一致", near(r3$coefs$estimate, ref3$coefficients[, 1], 1e-4))
chk("泊松回归：代码可执行", !inherits(run_code(r3$code, d3), "error"))

# ============================================================
# 4) 分类自变量自动转因子
# ============================================================
d4 <- data.frame(
  y = c(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12),
  g = rep(c("A", "B", "C"), each = 4),
  x = c(1, 2, 3, 4, 2, 3, 4, 5, 3, 4, 5, 6)
)
r4 <- .ggspec_reg_fit(d4, y = "y", xs = c("g", "x"), method = "lm")
ref4 <- summary(stats::lm(y ~ factor(g) + x, data = d4))
chk("分类自变量：识别为因子", "g" %in% unlist(r4$factorVars))
chk("分类自变量：系数数量 = 4（截距 + 2 个哑变量 + x）", nrow(r4$coefs) == 4)
chk("分类自变量：系数一致", near(r4$coefs$estimate, ref4$coefficients[, 1], 1e-3))
chk("分类自变量：代码含 factor()", grepl("factor(df$g)", r4$code, fixed = TRUE))
chk("分类自变量：代码可执行", !inherits(run_code(r4$code, d4), "error"))

# ============================================================
# 5) 相关矩阵
# ============================================================
r5 <- .ggspec_reg_fit(iris, y = "Sepal.Length", xs = c("Sepal.Width", "Petal.Length"), method = "corr")
ref5 <- stats::cor(iris[, c("Sepal.Length", "Sepal.Width", "Petal.Length")])
chk("相关矩阵：方法正确", identical(r5$method, "corr"))
chk("相关矩阵：变量数 = 3", r5$n > 0 && length(r5$vars) == 3)
chk("相关矩阵：3 变量产生 3 对", nrow(r5$coefs) == 3)
pair_row <- r5$coefs[r5$coefs$var1 == "Sepal.Length" & r5$coefs$var2 == "Petal.Length", ]
chk("相关矩阵：r 值与 cor() 一致",
    near(pair_row$r, ref5["Sepal.Length", "Petal.Length"], 1e-4))
chk("相关矩阵：含 p 值", all(c("p", "stars") %in% names(r5$coefs)))
chk("相关矩阵：代码可执行", !inherits(run_code(r5$code, iris), "error"))

# ============================================================
# 6) 诊断提示
# ============================================================
# 小样本应提示
d6 <- data.frame(y = c(1, 2, 3, 4, 5), x = c(1, 2, 3, 4, 5))
r6 <- .ggspec_reg_fit(d6, y = "y", xs = "x", method = "lm")
chk("小样本：给出样本量提示", any(grepl("样本量", unlist(r6$notes))))

# 共线性应提示
set.seed(1)
d7 <- data.frame(x1 = rnorm(60))
d7$x2 <- d7$x1 * 1.0001 + rnorm(60, sd = 0.001)
d7$y <- 1 + 2 * d7$x1 + rnorm(60, sd = 0.1)
r7 <- .ggspec_reg_fit(d7, y = "y", xs = c("x1", "x2"), method = "lm")
chk("共线性：给出提示", any(grepl("共线性", unlist(r7$notes))))

# ============================================================
# 7) 错误处理
# ============================================================
e1 <- tryCatch(.ggspec_reg_fit(d1, y = "y", xs = character(0), method = "lm"), error = function(e) e)
chk("无自变量应报错", inherits(e1, "error"))
e2 <- tryCatch(.ggspec_reg_fit(d1, y = "nope", xs = "x1", method = "lm"), error = function(e) e)
chk("因变量不存在应报错", inherits(e2, "error"))
e3 <- tryCatch(.ggspec_reg_fit(d4, y = "g", xs = "x", method = "lm"), error = function(e) e)
chk("线性回归用分类因变量应报错", inherits(e3, "error"))
e4 <- tryCatch(.ggspec_reg_fit(d1, y = "y", xs = "x1", method = "logistic"), error = function(e) e)
chk("逻辑回归用连续因变量应报错", inherits(e4, "error"))
e5 <- tryCatch(.ggspec_reg_fit(d1, y = "y", xs = "x1", method = "poisson"), error = function(e) e)
chk("泊松回归用非计数因变量应报错", inherits(e5, "error"))
e6 <- tryCatch(.ggspec_reg_fit(data.frame(y = 1:5), y = "y", xs = "y", method = "corr"), error = function(e) e)
chk("相关矩阵变量不足应报错", inherits(e6, "error"))

# ============================================================
# 8) 列角色识别
# ============================================================
cols <- .ggspec_reg_columns(d4)
chk("列角色：y 为数值", "y" %in% unlist(cols$numeric))
chk("列角色：g 为分类", "g" %in% unlist(cols$categorical))
cols2 <- .ggspec_reg_columns(d2)
chk("列角色：二分类识别", "y" %in% unlist(cols2$binary))
cols3 <- .ggspec_reg_columns(d3)
chk("列角色：计数型识别", "y" %in% unlist(cols3$count))

# ============================================================
# 9) 真实数据：mtcars
# ============================================================
r9 <- .ggspec_reg_fit(mtcars, y = "mpg", xs = c("wt", "hp", "cyl"), method = "lm")
ref9 <- summary(stats::lm(mpg ~ wt + hp + cyl, data = mtcars))
chk("mtcars：系数一致", near(r9$coefs$estimate, ref9$coefficients[, 1], 1e-4))
chk("mtcars：R² 一致", near(r9$fitStats$r2, round(ref9$r.squared, 4), 1e-3))
chk("mtcars：p 值一致", near(r9$coefs$p, signif(ref9$coefficients[, 4], 4), 1e-3))
chk("mtcars：代码可执行", !inherits(run_code(r9$code, mtcars), "error"))

cat(sprintf("\n===== L4 回归分析: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
