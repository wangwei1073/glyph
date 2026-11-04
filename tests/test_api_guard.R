# ggplotGUI 回归测试：请求来源校验（防浏览器侧 CSRF / DNS 重绑定）
# 背景：/api/rawrender 会在本机执行任意 R 代码，若不加来源校验，
#       任意网页都能借用户浏览器对本机 POST 一段 R 代码。
# 运行: Rscript tests/test_api_guard.R

if (.Platform$OS.type == "windows") {
  ok <- tryCatch(nzchar(Sys.setlocale("LC_CTYPE", ".UTF-8")), error = function(e) FALSE)
  if (!ok) invisible(try(Sys.setlocale("LC_CTYPE", "Chinese (Simplified)_China.utf8"), silent = TRUE))
}
options(warn = 1)
for (f in sort(list.files(file.path(getwd(), "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8")
}
suppressPackageStartupMessages(library(ggplot2))

STATE <- list(version = "1.0.0", meta = list(geoms = list()), data_store = DataStore,
              pin_store = Pins, edit_store = EditStore, raw_data = NULL,
              plot_dir = file.path(tempdir(), "ggplotgui-guard"),
              dist_dir = file.path(getwd(), "dist"),
              allowed_hosts = c("127.0.0.1", "localhost", "::1"))
app <- ggspec_api_app(STATE)

# 直接构造请求（模拟浏览器发来的各种组合）
call_raw <- function(path, method = "POST", body = "{}", host = "127.0.0.1:4321",
                     origin = NULL, ctype = "application/json", sfs = NULL) {
  tmp <- tempfile()
  writeLines(body, tmp, useBytes = TRUE)
  con <- file(tmp, open = "rb")
  on.exit({ try(close(con), silent = TRUE); unlink(tmp) }, add = TRUE)
  req <- list(PATH_INFO = path, REQUEST_METHOD = method, QUERY_STRING = "",
              HTTP_HOST = host, CONTENT_TYPE = ctype, .bodyData = con)
  if (!is.null(origin)) req$HTTP_ORIGIN <- origin
  if (!is.null(sfs)) req$HTTP_SEC_FETCH_SITE <- sfs
  res <- app$call(req)
  txt <- if (is.raw(res$body)) rawToChar(res$body) else paste(as.character(res$body), collapse = "")
  list(status = res$status, txt = txt)
}

expect_status <- function(label, got, want) {
  if (identical(as.integer(got), as.integer(want))) {
    cat(sprintf("[OK] %s -> %d\n", label, got)); TRUE
  } else {
    cat(sprintf("[FAIL] %s -> %d（期望 %d）\n", label, got, want)); FALSE
  }
}

ok <- TRUE
# 1) 正常同源请求放行
ok <- expect_status("同源 POST /api/code", call_raw("/api/code", body = '{"spec":{}}')$status, 200L) && ok
ok <- expect_status("同源 GET /api/meta", call_raw("/api/meta", method = "GET", ctype = NULL)$status, 200L) && ok
# 1b) 浏览器对同源 POST 也会带 Origin —— 必须放行（回归：曾因未去 scheme 被误判为跨站）
ok <- expect_status("同源 Origin 127.0.0.1:4321",
                    call_raw("/api/code", body = '{"spec":{}}',
                             origin = "http://127.0.0.1:4321")$status, 200L) && ok
ok <- expect_status("同源 Origin localhost:4321",
                    call_raw("/api/code", body = '{"spec":{}}', host = "localhost:4321",
                             origin = "http://localhost:4321")$status, 200L) && ok
# 2) 跨站 Origin 被拒
ok <- expect_status("跨站 Origin POST",
                    call_raw("/api/rawrender", body = '{"code":"1"}',
                             origin = "https://evil.example")$status, 403L) && ok
# 2b) 同主机不同端口（浏览器视为不同源）被拒
ok <- expect_status("Origin 同主机不同端口",
                    call_raw("/api/code", body = '{"spec":{}}',
                             origin = "http://127.0.0.1:9999")$status, 403L) && ok
# 3) Sec-Fetch-Site: cross-site 被拒
ok <- expect_status("Sec-Fetch-Site cross-site",
                    call_raw("/api/rawrender", body = '{"code":"1"}', sfs = "cross-site")$status, 403L) && ok
# 4) DNS 重绑定：Host 不是回环地址被拒
ok <- expect_status("Host=evil.example（DNS 重绑定）",
                    call_raw("/api/rawrender", body = '{"code":"1"}', host = "evil.example")$status, 403L) && ok
# 5) 简单请求（text/plain，可绕过 CORS 预检）被拒
ok <- expect_status("Content-Type: text/plain",
                    call_raw("/api/rawrender", body = '{"code":"1"}', ctype = "text/plain")$status, 403L) && ok
# 6) 图片/文件 GET 无 Origin 头，仍可访问
ok <- expect_status("GET /api/plot 无 Origin",
                    call_raw("/api/plot/none.png", method = "GET", ctype = NULL)$status, 404L) && ok

cat(if (ok) "\n===== 来源校验全部通过 =====\n" else "\n===== 来源校验存在失败 =====\n")
quit(status = if (ok) 0L else 1L)
