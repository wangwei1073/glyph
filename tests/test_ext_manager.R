# 扩展开关测试
# 运行: Rscript tests/test_ext_manager.R
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) invisible(try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE))
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

tmp <- file.path(tempdir(), paste0("extm-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
state_file <- file.path(tmp, "extensions.json")
ext_state_bind(state_file)

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}
ng <- function() length(meta_build_lookup(ggspec_build_meta())$geoms)
ns <- function() length(meta_build_lookup(ggspec_build_meta())$scales)

# ---------- 1) 清单与状态 ----------
cat("--- 清单 ---\n")
cat0 <- ext_catalog()
chk("清单非空", length(cat0) >= 8)
chk("清单含 ggside", any(vapply(cat0, function(e) e$id == "ggside", logical(1))))
chk("每项有 label/desc/pkg", all(vapply(cat0, function(e) {
  nzchar(e$label) && nzchar(e$desc) && nzchar(e$pkg)
}, logical(1))))
chk("已安装项 installed=TRUE", isTRUE(Filter(function(e) e$id == "ggbeeswarm", cat0)[[1]]$installed))
chk("默认全部启用", all(vapply(Filter(function(e) e$installed, cat0),
                                function(e) isTRUE(e$enabled), logical(1))))

# ---------- 2) 关闭 ggside → geom 减少 ----------
cat("\n--- 关闭 ggside ---\n")
base_n <- ng()
chk("初始 geom 数 > 90", base_n > 90)
ext_set_enabled("ggside", FALSE)
after_side <- ng()
chk("关闭 ggside 后 geom 变少", after_side < base_n)
chk("关闭后无 xside geom",
    !any(grepl("^(x|y)side", vapply(meta_build_lookup(ggspec_build_meta())$geoms,
                                    function(g) g$name, ""))))
chk("extensions.ggside = FALSE", isFALSE(meta_build_lookup(ggspec_build_meta())$extensions$ggside))
chk("catalog 中 ggside enabled=FALSE",
    isFALSE(Filter(function(e) e$id == "ggside", ext_catalog())[[1]]$enabled))

# ---------- 3) 关闭 ggsci → scale 减少 ----------
cat("\n--- 关闭 ggsci ---\n")
s0 <- ns()
ext_set_enabled("ggsci", FALSE)
s1 <- ns()
chk("关闭 ggsci 后 scale 变少", s1 < s0)
chk("ggsci scale 已消失", !"colour|npg" %in% names(meta_build_lookup(ggspec_build_meta())$scale_fn))

# ---------- 4) 恢复 ----------
cat("\n--- 恢复 ---\n")
ext_set_enabled("ggside", TRUE)
ext_set_enabled("ggsci", TRUE)
chk("恢复后 geom 数还原", identical(ng(), base_n))
chk("恢复后 scale 数还原", identical(ns(), s0))

# ---------- 5) 持久化 ----------
cat("\n--- 持久化 ---\n")
ext_set_enabled("ggtext", FALSE)
chk("状态文件已写出", file.exists(state_file))
ext_state_bind(state_file)   # 模拟重启
chk("重启后仍记住关闭状态", isFALSE(ext_is_enabled("ggtext")))
chk("重启后 ggtext 不在 active_for('geom')", !("ggtext" %in% ext_active_for("geom")))
ext_set_enabled("ggtext", TRUE)
ext_state_bind(state_file)
chk("恢复后 ggtext 又启用", isTRUE(ext_is_enabled("ggtext")))

# ---------- 6) 关闭后组件真的不可用 ----------
cat("\n--- 关闭后注册表内容 ---\n")
ext_set_enabled("ggbeeswarm", FALSE)
M <- meta_build_lookup(ggspec_build_meta())
chk("关闭 ggbeeswarm 后无 beeswarm geom", is.null(M$geom_by_name[["beeswarm"]]))
# 仍能正常出基础图
sp <- list(data = list(source = list(type = "dataset", name = "iris")),
           layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                              aes = list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")),
                              params = list(), aesParams = list())),
           scales = list(), labs = list(), theme = list(base = "", args = list(), elements = list()))
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)
g <- tryCatch(spec_to_code(sp, M, STATE), error = function(e) e)
chk("关闭扩展后基础图仍可生成代码", !inherits(g, "error"))
rf <- tryCatch(ggspec_render_file(g$eval_code, ggspec_resolve_data(sp, STATE), 320, 240, 96, "png"),
               error = function(e) e)
chk("关闭扩展后基础图仍可渲染", !inherits(rf, "error"))
if (!inherits(rf, "error")) unlink(rf$path)
ext_set_enabled("ggbeeswarm", TRUE)

# ---------- 7) 未知扩展与边界 ----------
cat("\n--- 边界 ---\n")
e1 <- tryCatch(ext_set_enabled("no_such_pkg", FALSE), error = function(e) e)
chk("未知扩展报错", inherits(e1, "error"))
chk("重复关闭幂等", {
  ext_set_enabled("ggside", FALSE); ext_set_enabled("ggside", FALSE)
  !ext_is_enabled("ggside")
})
ext_set_enabled("ggside", TRUE)
chk("重复开启幂等", {
  ext_set_enabled("ggside", TRUE); ext_set_enabled("ggside", TRUE)
  ext_is_enabled("ggside")
})

# ---------- 8) 未安装的扩展不参与扫描 ----------
cat("\n--- 未安装扩展 ---\n")
# 用一个确实未安装的 id 构造（清单里没有就跳过）
chk("active 列表只含已安装项",
    all(vapply(unique(unlist(lapply(GGSPEC_EXTENSIONS, function(e) e$kind))), function(k) {
      all(vapply(ext_active_for(k), function(id) {
        e <- .ext_by_id(id); .ext_installed(e$pkg)
      }, logical(1)))
    }, logical(1))))

cat(sprintf("\n===== 扩展开关: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
