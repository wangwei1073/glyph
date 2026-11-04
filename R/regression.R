# ggplotGUI - L4 回归与相关分析
# 设计：
#   1) 支持线性回归 lm、逻辑回归 glm(binomial)、泊松 glm(poisson)
#   2) 输出：整体拟合优度 + 系数表（估计/标准误/t/p/置信区间/显著性）+ 可复现代码
#   3) 变量角色自动判定：数值 → 连续自变量；分类 → 因子（自动设参照水平）
#   4) 诊断提示：样本量、完全分离、多重共线性（VIF）、残差正态性
#   5) 零硬依赖：base R + stats；broom 存在时用于交叉校验

## ---- 模型类型 ---------------------------------------------------------------
.ggspec_reg_methods <- function() {
  list(
    list(id = "lm",      label = "线性回归",        family = "gaussian", need = "numeric",
         desc = "连续因变量 ~ 一个或多个自变量"),
    list(id = "logistic",label = "逻辑回归",        family = "binomial", need = "binary",
         desc = "二分类因变量（0/1 或两水平因子）"),
    list(id = "poisson", label = "泊松回归",        family = "poisson",  need = "count",
         desc = "计数型因变量（非负整数）"),
    list(id = "corr",    label = "相关矩阵",        family = "none",     need = "numeric2",
         desc = "多个连续变量两两相关（含 p 值）")
  )
}

.ggspec_reg_method_by_id <- function(id) {
  for (m in .ggspec_reg_methods()) if (identical(m$id, id)) return(m)
  NULL
}

## ---- 变量角色 ---------------------------------------------------------------
# 因变量是否适合二分类
.stats_is_binary <- function(x) {
  x <- x[!is.na(x)]
  if (is.logical(x)) return(length(unique(x)) == 2)
  if (is.factor(x) || is.character(x)) return(length(unique(as.character(x))) == 2)
  u <- unique(x)
  length(u) == 2 && all(u %in% c(0, 1))
}

# 是否适合计数型（非负整数，取值多于 2 个）
.stats_is_count <- function(x) {
  x <- x[!is.na(x)]
  if (!is.numeric(x)) return(FALSE)
  if (length(x) < 2) return(FALSE)
  all(x >= 0) && all(abs(x - round(x)) < 1e-9) && length(unique(x)) > 2
}

## ---- 系数表整理 -------------------------------------------------------------
# 从 summary(lm/glm) 抽出系数矩阵，统一为 data.frame
.stats_coef_table <- function(fit) {
  s <- summary(fit)
  cf <- s$coefficients
  if (is.null(cf) || !nrow(cf)) return(NULL)
  est <- cf[, 1]; se <- cf[, 2]
  stat <- if (ncol(cf) >= 3) cf[, 3] else rep(NA_real_, length(est))
  p <- if (ncol(cf) >= 4) cf[, ncol(cf)] else rep(NA_real_, length(est))
  # 置信区间：优先用 confint，失败则用 est ± 1.96*se
  ci <- tryCatch(stats::confint(fit), error = function(e) NULL)
  if (is.null(ci) || nrow(ci) != length(est)) {
    lo <- est - 1.96 * se; hi <- est + 1.96 * se
  } else {
    lo <- ci[, 1]; hi <- ci[, 2]
  }
  term <- rownames(cf)
  is_glm <- inherits(fit, "glm")
  data.frame(
    term = term,
    estimate = round(as.numeric(est), 5),
    se = round(as.numeric(se), 5),
    stat = round(as.numeric(stat), 4),
    p = signif(as.numeric(p), 4),
    ciLow = round(as.numeric(lo), 5),
    ciHigh = round(as.numeric(hi), 5),
    stars = vapply(as.numeric(p), .stats_p_stars, character(1)),
    expEstimate = if (is_glm) round(exp(as.numeric(est)), 4) else NA_real_,
    stringsAsFactors = FALSE
  )
}

.stats_p_stars <- function(p) {
  if (is.na(p)) return("")
  if (p < 0.001) return("***")
  if (p < 0.01) return("**")
  if (p < 0.05) return("*")
  if (p < 0.1) return(".")
  ""
}

## ---- 拟合优度 ---------------------------------------------------------------
.stats_fit_stats <- function(fit) {
  s <- summary(fit)
  out <- list()
  if (inherits(fit, "lm") && !inherits(fit, "glm")) {
    out$r2 <- round(s$r.squared, 4)
    out$adjR2 <- round(s$adj.r.squared, 4)
    f <- s$fstatistic
    if (!is.null(f) && length(f) == 3) {
      out$fstat <- round(as.numeric(f[1]), 3)
      out$df1 <- as.integer(f[2]); out$df2 <- as.integer(f[3])
      out$p <- signif(stats::pf(f[1], f[2], f[3], lower.tail = FALSE), 4)
    }
    out$sigma <- round(s$sigma, 5)
  } else if (inherits(fit, "glm")) {
    out$deviance <- round(fit$deviance, 3)
    out$nullDeviance <- round(fit$null.deviance, 3)
    out$aov <- round(s$aic, 3)
    out$aic <- round(stats::AIC(fit), 3)
    out$pseudoR2 <- round(1 - fit$deviance / fit$null.deviance, 4)
  }
  out$n <- length(stats::residuals(fit))
  out$dfResidual <- fit$df.residual
  out
}

## ---- 诊断提示 ---------------------------------------------------------------
.stats_diagnostics <- function(fit, d, y, xs) {
  notes <- character(0)
  n <- nrow(d)
  k <- length(xs)
  if (n < 30) notes <- c(notes, sprintf("样本量较小（n=%d），系数估计可能不稳定", n))
  if (n / max(k, 1) < 10) {
    notes <- c(notes, sprintf("样本量与自变量之比为 %.1f:1，建议至少 10:1", n / max(k, 1)))
  }
  # 多重共线性（仅数值自变量、2 个以上）
  # 对每个自变量做「对其余自变量」的辅助回归，取最大 VIF = 1/(1-R²)
  if (k >= 2) {
    num_xs <- xs[vapply(xs, function(v) is.numeric(d[[v]]), logical(1))]
    if (length(num_xs) >= 2) {
      vifs <- vapply(num_xs, function(v) {
        others <- setdiff(num_xs, v)
        if (!length(others)) return(NA_real_)
        tryCatch({
          f <- stats::as.formula(sprintf("%s ~ %s", v, paste(others, collapse = " + ")))
          r2 <- summary(stats::lm(f, data = d))$r.squared
          if (!is.finite(r2) || r2 >= 1) Inf else 1 / (1 - r2)
        }, error = function(e) NA_real_)
      }, numeric(1))
      worst <- suppressWarnings(max(vifs, na.rm = TRUE))
      if (is.finite(worst) && worst > 5) {
        bad <- num_xs[which.max(vifs)]
        notes <- c(notes, sprintf("自变量存在共线性（%s 的 VIF≈%.1f），系数解释需谨慎",
                                  bad, worst))
      }
    }
  }
  # 残差正态性（仅线性回归）
  if (inherits(fit, "lm") && !inherits(fit, "glm")) {
    r <- stats::residuals(fit)
    if (length(r) >= 3 && length(r) <= 5000) {
      p <- tryCatch(stats::shapiro.test(r)$p.value, error = function(e) NA_real_)
      if (is.finite(p) && p < 0.05) {
        notes <- c(notes, sprintf("残差偏离正态（Shapiro p=%.3g），推断需谨慎", p))
      }
    }
  }
  # 逻辑回归完全分离迹象
  if (inherits(fit, "glm") && identical(fit$family$family, "binomial")) {
    se <- tryCatch(summary(fit)$coefficients[, 2], error = function(e) numeric(0))
    if (length(se) && any(se > 10, na.rm = TRUE)) {
      notes <- c(notes, "标准误异常大（可能完全分离），结果不可靠")
    }
  }
  notes
}

## ---- 主入口 -----------------------------------------------------------------
# 返回 list(ok, method, methodLabel, fit, coefs, fitStats, notes, n, code, formula)
#   y   : 因变量列名
#   xs  : 自变量列名（字符向量）
#   method: lm | logistic | poisson | corr
.ggspec_reg_fit <- function(d, y = "", xs = character(0), method = "lm") {
  if (is.null(d) || !nrow(d)) stop("没有可用数据")
  d <- as.data.frame(d)
  d <- d[, setdiff(names(d), ".gg_rid"), drop = FALSE]

  y <- as.character(y %||% "")
  xs <- as.character(xs %||% character(0))
  method <- as.character(method %||% "lm")
  if (!nzchar(y)) stop("请选择因变量")
  if (!y %in% names(d)) stop(sprintf("因变量不存在: %s", y))

  # ---- 相关矩阵 ----
  if (identical(method, "corr")) {
    vars <- unique(c(y, xs))
    vars <- vars[vars %in% names(d)]
    vars <- vars[vapply(vars, function(v) .stats_is_numeric(d[[v]]), logical(1))]
    if (length(vars) < 2) stop("相关矩阵至少需要 2 个数值变量")
    sub <- d[, vars, drop = FALSE]
    sub <- sub[stats::complete.cases(sub), , drop = FALSE]
    if (nrow(sub) < 3) stop("有效样本不足（< 3 行）")
    m <- stats::cor(sub)
    # p 值矩阵
    pm <- matrix(NA_real_, length(vars), length(vars), dimnames = list(vars, vars))
    for (i in seq_along(vars)) for (j in seq_along(vars)) {
      if (i == j) next
      pm[i, j] <- tryCatch(
        suppressWarnings(stats::cor.test(sub[[i]], sub[[j]])$p.value),
        error = function(e) NA_real_)
    }
    # 展开为长表：每对变量一行（上三角），便于前端渲染与 JSON 传输
    pairs <- list()
    if (length(vars) >= 2) {
      for (i in seq_len(length(vars) - 1)) {
        for (j in seq.int(i + 1, length(vars))) {
          pairs[[length(pairs) + 1]] <- data.frame(
            var1 = vars[i], var2 = vars[j],
            r = round(as.numeric(m[i, j]), 4),
            p = signif(as.numeric(pm[i, j]), 4),
            stars = .stats_p_stars(as.numeric(pm[i, j])),
            n = nrow(sub),
            stringsAsFactors = FALSE
          )
        }
      }
    }
    coefs <- if (length(pairs)) do.call(rbind, pairs) else data.frame()
    # 同时给出对称矩阵（供将来画热图）
    mat_out <- lapply(seq_along(vars), function(i) {
      lapply(seq_along(vars), function(j) round(as.numeric(m[i, j]), 4))
    })
    return(list(
      ok = TRUE, method = "corr", methodLabel = "相关矩阵",
      coefs = coefs, matrix = mat_out, n = nrow(sub), vars = as.list(vars),
      fitStats = list(n = nrow(sub)),
      notes = as.list("Pearson 相关；p 值未做多重比较校正，变量多时请自行校正"),
      code = paste(c(
        "# 相关矩阵",
        sprintf("vars <- c(%s)", paste(r_string(vars), collapse = ", ")),
        "round(cor(df[, vars], use = \"complete.obs\"), 3)"
      ), collapse = "\n")
    ))
  }

  m <- .ggspec_reg_method_by_id(method)
  if (is.null(m)) stop(sprintf("未知回归方法: %s", method))
  if (!length(xs)) stop("请至少选择一个自变量")
  xs <- xs[xs %in% names(d)]
  if (!length(xs)) stop("自变量在数据中不存在")
  if (y %in% xs) xs <- setdiff(xs, y)

  # 因变量类型校验
  yv <- d[[y]]
  if (identical(method, "lm") && !.stats_is_numeric(yv)) {
    stop("线性回归需要数值型因变量")
  }
  if (identical(method, "logistic") && !.stats_is_binary(yv)) {
    stop("逻辑回归需要二分类因变量（0/1 或两水平因子）")
  }
  if (identical(method, "poisson") && !.stats_is_count(yv)) {
    stop("泊松回归需要非负整数计数型因变量")
  }

  # 分类自变量转因子（保持可复现：代码里也用 factor()）
  d2 <- d
  factor_vars <- character(0)
  for (v in xs) {
    col <- d2[[v]]
    if (!.stats_is_numeric(col)) {
      d2[[v]] <- factor(as.character(col))
      factor_vars <- c(factor_vars, v)
    }
  }
  if (identical(method, "logistic") && !.stats_is_numeric(yv)) {
    d2[[y]] <- factor(as.character(d2[[y]]))
  }

  # 去掉缺失
  keep <- stats::complete.cases(d2[, c(y, xs), drop = FALSE])
  d2 <- d2[keep, , drop = FALSE]
  if (nrow(d2) < 3) stop("有效样本不足（< 3 行）")

  fml <- stats::as.formula(paste(y, "~", paste(xs, collapse = " + ")))
  fit <- tryCatch({
    if (identical(method, "lm")) {
      stats::lm(fml, data = d2)
    } else if (identical(method, "logistic")) {
      stats::glm(fml, data = d2, family = stats::binomial())
    } else {
      stats::glm(fml, data = d2, family = stats::poisson())
    }
  }, error = function(e) e)
  if (inherits(fit, "error")) stop(sprintf("模型拟合失败: %s", conditionMessage(fit)))

  coefs <- .stats_coef_table(fit)
  if (is.null(coefs)) stop("模型没有可用的系数（可能全为缺失）")
  fit_stats <- .stats_fit_stats(fit)
  notes <- .stats_diagnostics(fit, d2, y, xs)

  code <- .stats_reg_code(method, y, xs, factor_vars)

  list(
    ok = TRUE,
    method = method,
    methodLabel = m$label,
    formula = deparse(fml),
    coefs = coefs,
    fitStats = fit_stats,
    notes = as.list(notes),
    n = nrow(d2),
    vars = as.list(c(y, xs)),
    factorVars = as.list(factor_vars),
    code = paste(code, collapse = "\n")
  )
}

## ---- 可复现代码 -------------------------------------------------------------
.stats_reg_code <- function(method, y, xs, factor_vars) {
  lines <- character(0)
  if (length(factor_vars)) {
    lines <- c(lines, sprintf("# 分类自变量转为因子：%s", paste(factor_vars, collapse = ", ")))
    for (v in factor_vars) {
      lines <- c(lines, sprintf("df$%s <- factor(df$%s)", v, v))
    }
  }
  rhs <- paste(xs, collapse = " + ")
  if (identical(method, "lm")) {
    lines <- c(lines, "# 线性回归",
               sprintf("fit <- lm(%s ~ %s, data = df)", y, rhs),
               "summary(fit)",
               "confint(fit)")
  } else if (identical(method, "logistic")) {
    lines <- c(lines, "# 逻辑回归",
               sprintf("fit <- glm(%s ~ %s, data = df, family = binomial())", y, rhs),
               "summary(fit)",
               "exp(cbind(OR = coef(fit), confint(fit)))")
  } else {
    lines <- c(lines, "# 泊松回归",
               sprintf("fit <- glm(%s ~ %s, data = df, family = poisson())", y, rhs),
               "summary(fit)",
               "exp(cbind(RR = coef(fit), confint(fit)))")
  }
  lines
}

## ---- 可用变量与推荐 ---------------------------------------------------------
.ggspec_reg_columns <- function(d) {
  if (is.null(d)) return(list(numeric = list(), categorical = list(), binary = list(), count = list()))
  d <- as.data.frame(d)
  nm <- setdiff(names(d), ".gg_rid")
  list(
    numeric = as.list(nm[vapply(nm, function(v) .stats_is_numeric(d[[v]]), logical(1))]),
    categorical = as.list(nm[vapply(nm, function(v) {
      !.stats_is_numeric(d[[v]]) && .stats_is_groupable(d[[v]])
    }, logical(1))]),
    binary = as.list(nm[vapply(nm, function(v) .stats_is_binary(d[[v]]), logical(1))]),
    count = as.list(nm[vapply(nm, function(v) .stats_is_count(d[[v]]), logical(1))])
  )
}
