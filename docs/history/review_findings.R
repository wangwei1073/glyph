# ggplotGUI 走查复现脚本（只读性质：全部用临时目录，不污染项目文件）
# 运行（项目根目录）: Rscript tests/review_findings.R
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) invisible(try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE))
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

META <- meta_build_lookup(ggspec_build_meta())
tmp_root <- file.path(tempdir(), paste0("review-", as.integer(Sys.time())))
dir.create(tmp_root, showWarnings = FALSE, recursive = TRUE)
STATE <- list(version = "1.0.0", meta = META, data_store = DataStore, pin_store = Pins,
              edit_store = EditStore, raw_data = NULL, plot_dir = tmp_root,
              dist_dir = file.path(getwd(), "dist"))
invisible(EditStore$bind(file.path(tmp_root, "edits.json")))
invisible(Pins$bind(file.path(tmp_root, "pins.json")))

hr <- function(x) cat("\n", strrep("=", 72), "\n## ", x, "\n", strrep("=", 72), "\n", sep = "")

call_api <- function(app, path, body = NULL, method = "POST", query = "") {
  tmp <- tempfile(fileext = ".json")
  if (!is.null(body)) {
    writeLines(jsonlite::toJSON(body, auto_unbox = TRUE, null = "null", digits = NA),
               tmp, useBytes = TRUE)
  } else file.create(tmp)
  con <- file(tmp, open = "rb")
  on.exit({ try(close(con), silent = TRUE); unlink(tmp) }, add = TRUE)
  req <- list(PATH_INFO = path, REQUEST_METHOD = method, QUERY_STRING = query,
              HTTP_HOST = "127.0.0.1:4321",
              CONTENT_TYPE = if (identical(method, "POST")) "application/json" else NULL,
              .bodyData = con)
  res <- app$call(req)
  txt <- rawToChar(res$body)
  list(status = res$status, txt = txt,
       json = tryCatch(jsonlite::fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL))
}

app <- ggspec_api_app(STATE)
spec_point <- function(src, prep = list(), y = "hwy") {
  list(data = c(list(source = src), prep),
       layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                          aes = list(x = list(map = "displ"), y = list(map = y)),
                          params = list(), aesParams = list())))
}

# ============================================================================
hr("A. 上传数据（user 源）在预览 / 编辑链路里是否可用")
# 模拟 data_from_upload 的产物（带 .gg_rid）
uid <- DataStore$add(ggspec_with_rid(data.frame(a = 1:5, b = c(2.2, 4.1, 5.9, 8.2, 10.1),
                                                c = c("甲", "乙", "甲", "乙", "甲"))), "复现数据")
r_id <- call_api(app, "/api/data/preview", list(source = list(type = "user", id = uid), prep = list()))
r_nm <- call_api(app, "/api/data/preview", list(source = list(type = "user", name = uid), prep = list()))
cat("前端实际发送 {type:'user', id:'", uid, "'}   -> HTTP ", r_id$status,
    "  nrow=", r_id$json$nrow %||% "NULL", "  error=", r_id$json$error %||% "-", "\n", sep = "")
cat("后端能解析  {type:'user', name:'", uid, "'} -> HTTP ", r_nm$status,
    "  nrow=", r_nm$json$nrow %||% "NULL", "\n", sep = "")
e_add <- call_api(app, "/api/edits/add",
                  list(source = list(type = "user", id = uid), prep = list(),
                       op = list(kind = "cell", rid = 1, col = "a", value = 9)))
cat("上传数据手工编辑 /api/edits/add -> HTTP ", e_add$status, " : ",
    e_add$json$error %||% "ok", "\n", sep = "")

# ============================================================================
hr("B. 预览分页越界（start > 总行数）")
r_page <- call_api(app, "/api/data/preview",
                   list(source = list(type = "dataset", name = "mpg"), prep = list(),
                        start = 1000, length = 50))
cat("请求 start=1000 / length=50，mpg 只有 234 行；返回 page.length = ",
    r_page$json$page$length %||% "NULL", "，rows 条数 = ", length(r_page$json$rows), "\n", sep = "")
cat("后端 idx = seq(1000, min(234, 1049)) 前 6 个: ",
    paste(head(seq(1000, min(234, 1049)), 6), collapse = ", "), "  <- 反向递减\n", sep = "")

# ============================================================================
hr("C. 手工编辑：把因子列改成新水平")
d0 <- ggspec_with_rid(iris)
warns <- character(0)
d1 <- withCallingHandlers(
  apply_data_edits(d0, list(list(kind = "cell", rid = 1, col = "Species", value = "新物种"))),
  warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") })
cat("Species[1]: '", as.character(d0$Species[1]), "' -> 写入 '新物种' -> 实际值: ",
    as.character(d1$Species[1]), "\n", sep = "")
cat("warning: ", if (length(warns)) paste(warns, collapse = " / ") else "（无）", "\n", sep = "")
probe <- tryCatch({ suppressWarnings(apply_data_edits(d0, list(list(kind = "cell", rid = 1, col = "Species", value = "新物种")))); TRUE },
                  error = function(e) e)
cat("预校验结果（合法编辑应放行）: ", if (inherits(probe, "error")) paste("拒绝 ->", conditionMessage(probe)) else "放行", "\n", sep = "")

# ============================================================================
hr("D1. 展示代码里的「行筛选」在 tibble 数据集上直接报错")
sp <- spec_point(list(type = "dataset", name = "mpg"), list(filter = "hwy > 20"))
gen <- ggspec_pipeline(sp, META, STATE)
cat("mpg 的类是: ", paste(class(ggplot2::mpg), collapse = "/"), "\n", sep = "")
cat("生成的数据行: ", grep("^df <- ", strsplit(gen$code, "\n")[[1]], value = TRUE), "\n", sep = "")
cat("筛选行: ", grep("行筛选", strsplit(gen$code, "\n")[[1]], value = TRUE), "\n", sep = "")
err <- tryCatch({ e2 <- new.env(parent = globalenv()); eval(parse(text = gen$code), envir = e2); NULL },
                error = function(e) conditionMessage(e))
cat("把这段代码整段执行的结果: ", if (is.null(err)) "成功" else paste("失败 ->", err), "\n", sep = "")
cat("（渲染路径本身没问题，因为 data_prepare 用 eval(expr, envir=df) 求值）\n")

# ============================================================================
hr("D2. 「筛选 + 手工编辑」时 .gg_rid 重编号，展示代码与渲染结果不一致")
EditStore$clear("dataset:mpg")
EditStore$add("dataset:mpg", list(kind = "cell", rid = 5, col = "hwy", value = 99))
sp <- spec_point(list(type = "dataset", name = "mpg"), list(filter = "displ > 2"))
gen <- ggspec_pipeline(sp, META, STATE)
d_render <- ggspec_resolve_data(sp, STATE)
lines <- strsplit(gen$code, "\n")[[1]]
lines[grep("^df <- mpg$", lines)] <- "df <- as.data.frame(mpg)"
lines[grep("行筛选", lines)] <- "df <- df[with(df, displ > 2 & !is.na(displ)), , drop = FALSE]  # 行筛选(修正写法，仅为验证行锚)"
code2 <- paste(lines, collapse = "\n")
env <- new.env(parent = globalenv())
invisible(eval(parse(text = code2), envir = env))
d_copy <- get("df", env)
cat("渲染路径：.gg_rid==5 的 hwy = ", d_render$hwy[d_render$.gg_rid == 5],
    "（原始第 5 行被改成 99）\n", sep = "")
cat("复制代码：.gg_rid==5 的 hwy = ", d_copy$hwy[d_copy$.gg_rid == 5],
    "（筛选后第 5 行，另一行被改成 99）\n", sep = "")
cat("两路数据一致（忽略行名/属性）? ",
    isTRUE(all.equal(as.data.frame(d_render), as.data.frame(d_copy), check.attributes = FALSE)), "\n", sep = "")
cat("渲染路径里被改成 99 的行: ", paste(unlist(d_render[d_render$hwy == 99, c("displ", "model")]), collapse = " / "), "\n", sep = "")
cat("复制代码里被改成 99 的行: ", paste(unlist(d_copy[d_copy$hwy == 99, c("displ", "model")]), collapse = " / "), "\n", sep = "")
cat("逐行不同的单元格数: ",
    sum(as.matrix(d_render[, c("displ", "hwy")]) != as.matrix(d_copy[, c("displ", "hwy")])), "\n", sep = "")
cat("展示代码中 .gg_rid 出现的位置:\n")
cat(paste0("  ", grep("\\.gg_rid", strsplit(gen$code, "\n")[[1]], value = TRUE), collapse = "\n"), "\n")
EditStore$clear("dataset:mpg")

# ============================================================================
hr("E. .edits_code_lines 遇到空 rowIns 会丢弃此前所有编辑语句")
bad <- .edits_code_lines(list(list(kind = "cell", rid = 1, col = "hwy", value = 1),
                              list(kind = "rowIns", values = list())), "df")
ok <- .edits_code_lines(list(list(kind = "cell", rid = 1, col = "hwy", value = 1)), "df")
cat("含空 rowIns 时生成 ", length(bad), " 行；只有 cell 时 ", length(ok), " 行（期望前者 >= 后者）\n", sep = "")

# ============================================================================
hr("F. 拼图：槽位引用缺失图库条目时运算符错位")
j <- function() jsonlite::toJSON(list(data = list(source = list(type = "dataset", name = "mpg")),
                                      layers = list(list(geom = "point", stat = "",
                                                         position = list(type = "", params = list()),
                                                         aes = list(x = list(map = "displ"), y = list(map = "hwy")),
                                                         params = list(), aesParams = list()))),
                                 auto_unbox = TRUE, digits = NA)
p1 <- Pins$add(j(), "P1图"); p2 <- Pins$add(j(), "P2图")
cb <- list(active = TRUE,
           slots = list(list(pin = p1, op = "+"), list(pin = "P不存在", op = "|"), list(pin = p2, op = "|")),
           layout = list(), annotation = list())
g <- ggspec_compose_code(cb, META, STATE)
cat("槽位 [P1, 缺失, P2]，中间槽位运算符为 '|'\n")
cat("生成的组合表达式: ", tail(strsplit(g$code, "\n")[[1]], 2)[1], "\n", sep = "")

# ============================================================================
hr("G. 注释坐标在「文本」控件里输入数字会被加引号")
sp2 <- list(data = list(source = list(type = "dataset", name = "mpg")),
            layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                               aes = list(x = list(map = "displ"), y = list(map = "hwy")),
                               params = list(), aesParams = list())),
            annotations = list(list(kind = "annotate", geom = "text",
                                    params = list(x = "5", y = "40", label = "高油耗区"))))
g2 <- spec_to_code(sp2, META, STATE)
cat("生成的注释行: ", grep("annotate\\(", strsplit(g2$code, "\n")[[1]], value = TRUE), "\n", sep = "")
err2 <- tryCatch({ ggspec_render_file(g2$eval_code, ggspec_resolve_data(sp2, STATE),
                                      width = 400, height = 300, dpi = 72); NULL },
                 error = function(e) conditionMessage(e))
cat("渲染结果: ", if (is.null(err2)) "成功" else paste("失败 ->", err2), "\n", sep = "")

# ============================================================================
hr("H. NA 字符串 / 内联数据里混入内部锚列")
cat("r_string(NA_character_) = ", r_string(NA_character_), "\n", sep = "")
g3 <- spec_to_code(spec_point(list(type = "user", id = uid)), META, STATE)
cat("内联 data.frame 里是否混入 .gg_rid 列: ",
    any(grepl("^\\.gg_rid = c\\(", strsplit(g3$code, "\n")[[1]])), "\n", sep = "")
cat(paste(head(strsplit(g3$code, "\n")[[1]], 8), collapse = "\n"), "\n")

# ============================================================================
hr("I. 筛选表达式返回数值时被当成行号")
dn <- tryCatch(data_prepare(dataset_load("mpg"), list(filter = "hwy")), error = function(e) e)
if (inherits(dn, "error")) {
  cat("报错（可接受）: ", conditionMessage(dn), "\n", sep = "")
} else {
  cat("不报错；行数 = ", nrow(dn), "（原 234），NA 行 = ", sum(is.na(dn$displ)), "\n", sep = "")
}

# ============================================================================
hr("J. 渲染超时：前端 20s 硬超时 vs 重图")
cat("api.js 对每个请求设置 AbortController 20s 超时；diamonds(53k) 平滑/plotly 常见 >20s\n")

cat("\n（复现脚本结束）\n")
