# Glyph - 图库（pins）：把单图 spec 存档供 patchwork 拼图复用
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
      # 先清空内存：切换到另一个（可能为空的）工作区时，
      # .load() 在文件不存在时会直接返回，不清空就会残留上一个工作区的条目。
      .pins <<- list()
      dir.create(dirname(file), showWarnings = FALSE, recursive = TRUE)
      # 缩略图/快照子目录（见 data_path / thumb_path）
      dir.create(file.path(dirname(file), "pins"), showWarnings = FALSE, recursive = TRUE)
      .load()
    },
    add = function(spec_json, label = NULL, project = NULL) {
      n <- length(.pins) + 1L
      # id 永不复用（重启后继续编号）
      n <- max(n, .pins_max_n() + 1L)
      id <- sprintf("P%d", n)
      .pins[[id]] <<- list(
        id = id,
        label = (label %||% paste0("图", n)),
        specJson = spec_json,
        project = as.character(project %||% ""),
        t = format(Sys.time(), "%m-%d %H:%M"),
        # rev：缩略图的版本号。前端把它拼进缩略图 URL（?v=rev），
        # 规格一改 rev 就变，浏览器才会重新取图 —— 否则 URL 不变，
        # 即使后端删了缓存文件、加了 no-store，浏览器也不会再发请求。
        rev = 1L
      )
      .save()
      id
    },
    remove = function(id) {
      .pins[[id]] <<- NULL
      .save()
    },
    # 覆盖更新已有条目的绘图规格（标签保持不变）
    # 返回 TRUE 表示更新成功；条目不存在返回 FALSE（调用方决定回退策略）
    # 注意：不更新 project —— 条目归属不因「编辑后保存」而改变，
    # 否则把一个无项目的共享条目改成某个项目专属后，在其他项目里就消失了。
    set_spec = function(id, spec_json) {
      if (is.null(.pins[[id]])) return(FALSE)
      .pins[[id]]$specJson <<- spec_json
      .pins[[id]]$t <<- format(Sys.time(), "%m-%d %H:%M")
      .pins[[id]]$rev <<- as.integer(.pins[[id]]$rev %||% 0L) + 1L
      .save()
      TRUE
    },
    # 只改显示名，不动 specJson / 缩略图 / project。
    # 返回 TRUE / FALSE，便于调用方区分「改了」与「条目不存在」。
    #
    # 注意必须用 <<-：`.pins[[id]]$label <- x` 在函数内会先复制一份 .pins 到本地，
    # 闭包里的原列表不会被改（R 的列表值语义）。这里此前写成 <- ，
    # 导致改名接口一直「返回成功但实际没改」。
    rename = function(id, label) {
      if (is.null(.pins[[id]])) return(FALSE)
      .pins[[id]]$label <<- label
      .save()
      TRUE
    },
    add_code = function(label, code, packages, data, renderOpts, project = NULL) {
      n <- max(length(.pins) + 1L, .pins_max_n() + 1L)
      id <- sprintf("P%d", n)
      .pins[[id]] <<- list(
        id = id, type = "code",
        label = (label %||% paste0("代码图 ", n)),
        code = list(text = as.character(code),
                    packages = as.character(packages %||% character(0))),
        data = data, renderOpts = renderOpts,
        project = as.character(project %||% ""),
        t = format(Sys.time(), "%m-%d %H:%M")
      )
      .save()
      id
    },
    # 缩略图与数据快照放在 pins/ 子目录：工作区根目录只留 pins.json，
    # 整个目录可以直接纳入版本库或打包带走，不会被一堆 P*.png 铺满。
    data_path = function(id) file.path(dirname(.file), "pins", paste0(id, ".rds")),
    thumb_path = function(id) file.path(dirname(.file), "pins", paste0(id, ".png")),
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
          project = as.character(it$project %||% ""),
          t = as.character(it$t %||% ""),
          # 缩略图版本号：前端拼进 URL 做缓存失效（老条目没有该字段，按 0 处理）
          rev = as.integer(it$rev %||% 0L),
          src = as.character(src$name %||% ""),
          srcType = as.character(src$type %||% "none"),
          layers = length((sp %||% list())$layers %||% list()),
          type = as.character(it$type %||% "spec"),
          codePackages = as.character((it$code %||% list())$packages %||% character(0)),
          dataMode = as.character((it$data %||% list())$mode %||% "")
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
