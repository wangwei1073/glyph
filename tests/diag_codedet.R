Sys.setlocale("LC_CTYPE", ".UTF-8")
for (f in sort(list.files("R", pattern = "[.]R$", full.names = TRUE))) source(f, encoding = "UTF-8")
suppressPackageStartupMessages(library(ggplot2))
META <- meta_build_lookup(ggspec_build_meta())
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tempdir())
EditStore$bind(file.path(tempdir(), "t5.json"))
STATE$edit_store$clear("dataset:mpg")
STATE$edit_store$add("dataset:mpg", list(kind = "cell", rid = 3, col = "hwy", value = 41.5))
STATE$edit_store$add("dataset:mpg", list(kind = "colRen", from = "hwy", to = "hwy_new"))
STATE$edit_store$add("dataset:mpg", list(kind = "rowDel", rid = 9))
spec <- list(data = list(source = list(type = "dataset", name = "mpg")), layers = list())
gen <- ggspec_pipeline(spec, META, STATE)
code <- gen$code
pattern <- 'df\\$hwy_new\\[df\\$\\.gg_rid == 3\\] <- 41\\.5'
cat("grepRes:", grepl(pattern, code, perl = TRUE), "\n")
m <- regexpr(pattern, code, perl = TRUE)
cat("match:", m, "| seg:", substr(substr(code, m, m + 70), 1, 70), "\n")
# 找出 df$hwy_new 行的确切字节
lines <- unlist(strsplit(code, "\n", fixed = TRUE))
for (l in lines) if (grepl("hwy_new", l, fixed = TRUE)) {
  cat("LINE[", l, "]\n  chars:", paste(as.integer(utf8ToInt(l)), collapse = ","), "\n", sep = " ")
}
