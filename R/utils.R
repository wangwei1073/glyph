# Glyph - 工具函数

`%||%` <- function(a, b) if (is.null(a)) b else a

glog <- function(...) {
  msg <- paste0(...)
  cat(format(Sys.time(), "[%H:%M:%OS3] "), msg, "\n", sep = "")
}

## JSON 标量 -> R 代码字面量 ---------------------------------------------------
## 约定：
##   list(expr = "raw R code")  -> 原样输出（R 表达式模式）
##   "text"                     -> 带引号字符串
##   数字 / 逻辑                -> 字面量
##   NULL                       -> NULL
is_expr_spec <- function(x) is.list(x) && !is.null(x$expr)

# 前端颜色控件偶尔会给出 CSS 写法 rgb(r,g,b)（甚至带脏尾巴），
# 转成 R 认识的 #RRGGBB；不是这种格式则原样返回 NULL
.css_color_to_hex <- function(s) {
  if (length(s) != 1 || is.na(s)) return(NULL)
  m <- regmatches(s, regexec("^rgba?\\(\\s*([0-9]{1,3})\\s*,\\s*([0-9]{1,3})\\s*,\\s*([0-9]{1,3})",
                             s, ignore.case = TRUE))[[1]]
  if (length(m) < 4) return(NULL)
  v <- suppressWarnings(as.numeric(m[2:4]))
  if (any(is.na(v)) || any(v < 0 | v > 255)) return(NULL)
  grDevices::rgb(v[1], v[2], v[3], maxColorValue = 255)
}
r_literal <- function(x) {
  if (is.null(x)) return("NULL")
  if (is_expr_spec(x)) return(enc2utf8(as.character(x$expr)))
  if (is.list(x) && !is.null(x$value) && length(x) == 1) return(r_literal(x$value))
  if (is.logical(x)) return(if (x) "TRUE" else "FALSE")
  if (is.numeric(x)) {
    if (is.nan(x) || is.na(x)) return("NA")
    out <- format(x, digits = 15, trim = TRUE, scientific = FALSE)
    return(as.character(out))
  }
  if (is.character(x) || is.factor(x)) {
    s <- as.character(x)
    hex <- .css_color_to_hex(s)
    return(r_string(if (is.null(hex)) s else hex))
  }
  if (is.list(x) && !is.null(x$map)) return(r_string(x$map))  # 防御
  # 数组（jsonlite simplifyVector=FALSE 时为 list）
  if (is.list(x)) {
    if (!length(x)) return("NULL")
    parts <- vapply(x, r_literal, character(1))
    return(paste0("c(", paste(parts, collapse = ", "), ")"))
  }
  r_string(as.character(x))
}

r_string <- function(s) {
  s <- enc2utf8(as.character(s))
  if (length(s) == 1 && is.na(s)) return("NA")   # NA 不能变成字符串 "NA"
  s <- gsub("\\", "\\\\", s, fixed = TRUE)
  s <- gsub('"', '\\"', s, fixed = TRUE)
  s <- gsub("\n", "\\n", s, fixed = TRUE)
  paste0('"', s, '"')
}

## 原子写文件：先写临时文件再改名，避免进程中断留下半个 JSON
write_file_atomic <- function(text, file) {
  tmp <- paste0(file, ".tmp", as.integer(stats::runif(1, 1, 1e6)))
  ok <- tryCatch({
    writeLines(enc2utf8(as.character(text)), tmp, useBytes = TRUE)
    TRUE
  }, error = function(e) FALSE)
  if (!ok) { unlink(tmp); return(FALSE) }
  moved <- isTRUE(tryCatch(file.rename(tmp, file), error = function(e) FALSE, warning = function(w) FALSE))
  if (!moved) {
    # Windows 上目标已存在时 rename 可能失败，退回覆盖拷贝
    moved <- isTRUE(tryCatch(file.copy(tmp, file, overwrite = TRUE), error = function(e) FALSE))
    unlink(tmp)
  }
  moved
}

## 值存在且非空/非空串
has_val <- function(x) {
  if (is.null(x)) return(FALSE)
  if (is_expr_spec(x)) return(nzchar(trimws(as.character(x$expr))))
  if (is.list(x)) return(length(x) > 0)
  if (length(x) != 1) return(length(x) > 0)
  if (is.na(x)) return(FALSE)
  if (is.character(x)) return(nzchar(trimws(x)))
  TRUE
}

## aes 值编码: {map:"col"} -> 符号 / {expr} -> 原样 / {value} -> 字面量
r_aes_value <- function(v) {
  if (is.null(v)) return(NULL)
  if (is_expr_spec(v)) return(enc2utf8(as.character(v$expr)))
  if (is.list(v) && !is.null(v$map)) {
    if (identical(v$map, "")) return(NULL)
    return(enc2utf8(as.character(v$map)))
  }
  if (is.list(v) && !is.null(v$value)) return(r_literal(v$value))
  r_literal(v)
}


## 读取 httpuv 请求体。httpuv >= 1.6.17 将 body 写入临时文件并以连接提供
## (req$.bodyData)，写完后读指针留在文件末尾 —— 必须 seek 重绕后再读；
## 连接由 httpuv 自行关闭，我们不主动 close。
## 上限 50MB：超出时给出明确错误（否则会被静默截断成「JSON 解析失败」）
GG_BODY_LIMIT <- 5e7

read_body <- function(req) {
  con <- req$.bodyData
  if (!is.null(con) && inherits(con, "connection")) {
    raw <- tryCatch({
      seek(con, where = 0)
      readBin(con, "raw", n = GG_BODY_LIMIT + 1)
    }, error = function(e) NULL)
    if (length(raw) > GG_BODY_LIMIT) {
      stop("请求体过大：上限 50MB（约合 37MB 数据文件），请先裁剪后再上传", call. = FALSE)
    }
    if (length(raw)) {
      txt <- rawToChar(raw)
      Encoding(txt) <- "UTF-8"
      return(txt)
    }
  }
  pb <- req$postBody
  if (!is.null(pb) && nzchar(pb)) return(pb)
  input <- req$rook.input
  if (!is.null(input)) {
    chunks <- list()
    total <- 0L
    repeat {
      chunk <- input$read(65536L)
      if (length(chunk) == 0) break
      total <- total + length(chunk)
      if (total > GG_BODY_LIMIT) {
        stop("请求体过大：上限 50MB（约合 37MB 数据文件），请先裁剪后再上传", call. = FALSE)
      }
      chunks[[length(chunks) + 1]] <- rawToChar(chunk)
    }
    txt <- paste(chunks, collapse = "")
    Encoding(txt) <- "UTF-8"
    return(txt)
  }
  ""
}

parse_json_body <- function(req) {
  txt <- read_body(req)
  if (!nzchar(trimws(txt))) return(list())
  Encoding(txt) <- "UTF-8"
  jsonlite::fromJSON(txt, simplifyVector = FALSE)
}

json_response <- function(obj, status = 200L) {
  txt <- jsonlite::toJSON(obj, auto_unbox = TRUE, null = "null", na = "null",
                          digits = NA, pretty = FALSE)
  # 以 raw 返回：httpuv 将据此设置明确的 Content-Length，
  # 避免依赖 chunked 编码（部分代理对大 chunked 响应处理有问题）
  list(status = status,
       headers = list("Content-Type" = "application/json; charset=utf-8",
                      "Cache-Control" = "no-store"),
       body = charToRaw(enc2utf8(as.character(txt))))
}

json_error <- function(msg, status = 400L) {
  json_response(list(ok = FALSE, error = enc2utf8(as.character(msg))), status)
}

## 渲染尺寸/dpi 钳制：客户端 bug 或恶意请求传 1e5×1e5 时，
## 避免 agg_png 直接分配数十 GB 位图把单线程后端打挂
clamp_px <- function(v, def, lo, hi) {
  v <- suppressWarnings(as.integer(v %||% def))
  if (is.na(v)) v <- as.integer(def)
  max(as.integer(lo), min(v, as.integer(hi)))
}

