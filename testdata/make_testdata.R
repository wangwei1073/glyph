# 生成测试数据：模拟一个剂量-反应实验
#   3 个分组 × 2 性别 × 4 个时间点 × 3 个个体 = 72 行
#   设计要点（为了能测到 Glyph 的常见功能）：
#     · 分组变量（对照组 / 低剂量组 / 高剂量组）→ 颜色、分组线
#     · 时间点（0/7/14/28）→ 分类 x 轴
#     · 两个连续变量（体重、肿瘤体积）→ 误差棒、组均值
#     · 标志物浓度：与肿瘤体积相关，并**故意留约 12% 缺失**，用于测试缺失值处理
#     · 应答：只在第 28 天评价（终点指标），其余为 NA，模拟真实随访数据
set.seed(20261110)

groups <- c("对照组", "低剂量组", "高剂量组")
sexes  <- c("男", "女")
times  <- c(0, 7, 14, 28)

# 各组的肿瘤生长强度（指数增长系数）
slope_of <- c(对照组 = 1.85, 低剂量组 = 1.05, 高剂量组 = 0.32)

rows <- list()
pid <- 0L
for (g in groups) {
  for (s in sexes) {
    for (k in 1:3) {
      pid <- pid + 1L
      idv <- sprintf("M%03d", pid)
      # 个体基线（个体间差异）
      base_w <- rnorm(1, mean = if (s == "男") 23.5 else 21.0, sd = 1.4)
      base_v <- rnorm(1, mean = 95, sd = 11)
      for (t in times) {
        w <- base_w + 0.085 * t + rnorm(1, 0, 0.55)
        v <- base_v * exp(slope_of[[g]] * t / 28) + rnorm(1, 0, 6)
        v <- max(v, 5)
        # 标志物：与肿瘤体积正相关，随机缺失约 12%
        mk <- 12 + 0.155 * v + rnorm(1, 0, 3)
        marker <- if (runif(1) < 0.12) NA_real_ else round(mk, 1)
        resp <- if (t == 28) ifelse(v < 150, "是", "否") else NA_character_
        rows[[length(rows) + 1L]] <- data.frame(
          编号 = idv, 分组 = g, 性别 = s, 时间点 = t,
          体重 = round(w, 1), 肿瘤体积 = round(v, 1), 标志物浓度 = marker,
          应答 = resp, stringsAsFactors = FALSE
        )
      }
    }
  }
}
df <- do.call(rbind, rows)

out <- file.path("testdata", "dose_response.csv")
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
# 中文列名 + UTF-8；na = "" 让缺失值在 CSV 里是空字段
write.csv(df, out, row.names = FALSE, na = "", fileEncoding = "UTF-8")

cat("已生成:", normalizePath(out), "\n")
cat("行数:", nrow(df), " 列数:", ncol(df), "\n")
cat("分组:", paste(unique(df$分组), collapse = " / "), "\n")
cat("缺失的 标志物浓度:", sum(is.na(df$标志物浓度)), "/", nrow(df), "\n")
cat("第28天应答:", paste(names(table(df$应答)), table(df$应答), sep = "=", collapse = ", "), "\n")
