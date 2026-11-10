# Glyph - httpuv API 路由 + 静态文件服务

MIME_MAP <- c(
  html = "text/html; charset=utf-8", js = "application/javascript; charset=utf-8",
  mjs = "application/javascript; charset=utf-8", css = "text/css; charset=utf-8",
  json = "application/json; charset=utf-8", svg = "image/svg+xml",
  png = "image/png", jpg = "image/jpeg", ico = "image/x-icon",
  woff2 = "font/woff2", woff = "font/woff", ttf = "font/ttf",
  map = "application/json", txt = "text/plain; charset=utf-8", wasm = "application/wasm",
  csv = "text/csv; charset=utf-8", zip = "application/zip",
  md = "text/markdown; charset=utf-8", r = "text/plain; charset=utf-8"
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

    ## ---- 退出服务 ----
    ## 只置标志位，由 run.R 的主循环检测后优雅停止（httpuv::runServer 是阻塞的，无法从请求内部停止）
    ## 注意：state 是 list（值语义），直接写 state$shutdown_requested 只改局部副本；
    ## 必须通过环境（引用语义）把标志传回主循环。
    if (path == "/api/shutdown" && method == "POST") {
      if (!is.null(state$shutdown_flag) && is.environment(state$shutdown_flag)) {
        state$shutdown_flag$requested <- TRUE
      }
      glog("收到退出请求，服务即将停止")
      return(json_response(list(ok = TRUE, message = "服务正在退出")))
    }

    ## ---- 心跳：IDE 插件定时调用，用于判定宿主是否还活着 ----
    ## 同样必须用环境回传（state 是值语义的 list）
    if (path == "/api/heartbeat") {
      if (!is.null(state$heartbeat_env) && is.environment(state$heartbeat_env)) {
        assign("last", Sys.time(), envir = state$heartbeat_env)
      }
      return(json_response(list(ok = TRUE)))
    }

    ## ---- 扩展管理 ----
    if (path == "/api/extensions" && method == "GET") {
      return(json_response(list(ok = TRUE, extensions = ext_catalog())))
    }
    # 启停扩展：会重建元数据注册表（扫描耗时约 0.5-1s）
    if (path == "/api/extensions/toggle" && method == "POST") {
      id <- as.character(body$id %||% "")
      on <- isTRUE(body$enabled)
      chk <- tryCatch({ ext_set_enabled(id, on); TRUE }, error = function(e) e)
      if (inherits(chk, "error")) return(json_error(conditionMessage(chk), 400))
      # 开关改变了扫描范围 → 重建 meta
      state$meta <- tryCatch(meta_build_lookup(ggspec_build_meta()), error = function(e) state$meta)
      return(json_response(list(ok = TRUE, id = id, enabled = ext_is_enabled(id),
                                meta = state$meta, extensions = ext_catalog())))
    }

    # 一键安装扩展（后台 Rscript，轮询 /api/extensions/install/status）
    if (path == "/api/extensions/install" && method == "POST") {
      pkg <- as.character(body$pkg %||% "")
      res <- tryCatch(ext_install_start(pkg), error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, job = list(id = res$id, pkg = res$pkg,
                                                      status = res$status))))
    }
    if (path == "/api/extensions/install/status" && method == "GET") {
      st <- ext_install_status()
      meta <- ext_install_meta(state)
      return(json_response(list(ok = TRUE, job = st, meta = meta,
                                extensions = ext_catalog())))
    }

    ## ---- 远程数据库（P1）----
    if (path == "/api/db/drivers" && method == "GET") {
      return(json_response(list(ok = TRUE, drivers = db_driver_catalog())))
    }
    if (path == "/api/db/test" && method == "POST") {
      res <- tryCatch(db_test_connection(body %||% list()), error = function(e) e)
      if (inherits(res, "error")) return(json_response(list(ok = FALSE, error = conditionMessage(res))))
      return(json_response(list(ok = TRUE, result = res)))
    }
    if (path == "/api/db/connect" && method == "POST") {
      res <- tryCatch(db_connect(body %||% list()), error = function(e) e)
      if (inherits(res, "error")) return(json_response(list(ok = FALSE, error = conditionMessage(res))))
      return(json_response(list(ok = TRUE, connection = res,
                                connections = db_connections())))
    }
    if (path == "/api/db/tables" && method == "GET") {
      conn <- .query_param(req, "conn") %||% ""
      res <- tryCatch(db_tables(conn), error = function(e) e)
      if (inherits(res, "error")) return(json_response(list(ok = FALSE, error = conditionMessage(res))))
      return(json_response(list(ok = TRUE, tables = res)))
    }
    if (path == "/api/db/preview" && method == "POST") {
      res <- tryCatch(db_preview(body$conn %||% "", body$schema %||% "", body$table %||% "",
                                 body$sql %||% "", body$limit %||% 100), error = function(e) e)
      if (inherits(res, "error")) return(json_response(list(ok = FALSE, error = conditionMessage(res))))
      return(json_response(list(ok = TRUE, preview = res)))
    }
    if (path == "/api/db/import" && method == "POST") {
      res <- tryCatch(db_import(body$conn %||% "", body$schema %||% "", body$table %||% "",
                                body$sql %||% "", body$label %||% NULL, body$limit %||% 1000000L),
                      error = function(e) e)
      if (inherits(res, "error")) return(json_response(list(ok = FALSE, error = conditionMessage(res))))
      return(json_response(list(ok = TRUE, source = res$info, columns = res$columns)))
    }
    if (path == "/api/db/disconnect" && method == "POST") {
      db_disconnect(body$conn %||% "")
      return(json_response(list(ok = TRUE, connections = db_connections())))
    }
    if (path == "/api/db/connections" && method == "GET") {
      return(json_response(list(ok = TRUE, connections = db_connections())))
    }

    ## ---- 元数据 ----
    if (path == "/api/meta" && method == "GET") {
      return(json_response(list(ok = TRUE, meta = state$meta,
                                workspace = state$workspace)))
    }

    ## ---- 代码推送（外部 → 编辑器）----
    ## 供 IDE / AI 等外部进程把一段 R 代码送进「高级」页的编辑器。
    ##   POST /api/code/push   { code, run? }  → 暂存待取
    ##   GET  /api/code/pending               → 取走（取走即清空，避免重复注入）
    ## 例：curl -X POST localhost:4321/api/code/push \
    ##       -H 'Content-Type: application/json' \
    ##       -d '{"code":"ggplot(mtcars,aes(wt,mpg))+geom_point()","run":true}'
    ## 默认 run=false（只填进编辑器，由用户确认后再运行）；
    ## run=true 时前端会在填入后立即运行一次。
    if (path == "/api/code/push" && method == "POST") {
      code <- as.character(unlist(body$code %||% ""))
      code <- if (length(code)) code[1] else ""
      if (!nzchar(trimws(code))) return(json_error("缺少 code", 400))
      state$code_seq <- as.integer(state$code_seq %||% 0L) + 1L
      state$pending_code <- list(seq = state$code_seq, code = code,
                                 run = isTRUE(body$run),
                                 at = as.numeric(Sys.time()))
      cat(sprintf("[code-push] seq=%d run=%s len=%d\n", state$code_seq,
                  isTRUE(body$run), nchar(code)), file = stderr())
      return(json_response(list(ok = TRUE, seq = state$code_seq)))
    }
    if (path == "/api/code/pending" && method == "GET") {
      pc <- state$pending_code
      if (is.null(pc)) return(json_response(list(ok = TRUE, seq = 0L, code = NULL)))
      state$pending_code <- NULL
      return(json_response(list(ok = TRUE, seq = pc$seq, code = pc$code,
                                run = isTRUE(pc$run))))
    }

    ## ---- 工作区 ----
    ## GET  返回当前工作区；POST { dir } 运行时切换（重新绑定各 store）
    ## 传 dir = "" 表示退回安装目录。
    if (path == "/api/workspace" && method == "GET") {
      return(json_response(list(ok = TRUE, workspace = state$workspace)))
    }
    if (path == "/api/workspace" && method == "POST") {
      # 只取第一个标量：防御性处理（不同客户端可能把 dir 传成数组或带尾部空白）
      want <- trimws(as.character(unlist(body$dir %||% "")))
      want <- if (length(want)) want[1] else ""
      if (!nzchar(want)) {
        # 退回安装目录
        target <- state$workspace$appRoot
        explicit <- FALSE
      } else {
        target <- WORKSPACE$normalize(want)
        if (is.null(target)) {
          return(json_error(sprintf("目录不可用：%s", want), 400))
        }
        explicit <- TRUE
      }
      # 切目录不影响正在运行的渲染缓存（在 tempdir 里），只重绑持久化数据
      lay <- tryCatch(bind_workspace(state, target),
                      error = function(e) e)
      if (inherits(lay, "error")) {
        return(json_error(sprintf("切换工作区失败：%s", conditionMessage(lay)), 500))
      }
      # 切工作区后清掉上一个项目的运行时数据，避免代码图继续用旧 df
      state$raw_data <- NULL
      state$pending_code <- NULL
      state$workspace <- list(
        root = lay$root,
        id = WORKSPACE$id_for(lay$root),
        explicit = explicit,
        appRoot = state$workspace$appRoot
      )
      return(json_response(list(
        ok = TRUE,
        workspace = state$workspace,
        pins = state$pin_store$list(),
        sources = data_sources()
      )))
    }

    ## ---- 代码补全词表 ----
    ## 从 meta（geom/stat/scale/coord/theme 主题函数）+ 已安装包生成，
    ## 供前端编辑器做静态补全。结果缓存在 state 上，避免每次重算。
    if (path == "/api/completions" && method == "GET") {
      if (is.null(state$completions)) {
        state$completions <- tryCatch(
          ggspec_build_completions(state$meta),
          error = function(e) list(error = conditionMessage(e))
        )
      }
      return(json_response(list(ok = TRUE, completions = state$completions)))
    }

    ## ---- 数据源 ----
    if (path == "/api/sources" && method == "GET") {
      return(json_response(list(ok = TRUE, sources = data_sources())))
    }

    ## ---- 导入向导（P0）----
    if (path == "/api/import/drivers" && method == "GET") {
      return(json_response(list(ok = TRUE, drivers = import_drivers())))
    }
    if (path == "/api/import/upload" && method == "POST") {
      res <- tryCatch(
        import_upload(body$name %||% "upload.csv", body$ext %||% NULL, body$dataBase64 %||% ""),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, session = res)))
    }
    if (path == "/api/import/preview" && method == "POST") {
      res <- tryCatch(
        import_preview(body$token %||% "", body$opts %||% list(), body$limit %||% 50),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, preview = res)))
    }
    if (path == "/api/import/commit" && method == "POST") {
      res <- tryCatch(
        import_commit_file(body$token %||% "", body$opts %||% list(), body$label %||% NULL),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, source = res$info, columns = res$columns)))
    }
    if (path == "/api/import/sqlite/tables" && method == "GET") {
      tok <- .query_param(req, "token") %||% ""
      res <- tryCatch(.import_sqlite_tables(tok), error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, tables = res)))
    }
    if (path == "/api/import/sqlite/preview" && method == "POST") {
      res <- tryCatch(
        .import_sqlite_preview(body$token %||% "", body$table %||% "", body$limit %||% 100),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, preview = res)))
    }
    if (path == "/api/import/sqlite/commit" && method == "POST") {
      res <- tryCatch(
        import_commit_sqlite(body$token %||% "", body$table %||% "", body$label %||% NULL,
                             body$limit %||% 1000000L),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, source = res$info, columns = res$columns)))
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

    # 数据准备摘要（步骤影响 + 代码），界面展示用
    if (path == "/api/prep/summary" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      raw <- tryCatch(resolve_source_df(paste0((src$type %||% "none"), ":", src_id_of(src)), state),
                      error = function(e) e)
      if (inherits(raw, "error")) return(json_error(conditionMessage(raw), 400))
      s <- data_prep_summary(raw, prep)
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      final <- if (inherits(pv, "error")) s else pv$d
      return(json_response(list(
        ok = TRUE,
        raw = list(nrow = nrow(raw), ncol = ncol(raw) - as.integer(".gg_rid" %in% names(raw))),
        final = list(nrow = nrow(final),
                     ncol = ncol(final) - as.integer(".gg_rid" %in% names(final))),
        steps = s$steps,
        code = paste(s$code, collapse = "\n")
      )))
    }

    # 列清单（加工后）：POST 带 prep，返回筛选 / 新增列 / 抽样后的列
    if (path == "/api/columns" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      d <- pv$d
      if (is.null(d) || !nrow(d)) return(json_response(list(ok = TRUE, columns = list())))
      d <- d[, setdiff(names(d), ".gg_rid"), drop = FALSE]
      return(json_response(list(ok = TRUE, columns = column_info(d))))
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

    ## ---- 描述统计（L1）----
    ## 复用 .prepared_full：统计基于「加工 + 手工编辑后」的数据，与画布/预览完全一致
    if (path == "/api/stats/summary" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      res <- tryCatch(
        .ggspec_stats_summary(pv$d,
                              vars = body$vars %||% character(0),
                              groupBy = body$groupBy %||% character(0)),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE,
                                summary = res$summary,
                                vars = as.list(res$vars),
                                groupBy = as.list(res$groupBy),
                                nrow = nrow(pv$d),
                                code = paste(res$code, collapse = "\n"))))
    }

    ## 统计可用列（数值列 / 可分组列）
    if (path == "/api/stats/columns" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      cols <- tryCatch(.ggspec_stats_columns(pv$d), error = function(e) e)
      if (inherits(cols, "error")) return(json_error(conditionMessage(cols), 400))
      return(json_response(list(ok = TRUE, numeric = cols$numeric,
                                groupable = cols$groupable, nrow = nrow(pv$d))))
    }

    ## ---- 显著性标注规划（L3）：给出可选比较对与默认 y 位置 ----
    if (path == "/api/sig/plan" && method == "POST") {
      spec <- body$spec %||% list()
      d <- tryCatch(ggspec_resolve_data(spec, state), error = function(e) e)
      if (inherits(d, "error")) return(json_error(conditionMessage(d), 400))
      plan <- tryCatch(.ggspec_sig_plan(d, spec), error = function(e) e)
      if (inherits(plan, "error")) return(json_error(conditionMessage(plan), 400))
      plan$ok <- isTRUE(plan$ok)
      plan$hasGgsignif <- .ggspec_has_pkg("ggsignif")
      plan$hasGgpubr <- .ggspec_has_pkg("ggpubr")
      plan$hasData <- !is.null(d)
      return(json_response(plan))
    }

    ## ---- 基线特征表（L5）----
    if (path == "/api/table1/columns" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      cols <- tryCatch(.ggspec_table1_columns(pv$d), error = function(e) e)
      if (inherits(cols, "error")) return(json_error(conditionMessage(cols), 400))
      return(json_response(list(ok = TRUE, all = cols$all, groupable = cols$groupable,
                                nrow = nrow(pv$d),
                                stats = .ggspec_t1_stats())))
    }

    if (path == "/api/table1/build" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      res <- tryCatch(
        .ggspec_table1(pv$d,
                       vars = body$vars %||% character(0),
                       by = body$by %||% "",
                       statId = body$statId %||% "mean_sd",
                       addP = isTRUE(body$addP),
                       includeOverall = isTRUE(body$includeOverall),
                       digits = body$digits %||% 1L),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      res$nrow <- nrow(pv$d)
      return(json_response(res))
    }

    ## 基线表导出（docx / xlsx / csv）：落盘后返回下载 URL
    if (path == "/api/table1/export" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      res <- tryCatch(
        .ggspec_table1(pv$d,
                       vars = body$vars %||% character(0),
                       by = body$by %||% "",
                       statId = body$statId %||% "mean_sd",
                       addP = isTRUE(body$addP),
                       includeOverall = isTRUE(body$includeOverall),
                       digits = body$digits %||% 1L),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      ex <- tryCatch(
        .ggspec_table1_export(res, format = body$format %||% "docx", out_dir = state$plot_dir),
        error = function(e) e)
      if (inherits(ex, "error")) return(json_error(conditionMessage(ex), 400))
      return(json_response(list(ok = TRUE,
                                url = paste0("/api/plotfile/", ex$filename),
                                filename = ex$filename)))
    }

    ## ---- 回归分析（L4）----
    if (path == "/api/reg/fit" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      res <- tryCatch(
        .ggspec_reg_fit(pv$d,
                        y = body$y %||% "",
                        xs = body$xs %||% character(0),
                        method = body$method %||% "lm"),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      res$nrow <- nrow(pv$d)
      return(json_response(res))
    }

    ## 回归可用变量
    if (path == "/api/reg/columns" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      cols <- tryCatch(.ggspec_reg_columns(pv$d), error = function(e) e)
      if (inherits(cols, "error")) return(json_error(conditionMessage(cols), 400))
      return(json_response(list(ok = TRUE, numeric = cols$numeric,
                                categorical = cols$categorical,
                                binary = cols$binary, count = cols$count,
                                nrow = nrow(pv$d))))
    }

    ## ---- 统计检验（L2）----
    if (path == "/api/stats/test" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      res <- tryCatch(
        .ggspec_stats_test(pv$d,
                           y = body$y %||% "",
                           x = body$x %||% "",
                           group = body$group %||% "",
                           method = body$method %||% ""),
        error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      res$ok <- TRUE
      res$nrow <- nrow(pv$d)
      return(json_response(res))
    }

    ## 统计方法推荐（按当前数据的列角色）
    if (path == "/api/stats/suggest" && method == "POST") {
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
      if (inherits(pv, "error")) return(json_error(pv$message, 400))
      sug <- tryCatch(.ggspec_stats_suggest(pv$d), error = function(e) e)
      if (inherits(sug, "error")) return(json_error(conditionMessage(sug), 400))
      return(json_response(list(ok = TRUE, methods = sug$methods, roles = sug$roles,
                                nrow = nrow(pv$d))))
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

    if (path == "/api/code/format" && method == "POST") {
      code <- body$code %||% ""
      if (!nzchar(trimws(code))) return(json_error("代码为空", 400))
      if (!requireNamespace("styler", quietly = TRUE)) {
        return(json_error("未安装 styler 包，无法格式化", 400))
      }
      out <- tryCatch(paste(as.character(styler::style_text(code)), collapse = "\n"),
                      error = function(e) e)
      if (inherits(out, "error")) return(json_error(conditionMessage(out), 400))
      return(json_response(list(ok = TRUE, code = out)))
    }
    if (path == "/api/packages/check" && method == "POST") {
      pkgs <- as.character(unlist(body$packages %||% list()))
      pkgs <- pkgs[nzchar(pkgs)]
      ok <- vapply(pkgs, function(p) requireNamespace(p, quietly = TRUE), logical(1))
      return(json_response(list(ok = TRUE,
                                installed = pkgs[ok],
                                missing = pkgs[!ok])))
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

    ## ---- 期刊模板 ----
    if (path == "/api/journal/templates" && method == "GET") {
      return(json_response(list(ok = TRUE, templates = journal_templates())))
    }

    ## ---- 可复现包 ----
    if (path == "/api/bundle" && method == "POST") {
      spec <- body$spec %||% list()
      format <- body$format %||% "png"
      width <- as.integer(body$width %||% 1600); height <- as.integer(body$height %||% 1000)
      dpi <- as.integer(body$dpi %||% 300)
      journal <- body$journal %||% NULL
      res <- tryCatch(ggspec_bundle(spec, state$meta, state, width, height, dpi, format,
                                    journal = journal, project_id = body$projectId %||% NULL,
                                    code = as.character(body$code %||% "")),
                      error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(list(ok = TRUE, url = paste0("/api/plotfile/", res$filename),
                                filename = res$filename, files = res$files)))
    }

    ## ---- 导出 ----
    if (path == "/api/export/check" && method == "POST") {
      spec <- body$spec %||% list()
      format <- body$format %||% "png"
      width <- as.integer(body$width %||% 1600); height <- as.integer(body$height %||% 1000)
      dpi <- as.integer(body$dpi %||% 300)
      journal <- body$journal %||% NULL
      res <- tryCatch(ggspec_export_check(spec, state$meta, state, width, height, dpi, format,
                                          journal = journal,
                                          code = as.character(body$code %||% "")),
                      error = function(e) e)
      if (inherits(res, "error")) return(json_error(conditionMessage(res), 400))
      return(json_response(res))
    }
    if (path == "/api/export" && method == "POST") {
      spec <- body$spec %||% list()
      format <- body$format %||% "png"
      width <- as.integer(body$width %||% 1600); height <- as.integer(body$height %||% 1000)
      dpi <- as.integer(body$dpi %||% 300)
      code <- as.character(body$code %||% "")
      # 有代码（代码图）就从代码导出，否则按 spec 导出
      res <- tryCatch({
        if (nzchar(code)) ggspec_export_code(code, spec, state, width, height, dpi, format)
        else ggspec_export(spec, state$meta, state, width, height, dpi, format)
      }, error = function(e) e)
      if (inherits(res, "error")) {
        msg <- if (inherits(res, "ggplot_error")) res$message else conditionMessage(res)
        return(json_error(msg, 400))
      }
      # 大文件落盘，前端经 /api/plotfile/<fn> 下载
      # 文件名精确到秒，同一秒内连续导出两次会撞名并互相覆盖，故追加 3 位随机后缀
      ext <- switch(format, png = "png", svg = "svg", pdf = "pdf", "png")
      fname <- sprintf("ggplotgui-%s-%03d.%s", format(Sys.time(), "%Y%m%d-%H%M%S"),
                       as.integer(stats::runif(1, 0, 999)), ext)
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
      id <- state$pin_store$add(spec_json, (body$label %||% NULL), (body$project %||% ""))
      return(json_response(list(ok = TRUE, id = id, created = TRUE, pins = state$pin_store$list())))
    }
    # 覆盖更新已有条目（标签保持不变）。
    # 条目已被删除时回退为新建并返回 created = TRUE，避免前端卡在「更新失败」。
    if (path == "/api/pins/update" && method == "POST") {
      spec_json <- tryCatch({
        raw <- trimws(as.character(body$specJson %||% ""))
        if (!nzchar(raw)) return(json_error("缺少绘图规格"))
        jsonlite::fromJSON(raw, simplifyVector = FALSE)
        raw
      }, error = function(e) NULL)
      if (is.null(spec_json)) return(json_error("绘图规格解析失败", 400))
      id <- as.character(body$id %||% "")
      project <- body$project %||% ""
      ok <- isTRUE(state$pin_store$set_spec(id, spec_json))
      created <- FALSE
      if (!ok) {
        id <- state$pin_store$add(spec_json, (body$label %||% NULL), project)
        created <- TRUE
      } else {
        # 缩略图是懒生成并缓存的（见 /api/pins/thumb/）：规格变了必须让它失效，
        # 否则卡片上仍显示旧图。
        unlink(state$pin_store$thumb_path(id))
      }
      return(json_response(list(ok = TRUE, id = id, created = created,
                                pins = state$pin_store$list())))
    }
    if (path == "/api/pins/delete" && method == "POST") {
      state$pin_store$remove(body$id %||% "")
      return(json_response(list(ok = TRUE, pins = state$pin_store$list())))
    }
    if (path == "/api/pins/rename" && method == "POST") {
      id <- as.character(body$id %||% "")
      label <- trimws(as.character(body$label %||% ""))
      if (!nzchar(label)) return(json_error("名称不能为空", 400))
      # 卡片宽度有限，过长名字没有意义；按字符截断（中文一个字算 1）
      if (nchar(label) > 40) label <- substr(label, 1, 40)
      ok <- isTRUE(state$pin_store$rename(id, label))
      if (!ok) return(json_error("图库条目不存在", 404))
      return(json_response(list(ok = TRUE, id = id, label = label,
                                pins = state$pin_store$list())))
    }
    if (path == "/api/pins/save-code" && method == "POST") {
      code <- as.character(body$code %||% "")
      if (!nzchar(trimws(code))) return(json_error("代码为空", 400))
      src <- body$source %||% list()
      prep <- body$prep %||% list()
      # 允许“无数据源”的代码图（代码直接用 mpg/iris 等内置数据）
      has_src <- !identical(as.character(src$type %||% "none"), "none")
      pv <- NULL
      if (has_src) {
        pv <- tryCatch(.prepared_full(src, prep), error = function(e) e)
        if (inherits(pv, "error")) return(json_error(conditionMessage(pv), 400))
      }
      data_meta <- if (has_src) list(mode = "snapshot", source = src, prep = prep)
                   else list(mode = "none", source = src)
      id <- state$pin_store$add_code(
        body$label %||% NULL, code, body$packages %||% list(),
        data_meta, body$renderOpts %||% list(), body$project %||% NULL)
      if (has_src) saveRDS(pv$d, state$pin_store$data_path(id))
      fn <- basename(as.character(body$pngUrl %||% ""))
      if (nzchar(fn)) {
        srcf <- file.path(state$plot_dir, fn)
        if (file.exists(srcf)) file.copy(srcf, state$pin_store$thumb_path(id), overwrite = TRUE)
      }
      # 没有可用预览图时，用代码现场渲染一张作为缩略图
      if (!file.exists(state$pin_store$thumb_path(id))) {
        ro <- body$renderOpts %||% list()
        rr <- tryCatch(ggspec_render_rawcode(
          code, state,
          as.integer(ro$width %||% 900), as.integer(ro$height %||% 560),
          as.integer(ro$dpi %||% 150), png_dir = state$plot_dir),
          error = function(e) NULL)
        if (!is.null(rr) && nzchar(rr$pngUrl %||% "")) {
          file.copy(file.path(state$plot_dir, basename(rr$pngUrl)),
                    state$pin_store$thumb_path(id), overwrite = TRUE)
        }
      }
      return(json_response(list(ok = TRUE, id = id, pins = state$pin_store$list())))
    }
    if (path == "/api/pins/open" && method == "POST") {
      id <- as.character(body$id %||% "")
      full <- state$pin_store$list_full()
      it <- full[[id]]
      if (is.null(it)) return(json_error("图库条目不存在", 404))
      if (!identical(as.character(it$type %||% "spec"), "code")) {
        return(json_response(list(ok = TRUE, type = "spec", specJson = it$specJson)))
      }
      dp <- state$pin_store$data_path(id)
      if (file.exists(dp)) state$raw_data <- tryCatch(readRDS(dp), error = function(e) state$raw_data)
      # 旧条目缺缩略图：按保存的代码补渲染一张
      if (!file.exists(state$pin_store$thumb_path(id))) {
        ro <- it$renderOpts %||% list()
        rr <- tryCatch(ggspec_render_rawcode(
          as.character((it$code %||% list())$text %||% ""), state,
          as.integer(ro$width %||% 900), as.integer(ro$height %||% 560),
          as.integer(ro$dpi %||% 150), png_dir = state$plot_dir),
          error = function(e) NULL)
        if (!is.null(rr) && nzchar(rr$pngUrl %||% "")) {
          file.copy(file.path(state$plot_dir, basename(rr$pngUrl)),
                    state$pin_store$thumb_path(id), overwrite = TRUE)
        }
      }
      thumb_ok <- file.exists(state$pin_store$thumb_path(id))
      return(json_response(list(
        ok = TRUE, type = "code",
        code = as.character((it$code %||% list())$text %||% ""),
        renderOpts = it$renderOpts %||% list(),
        pngUrl = if (thumb_ok) paste0("/api/pins/thumb/", id, ".png") else ""
      )))
    }
    if (startsWith(path, "/api/pins/thumb/") && method == "GET") {
      fn <- gsub("[^A-Za-z0-9_.-]", "", basename(path))
      id <- sub("\\.png$", "", fn)
      full <- file.path(dirname(state$pin_store$thumb_path("x")), paste0(id, ".png"))
      # 缩略图懒生成：spec 图按 spec 渲染，代码图按代码渲染，生成后缓存
      if (!file.exists(full)) {
        it <- tryCatch(state$pin_store$list_full()[[id]], error = function(e) NULL)
        if (!is.null(it)) {
          if (identical(as.character(it$type %||% "spec"), "code")) {
            dp <- state$pin_store$data_path(id)
            if (file.exists(dp)) state$raw_data <- tryCatch(readRDS(dp), error = function(e) state$raw_data)
            ro <- it$renderOpts %||% list()
            rr <- tryCatch(ggspec_render_rawcode(
              as.character((it$code %||% list())$text %||% ""), state,
              as.integer(ro$width %||% 900), as.integer(ro$height %||% 560),
              as.integer(ro$dpi %||% 150), png_dir = state$plot_dir),
              error = function(e) NULL)
            if (!is.null(rr) && nzchar(rr$pngUrl %||% "")) {
              file.copy(file.path(state$plot_dir, basename(rr$pngUrl)), full, overwrite = TRUE)
            }
          } else if (nzchar(as.character(it$specJson %||% ""))) {
            sp <- tryCatch(jsonlite::fromJSON(as.character(it$specJson), simplifyVector = FALSE),
                           error = function(e) NULL)
            if (!is.null(sp)) {
              gen <- tryCatch(ggspec_pipeline(sp, state$meta, state), error = function(e) NULL)
              if (!is.null(gen)) {
                rf <- tryCatch(ggspec_render_file(gen$eval_code, gen$env_list,
                                                  width = 480, height = 300, dpi = 96),
                               error = function(e) NULL)
                if (!is.null(rf)) {
                  file.copy(rf$path, full, overwrite = TRUE)
                  unlink(rf$path)
                }
              }
            }
          }
        }
      }
      if (!file.exists(full)) return(list(status = 404L, headers = list("Content-Type" = "text/plain"), body = "not found"))
      return(list(status = 200L,
                  headers = list("Content-Type" = "image/png", "Cache-Control" = "no-store"),
                  body = readBin(full, "raw", file.info(full)$size)))
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
                 error = function(e) {
                   # 把出错调用打到 stderr，便于定位（用户只看到简短消息）
                   called <- tryCatch(paste(deparse(conditionCall(e)), collapse = " "),
                                      error = function(e2) "")
                   if (nzchar(called)) cat("[api-error]", req$PATH_INFO, "::", called, "\n", file = stderr())
                   json_error(paste0("服务器内部错误: ", conditionMessage(e)), 500)
                 })
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
