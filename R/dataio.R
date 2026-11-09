# Glyph - 用户数据 IO：上传 / 粘贴 / 数据加工

# 全局用户数据存储（内存 + 落盘，重启后可恢复）
# 目录结构：<dir>/meta.json + <dir>/u1.rds（上传/粘贴的原始数据）
DataStore <- local({
  .items <- list()
  .counter <- 0L
  .dir <- NULL

  .meta_file <- function() file.path(.dir, "meta.json")
  .item_file <- function(id) file.path(.dir, paste0(id, ".rds"))

  .save_meta <- function() {
    if (is.null(.dir)) return(invisible(FALSE))
    meta <- lapply(.items, function(it) {
      out <- list(id = it$id, label = it$label, nrow = it$nrow, ncol = it$ncol)
      if (!is.null(it$origin)) out$origin <- it$origin
      out
    })
    invisible(tryCatch({
      write_file_atomic(jsonlite::toJSON(unname(meta), auto_unbox = TRUE, pretty = TRUE,
                                         null = "null", na = "null"),
                        .meta_file())
      TRUE
    }, error = function(e) FALSE))
  }

  .load <- function() {
    if (is.null(.dir) || !file.exists(.meta_file())) return(invisible(FALSE))
    meta <- tryCatch(jsonlite::fromJSON(.meta_file(), simplifyVector = FALSE),
                     error = function(e) NULL)
    if (!is.list(meta)) return(invisible(FALSE))
    for (m in meta) {
      id <- as.character(m$id %||% "")
      if (!nzchar(id) || !file.exists(.item_file(id))) next
      d <- tryCatch(readRDS(.item_file(id)), error = function(e) NULL)
      if (is.null(d)) next
      if (!".gg_rid" %in% names(d)) d <- ggspec_with_rid(d)
      .items[[id]] <<- list(df = d, label = as.character(m$label %||% id), id = id,
                            nrow = nrow(d), ncol = ncol(d), origin = m$origin)
      n <- suppressWarnings(as.integer(sub("^u", "", id)))
      if (!is.na(n)) .counter <<- max(.counter, n)
    }
    invisible(TRUE)
  }

  list(
    bind = function(dir) {
      .dir <<- dir
      dir.create(dir, showWarnings = FALSE, recursive = TRUE)
      .load()
    },
    dir = function() .dir,
    add = function(df, label, origin = NULL) {
      if (!".gg_rid" %in% names(df)) df <- ggspec_with_rid(df)
      .counter <<- .counter + 1L
      id <- sprintf("u%d", .counter)
      .items[[id]] <<- list(df = df, label = label, id = id,
                            nrow = nrow(df), ncol = ncol(df), origin = origin)
      if (!is.null(.dir)) {
        try(saveRDS(df, .item_file(id)), silent = TRUE)
        .save_meta()
      }
      id
    },
    get = function(id) .items[[id]]$df,
    info = function(id) {
      it <- .items[[id]]
      if (is.null(it)) return(NULL)
      list(type = "user", id = it$id, name = it$id, label = it$label,
           nrow = it$nrow, ncol = it$ncol, package = NULL,
           origin = it$origin %||% NULL)
    },
    list = function() lapply(names(.items), function(id) .info_wrap(.items[[id]])),
    remove = function(id) {
      .items[[id]] <<- NULL
      if (!is.null(.dir)) {
        unlink(.item_file(id))
        .save_meta()
      }
    }
  )
})
.info_wrap <- function(it) list(type = "user", id = it$id, name = it$id, label = it$label,
                                nrow = it$nrow, ncol = it$ncol, package = NULL,
                                origin = it$origin %||% NULL)

# 解码 base64 -> 临时文件 -> 读取为 data.frame
data_from_upload <- function(name, ext, data_base64) {
  ext <- tolower(sub("^\\.", "", ext %||% tools::file_ext(name)))
  tmp <- tempfile(fileext = paste0(".", ext))
  on.exit(unlink(tmp), add = TRUE)
  con <- file(tmp, open = "wb")
  writeBin(jsonlite::base64_dec(data_base64), con)
  close(con)
  d <- switch(ext,
    csv = readr::read_csv(tmp, show_col_types = FALSE, progress = FALSE),
    tsv = readr::read_tsv(tmp, show_col_types = FALSE, progress = FALSE),
    txt = readr::read_csv(tmp, show_col_types = FALSE, progress = FALSE),
    xls = , xlsx = readxl::read_excel(tmp),
    rds = readRDS(tmp),
    json = jsonlite::fromJSON(tmp, simplifyVector = TRUE),
    rdata = , rda = (function() { e <- new.env(); load(tmp, envir = e); e })(),
    stop(sprintf("暂不支持的文件类型: %s", ext))
  )
  if (inherits(d, "environment")) {
    cands <- Filter(function(n) is.data.frame(d[[n]]), ls(d))
    if (!length(cands)) stop("RData 中没有找到 data.frame")
    d <- d[[cands[1]]]
  }
  d <- as.data.frame(d)
  names(d) <- make.names(names(d), unique = TRUE)
  ggspec_with_rid(d)
}

# 粘贴文本（CSV/TSV 自动识别）
data_from_paste <- function(text) {
  text <- enc2utf8(paste0(text, "\n"))
  tmp <- tempfile(fileext = ".txt")
  on.exit(unlink(tmp), add = TRUE)
  writeLines(text, tmp, useBytes = TRUE)
  sep <- if (grepl("\t", text)) "\t" else ","
  d <- readr::read_delim(tmp, delim = sep, show_col_types = FALSE, progress = FALSE)
  d <- as.data.frame(d)
  names(d) <- make.names(names(d), unique = TRUE)
  ggspec_with_rid(d)
}

# 数据加工：筛选 / 新增列 / 抽样
# 数据准备摘要：逐步计算影响（不修改原始数据），供界面展示
# 异常值：按列计算 IQR / z-score 边界，返回处理后的数据与统计
.apply_outlier_step <- function(df, o) {
  nm <- trimws(as.character(o$name %||% ""))
  if (!nzchar(nm) || !nm %in% names(df)) return(NULL)
  x <- suppressWarnings(as.numeric(df[[nm]]))
  if (all(is.na(x))) return(NULL)
  method <- as.character(o$method %||% "iqr")
  k <- suppressWarnings(as.numeric(o$k %||% if (identical(method, "z")) 3 else 1.5))
  if (!is.finite(k) || k <= 0) k <- if (identical(method, "z")) 3 else 1.5
  if (identical(method, "z")) {
    mu <- mean(x, na.rm = TRUE); sdv <- sd(x, na.rm = TRUE)
    lo <- mu - k * sdv; hi <- mu + k * sdv
  } else {
    q <- quantile(x, c(.25, .75), na.rm = TRUE, names = FALSE)
    iqr <- q[2] - q[1]
    lo <- q[1] - k * iqr; hi <- q[2] + k * iqr
  }
  flag <- !is.na(x) & (x < lo | x > hi)
  action <- as.character(o$action %||% "flag")
  if (identical(action, "flag")) {
    df[[paste0(nm, "_outlier")]] <- flag
  } else if (identical(action, "drop")) {
    df <- df[!flag, , drop = FALSE]
  } else if (identical(action, "winsor")) {
    x[!is.na(x) & x < lo] <- lo
    x[!is.na(x) & x > hi] <- hi
    df[[nm]] <- x
  }
  list(df = df, nm = nm, n = sum(flag), lo = lo, hi = hi,
       method = method, k = k, action = action, flag = flag)
}

data_prep_summary <- function(df, prep) {
  prep <- prep %||% list()
  if (is.null(df)) return(list(steps = list(), nrow = 0, ncol = 0, code = character(0)))
  d <- df
  steps <- list()
  code <- character(0)
  for (t in prep$types %||% list()) {
    if (isTRUE(t$disabled)) next
    nm <- trimws(as.character(t$name %||% ""))
    to <- as.character(t$type %||% "")
    if (!nzchar(nm) || !nm %in% names(d) || !nzchar(to)) next
    d[[nm]] <- switch(to, num = suppressWarnings(as.numeric(d[[nm]])),
                      chr = as.character(d[[nm]]), fct = as.factor(d[[nm]]),
                      lgl = suppressWarnings(as.logical(d[[nm]])),
                      date = suppressWarnings(as.Date(d[[nm]])), d[[nm]])
    steps[[length(steps) + 1]] <- list(type = "type", name = nm, to = to)
    fn <- c(num = "as.numeric", chr = "as.character", fct = "as.factor",
            lgl = "as.logical", date = "as.Date")[[to]]
    code <- c(code, sprintf("df$%s <- %s(df$%s)", nm, fn, nm))
  }
  for (tx in prep$text %||% list()) {
    if (isTRUE(tx$disabled)) next
    nm <- trimws(as.character(tx$name %||% ""))
    if (!nzchar(nm) || !nm %in% names(d)) next
    x0 <- as.character(d[[nm]])
    op <- as.character(tx$op %||% "trim")
    new <- switch(op,
      trim = trimws(x0), upper = toupper(x0), lower = tolower(x0),
      replace = {
        from <- as.character(tx$from %||% "")
        to <- as.character(tx$to %||% "")
        if (nzchar(from)) gsub(from, to, x0, fixed = TRUE) else x0
      }, x0)
    changed <- sum(!is.na(x0) & (is.na(new) | x0 != new))
    d[[nm]] <- new
    steps[[length(steps) + 1]] <- list(type = "text", name = nm, op = op, changed = changed)
    code <- c(code, switch(op,
      trim = sprintf("df$%s <- trimws(df$%s)", nm, nm),
      upper = sprintf("df$%s <- toupper(df$%s)", nm, nm),
      lower = sprintf("df$%s <- tolower(df$%s)", nm, nm),
      replace = sprintf("df$%s <- gsub(%s, %s, df$%s, fixed = TRUE)", nm,
                        deparse(as.character(tx$from %||% "")),
                        deparse(as.character(tx$to %||% "")), nm)))
  }
  for (o in prep$outliers %||% list()) {
    if (isTRUE(o$disabled)) next
    r <- .apply_outlier_step(d, o)
    if (is.null(r)) next
    d <- r$df
    steps[[length(steps) + 1]] <- list(type = "outlier", name = r$nm, method = r$method,
                                       action = r$action, n = r$n)
    code <- c(code, switch(r$action,
      flag = sprintf("df$%s_outlier <- !is.na(df$%s) & (df$%s < %.6g | df$%s > %.6g)",
                     r$nm, r$nm, r$nm, r$lo, r$nm, r$hi),
      drop = sprintf("df <- df[!is.na(df$%s) & (df$%s < %.6g | df$%s > %.6g), , drop = FALSE]",
                     r$nm, r$nm, r$lo, r$nm, r$hi),
      winsor = sprintf("df$%s <- pmin(pmax(df$%s, %.6g), %.6g)", r$nm, r$nm, r$lo, r$hi)))
  }
  for (m in prep$mutate %||% list()) {
    if (isTRUE(m$disabled)) next
    nm <- trimws(as.character(m$name %||% ""))
    ex <- trimws(as.character(m$expr %||% ""))
    if (!nzchar(nm) || !nzchar(ex)) next
    val <- tryCatch(eval(parse(text = ex, keep.source = FALSE), envir = d, enclos = parent.frame()),
                    error = function(e) e)
    if (inherits(val, "error")) {
      steps[[length(steps) + 1]] <- list(type = "mutate", name = nm,
                                         error = conditionMessage(val))
      next
    }
    d[[nm]] <- if (length(val) == 1L) rep(val, nrow(d)) else val
    steps[[length(steps) + 1]] <- list(type = "mutate", name = nm)
    code <- c(code, sprintf("df$%s <- %s", nm, ex))
  }
  flt <- trimws(as.character(prep$filter %||% ""))
  if (!isTRUE(prep$dropnaDisabled)) {
    cols <- intersect(as.character(unlist(prep$dropnaCols %||% list())), names(d))
    if (length(cols)) {
      before <- nrow(d)
      miss <- is.na(d[, cols, drop = FALSE])
      drop <- if (identical(prep$dropnaHow, "all")) apply(miss, 1, all) else apply(miss, 1, any)
      d <- d[!drop, , drop = FALSE]
      steps[[length(steps) + 1]] <- list(type = "dropna", removed = before - nrow(d), nrow = nrow(d))
      code <- c(code, sprintf("df <- df[!apply(is.na(df[, c(%s), drop = FALSE]), 1, %s), , drop = FALSE]",
                              paste(sprintf('"%s"', cols), collapse = ", "),
                              if (identical(prep$dropnaHow, "all")) "all" else "any"))
    }
  }
  if (!isTRUE(prep$filterDisabled) && nzchar(flt)) {
    before <- nrow(d)
    keep <- tryCatch(eval(parse(text = flt, keep.source = FALSE), envir = d, enclos = parent.frame()),
                     error = function(e) e)
    if (inherits(keep, "error")) {
      steps[[length(steps) + 1]] <- list(type = "filter", error = conditionMessage(keep))
    } else if (is.logical(keep)) {
      keep <- keep & !is.na(keep)
      d <- d[keep, , drop = FALSE]
      steps[[length(steps) + 1]] <- list(type = "filter", removed = before - nrow(d), nrow = nrow(d))
      code <- c(code, sprintf("df <- subset(df, %s)", flt))
    }
  }
  if (isTRUE(prep$dedupEnabled)) {
    before <- nrow(d)
    cols <- intersect(as.character(unlist(prep$dedupCols %||% list())), names(d))
    if (!length(cols)) cols <- setdiff(names(d), ".gg_rid")
    if (length(cols)) {
      d <- d[!duplicated(d[, cols, drop = FALSE]), , drop = FALSE]
      steps[[length(steps) + 1]] <- list(type = "dedup", removed = before - nrow(d), nrow = nrow(d))
      code <- c(code, sprintf("df <- df[!duplicated(df[, c(%s), drop = FALSE]), , drop = FALSE]",
                              paste(sprintf('"%s"', cols), collapse = ", ")))
    }
  }
  n <- prep$sample
  if (!isTRUE(prep$sampleDisabled) && !is.null(n) && is.numeric(n) && n > 0 && n < nrow(d)) {
    d <- d[sample.int(nrow(d), as.integer(n)), , drop = FALSE]
    steps[[length(steps) + 1]] <- list(type = "sample", n = nrow(d))
    code <- c(code, sprintf("set.seed(%s); df <- df[sample.int(nrow(df), %d), ]",
                            as.character(prep$seed %||% "NULL"), nrow(d)))
  }
  list(steps = steps, nrow = nrow(d), ncol = ncol(d), code = code)
}

data_prepare <- function(df, prep) {
  if (is.null(df)) return(df)
  prep <- prep %||% list()
  seed <- prep$seed
  if (!is.null(seed) && is.numeric(seed)) set.seed(as.integer(seed))

  # 类型转换（先做，后续筛选/派生依赖正确类型）
  for (t in prep$types %||% list()) {
    if (isTRUE(t$disabled)) next
    nm <- trimws(as.character(t$name %||% ""))
    if (!nzchar(nm) || !nm %in% names(df)) next
    x <- df[[nm]]
    df[[nm]] <- switch(as.character(t$type %||% ""),
      num  = suppressWarnings(as.numeric(x)),
      chr  = as.character(x),
      fct  = as.factor(x),
      lgl  = suppressWarnings(as.logical(x)),
      date = suppressWarnings(as.Date(x)),
      x)
  }

  # 文本清洗：去空格 / 大小写 / 替换
  for (tx in prep$text %||% list()) {
    if (isTRUE(tx$disabled)) next
    nm <- trimws(as.character(tx$name %||% ""))
    if (!nzchar(nm) || !nm %in% names(df)) next
    x <- as.character(df[[nm]])
    op <- as.character(tx$op %||% "trim")
    df[[nm]] <- switch(op,
      trim = trimws(x),
      upper = toupper(x),
      lower = tolower(x),
      replace = {
        from <- as.character(tx$from %||% "")
        to <- as.character(tx$to %||% "")
        if (nzchar(from)) gsub(from, to, x, fixed = TRUE) else x
      },
      x)
  }

  # 异常值：IQR / z-score，标记 / 删除 / 缩尾
  for (o in prep$outliers %||% list()) {
    if (isTRUE(o$disabled)) next
    r <- .apply_outlier_step(df, o)
    if (!is.null(r)) df <- r$df
  }

  # 新增列（先于筛选，供筛选使用）
  for (m in prep$mutate %||% list()) {
    if (isTRUE(m$disabled)) next
    if (is.null(m$name) || !nzchar(trimws(m$name))) next
    expr <- trimws(as.character(m$expr %||% ""))
    if (!nzchar(expr)) next
    val <- tryCatch(eval(parse(text = expr, keep.source = FALSE), envir = df, enclos = parent.frame()),
                    error = function(e) stop(sprintf("新增列 %s 出错: %s", m$name, conditionMessage(e))))
    df[[m$name]] <- if (length(val) == 1L) rep(val, nrow(df)) else val
  }

  # 缺失值：按所选列删除（any = 任一缺失即删；all = 全部缺失才删）
  if (!isTRUE(prep$dropnaDisabled)) {
    cols <- intersect(as.character(unlist(prep$dropnaCols %||% list())), names(df))
    if (length(cols)) {
      miss <- is.na(df[, cols, drop = FALSE])
      drop <- if (identical(prep$dropnaHow, "all")) apply(miss, 1, all) else apply(miss, 1, any)
      df <- df[!drop, , drop = FALSE]
    }
  }

  # 行筛选
  flt <- trimws(as.character(prep$filter %||% ""))
  if (!isTRUE(prep$filterDisabled) && nzchar(flt)) {
    keep <- tryCatch(eval(parse(text = flt, keep.source = FALSE), envir = df, enclos = parent.frame()),
                     error = function(e) stop(sprintf("筛选表达式出错: %s", conditionMessage(e))))
    if (!is.logical(keep)) {
      stop(sprintf("筛选表达式必须返回 TRUE/FALSE，当前返回 %s（例如写 hwy > 20 而不是 hwy）",
                   class(keep)[1]))
    }
    keep <- keep & !is.na(keep)
    df <- df[keep, , drop = FALSE]
  }

  # 去重（默认按全部列；可选指定列）
  if (isTRUE(prep$dedupEnabled)) {
    cols <- intersect(as.character(unlist(prep$dedupCols %||% list())), names(df))
    if (!length(cols)) cols <- setdiff(names(df), ".gg_rid")
    if (length(cols)) df <- df[!duplicated(df[, cols, drop = FALSE]), , drop = FALSE]
  }

  # 抽样
  n <- prep$sample
  if (!isTRUE(prep$sampleDisabled) && !is.null(n) && is.numeric(n) && n > 0 && n < nrow(df)) {
    df <- df[sample.int(nrow(df), as.integer(n)), , drop = FALSE]
  }
  rownames(df) <- NULL
  df
}

# 汇总数据来源（内置 + 用户上传）
data_sources <- function() {
  c(list(list(type = "none", name = "__none__", label = "（无数据）", nrow = NA, ncol = NA)),
    dataset_list(),
    DataStore$list())
}

# ---- 手动编辑：操作存储（edits.json）与引擎 ---------------------------------
# ops 形态（源自前端）：
#   cell   {kind, rid, col, value}      修改单元格（value NULL/"" -> NA）
#   rowDel {kind, rid}                  删除行
#   rowIns {kind, values:{col:value}}   末尾新增行（缺失列 NA）
#   colRen {kind, from, to}             列改名（同步更新后续编辑里的列名）
EditStore <- local({
  .edits <- list()   # key("dataset:mpg"/"user:u1") -> list of ops
  .file <- NULL
  .save <- function() {
    if (is.null(.file)) return()
    txt <- jsonlite::toJSON(.edits, auto_unbox = TRUE, null = "null", na = "null", pretty = TRUE)
    write_file_atomic(txt, .file)
  }
  list(
    bind = function(file) {
      .file <<- file
      dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
      if (file.exists(file)) {
        obj <- tryCatch(jsonlite::fromJSON(file, simplifyVector = FALSE), error = function(e) NULL)
        if (is.list(obj)) .edits <<- obj
      }
    },
    add = function(key, op) {
      .edits[[key]] <<- c(.edits[[key]] %||% list(), list(op))
      .save()
    },
    pop = function(key) {
      p <- .edits[[key]] %||% list()
      if (!length(p)) return(NULL)
      last <- p[[length(p)]]
      .edits[[key]] <<- if (length(p) == 1) NULL else p[-length(p)]
      .save()
      last
    },
    get = function(key) .edits[[key]] %||% list(),
    count = function(key) length(.edits[[key]] %||% list()),
    clear = function(key) { .edits[[key]] <<- NULL; .save() }
  )
})

.keyof <- function(src) {
  src <- src %||% list()
  # 前端对 dataset 源发 name，对 user 源发 id；两种都接受，统一成 "type:标识"
  id <- as.character(src$id %||% src$name %||% "")
  paste0(src$type %||% "none", ":", substr(id, 1, 64))
}

# 数据源标识（dataset 用 name，user 用 id，二者都兼容）
src_id_of <- function(src) {
  src <- src %||% list()
  as.character(src$id %||% src$name %||% "")
}

.coerce_value <- function(v, template) {
  if (is.null(v) || identical(v, "") || identical(v, "NA")) return(NA)
  # 因子列：先按字符接收，由调用方补水平（R 直接把新字符串写进因子会变成 NA）
  if (is.factor(template)) return(as.character(v))
  if (is.numeric(template)) {
    out <- suppressWarnings(as.numeric(v))
    if (is.na(out)) stop(sprintf("值 %s 无法转成数值列", as.character(v)))
    return(out)
  }
  if (is.logical(template)) {
    out <- switch(tolower(as.character(v)), true = TRUE, false = FALSE, na = NA,
                  suppressWarnings(as.logical(v)))
    if (is.null(out) || is.na(out)) stop(sprintf("值 %s 无法转成逻辑列", as.character(v)))
    return(out)
  }
  if (inherits(template, "Date")) {
    out <- suppressWarnings(as.Date(as.character(v)))
    if (is.na(out)) stop(sprintf("值 %s 无法转成日期列", as.character(v)))
    return(out)
  }
  as.character(v)
}

# 取列模板值（空列返回 NULL，交给 .coerce_value 按字符处理）
.template_of <- function(x) if (length(x)) x[[1]] else NULL

# 把新值写入因子列：必要时追加水平，避免静默变成 NA
.set_factor_cell <- function(x, i, v) {
  v <- as.character(v)
  if (!is.na(v) && !v %in% levels(x)) levels(x) <- c(levels(x), v)
  x[i] <- v
  x
}

.apply_data_edits <- function(df, ops) {
  if (!".gg_rid" %in% names(df)) {
    stop("数据缺少行锚列（.gg_rid），编辑不可用")
  }
  for (op in ops) {
    kind <- op$kind %||% ""
    if (kind == "cell") {
      col <- op$col %||% ""
      if (!col %in% names(df)) stop(sprintf("手工编辑目标列不存在: %s（可能已被改名/删除）", col))
      idx <- which(df$.gg_rid == as.numeric(op$rid))
      if (!length(idx)) stop(sprintf("编辑目标行不存在（rid=%g，可能已被删除）", as.numeric(op$rid)))
      v <- .coerce_value(op$value, .template_of(df[[col]]))
      if (is.factor(df[[col]])) df[[col]] <- .set_factor_cell(df[[col]], idx[1], v)
      else df[[col]][idx[1]] <- v
    } else if (kind == "rowDel") {
      idx <- which(df$.gg_rid == as.numeric(op$rid))
      if (!length(idx)) next  # 已删除则幂等
      df <- df[-idx, , drop = FALSE]
    } else if (kind == "rowIns") {
      vals <- op$values %||% list()
      out <- lapply(setNames(names(df), names(df)), function(col) {
        if (col == ".gg_rid") return(NA)
        v <- vals[[col]]
        if (is.null(v)) return(if (is.character(df[[col]][1])) "" else NA)
        .coerce_value(v, .template_of(df[[col]]))
      })
      # 因子列：把新行提升为同水平集的因子，否则 rbind 会报类型不匹配
      for (col in names(df)) {
        if (is.factor(df[[col]]) && !is.null(out[[col]]) && !all(is.na(out[[col]]))) {
          v <- as.character(out[[col]])
          out[[col]] <- factor(v, levels = union(levels(df[[col]]), v))
        }
      }
      new_row <- as.data.frame(out, stringsAsFactors = FALSE)
      if (!nrow(df)) {
        nrid <- 1L
      } else {
        nrid <- max(df$.gg_rid, na.rm = TRUE) + 1L
        # 同列名对齐，避免类型错乱
        new_row <- new_row[, names(df), drop = FALSE]
      }
      new_row$.gg_rid <- nrid
      df <- rbind(df, new_row)
    } else if (kind == "colRen") {
      from <- op$from %||% ""; to <- op$to %||% ""
      if (!from %in% names(df)) stop(sprintf("改名目标列不存在: %s", from))
      if (to %in% names(df) && to != from) stop(sprintf("新列名已存在: %s", to))
      names(df)[names(df) == from] <- to
    } else if (kind == "colDel") {
      col <- op$col %||% ""
      if (!col %in% names(df) || col == ".gg_rid") stop(sprintf("删除列不存在: %s", col))
      df[[col]] <- NULL
      if (ncol(df) <= 1) stop("至少保留一列")
    }
  }
  df
}

apply_data_edits <- .apply_data_edits  # 对外别名
