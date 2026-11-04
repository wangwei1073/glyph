# ggplotGUI 回归测试：展示代码必须「真的能跑」，且跑出来的数据与渲染路径一致
# 背景：代码面板承诺「所见即代码」，此前行筛选生成的是 df[<表达式>, ]（base R 的 `[`
#       不做数据掩码求值），复制到 RStudio 必然失败；筛选 + 手工编辑时行锚还会错位。
# 运行: Rscript tests/test_codegen_exec.R

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
tmp <- file.path(tempdir(), paste0("codegen-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)
invisible(EditStore$bind(file.path(tmp, "edits.json")))

layer <- function(...) {
  base <- list(geom = "point", stat = "", position = list(type = "", params = list()),
               aes = list(x = list(map = "displ"), y = list(map = "hwy")),
               params = list(), aesParams = list())
  patch <- list(...)
  for (nm in names(patch)) base[[nm]] <- patch[[nm]]
  base
}
spec_of <- function(src, layers = list(layer()), prep = list()) {
  list(data = c(list(source = src), prep), layers = layers)
}
DS <- function(name) list(type = "dataset", name = name)

fail <- 0L; pass <- 0L
check_case <- function(name, spec, want_rid = FALSE) {
  gen <- tryCatch(ggspec_pipeline(spec, META, STATE), error = function(e) e)
  if (inherits(gen, "error")) {
    cat(sprintf("[生成失败] %s: %s\n", name, conditionMessage(gen))); fail <<- fail + 1L; return(invisible())
  }
  has_rid <- any(grepl("\\.gg_rid", strsplit(gen$code, "\n")[[1]]))
  if (has_rid != want_rid) {
    cat(sprintf("[锚列断言失败] %s: 期望 .gg_rid=%s，实际=%s\n", name, want_rid, has_rid))
    fail <<- fail + 1L
  }
  # 1) 展示代码必须能整段执行
  env <- new.env(parent = globalenv())
  err <- tryCatch({ invisible(eval(parse(text = gen$code), envir = env)); NULL },
                  error = function(e) conditionMessage(e))
  if (!is.null(err)) {
    cat(sprintf("[执行失败] %s: %s\n", name, err))
    cat(gen$code, "\n\n"); fail <<- fail + 1L; return(invisible())
  }
  # 2) 跑出来的数据必须与渲染路径一致
  d_render <- tryCatch(ggspec_resolve_data(spec, STATE), error = function(e) e)
  if (inherits(d_render, "error")) {
    cat(sprintf("[渲染数据失败] %s: %s\n", name, conditionMessage(d_render))); fail <<- fail + 1L; return(invisible())
  }
  d_copy <- get("df", env)
  d_render <- as.data.frame(d_render)
  d_copy <- as.data.frame(d_copy)
  if (!want_rid) {
    # 无编辑时锚列不参与展示代码，比较时两边一起去掉
    d_render$.gg_rid <- NULL
    d_copy$.gg_rid <- NULL
  }
  cmp <- all.equal(d_render, d_copy, check.attributes = FALSE)
  if (!isTRUE(cmp)) {
    cat(sprintf("[数据不一致] %s:\n  %s\n", name, paste(cmp, collapse = "\n  ")))
    fail <<- fail + 1L; return(invisible())
  }
  cat(sprintf("[OK] %s（%d 行）\n", name, nrow(d_copy)))
  pass <<- pass + 1L
}

# ---- 无加工 ----
check_case("mpg 原样", spec_of(DS("mpg")))
check_case("economics 原样", spec_of(DS("economics"), list(layer(aes = list(x = list(map = "date"), y = list(map = "unemploy"))))))

# ---- 行筛选（曾生成不可执行代码） ----
check_case("mpg 筛选 hwy > 20", spec_of(DS("mpg"), prep = list(filter = "hwy > 20")))
check_case("iris 因子筛选", spec_of(DS("iris"), list(layer(aes = list(x = list(map = "Sepal.Length"), y = list(map = "Petal.Length")))),
                                 prep = list(filter = "Species == 'setosa'")))
check_case("筛选 + 新增列 + 抽样",
           spec_of(DS("mpg"), prep = list(filter = "hwy > 20",
                                          mutate = list(list(name = "ratio", expr = "hwy / displ")),
                                          sample = 100, seed = 42)))

# ---- 手工编辑（行锚） ----
EditStore$clear("dataset:mpg")
EditStore$add("dataset:mpg", list(kind = "cell", rid = 5, col = "hwy", value = 99))
EditStore$add("dataset:mpg", list(kind = "rowDel", rid = 9))
check_case("mpg + 编辑（无筛选）", spec_of(DS("mpg")), want_rid = TRUE)
check_case("mpg + 筛选 + 编辑（锚列必须在筛选之前）",
           spec_of(DS("mpg"), prep = list(filter = "displ > 2")), want_rid = TRUE)
EditStore$clear("dataset:mpg")

# ---- 用户上传数据（内联） ----
uid <- DataStore$add(ggspec_with_rid(data.frame(a = 1:5, b = c(2.2, 4.1, 5.9, 8.2, 10.1),
                                                c = c("甲", "乙", "甲", "乙", "甲"))), "内联数据")
check_case("内联用户数据（不得泄露 .gg_rid）",
           spec_of(list(type = "user", id = uid),
                   list(layer(aes = list(x = list(map = "a"), y = list(map = "b"))))))
EditStore$add(paste0("user:", uid), list(kind = "cell", rid = 2, col = "b", value = 77))
check_case("内联用户数据 + 编辑",
           spec_of(list(type = "user", id = uid),
                   list(layer(aes = list(x = list(map = "a"), y = list(map = "b"))))),
           want_rid = TRUE)

cat(sprintf("\n===== 代码可执行性: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
