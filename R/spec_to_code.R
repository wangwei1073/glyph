# Glyph - spec -> R 代码生成器
# spec 是前端产出的声明式绘图规格（JSON）；本文件把它编译为可读、可复制的
# 规范 R 代码。渲染管线唯一：/api/render 即 eval 本文件生成的代码。

# ---- 局部工具 ---------------------------------------------------------------
.enc <- function(x) r_literal(x)

# 合并调用参数：支持位置参数（name 为 ""）
.args_line <- function(args) {
  if (!length(args)) return("")
  nms <- names(args) %||% rep("", length(args))
  nms[is.na(nms)] <- ""
  vals <- unlist(args, use.names = FALSE)
  parts <- ifelse(nms == "", vals, paste0(nms, " = ", vals))
  paste0(parts, collapse = ", ")
}

# aes() 参数行：映射与表达式
.aes_line <- function(aes) {
  if (!length(aes)) return(NULL)
  parts <- character(0)
  for (nm in names(aes)) {
    v <- r_aes_value(aes[[nm]])
    if (is.null(v) || !nzchar(trimws(v))) next
    parts <- c(parts, paste0(nm, " = ", v))
  }
  if (!length(parts)) return(NULL)
  paste0("aes(", paste(parts, collapse = ", "), ")")
}

# ---- 扩展函数限定名 ---------------------------------------------------------
# ggplot2 自身的函数保持裸名（如 geom_point），扩展包函数写成 pkg::fn。
# 这样生成的代码在任何只 library(ggplot2) 的环境里都能跑，
# 也避免与用户环境里的同名函数冲突。
.qualified_fn <- function(fn, pkg) {
  fn <- as.character(fn %||% "")
  if (!nzchar(fn)) return(fn)
  pkg <- as.character(pkg %||% "ggplot2")
  # 已带前缀（如 "ggpubr::stat_compare_means"）则原样返回
  if (grepl("::", fn, fixed = TRUE)) return(fn)
  if (identical(pkg, "ggplot2") || !nzchar(pkg)) return(fn)
  paste0(pkg, "::", fn)
}

# ---- 多重标度（ggnewscale）--------------------------------------------------
# ggnewscale 的 new_scale_fill() 不是图层，而是「插在图层之间的标记」：
#   ggplot() + geom_a(...) + new_scale_fill() + geom_b(...)
# 本项目用图层的 resetScale 字段表达：该层之前插入对应的 new_scale_*()。
# resetScale 取值：字符串或字符串数组，如 "fill" / c("fill","colour")。

.reset_scale_fns <- list(
  fill = "new_scale_fill", colour = "new_scale_colour", color = "new_scale_color",
  size = "new_scale", alpha = "new_scale", shape = "new_scale",
  linetype = "new_scale", linewidth = "new_scale"
)

# 返回 new_scale_*() 调用（可能多行），无可插入内容时返回 NULL
.reset_scale_line <- function(rs) {
  if (is.null(rs)) return(NULL)
  keys <- as.character(unlist(rs))
  keys <- keys[nzchar(keys)]
  if (!length(keys)) return(NULL)
  if (!.ggspec_has_pkg("ggnewscale")) {
    return("NULL  # 多重标度需要 ggnewscale 包，当前未安装")
  }
  lines <- character(0)
  for (k in keys) {
    fn <- .reset_scale_fns[[k]]
    if (is.null(fn)) fn <- "new_scale"
    lines <- c(lines, sprintf("ggnewscale::%s()", fn))
  }
  if (length(lines)) lines else NULL
}

# 图层调用
.layer_call <- function(layer, meta) {
  geom_name <- layer$geom %||% "point"
  gmeta <- meta$geom_by_name[[geom_name]]
  fn <- gmeta$fn %||% paste0("geom_", geom_name)
  # 扩展包的图层函数不在 ggplot2 命名空间里，必须写成 pkg::fn，
  # 否则渲染时报「没有 geom_xxx 这个函数」（ggbeeswarm / ggtext / ggside 等）
  fn <- .qualified_fn(fn, gmeta$package %||% "ggplot2")

  args <- list()
  aes_line <- .aes_line(layer$aes)
  if (!is.null(aes_line)) args[["mapping"]] <- aes_line

  # stat
  stat <- layer$stat %||% ""
  if (nzchar(stat) && !identical(stat, gmeta$defaultStat %||% "identity")) {
    args[["stat"]] <- r_string(stat)
  }

  # position
  pos <- layer$position %||% NULL
  if (!is.null(pos) && !is.null(pos$type) && nzchar(pos$type)) {
    pargs <- list()
    for (pnm in names(pos$params %||% list())) {
      if (has_val(pos$params[[pnm]])) pargs[[pnm]] <- .enc(pos$params[[pnm]])
    }
    if (identical(pos$type, "identity") && !length(pargs)) {
      # identity 无参数 → 不输出
    } else {
      pfn <- meta$position_fn[[pos$type]] %||% paste0("position_", pos$type)
      pfn <- .qualified_fn(pfn, meta$fn_package[[pfn]] %||% "ggplot2")   # 先用裸名查包名
      args[["position"]] <- paste0(pfn, "(", .args_line(pargs), ")")
    }
  }

  # geom/stat 参数
  for (pnm in names(layer$params %||% list())) {
    if (has_val(layer$params[[pnm]])) args[[pnm]] <- .enc(layer$params[[pnm]])
  }
  # 常量美学
  for (pnm in names(layer$aesParams %||% list())) {
    if (has_val(layer$aesParams[[pnm]])) args[[pnm]] <- .enc(layer$aesParams[[pnm]])
  }

  if (identical(layer$showLegend, FALSE)) args[["show.legend"]] <- "FALSE"
  if (identical(layer$inheritAes, FALSE)) args[["inherit.aes"]] <- "FALSE"

  paste0(fn, "(", .args_line(args), ")")
}

# 标度调用
.scale_call <- function(sc, meta) {
  aes <- sc$aes; type <- sc$type
  key <- paste0(aes, "|", type)
  fn <- meta$scale_fn[[key]]
  if (is.null(fn)) return(list(code = NULL, warn = sprintf("未找到标度函数 scale_%s_%s", aes, type)))
  fn <- .qualified_fn(fn, meta$fn_package[[fn]] %||% "ggplot2")   # 先用裸名查包名再加前缀
  args <- list()
  for (pnm in names(sc$params %||% list())) {
    if (has_val(sc$params[[pnm]])) args[[pnm]] <- .enc(sc$params[[pnm]])
  }
  if (has_val(sc$position)) args[["position"]] <- .enc(sc$position)
  # 次轴
  sa <- sc$secAxis
  if (!is.null(sa) && has_val(sa$transform %||% NULL)) {
    sa_args <- list(enc2utf8(as.character(sa$transform)))
    if (has_val(sa$name)) sa_args[["name"]] <- .enc(sa$name)
    if (has_val(sa$breaks)) sa_args[["breaks"]] <- .enc(sa$breaks)
    if (has_val(sa$labels)) sa_args[["labels"]] <- .enc(sa$labels)
    args[["sec.axis"]] <- paste0("sec_axis(", .args_line(sa_args), ")")
  }
  list(code = paste0(fn, "(", .args_line(args), ")"), warn = NULL)
}

# coord
.coord_call <- function(coord, meta) {
  if (is.null(coord) || is.null(coord$type) || !nzchar(coord$type)) return(NULL)
  type <- coord$type
  flip <- isTRUE(coord$flip)
  fn <- meta$coord_fn[[type]] %||% paste0("coord_", type)
  fn <- .qualified_fn(fn, meta$fn_package[[fn]] %||% "ggplot2")
  args <- list()
  for (pnm in names(coord$params %||% list())) {
    if (has_val(coord$params[[pnm]])) args[[pnm]] <- .enc(coord$params[[pnm]])
  }
  if (flip) {
    # coord_flip 只支持 xlim/ylim/expand/clip
    keep <- intersect(names(args), c("xlim", "ylim", "expand", "clip"))
    args <- args[keep]
    fn <- "coord_flip"
  }
  paste0(fn, "(", .args_line(args), ")")
}

# 分面
.facet_call <- function(facet, meta) {
  if (is.null(facet) || is.null(facet$type) || !nzchar(facet$type) || facet$type == "none") return(NULL)
  vars_of <- function(vs) {
    vs <- vs[vapply(vs, function(v) has_val(v), logical(1))]
    if (!length(vs)) return(NULL)
    paste0("vars(", paste(vapply(vs, as.character, ""), collapse = ", "), ")")
  }
  args <- list()
  if (identical(facet$type, "wrap")) {
    fv <- vars_of(facet$vars %||% list())
    if (is.null(fv)) return(NULL)
    args[["facets"]] <- fv
  } else if (identical(facet$type, "grid")) {
    rows <- vars_of(facet$rows %||% list()); cols <- vars_of(facet$cols %||% list())
    if (is.null(rows) && is.null(cols)) return(NULL)
    if (!is.null(rows)) args[["rows"]] <- rows
    if (!is.null(cols)) args[["cols"]] <- cols
  } else return(NULL)
  for (pnm in names(facet$params %||% list())) {
    if (has_val(facet$params[[pnm]])) args[[pnm]] <- .enc(facet$params[[pnm]])
  }
  paste0("facet_", facet$type, "(", .args_line(args), ")")
}

# labs
.labs_call <- function(labs) {
  if (!length(labs)) return(NULL)
  args <- list()
  for (nm in names(labs)) {
    v <- labs[[nm]]
    if (is.character(v) && nzchar(trimws(v)) || is_expr_spec(v)) args[[nm]] <- .enc(v)
  }
  if (!length(args)) return(NULL)
  paste0("labs(", .args_line(args), ")")
}

# guides
.guides_call <- function(guides, meta) {
  if (!length(guides)) return(NULL)
  args <- list()
  for (nm in names(guides)) {
    g <- guides[[nm]]
    if (is.character(g)) {
      if (nzchar(g)) args[[nm]] <- r_string(g)
    } else if (is.list(g) && has_val(g$type %||% NULL)) {
      gfn <- meta$guide_fn[[g$type]] %||% paste0("guide_", g$type)
      gargs <- list()
      for (pnm in names(g$params %||% list())) {
        if (has_val(g$params[[pnm]])) gargs[[pnm]] <- .enc(g$params[[pnm]])
      }
      args[[nm]] <- paste0(gfn, "(", .args_line(gargs), ")")
    }
  }
  if (!length(args)) return(NULL)
  paste0("guides(", .args_line(args), ")")
}

# 注释
.annotation_call <- function(a, meta) {
  kind <- a$kind %||% "annotate"
  if (identical(kind, "annotate")) {
    gname <- a$geom %||% "text"
    args <- list(r_string(gname))
    names(args) <- ""
    for (pnm in names(a$params %||% list())) {
      if (has_val(a$params[[pnm]])) args[[pnm]] <- .enc(a$params[[pnm]])
    }
    names(args)[1] <- ""  # 位置参数
    line <- paste0("annotate(", paste(paste0(names(args), ifelse(names(args) == "", "", " = "), args), collapse = ", "), ")")
    line
  } else if (identical(kind, "fn")) {
    fn <- meta$annotation_fn[[a$name %||% ""]] %||% paste0("annotation_", a$name %||% "")
  fn <- .qualified_fn(fn, meta$fn_package[[fn]] %||% "ggplot2")
    args <- list()
    for (pnm in names(a$params %||% list())) {
      if (has_val(a$params[[pnm]])) args[[pnm]] <- .enc(a$params[[pnm]])
    }
    paste0(fn, "(", .args_line(args), ")")
  }
}

# ---- 中文字体兜底 -----------------------------------------------------------
# ragg 下默认 sans 对部分汉字缺字（「著」「注」等会直接消失），
# 因此图形里一旦出现中文文本、且用户没指定 base_family，就自动补中文字体。
.ggspec_cjk_pattern <- "[\u4e00-\u9fff]"

.ggspec_has_cjk <- function(x) {
  if (is.null(x)) return(FALSE)
  if (is.list(x)) return(any(vapply(x, .ggspec_has_cjk, logical(1))))
  if (!is.character(x)) return(FALSE)
  any(grepl(.ggspec_cjk_pattern, x))
}

# 按平台挑选一个确定存在的中文字体；返回 NULL 表示无需/不可用
.ggspec_cjk_family <- function() {
  cands <- if (.Platform$OS.type == "windows") {
    c("Microsoft YaHei", "SimHei", "SimSun")
  } else if (identical(Sys.info()[["sysname"]], "Darwin")) {
    c("PingFang SC", "Heiti SC", "STHeiti")
  } else {
    c("Noto Sans CJK SC", "WenQuanYi Micro Hei", "Source Han Sans SC")
  }
  have <- tryCatch(systemfonts::system_fonts()$family, error = function(e) character(0))
  for (f in cands) if (f %in% have) return(f)
  NULL
}

# 需要补字体时返回一条 theme(...) 语句
.ggspec_cjk_font_line <- function(spec, meta) {
  # 用户已显式指定基础字体 → 尊重用户选择
  if (has_val((spec$theme %||% list())$args[["base_family"]])) return(NULL)
  # 只关心会落到图上的文本：labs / 注释 / 标注
  texts <- list(
    (spec$labs %||% list()),
    (spec$annotations %||% list()),
    (spec$sigMarks %||% list())
  )
  if (!.ggspec_has_cjk(texts)) return(NULL)
  fam <- .ggspec_cjk_family()
  if (is.null(fam)) return(NULL)
  sprintf("theme(text = element_text(family = %s))", r_string(fam))
}

# 主题
.theme_calls <- function(theme, meta) {
  out <- list()
  base <- theme$base %||% ""
  if (nzchar(base)) {
    tmeta <- meta$theme_by_name[[base]]
    fn <- tmeta$fn %||% paste0("theme_", base)
    fn <- .qualified_fn(fn, (tmeta$package %||% "ggplot2"))
    args <- list()
    for (pnm in names(theme$args %||% list())) {
      if (has_val(theme$args[[pnm]])) args[[pnm]] <- .enc(theme$args[[pnm]])
    }
    out <- c(out, paste0(fn, "(", .args_line(args), ")"))
  }
  els <- theme$elements %||% list()
  if (length(els)) {
    parts <- character(0)
    for (nm in names(els)) {
      el <- els[[nm]]
      if (is.list(el) && isTRUE(el$blank)) {
        parts <- c(parts, paste0(nm, " = element_blank()"))
        next
      }
      if (!is.list(el)) {
        # value 型：原始 JSON 值
        if (has_val(el)) parts <- c(parts, paste0(nm, " = ", .enc(el)))
        next
      }
      if (!is.null(el$value)) {
        # unit 型 {value, unit}
        parts <- c(parts, paste0(nm, " = ", .unit_code(el)))
        next
      }
      if (!is.null(el$margins)) {
        parts <- c(parts, paste0(nm, " = ", .margin_code(el$margins)))
        next
      }
      props <- el$props %||% list()
      type <- el$type %||% "text"
      if (type %in% c("title", "text")) type <- "text"
      fnel <- switch(type, line = "element_line", rect = "element_rect",
                     point = "element_point", polygon = "element_polygon",
                     geom = "element_geom", "element_text")
      eargs <- list()
      for (pnm in names(props)) {
        if (!has_val(props[[pnm]])) next
        # element_text/element_rect 的 margin 属性是 {t,r,b,l} 结构，需生成 margin() 调用
        if (pnm == "margin" && is.list(props[[pnm]]) && !is_expr_spec(props[[pnm]])) {
          mc <- .margin_code(props[[pnm]])
          if (nzchar(mc) && mc != "margin()") eargs[[pnm]] <- mc
          next
        }
        eargs[[pnm]] <- .enc(props[[pnm]])
      }
      if (is.null(el$props) && !length(eargs)) next
      if (!length(eargs)) next
      parts <- c(parts, paste0(nm, " = ", fnel, "(", .args_line(eargs), ")"))
    }
    if (length(parts)) out <- c(out, paste0("theme(", paste(parts, collapse = ", "), ")"))
  }
  out
}

.unit_code <- function(u) {
  val <- u$value %||% 0
  unit <- u$unit %||% "pt"
  vpart <- if (is_expr_spec(val)) enc2utf8(as.character(val$expr)) else format(as.numeric(val), trim = TRUE)
  paste0("unit(", vpart, ", ", r_string(unit), ")")
}

.margin_code <- function(m) {
  parts <- character(0)
  for (k in c("t", "r", "b", "l")) {
    v <- m[[k]]
    if (is.null(v) || is.na(suppressWarnings(as.numeric(v)))) next
    parts <- c(parts, paste0(k, " = ", format(as.numeric(v), trim = TRUE)))
  }
  if (!length(parts)) return("margin()")
  paste0("margin(", paste(parts, collapse = ", "), ")")
}

# 手动编辑 -> 可复现 R 语句（追加在数据处理段之后）
.edits_code_lines <- function(ops, df_name) {
  lines <- character(0)
  if (!length(ops)) return(lines)
  lit <- function(v) {
    if (is.null(v) || length(v) == 0 || identical(v, "") || identical(v, "NA")) return("NA")
    if (length(v) == 1 && is.na(v)) return("NA")
    if (is.logical(v)) return(if (isTRUE(v)) "TRUE" else "FALSE")
    if (is.numeric(v)) return(format(v, digits = 15, trim = TRUE, scientific = FALSE))
    r_string(as.character(v))
  }
  for (op in ops) {
    kind <- op$kind %||% ""
    if (kind == "cell" && has_val(op$col) && !is.null(op$rid)) {
      lines <- c(lines, paste0(df_name, "$", op$col, "[", df_name, "$.gg_rid == ",
                               format(as.numeric(op$rid), trim = TRUE), "] <- ",
                               lit(op$value), "  # 手动编辑"))
    } else if (kind == "rowDel" && !is.null(op$rid)) {
      lines <- c(lines, paste0(df_name, " <- ", df_name, "[", df_name, "$.gg_rid != ",
                               format(as.numeric(op$rid), trim = TRUE), ", ]"))
    } else if (kind == "rowIns") {
      vals <- op$values %||% list()
      parts <- character(0)
      for (col in names(vals)) {
        if (identical(col, ".gg_rid")) next
        parts <- c(parts, paste0(col, " = ", lit(vals[[col]])))
      }
      if (!length(parts)) next  # 不能 return()：那会把前面累积的编辑语句一起丢掉
      parts <- c(parts, paste0(".gg_rid = max(c(0, ", df_name, "$.gg_rid), na.rm = TRUE) + 1L"))
      lines <- c(lines, paste0(df_name, " <- rbind(", df_name, ", data.frame(",
                               paste(parts, collapse = ", "),
                               ", stringsAsFactors = FALSE))"))
    } else if (kind == "colRen" && has_val(op$from) && has_val(op$to)) {
      lines <- c(lines, paste0("names(", df_name, ")[names(", df_name, ") == ",
                               r_string(op$from), "] <- ", r_string(op$to)))
    } else if (kind == "colDel" && has_val(op$col)) {
      lines <- c(lines, paste0(df_name, "$", op$col, " <- NULL"))
    }
  }
  lines
}

# 数据赋值行
.data_lines <- function(spec, state, df_name = "df", data_file = NULL) {
  src <- (spec$data %||% list())$source %||% list(type = "none")
  prep <- (spec$data %||% list())
  lines <- character(0)
  if (identical(src$type, "dataset")) {
    lines <- c(lines, paste0(df_name, " <- ", src$name))
  } else if (identical(src$type, "user") && !is.null(data_file) && nzchar(data_file)) {
    # 可复现包：数据随包导出为 CSV，代码直接读同目录文件
    lines <- c(lines, sprintf('%s <- read.csv("%s", stringsAsFactors = FALSE, check.names = FALSE, encoding = "UTF-8")',
                              df_name, data_file))
  } else if (identical(src$type, "user")) {
    d <- tryCatch(state$data_store$get(src_id_of(src)), error = function(e) NULL)
    inline_ok <- !is.null(d) && nrow(d) <= 30 && ncol(d) <= 6 &&
      all(vapply(d, function(x) is.numeric(x) || is.character(x) || is.factor(x) || is.logical(x) || inherits(x, "Date"), logical(1)))
    if (inline_ok) {
      # 内部锚列 .gg_rid 不内联给用户，改由下方统一的锚行语句补上
      keep_cols <- setdiff(names(d), ".gg_rid")
      cols <- vapply(keep_cols, function(nm) {
        x <- d[[nm]]
        vals <- lapply(x, function(v) {
          if (inherits(v, "Date")) paste0('as.Date("', format(v, "%Y-%m-%d"), '")')
          else if (is.na(v)) "NA"
          else r_literal(v)
        })
        paste0(nm, " = c(", paste(unlist(vals), collapse = ", "), ")")
      }, character(1))
      lines <- c(lines, paste0(df_name, " <- data.frame(\n  ", paste(cols, collapse = ",\n  "), "\n)"))
    } else {
      lines <- c(lines, 'df <- read.csv("your_data.csv")  # TODO: 替换为实际数据文件路径')
    }
  } else {
    lines <- c(lines, "df <- data.frame()  # 未选择数据")
  }
  # 手动编辑的行锚：必须在筛选/抽样之前赋值，才能与渲染路径（加载时编号）保持一致
  edits <- character(0)
  es <- state$edit_store %||% NULL
  key <- .keyof(src)
  if (!is.null(es)) edits <- es$get(key)
  if (length(edits)) {
    lines <- c(lines, paste0(df_name, "$.gg_rid <- seq_len(nrow(", df_name, "))  # 编辑行锚"))
  }
  # 数据加工提示注释
  for (tx in prep$text %||% list()) {
    if (isTRUE(tx$disabled) || !has_val(tx$name)) next
    nm <- tx$name
    op <- as.character(tx$op %||% "trim")
    line <- switch(op,
      trim = sprintf("%s$%s <- trimws(%s$%s)  # 去空格", df_name, nm, df_name, nm),
      upper = sprintf("%s$%s <- toupper(%s$%s)  # 转大写", df_name, nm, df_name, nm),
      lower = sprintf("%s$%s <- tolower(%s$%s)  # 转小写", df_name, nm, df_name, nm),
      split = sprintf("%s <- tidyr::separate(%s, %s, into = c(%s, %s), sep = %s, extra = 'drop')  # 拆分列",
                      df_name, df_name, deparse(nm), deparse(as.character(tx$into1 %||% paste0(nm, "_1"))),
                      deparse(as.character(tx$into2 %||% paste0(nm, "_2"))), deparse(as.character(tx$sep %||% ","))),      replace = sprintf("%s$%s <- gsub(%s, %s, %s$%s, fixed = TRUE)  # 文本替换",
                        df_name, nm, deparse(as.character(tx$from %||% "")),
                        deparse(as.character(tx$to %||% "")), df_name, nm),
      NULL)
    if (!is.null(line)) lines <- c(lines, line)
  }
  for (o in prep$outliers %||% list()) {
    if (isTRUE(o$disabled) || !has_val(o$name)) next
    nm <- o$name; k <- as.numeric(o$k %||% if (identical(o$method, "z")) 3 else 1.5)
    method <- as.character(o$method %||% "iqr"); action <- as.character(o$action %||% "flag")
    bound <- if (identical(method, "z"))
      sprintf("mean(%1$s, na.rm = TRUE) + c(-1, 1) * %2$s * sd(%1$s, na.rm = TRUE)", df_name, k)
    else sprintf("quantile(%s, c(.25, .75), na.rm = TRUE) + c(-1, 1) * %s * IQR(%s, na.rm = TRUE)", df_name, k, df_name)
    lines <- c(lines, sprintf("q <- %s", bound))
    lines <- c(lines, switch(action,
      flag = sprintf("%s$%s_outlier <- !is.na(%s$%s) & (%s$%s < q[1] | %s$%s > q[2])  # 异常值标记",
                     df_name, nm, df_name, nm, df_name, nm, df_name, nm),
      drop = sprintf("%s <- %s[!(%s$%s < q[1] | %s$%s > q[2]), , drop = FALSE]  # 异常值删除",
                     df_name, df_name, df_name, nm, df_name, nm),
      winsor = sprintf("%s$%s <- pmin(pmax(%s$%s, q[1]), q[2])  # 异常值缩尾",
                       df_name, nm, df_name, nm)))
  }
  for (tt in prep$types %||% list()) {
    if (isTRUE(tt$disabled) || !has_val(tt$name)) next
    fn <- c(num = "as.numeric", chr = "as.character", fct = "as.factor",
            lgl = "as.logical", date = "as.Date")[[as.character(tt$type %||% "")]]
    if (is.null(fn)) next
    lines <- c(lines, sprintf("%s$%s <- %s(%s$%s)  # 类型转换", df_name, tt$name, fn, df_name, tt$name))
  }
  m <- prep$mutate %||% list()
  if (length(m)) {
    for (mm in m) {
      if (isTRUE(mm$disabled)) next
      if (has_val(mm$name) && has_val(mm$expr)) {
        lines <- c(lines, sprintf("%s$%s <- with(%s, %s)  # 新增列 %s", df_name, mm$name, df_name, enc2utf8(as.character(mm$expr)), mm$name))
      }
    }
  }
  for (f in prep$fillna %||% list()) {
    if (isTRUE(f$disabled) || !has_val(f$name)) next
    nm <- f$name; m <- as.character(f$method %||% "constant")
    line <- switch(m,
      constant = sprintf("%s$%s[is.na(%s$%s)] <- %s  # 缺失填充", df_name, nm, df_name, nm,
                         deparse(as.character(f$value %||% ""))),
      mean = sprintf("%s$%s[is.na(%s$%s)] <- mean(%s$%s, na.rm = TRUE)  # 均值填充", df_name, nm, df_name, nm, df_name, nm),
      median = sprintf("%s$%s[is.na(%s$%s)] <- median(%s$%s, na.rm = TRUE)  # 中位数填充", df_name, nm, df_name, nm, df_name, nm),
      mode = sprintf("%s$%s[is.na(%s$%s)] <- names(sort(table(%s$%s), decreasing = TRUE))[1]  # 众数填充", df_name, nm, df_name, nm, df_name, nm),
      NULL)
    if (!is.null(line)) lines <- c(lines, line)
  }
  if (!isTRUE(prep$dropnaDisabled)) {
    cols <- as.character(unlist(prep$dropnaCols %||% list()))
    if (length(cols)) {
      lines <- c(lines, sprintf(
        "%s <- %s[!apply(is.na(%s[, c(%s), drop = FALSE]), 1, %s), , drop = FALSE]  # 缺失值",
        df_name, df_name, df_name, paste(sprintf('"%s"', cols), collapse = ", "),
        if (identical(prep$dropnaHow, "all")) "all" else "any"))
    }
  }
  flt <- trimws(as.character(prep$filter %||% ""))
  if (!isTRUE(prep$filterDisabled) && nzchar(flt)) {
    # subset() 在数据框/ tibble 上都按列名求值，并自动丢弃条件为 NA 的行
    # （不能用 df[<表达式>, ]：base R 的 `[` 不做数据掩码求值）
    lines <- c(lines, sprintf("%s <- subset(%s, %s)  # 行筛选（NA 行自动剔除）", df_name, df_name, flt))
  }
  if (isTRUE(prep$dedupEnabled)) {
    cols <- as.character(unlist(prep$dedupCols %||% list()))
    if (!length(cols)) cols <- NULL
    lines <- c(lines, if (is.null(cols))
      sprintf("%s <- %s[!duplicated(%s), , drop = FALSE]  # 去重", df_name, df_name, df_name)
      else sprintf("%s <- %s[!duplicated(%s[, c(%s), drop = FALSE]), , drop = FALSE]  # 去重",
                   df_name, df_name, df_name, paste(sprintf('"%s"', cols), collapse = ", ")))
  }
  if (!isTRUE(prep$sampleDisabled) && !is.null(prep$sample) && is.numeric(prep$sample) && prep$sample > 0) {
    sd <- prep$seed
    if (!is.null(sd) && is.numeric(sd)) lines <- c(lines, sprintf("set.seed(%d)", as.integer(sd)))
    lines <- c(lines, sprintf("%s <- %s[sample(nrow(%s), min(%d, nrow(%s))), , drop = FALSE]  # 抽样", df_name, df_name, df_name, as.integer(prep$sample), df_name))
  }
  if (length(edits)) lines <- c(lines, .edits_code_lines(edits, df_name))
  lines
}

# 包依赖检测
.package_lines <- function(spec, meta) {
  used <- c("ggplot2")
  add_fn_pkg <- function(fn, table) {
    if (!is.null(fn) && !is.null(table[[fn]]) && !table[[fn]] %in% used) used <<- c(used, table[[fn]])
  }
  for (l in spec$layers %||% list()) {
    gn <- l$geom %||% "point"
    add_fn_pkg(meta$geom_by_name[[gn]]$fn, meta$fn_package)
    st <- l$stat %||% ""
    if (nzchar(st)) add_fn_pkg(paste0("stat_", st), meta$fn_package)
    pt <- (l$position %||% list())$type
    if (!is.null(pt) && nzchar(pt)) add_fn_pkg(meta$position_fn[[pt]], meta$fn_package)
  }
  for (sc in spec$scales %||% list()) {
    key <- paste0(sc$aes, "|", sc$type)
    add_fn_pkg(meta$scale_fn[[key]], meta$fn_package)
  }
  cd <- spec$coord
  if (!is.null(cd) && has_val(cd$type)) add_fn_pkg(meta$coord_fn[[cd$type]], meta$fn_package)
  base <- (spec$theme %||% list())$base
  if (has_val(base)) add_fn_pkg(meta$theme_by_name[[base]]$fn, meta$fn_package)
  for (g in spec$guides %||% list()) {
    if (is.list(g) && has_val(g$type)) add_fn_pkg(meta$guide_fn[[g$type]], meta$fn_package)
  }
  for (a in spec$annotations %||% list()) {
    if (identical(a$kind, "annotate")) {
      gn <- a$geom %||% "text"
      add_fn_pkg(meta$geom_by_name[[gn]]$fn, meta$fn_package)
    } else if (identical(a$kind, "fn")) {
      add_fn_pkg(meta$annotation_fn[[a$name %||% ""]], meta$fn_package)
    }
  }
  # 显著性标注依赖：括号走 ggsignif，文字走 ggpubr（生成器已按可用性退化）
  sig_marks <- spec$sigMarks %||% list()
  if (length(sig_marks)) {
    need_bracket <- any(vapply(sig_marks, function(m) identical(m$kind %||% "", "bracket"), logical(1)))
    need_text <- any(vapply(sig_marks, function(m) !identical(m$kind %||% "", "bracket"), logical(1)))
    if (need_bracket && .ggspec_has_pkg("ggsignif")) used <- c(used, "ggsignif")
    if (need_text && .ggspec_has_pkg("ggpubr")) used <- c(used, "ggpubr")
  }
  # 多重标度依赖 ggnewscale
  has_reset <- any(vapply(spec$layers %||% list(),
                          function(l) length(l$resetScale %||% character(0)) > 0, logical(1)))
  if (has_reset && .ggspec_has_pkg("ggnewscale")) used <- c(used, "ggnewscale")
  vapply(setdiff(unique(used), "ggplot2"), function(p) paste0("library(", p, ")"), character(1)) |> unname()
}

# ggplot 级 aes 提升判定：单层，或多层 aes 完全一致且全部继承
# 只在「可见图层」之间判断：隐藏层不参与出图，也不应影响 aes 提升
.ggplot_aes <- function(layers) {
  layers <- Filter(function(l) !identical(l$visible, FALSE), layers)
  real <- Filter(function(l) !identical(l$inheritAes, FALSE), layers)
  if (!length(real)) return(NULL)
  first <- real[[1]]
  if (!length(first$aes %||% list())) return(NULL)
  if (length(layers) == 1) return(first$aes)
  for (l in layers) {
    if (identical(l$inheritAes, FALSE)) next
    la <- l$aes %||% list()
    if (!identical(lapply(la, function(x) x), lapply(first$aes, function(x) x))) return(NULL)
    if (setequal(names(la), names(first$aes))) next else return(NULL)
  }
  first$aes
}

# ---- 主入口 -----------------------------------------------------------------
# 返回 list(code, eval_code, warnings, packages)
# var_name/df_name：拼图模式下用 p1/df1 等独立命名
# include_data：是否包含数据赋值/加工行（拼图展示代码包含，eval 由环境注入）
# with_final：是否以变量名自身作为最后表达式（print 用）
spec_to_code <- function(spec, meta, state, var_name = "p", df_name = "df",
                         include_data = TRUE, with_final = TRUE, data_file = NULL) {
  warns <- character(0)
  spec <- spec %||% list()
  layers <- spec$layers %||% list()

  data_lines <- if (include_data) .data_lines(spec, state, df_name, data_file) else character(0)

  g_aes <- .ggplot_aes(layers)
  plot_args <- df_name
  if (!is.null(g_aes)) {
    al <- .aes_line(g_aes)
    if (!is.null(al)) plot_args <- c(plot_args, al)
  }
  plot_line <- paste0(var_name, " <- ggplot(", paste(plot_args, collapse = ", "), ")")

  layer_lines <- character(0)
  for (i in seq_along(layers)) {
    l <- layers[[i]]
    # 图层显隐：visible = FALSE 的层不参与出图（但仍保留在 spec 里，方便随时恢复）。
    # 注意不能简单跳过，否则「ggplot() 提升的 aes」会引用到不存在的图层数据。
    if (identical(l$visible, FALSE)) next
    # 多重标度（ggnewscale）：该层之前插入 new_scale_*()，让后续图层重新开始一套标度。
    # 这是 ggnewscale 的特殊机制——它不是图层，而是「插在图层之间的标记」。
    rs <- .reset_scale_line(l$resetScale)
    if (!is.null(rs)) {
      layer_lines <- c(layer_lines, rs)
      warns <- c(warns, sprintf("图层 %d 使用了多重标度（%s），需要 ggnewscale 包",
                                i, paste(l$resetScale, collapse = "+")))
    }
    ll <- l
    # 已提升到 ggplot() 的 aes 从图层中去掉
    if (!is.null(g_aes)) {
      own <- l$aes %||% list()
      if (identical(lapply(own, function(x) x), lapply(g_aes, function(x) x))) ll$aes <- list()
    }
    lc <- .layer_call(ll, meta)
    if (nzchar(lc)) layer_lines <- c(layer_lines, lc)
  }
  # 全部隐藏（或原本没有图层）时输出占位层，保证 ggplot 链合法
  if (!length(layer_lines)) layer_lines <- c("geom_blank()")

  tail_lines <- character(0)
  for (sc in spec$scales %||% list()) {
    cc <- .scale_call(sc, meta)
    if (!is.null(cc$warn)) warns <- c(warns, cc$warn)
    else if (!is.null(cc$code)) tail_lines <- c(tail_lines, cc$code)
  }
  cc <- .coord_call(spec$coord, meta); if (!is.null(cc)) tail_lines <- c(tail_lines, cc)
  fc <- .facet_call(spec$facet, meta); if (!is.null(fc)) tail_lines <- c(tail_lines, fc)
  lc2 <- .labs_call(spec$labs);       if (!is.null(lc2)) tail_lines <- c(tail_lines, lc2)
  gc2 <- .guides_call(spec$guides, meta); if (!is.null(gc2)) tail_lines <- c(tail_lines, gc2)
  for (a in spec$annotations %||% list()) {
    ac <- tryCatch(.annotation_call(a, meta), error = function(e) {
      warns <<- c(warns, sprintf("注释生成失败: %s", conditionMessage(e))); NULL
    })
    if (!is.null(ac)) tail_lines <- c(tail_lines, ac)
  }
  tail_lines <- c(tail_lines, .theme_calls(spec$theme, meta))

  # 中文字体兜底：默认 sans 在 ragg 下会缺字（如「著」「注」直接不显示），
  # 因此当图形里存在中文文本、且用户没指定 base_family 时，自动补一个中文字体。
  cn_font <- .ggspec_cjk_font_line(spec, meta)
  if (!is.null(cn_font)) tail_lines <- c(tail_lines, cn_font)

  # 显著性标注（L3）：依赖 ggsignif / ggpubr，缺失时退化为 annotate("text")
  sig_marks <- spec$sigMarks %||% list()
  if (length(sig_marks)) {
    sig_lines <- tryCatch({
      d <- NULL
      if (!is.null(state)) {
        d <- tryCatch(ggspec_resolve_data(spec, state), error = function(e) NULL)
      }
      .ggspec_sig_lines(spec, sig_marks, d)
    }, error = function(e) {
      warns <<- c(warns, sprintf("显著性标注生成失败: %s", conditionMessage(e)))
      character(0)
    })
    tail_lines <- c(tail_lines, sig_lines)
  }

  # 组装（+ 链）：ggplot 行与图层/附加项同处一条链，行尾统一接 +
  chain <- c(plot_line, layer_lines, tail_lines)
  add_chain <- function(pre) {
    lines <- c(.package_lines(spec, meta), pre)
    for (i in seq_along(chain)) {
      sep <- if (i == length(chain)) "" else " +"
      indent <- if (i == 1) "" else "  "
      lines <- c(lines, paste0(indent, chain[i], sep))
    }
    if (with_final) c(lines, var_name) else lines
  }
  # 展示用：含数据加工行；求值用：跳过（df 由环境注入，已含加工结果）
  lines_display <- add_chain(data_lines)
  lines_eval <- add_chain(character(0))

  code <- paste(lines_display, collapse = "\n")
  eval_code <- paste(lines_eval, collapse = "\n")
  Encoding(code) <- "UTF-8"; Encoding(eval_code) <- "UTF-8"
  list(code = code, eval_code = eval_code, warnings = warns,
       packages = .package_lines(spec, meta))
}

# ---- 拼图（patchwork）代码生成 -----------------------------------------------
# combine spec: {active, slots:[{pin, op}], layout:{...}, annotation:{...}}
# 逐槽位调用 spec_to_code 生成独立图元代码（p1/df1 命名），再以 patchwork 组合。
# 返回 list(code, eval_code, warnings, env_list)
ggspec_compose_code <- function(combine, meta, state) {
  slots <- combine$slots %||% list()
  if (!length(slots)) stop("拼图未选择图库槽位")
  # 拼图依赖 patchwork；若用户在「扩展管理」里关掉了它，明确提示而不是产出跑不了的代码
  if (!ext_is_enabled("patchwork")) {
    stop("patchwork 扩展已在「高级 → 扩展管理」中关闭，无法生成拼图")
  }
  if (!requireNamespace("patchwork", quietly = TRUE)) stop("patchwork 未安装，无法拼图")
  warns <- character(0)
  pkgs <- c("ggplot2", "patchwork")
  chunks_display <- character(0)
  chunks_eval <- character(0)
  env_list <- list()
  plot_names <- character(0)
  used_ops <- character(0)   # 与 plot_names 一一对应（op 属于「它前面那个槽位」的语义：见前端 PinPanel）

  for (i in seq_along(slots)) {
    sl <- slots[[i]]
    pid <- sl$pin %||% ""
    # 代码图槽位：用 local({ ... }) 求值出 ggplot 对象，再参与 patchwork
    it <- tryCatch(state$pin_store$list_full()[[pid]], error = function(e) NULL)
    if (!is.null(it) && identical(as.character(it$type %||% "spec"), "code")) {
      mode <- as.character((it$data %||% list())$mode %||% "none")
      code_txt <- as.character((it$code %||% list())$text %||% "")
      if (identical(mode, "snapshot")) {
        warns <- c(warns, sprintf("槽位 %d (%s) 是带数据快照的代码图，暂不支持拼图，已跳过", i, pid))
        next
      }
      if (!nzchar(trimws(code_txt))) {
        warns <- c(warns, sprintf("槽位 %d (%s) 代码为空，已跳过", i, pid))
        next
      }
      pn <- sprintf("p%d", length(plot_names) + 1L)
      label <- state$pin_store$label(pid) %||% pid
      wrapped <- sprintf("%s <- local({\n%s\n})", pn, code_txt)
      chunks_display <- c(chunks_display, sprintf("# ---- %s (%s) ----", label, pn), wrapped, "")
      chunks_eval <- c(chunks_eval, sprintf("# ---- %s (%s) ----", label, pn), wrapped, "")
      plot_names <- c(plot_names, pn)
      used_ops <- c(used_ops, as.character(sl$op %||% "+"))
      next
    }
    spec_json <- state$pin_store$get(pid)
    if (is.null(spec_json)) {
      warns <- c(warns, sprintf("槽位 %d 引用的图库项目 %s 不存在，已跳过", i, pid))
      next
    }
    pin_spec <- tryCatch(jsonlite::fromJSON(spec_json, simplifyVector = FALSE),
                         error = function(e) NULL)
    if (is.null(pin_spec) || !length(pin_spec$layers %||% list())) {
      warns <- c(warns, sprintf("槽位 %d (%s) 没有可用图层，已跳过", i, pid))
      next
    }
    pn <- sprintf("p%d", length(plot_names) + 1L)
    dn <- sprintf("df%d", length(plot_names) + 1L)
    data_df <- ggspec_resolve_data(pin_spec, state)
    env_list[[dn]] <- data_df

    gen <- spec_to_code(pin_spec, meta, state, var_name = pn, df_name = dn,
                        include_data = FALSE, with_final = FALSE)
    warns <- c(warns, gen$warnings)
    # gen$packages 是 "library(pkg)" 文本；这里要的是包名，否则会生成 library(library(pkg))
    gen_pkgs <- sub("^library\\((.*)\\)$", "\\1", gen$packages %||% character(0))
    pkgs <- union(pkgs, gen_pkgs)
    # 每个子图的代码顶部会重复 library()；统一提到最外层，子图块里去掉
    gen_lines <- strsplit(gen$code, "\n", fixed = TRUE)[[1]]
    gen_lines <- gen_lines[!grepl("^library\\(", gen_lines)]
    gen_code <- paste(gen_lines, collapse = "\n")
    label <- state$pin_store$label(pid) %||% pid
    chunks_display <- c(chunks_display,
                        sprintf("# ---- %s (%s) ----", label, pn),
                        .data_lines(pin_spec, state, dn),
                        "",
                        gen_code,
                        "")
    chunks_eval <- c(chunks_eval,
                     sprintf("# ---- %s (%s) ----", label, pn),
                     gen_code,
                     "")
    plot_names <- c(plot_names, pn)
    used_ops <- c(used_ops, as.character(sl$op %||% "+"))
  }
  if (!length(plot_names)) stop("拼图槽位为空：先在画布上点「存入图库」")

  # 组合表达式：相邻槽位之间的运算符（+ / | / -）
  # 前端把运算符存在「后一个槽位」上（PinPanel 用 slots[i+1].op 显示 i 与 i+1 之间的符号），
  # 因此这里取 used_ops[j] 而不是 used_ops[j-1]；used_ops 只收集成功解析的槽位，避免缺槽错位。
  expr <- plot_names[1]
  for (j in seq_along(plot_names)) {
    if (j == 1) next
    op <- if (length(used_ops) >= j) used_ops[j] else "+"
    if (!op %in% c("+", "|", "-")) op <- "+"
    expr <- paste(expr, op, plot_names[j])
  }
  expr <- paste0("(", expr, ")")

  # plot_layout 参数
  lo <- (combine$layout %||% list())
  largs <- list()
  if (has_val(lo$ncol)) largs[["ncol"]] <- .enc(lo$ncol)
  if (has_val(lo$nrow)) largs[["nrow"]] <- .enc(lo$nrow)
  if (has_val(lo$widths)) largs[["widths"]] <- .enc(lo$widths)
  if (has_val(lo$heights)) largs[["heights"]] <- .enc(lo$heights)
  if (has_val(lo$guides)) largs[["guides"]] <- .enc(lo$guides)
  if (isTRUE(lo$byrow)) largs[["byrow"]] <- "TRUE"
  if (has_val(lo$design)) largs[["design"]] <- .enc(lo$design)
  if (length(largs)) {
    expr <- paste0(expr, " + plot_layout(", .args_line(largs), ")")
  }

  # plot_annotation
  an <- (combine$annotation %||% list())
  aargs <- list()
  for (nm in c("title", "subtitle", "caption", "tag")) {
    if (has_val(an[[nm]])) aargs[[nm]] <- .enc(an[[nm]])
  }
  if (has_val(an$tag_levels)) aargs[["tag_levels"]] <- .enc(an$tag_levels)

  # 标注样式：plot_annotation(theme = theme(...))
  # 只作用于标注层（标题/副标题/注释/标签），不会改变各子图内部的字号。
  sty <- (an$style %||% list())
  .sty_el <- function(kind, args) {
    if (!length(args)) return(NULL)
    sprintf("element_text(%s)", paste(args, collapse = ", "))
  }
  tparts <- character(0)
  add_el <- function(elem, size, bold, color) {
    a <- character(0)
    if (has_val(size)) a <- c(a, sprintf("size = %s", as.numeric(size)))
    if (isTRUE(bold)) a <- c(a, "face = \"bold\"")
    if (has_val(color)) a <- c(a, sprintf("colour = \"%s\"", color))
    e <- .sty_el(elem, a)
    if (!is.null(e)) tparts <<- c(tparts, sprintf("%s = %s", elem, e))
  }
  add_el("plot.title",    sty$title_size,    sty$title_bold,    sty$title_color)
  add_el("plot.subtitle", sty$subtitle_size, NULL,              sty$subtitle_color)
  add_el("plot.caption",  sty$caption_size,  NULL,              sty$caption_color)
  add_el("plot.tag",      sty$tag_size,      sty$tag_bold,      sty$tag_color)
  if (has_val(sty$family)) {
    tparts <- c(tparts, sprintf("text = element_text(family = \"%s\")", sty$family))
  }
  if (length(tparts)) {
    aargs[["theme"]] <- sprintf("theme(%s)", paste(tparts, collapse = ", "))
  }

  if (length(aargs)) {
    # aargs 的值已经是可直接输出的 R 表达式（.enc 负责加引号，theme() 本身就是表达式），
    # 因此统一交给 .args_line 拼接即可。
    expr <- paste0(expr, " + plot_annotation(", .args_line(aargs), ")")
  }

  # 收集图例时 guides 参数一起给 plot_layout —— patchwork 支持 guides="collect"
  pkg_lines <- vapply(setdiff(unique(pkgs), "ggplot2"),
                      function(pk) paste0("library(", pk, ")"), character(1)) |> unname()

  code <- paste(c(pkg_lines, chunks_display, paste0("p <- ", expr), "p"), collapse = "\n")
  eval_code <- paste(c(pkg_lines, chunks_eval, paste0("p <- ", expr), "p"), collapse = "\n")
  Encoding(code) <- "UTF-8"; Encoding(eval_code) <- "UTF-8"
  list(code = code, eval_code = eval_code, warnings = warns, env_list = env_list)
}

# ---- meta 查找表构建（一次） -------------------------------------------------
meta_build_lookup <- function(meta) {
  meta$geom_by_name <- setNames(lapply(meta$geoms, function(g) g), vapply(meta$geoms, function(g) g$name, ""))
  meta$position_fn <- setNames(vapply(meta$positions, function(p) p$fn, ""), vapply(meta$positions, function(p) p$name, ""))
  meta$scale_fn <- list()
  for (s in meta$scales) meta$scale_fn[[paste0(s$aes, "|", s$type)]] <- s$fn
  meta$coord_fn <- setNames(vapply(meta$coords, function(c) c$fn, ""), vapply(meta$coords, function(c) c$name, ""))
  meta$guide_fn <- setNames(vapply(meta$guides, function(g) g$fn, ""), vapply(meta$guides, function(g) g$name, ""))
  meta$theme_by_name <- setNames(lapply(meta$themes, function(t) t), vapply(meta$themes, function(t) t$name, ""))
  meta$annotation_fn <- setNames(vapply(meta$annotations, function(a) a$fn, ""), vapply(meta$annotations, function(a) a$name, ""))
  # 函数 -> 包
  fp <- list()
  for (g in meta$geoms) fp[[g$fn]] <- g$package %||% "ggplot2"
  for (s in meta$scales) fp[[s$fn]] <- s$package %||% "ggplot2"
  for (t in meta$themes) fp[[t$fn]] <- t$package %||% "ggplot2"
  for (g in meta$guides) fp[[g$fn]] <- g$package %||% "ggplot2"
  for (st in meta$stats) fp[[st$fn]] <- "ggplot2"
  for (a in meta$annotations) fp[[a$fn]] <- a$package %||% "ggplot2"
  for (p in meta$positions) fp[[p$fn]] <- "ggplot2"
  for (cc in meta$coords) fp[[cc$fn]] <- "ggplot2"
  meta$fn_package <- fp
  meta
}
