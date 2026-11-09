# Glyph - 工作区（项目目录）
#
# 为什么需要：此前所有持久化数据都锚在「Glyph 安装目录」（run.R 里 root <- scriptdir），
# 导致图库、上传数据、编辑记录都混在程序目录里，无法按项目隔离。
# 引入工作区后：
#   APP_ROOT = 安装目录（R/ 与 dist/ 所在，只读）
#   WS_ROOT  = 工作区目录（数据与产出所在，按项目）
# 未指定时 WS_ROOT 退回 APP_ROOT，保持与旧版行为一致。
#
# 目录布局（<WS_ROOT>/）：
#   glyph.json      项目文件（绘图规格）
#   pins.json       图库索引
#   pins/           图库缩略图（P*.png）与数据快照（P*.rds）
#   userdata/       上传 / 粘贴的数据
#   edits.json      单元格手工编辑记录
#   extensions.json 扩展开关（全局性，但留在工作区便于整目录搬迁）

WORKSPACE <- local({
  .root <- NULL
  .explicit <- FALSE

  normalize_dir <- function(dir) {
    if (is.null(dir) || !is.character(dir) || length(dir) != 1L || !nzchar(dir)) {
      return(NULL)
    }
    # 允许 ~ 与相对路径；不存在则尝试创建（DSH 传来的目录可能尚未建好）
    p <- tryCatch(path.expand(dir), error = function(e) dir)
    if (!dir.exists(p)) {
      ok <- tryCatch(dir.create(p, recursive = TRUE, showWarnings = FALSE),
                     error = function(e) FALSE)
      if (!ok && !dir.exists(p)) return(NULL)
    }
    tryCatch(normalizePath(p, winslash = "/", mustWork = TRUE),
             error = function(e) normalizePath(p, winslash = "/", mustWork = FALSE))
  }

  layout_of <- function(root) {
    list(
      root      = root,
      project   = file.path(root, "glyph.json"),
      pins_file = file.path(root, "pins.json"),
      pins_dir  = file.path(root, "pins"),
      userdata  = file.path(root, "userdata"),
      edits     = file.path(root, "edits.json"),
      extensions = file.path(root, "extensions.json")
    )
  }

  # 工作区标识：由规范化路径派生，稳定且可复现。
  # 前端用它作为 projectId —— 同一个目录在任何浏览器/机器上都对应同一份图库视图。
  id_of <- function(root) {
    if (is.null(root) || !nzchar(root)) return("")
    # 统一大小写（Windows 路径不区分大小写），再取短哈希。
    # 用「多项式滚动哈希 + 取模」，全程保持在 double 安全整数范围内。
    key <- tolower(gsub("\\\\", "/", root))
    h <- 5381
    for (b in as.integer(charToRaw(key))) {
      h <- (h * 33 + b) %% 2147483647
    }
    sprintf("ws-%08x", as.integer(h))
  }

  list(
    # 初始化：dir 为空则退回 app_root（向后兼容）
    init = function(dir, app_root) {
      r <- normalize_dir(dir)
      .explicit <<- !is.null(r)
      .root <<- if (.explicit) r else app_root
      layout_of(.root)
    },
    root = function() .root,
    is_explicit = function() .explicit,
    layout = function() layout_of(.root),
    layout_for = function(root) layout_of(root),
    id = function() id_of(.root),
    id_for = function(root) id_of(root),
    normalize = normalize_dir
  )
})

# 把旧布局（P*.png / P*.rds 直接放在工作区根下）迁移到 pins/ 子目录
# 只在目标文件不存在时移动，避免覆盖已有数据
migrate_pins_layout <- function(layout) {
  if (!dir.exists(layout$pins_dir)) {
    dir.create(layout$pins_dir, showWarnings = FALSE, recursive = TRUE)
  }
  old <- list.files(layout$root, pattern = "^P[0-9]+\\.(png|rds)$", full.names = TRUE)
  moved <- 0L
  for (f in old) {
    dst <- file.path(layout$pins_dir, basename(f))
    if (!file.exists(dst)) {
      if (isTRUE(file.rename(f, dst))) moved <- moved + 1L
    }
  }
  if (moved > 0L) {
    cat(sprintf("已把 %d 个图库文件从根目录迁到 pins/（工作区: %s）\n", moved, layout$root))
  }
  invisible(moved)
}

# 把各 store 绑到某个工作区目录（启动时与运行时切换都走这里）
bind_workspace <- function(state, root, migrate = TRUE) {
  lay <- WORKSPACE$layout_for(root)
  dir.create(lay$pins_dir, showWarnings = FALSE, recursive = TRUE)
  if (migrate) migrate_pins_layout(lay)
  DataStore$bind(lay$userdata)
  Pins$bind(lay$pins_file)
  EditStore$bind(lay$edits)
  ext_state_bind(lay$extensions)
  state$pin_file <- lay$pins_file
  invisible(lay)
}
