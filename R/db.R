# Glyph - 远程数据库（P1）：连接 / 浏览 / 只读预览 / 导入
# 安全约定：
#   * 连接对象只存在后端内存，前端只拿 connId；密码不落盘、不回传；
#   * 连接后尽量设置只读事务；自定义 SQL 只允许单条 SELECT/WITH；
#   * 预览默认 LIMIT 100，导入上限 100 万行。

DB_STATE <- new.env(parent = emptyenv())
DB_STATE$conns <- list()

DB_DRIVERS <- list(
  postgres = list(pkg = "RPostgres", label = "PostgreSQL", port = 5432),
  mysql    = list(pkg = "RMariaDB",  label = "MySQL / MariaDB", port = 3306),
  odbc     = list(pkg = "odbc",      label = "ODBC", port = NULL)
)

db_driver_catalog <- function() {
  lapply(names(DB_DRIVERS), function(id) {
    d <- DB_DRIVERS[[id]]
    list(id = id, label = d$label, pkg = d$pkg, port = d$port,
         installed = requireNamespace(d$pkg, quietly = TRUE),
         version = if (requireNamespace(d$pkg, quietly = TRUE)) as.character(utils::packageVersion(d$pkg)) else NULL)
  })
}

.db_sanitize <- function(msg, opts) {
  msg <- as.character(msg)
  pwd <- as.character(opts$password %||% "")
  # 短密码（1-3 字符）做全局替换会把错误信息里的数字/字母也糟蹋掉；
  # 真实错误信息通常不含密码，只有 >=4 位才做掩码
  if (nzchar(pwd) && nchar(pwd) >= 4) msg <- gsub(pwd, "******", msg, fixed = TRUE)
  msg
}

.db_connect_raw <- function(opts) {
  driver <- as.character(opts$driver %||% "postgres")[1]
  if (!driver %in% names(DB_DRIVERS)) stop("未知驱动：" , driver)
  pkg <- DB_DRIVERS[[driver]]$pkg
  if (!requireNamespace(pkg, quietly = TRUE)) stop(sprintf("%s 驱动未安装：请先安装 %s", driver, pkg))
  pwd <- as.character(opts$password %||% "")
  if (driver == "postgres") {
    args <- list(drv = RPostgres::Postgres(),
                 host = as.character(opts$host %||% "127.0.0.1"),
                 port = as.integer(opts$port %||% 5432),
                 dbname = as.character(opts$dbname %||% ""),
                 user = as.character(opts$user %||% ""),
                 password = pwd,
                 sslmode = as.character(opts$sslmode %||% "prefer"))
    con <- do.call(DBI::dbConnect, args)
  } else if (driver == "mysql") {
    con <- DBI::dbConnect(RMariaDB::MariaDB(),
                          host = as.character(opts$host %||% "127.0.0.1"),
                          port = as.integer(opts$port %||% 3306),
                          dbname = as.character(opts$dbname %||% ""),
                          user = as.character(opts$user %||% ""),
                          password = pwd)
  } else {
    dsn <- as.character(opts$dsn %||% "")
    if (nzchar(dsn)) {
      con <- DBI::dbConnect(odbc::odbc(), dsn = dsn,
                            uid = as.character(opts$user %||% ""), pwd = pwd)
    } else {
      con <- DBI::dbConnect(odbc::odbc(),
                            driver = as.character(opts$driverName %||% ""),
                            server = as.character(opts$host %||% ""),
                            database = as.character(opts$dbname %||% ""),
                            uid = as.character(opts$user %||% ""),
                            pwd = pwd)
    }
  }
  # 尽量设只读（失败不阻断，SQL 守卫仍生效）
  try(DBI::dbExecute(con, if (driver == "mysql")
    "SET SESSION TRANSACTION READ ONLY" else "SET default_transaction_read_only = on"), silent = TRUE)
  con
}

db_test_connection <- function(opts) {
  t0 <- Sys.time()
  con <- tryCatch(.db_connect_raw(opts), error = function(e) e)
  if (inherits(con, "error")) stop(.db_sanitize(conditionMessage(con), opts))
  on.exit(try(DBI::dbDisconnect(con), silent = TRUE), add = TRUE)
  ver <- tryCatch(as.character(DBI::dbGetQuery(con, "SELECT version() AS v")$v[1]),
                  error = function(e) NA_character_)
  if (is.na(ver)) ver <- tryCatch(paste(DBI::dbGetInfo(con)$db.version %||% ""), error = function(e) "")
  list(ok = TRUE, version = ver,
       elapsedMs = round(as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000))
}

db_connect <- function(opts) {
  con <- tryCatch(.db_connect_raw(opts), error = function(e) e)
  if (inherits(con, "error")) stop(.db_sanitize(conditionMessage(con), opts))
  id <- paste0("db-", sprintf("%08x", as.integer(stats::runif(1, 1, 2^31 - 1))))
  info <- tryCatch(DBI::dbGetInfo(con), error = function(e) list())
  DB_STATE$conns[[id]] <- list(
    id = id, con = con,
    driver = as.character(opts$driver %||% ""),
    host = as.character(opts$host %||% ""),
    dbname = as.character(opts$dbname %||% ""),
    user = as.character(opts$user %||% ""),
    label = as.character(opts$label %||% ""),
    opened = Sys.time()
  )
  list(connId = id, driver = DB_STATE$conns[[id]]$driver,
       version = as.character(info$db.version %||% ""),
       host = DB_STATE$conns[[id]]$host, dbname = DB_STATE$conns[[id]]$dbname)
}

.db_conn <- function(conn_id) {
  c <- DB_STATE$conns[[as.character(conn_id)[1]]]
  if (is.null(c)) stop("连接不存在或已断开")
  c
}

db_disconnect <- function(conn_id) {
  c <- DB_STATE$conns[[as.character(conn_id)[1]]]
  if (!is.null(c)) {
    try(DBI::dbDisconnect(c$con), silent = TRUE)
    DB_STATE$conns[[as.character(conn_id)[1]]] <- NULL
  }
  invisible(TRUE)
}

db_connections <- function() {
  lapply(DB_STATE$conns, function(c) {
    list(connId = c$id, driver = c$driver, host = c$host, dbname = c$dbname,
         label = c$label, opened = format(c$opened, "%Y-%m-%d %H:%M:%S"))
  })
}

.db_ident <- function(driver, x) {
  x <- as.character(x)[1]
  if (driver == "mysql") paste0("`", gsub("`", "``", x), "`")
  else paste0('"', gsub('"', '""', x), '"')
}

.db_table_ref <- function(driver, schema, table) {
  if (nzchar(schema %||% "")) paste(.db_ident(driver, schema), .db_ident(driver, table), sep = ".")
  else .db_ident(driver, table)
}

db_tables <- function(conn_id) {
  c <- .db_conn(conn_id)
  driver <- c$driver
  if (driver == "postgres") {
    q <- paste0("SELECT table_schema AS schema, table_name AS name, table_type AS type, ",
                "COALESCE(table_rows, 0) AS rows FROM information_schema.tables ",
                "WHERE table_schema NOT IN ('pg_catalog','information_schema') ",
                "ORDER BY table_schema, table_name")
  } else if (driver == "mysql") {
    q <- paste0("SELECT table_schema AS schema, table_name AS name, table_type AS type, ",
                "COALESCE(table_rows, 0) AS rows FROM information_schema.tables ",
                "WHERE table_schema = DATABASE() ORDER BY table_name")
  } else {
    tabs <- tryCatch(DBI::dbListTables(c$con), error = function(e) character(0))
    return(lapply(tabs, function(t) list(schema = "", name = t, type = "TABLE", rows = NULL)))
  }
  df <- tryCatch(DBI::dbGetQuery(c$con, q), error = function(e) e)
  if (inherits(df, "error")) stop(.db_sanitize(conditionMessage(df), list()))
  lapply(seq_len(nrow(df)), function(i) {
    list(schema = as.character(df$schema[i]), name = as.character(df$name[i]),
         type = as.character(df$type[i]), rows = as.numeric(df$rows[i]))
  })
}

.db_clean_sql <- function(sql) {
  s <- trimws(as.character(sql)[1])
  s <- sub(";\\s*$", "", s)
  if (!nzchar(s)) stop("SQL 为空")
  if (grepl(";", s, fixed = TRUE)) stop("只允许单条 SELECT 查询（不要包含分号）")
  if (!grepl("^\\s*(select|with)\\b", s, ignore.case = TRUE)) stop("只允许 SELECT / WITH 查询")
  s
}

db_preview <- function(conn_id, schema = "", table = "", sql = "", limit = 100) {
  c <- .db_conn(conn_id)
  limit <- max(1L, min(as.integer(limit %||% 100), 1000L))
  if (nzchar(sql %||% "")) {
    s <- .db_clean_sql(sql)
    q <- sprintf("SELECT * FROM (%s) glyph_sub LIMIT %d", s, limit)
  } else {
    if (!nzchar(table %||% "")) stop("缺少表名或 SQL")
    q <- sprintf("SELECT * FROM %s LIMIT %d",
                 .db_table_ref(c$driver, schema, table), limit)
  }
  df <- tryCatch(DBI::dbGetQuery(c$con, q), error = function(e) e)
  if (inherits(df, "error")) stop(.db_sanitize(conditionMessage(df), list()))
  list(columns = import_columns(df), rows = import_rows(df, nrow(df)),
       stats = lapply(df, .import_col_stats), previewRows = nrow(df),
       sql = if (nzchar(sql %||% "")) sql else q)
}

db_import <- function(conn_id, schema = "", table = "", sql = "", label = NULL, limit = 1000000L) {
  c <- .db_conn(conn_id)
  limit <- max(1L, min(as.integer(limit %||% 1000000L), 1000000L))
  if (nzchar(sql %||% "")) {
    s <- .db_clean_sql(sql)
    q <- sprintf("SELECT * FROM (%s) glyph_sub LIMIT %d", s, limit)
    table_name <- ""
  } else {
    if (!nzchar(table %||% "")) stop("缺少表名或 SQL")
    q <- sprintf("SELECT * FROM %s LIMIT %d",
                 .db_table_ref(c$driver, schema, table), limit)
    table_name <- as.character(table)
  }
  df <- tryCatch(DBI::dbGetQuery(c$con, q), error = function(e) e)
  if (inherits(df, "error")) stop(.db_sanitize(conditionMessage(df), list()))
  df <- ggspec_with_rid(df)
  origin <- list(kind = "db", driver = c$driver, host = c$host, database = c$dbname,
                 schema = as.character(schema %||% ""), table = table_name,
                 sqlHash = if (nzchar(sql %||% "")) substr(paste0("q-", nchar(sql)), 1, 80) else NULL,
                 importedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"))
  id <- DataStore$add(df, label %||% table_name %||% "查询结果", origin = origin)
  list(id = id, info = DataStore$info(id), columns = import_columns(df))
}
