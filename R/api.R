# ggplotGUI - httpuv API 路由 + 静态文件服务

MIME_MAP <- c(
  html = "text/html; charset=utf-8", js = "application/javascript; charset=utf-8",
  mjs = "application/javascript; charset=utf-8", css = "text/css; charset=utf-8",
  json = "application/json; charset=utf-8", svg = "image/svg+xml",
  png = "image/png", jpg = "image/jpeg", ico = "image/x-icon",
  woff2 = "font/woff2", woff = "font/woff", ttf = "font/ttf",
  map = "application/json", txt = "text/plain; charset=utf-8", wasm = "application/wasm",
  csv = "text/csv; charset=utf-8"
)

.static_file <- function(root, url_path) {
  rel <- if (identical(url_path, "/") || !nzchar(url_path)) "index.html" else sub("^/", "", url_path)
  # 安全：禁止路径穿越（先删 ".." 再规范化校验，双重保险）
  rel <- gsub("\\.\\.", "", rel)
  full <- file.path(root, rel)
  root_norm <- normalizePath(root, winslash = "/", mustWork = FALSE)
  full_norm <- normalizePath(full, winslash = "/", mustWork = FALSE)
  inside <- identical(full_norm, root_norm) || startsWith(paste0(full_norm, "/"), paste0(root_norm, "/"))
  if (!inside) {
    return(list(status = 403L, headers = list("Content-Type" = "text/plain; charset=utf-8"),
                body = "forbidden"))
  }
  if (!file.exists(full) || dir.exists(full)) {
    # SPA 回退到 index.html
    full <- file.path(root, "index.html")
    if (!file.exists(full)) return(list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "frontend dist not found"))
  }
  ext <- tolower(tools::file_ext(full))
  mime <- .mime_for(ext)
  cache <- if (startsWith(rel, "assets/")) "public, max-age=31536000, immutable" else "no-cache"
  body <- readBin(full, "raw", file.info(full)$size)
  list(status = 200L,
       headers = list("Content-Type" = mime, "Cache-Control" = cache),
       body = body)
}


# 数据源键（dataset:mpg / user:u1）与标识统一在 dataio.R 中定义（.keyof / src_id_of）

# MIME 空安全查找（向量 [[未知键]] 会抛错，需 tryCatch）
.mime_for <- function(ext) {
  v <- tryCatch(MIME_MAP[[tolower(ext)]], error = function(e) NULL)
  v %||% "application/octet-stream"
}

.query_param <- function(req, key) {
  qs <- req$QUERY_STRING %||% ""
  parts <- strsplit(sub("^\\?", "", qs), "&", fixed = TRUE)[[1]]
  for (p in parts) {
    kv <- strsplit(p, "=", fixed = TRUE)[[1]]
    if (identical(URLdecode(kv[1]), key)) return(URLdecode(paste(kv[-1], collapse = "=")))
  }
  NULL
}

## ---- 请求来源校验 ----------------------------------------------------------
## 本服务会在本机执行任意 R 代码（原始代码模式），因此必须挡住浏览器侧的跨站请求：
## 任意网页只要能对本机发 POST，就能借用户的浏览器执行 R 代码。
.host_name <- function(h) {
  h <- as.character(h %||% "")
  h <- sub("^[a-zA-Z][a-zA-Z0-9+.-]*://", "", h)   # 去掉 scheme（Origin 是 http://host:port）
  h <- sub("[/?#].*$", "", h)                      # 去掉 path / query / fragment
  h <- sub("^\\[", "", h)                          # [::1]:8080 -> ::1
  h <- sub("\\].*$", "", h)
  sub(":[0-9]+$", "", h)                           # 去掉端口
}

# authority = host:port（去掉 scheme 与 path），用于同源比较
.authority <- function(h) {
  h <- as.character(h %||% "")
  h <- sub("^[a-zA-Z][a-zA-Z0-9+.-]*://", "", h)
  tolower(trimws(sub("[/?#].*$", "", h)))
}

.request_guard <- function(req, state = NULL) {
  st <- state %||% list()
  host <- as.character(req$HTTP_HOST %||% "")
  # 1) Host 白名单：防 DNS 重绑定（evil.com 解析到 127.0.0.1 时 Host 仍是 evil.com）
  allowed <- st$allowed_hosts %||% c("127.0.0.1", "localhost", "::1")
  if (nzchar(host) && !isTRUE(st$allow_any_host)) {
    hn <- tolower(.host_name(host))
    if (!hn %in% tolower(allowed)) {
      return(sprintf("拒绝访问：Host %s 不在允许列表内", host))
    }
  }
  # 2) Origin 必须与 Host 同源（浏览器对同源 POST 也会带 Origin，不能只看主机名）
  origin <- as.character(req$HTTP_ORIGIN %||% "")
  if (nzchar(origin) && nzchar(host)) {
    oa <- .authority(origin); ha <- .authority(host)
    if (!identical(oa, ha)) {
      has_port <- function(x) grepl(":[0-9]+$", x)
      # 端口省略时（如 Host: 127.0.0.1）退化为只比主机名，其余情况按 host:port 严格比较
      if (has_port(oa) && has_port(ha)) return("跨站请求被拒绝（Origin 与 Host 不一致）")
      if (!identical(tolower(.host_name(oa)), tolower(.host_name(ha)))) {
        return("跨站请求被拒绝（Origin 与 Host 不一致）")
      }
    }
  }
  if (identical(tolower(as.character(req$HTTP_SEC_FETCH_SITE %||% "")), "cross-site")) {
    return("跨站请求被拒绝（Sec-Fetch-Site: cross-site）")
  }
  # 3) POST 必须是 application/json（强制 CORS 预检，普通表单/文本请求无法伪造）
  if (identical(toupper(req$REQUEST_METHOD %||% "GET"), "POST")) {
    ct <- tolower(as.character(req$CONTENT_TYPE %||% req$HTTP_CONTENT_TYPE %||% ""))
    if (!startsWith(ct, "application/json")) {
      return("请求 Content-Type 必须为 application/json")
    }
  }
  NULL
}

ggspec_api_app <- function(state) {

  route <- function(req, body) {
    path <- req$PATH_INFO
    method <- req$REQUEST_METHOD

    ## ---- 元数据 ----
    if (path == "/api/meta" && method == "GET") {
      return(json_response(list(ok = TRUE, meta = state$meta)))
    }

    ## ---- 数据源 ----
    if (path == "/api/sources" && method == "GET") {
      return(json_response(list(ok = TRUE, sources = data_sources())))
    }

    if (path == "/api/data/upload" && method == "POST") {
      name <- body$name %||% "upload.csv"
      ext <- body$ext %||% tools::file_ext(name)
      b64 <- body$dataBase64
      if (is.null(b64) || !nzchar(b64)) return(json_error("缺少文件内容"))
      d <- tryCatch(data_from_upload(name, ext, b64), error = function(e) e)
      if (inherits(d, "error")) return(json_error(d$message, 400))
      id <- state$data_store$add(d, body$label %||% name)
      info <- state$data_store$info(id)
      return(json_response(list(ok = TRUE, source = info, columns = column_info(d))))
    }

    if (path == "/api/data/paste" && method == "POST") {
      txt <- body$text %||% ""
      if (!nzchar(trimws(txt))) return(json_error("粘贴内容为空"))
      d <- tryCatch(data_from_paste(txt), error = function(e) e)
      if (inherits(d, "error")) return(json_error(d$message, 400))
      label <- body$label %||% sprintf("粘贴数据 %s", format(Sys.time(), "%H:%M:%S"))
      id <- state$data_store$add(d, label)
      return(json_response(list(ok = TRUE, source = state$data_store$info(id),
                                columns = column_info(d))))
    }

    if (path == "/api/columns" && method == "GET") {
      src <- .query_param(req, "src") %||% ""
      d <- tryCatch(resolve_source_df(src, state), error = function(e) e)
      if (inherits(d, "error")) return(json_error(d$message, 400))
      if (is.null(d)) return(json_response(list(ok = TRUE, columns = list())))
      return(json_response(list(ok = TRUE, columns = column_info(d))))
    }

    .prepared_full <- function(src, prep) {
      raw <- resolve_source_df(paste0((src$type %||% "none"), ":", src_id_of(src)), state)
      d <- data_prepare(raw, prep)
      key <- .keyof(src)
      d <- apply_data_edits(d, state$edit_store$get(key))
      list(d = d, key = key)
    }

    if (path == "/api/data/preview" && method == "POST") {
      src <- body$source
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      d <- pv$d
      if (is.null(d) || !nrow(d)) {
        return(json_response(list(ok = TRUE, nrow = 0, ncol = 0, columns = list(), rows = list())))
      }
      # 服务端排序（可选）
      sort_col <- body$sortCol %||% NULL
      if (!is.null(sort_col) && nzchar(sort_col) && sort_col %in% names(d)) {
        d <- d[order(d[[sort_col]], decreasing = !isTRUE(body$asc), na.last = TRUE), , drop = FALSE]
      }
      total <- nrow(d)
      # 服务端分页（可选；缺省回退前 n 行）
      # 注意：start 可能超过 total（例如在最后一页删完行后前端未回夹页码），
      # 必须夹取，否则 seq(start, total) 会反向递减并返回大量 NA 行。
      start <- suppressWarnings(as.integer(body$start %||% 1L))
      if (is.na(start) || start < 1L) start <- 1L
      len <- suppressWarnings(as.integer(body$length %||% as.integer(body$n %||% 30L)))
      if (is.na(len) || len < 1L) len <- 30L
      len <- min(len, 1000L)
      if (start > total) start <- max(1L, total - len + 1L)
      idx <- seq.int(start, min(total, start + len - 1L))
      rows <- lapply(idx, function(i) as.list(lapply(d[i, , drop = FALSE], function(x) {
        if (length(x) == 1 && is.na(x)) NA else x
      })))
      rows <- lapply(rows, function(r) lapply(r, function(v) if (is.null(v)) NA else v))
      row_ids <- as.list(d$.gg_rid[idx])
      return(json_response(list(ok = TRUE, nrow = total, ncol = length(column_info(d)),
                                columns = column_info(d), rows = rows, rowIds = row_ids,
                                page = list(start = start, length = length(idx)))))
    }

    ## 加工后数据导出 CSV
    if (path == "/api/data/export-csv" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      d <- pv$d
      if (is.null(d) || !nrow(d)) return(json_error("没有可导出的数据", 400))
      fname <- sprintf("ggplotgui-data-%s.csv", format(Sys.time(), "%Y%m%d-%H%M%S"))
      fname <- gsub("[^A-Za-z0-9_.-]", "", fname)
      full <- file.path(state$plot_dir, fname)
      disp <- d[, setdiff(names(d), ".gg_rid"), drop = FALSE]
      readr::write_csv(disp, full)
      return(json_response(list(ok = TRUE, url = paste0("/api/plotfile/", fname), filename = fname)))
    }

    if (path == "/api/data/delete" && method == "POST") {
      state$data_store$remove(body$id %||% "")
      return(json_response(list(ok = TRUE)))
    }

    ## 项目数据快照：把上传/粘贴的原始数据序列化为 CSV，供项目文件内嵌
    ## （内置数据集不内嵌，靠数据集名即可复现）
    if (path == "/api/data/snapshot" && method == "POST") {
      src <- body$source %||% list()
      if (!identical(src$type %||% "", "user")) {
        return(json_error("只有上传/粘贴的数据需要内嵌", 400))
      }
      id <- src_id_of(src)
      d <- state$data_store$get(id)
      if (is.null(d)) return(json_error("数据不存在或已失效", 404))
      d2 <- d[, setdiff(names(d), ".gg_rid"), drop = FALSE]
      csv <- tryCatch(paste(readr::format_csv(d2), collapse = ""),
                      error = function(e) {
                        paste(utils::capture.output(
                          utils::write.csv(d2, row.names = FALSE, na = "")), collapse = "\n")
                      })
      if (!nzchar(csv)) return(json_error("数据快照失败", 500))
      info <- state$data_store$info(id) %||% list()
      return(json_response(list(ok = TRUE, csv = csv,
                                label = info$label %||% id,
                                nrow = nrow(d2), ncol = ncol(d2))))
    }

    ## ---- 渲染 ----
    if (path == "/api/render" && method == "POST") {
      spec <- body$spec %||% list()
      width <- as.integer(body$width %||% 800); height <- as.integer(body$height %||% 500)
      dpi <- as.integer(body$dpi %||% 150)
      res <- tryCatch(ggspec_render_preview(spec, state$meta, state, width, height, dpi,
                                            png_dir = state$plot_dir),
                      error = function(e) e)
      if (inherits(res, "error")) {
        msg <- if (inherits(res, "ggplot_error")) res$message else conditionMessage(res)
        return(json_response(list(ok = FALSE, error = msg,
                                  warnings = attr(res, "warnings") %||% list())))
      }
      return(json_response(res))
    }

    if (path == "/api/code" && method == "POST") {
      spec <- body$spec %||% list()
      res <- tryCatch(spec_to_code(spec, state$meta, state), error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, code = res$code, warnings = res$warnings)))
    }

    if (path == "/api/rawrender" && method == "POST") {
      code <- body$code %||% ""
      spec <- body$spec %||% list()
      state$raw_data <- tryCatch(ggspec_resolve_data(spec, state), error = function(e) NULL)
      width <- as.integer(body$width %||% 800); height <- as.integer(body$height %||% 500)
      dpi <- as.integer(body$dpi %||% 150)
      res <- tryCatch(ggspec_render_rawcode(code, state, width, height, dpi,
                                            png_dir = state$plot_dir),
                      error = function(e) e)
      if (inherits(res, "error")) {
        msg <- if (inherits(res, "ggplot_error")) res$message else conditionMessage(res)
        return(json_response(list(ok = FALSE, error = msg)))
      }
      return(json_response(res))
    }

    ## ---- 渲染结果 PNG 文件 ----
    if (startsWith(path, "/api/plot/") && method == "GET") {
      fn <- gsub("[^A-Za-z0-9_.-]", "", basename(path))
      full <- file.path(state$plot_dir, fn)
      if (!nzchar(fn) || !file.exists(full)) {
        return(list(status = 404L, headers = list("Content-Type" = "text/plain; charset=utf-8"),
                    body = "not found"))
      }
      bytes <- readBin(full, "raw", file.info(full)$size)
      return(list(status = 200L,
                  headers = list("Content-Type" = "image/png", "Cache-Control" = "no-store"),
                  body = bytes))
    }

    ## ---- 导出 ----
    if (path == "/api/export/check" && method == "POST") {
      spec <- body$spec %||% list()
      format <- body$format %||% "png"
      width <- as.integer(body$width %||% 1600); height <- as.integer(body$height %||% 1000)
      dpi <- as.integer(body$dpi %||% 300)
      res <- tryCatch(ggspec_export_check(spec, state$meta, state, width, height, dpi, format),
                      error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(res))
    }
    if (path == "/api/export" && method == "POST") {
      spec <- body$spec %||% list()
      format <- body$format %||% "png"
      width <- as.integer(body$width %||% 1600); height <- as.integer(body$height %||% 1000)
      dpi <- as.integer(body$dpi %||% 300)
      res <- tryCatch(ggspec_export(spec, state$meta, state, width, height, dpi, format),
                      error = function(e) e)
      if (inherits(res, "error")) {
        msg <- if (inherits(res, "ggplot_error")) res$message else conditionMessage(res)
        return(json_error(msg, 400))
      }
      # 大文件落盘，前端经 /api/plotfile/<fn> 下载
      ext <- switch(format, png = "png", svg = "svg", pdf = "pdf", "png")
      fname <- sprintf("ggplotgui-%s.%s", format(Sys.time(), "%Y%m%d-%H%M%S"), ext)
      fname <- gsub("[^A-Za-z0-9_.-]", "", fname)
      ok <- file.copy(res$path, file.path(state$plot_dir, fname), overwrite = TRUE)
      unlink(res$path)
      if (!ok) return(json_error("导出文件写入失败", 500))
      return(json_response(list(ok = TRUE, url = paste0("/api/plotfile/", fname), filename = fname)))
    }

    ## ---- 导出文件下载 ----
    if (startsWith(path, "/api/plotfile/") && method == "GET") {
      fn <- gsub("[^A-Za-z0-9_.-]", "", basename(path))
      full <- file.path(state$plot_dir, fn)
      if (!nzchar(fn) || !file.exists(full)) {
        return(list(status = 404L, headers = list("Content-Type" = "text/plain; charset=utf-8"),
                    body = "not found"))
      }
      ext <- tolower(tools::file_ext(full))
      bytes <- readBin(full, "raw", file.info(full)$size)
      headers <- list("Content-Type" = .mime_for(ext),
                      "Cache-Control" = "no-store")
      # 附带 Content-Disposition 时浏览器直接下载；但 <a download>/fetch 也能取
      return(list(status = 200L, headers = headers, body = bytes))
    }

    ## ---- plotly ----
    if (path == "/api/plotly" && method == "POST") {
      spec <- body$spec %||% list()
      width <- as.integer(body$width %||% 800); height <- as.integer(body$height %||% 500)
      res <- tryCatch(ggspec_to_plotly(spec, state$meta, state, width, height), error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      # plotly JSON 可能很大：落盘后由前端 GET 拉取
      fn <- paste0("ply-", format(Sys.time(), "%H%M%OS3"), ".json")
      fn <- gsub("[^A-Za-z0-9_.-]", "", fn)
      writeBin(charToRaw(enc2utf8(res)), file.path(state$plot_dir, fn))
      old <- list.files(state$plot_dir, pattern = "^ply-.*\\.json$", full.names = TRUE)
      old <- old[order(file.mtime(old), decreasing = TRUE)]
      if (length(old) > 6) unlink(tail(old, -6))
      return(json_response(list(ok = TRUE, url = paste0("/api/plotdata/", fn))))
    }

    ## ---- 手动编辑（编辑模式）----
    if (path == "/api/edits" && method == "GET") {
      key <- .query_param(req, "key") %||% ""
      return(json_response(list(ok = TRUE, ops = state$edit_store$get(key),
                                count = state$edit_store$count(key))))
    }
    if (path == "/api/edits/add" && method == "POST") {
      src <- body$source %||% list()
      op <- body$op %||% NULL
      if (is.null(op) || is.null(op$kind)) return(json_error("缺少编辑操作", 400))
      key <- .keyof(src)
      # 后端校验：应用到副本，出错即拒绝（warning 也视为失败，避免「静默变 NA」这类问题）
      probe <- tryCatch(
        withCallingHandlers({
          d <- resolve_source_df(paste0((src$type %||% "none"), ":", src_id_of(src)), state)
          d <- data_prepare(d, body$prep %||% list())
          apply_data_edits(d, state$edit_store$get(key))
          apply_data_edits(d, list(op))
          TRUE
        }, warning = function(w) stop(conditionMessage(w), call. = FALSE)),
        error = function(e) e)
      if (inherits(probe, "error")) return(json_error(conditionMessage(probe), 400))
      state$edit_store$add(key, op)
      return(json_response(list(ok = TRUE, count = state$edit_store$count(key))))
    }
    if (path == "/api/edits/undo" && method == "POST") {
      src <- body$source %||% list()
      key <- .keyof(src)
      last <- state$edit_store$pop(key)
      return(json_response(list(ok = TRUE, popped = !is.null(last),
                                count = state$edit_store$count(key),
                                undoKind = last$kind %||% NULL)))
    }
    if (path == "/api/edits/clear" && method == "POST") {
      src <- body$source %||% list()
      state$edit_store$clear(.keyof(src))
      return(json_response(list(ok = TRUE)))
    }
    ## 项目载入时批量恢复手工编辑（跟随数据一起内嵌在项目文件里）
    if (path == "/api/edits/import" && method == "POST") {
      src <- body$source %||% list()
      ops <- body$ops %||% list()
      key <- .keyof(src)
      imported <- 0L
      for (op in ops) {
        if (is.list(op) && !is.null(op$kind)) {
          state$edit_store$add(key, op)
          imported <- imported + 1L
        }
      }
      return(json_response(list(ok = TRUE, imported = imported,
                                count = state$edit_store$count(key))))
    }
    ## ---- 图库（pins）----
    if (path == "/api/pins" && method == "GET") {
      return(json_response(list(ok = TRUE, pins = state$pin_store$list())))
    }
    if (path == "/api/pins/save" && method == "POST") {
      spec_json <- tryCatch({
        raw <- trimws(as.character(body$specJson %||% ""))
        if (!nzchar(raw)) return(json_error("缺少绘图规格"))
        # 校验可解析
        jsonlite::fromJSON(raw, simplifyVector = FALSE)
        raw
      }, error = function(e) NULL)
      if (is.null(spec_json)) return(json_error("绘图规格解析失败", 400))
      id <- state$pin_store$add(spec_json, (body$label %||% NULL))
      return(json_response(list(ok = TRUE, id = id, pins = state$pin_store$list())))
    }
    if (path == "/api/pins/delete" && method == "POST") {
      state$pin_store$remove(body$id %||% "")
      return(json_response(list(ok = TRUE, pins = state$pin_store$list())))
    }
    if (path == "/api/pins/rename" && method == "POST") {
      state$pin_store$rename(body$id %||% "", as.character(body$label %||% ""))
      return(json_response(list(ok = TRUE, pins = state$pin_store$list())))
    }

    ## ---- 大 JSON 数据文件（plotly 等）----
    if (startsWith(path, "/api/plotdata/") && method == "GET") {
      fn <- gsub("[^A-Za-z0-9_.-]", "", basename(path))
      full <- file.path(state$plot_dir, fn)
      if (!nzchar(fn) || !file.exists(full)) {
        return(list(status = 404L, headers = list("Content-Type" = "text/plain; charset=utf-8"),
                    body = "not found"))
      }
      bytes <- readBin(full, "raw", file.info(full)$size)
      return(list(status = 200L,
                  headers = list("Content-Type" = "application/json; charset=utf-8",
                                 "Cache-Control" = "no-store"),
                  body = bytes))
    }

    json_error(sprintf("未知路由: %s %s", method, path), 404)
  }

  list(
    call = function(req) {
      if (startsWith(req$PATH_INFO, "/api/")) {
        guard <- .request_guard(req, state)
        if (!is.null(guard)) return(json_error(guard, 403))
        parse_err <- NULL
        body <- tryCatch(parse_json_body(req),
                         error = function(e) {
                           parse_err <<- conditionMessage(e)
                           glog("BODY PARSE ERR [", req$PATH_INFO, "]: ", parse_err)
                           list()
                         })
        if (!is.null(parse_err)) {
          return(json_error(paste0("请求体解析失败: ", parse_err), 400))
        }
        tryCatch(route(req, body),
                 error = function(e) json_error(paste0("服务器内部错误: ", conditionMessage(e)), 500))
      } else {
        .static_file(state$dist_dir, req$PATH_INFO)
      }
    }
  )
}

# "dataset:mpg" / "user:u1" / "none" -> data.frame
resolve_source_df <- function(src_str, state) {
  parts <- strsplit(src_str, ":", fixed = TRUE)[[1]]
  type <- parts[1]; name <- if (length(parts) > 1) parts[2] else ""
  if (identical(type, "dataset") && nzchar(name)) return(dataset_load(name))
  if (identical(type, "user") && nzchar(name)) {
    d <- state$data_store$get(name)
    if (is.null(d)) stop("上传数据不存在或已失效")
    return(d)
  }
  NULL
}
