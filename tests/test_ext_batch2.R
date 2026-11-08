# 第二批扩展接入测试
# 运行: Rscript tests/test_ext_batch2.R
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
tmp <- file.path(tempdir(), paste0("b2-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}
spec_of <- function(geom, aes, data = "iris", position = list(type = "", params = list()),
                    params = list()) {
  list(data = list(source = list(type = "dataset", name = data)),
       layers = list(list(geom = geom, stat = "", position = position,
                          aes = aes, params = params, aesParams = list())),
       scales = list(), labs = list(), theme = list(base = "", args = list(), elements = list()))
}
run <- function(sp) {
  g <- tryCatch(spec_to_code(sp, META, STATE), error = function(e) e)
  if (inherits(g, "error")) return(list(ok = FALSE, msg = conditionMessage(g), code = NA))
  rf <- tryCatch(ggspec_render_file(g$eval_code, ggspec_resolve_data(sp, STATE),
                                    400, 300, 96, "png"), error = function(e) e)
  if (!inherits(rf, "error")) unlink(rf$path)
  list(ok = !inherits(rf, "error"),
       msg = if (inherits(rf, "error")) conditionMessage(rf) else "",
       code = g$code)
}

# ---------- 1) 注册表 ----------
cat("--- 注册表 ---\n")
chk("geom 总数 > 120", length(META$geoms) > 120)
for (n in c("ridgeline", "density_ridges", "prop_bar", "likert", "pointpath", "tilemargin")) {
  g <- META$geom_by_name[[n]]
  chk(paste0("注册 ", n), !is.null(g) && nzchar(g$label) && !identical(g$label, n))
}
chk("ggstats position 已纳入",
    all(c("likert", "diverging") %in% vapply(META$positions, function(p) p$name, "")))
chk("扩展 position 带包前缀",
    any(grepl("::", vapply(META$positions, function(p) p$fn, ""))))
chk("extensions 汇报第二批", isTRUE(META$extensions$ggridges) &&
      isTRUE(META$extensions$ggh4x) && isTRUE(META$extensions$ggstats))

# ---------- 2) ggridges 出图 ----------
cat("\n--- ggridges ---\n")
# geom_ridgeline 需要 x / y / height 三个美学（height 是脊线高度，不是密度），
# 与 geom_density_ridges（只需 x、y，自动算密度）用法不同
r1 <- run(spec_of("ridgeline", list(x = list(map = "Sepal.Length"), y = list(map = "Species"),
                                    height = list(expr = "1"))))
chk("山脊线：代码含 ggridges:: 前缀", isTRUE(grepl("ggridges::geom_ridgeline", r1$code, fixed = TRUE)))
chk("山脊线：渲染成功", isTRUE(r1$ok))
if (!r1$ok) cat("     ", substr(r1$msg, 1, 90), "\n")

# 更常用的是 density_ridges（自动算密度）
r2 <- run(spec_of("density_ridges", list(x = list(map = "Sepal.Length"), y = list(map = "Species"))))
chk("山脊密度：渲染成功", isTRUE(r2$ok))
if (!r2$ok) cat("     ", substr(r2$msg, 1, 90), "\n")
chk("山脊密度：代码含包前缀", isTRUE(grepl("ggridges::geom_density_ridges", r2$code, fixed = TRUE)))

# ---------- 3) ggh4x 出图 ----------
cat("\n--- ggh4x ---\n")
r3 <- run(spec_of("pointpath", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width"))))
chk("点路径：代码含 ggh4x:: 前缀", isTRUE(grepl("ggh4x::geom_pointpath", r3$code, fixed = TRUE)))
chk("点路径：渲染成功", isTRUE(r3$ok))
if (!r3$ok) cat("     ", substr(r3$msg, 1, 90), "\n")

# ---------- 4) ggstats 出图（含 position 特殊要求）----------
cat("\n--- ggstats ---\n")
# 用长表数据（ggstats 的 stat_prop 要求）
d_long <- data.frame(
  q = factor(rep(c("Q1", "Q2"), each = 30)),
  resp = factor(rep(c("Low", "Mid", "High"), 20), levels = c("Low", "Mid", "High"))
)
r4 <- run(spec_of("prop_bar", list(y = list(map = "q"), fill = list(map = "resp")), data = "none"))
# 该调用用的是 iris，改用直接渲染验证
rf4 <- tryCatch({
  g <- spec_to_code(spec_of("prop_bar", list(y = list(map = "Species"), fill = list(map = "Species"))),
                    META, STATE)
  ggspec_render_file(g$eval_code, iris, 400, 300, 96, "png")
}, error = function(e) e)
chk("比例条：可渲染", !inherits(rf4, "error"))
if (!inherits(rf4, "error")) unlink(rf4$path)
if (inherits(rf4, "error")) cat("     ", substr(conditionMessage(rf4), 1, 90), "\n")

# likert 必须显式 position_likert
sp_lik <- spec_of("likert", list(y = list(map = "Species"), fill = list(map = "Species")),
                  position = list(type = "likert", params = list()))
g_lik <- tryCatch(spec_to_code(sp_lik, META, STATE), error = function(e) e)
chk("Likert：代码生成成功", !inherits(g_lik, "error"))
if (!inherits(g_lik, "error")) {
  chk("Likert：position 带 ggstats:: 前缀",
      grepl("ggstats::position_likert", g_lik$code, fixed = TRUE))
  rf_lik <- tryCatch(ggspec_render_file(g_lik$eval_code, iris, 400, 300, 96, "png"),
                     error = function(e) e)
  chk("Likert：渲染成功", !inherits(rf_lik, "error"))
  if (!inherits(rf_lik, "error")) unlink(rf_lik$path)
  if (inherits(rf_lik, "error")) cat("     ", substr(conditionMessage(rf_lik), 1, 90), "\n")
}

# ---------- 5) 关闭扩展后组件消失 ----------
cat("\n--- 扩展开关 ---\n")
ext_state_bind(file.path(tmp, "ext.json"))
n_all <- length(meta_build_lookup(ggspec_build_meta())$geoms)
ext_set_enabled("ggridges", FALSE)
M_off <- meta_build_lookup(ggspec_build_meta())
chk("关闭 ggridges 后 geom 减少", length(M_off$geoms) < n_all)
chk("关闭后无 ridgeline", is.null(M_off$geom_by_name[["ridgeline"]]))
ext_set_enabled("ggridges", TRUE)
chk("恢复后 ridgeline 回来",
    !is.null(meta_build_lookup(ggspec_build_meta())$geom_by_name[["ridgeline"]]))

# 关闭 ggstats 后 position 也应消失
ext_set_enabled("ggstats", FALSE)
M_ns <- meta_build_lookup(ggspec_build_meta())
chk("关闭 ggstats 后 position_likert 消失",
    !("likert" %in% vapply(M_ns$positions, function(p) p$name, "")))
ext_set_enabled("ggstats", TRUE)

# ---------- 6) 代码可复现性 ----------
cat("\n--- 代码可复现 ---\n")
g <- spec_to_code(spec_of("ridgeline", list(x = list(map = "Sepal.Length"), y = list(map = "Species"))),
                  META, STATE)
chk("生成 library(ggridges)", grepl("library(ggridges)", g$code, fixed = TRUE))
chk("代码可解析", !inherits(tryCatch(parse(text = g$eval_code), error = function(e) e), "error"))

cat(sprintf("\n===== 第二批扩展: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
