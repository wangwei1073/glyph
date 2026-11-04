Sys.setlocale("LC_CTYPE", ".UTF-8")
for (f in sort(list.files("R", pattern = "[.]R$", full.names = TRUE))) source(f, encoding = "UTF-8")
suppressPackageStartupMessages(library(ggplot2))
META <- meta_build_lookup(ggspec_build_meta())
STATE <- list(data_store = DataStore, raw_data = NULL)
spec <- list(data = list(source = list(type = "dataset", name = "mpg")),
             layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                                aes = list(x = list(map = "displ"), y = list(map = "hwy")),
                                params = list(), aesParams = list())))
gen <- ggspec_pipeline(spec, META, STATE)
cat("code ok\n")
rf <- tryCatch(ggspec_render_file(gen$eval_code, ggspec_resolve_data(spec, STATE),
                                  width = 500, height = 320, dpi = 96, format = "png"),
               error = function(e) e)
if (inherits(rf, "error")) {
  cat("ERR:", conditionMessage(rf), "\n")
  # 详细回溯
  trace_res <- withCallingHandlers(
    tryCatch(ggspec_render_file(gen$eval_code, ggspec_resolve_data(spec, STATE), width = 500, height = 320,
                                dpi = 96, format = "png"), error = function(e) e),
    error = function(e) { cat("TRACE:", paste(sys.calls() |> sapply(function(x) deparse(x)[1], USE.NAMES = FALSE), collapse = " <- "), "\n") })
} else {
  cat("render OK\n")
}
