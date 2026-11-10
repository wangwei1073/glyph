# Glyph - L1 描述统计（原型）
# 设计原则：
#   1) 只读：不改动数据，不写入 edits/pins，纯计算
#   2) 单一出口：汇总结果同时产出「表格」和「可复现 R 代码」，延续所见即代码
#   3) 零硬依赖：优先用 base R，rstatix 存在时复用（缺失则回退）
#   4) 可扩展：L2 统计检验将复用同一套「变量槽位 → 表达式」翻译层

## ---- 变量类型判定 -----------------------------------------------------------
# 分组变量要求是「可枚举」的：factor / character / logical，或唯一值很少的数值
.stats_is_groupable <- function(x, max_levels = 30L) {
  if (is.factor(x) || is.character(x) || is.logical(x)) {
    return(length(unique(as.character(x[!is.na(x)]))) <= max_levels)
  }
  if (is.numeric(x)) {
    u <- unique(x[!is.na(x)])
    return(length(u) > 1 && length(u) <= max_levels)
  }
  FALSE
}

.stats_is_numeric <- function(x) is.numeric(x) && !inherits(x, c("Date", "POSIXt"))

## ---- 描述统计核心 -----------------------------------------------------------
# 返回 list(summary = data.frame, code = character)
#   vars   : 需要汇总的数值列（字符向量，空表示全部数值列）
#   groupBy: 分组列（字符向量，可空）
.ggspec_stats_summary <- function(d, vars = character(0), groupBy = character(0)) {
  if (is.null(d) || !nrow(d)) stop("没有可用数据")
  d <- as.data.frame(d)
  d <- d[, setdiff(names(d), ".gg_rid"), drop = FALSE]

  vars <- intersect(as.character(vars %||% character(0)), names(d))
  vars <- vars[vapply(vars, function(v) .stats_is_numeric(d[[v]]), logical(1))]
  if (!length(vars)) {
    vars <- names(d)[vapply(d, .stats_is_numeric, logical(1))]
  }
  if (!length(vars)) stop("数据里没有可汇总的数值列")

  groupBy <- intersect(as.character(groupBy %||% character(0)), names(d))
  groupBy <- groupBy[!groupBy %in% vars]

  has_group <- length(groupBy) > 0

  summarise_one <- function(x) {
    x <- x[!is.na(x)]
    n <- length(x)
    if (!n) {
      return(list(n = 0L, n_missing = NA_integer_, mean = NA_real_, sd = NA_real_,
                  median = NA_real_, q1 = NA_real_, q3 = NA_real_,
                  min = NA_real_, max = NA_real_, se = NA_real_))
    }
    sd_v <- if (n > 1) stats::sd(x) else NA_real_
    list(
      n = n,
      n_missing = NA_integer_,          # 由外部填充
      mean = mean(x),
      sd = sd_v,
      median = stats::median(x),
      q1 = as.numeric(stats::quantile(x, 0.25, names = FALSE)),
      q3 = as.numeric(stats::quantile(x, 0.75, names = FALSE)),
      min = min(x),
      max = max(x),
      se = if (!is.na(sd_v)) sd_v / sqrt(n) else NA_real_
    )
  }

  rows <- list()
  if (!has_group) {
    for (v in vars) {
      s <- summarise_one(d[[v]])
      s$n_missing <- sum(is.na(d[[v]]))
      rows[[length(rows) + 1]] <- c(list(variable = v, group = "（全部）"), s)
    }
  } else {
    # 多列分组：用 interaction 生成组合标签，保持稳定顺序
    key_df <- d[, groupBy, drop = FALSE]
    key_chr <- do.call(paste, c(lapply(key_df, function(x) {
      x <- as.character(x)
      x[is.na(x)] <- "NA"
      x
    }), sep = " | "))
    lv <- unique(key_chr)
    for (v in vars) {
      for (g in lv) {
        sel <- !is.na(key_chr) & key_chr == g
        s <- summarise_one(d[[v]][sel])
        s$n_missing <- sum(is.na(d[[v]][sel]))
        rows[[length(rows) + 1]] <- c(list(variable = v, group = g), s)
      }
    }
  }

  out <- do.call(rbind, lapply(rows, function(r) {
    data.frame(
      variable = as.character(r$variable),
      group = as.character(r$group),
      n = as.integer(r$n),
      nMissing = as.integer(r$n_missing),
      mean = round(as.numeric(r$mean), 4),
      sd = round(as.numeric(r$sd), 4),
      se = round(as.numeric(r$se), 4),
      median = round(as.numeric(r$median), 4),
      q1 = round(as.numeric(r$q1), 4),
      q3 = round(as.numeric(r$q3), 4),
      min = round(as.numeric(r$min), 4),
      max = round(as.numeric(r$max), 4),
      stringsAsFactors = FALSE
    )
  }))
  rownames(out) <- NULL

  # 补充一行「合计」（有分组时）
  if (has_group) {
    tot <- do.call(rbind, lapply(vars, function(v) {
      s <- summarise_one(d[[v]])
      s$n_missing <- sum(is.na(d[[v]]))
      data.frame(
        variable = v, group = "（合计）",
        n = as.integer(s$n), nMissing = as.integer(s$n_missing),
        mean = round(as.numeric(s$mean), 4), sd = round(as.numeric(s$sd), 4),
        se = round(as.numeric(s$se), 4), median = round(as.numeric(s$median), 4),
        q1 = round(as.numeric(s$q1), 4), q3 = round(as.numeric(s$q3), 4),
        min = round(as.numeric(s$min), 4), max = round(as.numeric(s$max), 4),
        stringsAsFactors = FALSE
      )
    }))
    out <- rbind(out, tot)
  }

  list(summary = out, vars = vars, groupBy = groupBy,
       code = .ggspec_stats_summary_code(vars, groupBy))
}

## ---- 可复现代码 -------------------------------------------------------------
.ggspec_stats_summary_code <- function(vars, groupBy) {
  v <- paste(r_string(vars), collapse = ", ")
  stat_body <- c(
    "  x <- x[!is.na(x)]",
    "  c(n = length(x), mean = mean(x), sd = stats::sd(x),",
    "    median = stats::median(x), q1 = as.numeric(stats::quantile(x, .25)),",
    "    q3 = as.numeric(stats::quantile(x, .75)))"
  )
  if (!length(groupBy)) {
    # aggregate() 的 by 不接受 NULL，无分组时用 sapply 更直接
    return(c(
      "# 描述统计（均值 / 标准差 / 中位数 / 四分位 / 缺失数）",
      sprintf("sapply(df[, c(%s)], function(x) {", v),
      stat_body,
      "})"
    ))
  }
  g <- paste(r_string(groupBy), collapse = ", ")
  c(
    "# 描述统计（按分组）",
    sprintf("stats::aggregate(df[, c(%s), drop = FALSE],", v),
    sprintf("  by = df[, c(%s), drop = FALSE], FUN = function(x) {", g),
    stat_body,
    "})"
  )
}

## ---- 列的可选角色（供前端渲染下拉） -----------------------------------------
.ggspec_stats_columns <- function(d) {
  if (is.null(d)) return(list(numeric = list(), groupable = list()))
  d <- as.data.frame(d)
  nm <- setdiff(names(d), ".gg_rid")
  list(
    numeric = as.list(nm[vapply(nm, function(x) .stats_is_numeric(d[[x]]), logical(1))]),
    groupable = as.list(nm[vapply(nm, function(x) .stats_is_groupable(d[[x]]), logical(1))])
  )
}

## ---- 误差条数据集（一键均值±CI 图的前置）------------------------------------
# 从描述统计结果构建长表：variable/group/n/mean/sd/se/lower/upper。
# err: ci95（默认，t 分布 95% 置信区间）/ se / sd；分组只取第一个维度。
stats_agg <- function(d, vars = character(0), groupBy = character(0),
                      err = c("ci95", "se", "sd")) {
  err <- match.arg(err)
  if (!length(vars)) stop("请先选择数值变量")
  s <- .ggspec_stats_summary(d, vars, groupBy[1])
  sm <- s$summary
  sm <- sm[sm$group != "（合计）", , drop = FALSE]
  if (!nrow(sm)) stop("没有可聚合的统计结果：先选择数值变量")
  half <- switch(err,
    sd  = sm$sd,
    se  = sm$se,
    ci95 = ifelse(sm$n > 1, stats::qt(0.975, pmax(sm$n - 1L, 1L)) * sm$se, NA_real_))
  out <- data.frame(
    variable = sm$variable, group = sm$group, n = sm$n,
    mean = sm$mean, sd = sm$sd, se = sm$se,
    lower = round(sm$mean - half, 4), upper = round(sm$mean + half, 4),
    stringsAsFactors = FALSE)
  rownames(out) <- NULL
  has_group <- length(s$groupBy) > 0
  n_vars <- length(unique(out$variable))
  list(
    df = out,
    xSuggest = if (has_group) s$groupBy[1] else "variable",
    fillSuggest = if (n_vars > 1) "variable" else if (has_group) s$groupBy[1] else "variable",
    hasGroup = has_group, nVars = n_vars,
    errLabel = switch(err, ci95 = "95% CI", se = "±SE", sd = "±SD"))
}

## ---- 配对线数据集（配对检验结果的可视化前置）--------------------------------
# 把「数值列 + 两水平分组列」按行位置配对，转成 id/variable/value 长表。
# 行位置配对与 t.test.paired 的逐位置语义一致（同一观测两次测量按行序对应）。
stats_paired_df <- function(d, y, group) {
  y <- as.character(y)[1]
  g <- as.character(group)[1]
  if (!nzchar(y) || !y %in% names(d)) stop("数值列不存在或未选择")
  if (!nzchar(g) || !g %in% names(d)) stop("分组列不存在或未选择")
  gv <- as.character(d[[g]])
  lv <- unique(gv[!is.na(gv)])
  if (length(lv) != 2) stop(sprintf("配对线需要分组列恰好两个水平，当前 %d 个", length(lv)))
  keep <- !is.na(gv) & gv %in% lv
  d2 <- d[keep, , drop = FALSE]
  gv2 <- as.character(d2[[g]])
  n1 <- sum(gv2 == lv[1]); n2 <- sum(gv2 == lv[2])
  if (n1 != n2) stop(sprintf("两个水平的观测数不一致（%d vs %d）：逐位置配对要求成对，请检查行序", n1, n2))
  out <- data.frame(
    id = seq_len(n1),
    variable = factor(rep(lv, each = n1), levels = lv),
    value = c(d2[[y]][gv2 == lv[1]], d2[[y]][gv2 == lv[2]]),
    stringsAsFactors = FALSE)
  rownames(out) <- NULL
  list(df = out, level1 = lv[1], level2 = lv[2], y = y, group = g, n = n1)
}
