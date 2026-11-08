# 抓取 ggplot2 extensions gallery 的完整扩展清单（170 个）
# 用法: Rscript tools/fetch_ext_gallery.R
#
# 背景：gallery 页面是 JS 动态渲染，但全部 170 个卡片都在初始 HTML 里，
#       直接用 HTTP 取回再按 .card grid-item 切分即可，无需浏览器。

out_file <- file.path("tools", "ggplot2_extensions_170.csv")
url <- "https://exts.ggplot2.tidyverse.org/gallery/"

html <- tryCatch({
  tmp <- tempfile(fileext = ".html")
  utils::download.file(url, tmp, quiet = TRUE, mode = "wb")
  txt <- paste(readLines(tmp, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
  unlink(tmp)
  txt
}, error = function(e) NULL)

if (is.null(html) || !nzchar(html)) {
  cat("下载失败：请检查网络，或用浏览器另存页面后手工解析\n")
  quit(status = 1L)
}

# 按卡片切分
parts <- strsplit(html, '<div class="card grid-item"', fixed = TRUE)[[1]]
if (length(parts) < 2) {
  cat("页面结构可能已变，未找到 card 容器\n")
  quit(status = 1L)
}

grab <- function(block, pattern) {
  m <- regmatches(block, regexpr(pattern, block, perl = TRUE))
  if (!length(m)) return("")
  sub(pattern, "\\1", m, perl = TRUE)
}

rows <- list()
for (i in 2:length(parts)) {
  b <- parts[[i]]
  name <- grab(b, '<span class="card-title[^"]*">([^<]+)</span>')
  if (!nzchar(name)) next
  rows[[length(rows) + 1]] <- data.frame(
    Name = name,
    Author = grab(b, 'widget-author widget-meta"><a href="[^"]+">([^<]+)</a>'),
    Tags = grab(b, 'widget-tags widget-meta">([^<]+)</span>'),
    Cran = grab(b, 'widget-cran">(true|false)'),
    Desc = gsub("\\s+", " ", grab(b, 'widget-shortdesc">([\\s\\S]*?)</p>')),
    Url = grab(b, '<a href="(https://github\\.com/[^"]+)"><span class="card-title'),
    stringsAsFactors = FALSE
  )
}

if (!length(rows)) {
  cat("未解析到任何扩展\n")
  quit(status = 1L)
}
df <- do.call(rbind, rows)
df$Desc <- trimws(df$Desc)
df <- df[!duplicated(df$Name), ]
utils::write.csv(df, out_file, row.names = FALSE, fileEncoding = "UTF-8")

cat(sprintf("已解析 %d 个扩展 -> %s\n", nrow(df), out_file))
cat(sprintf("  CRAN 内: %d / 仅 GitHub: %d\n",
            sum(df$Cran == "true"), sum(df$Cran == "false")))
