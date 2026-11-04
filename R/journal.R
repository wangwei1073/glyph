# ggplotGUI - 期刊模板（P1-2）
# 只放"可判定"的硬性要求：栏宽、最小字号、字体白名单、可接受格式、最小 dpi。
# 宽高比、图注字数等软性要求不在这里，避免给出错误的安全感。

JOURNAL_TEMPLATES <- list(
  list(
    id = "generic", label = "通用（300 dpi 白底）",
    widthMm = NULL, minTextPt = 6, minDpi = 300,
    fonts = NULL, formats = c("png", "svg", "pdf"),
    note = "不绑定具体期刊，只做基础规范检查"
  ),
  list(
    id = "nature", label = "Nature",
    widthMm = 89, minTextPt = 5, minDpi = 300,
    fonts = c("Arial", "Helvetica", "Times New Roman", "Times"),
    formats = c("pdf", "svg", "png"),
    note = "单栏约 89 mm；正文 5–7 pt；优先矢量或 300 dpi 以上位图"
  ),
  list(
    id = "science", label = "Science",
    widthMm = 55, minTextPt = 5, minDpi = 300,
    fonts = c("Arial", "Helvetica"),
    formats = c("pdf", "svg"),
    note = "单栏约 55 mm；优先 PDF/SVG"
  ),
  list(
    id = "cell", label = "Cell",
    widthMm = 85, minTextPt = 6, minDpi = 300,
    fonts = c("Arial", "Helvetica"),
    formats = c("pdf", "svg", "png"),
    note = "单栏约 85 mm；字号 ≥6 pt"
  ),
  list(
    id = "plos", label = "PLOS",
    widthMm = 83, minTextPt = 6, minDpi = 300,
    fonts = c("Arial", "Helvetica", "Times New Roman"),
    formats = c("tiff", "eps", "pdf"),
    note = "单栏约 83 mm；偏好 TIFF/EPS；PDF 可作替代"
  ),
  list(
    id = "ieee", label = "IEEE",
    widthMm = 88, minTextPt = 8, minDpi = 300,
    fonts = c("Times New Roman", "Times", "Arial"),
    formats = c("pdf", "svg"),
    note = "单栏约 88 mm；正文 ≥8 pt；优先矢量"
  ),
  list(
    id = "cn-core", label = "中文核心",
    widthMm = 85, minTextPt = 7, minDpi = 300,
    fonts = c("宋体", "SimSun", "黑体", "SimHei", "Times New Roman", "Arial"),
    formats = c("pdf", "svg", "png"),
    note = "单栏约 85 mm；正文 ≥7 pt；中文用宋体/黑体"
  )
)

journal_templates <- function() JOURNAL_TEMPLATES

journal_get <- function(id) {
  if (is.null(id) || !nzchar(as.character(id))) return(NULL)
  id <- as.character(id)
  for (t in JOURNAL_TEMPLATES) if (identical(t$id, id)) return(t)
  NULL
}
