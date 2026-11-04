# ggplotGUI 拼图（patchwork）测试：图库存取 + 组合代码生成 + 渲染
# 运行: Rscript tests/test_patchwork.R

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
STATE <- list(data_store = DataStore, pin_store = Pins, raw_data = NULL,
              plot_dir = file.path(tempdir(), "ggplotgui-test-plots"))
Pins$bind(file.path(tempdir(), paste0("ggplotgui-test-pins-", as.integer(Sys.time())), ".json"))

# spec JSON（模拟前端 JSON.stringify 的单图规格）
spec_json <- function(...) {
  sp <- list(...)
  jsonlite::toJSON(sp, auto_unbox = TRUE, digits = NA)
}

# ---- 图库：保存/读取/列表/删除 ----
j1 <- spec_json(
  data = list(source = list(type = "dataset", name = "mpg")),
  layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                     aes = list(x = list(map = "displ"), y = list(map = "hwy"),
                                colour = list(map = "class")),
                     params = list(alpha = 0.8), aesParams = list(size = 2)))
)
j2 <- spec_json(
  data = list(source = list(type = "dataset", name = "economics")),
  layers = list(list(geom = "line", stat = "", position = list(type = "", params = list()),
                     aes = list(x = list(map = "date"), y = list(map = "unemploy")),
                     params = list(linewidth = 0.8), aesParams = list(colour = "#c0392b")))
)
id1 <- Pins$add(j1, "散点图")
id2 <- Pins$add(j2, "经济线图")
stopifnot(id1 == "P1", id2 == "P2")
stopifnot(is.character(Pins$get(id1)), nzchar(Pins$get(id1)))
pl <- Pins$list()
stopifnot(length(pl) == 2, pl[[1]]$label == "散点图")
cat("图库存取 OK\n")

# ---- 组合代码生成 ----
combine <- list(
  active = TRUE,
  slots = list(list(pin = "P1", op = "+"), list(pin = "P2", op = "|")),
  layout = list(ncol = 2, widths = list(expr = "c(2, 1)")),
  annotation = list(title = "拼图测试：散点 + 经济线")
)
# 组合的顶层 spec
spec <- list(
  data = list(source = list(type = "none")),
  layers = list(),
  combine = combine
)
gen <- tryCatch(ggspec_pipeline(spec, META, STATE), error = function(e) e)
stopifnot(!inherits(gen, "error"))
# 解析校验
parsed <- tryCatch(parse(text = gen$eval_code), error = function(e) e)
stopifnot(!inherits(parsed, "error"))
cat("组合代码解析 OK\n")
cat(gen$code, "\n\n")

# ---- 渲染 ----
rf <- tryCatch(ggspec_render_file(gen$eval_code, gen$env_list,
                                  width = 900, height = 500, dpi = 96, format = "png"),
               error = function(e) e)
stopifnot(!inherits(rf, "error"))
out <- file.path(getwd(), "tests", "out", "patchwork_compose.png")
file.copy(rf$path, out, overwrite = TRUE); unlink(rf$path)
cat("组合渲染 OK ->", out, "\n")

# ---- 单槽位 + 空布局参数 + guides=collect ----
combine2 <- list(active = TRUE,
                 slots = list(list(pin = "P2", op = "+"), list(pin = "P1", op = "+")),
                 layout = list(guides = "collect", nrow = 2),
                 annotation = list(tag_levels = "A"))
gen2 <- ggspec_pipeline(list(layers = list(), combine = combine2), META, STATE)
parsed2 <- tryCatch(parse(text = gen2$eval_code), error = function(e) e)
stopifnot(!inherits(parsed2, "error"))
rf2 <- tryCatch(ggspec_render_file(gen2$eval_code, gen2$env_list,
                                   width = 800, height = 700, dpi = 96, format = "png"),
                error = function(e) e)
stopifnot(!inherits(rf2, "error"))
out2 <- file.path(getwd(), "tests", "out", "patchwork_compose2.png")
file.copy(rf2$path, out2, overwrite = TRUE); unlink(rf2$path)
cat("组合2（collect + 行排）OK ->", out2, "\n")

# ---- 引用不存在槽位的容错 ----
combine3 <- list(active = TRUE, slots = list(list(pin = "PX", op = "+")), layout = list())
err3 <- tryCatch(ggspec_pipeline(list(layers = list(), combine = combine3), META, STATE),
                 error = function(e) e)
stopifnot(inherits(err3, "error"))
cat("缺失槽位容错 OK:", conditionMessage(err3), "\n")

cat("\n===== 拼图测试全部通过 =====\n")
