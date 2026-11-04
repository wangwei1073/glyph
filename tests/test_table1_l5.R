# ggplotGUI - L5 基线特征表测试
# 运行: Rscript tests/test_table1_l5.R
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) invisible(try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE))
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

tmp <- file.path(tempdir(), paste0("t1-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}
run_code <- function(code, data) {
  env <- new.env(parent = globalenv())
  assign("df", data, envir = env)
  tryCatch(eval(parse(text = code), envir = env), error = function(e) e)
}

# ============================================================
# 1) 基础：单组汇总（iris 全部数值列）
# ============================================================
r1 <- .ggspec_table1(iris, vars = c("Sepal.Length", "Sepal.Width"), by = "", statId = "mean_sd")
chk("单组：生成成功", isTRUE(r1$ok))
chk("单组：2 个变量 → 2 行", nrow(r1$table) == 2)
chk("单组：含合计列", "合计" %in% names(r1$table) || ncol(r1$table) >= 2)
chk("单组：n 正确", r1$n == 150)
chk("单组：引擎标识", r1$engine %in% c("gtsummary", "base"))
# 校验数值：Sepal.Length 均值 5.843，SD 0.828（默认 2 位小数）
cells <- unlist(r1$table)
has_mean <- any(grepl("5\\.84", cells))
has_sd <- any(grepl("\\(0\\.83|\\(0\\.8\\)", cells))
chk("单组：均值与 R 一致（5.84）", has_mean)
chk("单组：SD 与 R 一致（0.83）", has_sd)
chk("单组：代码可执行", !inherits(run_code(r1$code, iris), "error"))

# ============================================================
# 2) 分组汇总
# ============================================================
r2 <- .ggspec_table1(iris, vars = "Sepal.Length", by = "Species", statId = "mean_sd")
chk("分组：生成成功", isTRUE(r2$ok))
chk("分组：识别 3 个水平", length(r2$groups) == 3)
# gtsummary 的列名形如 "setosa N = 50"，用模糊匹配
chk("分组：表格含 3 组列",
    sum(vapply(c("setosa", "versicolor", "virginica"),
               function(g) any(grepl(g, names(r2$table), fixed = TRUE)), logical(1))) == 3)
chk("分组：含 p 值列", any(grepl("p", names(r2$table), ignore.case = TRUE)))
chk("分组：代码可执行", !inherits(run_code(r2$code, iris), "error"))
# 校验 setosa 均值 5.006（默认 2 位 → 5.01 或 5.00）
cells2 <- unlist(r2$table)
chk("分组：setosa 均值与 R 一致", any(grepl("5\\.01|5\\.00?6", cells2)))
chk("分组：virginica 均值与 R 一致", any(grepl("6\\.5[89]", cells2)))

# ============================================================
# 3) 统计量选项
# ============================================================
r3a <- .ggspec_table1(iris, vars = "Sepal.Length", by = "", statId = "median_iqr")
chk("中位数(IQR)：生成成功", isTRUE(r3a$ok))
chk("中位数(IQR)：含中位数 5.8", length(grep("5\\.80?|5\\.8", unlist(r3a$table), value = TRUE)) > 0)

r3b <- .ggspec_table1(iris, vars = "Sepal.Length", by = "", statId = "mean_se")
chk("均值(SE)：生成成功", isTRUE(r3b$ok))

# ============================================================
# 4) 分类变量
# ============================================================
df4 <- data.frame(
  age = c(20, 30, 40, 50, 60, 70, 25, 35, 45, 55),
  sex = factor(c("男", "女", "男", "女", "男", "女", "男", "女", "男", "女")),
  arm = factor(c("A", "A", "A", "A", "A", "B", "B", "B", "B", "B"))
)
r4 <- .ggspec_table1(df4, vars = c("age", "sex"), by = "arm", statId = "mean_sd")
chk("分类变量：生成成功", isTRUE(r4$ok))
# gtsummary 会把分类变量展开为「变量名 + 各水平」多行，base 引擎压成一行
chk("分类变量：至少 2 行", nrow(r4$table) >= 2)
chk("分类变量：sex 显示计数(%)",
    any(grepl("\\d+ \\(\\d+%\\)", unlist(r4$table))))
chk("分类变量：代码可执行", !inherits(run_code(r4$code, df4), "error"))

# ============================================================
# 5) 合计列
# ============================================================
r5 <- .ggspec_table1(iris, vars = "Sepal.Length", by = "Species",
                     includeOverall = TRUE, addP = FALSE)
chk("合计列：生成成功", isTRUE(r5$ok))
chk("合计列：含合计列", any(grepl("合计|Overall", names(r5$table))))

# ============================================================
# 6) 小数位控制
# ============================================================
r6 <- .ggspec_table1(iris, vars = "Sepal.Length", by = "", statId = "mean_sd", digits = 2)
chk("小数位 2：生成成功", isTRUE(r6$ok))
chk("小数位 2：显示两位", any(grepl("5\\.84\\d?", unlist(r6$table))))

# ============================================================
# 7) 边界与错误
# ============================================================
e1 <- tryCatch(.ggspec_table1(iris[0, ], vars = "Sepal.Length"), error = function(e) e)
chk("空数据应报错", inherits(e1, "error"))
e2 <- tryCatch(.ggspec_table1(iris, vars = "Sepal.Length", by = "不存在的列"), error = function(e) e)
chk("分组列不存在应报错", inherits(e2, "error"))

# 全缺失列应被忽略而不是报错
d7 <- data.frame(a = c(1, 2, 3), b = c(NA_real_, NA_real_, NA_real_))
r7 <- tryCatch(.ggspec_table1(d7) , error = function(e) e)
chk("全缺失列被忽略或报明确错误", !inherits(r7, "error") || grepl("全部为空", conditionMessage(r7)))

# ============================================================
# 8) 导出
# ============================================================
r8 <- .ggspec_table1(iris, vars = c("Sepal.Length", "Petal.Length"), by = "Species")
ex_csv <- tryCatch(.ggspec_table1_export(r8, "csv", tmp), error = function(e) e)
chk("导出 CSV 成功", !inherits(ex_csv, "error") && file.exists(file.path(tmp, ex_csv$filename)))
chk("CSV 非空", !inherits(ex_csv, "error") &&
      file.info(file.path(tmp, ex_csv$filename))$size > 100)

if (requireNamespace("writexl", quietly = TRUE)) {
  ex_xlsx <- tryCatch(.ggspec_table1_export(r8, "xlsx", tmp), error = function(e) e)
  chk("导出 XLSX 成功", !inherits(ex_xlsx, "error") && file.exists(file.path(tmp, ex_xlsx$filename)))
  chk("XLSX 非空", !inherits(ex_xlsx, "error") &&
        file.info(file.path(tmp, ex_xlsx$filename))$size > 1000)
}

if (requireNamespace("flextable", quietly = TRUE) && requireNamespace("officer", quietly = TRUE)) {
  ex_docx <- tryCatch(.ggspec_table1_export(r8, "docx", tmp), error = function(e) e)
  chk("导出 DOCX 成功", !inherits(ex_docx, "error") && file.exists(file.path(tmp, ex_docx$filename)))
  chk("DOCX 非空（>5KB）", !inherits(ex_docx, "error") &&
        file.info(file.path(tmp, ex_docx$filename))$size > 5000)
}

e3 <- tryCatch(.ggspec_table1_export(r8, "pdf", tmp), error = function(e) e)
chk("不支持的格式应报错", inherits(e3, "error"))

# ============================================================
# 9) 列信息
# ============================================================
cols <- .ggspec_table1_columns(iris)
chk("列信息：返回全部列", length(cols$all) == 5)
chk("列信息：可分组列含 Species", "Species" %in% unlist(cols$groupable))

# ============================================================
# 10) 真实数据：mtcars（二分类分组 + p 值）
# ============================================================
r10 <- .ggspec_table1(mtcars, vars = c("mpg", "wt", "hp"), by = "am",
                      statId = "mean_sd", addP = TRUE)
chk("mtcars：生成成功", isTRUE(r10$ok))
chk("mtcars：识别 2 组", length(r10$groups) == 2)
chk("mtcars：含 p 值列", any(grepl("p", names(r10$table), ignore.case = TRUE)))
chk("mtcars：代码可执行", !inherits(run_code(r10$code, mtcars), "error"))

cat(sprintf("\n===== L5 基线表: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
