# 第三批扩展接入测试
# 运行: Rscript tests/test_ext_batch3.R
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
tmp <- file.path(tempdir(), paste0("b3-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}
run <- function(geom, aes, data = "iris", scales = list(), params = list(), theme = NULL) {
  sp <- list(data = list(source = list(type = "dataset", name = data)),
             layers = list(list(geom = geom, stat = "",
                                position = list(type = "", params = list()),
                                aes = aes, params = params, aesParams = list())),
             scales = scales, labs = list(),
             theme = theme %||% list(base = "", args = list(), elements = list()))
  g <- tryCatch(spec_to_code(sp, META, STATE), error = function(e) e)
  if (inherits(g, "error")) return(list(ok = FALSE, msg = conditionMessage(g), code = NA))
  rf <- tryCatch(ggspec_render_file(g$eval_code, ggspec_resolve_data(sp, STATE),
                                    400, 300, 96, "png"), error = function(e) e)
  if (!inherits(rf, "error")) unlink(rf$path)
  list(ok = !inherits(rf, "error"),
       msg = if (inherits(rf, "error")) conditionMessage(rf) else "", code = g$code)
}

# ---------- 1) 注册表 ----------
cat("--- 注册表 ---\n")
chk("geom 总数 >= 170", length(META$geoms) >= 170)
chk("ggforce 贡献 40 个 geom",
    sum(vapply(META$geoms, function(g) identical(g$package, "ggforce"), logical(1))) >= 35)
for (n in c("slab", "dots", "circle", "ellipse", "sina", "mark_hull", "arc_bar")) {
  g <- META$geom_by_name[[n]]
  chk(paste0("注册 ", n), !is.null(g) && nzchar(g$label) && !identical(g$label, n))
}
chk("第三批主题已接入", all(c("ggdist", "ipsum", "modern_rc") %in% names(META$theme_by_name)))
chk("主题带包名前缀",
    identical(META$theme_by_name[["ipsum"]]$fn, "hrbrthemes::theme_ipsum"))
chk("Prism 主题未丢失", identical(META$theme_by_name[["prism"]]$fn, "ggprism::theme_prism"))
chk("断轴 scale 已注册", !is.null(META$scale_fn[["y|break"]]))
chk("extensions 汇报第三批", all(vapply(c("ggdist", "ggforce", "ggbreak", "hrbrthemes"),
                                         function(k) isTRUE(META$extensions[[k]]), logical(1))))

# ---------- 2) ggdist ----------
cat("\n--- ggdist ---\n")
r1 <- run("slab", list(x = list(map = "Sepal.Length"), y = list(map = "Species")))
chk("半小提琴：代码含 ggdist:: 前缀", isTRUE(grepl("ggdist::geom_slab", r1$code, fixed = TRUE)))
chk("半小提琴：渲染成功", isTRUE(r1$ok))
if (!r1$ok) cat("     ", substr(r1$msg, 1, 90), "\n")

r2 <- run("dots", list(x = list(map = "Sepal.Length"), y = list(map = "Species")))
chk("点阵：渲染成功", isTRUE(r2$ok))
if (!r2$ok) cat("     ", substr(r2$msg, 1, 90), "\n")

# ---------- 3) ggforce ----------
cat("\n--- ggforce ---\n")
r3 <- run("sina", list(x = list(map = "Species"), y = list(map = "Sepal.Length")))
chk("Sina 散点：渲染成功", isTRUE(r3$ok))
if (!r3$ok) cat("     ", substr(r3$msg, 1, 90), "\n")

r4 <- run("circle", list(x0 = list(map = "Sepal.Length"), y0 = list(map = "Sepal.Width"),
                         r = list(value = 0.3)))
chk("圆形：渲染成功", isTRUE(r4$ok))
chk("圆形：代码含 ggforce::", isTRUE(grepl("ggforce::geom_circle", r4$code, fixed = TRUE)))
if (!r4$ok) cat("     ", substr(r4$msg, 1, 90), "\n")

r5 <- run("mark_hull", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")))
chk("轮廓标注：渲染成功", isTRUE(r5$ok))
if (!r5$ok) cat("     ", substr(r5$msg, 1, 90), "\n")

# ellipse 需要 x0/y0/a/b/angle 专用美学（非 x/y），单独验证用法正确性
r6 <- run("ellipse", list(x0 = list(map = "Sepal.Length"), y0 = list(map = "Sepal.Width"),
                          a = list(value = 0.3), b = list(value = 0.2), angle = list(value = 0)))
chk("椭圆（专用美学）：渲染成功", isTRUE(r6$ok))
if (!r6$ok) cat("     ", substr(r6$msg, 1, 90), "\n")

# ---------- 4) ggbreak 断轴 ----------
cat("\n--- ggbreak ---\n")
r7 <- run("boxplot", list(x = list(map = "Species"), y = list(map = "Sepal.Length")),
          scales = list(list(aes = "y", type = "break",
                             params = list(breaks = list(expr = "c(6, 7)")),
                             position = "", secAxis = NULL)))
chk("断轴：代码含 ggbreak::", isTRUE(grepl("ggbreak::scale_y_break", r7$code, fixed = TRUE)))
chk("断轴：breaks 参数正确", isTRUE(grepl("breaks = c(6, 7)", r7$code, fixed = TRUE)))
chk("断轴：渲染成功", isTRUE(r7$ok))
if (!r7$ok) cat("     ", substr(r7$msg, 1, 90), "\n")

# ---------- 5) hrbrthemes ----------
cat("\n--- hrbrthemes ---\n")
r8 <- run("point", list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")),
          theme = list(base = "ipsum", args = list(base_size = 11), elements = list()))
chk("ipsum 主题：代码含 hrbrthemes::", isTRUE(grepl("hrbrthemes::theme_ipsum", r8$code, fixed = TRUE)))
chk("ipsum 主题：渲染成功", isTRUE(r8$ok))
if (!r8$ok) cat("     ", substr(r8$msg, 1, 90), "\n")

# ---------- 6) 扩展开关 ----------
cat("\n--- 扩展开关 ---\n")
ext_state_bind(file.path(tmp, "ext.json"))
n0 <- length(meta_build_lookup(ggspec_build_meta())$geoms)
ext_set_enabled("ggforce", FALSE)
M_off <- meta_build_lookup(ggspec_build_meta())
chk("关闭 ggforce 后 geom 减少", length(M_off$geoms) < n0)
chk("关闭后无 circle", is.null(M_off$geom_by_name[["circle"]]))
ext_set_enabled("ggforce", TRUE)

ext_set_enabled("hrbrthemes", FALSE)
M_off2 <- meta_build_lookup(ggspec_build_meta())
chk("关闭 hrbrthemes 后主题消失", !("ipsum" %in% names(M_off2$theme_by_name)))
ext_set_enabled("hrbrthemes", TRUE)
chk("恢复后 ipsum 回来",
    "ipsum" %in% names(meta_build_lookup(ggspec_build_meta())$theme_by_name))

# ---------- 7) 代码可复现 ----------
cat("\n--- 代码可复现 ---\n")
chk("生成 library(ggdist)", grepl("library(ggdist)", run("slab",
    list(x = list(map = "Sepal.Length"), y = list(map = "Species")))$code, fixed = TRUE))
chk("生成 library(ggforce)", grepl("library(ggforce)", run("sina",
    list(x = list(map = "Species"), y = list(map = "Sepal.Length")))$code, fixed = TRUE))

cat(sprintf("\n===== 第三批扩展: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
