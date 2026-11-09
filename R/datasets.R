# Glyph - 内置数据集注册表与加载

DATASET_LABELS <- list(
  mpg = "汽车油耗测试数据", diamonds = "钻石价格数据(53k行)", economics = "美国经济时间序列",
  economics_long = "美国经济长表", faithfuld = "间歇泉二维密度", luv_colours = "颜色 LUV 坐标",
  midwest = "美国中西部县域", msleep = "哺乳动物睡眠", presidential = "美国总统任期",
  seals = "海豹移动轨迹", txhousing = "德州房价",
  mtcars = "汽车设计数据(1974)", iris = "鸢尾花", ToothGrowth = "维生素 C 与牙齿",
  PlantGrowth = "植物生长", airquality = "纽约空气质量", Orange = "橙树周长",
  sleep = "催眠药物", chickwts = "鸡饲料重量", faithful = "间歇泉喷发",
  pressure = "蒸汽压力", trees = "黑樱桃树", USArrests = "美国犯罪统计",
  quakes = "斐济地震", InsectSprays = "杀虫剂效果", warpbreaks = "织布机断线",
  DNase = "DNase 实验", CO2 = "CO2 摄取", Theoph = "茶碱药代动力学",
  Indometh = "吲哚美辛药代", ChickWeight = "雏鸡体重", npk = "NPK 肥料实验",
  Rock = "岩石渗透率", formaldehyde = "甲醛测定"
)

# 数据集清单缓存（内置数据集不会变，避免每次 /api/sources 都全量 get() 一遍）
GGSPEC_DATASET_LIST <- NULL

dataset_list <- function() {
  if (!is.null(GGSPEC_DATASET_LIST)) return(GGSPEC_DATASET_LIST)
  out <- list()
  add_ds <- function(env, pkg) {
    items <- data(package = pkg)$results[, "Item"]
    for (nm in items) {
      d <- tryCatch(get(nm, envir = as.environment(env)), error = function(e) NULL)
      if (is.null(d) || !is.data.frame(d)) next
      out[[length(out) + 1]] <<- list(
        type = "dataset", name = nm, package = pkg,
        label = (DATASET_LABELS[[nm]] %||% nm),
        nrow = nrow(d), ncol = ncol(d)
      )
    }
  }
  for (pkg in c("ggplot2", "datasets")) {
    if (requireNamespace(pkg, quietly = TRUE)) add_ds(asNamespace(pkg), pkg)
  }
  GGSPEC_DATASET_LIST <<- out
  out
}

dataset_load <- function(name) {
  for (pkg in c("ggplot2", "datasets")) {
    if (requireNamespace(pkg, quietly = TRUE)) {
      d <- tryCatch(get(name, envir = asNamespace(pkg)), error = function(e) NULL)
      if (!is.null(d) && is.data.frame(d)) return(ggspec_with_rid(as.data.frame(d)))
    }
  }
  stop(sprintf("内置数据集不存在: %s", name))
}

# 统一加载出口：追加不可见的行锚 .gg_rid（供手动编辑精确定位；不在列信息/预览中展示）
ggspec_with_rid <- function(df) {
  if (".gg_rid" %in% names(df)) return(df)
  df$.gg_rid <- seq_len(nrow(df))
  df
}

# 列信息（类型 / 预览值），供 aes 映射下拉与参数提示
column_info <- function(df, max_preview = 6) {
  out <- list()
  for (nm in names(df)) {
    if (startsWith(nm, ".gg")) next  # 内部锚列不进 UI
    x <- df[[nm]]
    type <- if (is.numeric(x)) "numeric"
            else if (inherits(x, "Date")) "date"
            else if (inherits(x, "POSIXt")) "datetime"
            else if (is.logical(x)) "logical"
            else if (is.factor(x)) "factor"
            else "character"
    if (is.numeric(x)) {
      pv_vals <- suppressWarnings(x[!is.na(x)])
      rng <- if (length(pv_vals)) c(min(pv_vals), max(pv_vals)) else c(NA, NA)
      preview <- as.list(head(format(pv_vals, trim = TRUE, digits = 6), max_preview))
    } else {
      rng <- NULL
      u <- unique(as.character(x))
      u <- u[!is.na(u)]
      preview <- as.list(head(u, max_preview))
    }
    out[[length(out) + 1]] <- list(
      name = nm, type = type,
      nMissing = sum(is.na(x)), nUnique = length(unique(x)),
      range = if (!is.null(rng)) as.list(rng) else NULL,
      preview = preview
    )
  }
  out
}
