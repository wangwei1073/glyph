# Glyph - 可复现包（P1-3）
# 一次导出：图（PNG+PDF）+ 原始数据 CSV + 可运行代码 + sessionInfo + 图注草稿 + 项目文件
# 全部打成一个 zip，解压后 `Rscript figure.R` 即可复现。

ggspec_bundle <- function(spec, meta, state, width = 1600, height = 1000,
                          dpi = 300, format = "png", journal = NULL, project_id = NULL,
                          code = NULL) {
  spec <- spec %||% list()
  is_code <- is.character(code) && length(code) == 1L && nzchar(code)
  if (isTRUE((spec$combine %||% list())$active)) {
    stop("拼图模式暂不支持可复现包：请先关闭「渲染组合图」")
  }
  # 代码图没有图层，但确实有内容可打包 —— 之前会误报「画布为空」
  has_layers <- is_code || length(spec$layers %||% list()) > 0
  if (!has_layers) stop("画布为空，没有可打包的内容")

  bdir <- file.path(tempdir(), paste0("ggbundle-", as.integer(stats::runif(1, 1, 1e9))))
  dir.create(bdir, showWarnings = FALSE, recursive = TRUE)
  on.exit(unlink(bdir, recursive = TRUE), add = TRUE)

  src <- (spec$data %||% list())$source %||% list(type = "none")
  is_user <- identical(src$type, "user")
  data_file <- if (is_user) "data.csv" else NULL

  # ---- 数据 ----
  data_label <- ""
  if (is_user) {
    d <- state$data_store$get(src_id_of(src))
    if (is.null(d)) stop("上传数据不存在或已失效，无法打包")
    d <- d[, setdiff(names(d), ".gg_rid"), drop = FALSE]
    utils::write.csv(d, file.path(bdir, "data.csv"), row.names = FALSE, na = "",
                     fileEncoding = "UTF-8")
    info <- state$data_store$info(src_id_of(src)) %||% list()
    data_label <- sprintf("%s（%d 行 × %d 列）", info$label %||% "上传数据", nrow(d), ncol(d))
  } else if (identical(src$type, "dataset")) {
    d <- tryCatch(dataset_load(src$name), error = function(e) NULL)
    data_label <- sprintf("%s（内置数据集%s）", src$name,
                          if (is.null(d)) "" else sprintf("，%d 行 × %d 列", nrow(d), ncol(d)))
  }

  # ---- 代码 ----
  if (is_code) {
    # 代码图：figure.R = 数据准备行 + 用户自己的代码，保证解压后能直接 Rscript 复现
    preamble <- .data_lines(spec, state, df_name = "df", data_file = data_file)
    writeLines(c(preamble, "", code), file.path(bdir, "figure.R"), useBytes = TRUE)
  } else {
    gen <- spec_to_code(spec, meta, state, data_file = data_file)
    writeLines(gen$code, file.path(bdir, "figure.R"), useBytes = TRUE)
  }

  # ---- 图（PNG + PDF） ----
  fig_files <- character(0)
  for (fmt in c("png", "pdf")) {
    rf <- tryCatch({
      if (is_code) ggspec_export_code(code, spec, state, width, height, dpi, fmt)
      else ggspec_export(spec, meta, state, width, height, dpi, fmt)
    }, error = function(e) e)
    if (inherits(rf, "error")) stop("图形导出失败：", conditionMessage(rf))
    dst <- file.path(bdir, paste0("figure.", fmt))
    file.copy(rf$path, dst, overwrite = TRUE)
    unlink(rf$path)
    fig_files <- c(fig_files, dst)
  }

  # ---- 运行环境 ----
  writeLines(capture.output(sessionInfo()), file.path(bdir, "sessionInfo.txt"))

  # ---- 图注草稿 ----
  tpl <- journal_get(journal)
  w_mm <- round(width / max(dpi, 1) * 25.4, 1)
  h_mm <- round(height / max(dpi, 1) * 25.4, 1)
  pkg_ver <- function(p) {
    if (!requireNamespace(p, quietly = TRUE)) return(NULL)
    sprintf("%s %s", p, as.character(packageVersion(p)))
  }
  # 依赖包清单：spec 路径用生成器给的；代码图路径从代码里的 library() 解析
  if (is_code) {
    hits <- regmatches(code, gregexpr("library\\(\\s*[\"']?([A-Za-z0-9._]+)", code, perl = TRUE))[[1]]
    code_pkgs <- sub("library\\(\\s*[\"']?", "", hits)
    pkgs <- unique(c("ggplot2", code_pkgs))
  } else {
    pkgs <- unique(c("ggplot2", sub("^library\\((.*)\\)$", "\\1", gen$packages %||% character(0))))
  }
  ver_line <- paste(Filter(Negate(is.null), vapply(pkgs, pkg_ver, "")), collapse = " · ")
  # 数据文件校验哈希：审稿返修时核对数据版本用
  data_hash <- if (is_user)
    tryCatch(as.character(tools::md5sum(file.path(bdir, "data.csv"))), error = function(e) NULL)
    else NULL
  caption <- c(
    sprintf("# %s", (spec$labs %||% list())$title %||% "Glyph figure"),
    "",
    sprintf("- 数据来源：%s", if (nzchar(data_label)) data_label else "未使用数据"),
    if (!is.null(data_hash)) sprintf("- 数据校验 (MD5): %s", data_hash),
    sprintf("- 图形尺寸：%s × %s mm @ %d dpi（PNG）/ 同尺寸 PDF", w_mm, h_mm, dpi),
    if (!is.null(tpl)) sprintf("- 目标期刊模板：%s", tpl$label),
    sprintf("- 生成时间：%s", format(Sys.time(), "%Y-%m-%d %H:%M")),
    sprintf("- 软件环境：%s", ver_line),
    "",
    "> 图注为自动生成的草稿：数据来源、统计方法与缩写请在投稿前人工核对。"
  )
  writeLines(caption, file.path(bdir, "caption.md"), useBytes = TRUE)

  # ---- 项目文件（可重新导入 Glyph） ----
  env_data <- NULL
  if (is_user) {
    env_data <- list(
      sourceKey = .keyof(src),
      label = (state$data_store$info(src_id_of(src)) %||% list())$label %||% "上传数据",
      csv = paste(readLines(file.path(bdir, "data.csv"), warn = FALSE), collapse = "\n"),
      edits = (state$edit_store %||% list(get = function(k) list()))$get(.keyof(src))
    )
  }
  project <- list(app = "ggplotgui", format = 2, savedAt = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ"),
                  projectId = as.character(project_id %||% ""),
                  spec = spec, data = env_data)
  writeLines(jsonlite::toJSON(project, auto_unbox = TRUE, null = "null", digits = NA, pretty = TRUE),
             file.path(bdir, "project.json"), useBytes = TRUE)

  # ---- 说明 ----
  readme <- c(
    "Glyph 可复现包",
    "=============",
    "",
    "文件：",
    sprintf("- figure.png / figure.pdf   最终图（%s × %s mm @ %d dpi）", w_mm, h_mm, dpi),
    "- figure.R                 生成该图的 R 代码（工作目录 = 本文件夹）",
    if (is_user) "- data.csv                 本次使用的原始数据（加工步骤写在代码里）",
    "- sessionInfo.txt          运行环境与包版本",
    "- caption.md               图注草稿（需人工核对）",
    "- project.json             可重新导入 Glyph 的项目文件",
    "",
    "复现：",
    "1. 安装代码中用到的包（见 sessionInfo.txt）",
    "2. 在本文件夹执行：Rscript figure.R",
    "",
    "说明：",
    "- 内置数据集（如 mpg）由 ggplot2 提供，无需 data.csv。",
    "- 手工编辑（单元格/增删行）已写入 figure.R，数据文件保持原始状态。"
  )
  writeLines(readme, file.path(bdir, "README.txt"), useBytes = TRUE)

  # ---- 打包 ----
  fname <- sprintf("ggplotgui-bundle-%s.zip", format(Sys.time(), "%Y%m%d-%H%M%S"))
  zip_path <- file.path(bdir, fname)
  files <- list.files(bdir, full.names = FALSE)
  files <- setdiff(files, fname)
  if (requireNamespace("zip", quietly = TRUE)) {
    zip::zipr(zip_path, files = files, root = bdir)
  } else {
    old <- setwd(bdir); on.exit(setwd(old), add = TRUE)
    utils::zip(zipfile = zip_path, files = files)
  }
  if (!file.exists(zip_path)) stop("打包失败")
  dst <- file.path(state$plot_dir, fname)
  dir.create(state$plot_dir, showWarnings = FALSE, recursive = TRUE)
  if (!file.copy(zip_path, dst, overwrite = TRUE)) stop("可复现包写入失败")
  list(path = dst, filename = fname, files = files,
       widthMm = w_mm, heightMm = h_mm, dpi = dpi)
}

# 一键完整脚本：与可复现包 figure.R 同源（数据准备 + 绘图代码），
# 外加头部环境注释（生成时间 / R 版本 / 依赖包与版本 / 安装命令）。
# 数据用内联或 TODO 占位（不走 data.csv），粘贴到 RStudio 即可复跑。
ggspec_full_script <- function(spec, meta, state, code = NULL) {
  spec <- spec %||% list()
  is_code <- is.character(code) && length(code) == 1L && nzchar(code)
  has_layers <- is_code || length(spec$layers %||% list()) > 0
  if (!has_layers) stop("画布为空，没有可导出的内容")

  pkgs <- character(0)
  if (is_code) {
    body_lines <- c(.data_lines(spec, state, df_name = "df", data_file = NULL), "", code)
    hits <- regmatches(code, gregexpr("library\\(\\s*[\"']?([A-Za-z0-9._]+)", code, perl = TRUE))[[1]]
    pkgs <- unique(c("ggplot2", sub("library\\(\\s*[\"']?", "", hits)))
  } else {
    gen <- spec_to_code(spec, meta, state)
    body_lines <- gen$code
    pkgs <- unique(c("ggplot2", sub("^library\\((.*)\\)$", "\\1", gen$packages %||% character(0))))
  }
  pkg_ver <- function(p) {
    if (!requireNamespace(p, quietly = TRUE))
      return(sprintf("%s (未安装)", p))
    sprintf("%s %s", p, as.character(utils::packageVersion(p)))
  }
  header <- c(
    "# 由 Glyph 生成的完整复现脚本",
    sprintf("# 生成时间：%s | %s", format(Sys.time(), "%Y-%m-%d %H:%M"), R.version.string),
    sprintf("# 依赖包：%s", paste(vapply(pkgs, pkg_ver, ""), collapse = ", ")),
    sprintf("# 缺包时先运行：install.packages(c(%s))",
            paste(sprintf('"%s"', pkgs), collapse = ", ")),
    "",
    "# ============ 数据准备 ============"
  )
  c(header, body_lines)
}
