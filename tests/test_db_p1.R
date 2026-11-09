# 远程数据库（P1）：SQL 守卫 / 标识符 / 驱动清单 / 错误脱敏
# 运行: Rscript tests/test_db_p1.R
# 说明：不依赖真实数据库服务器；连接成功路径需在本地/远程实例上手工验证。

if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE)
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

pass <- 0; fail <- 0
ok <- function(label, cond) {
  if (isTRUE(cond)) { cat("[OK]", label, "\n"); pass <<- pass + 1 }
  else { cat("[FAIL]", label, "\n"); fail <<- fail + 1 }
}

## ---- SQL 守卫 ----
ok("SELECT 通过", identical(.db_clean_sql("select 1"), "select 1"))
ok("WITH 通过", grepl("^with", .db_clean_sql("WITH x AS (SELECT 1) SELECT * FROM x"),
                      ignore.case = TRUE))
ok("去掉末尾分号", identical(.db_clean_sql("select 1;  "), "select 1"))
err1 <- tryCatch(.db_clean_sql("drop table t"), error = function(e) e)
ok("拒绝 DROP", inherits(err1, "error"))
err2 <- tryCatch(.db_clean_sql("select 1; select 2"), error = function(e) e)
ok("拒绝多条语句", inherits(err2, "error"))
err3 <- tryCatch(.db_clean_sql("  "), error = function(e) e)
ok("拒绝空 SQL", inherits(err3, "error"))

## ---- 标识符 ----
ok("Postgres 双引号", identical(.db_ident("postgres", "a"), '"a"'))
ok("MySQL 反引号", identical(.db_ident("mysql", "a"), "`a`"))
ok("转义双引号", identical(.db_ident("postgres", 'a"b'), '"a""b"'))
ok("表引用带 schema", identical(.db_table_ref("postgres", "public", "t"), '"public"."t"'))
ok("表引用无 schema", identical(.db_table_ref("postgres", "", "t"), '"t"'))

## ---- 驱动清单 ----
cat2 <- db_driver_catalog()
ok("三个远程驱动", length(cat2) == 3 &&
     all(c("postgres", "mysql", "odbc") %in% vapply(cat2, `[[`, "", "id")))
ok("驱动含 installed 字段", all(vapply(cat2, function(d) "installed" %in% names(d), TRUE)))

## ---- 错误脱敏 ----
ok("短密码不破坏错误信息",
   identical(.db_sanitize("port 5432 refused", list(password = "x")), "port 5432 refused"))
ok("长密码被掩码",
   !grepl("secretpass", .db_sanitize("secretpass bad", list(password = "secretpass"))))

## ---- 未知连接 ----
e1 <- tryCatch(db_preview("nope"), error = function(e) e)
ok("未知连接：预览报错", inherits(e1, "error") && grepl("连接", conditionMessage(e1)))
e2 <- tryCatch(db_import("nope"), error = function(e) e)
ok("未知连接：导入报错", inherits(e2, "error"))
ok("断开不存在的连接安全", isTRUE(db_disconnect("nope")))

cat(sprintf("\n===== 远程数据库测试: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1 else 0)
