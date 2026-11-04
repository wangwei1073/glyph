# ggplotGUI - L3 图上显著性标注测试
# 运行: Rscript tests/test_sig_l3.R
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
tmp <- file.path(tempdir(), paste0("sig-", as.integer(Sys.time())))
dir.create(tmp, showWarnings = FALSE, recursive = TRUE)
STATE <- list(data_store = DataStore, pin_store = Pins, edit_store = EditStore,
              raw_data = NULL, plot_dir = tmp)

pass <- 0L; fail <- 0L
chk <- function(label, cond) {
  if (isTRUE(cond)) { cat(sprintf("[OK] %s\n", label)); pass <<- pass + 1L }
  else { cat(sprintf("[FAIL] %s\n", label)); fail <<- fail + 1L }
}

# 基础 spec：离散 x（Species）+ 连续 y
spec_box <- list(
  data = list(source = list(type = "dataset", name = "iris")),
  layers = list(list(geom = "boxplot", stat = "", position = list(type = "", params = list()),
                     aes = list(x = list(map = "Species"), y = list(map = "Sepal.Length")),
                     params = list(), aesParams = list())),
  scales = list(), labs = list(title = "L3 探针"),
  theme = list(base = "classic", args = list(), elements = list())
)

# ---------- 1) 括号标注（bracket）----------
spec1 <- spec_box
spec1$sigMarks <- list(
  list(kind = "bracket", group1 = "setosa", group2 = "versicolor", label = "***", yPos = 8.2),
  list(kind = "bracket", group1 = "versicolor", group2 = "virginica", label = "***", yPos = 8.8)
)
gen1 <- tryCatch(spec_to_code(spec1, META, STATE), error = function(e) e)
chk("括号标注：代码生成成功", !inherits(gen1, "error"))
if (!inherits(gen1, "error")) {
  chk("含 ggsignif 调用", grepl("ggsignif::geom_signif", gen1$code, fixed = TRUE))
  chk("含 library(ggsignif)", grepl("library(ggsignif)", gen1$code, fixed = TRUE))
  chk("comparisons 正确", grepl('c("setosa", "versicolor")', gen1$code, fixed = TRUE))
  chk("annotations 正确", grepl('annotations = c("***", "***")', gen1$code, fixed = TRUE))
  chk("代码可解析", !inherits(tryCatch(parse(text = gen1$eval_code), error = function(e) e), "error"))
  rf <- tryCatch(ggspec_render_file(gen1$eval_code, ggspec_resolve_data(spec1, STATE),
                                    width = 420, height = 320, dpi = 96, format = "png"),
                 error = function(e) e)
  chk("括号标注：渲染成功", !inherits(rf, "error"))
  if (!inherits(rf, "error")) unlink(rf$path)
}

# ---------- 2) 文字标注（text）----------
spec2 <- spec_box
spec2$sigMarks <- list(
  list(kind = "text", group1 = "setosa", group2 = "virginica", label = "p < 0.001", yPos = 8.2)
)
gen2 <- tryCatch(spec_to_code(spec2, META, STATE), error = function(e) e)
chk("文字标注：代码生成成功", !inherits(gen2, "error"))
if (!inherits(gen2, "error")) {
  chk("含 ggpubr::stat_pvalue_manual", grepl("ggpubr::stat_pvalue_manual", gen2$code, fixed = TRUE))
  chk("含 library(ggpubr)", grepl("library(ggpubr)", gen2$code, fixed = TRUE))
  chk("label 内联正确", grepl('"p < 0.001"', gen2$code, fixed = TRUE))
  chk("代码可解析", !inherits(tryCatch(parse(text = gen2$eval_code), error = function(e) e), "error"))
  rf2 <- tryCatch(ggspec_render_file(gen2$eval_code, ggspec_resolve_data(spec2, STATE),
                                     width = 420, height = 320, dpi = 96, format = "png"),
                  error = function(e) e)
  chk("文字标注：渲染成功", !inherits(rf2, "error"))
  if (!inherits(rf2, "error")) unlink(rf2$path)
}

# ---------- 3) 自动 y 位置（不指定 yPos）----------
spec3 <- spec_box
spec3$sigMarks <- list(
  list(kind = "bracket", group1 = "setosa", group2 = "versicolor", label = "*"),
  list(kind = "bracket", group1 = "versicolor", group2 = "virginica", label = "*")
)
gen3 <- tryCatch(spec_to_code(spec3, META, STATE), error = function(e) e)
chk("无 yPos 时自动定位", !inherits(gen3, "error") &&
      grepl("y_position = c(", gen3$code, fixed = TRUE))
if (!inherits(gen3, "error")) {
  ys <- regmatches(gen3$code, regexpr('y_position = c\\([0-9., ]+\\)', gen3$code))
  nums <- as.numeric(strsplit(gsub("[^0-9.,]", "", ys), ",")[[1]])
  chk("自动 y 位置在数据范围之上", length(nums) == 2 && all(nums > max(iris$Sepal.Length)))
  chk("多级括号递增避让", length(nums) == 2 && nums[2] > nums[1])
  rf3 <- tryCatch(ggspec_render_file(gen3$eval_code, ggspec_resolve_data(spec3, STATE),
                                     width = 420, height = 320, dpi = 96, format = "png"),
                  error = function(e) e)
  chk("自动定位：渲染成功", !inherits(rf3, "error"))
  if (!inherits(rf3, "error")) unlink(rf3$path)
}

# ---------- 4) 无数值 y 的情况（不应崩溃）----------
spec4 <- list(
  data = list(source = list(type = "dataset", name = "iris")),
  layers = list(list(geom = "bar", stat = "", position = list(type = "", params = list()),
                     aes = list(x = list(map = "Species")), params = list(), aesParams = list())),
  scales = list(), labs = list(), theme = list(base = "classic", args = list(), elements = list()),
  sigMarks = list(list(kind = "text", group1 = "setosa", group2 = "versicolor", label = "*"))
)
gen4 <- tryCatch(spec_to_code(spec4, META, STATE), error = function(e) e)
chk("无 y 映射：不报错", !inherits(gen4, "error"))

# ---------- 5) 空标注 / 无标注 ----------
spec5 <- spec_box; spec5$sigMarks <- list()
gen5 <- tryCatch(spec_to_code(spec5, META, STATE), error = function(e) e)
chk("空 sigMarks：不产生标注代码", !inherits(gen5, "error") &&
      !grepl("geom_signif|stat_pvalue_manual", gen5$code))

spec6 <- spec_box
gen6 <- tryCatch(spec_to_code(spec6, META, STATE), error = function(e) e)
chk("无 sigMarks 字段：正常", !inherits(gen6, "error") &&
      !grepl("geom_signif|stat_pvalue_manual", gen6$code))

# ---------- 6) 标注规划 API ----------
plan <- .ggspec_sig_plan(ggspec_resolve_data(spec_box, STATE), spec_box)
chk("规划：识别离散 x", isTRUE(plan$discrete))
chk("规划：x 列名正确", identical(plan$xCol, "Species"))
chk("规划：y 列名正确", identical(plan$yCol, "Sepal.Length"))
chk("规划：3 组产生 3 个比较对", length(plan$pairs) == 3)
chk("规划：y 起点高于数据最大值", plan$yStart > max(iris$Sepal.Length))

# 连续 x 的场景
spec_num <- list(
  data = list(source = list(type = "dataset", name = "mtcars")),
  layers = list(list(geom = "point", stat = "", position = list(type = "", params = list()),
                     aes = list(x = list(map = "wt"), y = list(map = "mpg")),
                     params = list(), aesParams = list())),
  scales = list(), labs = list(), theme = list(base = "classic", args = list(), elements = list())
)
plan2 <- .ggspec_sig_plan(ggspec_resolve_data(spec_num, STATE), spec_num)
chk("规划：连续 x 不产生比较对", length(plan2$pairs) == 0)
chk("规划：连续 x 标记为非离散", isFALSE(plan2$discrete))

# ---------- 7) 与 L2 检验结果联动（端到端）----------
d_iris2 <- iris[iris$Species != "virginica", ]
res <- .ggspec_stats_test(d_iris2, y = "Sepal.Length", group = "Species", method = "t.test")
chk("L2 检验可算 p", is.finite(res$p))
spec7 <- spec_box
spec7$data <- list(source = list(type = "dataset", name = "iris"),
                   filter = "Species != 'virginica'")
spec7$sigMarks <- list(list(kind = "bracket", group1 = "setosa", group2 = "versicolor",
                            label = if (res$p < 0.001) "***" else "n.s."))
gen7 <- tryCatch(spec_to_code(spec7, META, STATE), error = function(e) e)
chk("L2+L3 联动：代码生成", !inherits(gen7, "error"))
chk("L2+L3 联动：标注为 ***", grepl('"\\*\\*\\*"', gen7$code))
if (!inherits(gen7, "error")) {
  chk("L2+L3 联动：含筛选代码", grepl("subset(", gen7$code, fixed = TRUE))
}

# ---------- 8) y 轴自动扩展（防止标注被裁 / 挤压标题）----------
spec8 <- spec_box
spec8$sigMarks <- list(
  list(kind = "bracket", group1 = "setosa", group2 = "versicolor", label = "***"),
  list(kind = "bracket", group1 = "versicolor", group2 = "virginica", label = "***"),
  list(kind = "bracket", group1 = "setosa", group2 = "virginica", label = "n.s.")
)
gen8 <- tryCatch(spec_to_code(spec8, META, STATE), error = function(e) e)
chk("多标注：生成 y 轴扩展语句", !inherits(gen8, "error") &&
      grepl("scale_y_continuous", gen8$code, fixed = TRUE))
if (!inherits(gen8, "error")) {
  # 解析 limits 上界，必须覆盖最高标注（第 3 条 = start + 2*step）
  lim <- regmatches(gen8$code, regexpr("limits = c\\([0-9.\\-]+, [0-9.\\-]+\\)", gen8$code))
  nums <- as.numeric(strsplit(gsub("[^0-9.,\\-]", "", lim), ",")[[1]])
  d8 <- ggspec_resolve_data(spec8, STATE)
  pos8 <- .ggspec_sig_positions(d8, "Sepal.Length", 3)
  top_mark <- pos8$start + pos8$step * 2
  chk("y 上限覆盖最高标注", length(nums) == 2 && nums[2] > top_mark)
  chk("y 下限不高于数据最小值", length(nums) == 2 && nums[1] <= min(d8$Sepal.Length))
  # 渲染时不应出现「Removed ... rows」
  w <- character(0)
  rf8 <- withCallingHandlers(
    tryCatch(ggspec_render_file(gen8$eval_code, d8, 560, 400, 96, "png"), error = function(e) e),
    warning = function(e) { w <<- c(w, conditionMessage(e)); invokeRestart("muffleWarning") })
  chk("多标注渲染成功", !inherits(rf8, "error"))
  chk("无标注被裁掉的警告", !any(grepl("Removed.*rows", w)))
  if (!inherits(rf8, "error")) unlink(rf8$path)
}

# ---------- 9) 中文字体兜底（ragg 下 sans 缺字）----------
chk("字体探测函数可用", is.function(.ggspec_cjk_family))
chk("中文检测：识别中文", isTRUE(.ggspec_has_cjk("显著性")))
chk("中文检测：英文为假", isFALSE(.ggspec_has_cjk("Sepal Length")))

spec9 <- spec_box   # labs(title = "L3 探针") 含中文
spec9$labs <- list(title = "中文标题测试")
gen9 <- tryCatch(spec_to_code(spec9, META, STATE), error = function(e) e)
chk("中文标题：自动补字体", !inherits(gen9, "error") &&
      (is.null(.ggspec_cjk_family()) || grepl("element_text(family", gen9$code, fixed = TRUE)))

spec10 <- spec_box
spec10$labs <- list(title = "English Only Title")
gen10 <- tryCatch(spec_to_code(spec10, META, STATE), error = function(e) e)
chk("纯英文标题：不补字体", !inherits(gen10, "error") &&
      !grepl("element_text(family", gen10$code, fixed = TRUE))

spec11 <- spec_box
spec11$labs <- list(title = "中文标题")
spec11$theme$args <- list(base_family = "SimHei")
gen11 <- tryCatch(spec_to_code(spec11, META, STATE), error = function(e) e)
chk("用户已指定字体：不重复补", !inherits(gen11, "error") &&
      !grepl("element_text(family", gen11$code, fixed = TRUE))

cat(sprintf("\n===== L3 显著性标注: %d 通过 / %d 失败 =====\n", pass, fail))
quit(status = if (fail > 0) 1L else 0L)
