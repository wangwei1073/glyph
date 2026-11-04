# ggplotGUI - L3 图上显著性标注
# 目标：把 L2 的检验结果画到图上，并保持「所见即代码」。
#
# 设计：
#   1) spec 新增 sigMarks: [{ id, kind, x, y, group1, group2, label, yPos, ... }]
#      —— 生成器据此输出可复现代码；渲染与代码走同一条管线
#   2) 两种标注形态：
#      - bracket : 离散 x 轴上的括号（ggsignif::geom_signif），3 组以上自动阶梯避让
#      - text    : 通用 p 值文字（ggpubr::stat_pvalue_manual），数值/离散轴都适用
#   3) 自动定位：根据数据范围推算 y 起点与步进，避免标注压到数据
#   4) 依赖可选：ggsignif / ggpubr 缺失时退化为 annotate("text")，不阻断出图

## ---- 依赖探测 ---------------------------------------------------------------
.ggspec_has_pkg <- function(p) requireNamespace(p, quietly = TRUE)

## ---- 标注形态选择 -----------------------------------------------------------
# 离散 x + 两组 → 括号；其他 → 文字
.ggspec_sig_kind <- function(spec) {
  x <- .ggspec_sig_x_column(spec)
  if (is.null(x)) return("text")
  .ggspec_is_discrete_x(spec, x) && .ggspec_has_pkg("ggsignif")
}

# 取第一个图层 x 映射的列名
.ggspec_sig_x_column <- function(spec) {
  layers <- spec$layers %||% list()
  for (l in layers) {
    v <- (l$aes %||% list())$x
    if (!is.null(v) && !is.null(v$map) && nzchar(v$map)) return(as.character(v$map))
  }
  # 提升到 ggplot() 的 aes
  for (l in layers) {
    v <- (l$aes %||% list())$x
    if (!is.null(v) && !is.null(v$map)) return(as.character(v$map))
  }
  NULL
}

.ggspec_sig_y_column <- function(spec) {
  layers <- spec$layers %||% list()
  for (l in layers) {
    v <- (l$aes %||% list())$y
    if (!is.null(v) && !is.null(v$map) && nzchar(v$map)) return(as.character(v$map))
  }
  NULL
}

# 判断 x 是否离散：优先看数据列类型，其次看图层是否强制 group
.ggspec_is_discrete_x <- function(spec, x) {
  if (is.null(x)) return(FALSE)
  state <- attr(spec, "state")
  if (!is.null(state)) {
    d <- tryCatch(ggspec_resolve_data(spec, state), error = function(e) NULL)
    if (!is.null(d) && x %in% names(d)) {
      v <- d[[x]]
      return(is.factor(v) || is.character(v) || is.logical(v))
    }
  }
  FALSE
}

## ---- y 位置计算 -------------------------------------------------------------
# 依据 y 列取值范围推算标注起点与步进
.ggspec_sig_positions <- function(d, y_col, n_marks) {
  if (is.null(d) || is.null(y_col) || !y_col %in% names(d) || !n_marks) {
    return(list(start = 0, step = 1))
  }
  v <- d[[y_col]]
  v <- v[is.finite(v)]
  if (!length(v)) return(list(start = 0, step = 1))
  rng <- range(v)
  span <- diff(rng)
  if (!is.finite(span) || span <= 0) span <- max(abs(rng), 1) * 0.2
  step <- span * 0.12                      # 每级括号的间距
  start <- rng[2] + span * 0.06            # 从数据最大值上方 6% 处起
  list(start = start, step = step, span = span)
}

## ---- 代码生成 ---------------------------------------------------------------
# 输出若干 ggplot 附加语句（字符串向量）
.ggspec_sig_lines <- function(spec, marks, d = NULL) {
  marks <- marks %||% list()
  if (!length(marks)) return(character(0))
  y_col <- .ggspec_sig_y_column(spec)
  pos <- .ggspec_sig_positions(d, y_col, length(marks))

  marks_lines <- .ggspec_sig_mark_lines(spec, marks, d, pos)

  # 关键：标注 y 若超出面板范围，几何体会被画到绘图区外，进而挤压标题区。
  # 因此把所有标注都纳入 y 轴范围，并在最高标注之上再留 4% 余量。
  expand <- .ggspec_sig_y_limit(d, y_col, marks, pos)
  if (is.null(expand)) return(marks_lines)
  c(expand, marks_lines)
}

# 生成 y 轴范围语句，使标注完整落在绘图区内
# 注意：必须与 .ggspec_sig_mark_lines 使用同一套 y 推算规则（无 yPos 时按 start/step 递增），
# 否则上限会算小、把高位标注裁掉（曾出现第 3 条括号被裁的问题）。
.ggspec_sig_y_limit <- function(d, y_col, marks, pos) {
  if (is.null(d) || is.null(y_col) || !y_col %in% names(d)) return(NULL)
  v <- d[[y_col]]
  v <- v[is.finite(v)]
  if (!length(v)) return(NULL)

  # 与图层生成一致的 y 序列：显式 yPos 优先，缺失则按序号递增
  ys <- vapply(seq_along(marks), function(i) {
    y <- marks[[i]]$yPos
    if (is.null(y) || is.na(suppressWarnings(as.numeric(y)))) {
      pos$start + pos$step * (i - 1)
    } else {
      as.numeric(y)
    }
  }, numeric(1))
  if (!length(ys)) ys <- pos$start

  top <- max(c(max(v), max(ys)))
  lo <- min(v)
  span <- top - lo
  if (!is.finite(span) || span <= 0) span <- abs(top) * 0.2 + 0.5
  pad <- span * 0.06
  sprintf("scale_y_continuous(limits = c(%s, %s), expand = expansion(mult = c(0.02, 0.02)))",
          format(lo - span * 0.02, trim = TRUE),
          format(top + pad, trim = TRUE))
}

# 只生成标注图层本身（不含 y 轴范围）
.ggspec_sig_mark_lines <- function(spec, marks, d, pos) {
  lines <- character(0)
  # 分组：bracket 类走 ggsignif，text 类走 ggpubr / annotate
  brackets <- Filter(function(m) identical(m$kind %||% "", "bracket"), marks)
  texts <- Filter(function(m) !identical(m$kind %||% "", "bracket"), marks)

  if (length(brackets)) {
    if (.ggspec_has_pkg("ggsignif")) {
      cmp <- vapply(brackets, function(m) {
        paste0("c(", r_string(as.character(m$group1 %||% "")), ", ",
               r_string(as.character(m$group2 %||% "")), ")")
      }, character(1))
      ann <- vapply(brackets, function(m) r_string(as.character(m$label %||% "*")), character(1))
      ys <- vapply(seq_along(brackets), function(i) {
        y <- brackets[[i]]$yPos
        if (is.null(y) || is.na(suppressWarnings(as.numeric(y)))) y <- pos$start + pos$step * (i - 1)
        format(as.numeric(y), trim = TRUE)
      }, character(1))
      lines <- c(lines, sprintf(
        "ggsignif::geom_signif(comparisons = list(%s), annotations = c(%s), y_position = c(%s), tip_length = 0.015, vjust = 0.4, textsize = 3.4)",
        paste(cmp, collapse = ", "), paste(ann, collapse = ", "), paste(ys, collapse = ", ")))
    } else {
      # 无 ggsignif：退化为文字标注
      for (i in seq_along(brackets)) {
        m <- brackets[[i]]
        y <- m$yPos %||% (pos$start + pos$step * (i - 1))
        xm <- as.character(m$group2 %||% m$group1 %||% "")
        lines <- c(lines, sprintf(
          "annotate(\"text\", x = %s, y = %s, label = %s, vjust = 0, size = 3.4)",
          r_string(xm), format(as.numeric(y), trim = TRUE),
          r_string(as.character(m$label %||% "*"))))
      }
    }
  }

  if (length(texts)) {
    # 统一用 ggpubr::stat_pvalue_manual（支持任意轴的 p 文字标注）
    if (.ggspec_has_pkg("ggpubr")) {
      g1 <- vapply(texts, function(m) r_string(as.character(m$group1 %||% "")), character(1))
      g2 <- vapply(texts, function(m) r_string(as.character(m$group2 %||% "")), character(1))
      yv <- vapply(seq_along(texts), function(i) {
        y <- texts[[i]]$yPos
        if (is.null(y) || is.na(suppressWarnings(as.numeric(y)))) y <- pos$start + pos$step * (i - 1)
        format(as.numeric(y), trim = TRUE)
      }, character(1))
      lab <- vapply(texts, function(m) r_string(as.character(m$label %||% "")), character(1))
      # label 直接内联（不走 p 的格式化），保证显示与用户设定一致
      lines <- c(lines, sprintf(
        "ggpubr::stat_pvalue_manual(data.frame(group1 = c(%s), group2 = c(%s), label = c(%s), y.position = c(%s)), label = \"label\", size = 3.4, vjust = 0)",
        paste(g1, collapse = ", "), paste(g2, collapse = ", "),
        paste(lab, collapse = ", "), paste(yv, collapse = ", ")))
    } else {
      for (i in seq_along(texts)) {
        m <- texts[[i]]
        y <- m$yPos %||% (pos$start + pos$step * (i - 1))
        xm <- as.character(m$group2 %||% m$group1 %||% "")
        lines <- c(lines, sprintf(
          "annotate(\"text\", x = %s, y = %s, label = %s, vjust = 0, size = 3.4)",
          r_string(xm), format(as.numeric(y), trim = TRUE),
          r_string(as.character(m$label %||% ""))))
      }
    }
  }

  lines
}

## ---- 用于「一键添加标注」的数据侧计算 ---------------------------------------
# 依据当前 spec 与数据，给出可选的比较对与默认 y 位置
.ggspec_sig_plan <- function(d, spec) {
  x_col <- .ggspec_sig_x_column(spec)
  y_col <- .ggspec_sig_y_column(spec)
  if (is.null(x_col) || is.null(y_col) || is.null(d)) {
    return(list(ok = FALSE, reason = "需要图层同时映射 x 与 y", pairs = list()))
  }
  if (!x_col %in% names(d) || !y_col %in% names(d)) {
    return(list(ok = FALSE, reason = "映射的列在数据中不存在", pairs = list()))
  }
  xv <- d[[x_col]]
  discrete <- is.factor(xv) || is.character(xv) || is.logical(xv)
  levels_x <- if (discrete) unique(as.character(xv[!is.na(xv)])) else NULL
  pos <- .ggspec_sig_positions(d, y_col, 1)

  pairs <- list()
  if (discrete && length(levels_x) >= 2 && length(levels_x) <= 12) {
    lv <- levels_x
    for (i in seq_len(length(lv) - 1)) {
      for (j in seq.int(i + 1, length(lv))) {
        pairs[[length(pairs) + 1]] <- list(group1 = lv[i], group2 = lv[j])
      }
    }
  }
  list(ok = TRUE, discrete = discrete, xCol = x_col, yCol = y_col,
       levels = as.list(levels_x %||% character(0)),
       pairs = pairs, yStart = pos$start, yStep = pos$step)
}
