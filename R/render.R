# ggplotGUI - 渲染与导出：eval 生成的代码 -> 设备输出
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
  ev <- .ggspec_eval(code, env)
  if (!is.null(ev$error)) {
    stop(structure(class = "ggplot_error", list(message = ev$error,
                                                warnings = ev$warnings)))
  }
  plot_obj <- .ggspec_pick_plot(ev$result, env)
  if (is.null(plot_obj)) stop("代码没有产生 ggplot 对象（最后表达式或变量 p）")

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
