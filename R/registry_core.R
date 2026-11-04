# ggplotGUI - 核心注册表：从已安装的 ggplot2 自省全部能力
# 设计：运行时枚举 geom_/stat_/scale_/coord_/position_/facet_/guide_/theme 元素，
#       与 registry_meta.R 的中文覆盖表合并后通过 /api/meta 提供给前端。
#       → 无论 ggplot2 升级到什么版本，界面能力自动同步。

GGSPEC_NS_ENV <- NULL  # 缓存命名空间，避免重复查找

.ggspec_ns <- function() {
  if (is.null(GGSPEC_NS_ENV)) GGSPEC_NS_ENV <<- asNamespace("ggplot2")
  GGSPEC_NS_ENV
}

# 在命名空间中找某一类 ggproto 对象
.ggspec_objects_of_kind <- function(kind) {
  ns <- .ggspec_ns()
  out <- list()
  for (n in ls(ns)) {
    obj <- tryCatch(get(n, envir = ns), error = function(e) NULL)
    if (!is.null(obj) && !is.function(obj) && kind %in% class(obj)) out[[n]] <- obj
  }
  out
}

# geom_* 函数 -> LayerInstance（无参调用取 geom/stat/position 对象）
.ggspec_layer_of <- function(fn) {
  f <- get(fn, envir = .ggspec_ns())
  l <- tryCatch(suppressWarnings(f()), error = function(e) NULL)
  if (!is.null(l) && inherits(l, "LayerInstance")) return(l)
  NULL
}

# 兜底：从函数体提取 geom = "xxx" 字符串，再按去符号名匹配 Geom 对象
.ggspec_geom_obj_fallback <- function(fn, geom_objs) {
  f <- get(fn, envir = .ggspec_ns())
  b <- paste(deparse(body(f)), collapse = " ")
  m <- regmatches(b, regexpr('geom\\s*=\\s*"(p_[a-z0-9_]+|[a-z0-9_]+)"', b))
  name <- if (length(m)) sub('.*"(.*?)"$', "\\1", m) else sub("^geom_", "", fn)
  key <- gsub("[^a-z0-9]", "", tolower(name))
  for (obj_name in names(geom_objs)) {
    if (gsub("[^a-z0-9]", "", tolower(sub("^Geom", "", obj_name))) == key) {
      return(geom_objs[[obj_name]])
    }
  }
  NULL
}

.ggspec_stat_name <- function(stat_obj, fn) {
  if (!is.null(stat_obj)) {
    n <- class(stat_obj)[1]
    if (n %in% c("Stat")) return("identity")
    return(tolower(gsub("([a-z0-9])([A-Z])", "\\1_\\2", sub("^Stat", "", n))))
  }
  f <- get(fn, envir = .ggspec_ns())
  as.character(formals(f)$stat %||% "identity")
}

# 参数 schema：覆盖表优先，缺省为 text
.ggspec_param_schema <- function(name, default_value = NULL) {
  w <- PARAM_WIDGETS[[name]]
  if (is.null(w)) w <- pv(name, "text")
  out <- w
  if (is.null(out$default) && !is.null(default_value) &&
      (is.character(default_value) || is.numeric(default_value) || is.logical(default_value))) {
    out$default <- default_value
  }
  out
}

.ggspec_formals_params <- function(fn, exclude = c("mapping", "data", "stat", "position",
                                                   "...", "show.legend", "inherit.aes"),
                                   pkg = "ggplot2") {
  f <- get(fn, envir = if (identical(pkg, "ggplot2")) .ggspec_ns() else asNamespace(pkg))
  fm <- formals(f)
  names <- setdiff(names(fm), exclude)
  lapply(setNames(names, names), function(nm) {
    d <- fm[[nm]]
    # 无默认值形参是 missing 标记，任何求值都会抛错 -> 用 force 探测
    miss <- tryCatch({ force(d); FALSE }, error = function(e) TRUE)
    dv <- NULL
    if (!miss && !is.symbol(d) && !is.call(d) && !is.language(d)) {
      v <- tryCatch(eval(d, envir = .ggspec_ns()), error = function(e) NULL)
      if (is.character(v) || is.numeric(v) || is.logical(v)) dv <- v
    }
    .ggspec_param_schema(nm, dv)
  })
}

.ggspec_stat_params_schema <- function(stat_obj) {
  if (is.null(stat_obj)) return(list())
  ps <- tryCatch(stat_obj$parameters(), error = function(e) character(0))
  ps <- setdiff(ps, c("flipped_aes", "..."))
  lapply(setNames(ps, ps), .ggspec_param_schema)
}

.ggspec_aes_list <- function(obj) {
  aes_all <- tryCatch(obj$aesthetics(), error = function(e) character(0))
  req <- tryCatch(as.character(obj$required_aes), error = function(e) character(0))
  req <- req[!grepl("^\\|", req)]  # 形如 "x|y" 的二选一拆开显示
  req_expanded <- unique(unlist(strsplit(req, "|", fixed = TRUE)))
  list(required = as.list(req_expanded),
       optional = as.list(setdiff(aes_all, req_expanded)))
}

# ---- 标度解析 ---------------------------------------------------------------
SCALE_AES_PREFIXES <- c("x", "y", "colour", "color", "fill", "alpha", "size",
                        "linewidth", "linetype", "shape", "radius")

.ggspec_parse_scale_fn <- function(fn) {
  rest <- sub("^scale_", "", fn)
  aes <- NULL
  for (p in SCALE_AES_PREFIXES) {
    if (startsWith(rest, paste0(p, "_"))) { aes <- p; rest <- sub(paste0("^", p, "_"), "", rest); break }
  }
  if (is.null(aes)) return(NULL)
  if (aes == "color") aes <- "colour"
  list(aes = aes, type = rest)
}

# ---- 主题元素 ---------------------------------------------------------------
.ggspec_element_type <- function(cls) {
  ns <- .ggspec_ns()
  ctors <- c("element_blank", "element_text", "element_line", "element_rect",
             "element_point", "element_polygon", "element_geom", "element_title",
             "element_margins", "element_spacing", "element_grob")
  for (e in ctors) {
    obj <- tryCatch(get(e, envir = ns), error = function(e2) NULL)
    if (!is.null(obj) && identical(obj, cls)) return(sub("^element_", "", e))
  }
  "value"
}

.ggspec_theme_elements <- function() {
  et <- tryCatch(ggplot2:::get_element_tree(), error = function(e) list())
  out <- list()
  for (nm in names(et)) {
    entry <- et[[nm]]
    type <- .ggspec_element_type(entry$class)
    inherit_raw <- entry$inherit %||% NA_character_
    inherit <- if (length(inherit_raw) != 1 || is.na(inherit_raw)) NULL else as.character(inherit_raw)
    group <- if (grepl("\\.", nm)) sub("\\..*$", "", nm) else "base"
    item <- list(name = nm, type = type, group = group,
                 label = (THEME_ELEMENT_LABELS[[nm]] %||% nm),
                 inherits = inherit)
    if (type == "value") {
      w <- THEME_VALUE_WIDGETS[[nm]]
      if (is.null(w)) {
        w <- if (grepl("margin", nm)) pv(nm, "margins")
             else if (grepl("(length|spacing)$", nm)) pv(nm, "unit")
             else pv(nm, "text")
      }
      item$widget <- w
    }
    out[[length(out) + 1]] <- item
  }
  out
}

.ggspec_theme_args <- function(fn, pkg = "ggplot2") {
  f <- get(fn, envir = if (identical(pkg, "ggplot2")) .ggspec_ns() else asNamespace(pkg))
  fm <- formals(f)
  out <- list()
  for (nm in names(fm)) {
    if (nm == "...") next
    w <- switch(nm,
      base_size = pv(nm, "number", "基础字号", min = 4, max = 48, step = 1),
      base_family = pv(nm, "text", "基础字体"),
      header_family = pv(nm, "text", "标题字体"),
      base_line_size = pv(nm, "number", "基础线宽", min = 0, step = 0.1),
      base_rect_size = pv(nm, "number", "基础边框宽", min = 0, step = 0.1),
      ink = pv(nm, "color", "墨色（前景）"),
      paper = pv(nm, "color", "纸色（背景）"),
      accent = pv(nm, "color", "强调色"),
      pv(nm, "text")
    )
    out[[length(out) + 1]] <- w
  }
  out
}

# ---- 扩展包 -----------------------------------------------------------------
GGSCI_FAMILIES <- list(
  npg = "NPG 自然出版集团", aaas = "AAAS 科学", nejm = "NEJM 医学", lancet = "Lancet",
  jama = "JAMA 医学", ucscgb = "UCSC 基因组", d3 = "D3.js 分类", locuszoom = "LocusZoom",
  igv = "IGV", uchicago = "UChicago", startrek = "Star Trek", tron = "Tron",
  futurama = "Futurama", rickandmorty = "Rick & Morty", simpsons = "Simpsons",
  frontiers = "Frontiers", glow = "Glow", higlass = "hiGlass", observable = "Observable",
  material = "Material Design"
)
GGTHEMES_THEME_LABELS <- list(
  economist = "经济学人", economist_white = "经济学人 白", wsj = "华尔街日报",
  fivethirtyeight = "FiveThirtyEight", few = "Few 简洁", excel = "Excel 经典",
  excel_new = "Excel 新版", gdocs = "Google Docs", calc = "LibreOffice Calc",
  pander = "Pander", hc = "Highcharts", solarized = "Solarized", solarized_2 = "Solarized 2",
  stata = "Stata", tufte = "Tufte 极简", igray = "极简灰", base = "基础 (base R 风)",
  solid = "纯白 solid", map = "地图 (无轴)", par = "Par", clean = "Clean",
  foundation = "Foundation"
)

.ggspec_scan_pkg_scales <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) return(list())
  fns <- grep("^scale_", getNamespaceExports(pkg), value = TRUE)
  fns <- fns[!grepl("\\.", fns)]
  out <- list()
  for (fn in fns) {
    parsed <- .ggspec_parse_scale_fn(fn)
    if (is.null(parsed)) next
    type <- parsed$type
    if (pkg == "ggsci") {
      fam <- sub("^(npg|aaas|nejm|lancet|jama|ucscgb|d3|locuszoom|igv|uchicago|startrek|tron|futurama|rickandmorty|simpsons|frontiers|glow|higlass|observable|material).*$", "\\1", type)
      label <- GGSCI_FAMILIES[[fam]] %||% fam
      label <- paste0(label, " (ggsci)")
    } else if (pkg == "ggprism") {
      # scale_color_* 是 scale_colour_* 的别名，跳过以免下拉里出现两个一样的选项
      if (startsWith(fn, "scale_color_")) next
      # ggprism 的标度共享 type="prism"，靠 aes 区分；palette 取值来自
      # ggprism_data 的命名，直接做成下拉避免用户背调色板名。
      label <- if (identical(parsed$aes, "shape")) "Prism 形状 (ggprism)" else "Prism 配色 (ggprism)"
      pals <- .ggprism_palette_names(parsed$aes)
      out[[length(out) + 1]] <- list(
        fn = fn, aes = parsed$aes, type = type, label = label, package = pkg,
        params = list(palette = pv("palette", "select", "Prism 调色板", options = as.list(pals)))
      )
      next
    } else {
      fam <- sub("^([a-z0-9_]+?)(_(c|b|d|p|gradient|continuous|discrete|manual|shape|linetype|stata|excel|tableau))?$", "\\1", type)
      fam <- sub("^(economist|wsj|fivethirtyeight|few|excel|excel_new|gdocs|calc|pander|hc|solarized|solarized_2|stata|tufte|igray|base|solid|map|par|clean|foundation|colorblind|canva|carto|ptol|flat_ui|manyeye|material|nejm|jama|ee|lh|squad|hue|grey|brewer|step).*$", "\\1", type)
      label <- paste0((GGTHEMES_THEME_LABELS[[fam]] %||% fam), " (ggthemes)")
    }
    fm <- formals(get(fn, envir = asNamespace(pkg)))
    pnames <- setdiff(names(fm), c("...", "aesthetics"))
    params <- lapply(setNames(pnames, pnames), function(nm) {
      w <- PARAM_WIDGETS[[nm]]
      (w %||% pv(nm, "text"))
    })
    out[[length(out) + 1]] <- list(
      fn = fn, aes = parsed$aes, type = type, label = label,
      package = pkg, params = params
    )
  }
  out
}

.ggspec_scan_pkg_geoms <- function(pkg, labels) {
  if (!requireNamespace(pkg, quietly = TRUE)) return(list())
  fns <- grep("^geom_", getNamespaceExports(pkg), value = TRUE)
  out <- list()
  for (fn in fns) {
    name <- sub("^geom_", "", fn)
    out[[length(out) + 1]] <- list(
      fn = fn, name = name, package = pkg,
      label = (GEOM_META[[name]]$label %||% paste0(name, " (", pkg, ")")),
      group = (GEOM_META[[name]]$group %||% "扩展"),
      desc = (GEOM_META[[name]]$desc %||% "")
    )
  }
  out
}

# ---- 扩展包通用扫描器（theme / guide / annotation） --------------------------

# ggprism 调色板名：直接读 ggprism_data，随包升级自动同步（不硬编码 110+ 个名字）
# 注意 ggprism_data 是 lazy-data，不在命名空间里，走 getExportedValue / utils::data
.ggprism_palette_names <- function(aes = "colour") {
  if (!requireNamespace("ggprism", quietly = TRUE)) return(character(0))
  d <- tryCatch(getExportedValue("ggprism", "ggprism_data"), error = function(e) NULL)
  if (!is.list(d)) {
    d <- tryCatch({
      e <- new.env()
      utils::data("ggprism_data", package = "ggprism", envir = e)
      get("ggprism_data", envir = e)
    }, error = function(e2) NULL)
  }
  if (!is.list(d)) return(character(0))
  key <- switch(aes,
    colour = "colour_palettes", color = "colour_palettes",
    fill = "fill_palettes", shape = "shape_palettes", NULL)
  if (is.null(key) || is.null(d[[key]])) return(character(0))
  names(d[[key]])
}

# theme_prism 的专用控件（palette 是 65 选 1，border/轴线角度也需要合适的控件）
.ggprism_theme_args <- function(args) {
  for (i in seq_along(args)) {
    nm <- args[[i]]$name
    if (identical(nm, "palette")) {
      args[[i]] <- pv("palette", "select", "Prism 调色板",
                      options = as.list(.ggprism_palette_names("colour")))
    } else if (identical(nm, "base_fontface")) {
      args[[i]] <- pv("base_fontface", "select", "字体样式",
                      c("plain", "bold", "italic", "bold.italic"))
    } else if (identical(nm, "axis_text_angle")) {
      args[[i]] <- pv("axis_text_angle", "number", "轴文字角度", step = 15)
    } else if (identical(nm, "border")) {
      args[[i]] <- pv("border", "bool", "显示边框")
    } else if (identical(nm, "base_size")) {
      args[[i]] <- pv("base_size", "number", "基础字号", min = 4, max = 48, step = 1)
    } else if (nm %in% c("base_line_size", "base_rect_size")) {
      args[[i]] <- pv(nm, "number", "基础线宽", min = 0, step = 0.1)
    } else if (identical(nm, "base_family")) {
      args[[i]] <- pv("base_family", "text", "基础字体")
    }
  }
  args
}

.ggspec_scan_pkg_themes <- function(pkg, labels = list()) {
  if (!requireNamespace(pkg, quietly = TRUE)) return(list())
  fns <- grep("^theme_", getNamespaceExports(pkg), value = TRUE)
  fns <- setdiff(fns, c("theme_get", "theme_set", "theme_update", "theme_replace",
                       "theme_solid_calc"))
  out <- list()
  for (fn in sort(fns)) {
    f <- tryCatch(get(fn, envir = asNamespace(pkg)), error = function(e) NULL)
    if (is.null(f) || !is.function(f)) next
    key <- sub("^theme_", "", fn)
    args <- .ggspec_theme_args(fn, pkg)
    if (identical(pkg, "ggprism") && identical(key, "prism")) args <- .ggprism_theme_args(args)
    out[[length(out) + 1]] <- list(
      name = key, fn = fn, package = pkg,
      label = paste0(labels[[key]] %||% key, " (", pkg, ")"),
      args = args
    )
  }
  out
}

.ggspec_scan_pkg_guides <- function(pkg, labels = list()) {
  if (!requireNamespace(pkg, quietly = TRUE)) return(list())
  fns <- grep("^guide_", getNamespaceExports(pkg), value = TRUE)
  fns <- fns[!grepl("\\.", fns)]
  fns <- setdiff(fns, c("guide_build", "guide_gengrob", "guide_geom", "guide_grid",
                        "guide_merge", "guide_train", "guide_transform"))
  out <- list()
  for (fn in sort(fns)) {
    name <- sub("^guide_", "", fn)
    meta <- GUIDE_META[[name]]
    p <- .ggspec_formals_params(fn, exclude = c("...", "available_aes", "position", "order"),
                                pkg = pkg)
    for (i in seq_along(p)) {
      ov <- GUIDE_PARAM_WIDGETS[[names(p)[i]]]
      if (!is.null(ov)) p[[i]] <- ov
    }
    label <- meta$label %||% paste0("guide_", name)
    out[[length(out) + 1]] <- list(
      fn = fn, name = name, package = pkg,
      label = paste0(label, " (", pkg, ")"),
      desc = meta$desc %||% "", params = p
    )
  }
  out
}

.ggspec_scan_pkg_annotations <- function(pkg) {
  if (!requireNamespace(pkg, quietly = TRUE)) return(list())
  fns <- grep("^annotation_", getNamespaceExports(pkg), value = TRUE)
  out <- list()
  for (fn in sort(fns)) {
    name <- sub("^annotation_", "", fn)
    p <- .ggspec_formals_params(fn, exclude = c("...", "data", "mapping"), pkg = pkg)
    if (identical(pkg, "ggprism") && identical(name, "ticks")) {
      p$sides <- pv("sides", "text", "边（b/l/t/r 可组合，如 bl）")
      p$type <- pv("type", "select", "刻度类型", c("both", "major", "minor"))
      p$outside <- pv("outside", "bool", "朝向图外")
      # tick.length / minor.length 需要 unit()，参数面板暂不支持（值会变成裸数字），
      # 依赖默认值 4.8pt / 2.4pt；需要自定义时走「高级模式」写代码。
      p$tick.length <- NULL
      p$minor.length <- NULL
    }
    out[[length(out) + 1]] <- list(
      fn = fn, name = name, package = pkg,
      label = paste0(ANNOTATION_META[[name]] %||% paste0("annotation_", name), " (", pkg, ")"),
      params = p
    )
  }
  out
}

# ---- 主入口 -----------------------------------------------------------------
ggspec_build_meta <- function() {
  ns <- .ggspec_ns()

  ## geom_* 函数
  geom_fns <- grep("^geom_", ls(ns), value = TRUE)
  geom_objs <- .ggspec_objects_of_kind("Geom")
  geoms <- list()
  for (fn in sort(geom_fns)) {
    layer <- .ggspec_layer_of(fn)
    geom_obj <- if (!is.null(layer)) layer$geom else .ggspec_geom_obj_fallback(fn, geom_objs)
    # 有些 geom_* 是内部工具函数（如 geom_column 取 sf 几何列名），既拿不到 LayerInstance
    # 也匹配不到 Geom 对象，不能当成 geom 列出来
    if (is.null(layer) && is.null(geom_obj)) next
    stat_obj <- if (!is.null(layer)) layer$stat else NULL
    name <- sub("^geom_", "", fn)
    meta <- GEOM_META[[name]]
    aes_info <- if (!is.null(geom_obj)) .ggspec_aes_list(geom_obj) else list(required = list("x", "y"), optional = list())
    stat_params <- .ggspec_stat_params_schema(stat_obj)
    geoms[[length(geoms) + 1]] <- list(
      fn = fn, name = name, package = "ggplot2",
      label = (meta$label %||% name), group = (meta$group %||% "其他"),
      shape = (GEOM_SHAPE[[name]] %||% "特殊"),
      desc = (meta$desc %||% ""),
      aes = aes_info,
      params = .ggspec_formals_params(fn),
      statParams = stat_params,
      defaultStat = .ggspec_stat_name(stat_obj, fn),
      defaultPosition = as.character(formals(get(fn, envir = ns))$position %||% "identity")
    )
  }
  # 扩展 geom
  for (pkg in c("ggrepel", "ggthemes")) {
    for (g in .ggspec_scan_pkg_geoms(pkg, NULL)) {
      f <- tryCatch(get(g$fn, envir = asNamespace(pkg)), error = function(e) NULL)
      if (is.null(f)) next
      layer <- tryCatch(suppressWarnings(f()), error = function(e) NULL)
      geom_obj <- if (!is.null(layer)) layer$geom else NULL
      aes_info <- if (!is.null(geom_obj)) .ggspec_aes_list(geom_obj) else list(required = list("x", "y"), optional = list())
      g$aes <- aes_info
      g$params <- lapply(setdiff(names(formals(f)), c("mapping", "data", "stat", "position", "...",
                                                      "show.legend", "inherit.aes")),
                         function(nm) PARAM_WIDGETS[[nm]] %||% pv(nm, "text"))
      g$statParams <- list()
      g$defaultStat <- if (!is.null(layer)) class(layer$stat)[1] else "identity"
      if (g$defaultStat %in% c("Stat", "StatIdentity", "ggproto", "gg")) g$defaultStat <- "identity"
      if (startsWith(g$defaultStat %||% "", "Stat")) g$defaultStat <- tolower(sub("^Stat", "", g$defaultStat))
      g$defaultPosition <- "identity"
      g$shape <- GEOM_SHAPE[[g$name]] %||% "特殊"
      geoms[[length(geoms) + 1]] <- g
    }
  }

  ## stat_*
  stat_objs <- .ggspec_objects_of_kind("Stat")
  stats <- list()
  for (obj_name in names(stat_objs)) {
    if (obj_name == "Stat") next
    name <- tolower(gsub("([a-z0-9])([A-Z])", "\\1_\\2", sub("^Stat", "", obj_name)))
    fn <- paste0("stat_", name)
    if (!exists(fn, envir = ns, inherits = FALSE)) next
    stats[[length(stats) + 1]] <- list(
      name = name, fn = fn,
      label = (STAT_META[[name]] %||% paste0("stat_", name)),
      aes = as.list(setdiff(tryCatch(stat_objs[[obj_name]]$aesthetics(), error = function(e) character(0)), "group")),
      params = .ggspec_stat_params_schema(stat_objs[[obj_name]])
    )
  }

  ## position_*
  pos_objs <- .ggspec_objects_of_kind("Position")
  positions <- list()
  for (obj_name in names(pos_objs)) {
    if (obj_name == "Position") next
    name <- tolower(gsub("([a-z0-9])([A-Z])", "\\1_\\2", sub("^Position", "", obj_name)))
    fn <- paste0("position_", name)
    if (!exists(fn, envir = ns, inherits = FALSE)) next
    meta <- POSITION_META[[name]]
    positions[[length(positions) + 1]] <- list(
      name = name, fn = fn,
      label = (meta$label %||% paste0("position_", name)),
      desc = (meta$desc %||% ""),
      params = .ggspec_formals_params(fn, exclude = c("...", "orientation"))
    )
  }

  ## coord_*
  coord_fns <- grep("^coord_", ls(ns), value = TRUE)
  coord_fns <- setdiff(coord_fns, c("coord_munch", "coord_transform"))
  coords <- list()
  for (fn in sort(coord_fns)) {
    name <- sub("^coord_", "", fn)
    meta <- COORD_META[[name]]
    coords[[length(coords) + 1]] <- list(
      fn = fn, name = name,
      label = (meta$label %||% paste0("coord_", name)),
      desc = (meta$desc %||% ""),
      params = (function() {
        p <- .ggspec_formals_params(fn, exclude = c("...", "default"))
        for (i in seq_along(p)) if (is.null(p[[i]]$widget) || p[[i]]$widget == "text") {
          ov <- COORD_PARAM_WIDGETS[[names(p)[i]]]
          if (!is.null(ov)) p[[i]] <- ov
        }
        p
      })()
    )
  }

  ## guide_*
  guide_fns <- grep("^guide_", ls(ns), value = TRUE)
  # guide_* 里混着泛型/内部方法（guide_train / guide_gengrob / guide_geom …），
  # 它们不是可选的 guide 类型，必须剔除，否则界面会列出 guide_train 这类非法选项。
  guide_fns <- guide_fns[!grepl("\\.", guide_fns)]
  guide_fns <- setdiff(guide_fns, c("guide_build", "guide_gengrob", "guide_geom", "guide_grid",
                                    "guide_merge", "guide_train", "guide_transform"))
  guides <- list()
  for (fn in sort(guide_fns)) {
    name <- sub("^guide_", "", fn)
    meta <- GUIDE_META[[name]]
    p <- .ggspec_formals_params(fn, exclude = c("...", "available_aes", "position", "order"))
    for (i in seq_along(p)) {
      ov <- GUIDE_PARAM_WIDGETS[[names(p)[i]]]
      if (!is.null(ov)) p[[i]] <- ov
    }
    guides[[length(guides) + 1]] <- list(
      fn = fn, name = name,
      label = (meta$label %||% paste0("guide_", name)),
      desc = (meta$desc %||% ""),
      params = p
    )
  }

  # 扩展 guide（ggprism: 次刻度 / 偏移轴 / 括号）
  for (pkg in c("ggprism")) {
    for (g in .ggspec_scan_pkg_guides(pkg)) guides[[length(guides) + 1]] <- g
  }

  ## scale_*（ggplot2 + ggsci + ggthemes）
  scale_fns <- grep("^scale_", ls(ns), value = TRUE)
  scale_fns <- scale_fns[!grepl("\\.", scale_fns)]
  scales <- list()
  for (fn in sort(scale_fns)) {
    parsed <- .ggspec_parse_scale_fn(fn)
    if (is.null(parsed)) next
    fm <- formals(get(fn, envir = ns))
    pnames <- setdiff(names(fm), c("...", "aesthetics"))
    params <- lapply(setNames(pnames, pnames), function(nm) {
      w <- PARAM_WIDGETS[[nm]]
      (w %||% pv(nm, "text", exprOk = nm %in% c("values", "palette", "type", "breaks", "labels", "limits", "high", "low", "mid", "midpoint", "colours", "colors", "endpoint", "rescaler")))
    })
    scales[[length(scales) + 1]] <- list(
      fn = fn, aes = parsed$aes, type = parsed$type, package = "ggplot2",
      label = (SCALE_TYPE_LABELS[[parsed$type]] %||% parsed$type),
      params = params
    )
  }
  for (pkg in c("ggsci", "ggthemes", "ggprism")) {
    for (s in .ggspec_scan_pkg_scales(pkg)) scales[[length(scales) + 1]] <- s
  }

  ## 主题
  themes <- lapply(THEME_BASE_THEMES, function(name) {
    list(name = name, fn = paste0("theme_", name),
         label = (THEME_LABELS[[name]] %||% name),
         args = .ggspec_theme_args(paste0("theme_", name)))
  })
  # ggthemes 主题
  if (requireNamespace("ggthemes", quietly = TRUE)) {
    for (fn in sort(grep("^theme_", getNamespaceExports("ggthemes"), value = TRUE))) {
      if (fn %in% c("theme_get", "theme_update", "theme_replace", "theme_solid_calc")) next
      if (!is.function(get(fn, envir = asNamespace("ggthemes")))) next
      key <- sub("^theme_", "", fn)
      themes[[length(themes) + 1]] <- list(
        name = key, fn = fn, package = "ggthemes",
        label = paste0((GGTHEMES_THEME_LABELS[[key]] %||% key), " (ggthemes)"),
        args = (function() {
          fm <- formals(get(fn, envir = asNamespace("ggthemes")))
          lapply(setdiff(names(fm), "..."), function(nm) {
            PARAM_WIDGETS[[nm]] %||% pv(nm, "text")
          })
        })()
      )
    }
  }

  # ggprism 主题（theme_prism）
  for (t in .ggspec_scan_pkg_themes("ggprism", GGPRISM_THEME_LABELS)) {
    themes[[length(themes) + 1]] <- t
  }

  ## 注释函数
  ann_fns <- grep("^annotation_", ls(ns), value = TRUE)
  annotations <- lapply(sort(ann_fns), function(fn) {
    name <- sub("^annotation_", "", fn)
    list(fn = fn, name = name,
         label = (ANNOTATION_META[[name]] %||% paste0("annotation_", name)),
         params = (function() {
           p <- .ggspec_formals_params(fn, exclude = c("...", "data", "mapping"))
           for (i in seq_along(p)) {
             ov <- PARAM_WIDGETS[[names(p)[i]]]
             if (!is.null(ov)) p[[i]] <- ov
           }
           p
         })()
    )
  })
  # 扩展注释函数（ggprism: annotation_ticks）
  for (pkg in c("ggprism")) {
    for (a in .ggspec_scan_pkg_annotations(pkg)) annotations[[length(annotations) + 1]] <- a
  }

  list(
    ggplot2Version = as.character(packageVersion("ggplot2")),
    geoms = geoms, stats = stats, positions = positions, coords = coords,
    shapeOrder = GEOM_SHAPE_ORDER,
    facets = list(
      wrap = FACET_SCHEMA$wrap, grid = FACET_SCHEMA$grid,
      labels = list(wrap = "facet_wrap 单变量序列", grid = "facet_grid 行列交叉", none = "不分面")
    ),
    guides = guides, scales = scales,
    scaleAesOrder = SCALE_AES_ORDER,
    scaleCommonParams = SCALE_COMMON_PARAMS[setdiff(names(SCALE_COMMON_PARAMS), "sec.axis")],
    themeElements = .ggspec_theme_elements(),
    themes = themes,
    themePropSchema = ELEMENT_PROP_SCHEMA,
    themeValueWidgets = list(margins = list(props = list("t", "r", "b", "l")),
                             unit = list(units = UNIT_OPTIONS)),
    themeUnitOptions = UNIT_OPTIONS,
    shapeOptions = SHAPE_OPTIONS, linetypeOptions = LINETYPE_OPTIONS,
    fonts = c("sans", "serif", "mono", "Microsoft YaHei 微软雅黑", "SimHei 黑体",
              "SimSun 宋体", "KaiTi 楷体", "DengXian 等线"),
    aesMeta = AES_META,
    annotations = annotations,
    annotateGeoms = list(),
    extensions = list(
      ggsci = requireNamespace("ggsci", quietly = TRUE),
      ggthemes = requireNamespace("ggthemes", quietly = TRUE),
      ggrepel = requireNamespace("ggrepel", quietly = TRUE),
      ggprism = requireNamespace("ggprism", quietly = TRUE),
      patchwork = requireNamespace("patchwork", quietly = TRUE),
      plotly = requireNamespace("plotly", quietly = TRUE)
    )
  )
}

# 常用 stat 的 after_stat 计算变量提示
STAT_COMPUTED <- list(
  bin = c("count", "ncount", "prop", "nprop", "ndensity", "density", "width"),
  density = c("density", "ndensity", "count", "ncount", "scaled"),
  count = c("n", "prop", "abundance"),
  summary = c("y", "ymin", "ymax"),
  smooth = c("se", "ymin", "ymax"),
  ecdf = c("ecdf", "y"),
  quantile = c("quantile"),
  `boxplot` = c("lower", "upper", "middle", "notchupper", "notchlower", "outliers"),
  y = c("y")
)

STAT_META <- list(
  bin = "分箱计数", count = "计数", density = "核密度",
  identity = "恒等（不统计）", summary = "汇总函数", smooth = "平滑拟合",
  unique = "去重", quantile = "分位数回归", qq = "QQ 抽样",
  `qq_line` = "QQ 参考线", ecdf = "经验累积分布", sf = "空间统计",
  `sf_coordinates` = "空间坐标", sum = "求和计数",
  summary_2d = "二维汇总", summary_bin = "分箱汇总", summary_hex = "六边形汇总",
  summary2d = "二维汇总（旧名）", binhex = "六边形分箱", `bin_2d` = "二维分箱",
  bin2d = "二维分箱（旧名）", contour = "等高线", contour_filled = "等高线填充",
  density_2d = "二维密度", density2d = "二维密度（旧名）",
  density2d_filled = "二维密度填充（旧名）",
  ellipse = "置信椭圆", `function` = "函数曲线",
  align = "对齐", spoke = "辐条", step = "阶梯",
  boxplot = "箱线统计", ydensity = "纵向密度", connect = "观测连线", manual = "手动值"
)

ANNOTATION_META <- list(
  logticks = "对数刻度 annotation_logticks",
  custom = "自定义 grob annotation_custom",
  map = "地图底图 annotation_map",
  raster = "图片 annotation_raster",
  ticks = "轴刻度 annotation_ticks"
)
