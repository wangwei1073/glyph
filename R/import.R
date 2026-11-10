# Glyph - 数据导入（P0）：统一会话 + 文件解析预览 + SQLite
# 设计：
#   * 上传一次，后续预览/建表/导入都复用同一个 token（不在每次预览时重传 base64）；
#   * 预览只读前 N 行（默认 50），提交时才整表读入；
#   * 来源信息（文件/数据库、表名、时间）写入 DataStore origin，供图注/可复现包使用。

IMPORT_STATE <- new.env(parent = emptyenv())
IMPORT_STATE$sessions <- list()

DATA_DRIVER_PKGS <- c("RSQLite", "readxl", "haven", "arrow",
                      "RPostgres", "RMariaDB", "odbc")

.import_token <- function() {
  paste0("imp-", sprintf("%08x", as.integer(stats::runif(1, 1, 2^31 - 1))),
         sprintf("%04x", as.integer(stats::runif(1, 1, 65535))))
}

.import_prune <- function() {
  keep <- list()
  now <- Sys.time()
  for (s in IMPORT_STATE$sessions) {
    if (as.numeric(difftime(now, s$created, units = "hours")) < 4) keep[[length(keep) + 1]] <- s
  }
  IMPORT_STATE$sessions <- keep
}

import_upload <- function(name, ext, data_base64, dir = NULL) {
  name <- as.character(name %||% "upload.csv")
  ext <- tolower(sub("^\\.", "", ext %||% tools::file_ext(name)))
  if (!nzchar(ext)) stop("无法识别文件类型")
  allowed <- c("csv", "tsv", "txt", "xlsx", "xls", "rds", "rdata", "rda", "json", "db", "sqlite", "sqlite3")
  if (!ext %in% allowed) stop(sprintf("暂不支持 .%s 文件", ext))
  raw <- tryCatch(jsonlite::base64_dec(data_base64), error = function(e) NULL)
  if (is.null(raw) || !length(raw)) stop("文件内容为空或 base64 解码失败")
  if (length(raw) > 100 * 1024^2) stop("文件超过 100 MB，请先拆分")
  d <- dir %||% file.path(tempdir(), "glyph-imports")
  dir.create(d, showWarnings = FALSE, recursive = TRUE)
  token <- .import_token()
  path <- file.path(d, paste0(token, ".", ext))
  writeBin(raw, path)
  .import_prune()
  IMPORT_STATE$sessions[[token]] <- list(
    token = token, name = name, ext = ext, path = path,
    size = length(raw), created = Sys.time()
  )
  list(token = token, name = name, ext = ext, size = length(raw))
}

import_session <- function(token) {
  s <- IMPORT_STATE$sessions[[as.character(token)[1]]]
  if (is.null(s)) stop("导入会话不存在或已过期，请重新选择文件")
  s
}

import_type <- function(x) {
  if (inherits(x, "Date")) return("date")
  if (inherits(x, "POSIXct") || inherits(x, "POSIXlt")) return("dttm")
  if (is.logical(x)) return("lgl")
  if (is.factor(x)) return("fct")
  if (is.numeric(x)) return("num")
  "chr"
}

import_columns <- function(df) {
  lapply(names(df), function(nm) list(name = nm, type = import_type(df[[nm]])))
}

import_rows <- function(df, n = 50) {
  df <- utils::head(df, n)
  lapply(seq_len(nrow(df)), function(i) {
    vals <- lapply(df, function(col) {
      v <- col[i]
      if (inherits(v, "Date")) return(format(v, "%Y-%m-%d"))
      if (inherits(v, "POSIXct")) return(format(v, "%Y-%m-%d %H:%M:%S"))
      if (is.factor(v)) return(as.character(v))
      # NA 保持 NA（JSON 里变 null，前端显示为空）；isTRUE 会把 NA 静默变成 FALSE
      if (is.logical(v)) return(if (is.na(v)) NA else v)
      v
    })
    stats::setNames(vals, names(df))
  })
}

.import_delim <- function(opts) {
  d <- as.character(opts$delim %||% "auto")[1]
  if (identical(d, "auto")) return(NULL)
  switch(d,
    comma = ",", tab = "\t", semicolon = ";", space = " ",
    d)
}

.import_encoding <- function(opts) {
  e <- as.character(opts$encoding %||% "UTF-8")[1]
  if (identical(toupper(e), "UTF-8")) "UTF-8" else e
}

import_parse_file <- function(session, opts = list(), n_max = NULL) {
  ext <- session$ext
  path <- session$path
  header <- isTRUE(opts$header %||% TRUE)
  skip <- max(0L, as.integer(opts$skip %||% 0))
  na <- as.character(opts$na %||% c("", "NA"))
  if (ext %in% c("csv", "tsv", "txt")) {
    delim <- .import_delim(opts)
    if (is.null(delim) && identical(ext, "tsv")) delim <- "\t"
    args <- list(file = path, delim = delim,
                 locale = readr::locale(encoding = .import_encoding(opts)),
                 col_names = header, skip = skip, na = na,
                 show_col_types = FALSE, progress = FALSE)
    if (!is.null(n_max)) args$n_max <- n_max
    df <- do.call(readr::read_delim, args)
  } else if (ext %in% c("xlsx", "xls")) {
    sheet <- opts$sheet %||% 1
    range <- opts$range %||% NULL
    args <- list(path = path, sheet = sheet, col_names = header, skip = skip,
                 na = na, .name_repair = "unique")
    if (!is.null(range) && nzchar(as.character(range))) args$range <- as.character(range)
    if (!is.null(n_max)) args$n_max <- n_max
    df <- do.call(readxl::read_excel, args)
    df <- as.data.frame(df, stringsAsFactors = FALSE)
  } else if (ext == "rds") {
    obj <- readRDS(path)
    df <- as.data.frame(obj, stringsAsFactors = FALSE)
    if (!is.null(n_max)) df <- utils::head(df, n_max)
  } else if (ext %in% c("rdata", "rda")) {
    e <- new.env()
    load(path, envir = e)
    objs <- ls(e)
    dfs <- Filter(function(nm) is.data.frame(e[[nm]]), objs)
    if (!length(dfs)) stop("RData 里没有 data.frame 对象")
    df <- e[[dfs[1]]]
    if (!is.null(n_max)) df <- utils::head(df, n_max)
  } else if (ext == "json") {
    obj <- jsonlite::fromJSON(path, simplifyVector = TRUE)
    df <- if (is.data.frame(obj)) obj else as.data.frame(obj, stringsAsFactors = FALSE)
    if (!is.null(n_max)) df <- utils::head(df, n_max)
  } else {
    stop(sprintf("暂不支持 .%s 文件", ext))
  }
  if (is.null(dim(df)) || !is.data.frame(df)) stop("文件内容不是表格")
  df
}

.import_col_stats <- function(x) {
  out <- list(missing = as.integer(sum(is.na(x))),
              unique = as.integer(length(unique(x[!is.na(x)]))))
  if (inherits(x, "Date")) {
    if (any(!is.na(x))) {
      out$min <- format(min(x, na.rm = TRUE), "%Y-%m-%d")
      out$max <- format(max(x, na.rm = TRUE), "%Y-%m-%d")
    }
  } else if (is.numeric(x)) {
    if (any(is.finite(x))) {
      out$min <- suppressWarnings(min(x, na.rm = TRUE))
      out$max <- suppressWarnings(max(x, na.rm = TRUE))
    }
  } else {
    tab <- sort(table(x), decreasing = TRUE)
    if (length(tab)) out$top <- paste(utils::head(names(tab), 3), collapse = ", ")
  }
  out
}

.import_apply_types <- function(df, col_types) {
  if (is.null(col_types) || !length(col_types)) return(df)
  for (nm in names(col_types)) {
    if (!nm %in% names(df)) next
    type <- as.character(col_types[[nm]])[1]
    x <- df[[nm]]
    df[[nm]] <- switch(type,
      num  = suppressWarnings(as.numeric(x)),
      chr  = as.character(x),
      fct  = as.factor(x),
      lgl  = suppressWarnings(as.logical(x)),
      date = suppressWarnings(as.Date(x)),
      x)
  }
  df
}

.import_text_rows <- function(path, skip = 0L, header = TRUE) {
  n <- tryCatch(length(readLines(path, warn = FALSE)), error = function(e) NA_integer_)
  if (is.na(n)) return(NA_integer_)
  max(0L, n - as.integer(skip) - if (isTRUE(header)) 1L else 0L)
}

import_preview <- function(token, opts = list(), limit = 50) {
  s <- import_session(token)
  if (s$ext %in% c("db", "sqlite", "sqlite3")) stop("数据库文件请使用表列表/表预览接口")
  df <- import_parse_file(s, opts, n_max = as.integer(limit %||% 50))
  df <- .import_apply_types(df, opts$colTypes)
  total <- if (s$ext %in% c("csv", "tsv", "txt")) {
    .import_text_rows(s$path, opts$skip %||% 0, isTRUE(opts$header %||% TRUE))
  } else NA_integer_
  raw <- NULL
  if (s$ext %in% c("csv", "tsv", "txt")) {
    raw <- tryCatch(paste(utils::head(readLines(s$path, warn = FALSE, n = 25), 25), collapse = "\n"),
                    error = function(e) NULL)
  }
  list(token = s$token, name = s$name, ext = s$ext,
       columns = import_columns(df), rows = import_rows(df, nrow(df)),
       stats = lapply(df, .import_col_stats), rawText = raw,
       totalRows = total,
       previewRows = nrow(df), truncated = nrow(df) >= as.integer(limit %||% 50))
}

import_commit_file <- function(token, opts = list(), label = NULL) {
  s <- import_session(token)
  df <- import_parse_file(s, opts, n_max = NULL)
  df <- .import_apply_types(df, opts$colTypes)
  df <- ggspec_with_rid(df)
  origin <- list(kind = "file", file = s$name, ext = s$ext,
                 importedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"))
  id <- DataStore$add(df, label %||% tools::file_path_sans_ext(s$name), origin = origin)
  list(id = id, info = DataStore$info(id), columns = import_columns(df))
}

## ---- SQLite ---------------------------------------------------------------
.import_sqlite_con <- function(s) {
  if (!requireNamespace("RSQLite", quietly = TRUE)) {
    stop("SQLite 驱动未安装：请先安装 RSQLite")
  }
  DBI::dbConnect(RSQLite::SQLite(), s$path)
}

.import_sqlite_tables <- function(token) {
  s <- import_session(token)
  con <- .import_sqlite_con(s)
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  tabs <- DBI::dbListTables(con)
  out <- lapply(tabs, function(tb) {
    cnt <- tryCatch(DBI::dbGetQuery(con, sprintf('SELECT COUNT(*) AS n FROM "%s"', gsub('"', '""', tb)))$n,
                    error = function(e) NA_integer_)
    list(name = tb, rows = as.integer(cnt))
  })
  out
}

.import_sqlite_preview <- function(token, table, limit = 100) {
  s <- import_session(token)
  con <- .import_sqlite_con(s)
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  tb <- as.character(table)[1]
  if (!tb %in% DBI::dbListTables(con)) stop(sprintf("表不存在：%s", tb))
  df <- DBI::dbGetQuery(con, sprintf('SELECT * FROM "%s" LIMIT %d',
                                     gsub('"', '""', tb), as.integer(limit %||% 100)))
  list(token = s$token, table = tb, columns = import_columns(df),
       rows = import_rows(df, nrow(df)), stats = lapply(df, .import_col_stats),
       previewRows = nrow(df))
}

import_commit_sqlite <- function(token, table, label = NULL, limit = 1000000L) {
  s <- import_session(token)
  con <- .import_sqlite_con(s)
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  tb <- as.character(table)[1]
  if (!tb %in% DBI::dbListTables(con)) stop(sprintf("表不存在：%s", tb))
  df <- DBI::dbGetQuery(con, sprintf('SELECT * FROM "%s" LIMIT %d',
                                     gsub('"', '""', tb), as.integer(limit)))
  df <- ggspec_with_rid(df)
  origin <- list(kind = "sqlite", file = s$name, table = tb,
                 importedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"))
  id <- DataStore$add(df, label %||% tb, origin = origin)
  list(id = id, info = DataStore$info(id), columns = import_columns(df))
}

import_drivers <- function() {
  lapply(DATA_DRIVER_PKGS, function(p) {
    list(pkg = p, installed = requireNamespace(p, quietly = TRUE),
         version = if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else NULL)
  })
}
