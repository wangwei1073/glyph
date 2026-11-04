# ggplotGUI - L2 统计检验
# 设计：
#   1) 统一出口：所有检验都归一化为「一行结论」+ 可复现代码
#   2) 自动选法：按变量角色（数值/分组）与组数自动推荐检验，同时允许手动指定
#   3) 假设提示：正态性 / 方差齐性 检查结果随结果一起返回，避免误用
#   4) 效应量：能算就算（Cohen's d / eta² / Cramér's V / r），缺失则 NA
#   5) 零硬依赖：只用 base R + stats；rstatix/effectsize 存在时用于交叉校验

## ---- 检验类型表 -------------------------------------------------------------
# 每个条目描述：需要什么变量角色、适用条件、R 函数
.stats_methods <- function() {
  list(
    list(id = "t.test",        label = "两独立样本 t 检验",   family = "mean",   n_group = 2,
         need = "numeric+group", desc = "比较两组均值（参数法，要求近似正态）"),
    list(id = "wilcox.test",   label = "Mann-Whitney U 检验", family = "mean",   n_group = 2,
         need = "numeric+group", desc = "两组位置差异（非参数，不要求正态）"),
    list(id = "t.test.paired", label = "配对 t 检验",         family = "mean",   n_group = 2, paired = TRUE,
         need = "numeric+group", desc = "同一样本两次测量（需配对）"),
    list(id = "aov",           label = "单因素方差分析",      family = "mean",   n_group = 3,
         need = "numeric+group", desc = "三组及以上均值比较（参数法）"),
    list(id = "kruskal.test",  label = "Kruskal-Wallis 检验", family = "mean",   n_group = 3,
         need = "numeric+group", desc = "三组及以上位置差异（非参数）"),
    list(id = "chisq.test",    label = "卡方检验（独立性）",  family = "count",  n_group = 2,
         need = "cat+cat",       desc = "两个分类变量的关联性"),
    list(id = "fisher.test",   label = "Fisher 精确检验",     family = "count",  n_group = 2,
         need = "cat+cat",       desc = "小样本下两分类变量关联"),
    list(id = "cor.test",      label = "Pearson 相关",        family = "corr",   n_group = 0,
         need = "numeric+numeric", desc = "两连续变量线性相关"),
    list(id = "cor.test.spearman", label = "Spearman 相关",   family = "corr",   n_group = 0,
         need = "numeric+numeric", desc = "两连续变量秩相关（非参数）")
  )
}

.stats_method_by_id <- function(id) {
  ms <- .stats_methods()
  for (m in ms) if (identical(m$id, id)) return(m)
  NULL
}

## ---- 假设检查 ---------------------------------------------------------------
# 返回 list(ok = TRUE/FALSE/NA, note = "文本")
.stats_check_normality <- function(x, max_n = 5000L) {
  x <- x[!is.na(x)]
  if (length(x) < 3) return(list(ok = NA, note = "样本量过小，无法判断"))
  if (length(x) > max_n) x <- sample(x, max_n)
  p <- tryCatch(stats::shapiro.test(x)$p.value, error = function(e) NA_real_)
  if (is.na(p)) return(list(ok = NA, note = "正态性检验失败"))
  list(ok = p > 0.05,
       note = sprintf("Shapiro-Wilk p = %.3g（%s）", p,
                      if (p > 0.05) "未拒绝正态" else "偏离正态，建议用非参数检验"))
}

.stats_check_variance <- function(groups) {
  if (length(groups) < 2) return(list(ok = NA, note = ""))
  p <- tryCatch(stats::bartlett.test(groups)$p.value, error = function(e) NA_real_)
  if (is.na(p)) return(list(ok = NA, note = "方差齐性检验失败"))
  list(ok = p > 0.05,
       note = sprintf("Bartlett p = %.3g（%s）", p,
                      if (p > 0.05) "方差齐" else "方差不齐，建议 Welch 或非参数"))
}

# 配对 t 检验：需先对齐成「成对」的两列
.stats_paired_series <- function(a, b) {
  k <- min(length(a), length(b))
  if (k < 2) stop("配对检验需要至少 2 对完整观测")
  list(a = a[seq_len(k)], b = b[seq_len(k)], k = k)
}
.stats_cohen_d <- function(x, y) {
  x <- x[!is.na(x)]; y <- y[!is.na(y)]
  nx <- length(x); ny <- length(y)
  if (nx < 2 || ny < 2) return(NA_real_)
  sp <- sqrt(((nx - 1) * stats::var(x) + (ny - 1) * stats::var(y)) / (nx + ny - 2))
  if (!is.finite(sp) || sp == 0) return(NA_real_)
  (mean(x) - mean(y)) / sp
}

# eta²（方差分析效应量）
.stats_eta2 <- function(aov_fit) {
  a <- tryCatch(stats::anova(aov_fit), error = function(e) NULL)
  if (is.null(a) || nrow(a) < 1) return(NA_real_)
  ss <- a[["Sum Sq"]]
  if (length(ss) < 2) return(NA_real_)
  denom <- sum(ss, na.rm = TRUE)
  if (!is.finite(denom) || denom == 0) return(NA_real_)
  ss[1] / denom
}

# Cramér's V
.stats_cramers_v <- function(tab) {
  chi <- tryCatch(suppressWarnings(stats::chisq.test(tab)), error = function(e) NULL)
  if (is.null(chi)) return(NA_real_)
  n <- sum(tab)
  if (n == 0) return(NA_real_)
  r <- nrow(tab); k <- ncol(tab)
  denom <- n * (min(r, k) - 1)
  if (!is.finite(denom) || denom <= 0) return(NA_real_)
  sqrt(as.numeric(chi$statistic) / denom)
}

## ---- 结果组装 ---------------------------------------------------------------
.stats_result <- function(method, stat = NA_real_, df = NA_real_, p = NA_real_,
                          estimate = NA_real_, estimate_name = "", n = NA_integer_,
                          groups = character(0), notes = character(0), code = character(0),
                          extra = list()) {
  list(
    method = method$id %||% "",
    methodLabel = method$label %||% "",
    statistic = stat,
    df = df,
    p = p,
    estimate = estimate,
    estimateName = estimate_name,
    n = n,
    groups = as.list(groups),
    notes = as.list(notes),
    code = paste(code, collapse = "\n"),
    extra = extra
  )
}

## ---- 主入口 -----------------------------------------------------------------
# 参数：
#   y       : 数值列名（因变量）
#   group   : 分组列名（可为空 → 相关分析）
#   x       : 第二数值列名（相关分析时使用）
#   method  : 指定检验 id；空表示自动推荐
#   data    : 数据框（已加工）
.ggspec_stats_test <- function(d, y = "", x = "", group = "", method = "") {
  if (is.null(d) || !nrow(d)) stop("没有可用数据")
  d <- as.data.frame(d)
  d <- d[, setdiff(names(d), ".gg_rid"), drop = FALSE]
  n_total <- nrow(d)

  y <- as.character(y %||% "")
  x <- as.character(x %||% "")
  group <- as.character(group %||% "")
  method <- as.character(method %||% "")

  is_num <- function(v) v %in% names(d) && .stats_is_numeric(d[[v]])
  is_grp <- function(v) v %in% names(d) && .stats_is_groupable(d[[v]])

  # ---- 相关分析：y + x，无分组 ----
  if (!nzchar(group) && nzchar(x) && is_num(y) && is_num(x)) {
    ok <- stats::complete.cases(d[[y]], d[[x]])
    dy <- d[[y]][ok]; dx <- d[[x]][ok]
    if (length(dy) < 3) stop("有效样本不足（< 3 行）")
    # 未指定方法时默认 Pearson；显式指定 spearman 时保留
    id <- if (nzchar(method)) method else "cor.test"
    if (identical(id, "cor.test.spearman")) {
      ct <- suppressWarnings(stats::cor.test(dx, dy, method = "spearman"))
      est_name <- "rho"
      # Spearman 的 $statistic 是 S（秩统计量），rho 在 $estimate 里
      stat_val <- as.numeric(ct$estimate)
    } else {
      ct <- stats::cor.test(dx, dy, method = "pearson")
      est_name <- "r"
      stat_val <- as.numeric(ct$statistic)
    }
    norm <- .stats_check_normality(dy)
    notes <- c(norm$note)
    if (identical(id, "cor.test") && identical(norm$ok, FALSE)) {
      notes <- c(notes, "提示：因变量偏离正态，可考虑 Spearman（cor.test.spearman）")
    }
    return(.stats_result(
      .stats_method_by_id(id) %||% list(id = id, label = "相关分析"),
      stat = stat_val, df = as.numeric(ct$parameter), p = ct$p.value,
      estimate = as.numeric(ct$estimate), estimate_name = est_name, n = length(dy),
      groups = c(y, x), notes = notes,
      code = c("# 相关分析",
               if (identical(est_name, "rho"))
                 sprintf("stats::cor.test(df$%s, df$%s, method = \"spearman\")", y, x)
               else sprintf("stats::cor.test(df$%s, df$%s, method = \"pearson\")", y, x))
    ))
  }

  # ---- 均值比较：y + group ----
  if (nzchar(group) && is_num(y) && is_grp(group)) {
    ok <- !is.na(d[[y]]) & !is.na(d[[group]])
    dy <- d[[y]][ok]; dg <- as.character(d[[group]][ok])
    lv <- unique(dg)
    if (length(lv) < 2) stop("分组变量至少需要 2 个有效水平")
    groups_list <- lapply(lv, function(g) dy[dg == g])
    names(groups_list) <- lv

    # 只有 2 组时，取前两组做两样本检验（3 组以上用整体检验）
    id <- method
    if (!nzchar(id)) id <- if (length(lv) == 2) "t.test" else "aov"
    m <- .stats_method_by_id(id)
    if (is.null(m)) stop(sprintf("未知检验方法: %s", id))

    if (identical(id, "t.test") || identical(id, "t.test.paired")) {
      if (length(lv) != 2) stop("两样本 t 检验要求恰好 2 组")
      a <- groups_list[[1]]; b <- groups_list[[2]]
      if (length(a) < 2 || length(b) < 2) stop("每组的有效样本不足（< 2）")
      if (identical(id, "t.test.paired")) {
        ps <- .stats_paired_series(a, b)
        k <- ps$k
        # 配对差值若是常量，t 检验无定义，给出明确提示
        if (stats::sd(ps$a - ps$b, na.rm = TRUE) == 0) {
          stop(sprintf("配对差值恒为常数（%d 对），配对 t 检验无定义；请检查分组是否为同一样本的重复测量",
                       k))
        }
        tt <- stats::t.test(ps$a, ps$b, paired = TRUE)
        extra_note <- sprintf("按前 %d 对配对（组大小不等时截断）", k)
      } else {
        tt <- stats::t.test(a, b)
        extra_note <- ""
      }
      norm_a <- .stats_check_normality(a)
      norm_b <- .stats_check_normality(b)
      var_chk <- .stats_check_variance(list(a, b))
      notes <- c(norm_a$note, norm_b$note, var_chk$note)
      if (nzchar(extra_note)) notes <- c(notes, extra_note)
      if (identical(norm_a$ok, FALSE) || identical(norm_b$ok, FALSE)) {
        notes <- c(notes, "提示：有组偏离正态，可考虑 Mann-Whitney（wilcox.test）")
      }
      if (identical(var_chk$ok, FALSE) && !identical(id, "t.test.paired")) {
        notes <- c(notes, "提示：方差不齐，已默认使用 Welch t 检验（R 的 t.test 默认）")
      }
      return(.stats_result(
        m, stat = as.numeric(tt$statistic), df = as.numeric(tt$parameter),
        p = tt$p.value,
        estimate = .stats_cohen_d(a, b), estimate_name = "Cohen's d",
        n = length(a) + length(b),
        groups = c(sprintf("%s (n=%d)", lv[1], length(a)),
                   sprintf("%s (n=%d)", lv[2], length(b))),
        notes = notes,
        code = c("# 两样本均值比较",
                 sprintf("t.test(df$%s[df$%s == %s], df$%s[df$%s == %s])",
                         y, group, r_string(lv[1]), y, group, r_string(lv[2])))
      ))
    }

    if (identical(id, "wilcox.test")) {
      if (length(lv) != 2) stop("Mann-Whitney 检验要求恰好 2 组")
      a <- groups_list[[1]]; b <- groups_list[[2]]
      wt <- suppressWarnings(stats::wilcox.test(a, b))
      return(.stats_result(
        m, stat = as.numeric(wt$statistic), df = NA_real_, p = wt$p.value,
        estimate = NA_real_, estimate_name = "",
        n = length(a) + length(b),
        groups = c(sprintf("%s (n=%d)", lv[1], length(a)),
                   sprintf("%s (n=%d)", lv[2], length(b))),
        notes = c("非参数检验，比较分布位置（中位数）"),
        code = c("# 两样本位置比较（非参数）",
                 sprintf("wilcox.test(df$%s[df$%s == %s], df$%s[df$%s == %s])",
                         y, group, r_string(lv[1]), y, group, r_string(lv[2])))
      ))
    }

    if (identical(id, "aov") || identical(id, "kruskal.test")) {
      if (length(lv) < 2) stop("方差分析至少需要 2 组")
      if (identical(id, "aov")) {
        fit <- stats::aov(dy ~ factor(dg))
        at <- summary(fit)[[1]]
        eta <- .stats_eta2(fit)
        notes <- c(.stats_check_variance(groups_list)$note)
        # 各组正态性简查（组数过多时只看前 5 组，避免刷屏）
        for (g in head(lv, 5)) {
          nc <- .stats_check_normality(groups_list[[g]])
          notes <- c(notes, sprintf("组 %s: %s", g, nc$note))
        }
        return(.stats_result(
          m, stat = at[["F value"]][1], df = at[["Df"]][1],
          p = at[["Pr(>F)"]][1], estimate = eta, estimate_name = "eta²",
          n = sum(vapply(groups_list, length, integer(1))),
          groups = sprintf("%s (n=%d)", lv, vapply(groups_list, length, integer(1))),
          notes = notes,
          code = c("# 单因素方差分析",
                   sprintf("fit <- aov(%s ~ %s, data = df)", y, group),
                   "summary(fit)")
        ))
      }
      kt <- stats::kruskal.test(dy, factor(dg))
      return(.stats_result(
        m, stat = as.numeric(kt$statistic), df = as.numeric(kt$parameter), p = kt$p.value,
        estimate = NA_real_, estimate_name = "",
        n = length(dy),
        groups = sprintf("%s (n=%d)", lv, vapply(groups_list, length, integer(1))),
        notes = c("非参数检验，比较各组分布位置"),
        code = c("# Kruskal-Wallis 检验",
                 sprintf("kruskal.test(%s ~ %s, data = df)", y, group))
      ))
    }

    stop(sprintf("方法 %s 不适用于「数值 + 分组」组合", id))
  }

  # ---- 分类关联：y + group，两者都是分类 ----
  if (nzchar(group) && !is_num(y) && is_grp(group) && y %in% names(d)) {
    ok <- !is.na(d[[y]]) & !is.na(d[[group]])
    tab <- table(as.character(d[[y]][ok]), as.character(d[[group]][ok]))
    if (nrow(tab) < 2 || ncol(tab) < 2) stop("两个分类变量都至少需要 2 个水平")
    id <- if (nzchar(method)) method else "chisq.test"
    m <- .stats_method_by_id(id)
    if (is.null(m)) stop(sprintf("未知检验方法: %s", id))
    if (identical(id, "fisher.test")) {
      ft <- stats::fisher.test(tab)
      return(.stats_result(
        m, stat = NA_real_, df = NA_real_, p = ft$p.value,
        estimate = as.numeric(ft$estimate), estimate_name = "odds ratio",
        n = sum(tab), groups = c(y, group),
        notes = c("Fisher 精确检验适用于小样本/稀疏列联表"),
        code = c("# Fisher 精确检验",
                 sprintf("fisher.test(table(df$%s, df$%s))", y, group))
      ))
    }
    ct <- suppressWarnings(stats::chisq.test(tab))
    warn <- any(ct$expected < 5)
    notes <- c(sprintf("期望频数 < 5 的格子占比 %.0f%%", 100 * mean(ct$expected < 5)))
    if (warn) notes <- c(notes, "提示：期望频数偏小，可考虑 Fisher 精确检验（fisher.test）")
    return(.stats_result(
      m, stat = as.numeric(ct$statistic), df = as.numeric(ct$parameter), p = ct$p.value,
      estimate = .stats_cramers_v(tab), estimate_name = "Cramér's V",
      n = sum(tab), groups = c(y, group), notes = notes,
      code = c("# 卡方独立性检验",
               sprintf("chisq.test(table(df$%s, df$%s))", y, group))
    ))
  }

  stop("变量组合不受支持：请选择「数值 + 分组」、「分类 + 分类」或「数值 + 数值（相关）」")
}

## ---- 自动推荐 ---------------------------------------------------------------
# 依据当前数据的列角色，推荐一组可用检验
.ggspec_stats_suggest <- function(d) {
  if (is.null(d)) return(list(methods = list(), roles = list()))
  d <- as.data.frame(d)
  nm <- setdiff(names(d), ".gg_rid")
  num <- nm[vapply(nm, function(v) .stats_is_numeric(d[[v]]), logical(1))]
  grp <- nm[vapply(nm, function(v) .stats_is_groupable(d[[v]]), logical(1))]
  grp_not_num <- setdiff(grp, num)
  methods <- list()
  if (length(num) && length(grp_not_num)) {
    methods <- c(methods, list(.stats_method_by_id("t.test"),
                               .stats_method_by_id("wilcox.test"),
                               .stats_method_by_id("aov"),
                               .stats_method_by_id("kruskal.test")))
  }
  if (length(grp_not_num) >= 2) {
    methods <- c(methods, list(.stats_method_by_id("fisher.test")))
  }
  if (length(num) >= 2) {
    methods <- c(methods, list(.stats_method_by_id("cor.test"),
                               .stats_method_by_id("cor.test.spearman")))
  }
  list(methods = methods[!vapply(methods, is.null, logical(1))],
       roles = list(numeric = as.list(num), groupable = as.list(grp),
                    categorical = as.list(grp_not_num)))
}
