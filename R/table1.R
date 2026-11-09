# Glyph - L5 基线特征表（Table 1）
# 设计：
#   1) 基于 gtsummary::tbl_summary 生成期刊级基线表；缺失时退化为纯 base R 实现
#   2) 输出三层：结构化数据（前端渲染表格）+ 可复现代码 + 文件导出（docx/xlsx/csv）
#   3) 统计量可选：均值(SD) / 中位数(IQR) / 计数(%)，连续变量可自动判断偏态
#   4) 组间比较：可选加 p 值（连续用 t/秩和，分类用卡方/Fisher），自动选法
#   5) 零硬依赖：gtsummary 与 officer/writexl 均为可选，缺失时降级

## ---- 统计量模板 -------------------------------------------------------------
.ggspec_t1_stats <- function() {
  list(
    list(id = "mean_sd",  label = "均值 (SD)",        cont = "{mean} ({sd})"),
    list(id = "median_iqr", label = "中位数 (IQR)",   cont = "{median} ({p25}, {p75})"),
    list(id = "mean_se",  label = "均值 (SE)",        cont = "{mean} ({se})")
  )
}

.ggspec_t1_stat_by_id <- function(id) {
  for (s in .ggspec_t1_stats()) if (identical(s$id, id)) return(s)
  .ggspec_t1_stats()[[1]]
}

## ---- 清洗 gtsummary 表头 ----------------------------------------------------
# gtsummary 的表头含 markdown（**bold**）与换行符，转成干净文本
.ggspec_clean_cell <- function(x) {
  x <- as.character(x)
  x <- gsub("\\*\\*", "", x)          # 去掉粗体标记
  x <- gsub("\\n", " ", x)            # 换行转换行空格
  x <- gsub("\\s+", " ", x)           # 合并连续空白
  trimws(x)
}

## ---- 主入口 -----------------------------------------------------------------
# 返回 list(ok, table(data.frame), columns, notes, code, n, groups)
#   vars   : 需要汇总的列（字符向量；空表示全部）
#   by     : 分组列（空表示单列描述）
#   statId : mean_sd | median_iqr | mean_se
#   addP   : 是否加组间 p 值
#   includeOverall : 是否加「合计」列
.ggspec_table1 <- function(d, vars = character(0), by = "", statId = "mean_sd",
                           addP = TRUE, includeOverall = FALSE, digits = 2L) {
  if (is.null(d) || !nrow(d)) stop("没有可用数据")
  d <- as.data.frame(d)
  d <- d[, setdiff(names(d), ".gg_rid"), drop = FALSE]

  by <- as.character(by %||% "")
  statId <- as.character(statId %||% "mean_sd")
  st <- .ggspec_t1_stat_by_id(statId)
  # 默认 2 位小数（期刊习惯：均值/中位数保留 1-2 位，这里统一 2 位可自行调整）
  digits <- suppressWarnings(as.integer(digits %||% 2L))
  if (is.na(digits) || digits < 0 || digits > 4) digits <- 2L

  all_vars <- setdiff(names(d), by)
  vars <- intersect(as.character(vars %||% character(0)), all_vars)
  if (!length(vars)) vars <- all_vars
  if (!length(vars)) stop("没有可汇总的变量")

  if (nzchar(by) && !by %in% names(d)) stop(sprintf("分组变量不存在: %s", by))

  # 只保留参与分析的列，并去掉全缺失的列
  sub <- d[, c(vars, if (nzchar(by)) by else NULL), drop = FALSE]
  keep <- vapply(sub, function(x) any(!is.na(x)), logical(1))
  # 分组列即使有缺失也保留（下方会给出缺失数提示）
  if (nzchar(by)) keep[[by]] <- TRUE
  sub <- sub[, keep, drop = FALSE]
  vars <- intersect(vars, names(sub))
  if (!length(vars)) stop("所选变量全部为空")

  # 逻辑变量与两水平字符变量按分类处理
  for (v in vars) {
    x <- sub[[v]]
    if (is.logical(x) || (is.character(x) && length(unique(x[!is.na(x)])) <= 10)) {
      sub[[v]] <- factor(as.character(x))
    } else if (is.numeric(x) && length(unique(x[!is.na(x)])) <= 5 &&
               all(abs(x - round(x)) < 1e-9, na.rm = TRUE)) {
      # 取值很少的整数（如 0/1 分组）按分类处理
      sub[[v]] <- factor(as.character(x))
    }
  }

  use_gts <- .ggspec_has_pkg("gtsummary")

  if (use_gts) {
    res <- tryCatch(
      .ggspec_table1_gtsummary(sub, vars, by, st, addP, includeOverall, digits),
      error = function(e) e)
    if (!inherits(res, "error")) return(res)
    # gtsummary 失败则退化到 base R
    warning_note <- sprintf("gtsummary 生成失败，已退化为 base R 实现: %s", conditionMessage(res))
  } else {
    warning_note <- "未安装 gtsummary，使用 base R 实现"
  }
  .ggspec_table1_base(sub, vars, by, st, addP, includeOverall, digits, warning_note)
}

## ---- gtsummary 实现 ---------------------------------------------------------
.ggspec_table1_gtsummary <- function(sub, vars, by, st, addP, includeOverall, digits) {
  # 版本差异：include 用 all_of() 包一层可兼容各版本 tidyselect；
  # missing 的合法取值为 "ifany" / "no" / "always"（不是 if_any）
  args <- list(data = sub, include = vars)
  if (nzchar(by)) args$by <- by
  args$statistic <- list(
    gtsummary::all_continuous() ~ st$cont,
    gtsummary::all_categorical() ~ "{n} ({p}%)"
  )
  args$digits <- list(
    gtsummary::all_continuous() ~ digits,
    gtsummary::all_categorical() ~ 0
  )
  args$missing <- "ifany"

  tb <- tryCatch(do.call(gtsummary::tbl_summary, args), error = function(e) e)
  if (inherits(tb, "error")) stop(conditionMessage(tb))

  # add_p / add_overall 是 gtsummary 的后置管道函数，不是 tbl_summary 的参数
  if (isTRUE(addP) && nzchar(by)) {
    tb <- tryCatch(suppressWarnings(gtsummary::add_p(tb)), error = function(e) tb)
  }
  if (isTRUE(includeOverall) && nzchar(by)) {
    tb <- tryCatch(suppressWarnings(gtsummary::add_overall(tb)), error = function(e) tb)
  }

  df <- tryCatch(as.data.frame(tb), error = function(e) e)
  if (inherits(df, "error")) stop(sprintf("结果转表格失败: %s", conditionMessage(df)))

  # 清洗表头
  cn <- vapply(names(df), .ggspec_clean_cell, character(1))
  names(df) <- make.unique(cn)
  # 清洗内容（去掉 markdown 标记）
  for (i in seq_along(df)) {
    if (is.character(df[[i]]) || is.factor(df[[i]])) {
      df[[i]] <- vapply(as.character(df[[i]]), .ggspec_clean_cell, character(1))
    }
  }
  # 首列改名
  names(df)[1] <- "特征"
  rownames(df) <- NULL

  notes <- character(0)
  if (nzchar(by)) {
    byv <- sub[[by]]
    notes <- c(notes, sprintf("按「%s」分组（%d 个水平，%d 行缺失）",
                              by, length(unique(byv[!is.na(byv)])), sum(is.na(byv))))
  }
  notes <- c(notes,
             sprintf("连续变量：%s；分类变量：n (%%)", st$label),
             "缺失值按变量单独统计（显示为 Unknown）")
  if (isTRUE(addP) && nzchar(by)) {
    notes <- c(notes, "p 值由 gtsummary 自动选择检验方法（连续用 t/秩和，分类用卡方/Fisher）")
  }

  list(
    ok = TRUE,
    engine = "gtsummary",
    table = df,
    columns = as.list(names(df)),
    vars = as.list(vars),
    by = by,
    statId = st$id,
    n = nrow(sub),
    groups = as.list(if (nzchar(by)) unique(as.character(sub[[by]][!is.na(sub[[by]])])) else character(0)),
    notes = as.list(notes),
    code = paste(.ggspec_table1_code(vars, by, st, addP, includeOverall, digits), collapse = "\n")
  )
}

## ---- base R 后备实现 --------------------------------------------------------
.ggspec_table1_base <- function(sub, vars, by, st, addP, includeOverall, digits, note) {
  grouped <- nzchar(by)
  grp_levels <- if (grouped) unique(as.character(sub[[by]][!is.na(sub[[by]])])) else character(0)

  fmt_num <- function(x, nd) {
    if (!is.finite(x)) return("—")
    format(round(x, nd), nsmall = nd, trim = TRUE)
  }

  # 单组统计
  stat_one <- function(x) {
    if (is.factor(x)) {
      tab <- table(x)
      tot <- sum(tab)
      if (!tot) return("—")
      parts <- vapply(names(tab), function(lv) {
        sprintf("%d (%.0f%%)", tab[[lv]], 100 * tab[[lv]] / tot)
      }, character(1))
      return(paste(sprintf("%s %s", names(tab), parts), collapse = "; "))
    }
    v <- x[is.finite(x)]
    if (!length(v)) return("—")
    if (identical(st$id, "median_iqr")) {
      q <- stats::quantile(v, c(.5, .25, .75), names = FALSE)
      sprintf("%s (%s, %s)", fmt_num(q[1], digits), fmt_num(q[2], digits), fmt_num(q[3], digits))
    } else if (identical(st$id, "mean_se")) {
      se <- if (length(v) > 1) stats::sd(v) / sqrt(length(v)) else NA_real_
      sprintf("%s (%s)", fmt_num(mean(v), digits), fmt_num(se, digits))
    } else {
      sd_v <- if (length(v) > 1) stats::sd(v) else NA_real_
      sprintf("%s (%s)", fmt_num(mean(v), digits), fmt_num(sd_v, digits))
    }
  }

  # 组间 p 值
  p_for <- function(x) {
    if (!grouped) return(NA_character_)
    ok <- !is.na(x) & !is.na(sub[[by]])
    x2 <- x[ok]; g2 <- as.character(sub[[by]][ok])
    if (length(unique(g2)) < 2) return("—")
    p <- tryCatch({
      if (is.factor(x2)) {
        tab <- table(x2, g2)
        # 期望频数过小用 Fisher
        ex <- suppressWarnings(stats::chisq.test(tab)$expected)
        if (any(ex < 5)) stats::fisher.test(tab)$p.value else
          suppressWarnings(stats::chisq.test(tab)$p.value)
      } else {
        if (length(unique(g2)) == 2) {
          stats::t.test(x2 ~ factor(g2))$p.value
        } else {
          summary(stats::aov(x2 ~ factor(g2)))[[1]][["Pr(>F)"]][1]
        }
      }
    }, error = function(e) NA_real_)
    if (!is.finite(p)) "—" else if (p < 0.001) "<0.001" else format(round(p, 3), nsmall = 3, trim = TRUE)
  }

  rows <- list()
  for (v in vars) {
    x <- sub[[v]]
    row <- list(特征 = v)
    if (grouped) {
      for (g in grp_levels) {
        xi <- x[!is.na(sub[[by]]) & as.character(sub[[by]]) == g]
        row[[g]] <- stat_one(xi)
      }
      if (isTRUE(includeOverall)) row[["合计"]] <- stat_one(x)
      if (isTRUE(addP)) row[["p 值"]] <- p_for(x)
    } else {
      row[["合计"]] <- stat_one(x)
    }
    rows[[length(rows) + 1]] <- as.data.frame(row, stringsAsFactors = FALSE, check.names = FALSE)
  }
  df <- do.call(rbind, rows)
  rownames(df) <- NULL

  notes <- c(note,
             sprintf("连续变量：%s；分类变量：n (%%)", st$label),
             "缺失值不参与统计")
  if (isTRUE(addP) && grouped) {
    notes <- c(notes, "p 值：两组连续用 t 检验、多组用方差分析；分类用卡方（期望频数 <5 时用 Fisher）")
  }

  list(
    ok = TRUE,
    engine = "base",
    table = df,
    columns = as.list(names(df)),
    vars = as.list(vars),
    by = by,
    statId = st$id,
    n = nrow(sub),
    groups = as.list(grp_levels),
    notes = as.list(notes),
    code = paste(.ggspec_table1_code(vars, by, st, addP, includeOverall, digits), collapse = "\n")
  )
}

## ---- 可复现代码 -------------------------------------------------------------
.ggspec_table1_code <- function(vars, by, st, addP, includeOverall, digits) {
  v <- paste(r_string(vars), collapse = ", ")
  lines <- character(0)
  if (.ggspec_has_pkg("gtsummary")) {
    lines <- c(lines, "# 基线特征表（Table 1）")
    by_arg <- if (nzchar(by)) sprintf(", by = %s", r_string(by)) else ""
    lines <- c(lines, sprintf("tbl <- gtsummary::tbl_summary(df, include = c(%s)%s,", v, by_arg))
    lines <- c(lines, sprintf("  statistic = list(gtsummary::all_continuous() ~ %s,", r_string(st$cont)))
    lines <- c(lines, "                   gtsummary::all_categorical() ~ \"{n} ({p}%)\"),")
    lines <- c(lines, sprintf("  digits = list(gtsummary::all_continuous() ~ %dL))", digits))
    if (isTRUE(addP) && nzchar(by)) lines <- c(lines, "tbl <- gtsummary::add_p(tbl)")
    if (isTRUE(includeOverall) && nzchar(by)) lines <- c(lines, "tbl <- gtsummary::add_overall(tbl)")
    lines <- c(lines, "tbl")
    lines <- c(lines, "# 导出 Word / Excel")
    if (.ggspec_has_pkg("flextable") && .ggspec_has_pkg("officer")) {
      lines <- c(lines,
        "ft <- gtsummary::as_flex_table(tbl)",
        "flextable::save_as_docx(ft, path = \"table1.docx\")")
    }
    if (.ggspec_has_pkg("writexl")) {
      lines <- c(lines, "writexl::write_xlsx(as.data.frame(tbl), \"table1.xlsx\")")
    }
  } else {
    # base R 版本
    lines <- c(lines,
      "# 基线特征表（base R 实现，需先安装 gtsummary 获得期刊排版）",
      sprintf("vars <- c(%s)", v))
    if (nzchar(by)) {
      lines <- c(lines,
        sprintf("by <- %s", r_string(by)),
        "agg <- stats::aggregate(df[, vars], by = df[, by, drop = FALSE], FUN = function(x) {",
        "  x <- x[!is.na(x)]",
        "  c(n = length(x), mean = mean(x), sd = stats::sd(x))",
        "})",
        "agg")
    } else {
      lines <- c(lines, sprintf("sapply(df[, vars], function(x) c(n = sum(!is.na(x)), mean = mean(x, na.rm = TRUE)))"))
    }
  }
  lines
}

## ---- 文件导出 ---------------------------------------------------------------
# format: docx | xlsx | csv
# 返回 list(ok, path, filename)
.ggspec_table1_export <- function(res, format = "docx", out_dir) {
  format <- tolower(as.character(format %||% "docx"))
  if (!res$ok || is.null(res$table)) stop("表格未生成")
  df <- res$table
  stamp <- format(Sys.time(), "%Y%m%d-%H%M%S")
  fn <- sprintf("table1-%s.%s", stamp, format)
  path <- file.path(out_dir, fn)

  if (identical(format, "csv")) {
    utils::write.csv(df, path, row.names = FALSE, fileEncoding = "UTF-8")
    return(list(ok = TRUE, filename = fn))
  }

  if (identical(format, "xlsx")) {
    if (!.ggspec_has_pkg("writexl")) stop("导出 Excel 需要 writexl 包")
    writexl::write_xlsx(df, path)
    return(list(ok = TRUE, filename = fn))
  }

  if (identical(format, "docx")) {
    if (!.ggspec_has_pkg("flextable") || !.ggspec_has_pkg("officer")) {
      stop("导出 Word 需要 flextable 与 officer 包")
    }
    ft <- tryCatch(
      flextable::flextable(df) |>
        flextable::autofit() |>
        flextable::set_caption("Table 1. 基线特征表"),
      error = function(e) e)
    if (inherits(ft, "error")) stop(sprintf("生成 Word 表失败: %s", conditionMessage(ft)))
    flextable::save_as_docx(ft, path = path)
    if (!file.exists(path)) stop("Word 文件写入失败")
    return(list(ok = TRUE, filename = fn))
  }

  stop(sprintf("不支持的导出格式: %s", format))
}

## ---- 可用变量 ---------------------------------------------------------------
.ggspec_table1_columns <- function(d) {
  if (is.null(d)) return(list(all = list(), groupable = list()))
  d <- as.data.frame(d)
  nm <- setdiff(names(d), ".gg_rid")
  list(
    all = as.list(nm),
    groupable = as.list(nm[vapply(nm, function(v) .stats_is_groupable(d[[v]]), logical(1))])
  )
}
