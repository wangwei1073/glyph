# Glyph - 渲染与导出：eval 生成的代码 -> 设备输出
# 渲染管线唯一：spec -> 代码 -> eval。代码面板与图形永远一致。

.ggspec_eval_env <- function(data_df) {
  env <- new.env(parent = globalenv())
  if (is.list(data_df) && !is.null(names(data_df)) && !is.data.frame(data_df)) {
    for (nm in names(data_df)) assign(nm, data_df[[nm]] %||% data.frame(), envir = env)
  } else {
    assign("df", data_df %||% data.frame(), envir = env)
  }
  env
}

# 依次求值顶层表达式，捕获错误/警告/消息
.ggspec_eval <- function(code, env) {
  exprs <- tryCatch(parse(text = code, keep.source = FALSE),
                    error = function(e) stop("代码解析失败: ", conditionMessage(e)))
  warnings <- character(0)
  messages <- character(0)
  err <- NULL
  result <- NULL
  for (e in exprs) {
    res <- tryCatch(
      withCallingHandlers(
        eval(e, envir = env),
        warning = function(w) {
          warnings <<- c(warnings, conditionMessage(w))
          invokeRestart("muffleWarning")
        },
        message = function(m) {
          messages <<- c(messages, conditionMessage(m))
          invokeRestart("muffleMessage")
        }
      ),
      error = function(er) {
        err <<- conditionMessage(er)
        NULL
      }
    )
    if (!is.null(err)) break
    result <- res
  }
  list(result = result, warnings = warnings, messages = messages, error = err)
}

# 找到 ggplot 对象
.ggspec_pick_plot <- function(result, env) {
  if (!is.null(result) && inherits(result, c("ggplot", "gg", "patchwork"))) return(result)
  for (nm in c("p", "last_plot")) {
    if (exists(nm, envir = env, inherits = FALSE)) {
      obj <- get(nm, envir = env)
      if (inherits(obj, c("ggplot", "gg", "patchwork"))) return(obj)
    }
  }
  NULL
}

# 渲染到文件，返回路径
ggspec_render_file <- function(code, data_df, width = 800, height = 500, dpi = 150,
                               format = c("png", "svg", "pdf")) {
  format <- match.arg(format)
  env <- .ggspec_eval_env(data_df)
  # 求值阶段先挂一个临时图形设备。
  # 用户代码里常见 print(p) / plot(p)，此时若没有设备，R 会打开默认 pdf 设备：
  #   · 在 Windows + UTF-8 locale 下，中文会被判为无法转换，
  #     刷出大量 "conversion failure ... in 'mbcsToSbcs'" 警告；
  #   · 还会在进程工作目录留下一个 Rplots.pdf。
  # 用 ragg 临时设备兜住（UTF-8 友好，输出到临时文件后丢弃）。
  dummy <- tempfile(fileext = ".png")
  dummy_open <- FALSE
  tryCatch({
    if (requireNamespace("ragg", quietly = TRUE)) {
      ragg::agg_png(dummy, width = 200, height = 200, units = "px", res = 72, background = "white")
      dummy_open <- TRUE
    }
  }, error = function(e) NULL)
  on.exit({
    if (dummy_open) tryCatch(grDevices::dev.off(), error = function(e) NULL)
    unlink(dummy)
  }, add = TRUE)

  ev <- .ggspec_eval(code, env)
  # 求值结束、拿到图对象后立刻关掉临时设备，后面正式渲染会另开一个
  if (dummy_open) {
    tryCatch(grDevices::dev.off(), error = function(e) NULL)
    dummy_open <- FALSE
  }
  if (!is.null(ev$error)) {
    stop(structure(class = "ggplot_error", list(message = ev$error,
                                                warnings = ev$warnings)))
  }
  plot_obj <- .ggspec_pick_plot(ev$result, env)
  if (is.null(plot_obj)) stop("代码没有产生 ggplot 对象（最后表达式或变量 p）")
  # 中文兜底：手写代码通常不会自己指定中文字体
  plot_obj <- .ggspec_apply_cjk_family(plot_obj, code)

  ext <- switch(format, png = "png", svg = "svg", pdf = "pdf")
  path <- tempfile(fileext = paste0(".", ext))
  w_in <- width / dpi; h_in <- height / dpi

  dev_opened <- FALSE
  tryCatch({
    switch(format,
      png = {
        if (requireNamespace("ragg", quietly = TRUE)) {
          ragg::agg_png(path, width = width, height = height, units = "px",
                        res = dpi, background = "white")
        } else {
          grDevices::png(path, width = width, height = height, units = "px", res = dpi,
                         bg = "white")
        }
      },
      svg = grDevices::svg(path, width = w_in, height = h_in, bg = "white", onefile = TRUE),
      pdf = {
        ok_cairo <- tryCatch({
          grDevices::cairo_pdf(path, width = w_in, height = h_in, onefile = TRUE); TRUE
        }, error = function(e) FALSE)
        if (!ok_cairo) grDevices::pdf(path, width = w_in, height = h_in, onefile = TRUE)
      }
    )
    dev_opened <- TRUE
    print(plot_obj)
  },
  error = function(e) {
    if (dev_opened) tryCatch(grDevices::dev.off(), error = function(e2) NULL)
    stop(structure(class = "ggplot_error",
                   list(message = sprintf("绘图出错: %s", conditionMessage(e)),
                        warnings = ev$warnings)))
  },
  finally = {
    if (dev_opened && grDevices::dev.cur() > 1) {
      tryCatch(grDevices::dev.off(), error = function(e) NULL)
    }
  })

  list(path = path, warnings = ev$warnings, messages = ev$messages)
}

# 统一构建管线：单图 spec 或激活中的拼图（patchwork）→ 代码 + 求值数据
ggspec_pipeline <- function(spec, meta, state) {
  spec <- spec %||% list()
  cb <- spec$combine %||% list()
  if (isTRUE(cb$active) && length(cb$slots %||% list())) {
    gen <- ggspec_compose_code(cb, meta, state)
    list(code = gen$code, eval_code = gen$eval_code,
         env_list = gen$env_list, warnings = gen$warnings)
  } else {
    gen <- spec_to_code(spec, meta, state)
    data_df <- ggspec_resolve_data(spec, state)
    list(code = gen$code, eval_code = gen$eval_code,
         env_list = list(df = data_df), warnings = gen$warnings)
  }
}

# spec -> 渲染 PNG（预览）。png_dir 非空时落盘并以 URL 返回（避免大 base64 JSON），
# 否则返回 base64。
ggspec_render_preview <- function(spec, meta, state, width, height, dpi, png_dir = NULL) {
  t0 <- Sys.time()
  gen <- ggspec_pipeline(spec, meta, state)
  data_df <- gen$env_list
  rf <- ggspec_render_file(gen$eval_code, data_df, width = width, height = height, dpi = dpi,
                           format = "png")
  png_val <- NULL; png_url <- NULL
  if (!is.null(png_dir)) {
    png_url <- paste0("/api/plot/", file_move_to_cache(rf$path, png_dir))
  } else {
    png_val <- jsonlite::base64_enc(readBin(rf$path, "raw", file.info(rf$path)$size))
    unlink(rf$path)
  }
  list(
    ok = TRUE,
    code = gen$code,
    png = png_val,
    pngUrl = png_url,
    warnings = c(gen$warnings, rf$warnings),
    messages = rf$messages,
    nrow = .pipeline_nrow(data_df),
    ncol = .pipeline_ncol(data_df),
    elapsedMs = as.integer(as.numeric(Sys.time() - t0, units = "secs") * 1000 + 0.5)
  )
}

.pipeline_nrow <- function(x) {
  if (is.data.frame(x)) return(nrow(x))
  if (is.list(x) && length(x)) {
    vals <- vapply(x, function(d) if (is.data.frame(d)) nrow(d) else 0L, integer(1))
    return(max(vals) %||% 0L)
  }
  0L
}
.pipeline_ncol <- function(x) {
  if (is.data.frame(x)) return(ncol(x))
  if (is.list(x) && length(x)) {
    first <- x[[1]]
    if (is.data.frame(first)) return(ncol(first))
  }
  0L
}

# 把渲染结果移入缓存目录，返回文件名（带随机后缀避免缓存歧义）
file_move_to_cache <- function(path, dir) {
  if (!dir.exists(dir)) dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  fn <- sprintf("p-%s-%s.png", format(Sys.time(), "%H%M%OS3"),
                substr(as.character(abs(as.integer(runif(1, 1, 1e7)))), 1, 6))
  fn <- gsub("[^A-Za-z0-9_.-]", "", fn)
  ok <- file.copy(path, file.path(dir, fn), overwrite = TRUE)
  unlink(path)
  if (!ok) stop("无法写入渲染缓存目录")
  # 清理旧的渲染缓存（仅保留最近 24 个）
  files <- list.files(dir, pattern = "^p-.*\\.png$", full.names = TRUE)
  files <- files[order(file.mtime(files), decreasing = TRUE)]
  if (length(files) > 24) unlink(tail(files, -24))
  fn
}

# 任意代码（原始代码模式）渲染
ggspec_render_rawcode <- function(code, state, width, height, dpi, png_dir = NULL) {
  t0 <- Sys.time()
  rf <- ggspec_render_file(code, state$raw_data %||% NULL, width = width, height = height,
                           dpi = dpi, format = "png")
  png_val <- NULL; png_url <- NULL
  if (!is.null(png_dir)) {
    png_url <- paste0("/api/plot/", file_move_to_cache(rf$path, png_dir))
  } else {
    png_val <- jsonlite::base64_enc(readBin(rf$path, "raw", file.info(rf$path)$size))
    unlink(rf$path)
  }
  list(ok = TRUE, code = code, png = png_val, pngUrl = png_url, warnings = rf$warnings,
       messages = rf$messages,
       elapsedMs = as.integer(as.numeric(Sys.time() - t0, units = "secs") * 1000 + 0.5))
}

# 导出文件
ggspec_export <- function(spec, meta, state, width, height, dpi, format) {
  format <- match.arg(format, c("png", "svg", "pdf"))
  gen <- ggspec_pipeline(spec, meta, state)
  rf <- ggspec_render_file(gen$eval_code, gen$env_list, width = width, height = height,
                           dpi = dpi, format = format)
  rf$code <- gen$code
  rf
}

# 原始代码路径的中文字体兜底。
# 背景：ragg 默认 sans 在 Windows 上是 Arial，没有中文字形，
# 于是中文标签会渲染成缺字/乱码，并伴随大量
# "conversion failure ... in 'mbcsToSbcs'" 警告。
# spec 生成路径已有 .ggspec_cjk_font_line() 注入主题字体，
# 但「高级 / 代码图」是用户手写代码，没人替他补这一层。
# 处理：代码里出现中文、且用户没显式指定 family 时，补一条 theme(text = ...)。
.ggspec_apply_cjk_family <- function(plot_obj, code) {
  if (!inherits(plot_obj, "ggplot")) return(plot_obj)
  if (!isTRUE(.ggspec_has_cjk(code))) return(plot_obj)
  fam <- .ggspec_cjk_family()
  if (is.null(fam)) return(plot_obj)
  # 用户已显式设置字体 → 尊重其选择
  cur <- tryCatch(plot_obj$theme$text$family, error = function(e) NULL)
  if (!is.null(cur) && length(cur) && nzchar(as.character(cur)[1])) return(plot_obj)
  plot_obj + ggplot2::theme(text = ggplot2::element_text(family = fam))
}

# 从「代码图」导出：直接渲染这段代码，而不是按 spec 渲染。
# 代码图是由代码绘制的，spec 里可能没有任何图层 —— 之前用户点导出会得到一张空白图，
# 而且不报错（静默错误），比直接失败更糟。
ggspec_export_code <- function(code, spec, state, width, height, dpi, format) {
  format <- match.arg(format, c("png", "svg", "pdf"))
  if (!nzchar(code %||% "")) stop("没有可导出的代码")
  # 代码里通常用 df 引用数据，这里按 spec 的数据源解析后注入求值环境
  data_df <- tryCatch(ggspec_resolve_data(spec %||% list(), state), error = function(e) NULL)
  rf <- ggspec_render_file(code, data_df, width = width, height = height,
                           dpi = dpi, format = format)
  rf$code <- code
  rf
}

# ---- 导出前检查（P0：白底 / 尺寸 / dpi / 矢量 / 字体 / 字号）----------------
.ggspec_is_whiteish <- function(col) {
  rgb <- tryCatch(grDevices::col2rgb(col), error = function(e) NULL)
  if (is.null(rgb)) return(FALSE)
  all(rgb[, 1] >= 245)
}

ggspec_export_check <- function(spec, meta, state, width = 1600, height = 1000,
                                dpi = 300, format = "png", journal = NULL, code = NULL) {
  format <- match.arg(format, c("png", "svg", "pdf"))
  tpl <- journal_get(journal)
  issues <- list()
  add <- function(id, level, title, detail, fix = NULL) {
    issues[[length(issues) + 1]] <<- list(id = id, level = level, title = title,
                                          detail = detail, fix = fix)
  }
  w_mm <- width / max(dpi, 1) * 25.4
  h_mm <- height / max(dpi, 1) * 25.4
  info <- list(widthMm = round(w_mm, 1), heightMm = round(h_mm, 1), dpi = dpi,
               format = format, fonts = character(0), minTextPt = NA_real_,
               journal = if (is.null(tpl)) NULL else tpl$id,
               journalLabel = if (is.null(tpl)) NULL else tpl$label)

  is_code <- is.character(code) && length(code) == 1L && nzchar(code)
  # 代码图没有图层，也要能检查 —— 否则会误报「画布为空」
  has_layers <- is_code || length(spec$layers %||% list()) > 0 ||
    isTRUE((spec$combine %||% list())$active)
  if (!has_layers) {
    add("layers", "fail", "画布为空", "还没有任何图层，导出会得到空白图。")
    return(list(ok = FALSE, issues = issues, info = info))
  }

  # 构建图对象（与渲染/导出一致）；代码图按代码构建
  plot <- tryCatch({
    if (is_code) {
      data_df <- tryCatch(ggspec_resolve_data(spec %||% list(), state), error = function(e) NULL)
      env <- .ggspec_eval_env(data_df)
      ev <- .ggspec_eval(code, env)
      if (!is.null(ev$error)) stop(ev$error)
      .ggspec_pick_plot(ev$result, env)
    } else {
      gen <- ggspec_pipeline(spec, meta, state)
      env <- .ggspec_eval_env(gen$env_list)
      ev <- .ggspec_eval(gen$eval_code, env)
      if (!is.null(ev$error)) stop(ev$error)
      .ggspec_pick_plot(ev$result, env)
    }
  }, error = function(e) e)
  if (inherits(plot, "error") || is.null(plot)) {
    add("render", "fail", "图形无法生成", conditionMessage(plot))
    return(list(ok = FALSE, issues = issues, info = info))
  }

  # 0) 试渲染：图对象能构造 ≠ 能画出来（stat/scale 错误常发生在 print 时）
  render_err <- NULL
  alpha_ok <- TRUE
  tmp_png <- tempfile(fileext = ".png")
  tryCatch({
    ragg::agg_png(tmp_png, width = 160, height = 160, units = "px", res = 72, background = "white")
    tryCatch(print(plot), error = function(e) { render_err <<- conditionMessage(e) })
    grDevices::dev.off()
    if (is.null(render_err) && identical(format, "png")) {
      img <- png::readPNG(tmp_png)
      if (length(dim(img)) >= 3 && dim(img)[3] == 4) alpha_ok <- min(img[, , 4]) >= 1
    }
  }, error = function(e) {
    render_err <<- conditionMessage(e)
    try(grDevices::dev.off(), silent = TRUE)
  })
  unlink(tmp_png)
  if (!is.null(render_err)) {
    add("render", "fail", "图形无法渲染", render_err)
    return(list(ok = FALSE, issues = issues, info = info))
  }
  if (!alpha_ok) {
    add("alpha", "fail", "存在透明像素", "导出 PNG 含透明通道；期刊通常要求不透明白底。")
  }

  # 1) 背景：透明 / 非白
  if (inherits(plot, "patchwork")) {
    add("background", "info", "拼图背景", "拼图模式下按各子图主题渲染，请确认整体为白色背景。")
  } else {
    bg <- tryCatch(ggplot2::calc_element("plot.background", plot$theme), error = function(e) NULL)
    fill <- bg$fill %||% "white"
    if (length(fill) == 0 || is.na(fill) || identical(tolower(as.character(fill)), "transparent")) {
      add("background", "fail", "背景透明", "导出图背景为透明；多数期刊要求白底（白色背景）。",
          fix = list(action = "white", label = "改为白底"))
    } else if (!.ggspec_is_whiteish(fill)) {
      add("background", "warn", "背景不是白色", sprintf("当前背景色 %s；投稿通常要求白色背景。", fill),
          fix = list(action = "white", label = "改为白底"))
    } else {
      add("background", "pass", "白底", "背景为白色。")
    }
    panel_bg <- tryCatch(ggplot2::calc_element("panel.background", plot$theme), error = function(e) NULL)
    if (!is.null(panel_bg) && !is.null(panel_bg$fill) && !is.na(panel_bg$fill) &&
        !identical(tolower(as.character(panel_bg$fill)), "transparent") &&
        !.ggspec_is_whiteish(panel_bg$fill)) {
      add("panel", "info", "面板为彩色背景",
          sprintf("面板背景 %s；若期刊偏好白底，可把主题换成 minimal / classic。", panel_bg$fill))
    }
  }

  # 2) 分辨率 / 矢量 / 格式
  min_dpi <- if (!is.null(tpl) && !is.null(tpl$minDpi)) tpl$minDpi else 300
  if (format == "png") {
    if (dpi < min_dpi) {
      add("dpi", "warn", "位图分辨率偏低",
          sprintf("当前 %d dpi；%s要求位图 ≥%d dpi。", dpi,
                  if (is.null(tpl)) "多数期刊" else tpl$label, min_dpi),
          fix = list(action = "dpi", value = min_dpi, label = sprintf("改为 %d dpi", min_dpi)))
    } else {
      add("dpi", "pass", "位图分辨率", sprintf("%d dpi，达到 %d dpi 要求。", dpi, min_dpi))
    }
  } else {
    add("vector", "pass", "矢量格式", sprintf("%s 为矢量格式，缩放不失真。", toupper(format)))
  }
  if (!is.null(tpl) && length(tpl$formats) && !format %in% tpl$formats) {
    preferred <- if ("pdf" %in% tpl$formats) "pdf" else tpl$formats[1]
    add("format", "warn", "格式不在模板要求内",
        sprintf("%s 接受：%s；当前为 %s。", tpl$label,
                paste(toupper(tpl$formats), collapse = " / "), toupper(format)),
        fix = if (preferred %in% c("png", "svg", "pdf"))
          list(action = "format", value = preferred, label = sprintf("改用 %s", toupper(preferred))) else NULL)
  }

  # 3) 物理尺寸（模板优先）
  min_text_pt <- if (!is.null(tpl) && !is.null(tpl$minTextPt)) tpl$minTextPt else 6
  if (!is.null(tpl) && !is.null(tpl$widthMm)) {
    target <- tpl$widthMm
    ok_w <- abs(w_mm - target) <= 6 || abs(w_mm - 2 * target) <= 10
    if (!ok_w) {
      add("size", "warn", "宽度与模板栏宽不符",
          sprintf("%s 单栏约 %d mm（双栏约 %d mm）；当前 %.0f mm。", tpl$label, target,
                  2 * target, w_mm),
          fix = list(action = "width", value = target, label = sprintf("套用 %d mm 栏宽", target)))
    } else {
      add("size", "pass", "物理尺寸", sprintf("约 %.0f × %.0f mm，符合 %s 栏宽。", w_mm, h_mm, tpl$label))
    }
  } else if (w_mm < 80 || w_mm > 180) {
    add("size", "warn", "物理宽度非常见栏宽",
        sprintf("当前约 %.0f mm 宽；单栏常见 85 mm、双栏 170 mm。", w_mm),
        fix = list(action = "width", value = 85, label = "套用 85 mm 栏宽"))
  } else {
    add("size", "pass", "物理尺寸", sprintf("约 %.0f × %.0f mm（宽 × 高）。", w_mm, h_mm))
  }

  # 4) 字体可用性 + 5) 最小字号
  if (!inherits(plot, "patchwork")) {
    els <- c("plot.title", "axis.title.x", "axis.title.y", "axis.text.x", "axis.text.y",
             "legend.text", "legend.title")
    get_el <- function(e) tryCatch(ggplot2::calc_element(e, plot$theme), error = function(e2) NULL)
    fams <- unique(stats::na.omit(vapply(els, function(e) {
      x <- get_el(e)
      if (is.null(x) || is.null(x$family)) return(NA_character_)
      f <- as.character(x$family)
      if (!nzchar(f)) NA_character_ else f
    }, character(1))))
    info$fonts <- fams
    # sans/serif/mono 是设备通用别名，不算"缺失字体"
    check_fams <- setdiff(fams, c("sans", "serif", "mono", "sans-serif"))
    if (length(check_fams)) {
      sys <- tryCatch(unique(systemfonts::system_fonts()$family), error = function(e) character(0))
      missing <- setdiff(check_fams, sys)
      if (length(missing)) {
        add("font", "warn", "字体可能不可用",
            sprintf("未在本机找到：%s；导出会自动回退，可能影响最终字形。", paste(missing, collapse = "、")))
      } else if (!is.null(tpl) && length(tpl$fonts) &&
                 !all(tolower(check_fams) %in% tolower(tpl$fonts))) {
        add("font", "warn", "字体不在模板白名单",
            sprintf("%s 建议：%s；当前：%s。", tpl$label,
                    paste(tpl$fonts, collapse = " / "), paste(check_fams, collapse = " / ")),
            fix = list(action = "font", value = tpl$fonts[1],
                       label = sprintf("改用 %s", tpl$fonts[1])))
      } else {
        add("font", "pass", "字体可用", paste(check_fams, collapse = "、"))
      }
    } else {
      add("font", "pass", "字体", "使用设备默认字体（sans / serif / mono）。")
    }
    sizes <- vapply(c("axis.text.x", "axis.text.y", "legend.text"), function(e) {
      x <- get_el(e)
      if (is.null(x) || is.null(x$size)) NA_real_ else as.numeric(x$size)
    }, numeric(1))
    min_pt <- suppressWarnings(min(sizes, na.rm = TRUE))
    if (is.finite(min_pt)) {
      info$minTextPt <- round(min_pt, 1)
      if (min_pt < min_text_pt - 0.05) {
        add("textsize", "warn", "文字偏小",
            sprintf("最小有效字号约 %.1f pt；%s要求 ≥%.0f pt。", min_pt,
                    if (is.null(tpl)) "多数期刊" else tpl$label, min_text_pt),
            fix = list(action = "textsize", value = min_text_pt,
                       label = sprintf("字号提到 %.0f pt", min_text_pt)))
      } else {
        add("textsize", "pass", "文字字号",
            sprintf("最小约 %.1f pt（要求 ≥%.0f pt）。", min_pt, min_text_pt))
      }
    }
  }

  # 6) 透明像素已在试渲染阶段检查（见上）

  list(ok = !any(vapply(issues, function(i) identical(i$level, "fail"), logical(1))),
       issues = issues, info = info)
}

# spec -> 数据（考虑加工 + 手动编辑）
ggspec_resolve_data <- function(spec, state) {
  spec <- spec %||% list()
  src <- (spec$data %||% list())$source %||% list(type = "none")
  prep <- (spec$data %||% list())
  d <- NULL
  if (identical(src$type, "dataset")) {
    d <- tryCatch(dataset_load(src$name), error = function(e) NULL)
    if (is.null(d)) stop(sprintf("内置数据集不存在: %s", src$name))
  } else if (identical(src$type, "user")) {
    d <- state$data_store$get(src$id)
    if (is.null(d)) stop("上传数据不存在或已失效")
  } else {
    return(NULL)
  }
  d <- data_prepare(d, prep)
  est <- state$edit_store %||% NULL
  edits <- if (!is.null(est)) est$get(.keyof(src)) else list()
  if (length(edits)) {
    w <- tryCatch(apply_data_edits(d, edits), error = function(e) e)
    if (inherits(w, "error")) stop(w$message)
    d <- w
  }
  d
}

# spec -> plotly 交互 JSON（只输出 plotly.js 需要的 data/layout/config，
# 剔除 R 侧的懒求值对象 plotly_eval / 函数引用）
.plotly_clean <- function(x, depth = 0L) {
  if (depth > 30) return(NULL)
  if (is.function(x)) return(NULL)
  if (inherits(x, "JS_EVAL")) return(as.character(x))
  if (is.list(x)) {
    if (!is.null(class(x)) && any(class(x) %in% c("plotly_eval", "formula"))) return(NULL)
    keep <- lapply(x, .plotly_clean, depth = depth + 1L)
    keep <- keep[!vapply(keep, is.null, logical(1))]
    if (length(keep) && !is.null(names(x))) {
      keep <- keep[names(keep) != ""]
      return(keep)
    }
    return(keep)
  }
  if (length(x) > 1 && !is.atomic(x)) return(lapply(x, .plotly_clean, depth = depth + 1L))
  x
}

# spec -> plotly 交互 JSON
ggspec_to_plotly <- function(spec, meta, state, width, height) {
  if (!requireNamespace("plotly", quietly = TRUE)) stop("plotly 未安装")
  if (!ext_is_enabled("plotly")) stop("plotly 扩展已在「高级 → 扩展管理」中关闭")
  data_df <- ggspec_resolve_data(spec, state)
  gen <- spec_to_code(spec, meta, state)
  env <- .ggspec_eval_env(data_df)
  ev <- .ggspec_eval(gen$eval_code, env)
  if (!is.null(ev$error)) stop(ev$error)
  p <- .ggspec_pick_plot(ev$result, env)
  if (is.null(p) || inherits(p, "patchwork")) stop("该图不支持 plotly 预览")
  ply <- plotly::ggplotly(p, width = width, height = height, tooltip = "all")
  w <- plotly::as_widget(ply)
  payload <- list(
    data = .plotly_clean(w$x$data %||% list()),
    layout = .plotly_clean(w$x$layout %||% list()),
    config = .plotly_clean(w$x$config %||% list())
  )
  jsonlite::toJSON(payload, auto_unbox = TRUE, digits = NA, null = "null", na = "null")
}
