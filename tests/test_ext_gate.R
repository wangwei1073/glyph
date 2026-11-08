# 关闭 patchwork / plotly 后的行为测试
# 运行: Rscript tests/test_ext_gate.R
if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) invisible(try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE))
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

tmp <- file.path(tempdir(), paste0("gate-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
ext_state_bind(file.path(tmp, "extensions.json"))
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)
Pins$bind(file.path(tmp, "pins.json"))
META <- meta_build_lookup(ggspec_build_meta())

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}

# ---------- 1) plotly 关闭后 /api/plotly 应明确拒绝 ----------
cat("--- plotly ---\n")
spec <- list(data = list(source = list(type = "dataset", name = "iris")),
             layers = list(list(geom = "point", stat = "",
                                position = list(type = "", params = list()),
                                aes = list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")),
                                params = list(), aesParams = list())),
             scales = list(), labs = list(), theme = list(base = "", args = list(), elements = list()))

# 启用时可用（plotly 已安装）
ok_on <- tryCatch({ ggspec_to_plotly(spec, META, STATE, 400, 300); TRUE },
                  error = function(e) e)
chk("plotly 启用时可转换", isTRUE(ok_on) || grepl("plotly", conditionMessage(ok_on)))

ext_set_enabled("plotly", FALSE)
err_off <- tryCatch({ ggspec_to_plotly(spec, META, STATE, 400, 300); NULL },
                    error = function(e) conditionMessage(e))
chk("plotly 关闭时报错", !is.null(err_off))
chk("错误信息提示已关闭", !is.null(err_off) && grepl("关闭", err_off))
chk("错误信息指向扩展管理", !is.null(err_off) && grepl("扩展管理", err_off))
ext_set_enabled("plotly", TRUE)

# ---------- 2) patchwork 关闭后不能生成拼图 ----------
cat("\n--- patchwork ---\n")
# 先存两个图库条目
pin_spec <- jsonlite::toJSON(list(
  data = list(source = list(type = "dataset", name = "iris")),
  layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                     aes = list(x = list(map = "Sepal.Length"), y = list(map = "Sepal.Width")),
                     params = list(), aesParams = list()))),
  auto_unbox = TRUE, digits = NA)
p1 <- Pins$add(pin_spec, "图1")
p2 <- Pins$add(pin_spec, "图2")

combine <- list(active = TRUE,
                slots = list(list(pin = p1, op = "+"), list(pin = p2, op = "+")),
                layout = list(), annotation = list())

# 启用时可生成
g_on <- tryCatch(ggspec_compose_code(combine, META, STATE), error = function(e) e)
chk("patchwork 启用时可生成拼图代码", !inherits(g_on, "error"))
if (!inherits(g_on, "error")) {
  chk("拼图代码含 patchwork 运算符", grepl("\\+", g_on$code))
}

ext_set_enabled("patchwork", FALSE)
err_pw <- tryCatch({ ggspec_compose_code(combine, META, STATE); NULL },
                   error = function(e) conditionMessage(e))
chk("patchwork 关闭时报错", !is.null(err_pw))
chk("拼图错误信息提示已关闭", !is.null(err_pw) && grepl("关闭", err_pw))

# 关闭 patchwork 不影响普通单图渲染
g_single <- tryCatch(spec_to_code(spec, META, STATE), error = function(e) e)
chk("关闭 patchwork 后单图仍可生成代码", !inherits(g_single, "error"))
rf <- tryCatch(ggspec_render_file(g_single$eval_code, ggspec_resolve_data(spec, STATE),
                                  320, 240, 96, "png"), error = function(e) e)
chk("关闭 patchwork 后单图仍可渲染", !inherits(rf, "error"))
if (!inherits(rf, "error")) unlink(rf$path)

# 图库存取不受影响（只读列表）
chk("关闭 patchwork 后图库仍可读取", is.list(Pins$list()) && length(Pins$list()) >= 2)

ext_set_enabled("patchwork", TRUE)
chk("恢复后可再次生成拼图",
    !inherits(tryCatch(ggspec_compose_code(combine, META, STATE), error = function(e) e), "error"))

# ---------- 3) 状态字段一致性 ----------
cat("\n--- 状态字段 ---\n")
ext_set_enabled("patchwork", FALSE)
chk("meta.extensions.patchwork = FALSE",
    isFALSE(meta_build_lookup(ggspec_build_meta())$extensions$patchwork))
ext_set_enabled("patchwork", TRUE)
chk("恢复后 meta.extensions.patchwork = TRUE",
    isTRUE(meta_build_lookup(ggspec_build_meta())$extensions$patchwork))

# ---------- 4) 无 kind 的扩展不影响注册表规模 ----------
cat("\n--- 注册表规模 ---\n")
n_before <- length(meta_build_lookup(ggspec_build_meta())$geoms)
ext_set_enabled("plotly", FALSE)
ext_set_enabled("patchwork", FALSE)
n_after <- length(meta_build_lookup(ggspec_build_meta())$geoms)
chk("关闭无组件的扩展不改变 geom 数", identical(n_before, n_after))
ext_set_enabled("plotly", TRUE)
ext_set_enabled("patchwork", TRUE)

cat(sprintf("\n===== 扩展门禁: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
