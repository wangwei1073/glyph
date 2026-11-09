# ============================================================
#  dose_response.csv 的绘图脚本
#  数据：3 组 × 2 性别 × 4 时间点 × 3 个体 = 72 行
#  图形：A 肿瘤体积随时间变化（均值 ± 标准误）
#        B 体重与标志物浓度的关系（含线性拟合）
#
#  两种用法：
#    1) 独立运行：Rscript plot_dose_response.R
#       （自动读取同目录的 dose_response.csv）
#    2) 粘进 Glyph「高级」页：先在左侧导入这份 CSV，
#       脚本检测到环境里已有 df，就不再读文件（见下方 if）
# ============================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(patchwork)   # 多图拼版
  if (requireNamespace("ggprism", quietly = TRUE)) library(ggprism)
})

# ---- 1. 读数据 ----
# 注意：R 里 df() 是 F 分布密度函数，所以不能只判断 exists("df")，
# 必须确认它确实是个数据框。Glyph「高级」页会把导入的数据注入为 df。
injected <- exists("df", inherits = TRUE) && is.data.frame(df)
if (!injected) {
  csv <- file.path("testdata", "dose_response.csv")
  if (!file.exists(csv)) csv <- "dose_response.csv"   # 同目录运行时
  df <- read.csv(csv, fileEncoding = "UTF-8", check.names = FALSE,
                 stringsAsFactors = FALSE)
}

# ---- 2. 整理因子水平 ----
# 默认按字母序排列（0/14/28/7），必须显式指定顺序，否则折线会交叉错乱
df$分组 <- factor(df$分组, levels = c("对照组", "低剂量组", "高剂量组"))
df$时间点 <- factor(df$时间点, levels = c(0, 7, 14, 28))
df$性别 <- factor(df$性别, levels = c("男", "女"))

# 中文需要一个真实存在的字体族名。
# 不要用 windowsFonts() 注册别名 —— ragg / systemfonts 只认系统字体名，
# 别名会让每个文字元素各报一次 "font family not found"（实测 50+ 警告）。
cjk <- "Microsoft YaHei"
if (requireNamespace("systemfonts", quietly = TRUE)) {
  have <- tryCatch(systemfonts::system_fonts()$family, error = function(e) character(0))
  if (!cjk %in% have) {
    cjk <- if ("SimHei" %in% have) "SimHei"
           else if ("SimSun" %in% have) "SimSun"
           else "sans"
  }
}

# 统一的主题：Prism 期刊风（没装 ggprism 则退回极简）
base_theme <- if (exists("theme_prism")) {
  theme_prism(base_size = 12, base_family = cjk)
} else {
  theme_minimal(base_size = 12, base_family = cjk)
}

# ---- 3. A 图：肿瘤体积随时间变化 ----
# stat_summary 直接算「均值 ± 标准误」，不需要先做汇总表
pA <- ggplot(df, aes(x = 时间点, y = 肿瘤体积, colour = 分组, group = 分组)) +
  stat_summary(fun = mean, geom = "line", linewidth = 0.9) +
  stat_summary(fun = mean, geom = "point", size = 2.4) +
  stat_summary(fun.data = mean_se, geom = "errorbar",
               width = 0.14, linewidth = 0.5) +
  labs(title = "A   肿瘤体积随时间变化",
       x = "时间（天）", y = expression("肿瘤体积（mm"^3 * "）"),
       colour = "分组") +
  base_theme

# ---- 4. B 图：体重与标志物浓度 ----
# 标志物浓度有缺失（9/72），geom_smooth 会告警删行，这里显式过滤更干净
dB <- df[!is.na(df$标志物浓度), ]

pB <- ggplot(dB, aes(x = 体重, y = 标志物浓度, colour = 分组)) +
  geom_point(size = 2.6, alpha = 0.85) +
  geom_smooth(method = "lm", formula = y ~ x, se = FALSE, linewidth = 0.8) +
  labs(title = "B   体重与标志物浓度的关系",
       x = "体重（g）", y = "标志物浓度（ng/mL）",
       colour = "分组") +
  base_theme +
  # B 图的图例与 A 图完全相同（同样的分组配色），
  # 两个面板的 legend key 几何不同（A 有误差棒、B 有拟合线），
  # patchwork 无法真正合并，会并排显示成两份。关掉 B 的图例、共用 A 的。
  guides(colour = "none")

# ---- 5. 拼版与输出 ----
fig <- (pA / pB) +
  plot_annotation(
    title = "剂量-反应实验：肿瘤体积与标志物变化",
    subtitle = sprintf("n = %d 只/组，第 28 天评价", length(unique(df$编号)) / 3),
    caption = "误差棒为均值 ± 标准误",
    theme = theme(plot.title = element_text(family = cjk, face = "bold", size = 14),
                  plot.subtitle = element_text(family = cjk, size = 10),
                  plot.caption = element_text(family = cjk, size = 9, colour = "grey40"))
  ) & theme(legend.position = "top", text = element_text(family = cjk))

# 独立运行时才写文件（在 Glyph 里由界面负责导出）
if (!injected) {
  out <- "testdata/dose_response_plot.png"
  if (!dir.exists("testdata")) out <- "dose_response_plot.png"
  ggsave(out, fig, width = 7.2, height = 8.0, dpi = 300, bg = "white")
  cat("已输出:", normalizePath(out), "\n")
}

# 结尾必须是图对象本身：Glyph 用「最后一个表达式的值」取图。
# 但 Rscript 会自动打印末表达式 —— 那会用默认 pdf 设备再画一遍，
# 中文在 pdf 设备上缺字体会刷出 50+ 警告，还会留下 Rplots.pdf。
# 所以独立运行时用 invisible() 抑制打印，两种场景都干净。
if (injected) fig else invisible(fig)
