Sys.setlocale("LC_CTYPE", ".UTF-8")
for (f in sort(list.files("R", pattern = "[.]R$", full.names = TRUE))) source(f, encoding = "UTF-8")
suppressPackageStartupMessages(library(ggplot2))
META <- meta_build_lookup(ggspec_build_meta())
STATE <- list(data_store = DataStore, raw_data = NULL)
spec <- list(data = list(source = list(type = "dataset", name = "mpg")),
             layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                                aes = list(x = list(map = "displ"), y = list(map = "hwy")),
                                params = list(), aesParams = list())))
# 定位 resolve 内部哪一行
d <- dataset_load("mpg"); cat("load rid:", ".gg_rid" %in% names(d), "\n")
dp <- data_prepare(d, list()); cat("prepare ok:", nrow(dp), "\n")
key <- "dataset:mpg"
cat("edit count:", (STATE$edit_store %||% NULL)$count(key), "\n")
res <- withCallingHandlers(
  tryCatch(ggspec_resolve_data(spec, STATE), error = function(e) e),
  error = function(e) { cat("ERR:", conditionMessage(e), "\n");
    print(sys.calls()[[sys.nframe() - length(sys.calls()) + 2]]) })
cat("resolve:", if (inherits(res, "data.frame")) "OK" else class(res), "\n")
# 深挖：直接单步
if (inherits(res, "error")) {
  browser_lines <- environment()
}
