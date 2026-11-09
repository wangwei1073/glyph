# 实测 ggplot2 4.0.3 下，各 theme 元素接受哪些枚举取值
# 目的：把「有几个固定选项」的自由文本输入改成下拉，选项必须真实可用
suppressMessages(library(ggplot2))

try_val <- function(elem, val) {
  p <- ggplot(mtcars, aes(wt, mpg)) + geom_point()
  th <- tryCatch(do.call(theme, stats::setNames(list(val), elem)),
                 error = function(e) e)
  if (inherits(th, "error")) return(paste0("ERR:", conditionMessage(th)))
  out <- tryCatch({
    f <- tempfile(fileext = ".png")
    ggsave(f, p + th, width = 3, height = 2, dpi = 72)
    unlink(f)
    "OK"
  }, error = function(e) paste0("ERR:", conditionMessage(e)),
     warning = function(w) paste0("WARN:", conditionMessage(w)))
  out
}

cases <- list(
  legend.direction          = c("horizontal", "vertical"),
  legend.location           = c("panel", "plot"),
  legend.justification      = c("center", "left", "right", "top", "bottom"),
  legend.justification.top  = c("center", "left", "right"),
  legend.justification.left = c("center", "top", "bottom"),
  legend.text.position      = c("top", "right", "bottom", "left"),
  legend.title.position     = c("top", "right", "bottom", "left"),
  legend.key.justification  = c("center", "left", "right", "top", "bottom"),
  plot.title.position       = c("panel", "plot"),
  plot.caption.position     = c("panel", "plot"),
  plot.tag.location         = c("panel", "plot", "margin"),
  plot.tag.position         = c("topleft", "top", "topright", "left", "center",
                                "right", "bottomleft", "bottom", "bottomright"),
  strip.placement.x         = c("outside", "inside"),
  strip.placement.y         = c("outside", "inside"),
  legend.byrow              = c(TRUE, FALSE),
  legend.direction.x        = c("horizontal")   # 预期不存在，验证探测方法
)

cat("ggplot2", as.character(packageVersion("ggplot2")), "\n\n")
for (elem in names(cases)) {
  cat("## ", elem, "\n", sep = "")
  for (v in cases[[elem]]) {
    r <- try_val(elem, v)
    cat(sprintf("   %-12s -> %s\n", deparse(v), r))
  }
  cat("\n")
}
