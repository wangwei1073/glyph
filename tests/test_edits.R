# ggplotGUI 手动编辑引擎测试
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE)
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages({ library(ggplot2) })

META <- meta_build_lookup(ggspec_build_meta())
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = file.path(tempdir(), "ggplotgui-test-edits"))
EditStore$bind(file.path(tempdir(), "ggplotgui-test", paste0("edits-", as.integer(Sys.time()), ".json")))
KEY <- "dataset:mpg"
EditStore$clear(KEY)

# 1) 加载即带锚列
d0 <- dataset_load("mpg")
stopifnot(".gg_rid" %in% names(d0), nrow(d0) == 234)
stopifnot(!any(grepl("^\\.gg_rid$", vapply(column_info(d0), function(x) x$name, ""))))

# 2) 引擎：cell / rowDel / rowIns / colRen / colDel
ops <- list(
  list(kind = "cell", rid = 1, col = "cty", value = 99),
  list(kind = "colRen", from = "cty", to = "city"),
  list(kind = "cell", rid = 2, col = "city", value = 55),           # cascade 后用新名
  list(kind = "rowDel", rid = 5),
  list(kind = "rowIns", values = list(manufacturer = "test", displ = 9.9, .gg_rid = NA,
                                      city = 10), model = NULL),
  list(kind = "colDel", col = "cyl")
)
d1 <- apply_data_edits(d0, ops)
stopifnot(d1$city[d1$.gg_rid == 1] == 99)
stopifnot(d1$city[d1$.gg_rid == 2] == 55)
stopifnot(!5 %in% d1$.gg_rid)
stopifnot(as.character(d1$manufacturer[d1$.gg_rid == max(d1$.gg_rid)]) == "test")
stopifnot(!"cyl" %in% names(d1), "city" %in% names(d1))
cat("引擎五类操作 OK\n")

# 3) codegen：锚行 + 编辑语句出现在展示代码；解析/渲染成功
STATE$edit_store$clear(KEY)
STATE$edit_store$add(KEY, list(kind = "cell", rid = 3, col = "hwy", value = 41.5))
STATE$edit_store$add(KEY, list(kind = "colRen", from = "hwy", to = "hwy_new"))
STATE$edit_store$add(KEY, list(kind = "rowDel", rid = 9))
spec <- list(data = list(source = list(type = "dataset", name = "mpg")),
             layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                                aes = list(x = list(map = "displ"), y = list(map = "hwy_new")),
                                params = list(), aesParams = list())))
gen <- ggspec_pipeline(spec, META, STATE)
code <- gen$code
cat(code, '
---
')
stopifnot(grepl("\\.gg_rid <- seq_len", code))
stopifnot(grepl('names\\(df\\)\\[names\\(df\\) == "hwy"\\] <- "hwy_new"', code, perl = TRUE))
stopifnot(grepl('df\\$hwy\\[df\\$\\.gg_rid == 3\\] <- 41\\.5', code, perl = TRUE))
stopifnot(grepl("\\.gg_rid != 9", code))
p2 <- tryCatch(parse(text = gen$eval_code), error = function(e) e)
stopifnot(!inherits(p2, "error"))
rf <- tryCatch(ggspec_render_file(gen$eval_code, gen$env_list, width = 500, height = 320,
                                  dpi = 96, format = "png"), error = function(e) e)
stopifnot(!inherits(rf, "error"))
unlink(rf$path)
cat("codegen + 渲染 OK（编辑/锚行状态）\n")
cat(gen$code, "\n\n")

# 4) 未编辑时不得出现锚行（回归）
STATE$edit_store$clear(KEY)
gen2 <- ggspec_pipeline(list(data = list(source = list(type = "dataset", name = "mpg")),
                             layers = list(list(geom = "point", stat = "",
                                                position = list(type = "", params = list()),
                                                aes = list(x = list(map = "displ"), y = list(map = "hwy")),
                                                params = list(), aesParams = list()))), META, STATE)
stopifnot(!grepl("\\.gg_rid", gen2$code))
cat("未编辑回归 OK（无锚行）\n")

# 5) 掠过/撤销
op1 <- list(kind = "cell", rid = 4, col = "cty", value = 33)
STATE$edit_store$add(KEY, op1)
last <- EditStore$pop(KEY)
stopifnot(identical(last$kind, "cell"), EditStore$count(KEY) == 0)
cat("undo pop OK\n")

# 6) 因子列：改成新水平不得静默变 NA（回归：R 默认会给非法水平产生 NA）
d_iris <- ggspec_with_rid(iris)
d_f <- apply_data_edits(d_iris, list(list(kind = "cell", rid = 1, col = "Species", value = "新物种")))
stopifnot(identical(as.character(d_f$Species[1]), "新物种"))
stopifnot("新物种" %in% levels(d_f$Species))
d_f2 <- apply_data_edits(d_iris, list(list(
  kind = "rowIns",
  values = list(Sepal.Length = 5, Sepal.Width = 3, Petal.Length = 4,
                Petal.Width = 1.2, Species = "新物种"))))
stopifnot(is.factor(d_f2$Species))
stopifnot(identical(as.character(tail(d_f2$Species, 1)), "新物种"))
cat("因子列编辑（cell / rowIns）OK\n")

cat("\n===== 手动编辑测试全部通过 =====\n")
