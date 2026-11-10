# Glyph - 远程数据库（P1）：连接 / 浏览 / 只读预览 / 导入
# 安全约定：
#   * 连接对象只存在后端内存，前端只拿 connId；密码不落盘、不回传；
#   * 连接后按驱动设置会话只读（成败记录在连接上，测试连接时会提示）；
#   * 自定义 SQL 先剥掉字符串字面量再查写操作关键字（挡 WITH...INSERT / SELECT INTO
#     这类以 SELECT/WITH 开头的变体），只允许单条 SELECT/WITH；
#   * 关键字守卫是最后一道防线：若会话只读设置失败（如部分 ODBC 后端），
#     前端会在测试连接时收到 readOnly=FALSE 与提示，自定义 SQL 仍可用但仅受关键字守卫保护；
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
  # 会话级只读：按驱动选正确的语句（此前对 ODBC 发的是 PG 语法，必失败且被静默吞掉）
  list(con = con, readOnly = .db_set_readonly(con, driver))
}

# 尽量设只读，返回是否成功。失败不阻断连接（表浏览是纯读的），
# 但自定义 SQL 的写风险会相应升高 —— 调用方负责把该状态透出给前端。
.db_set_readonly <- function(con, driver) {
  stmts <- switch(driver,
    mysql    = "SET SESSION TRANSACTION READ ONLY",
    postgres = "SET default_transaction_read_only = on",
    # ODBC 后端方言未知：PG 语法不行再试 MySQL 语法
    c("SET default_transaction_read_only = on", "SET SESSION TRANSACTION READ ONLY"))
  for (s in stmts) {
    ok <- tryCatch({ DBI::dbExecute(con, s); TRUE }, error = function(e) FALSE)
    if (ok) return(TRUE)
  }
  FALSE
}

db_test_connection <- function(opts) {
  t0 <- Sys.time()
  r <- tryCatch(.db_connect_raw(opts), error = function(e) e)
  if (inherits(r, "error")) stop(.db_sanitize(conditionMessage(r), opts))
  on.exit(try(DBI::dbDisconnect(r$con), silent = TRUE), add = TRUE)
  ver <- tryCatch(as.character(DBI::dbGetQuery(r$con, "SELECT version() AS v")$v[1]),
                  error = function(e) NA_character_)
  if (is.na(ver)) ver <- tryCatch(paste(DBI::dbGetInfo(r$con)$db.version %||% ""), error = function(e) "")
  list(ok = TRUE, version = ver, readOnly = r$readOnly,
       warning = if (!r$readOnly) "未能启用会话只读，自定义 SQL 仅受关键字守卫保护" else NULL,
       elapsedMs = round(as.numeric(difftime(Sys.time(), t0, units = "secs")) * 1000))
}

db_connect <- function(opts) {
  r <- tryCatch(.db_connect_raw(opts), error = function(e) e)
  if (inherits(r, "error")) stop(.db_sanitize(conditionMessage(r), opts))
  # 同参数重复连接：先断旧条目（连接只在内存里堆积，长会话会越积越多）
  driver <- as.character(opts$driver %||% "")
  host <- as.character(opts$host %||% "")
  dbname <- as.character(opts$dbname %||% "")
  user <- as.character(opts$user %||% "")
  for (cid in names(DB_STATE$conns)) {
    c0 <- DB_STATE$conns[[cid]]
    if (identical(c0$driver, driver) && identical(c0$host, host) &&
        identical(c0$dbname, dbname) && identical(c0$user, user)) {
      try(DBI::dbDisconnect(c0$con), silent = TRUE)
      DB_STATE$conns[[cid]] <- NULL
    }
  }
  # 数量上限：超出时断开最早建立的（list 保持插入序，names()[1] 即最旧）
  while (length(DB_STATE$conns) >= 8) {
    old_id <- names(DB_STATE$conns)[1]
    try(DBI::dbDisconnect(DB_STATE$conns[[old_id]]$con), silent = TRUE)
    DB_STATE$conns[[old_id]] <- NULL
  }
  id <- paste0("db-", sprintf("%08x", as.integer(stats::runif(1, 1, 2^31 - 1))))
  info <- tryCatch(DBI::dbGetInfo(r$con), error = function(e) list())
  DB_STATE$conns[[id]] <- list(
    id = id, con = r$con, readOnly = r$readOnly,
    driver = driver, host = host, dbname = dbname, user = user,
    label = as.character(opts$label %||% ""),
    opened = Sys.time()
  )
  list(connId = id, driver = driver,
       readOnly = r$readOnly,
       version = as.character(info$db.version %||% ""),
       host = host, dbname = dbname)
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
    # information_schema.tables 没有 table_rows 列（那是 MySQL 的非标准列，PG 上必然报错）；
    # PG 的行数估计在 pg_class.reltuples —— 直接查系统目录，表和视图一并返回
    q <- paste0(
      "SELECT n.nspname AS schema, c.relname AS name, ",
      "CASE c.relkind WHEN 'r' THEN 'BASE TABLE' WHEN 'p' THEN 'BASE TABLE' ",
      "WHEN 'v' THEN 'VIEW' WHEN 'm' THEN 'VIEW' ELSE 'OTHER' END AS type, ",
      "GREATEST(c.reltuples::bigint, 0) AS rows ",
      "FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace ",
      "WHERE n.nspname NOT IN ('pg_catalog','information_schema') ",
      "AND c.relkind IN ('r','p','v','m') ",
      "ORDER BY n.nspname, c.relname")
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
  # 先剥掉字符串字面量与引号标识符再查关键字，避免 WHERE note = '请 update 记录' 这类误报
  stripped <- gsub("'(?:[^']|'')*'", "''", s, perl = TRUE)   # 单引号字符串（含 '' 转义）
  stripped <- gsub('"[^"]*"', '""', stripped)                # 双引号标识符
  stripped <- gsub("`[^`]*`", "``", stripped)                # MySQL 反引号
  # 名称级守卫之外再挡写操作：WITH ... INSERT / SELECT ... INTO 这类以 SELECT/WITH
  # 开头的变体也必须拦下；setval/set_config 是能在 SELECT 里调用的写函数。
  # \b 保证 update_time 之类的列名不误伤（下划线是单词字符）；
  # 不拦 replace() 等读函数 —— REPLACE INTO 语句以 REPLACE 开头，已被前缀检查拒绝。
  if (grepl(paste0("\\b(into|insert|update|delete|merge|truncate|create|alter|drop|",
                   "grant|revoke|copy|call|exec|execute|do|set|reset|lock|",
                   "vacuum|analyze|analyse|setval|set_config)\\b"),
            stripped, ignore.case = TRUE)) {
    stop("只读查询：不允许包含写操作或 DDL 关键字")
  }
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
       readOnly = c$readOnly %||% TRUE,
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
                 # 旧实现只存查询长度（同长度的不同查询"哈希"相同，纯误导）；
                 # 改存长度 + 去空白后的前 60 字符，足以辨认来源查询
                 sqlHash = if (nzchar(sql %||% ""))
                   substr(paste0("q-", nchar(sql), ":", gsub("\\s+", " ", trimws(sql))), 1, 80)
                 else NULL,
                 importedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"))
  id <- DataStore$add(df, label %||% table_name %||% "查询结果", origin = origin)
  list(id = id, info = DataStore$info(id), columns = import_columns(df))
}
