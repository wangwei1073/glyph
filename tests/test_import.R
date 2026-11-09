# 数据导入（P0）：文件会话 / 预览 / 提交 / SQLite
# 运行: Rscript tests/test_import.R

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

store_dir <- file.path(tempdir(), paste0("imp-store-", as.integer(Sys.time())))
DataStore$bind(store_dir)

## ---- 1. CSV 文件 ----
csv <- "group,value,when\nA,1.5,2024-01-02\nB,2.5,2024-01-03\nA,3.5,2024-01-04\n"
s <- import_upload("test.csv", "csv", jsonlite::base64_enc(charToRaw(csv)))
ok("上传返回 token", nzchar(s$token))
p <- import_preview(s$token, list(delim = "comma", encoding = "UTF-8", header = TRUE))
ok("预览 3 行", identical(p$previewRows, 3L))
ok("列类型：字符/数值/日期",
   identical(vapply(p$columns, `[[`, "", "type"), c("chr", "num", "date")))
ok("预览行可 JSON 化", length(p$rows) == 3 && identical(p$rows[[1]]$group, "A"))

cm <- import_commit_file(s$token, list(delim = "comma"), "测试 CSV")
ok("提交返回数据源", !is.null(cm$info) && cm$info$nrow == 3)
ok("来源记录为 file", identical(cm$info$origin$kind, "file") &&
     identical(cm$info$origin$file, "test.csv"))

## ---- 2. 来源持久化（重新 bind 后仍在）----
DataStore$bind(store_dir)
it <- DataStore$info(cm$id)
ok("重新加载后来源仍在", !is.null(it) && identical(it$origin$file, "test.csv"))

## ---- 3. 不支持的类型 ----
err <- tryCatch(import_upload("x.zip", "zip", ""), error = function(e) e)
ok("拒绝不支持的类型", inherits(err, "error"))

## ---- 4. SQLite（驱动缺失则跳过）----
if (!requireNamespace("RSQLite", quietly = TRUE)) {
  cat("[SKIP] SQLite 驱动（RSQLite）未安装，跳过数据库用例\n")
} else {
  db <- file.path(tempdir(), paste0("imp-", as.integer(Sys.time()), ".sqlite"))
  con <- DBI::dbConnect(RSQLite::SQLite(), db)
  DBI::dbWriteTable(con, "patients",
                    data.frame(id = 1:5, age = c(50, 60, 45, 70, 55),
                               arm = c("A", "B", "A", "B", "A")))
  DBI::dbDisconnect(con)
  sdb <- import_upload("cohort.sqlite", "sqlite",
                       jsonlite::base64_enc(readBin(db, "raw", file.info(db)$size)))
  tabs <- .import_sqlite_tables(sdb$token)
  ok("SQLite 列出表", any(vapply(tabs, function(t) identical(t$name, "patients"), TRUE)))
  pv <- .import_sqlite_preview(sdb$token, "patients", 100)
  ok("SQLite 预览 5 行", identical(pv$previewRows, 5L))
  cd <- import_commit_sqlite(sdb$token, "patients", "cohort")
  ok("SQLite 导入成功", !is.null(cd$info) && cd$info$nrow == 5)
  ok("SQLite 来源记录", identical(cd$info$origin$kind, "sqlite") &&
       identical(cd$info$origin$table, "patients"))
  unlink(db)
}

cat(sprintf("\n===== 数据导入测试: %d 通过 / %d 失败 =====\n", pass, fail))
unlink(store_dir, recursive = TRUE)
quit(status = if (fail > 0) 1 else 0)
