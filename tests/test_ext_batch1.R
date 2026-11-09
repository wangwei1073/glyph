# 第一批扩展接入的端到端测试
# 运行: Rscript tests/test_ext_batch1.R
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
tmp <- file.path(tempdir(), paste0("ext1-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}

spec_of <- function(geom, aes, data = "iris", aesParams = list(), params = list(),
                    theme = list(base = "", args = list(), elements = list())) {
  list(data = list(source = list(type = "dataset", name = data)),
       layers = list(list(geom = geom, stat = "",
                          position = list(type = "", params = list()),
                          aes = aes, params = params, aesParams = aesParams)),
       scales = list(), labs = list(), theme = theme)
}
# 注意：aes 的键是「美学名」(x/y/colour/label)，值是 {map: 列名}。
# 不要写成 A(列名 = "列名")，那会把列名当成美学名。

# ---------- 1) 函数名前缀 ----------
cat("--- 函数限定名 ---\n")
chk(".qualified_fn 扩展包加前缀", identical(.qualified_fn("geom_beeswarm", "ggbeeswarm"), "ggbeeswarm::geom_beeswarm"))
chk(".qualified_fn ggplot2 保持裸名", identical(.qualified_fn("geom_point", "ggplot2"), "geom_point"))
chk(".qualified_fn 已带前缀不重复加", identical(.qualified_fn("a::b", "ggtext"), "a::b"))
chk(".qualified_fn 空串安全", identical(.qualified_fn("", "ggtext"), ""))

# ---------- 2) 各扩展 geom 的代码生成 + 渲染 ----------
cat("\n--- 扩展 geom 出图 ---\n")
cases <- list(
  list(nm = "ggbeeswarm 蜂群图", geom = "beeswarm",
       aes = list(x = list(map = "Species"), y = list(map = "Sepal.Length")),
       want = "ggbeeswarm::geom_beeswarm"),
  list(nm = "ggbeeswarm 准随机", geom = "quasirandom",
       aes = list(x = list(map = "Species"), y = list(map = "Sepal.Length")),
       want = "ggbeeswarm::geom_quasirandom"),
  list(nm = "ggtext 富文本", geom = "richtext",
       aes = list(x = list(map = "Species"), y = list(map = "Sepal.Length"),
                  label = list(expr = '"<b>x</b>"')),
       want = "ggtext::geom_richtext"),
  list(nm = "ggpubr 显著性", geom = "signif",
       aes = list(x = list(map = "Species"), y = list(map = "Sepal.Length")),
       want = "ggpubr::geom_signif"),
  list(nm = "ggside 边际直方", geom = "xsidehistogram",
       aes = list(x = list(map = "Sepal.Length")),
       want = "ggside::geom_xsidehistogram")
)
has_stringi <- requireNamespace("stringi", quietly = TRUE)
for (cs in cases) {
  # ggtext 的 gridtext 渲染依赖 stringi；缺依赖时跳过该用例
  if (identical(cs$nm, "ggtext 富文本") && !has_stringi) {
    cat("  [SKIP] ggtext 富文本：缺少 stringi 运行时依赖\n")
    next
  }
  sp <- spec_of(cs$geom, cs$aes)
  g <- tryCatch(spec_to_code(sp, META, STATE), error = function(e) e)
  if (inherits(g, "error")) {
    cat(sprintf("  %-16s 代码生成失败: %s\n", cs$nm, conditionMessage(g)))
    chk(cs$nm, FALSE); next
  }
  has_prefix <- grepl(cs$want, g$code, fixed = TRUE)
  rf <- tryCatch(ggspec_render_file(g$eval_code, ggspec_resolve_data(sp, STATE),
                                    420, 320, 96, "png"), error = function(e) e)
  rendered <- !inherits(rf, "error")
  if (rendered) unlink(rf$path)
  chk(paste0(cs$nm, "：代码含包前缀"), has_prefix)
  chk(paste0(cs$nm, "：渲染成功"), rendered)
  if (!rendered) cat("     渲染错误:", substr(conditionMessage(rf), 1, 90), "\n")
}

# ---------- 3) 扩展 scale / theme 也要加前缀 ----------
cat("\n--- 扩展 scale / theme ---\n")
sp_sc <- spec_of("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")))
sp_sc$scales <- list(list(aes = "colour", type = "npg", params = list(), position = "", secAxis = NULL))
g_sc <- spec_to_code(sp_sc, META, STATE)
chk("ggsci 标度加前缀", grepl("ggsci::scale_color_npg", g_sc$code, fixed = TRUE))

sp_th <- spec_of("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")),
                 theme = list(base = "few", args = list(), elements = list()))
g_th <- spec_to_code(sp_th, META, STATE)
chk("ggthemes 主题加前缀", grepl("ggthemes::theme_few", g_th$code, fixed = TRUE))

sp_rp <- spec_of("text_repel", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width"),
                                    label = list(map = "Species")))
g_rp <- spec_to_code(sp_rp, META, STATE)
chk("原有 ggrepel 仍正常加前缀", grepl("ggrepel::geom_text_repel", g_rp$code, fixed = TRUE))

# ---------- 4) ggplot2 原生不应被加前缀 ----------
sp_pt <- spec_of("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")))
g_pt <- spec_to_code(sp_pt, META, STATE)
chk("ggplot2 原生点图保持裸名", grepl("geom_point(", g_pt$code, fixed = TRUE) &&
      !grepl("ggplot2::geom_point", g_pt$code, fixed = TRUE))

# ---------- 5) 注册表完整性 ----------
cat("\n--- 注册表 ---\n")
chk("geom 总数 > 90（含扩展）", length(META$geoms) > 90)
for (n in c("beeswarm", "quasirandom", "richtext", "textbox", "signif", "bracket", "pwc")) {
  g <- META$geom_by_name[[n]]
  chk(paste0("注册 ", n), !is.null(g) && nzchar(g$label) && !identical(g$label, n))
}
chk("ggside geom 已注册（36 个）",
    sum(grepl("^(x|y)side", vapply(META$geoms, function(g) g$name, ""))) >= 30)
chk("新 geom 都有 shape 分类",
    all(vapply(c("beeswarm","richtext","signif"), function(n) {
      g <- META$geom_by_name[[n]]; !is.null(g$shape) && g$shape != "其他"
    }, logical(1))))
chk("extensions 汇报新包", isTRUE(META$extensions$ggbeeswarm) &&
      isTRUE(META$extensions$ggtext) && isTRUE(META$extensions$ggpubr))

# ---------- 6) library() 行正确 ----------
chk("ggbeeswarm 生成 library(ggbeeswarm)",
    grepl("library(ggbeeswarm)", spec_to_code(
      spec_of("beeswarm", list(x = list(map = "Species"), y = list(map = "Sepal.Length"))), META, STATE)$code,
      fixed = TRUE))
chk("ggside 生成 library(ggside)",
    grepl("library(ggside)", spec_to_code(
      spec_of("xsidehistogram", list(x = list(map = "Sepal.Length"))), META, STATE)$code,
      fixed = TRUE))

cat(sprintf("\n===== 第一批扩展接入: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
