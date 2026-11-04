# 项目数据随行：上传数据落盘 + 项目内嵌快照/手工编辑
# 运行: Rscript tests/test_project_data.R （项目根目录）
#
# 覆盖：
#   1) DataStore 落盘（meta.json + u*.rds），同进程重新 bind 可恢复
#   2) POST /api/data/snapshot 返回可解析的 CSV
#   3) POST /api/data/paste 用快照重建数据，列与内容一致
#   4) POST /api/edits/import 批量恢复手工编辑；GET /api/edits 能读回
#   5) 内置数据集不做快照（返回 400）

if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE)
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

dir <- file.path(tempdir(), paste0("ggstore-", as.integer(runif(1, 1, 1e6))))
DataStore$bind(dir)

STATE <- list(version = "1.0.0", meta = list(geoms = list()), data_store = DataStore,
              pin_store = Pins, edit_store = EditStore, raw_data = NULL,
              plot_dir = file.path(tempdir(), "ggplotgui-project"),
              dist_dir = file.path(getwd(), "dist"), allowed_hosts = "127.0.0.1")
app <- ggspec_api_app(STATE)

call_api <- function(path, method = "POST", body = "{}") {
  qs <- ""
  if (grepl("?", path, fixed = TRUE)) {
    qs <- sub("^[^?]*\\?", "", path)
    path <- sub("\\?.*$", "", path)
  }
  tmp <- tempfile()
  writeLines(body, tmp, useBytes = TRUE)
  con <- file(tmp, open = "rb")
  on.exit({ try(close(con), silent = TRUE); unlink(tmp) }, add = TRUE)
  req <- list(PATH_INFO = path, REQUEST_METHOD = method, QUERY_STRING = qs,
              HTTP_HOST = "127.0.0.1:4321", CONTENT_TYPE = "application/json", .bodyData = con)
  res <- app$call(req)
  txt <- if (is.raw(res$body)) rawToChar(res$body) else paste(as.character(res$body), collapse = "")
  list(status = as.integer(res$status), json = tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE),
                                                        error = function(e) NULL))
}

pass <- 0; fail <- 0
ok <- function(label, cond) {
  if (isTRUE(cond)) { cat("[OK]", label, "\n"); pass <<- pass + 1 }
  else { cat("[FAIL]", label, "\n"); fail <<- fail + 1 }
}

# ---- 1. 落盘 ---------------------------------------------------------------
d <- data.frame(group = c("A", "B", "A", "B"), value = c(1.5, 2.5, 3.5, 4.5),
                stringsAsFactors = FALSE)
id <- DataStore$add(d, "测试数据")
ok("数据 id 形如 uN", grepl("^u[0-9]+$", id))
ok("meta.json 存在", file.exists(file.path(dir, "meta.json")))
ok("数据 rds 存在", file.exists(file.path(dir, paste0(id, ".rds"))))
ok("rds 内容一致", identical(readRDS(file.path(dir, paste0(id, ".rds"))), d))

# 模拟重启：清空内存后重新 bind
DataStore$remove(id)
DataStore$bind(dir)
ok("重新 bind 后 rds 文件已随 remove 删除", !file.exists(file.path(dir, paste0(id, ".rds"))))
id2 <- DataStore$add(d, "测试数据2")
DataStore$bind(dir)
ok("重新 bind 后数据可读", identical(DataStore$get(id2), d))
ok("重新 bind 后 id 递增不复用", id2 != id)

# ---- 2. 快照 ---------------------------------------------------------------
r <- call_api("/api/data/snapshot", body = jsonlite::toJSON(
  list(source = list(type = "user", id = id2)), auto_unbox = TRUE))
ok("snapshot 返回 200", r$status == 200L)
csv <- r$json$csv %||% ""
ok("snapshot 含表头", grepl("group,value", csv, fixed = TRUE))
ok("snapshot 含数据行", grepl("A,1.5", csv, fixed = TRUE))

r2 <- call_api("/api/data/snapshot", body = jsonlite::toJSON(
  list(source = list(type = "dataset", name = "mpg")), auto_unbox = TRUE))
ok("内置数据集不做快照（400）", r2$status == 400L)

# ---- 3. 用快照重建 ----------------------------------------------------------
r3 <- call_api("/api/data/paste", body = jsonlite::toJSON(
  list(text = csv, label = "从项目恢复"), auto_unbox = TRUE))
new_id <- (r3$json$source %||% list())$id %||% ""
ok("paste 重建返回新 id", nzchar(new_id) && new_id != id2)
d2 <- DataStore$get(new_id)
ok("重建数据行数一致", nrow(d2) == nrow(d))
ok("重建数据列一致（忽略内部行锚 .gg_rid）",
   identical(setdiff(names(d2), ".gg_rid"), names(d)))
ok("重建后补上内部行锚", ".gg_rid" %in% names(d2) && identical(as.integer(d2$.gg_rid), seq_len(nrow(d2))))
ok("重建数据数值一致", isTRUE(all.equal(as.numeric(d2$value), as.numeric(d$value))))

# ---- 4. 手工编辑随项目恢复 ---------------------------------------------------
src <- list(type = "user", id = new_id)
op <- list(kind = "cell", rid = 1, col = "value", value = 9.9)
r4 <- call_api("/api/edits/import", body = jsonlite::toJSON(
  list(source = src, ops = list(op)), auto_unbox = TRUE, digits = NA))
ok("edits/import 返回 200", r4$status == 200L)
ok("edits/import 导入 1 条", identical(r4$json$imported, 1L))
r5 <- call_api(paste0("/api/edits?key=user:", new_id), method = "GET")
ok("GET /api/edits 读回 1 条", length(r5$json$ops %||% list()) == 1L)

# ---- 5. 图库按项目隔离 -------------------------------------------------------
jpin <- jsonlite::toJSON(list(data = list(source = list(type = "none")), layers = list()), auto_unbox = TRUE)
pa <- Pins$add(jpin, "项目A图", "proj-A")
pb <- Pins$add(jpin, "项目B图", "proj-B")
pl <- Pins$add(jpin, "旧图库")
plist <- Pins$list()
proj_of <- function(id) {
  it <- Filter(function(x) identical(x$id, id), plist)
  if (!length(it)) NA_character_ else it[[1]]$project
}
ok("图库条目带项目字段", identical(proj_of(pa), "proj-A") && identical(proj_of(pb), "proj-B"))
ok("旧图库条目 project 为空（对所有项目可见）", identical(proj_of(pl), ""))

cat(sprintf("\n===== 项目数据测试: %d 通过 / %d 失败 =====\n", pass, fail))
unlink(dir, recursive = TRUE)
quit(status = if (fail > 0) 1 else 0)
