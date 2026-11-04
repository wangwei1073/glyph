# ggplotGUI - 图库（pins）：把单图 spec 存档供 patchwork 拼图复用
# spec 以原始 JSON 文本保存（避免 R↔JSON 反复穿梭时的形状歧义），
# 使用时以 simplifyVector=FALSE 解析回 R 列表。

Pins <- local({
  .pins <- list()
  .file <- NULL

  .save <- function() {
    if (is.null(.file)) return()
    txt <- jsonlite::toJSON(unname(.pins), auto_unbox = TRUE, pretty = TRUE,
                            null = "null", na = "null", digits = NA)
    write_file_atomic(txt, .file)
  }

  .load <- function() {
    if (is.null(.file) || !file.exists(.file)) return()
    obj <- tryCatch(jsonlite::fromJSON(.file, simplifyVector = FALSE),
                    error = function(e) NULL)
    if (!is.null(obj) && is.list(obj)) {
      .pins <<- obj
      # 提升回 named list（读回后是匿名列表）
      names(.pins) <<- vapply(obj, function(x) as.character(x$id %||% ""), character(1))
    }
  }

  list(
    bind = function(file) {
      .file <<- file
      dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
      .load()
    },
    add = function(spec_json, label = NULL) {
      n <- length(.pins) + 1L
      # id 永不复用（重启后继续编号）
      n <- max(n, .pins_max_n() + 1L)
      id <- sprintf("P%d", n)
      .pins[[id]] <<- list(
        id = id,
        label = (label %||% paste0("图", n)),
        specJson = spec_json,
        t = format(Sys.time(), "%m-%d %H:%M")
      )
      .save()
      id
    },
    remove = function(id) {
      .pins[[id]] <<- NULL
      .save()
    },
    rename = function(id, label) {
      if (!is.null(.pins[[id]])) {
        .pins[[id]]$label <- label
        .save()
      }
    },
    get = function(id) {
      .pins[[id]]$specJson %||% NULL
    },
    label = function(id) {
      if (is.null(.pins[[id]])) NULL else .pins[[id]]$label
    },
    list = function() {
      lapply(unname(.pins), function(it) {
        sp <- tryCatch(jsonlite::fromJSON(as.character(it$specJson %||% "{}"),
                                          simplifyVector = FALSE),
                       error = function(e) NULL)
        src <- ((sp %||% list())$data %||% list())$source %||% list()
        list(
          id = as.character(it$id),
          label = as.character(it$label %||% it$id),
          t = as.character(it$t %||% ""),
          src = as.character(src$name %||% ""),
          srcType = as.character(src$type %||% "none"),
          layers = length((sp %||% list())$layers %||% list())
        )
      })
    }
  )
})

.pins_max_n <- function() {
  ids <- names(Pins$list_full())
  m <- 0
  for (x in ids) {
    k <- suppressWarnings(as.integer(sub("^P", "", x)))
    if (!is.na(k) && k > m) m <- k
  }
  m
}
# 内部辅助：直接访问原始列表
Pins$list_full <- local({
  get_env <- environment(Pins$get)
  function() get_env$.pins
})
