# ggplotGUI - 元数据覆盖表（中文标签 / 分组 / 控件提示）
# 自省提供"有什么"，本表提供"怎么显示、怎么填"。

# ---- 小构造器 ---------------------------------------------------------------
gm <- function(name, label, group, desc = "") {
  list(name = name, label = label, group = group, desc = desc)
}
pv <- function(name, widget, label = NULL, options = NULL, min = NULL, max = NULL,
               step = NULL, exprOk = FALSE, desc = NULL) {
  out <- list(name = name, widget = widget, label = label %||% name)
  if (!is.null(options)) out$options <- as.list(options)
  if (!is.null(min)) out$min <- min
  if (!is.null(max)) out$max <- max
  if (!is.null(step)) out$step <- step
  if (exprOk) out$exprOk <- TRUE
  if (!is.null(desc)) out$desc <- desc
  out
}

# ---- geom 中文标签与分组 ----------------------------------------------------
# 约定：label 只用中文（R 函数名在界面 tooltip / 参数面板里显示，不占标签宽度）
GEOM_META <- list(
  gm("point",    "散点图",            "点与线",   "基础散点图 geom_point"),
  gm("jitter",   "抖动散点",          "点与线",   "带随机抖动的散点（= geom_point(position_jitter)）"),
  gm("line",     "折线图",            "点与线",   "按 x 排序的折线"),
  gm("path",     "路径图",            "点与线",   "按数据顺序连接的路径"),
  gm("step",     "阶梯线",            "点与线",   "阶梯折线"),
  gm("smooth",   "平滑曲线",          "点与线",   "回归/平滑曲线（lm/glm/gam/loess）"),
  gm("rug",      "地毯刻度",          "点与线",   "边缘地毯刻度"),
  gm("quantile", "分位数线",          "点与线",   "分位数回归拟合线"),
  gm("qq",       "QQ 图",             "点与线",   "分位数-分位数图"),
  gm("qq_line",  "QQ 参考线",         "点与线",   "QQ 图参考线"),
  gm("function", "函数曲线",          "点与线",   "绘制函数 fun(x)"),
  gm("curve",    "弧形线段",          "点与线",   "带弧度的线段（可加箭头）"),
  gm("abline",   "斜参考线",          "参考线",   "斜率截距参考线"),
  gm("hline",    "水平参考线",        "参考线",   "y = 常数水平线"),
  gm("vline",    "垂直参考线",        "参考线",   "x = 常数垂直线"),
  gm("rangeframe", "轴端框线",        "参考线",   "ggthemes：在面板边缘绘制轴线框"),
  gm("bar",      "条形图",            "条形与频数", "以高度为计数/数值的条形"),
  gm("col",      "柱状图",            "条形与频数", "列图（bar 的别名，统计变换后高度）"),
  gm("count",    "计数点图",          "条形与频数", "点大小表示观测数"),
  gm("histogram","直方图",            "条形与频数", "连续变量分箱计数"),
  gm("freqpoly", "频率多边形",        "条形与频数", "直方图的折线形式"),
  gm("dotplot",  "点须图",            "条形与频数", "堆叠小点表示频数"),
  gm("density",  "核密度曲线",        "分布",     "一维核密度估计"),
  gm("area",     "面积图",            "分布",     "折线下方填充"),
  gm("boxplot",  "箱线图",            "分布",     "五数概括 + 异常值"),
  gm("violin",   "小提琴图",          "分布",     "密度曲线镜像"),
  gm("tufteboxplot", "Tufte 箱线图",  "分布",     "ggthemes：Tufte 极简箱线图"),
  gm("crossbar", "箱线须",            "区间与误差", "宽线箱 + 中线 + 须"),
  gm("errorbar", "误差条",            "区间与误差", "竖直误差条"),
  gm("errorbarh","横向误差条",        "区间与误差", "水平误差条"),
  gm("pointrange","点区间",           "区间与误差", "点 + 线区间"),
  gm("linerange","线区间",            "区间与误差", "竖直线段区间"),
  gm("ribbon",   "缎带区间",          "区间与误差", "上下界之间的填充带"),
  gm("text",     "文本",              "文本与标签", "在坐标处绘制文字"),
  gm("label",    "标签框",            "文本与标签", "带背景框的文字"),
  gm("text_repel",   "防重叠文本",    "文本与标签", "ggrepel：自动避让的文本"),
  gm("label_repel",  "防重叠标签框",  "文本与标签", "ggrepel：自动避让的标签"),
  gm("marquee_repel","富文本防重叠",  "文本与标签", "ggrepel：支持 markdown 的自动避让标签"),
  gm("bin_2d",   "二维分箱",          "二维分箱与密度", "矩形分箱计数热力"),
  gm("bin2d",    "二维分箱（旧名）",  "二维分箱与密度", "geom_bin_2d 的旧别名"),
  gm("hex",      "六边形分箱",        "二维分箱与密度", "六边形分箱计数"),
  gm("density_2d",        "二维密度线",       "二维分箱与密度", "二维核密度等高线"),
  gm("density_2d_filled", "二维密度填充",     "二维分箱与密度", "二维核密度填充等高线"),
  gm("density2d",         "二维密度线（旧名）",  "二维分箱与密度", "geom_density_2d 的旧别名"),
  gm("density2d_filled",  "二维密度填充（旧名）", "二维分箱与密度", "geom_density_2d_filled 的旧别名"),
  gm("contour",           "等高线",          "二维分箱与密度", "三维数据的等高线"),
  gm("contour_filled",    "等高线填充",      "二维分箱与密度", "填充式等高线"),
  gm("tile",     "瓦片图",            "瓦片与栅格", "矩形瓦片（热力图）"),
  gm("raster",   "栅格图",            "瓦片与栅格", "等距瓦片栅格"),
  gm("rect",     "矩形",              "瓦片与栅格", "xmin/xmax/ymin/ymax 矩形"),
  gm("polygon",  "多边形",            "多边形与地图", "填充多边形"),
  gm("map",      "地图",              "多边形与地图", "配合 map_data() 绘制地图"),
  gm("sf",       "空间数据",          "多边形与地图", "绘制 sf 空间对象"),
  gm("sf_label", "空间标签",          "多边形与地图", "sf 对象上的标签"),
  gm("sf_text",  "空间文本",          "多边形与地图", "sf 对象上的文本"),
  gm("segment",  "线段",              "特殊",     "(x,y) 到 (xend,yend) 的线段"),
  gm("spoke",    "辐条",              "特殊",     "带角度长度的辐条"),
  gm("blank",    "空白占位",          "特殊",     "什么都不画（占位/影响标度）"),

  # ---- 扩展包 geom（第一批）------------------------------------------------
  # ggbeeswarm：蜂群图，算法避让重叠点（比 jitter 的随机抖动更规整）
  gm("beeswarm",     "蜂群图",        "点与线",   "ggbeeswarm：按算法错开重叠的点"),
  gm("quasirandom",  "准随机散点",    "点与线",   "ggbeeswarm：类蜂群的准随机排布"),
  # ggtext：富文本标签，支持 markdown/HTML 片段
  gm("richtext",     "富文本标签",    "文本与标签", "ggtext：支持 <b>/<i>/<span> 样式的文本"),
  gm("textbox",      "富文本框",      "文本与标签", "ggtext：带换行与样式文本框"),
  # ggpubr：统计标注图层（追加图层，而非 stat= 参数）
  gm("signif",       "显著性标注",    "区间与误差", "ggpubr：自动计算并标注组间显著性"),
  gm("bracket",      "显著性括号",    "区间与误差", "ggpubr：两组或多组括号标注"),
  gm("pwc",          "成对比较",      "区间与误差", "ggpubr：两两比较并标注 p 值"),
  gm("exec",         "表达式标注",    "文本与标签", "ggpubr：执行 R 表达式后标注结果"),

  # ---- 第二批 ----
  # ggstats：比例与 Likert 类统计图（数据需长表：每行一个观测）
  gm("prop_bar",         "比例条",        "条形与频数", "ggstats：按组归一化的百分比堆叠条"),
  gm("prop_text",        "比例文字",      "文本与标签", "ggstats：比例条上的百分比标签"),
  gm("prop_connector",   "比例连接线",    "特殊",     "ggstats：连接比例条的引导线"),
  gm("likert",           "Likert 图",     "条形与频数", "ggstats：李克特量表双向堆叠条（需 position_likert）"),
  gm("likert_text",      "Likert 文字",   "文本与标签", "ggstats：Likert 图上的百分比标签"),
  gm("diverging",        "双向条形",      "条形与频数", "ggstats：以中点为基线的双向条"),
  gm("diverging_text",   "双向文字",      "文本与标签", "ggstats：双向条上的标签"),
  gm("pyramid",          "金字塔图",      "条形与频数", "ggstats：人口金字塔式背靠背条"),
  gm("pyramid_text",     "金字塔文字",    "文本与标签", "ggstats：金字塔图上的标签"),
  gm("bar_connector",    "条形连接线",    "特殊",     "ggstats：条形之间的连接线"),
  gm("connector",        "连接线",        "特殊",     "ggstats：分段之间的连接线"),
  gm("stripped_cols",    "分组底纹（列）", "瓦片与栅格", "ggstats：按分组交替底纹的列背景"),
  gm("stripped_rows",    "分组底纹（行）", "瓦片与栅格", "ggstats：按分组交替底纹的行背景"),
  # ggridges：山脊图系列
  gm("ridgeline",             "山脊线",    "分布", "ggridges：单条山脊密度曲线"),
  gm("ridgeline_gradient",    "山脊线（渐变）", "分布", "ggridges：按值渐变着色的山脊线"),
  gm("density_ridges",        "山脊密度",  "分布", "ggridges：多组密度曲线叠加排列"),
  gm("density_ridges2",       "山脊密度（闭合）", "分布", "ggridges：底边闭合的密度曲线"),
  gm("density_ridges_gradient","山脊密度（渐变）", "分布", "ggridges：按 x 值渐变着色的密度曲线"),
  gm("density_line",          "密度线",    "分布", "ggridges：仅画线不填充的密度"),
  gm("vridgeline",            "纵向山脊线", "分布", "ggridges：沿 y 轴方向的密度曲线"),
  # ggh4x：几何增强
  gm("pointpath",     "点路径",      "点与线",   "ggh4x：按顺序连接的点，路径更清晰"),
  gm("outline_point", "描边点",      "点与线",   "ggh4x：带描边的点（异色边）"),
  gm("text_aimed",    "定向文字",    "文本与标签", "ggh4x：自动朝向的文字"),
  gm("box",           "箱形框",      "区间与误差", "ggh4x：xmin/xmax/ymin/ymax 箱形"),
  gm("tilemargin",    "瓦片边距",    "瓦片与栅格", "ggh4x：贴边的瓦片（边际图用）"),
  gm("rectmargin",    "矩形边距",    "瓦片与栅格", "ggh4x：贴边的矩形"),
  gm("polygonraster", "多边形栅格",  "瓦片与栅格", "ggh4x：以多边形方式绘制栅格"),

  # ---- 第三批 ----
  # ggdist：分布与不确定性（x 为分布值，或配合 y 形成半小提琴/雨云图）
  gm("slab",          "分布区间（半小提琴）", "分布", "ggdist：半小提琴式的分布形态"),
  gm("slabinterval",  "分布区间（复合）", "分布", "ggdist：分布形态 + 区间 + 点估计"),
  gm("interval",      "区间",        "区间与误差", "ggdist：点估计与不确定区间"),
  gm("pointinterval", "点区间",      "区间与误差", "ggdist：点 + 区间"),
  gm("dots",          "点阵（蜂群）", "分布", "ggdist：每个观测一个点，自动避开"),
  gm("dotsinterval",  "点阵区间",    "分布", "ggdist：点阵 + 区间"),
  gm("swarm",         "自适应点阵",  "分布", "ggdist：按可用空间自适应的点阵"),
  gm("blur_dots",     "模糊点阵",    "分布", "ggdist：重叠时自动模糊的点阵"),
  gm("spike",         "尖峰",        "分布", "ggdist：以尖峰表示概率质量"),
  gm("weave",         "编织线",      "点与线", "ggdist：观测之间的编织连线"),
  gm("lineribbon",    "线 + 缎带",   "区间与误差", "ggdist：多条区间叠加的线缎带"),
  # ggforce：几何扩展（多为专用坐标参数，非标准 x/y）
  gm("circle",        "圆形",        "特殊",   "ggforce：以 x0/y0/r 定义圆"),
  gm("ellipse",       "椭圆",        "特殊",   "ggforce：以 x0/y0/a/b/angle 定义椭圆"),
  gm("arc",           "弧线",        "特殊",   "ggforce：圆弧"),
  gm("arc_bar",       "弧形条",      "特殊",   "ggforce：极坐标下的弧形条（饼图/玫瑰图）"),
  gm("sina",          "Sina 散点",   "点与线", "ggforce：带抖动幅度的散点（保持分布形状）"),
  gm("link",          "连接线",      "点与线", "ggforce：两点之间的连线（可带弧度）"),
  gm("bezier",        "贝塞尔曲线",  "点与线", "ggforce：二次/三次贝塞尔曲线"),
  gm("bspline",       "B 样条",      "点与线", "ggforce：平滑样条曲线"),
  gm("spiro",         "螺线",        "特殊",   "ggforce：内摆线/外摆线"),
  gm("shape",         "自定义图形",  "特殊",   "ggforce：支持任意图形（星形、心形等）"),
  gm("voronoi_tile",  "泰森多边形",  "多边形与地图", "ggforce：Voronoi 镶嵌"),
  gm("voronoi_segment","泰森边",     "多边形与地图", "ggforce：Voronoi 边界线"),
  gm("delaunay_tile", "Delaunay 三角", "多边形与地图", "ggforce：Delaunay 三角剖分"),
  gm("delaunay_segment","Delaunay 边", "多边形与地图", "ggforce：三角剖分边界"),
  gm("mark_hull",     "轮廓标注",    "文本与标签", "ggforce：圈出数据轮廓并标注"),
  gm("mark_circle",   "圆形标注",    "文本与标签", "ggforce：圆圈标注区域"),
  gm("mark_ellipse",  "椭圆标注",    "文本与标签", "ggforce：椭圆标注区域"),
  gm("mark_rect",     "矩形标注",    "文本与标签", "ggforce：矩形标注区域"),
  gm("mark_regon",    "区域标注",    "文本与标签", "ggforce：任意形状区域标注"),
  gm("regon",         "区域",        "多边形与地图", "ggforce：由数据点围成的区域"),
  gm("parallel_sets", "平行集",      "特殊",   "ggforce：多分类变量的平行集图"),
  gm("parallel_sets_axes","平行集轴", "特殊",  "ggforce：平行集的坐标轴"),
  gm("parallel_sets_labels","平行集标签","文本与标签", "ggforce：平行集的类别标签"),
  gm("diagonal",      "对角网格",    "特殊",   "ggforce：对角线方向的分格"),
  gm("diagonal_wide", "对角网格（宽）", "特殊", "ggforce：宽对角线分格"),
  gm("autopoint",     "自动点",      "点与线", "ggforce：为 facet_matrix 自动定位"),
  gm("autodensity",   "自动密度",    "分布",   "ggforce：为 facet_matrix 自动定位的密度"),
  gm("autohistogram", "自动直方",    "分布",   "ggforce：为 facet_matrix 自动定位的直方图")
)
GEOM_META <- setNames(GEOM_META, vapply(GEOM_META, function(x) x$name, character(1)))

# ---- ggside 的 36 个边际 geom：模式高度规整，程序化生成标签 ----------------
# 命名规则：xside/yside + geom 类型（histogram/density/boxplot/violin/…）
# 36 条手写既冗长又易错，这里按「侧 + 类型」组合生成，缺项自动跳过。
GG_SIDE_GEOM <- local({
  side_label <- c(xside = "X 轴边际", yside = "Y 轴边际")
  kind_label <- c(
    histogram = "直方图", density = "密度曲线", boxplot = "箱线图", violin = "小提琴图",
    point = "散点", line = "折线", bar = "条形", col = "柱状", tile = "瓦片",
    text = "文本", label = "标签", path = "路径", segment = "线段", hline = "水平线",
    vline = "垂直线", abline = "参考线", `function` = "函数曲线", freqpoly = "频率多边形"
  )
  out <- list()
  for (sd in names(side_label)) {
    for (kd in names(kind_label)) {
      nm <- paste0(sd, kd)
      out[[nm]] <- gm(nm, paste0(side_label[[sd]], "·", kind_label[[kd]]), "边际分布",
                      sprintf("ggside：在 %s 绘制 %s", substr(side_label[[sd]], 1, 1), kind_label[[kd]]))
    }
  }
  out
})
for (nm in names(GG_SIDE_GEOM)) {
  if (is.null(GEOM_META[[nm]])) GEOM_META[[nm]] <- GG_SIDE_GEOM[[nm]]
}

GEOM_GROUP_ORDER <- c("点与线", "条形与频数", "分布", "区间与误差", "文本与标签",
                      "二维分箱与密度", "瓦片与栅格", "多边形与地图", "边际分布", "参考线", "特殊")

# ---- 数据形态分组（cheatsheet 式：按「你手上是什么数据」分类） --------------
# 界面可在「按图形族 / 按数据形态」之间切换；每个 geom 只归入一类，保证列表不重复。
GEOM_SHAPE_ORDER <- c(
  "一变量 · 连续", "一变量 · 离散",
  "两变量 · 连续×连续", "两变量 · 离散×连续", "两变量 · 离散×离散",
  "二维分布（双连续）", "三变量", "区间与误差",
  "图形基元", "地图与空间", "边际分布", "特殊"
)
GEOM_SHAPE <- c(
  # 一变量
  histogram = "一变量 · 连续", density = "一变量 · 连续", freqpoly = "一变量 · 连续",
  dotplot = "一变量 · 连续", qq = "一变量 · 连续", qq_line = "一变量 · 连续",
  bar = "一变量 · 离散",
  # 两变量
  point = "两变量 · 连续×连续", jitter = "两变量 · 连续×连续", line = "两变量 · 连续×连续",
  step = "两变量 · 连续×连续", smooth = "两变量 · 连续×连续", quantile = "两变量 · 连续×连续",
  rug = "两变量 · 连续×连续", area = "两变量 · 连续×连续", text = "两变量 · 连续×连续",
  label = "两变量 · 连续×连续", text_repel = "两变量 · 连续×连续",
  label_repel = "两变量 · 连续×连续", marquee_repel = "两变量 · 连续×连续",
  col = "两变量 · 离散×连续", boxplot = "两变量 · 离散×连续", violin = "两变量 · 离散×连续",
  tufteboxplot = "两变量 · 离散×连续",
  count = "两变量 · 离散×离散",
  # 二维分布 / 三变量
  bin_2d = "二维分布（双连续）", bin2d = "二维分布（双连续）", hex = "二维分布（双连续）",
  density_2d = "二维分布（双连续）", density_2d_filled = "二维分布（双连续）",
  density2d = "二维分布（双连续）", density2d_filled = "二维分布（双连续）",
  contour = "三变量", contour_filled = "三变量", tile = "三变量", raster = "三变量",
  # 区间与误差
  crossbar = "区间与误差", errorbar = "区间与误差", errorbarh = "区间与误差",
  pointrange = "区间与误差", linerange = "区间与误差", ribbon = "区间与误差",
  # 图形基元（只吃坐标，不吃数据）
  curve = "图形基元", path = "图形基元", polygon = "图形基元", rect = "图形基元",
  segment = "图形基元", spoke = "图形基元", abline = "图形基元", hline = "图形基元",
  vline = "图形基元", `function` = "图形基元",
  # 地图与空间
  map = "地图与空间", sf = "地图与空间", sf_label = "地图与空间", sf_text = "地图与空间",
  # 扩展包（第一批）
  beeswarm = "两变量 · 离散×连续", quasirandom = "两变量 · 离散×连续",
  richtext = "两变量 · 连续×连续", textbox = "两变量 · 连续×连续",
  signif = "区间与误差", bracket = "区间与误差", pwc = "区间与误差", exec = "文本与标签",
  # 扩展包（第二批）
  prop_bar = "两变量 · 离散×离散", prop_text = "两变量 · 离散×离散",
  prop_connector = "两变量 · 离散×离散",
  likert = "两变量 · 离散×离散", likert_text = "两变量 · 离散×离散",
  diverging = "两变量 · 离散×连续", diverging_text = "两变量 · 离散×连续",
  pyramid = "两变量 · 离散×连续", pyramid_text = "两变量 · 离散×连续",
  bar_connector = "图形基元", connector = "图形基元",
  stripped_cols = "特殊", stripped_rows = "特殊",
  ridgeline = "一变量 · 连续", ridgeline_gradient = "一变量 · 连续",
  density_ridges = "一变量 · 连续", density_ridges2 = "一变量 · 连续",
  density_ridges_gradient = "一变量 · 连续", density_line = "一变量 · 连续",
  vridgeline = "一变量 · 连续",
  pointpath = "两变量 · 连续×连续", outline_point = "点与线",
  text_aimed = "文本与标签", box = "图形基元",
  tilemargin = "三变量", rectmargin = "图形基元", polygonraster = "三变量",
  # 扩展包（第三批）
  slab = "一变量 · 连续", slabinterval = "一变量 · 连续", interval = "区间与误差",
  pointinterval = "区间与误差", dots = "两变量 · 离散×连续",
  dotsinterval = "两变量 · 离散×连续", swarm = "两变量 · 离散×连续",
  blur_dots = "两变量 · 离散×连续", spike = "一变量 · 连续", weave = "图形基元",
  lineribbon = "区间与误差",
  circle = "特殊", ellipse = "特殊", arc = "特殊", arc_bar = "特殊",
  sina = "两变量 · 离散×连续", link = "点与线", bezier = "图形基元",
  bspline = "图形基元", spiro = "特殊", shape = "特殊",
  voronoi_tile = "多边形与地图", voronoi_segment = "多边形与地图",
  delaunay_tile = "多边形与地图", delaunay_segment = "多边形与地图",
  mark_hull = "文本与标签", mark_circle = "文本与标签", mark_ellipse = "文本与标签",
  mark_rect = "文本与标签", mark_regon = "文本与标签", regon = "多边形与地图",
  parallel_sets = "特殊", parallel_sets_axes = "特殊", parallel_sets_labels = "文本与标签",
  diagonal = "特殊", diagonal_wide = "特殊",
  autopoint = "点与线", autodensity = "一变量 · 连续", autohistogram = "一变量 · 连续",
  # 特殊
  blank = "特殊", rangeframe = "特殊"
)
# ggside 的边际 geom 统一归入「边际分布」数据形态
for (nm in names(GG_SIDE_GEOM)) GEOM_SHAPE[[nm]] <- "边际分布"

# ---- 美学映射元数据 ---------------------------------------------------------
AES_META <- list(
  list(name = "x",         label = "x",         kind = "position", desc = "横轴位置"),
  list(name = "y",         label = "y",         kind = "position", desc = "纵轴位置"),
  list(name = "colour",    label = "colour 颜色", kind = "color",  desc = "描边/点线颜色"),
  list(name = "fill",      label = "fill 填充",   kind = "color",  desc = "填充颜色"),
  list(name = "size",      label = "size 大小",   kind = "number", desc = "点/文字大小"),
  list(name = "linewidth", label = "linewidth 线宽", kind = "number", desc = "线宽/描边宽"),
  list(name = "shape",     label = "shape 形状",  kind = "shape",  desc = "点形状 (0-25)"),
  list(name = "linetype",  label = "linetype 线型", kind = "linetype", desc = "线型"),
  list(name = "alpha",     label = "alpha 透明度", kind = "number", desc = "透明度 0-1"),
  list(name = "stroke",    label = "stroke 描边宽", kind = "number", desc = "点描边宽度"),
  list(name = "label",     label = "label 文本",  kind = "text",   desc = "文字内容"),
  list(name = "angle",     label = "angle 角度",  kind = "number", desc = "旋转角度"),
  list(name = "hjust",     label = "hjust 水平对齐", kind = "number", desc = "0=左 0.5=中 1=右"),
  list(name = "vjust",     label = "vjust 垂直对齐", kind = "number", desc = "0=下 0.5=中 1=上"),
  list(name = "family",    label = "family 字体", kind = "text",   desc = "字体族"),
  list(name = "lineheight",label = "lineheight 行距", kind = "number", desc = "行距倍数"),
  list(name = "radius",    label = "radius 半径", kind = "number", desc = "六边形半径"),
  list(name = "weight",    label = "weight 权重", kind = "number", desc = "统计权重"),
  list(name = "sample",    label = "sample 抽样", kind = "number", desc = "stat_sample"),
  list(name = "subgroup",  label = "subgroup 子组", kind = "auto",  desc = "stat_density 子分组"),
  list(name = "xmin",      label = "xmin",      kind = "position", desc = "矩形/瓦片左界"),
  list(name = "xmax",      label = "xmax",      kind = "position", desc = "矩形/瓦片右界"),
  list(name = "ymin",      label = "ymin",      kind = "position", desc = "矩形/缎带下界"),
  list(name = "ymax",      label = "ymax",      kind = "position", desc = "矩形/缎带上界"),
  list(name = "xend",      label = "xend",      kind = "position", desc = "线段终点 x"),
  list(name = "yend",      label = "yend",      kind = "position", desc = "线段终点 y"),
  list(name = "alt",       label = "alt 替代文本", kind = "text",  desc = "无障碍替代文本"),
  list(name = "order",     label = "order 排序", kind = "number", desc = "绘制顺序"),
  list(name = "group",     label = "group 分组", kind = "auto",   desc = "分组变量")
)

# ---- 参数控件提示（按参数名匹配；未命中默认 text） --------------------------
PARAM_WIDGETS <- list(
  alpha       = pv("alpha", "number", "透明度", min = 0, max = 1, step = 0.05),
  size        = pv("size", "number", "大小", min = 0, step = 0.1),
  stroke      = pv("stroke", "number", "描边宽", min = 0, step = 0.1),
  linewidth   = pv("linewidth", "number", "线宽", min = 0, step = 0.1),
  shape       = pv("shape", "shape", "形状"),
  linetype    = pv("linetype", "linetype", "线型"),
  colour      = pv("colour", "color", "颜色"),
  color       = pv("color", "color", "颜色"),
  fill        = pv("fill", "color", "填充"),
  colour20    = pv("colour20", "color", "颜色"),
  width       = pv("width", "number", "宽度", min = 0, step = 0.05),
  height      = pv("height", "number", "高度", min = 0, step = 0.05),
  binwidth    = pv("binwidth", "number", "组距", min = 0, step = 0.5, exprOk = TRUE),
  bins        = pv("bins", "number", "分箱数", min = 1, step = 1),
  boundary    = pv("boundary", "number", "边界值", exprOk = TRUE),
  center      = pv("center", "number", "中心值", exprOk = TRUE),
  pad         = pv("pad", "bool", "首尾补零"),
  closed      = pv("closed", "select", "区间闭合", c("left", "right")),
  na.rm       = pv("na.rm", "bool", "忽略缺失值"),
  show.legend = pv("show.legend", "bool", "显示图例"),
  inherit.aes = pv("inherit.aes", "bool", "继承全局 aes"),
  se          = pv("se", "bool", "显示置信区间"),
  method      = pv("method", "select", "平滑方法",
                   c("auto", "lm", "glm", "gam", "loess", "rlm", "mass"), exprOk = TRUE),
  formula     = pv("formula", "text", "公式", exprOk = TRUE),
  span        = pv("span", "number", "平滑跨度", min = 0, max = 1, step = 0.05),
  n           = pv("n", "number", "采样点数", min = 2, step = 1),
  fullrange   = pv("fullrange", "bool", "拟合延伸到全范围"),
  level       = pv("level", "number", "置信水平", min = 0, max = 1, step = 0.01),
  orientation = pv("orientation", "select", "方向", c("x", "y")),
  just        = pv("just", "number", "对齐位置", min = 0, max = 1, step = 0.05),
  lineend     = pv("lineend", "select", "线端样式", c("butt", "round", "square")),
  linejoin    = pv("linejoin", "select", "折角样式", c("mitre", "round", "bevel")),
  linemitre   = pv("linemitre", "number", "斜接限制", min = 1, step = 1),
  arrow       = pv("arrow", "select", "箭头", c("无", "单端 arrow()", "两端 arrow(ends=\"both\")"),
                   exprOk = TRUE),
  flatten     = pv("flatten", "bool", "压平堆叠"),
  adjust      = pv("adjust", "number", "带宽倍数", min = 0, step = 0.1),
  kernel      = pv("kernel", "select", "核函数",
                   c("gaussian", "epanechnikov", "rectangular", "triangular", "biweight",
                     "cosine", "optcosine")),
  ncol        = pv("ncol", "number", "点须列数", min = 1, step = 1),
  scale       = pv("scale", "select", "面积缩放", c("area", "count", "width")),
  varwidth    = pv("varwidth", "bool", "宽度正比样本量"),
  notch       = pv("notch", "bool", "带凹槽"),
  notchwidth  = pv("notchwidth", "number", "凹槽宽度", step = 0.05),
  staplewidth = pv("staplewidth", "number", "端帽宽度", step = 0.05),
  outliers    = pv("outliers", "bool", "显示离群点", exprOk = TRUE),
  outlier.colour  = pv("outlier.colour", "color", "离群点颜色"),
  outlier.fill    = pv("outlier.fill", "color", "离群点填充"),
  outlier.shape   = pv("outlier.shape", "shape", "离群点形状"),
  outlier.size    = pv("outlier.size", "number", "离群点大小"),
  outlier.stroke  = pv("outlier.stroke", "number", "离群点描边"),
  outlier.alpha   = pv("outlier.alpha", "number", "离群点透明度", min = 0, max = 1, step = 0.05),
  funnel      = pv("funnel", "bool", "漏斗模式"),
  funnel.min  = pv("funnel.min", "number", "漏斗下限", step = 0.05),
  funnel.max  = pv("funnel.max", "number", "漏斗上限", step = 0.05),
  fun.args    = pv("fun.args", "text", "额外参数（R 表达式）", exprOk = TRUE),
  fun         = pv("fun", "text", "函数（R 表达式）", exprOk = TRUE),
  fun.y       = pv("fun.y", "text", "y 函数（R 表达式）", exprOk = TRUE),
  fun.ymin    = pv("fun.ymin", "text", "ymin 函数", exprOk = TRUE),
  fun.ymax    = pv("fun.ymax", "text", "ymax 函数", exprOk = TRUE),
  fun.data    = pv("fun.data", "text", "汇总函数（R 表达式）", exprOk = TRUE),
  geom        = pv("geom", "text", "底层 geom", exprOk = TRUE),
  position    = pv("position", "text", "位置调整", exprOk = TRUE),
  draw_quantiles = pv("draw_quantiles", "text", "分位数（如 c(0.25,0.5,0.75)）", exprOk = TRUE),
  trim        = pv("trim", "bool", "裁剪到数据范围"),
  tails       = pv("tails", "bool", "保留尾部"),
  bounds      = pv("bounds", "text", "取值范围 c(lo,hi)", exprOk = TRUE),
  na.value    = pv("na.value", "text", "缺失值样式", exprOk = TRUE),
  hexpand     = pv("hexpand", "number", "水平扩展", step = 0.05),
  vexpand     = pv("vexpand", "number", "垂直扩展", step = 0.05),
  quantiles   = pv("quantiles", "text", "分位数向量", exprOk = TRUE),
  distribution= pv("distribution", "text", "理论分布（如 qnorm）", exprOk = TRUE),
  dparams     = pv("dparams", "text", "分布参数", exprOk = TRUE),
  abstol      = pv("abstol", "number", "容差", step = 0.001),
  max_fdel    = pv("max_fdel", "number", "密度导数上限", step = 0.01),
  boxwidth    = pv("boxwidth", "number", "箱宽", min = 0, step = 0.05),
 .whisker     = pv(".whisker", "number", "须宽", step = 0.05),
  map         = pv("map", "text", "地图数据（data.frame）", exprOk = TRUE),
  curvature   = pv("curvature", "number", "曲率", step = 0.1),
  angle       = pv("angle", "number", "角度", step = 5),
  ncp         = pv("ncp", "number", "曲线控制点数", step = 1),
  segment.colour = pv("segment.colour", "color", "引线颜色"),
  segment.size   = pv("segment.size", "number", "引线宽度", step = 0.1),
  segment.alpha  = pv("segment.alpha", "number", "引线透明度", min = 0, max = 1, step = 0.05),
  segment.linetype = pv("segment.linetype", "linetype", "引线线型"),
  box.padding  = pv("box.padding", "number", "标签边距", step = 0.01),
  point.padding= pv("point.padding", "number", "点边距", step = 0.01),
  min.segment.length = pv("min.segment.length", "number", "最短引线", step = 0.1),
  force       = pv("force", "number", "斥力", step = 0.5),
  force_pull  = pv("force_pull", "number", "回拉力", step = 0.5),
  max.overlaps= pv("max.overlaps", "number", "最大重叠数", step = 1),
  max.iter    = pv("max.iter", "number", "迭代次数", step = 100),
  direction   = pv("direction", "select", "方向", c("both", "x", "y")),
  seed        = pv("seed", "number", "随机种子", step = 1),
  stat        = pv("stat", "text", "统计变换", exprOk = TRUE),
  inside      = pv("inside", "bool", "画在内部"),
  xnullable   = pv("xnullable", "bool", "x 可为缺失"),
  ynullable   = pv("ynullable", "bool", "y 可为缺失"),
  keep         = pv("keep", "text", "保留的参数", exprOk = TRUE),
  controllist  = pv("controllist", "text", "控制参数", exprOk = TRUE)
)

# ---- 位置调整 ---------------------------------------------------------------
POSITION_META <- list(
  gm("identity",     "不调整",           "位置调整", "原样绘制"),
  gm("dodge",        "并列",             "位置调整", "按分组并列"),
  gm("dodge2",       "并列（自适应）",   "位置调整", "自动适配宽度的并列"),
  gm("stack",        "堆叠",             "位置调整", "按分组堆叠"),
  gm("fill",         "百分比堆叠",       "位置调整", "堆叠并归一化到 1"),
  gm("jitter",       "抖动",             "位置调整", "随机抖动"),
  gm("jitterdodge",  "抖动并列",         "位置调整", "点图专用：抖动 + 并列"),
  gm("nudge",        "微移",             "位置调整", "固定偏移"),
  # 扩展 position
  gm("beeswarm",     "蜂群排列",         "位置调整", "ggbeeswarm：按算法错开重叠点"),
  gm("quasirandom",  "准随机排列",       "位置调整", "ggbeeswarm：准随机错开"),
  gm("rescale",      "重标定",           "位置调整", "ggside：边际图层的比例重标"),
  gm("likert",       "Likert 居中",      "位置调整", "ggstats：以中点为基线双向堆叠"),
  gm("diverging",    "双向发散",         "位置调整", "ggstats：按中位数发散排列")
)

POSITION_META <- setNames(POSITION_META, vapply(POSITION_META, function(x) x$name, character(1)))

# ---- 坐标系 -----------------------------------------------------------------
COORD_META <- list(
  gm("cartesian", "笛卡尔",           "坐标系", "标准坐标系（含裁剪/扩展/反转控制）"),
  gm("fixed",     "固定比例",         "坐标系", "固定纵横比（1:1 等）"),
  gm("flip",      "翻转（已废弃）",   "坐标系", "交换 x/y 轴（4.0 建议改为交换映射）"),
  gm("polar",     "极坐标",           "坐标系", "饼图/环形图/玫瑰图"),
  gm("radial",    "径向",             "坐标系", "4.0 新版径向坐标"),
  gm("quickmap",  "快速地图",         "坐标系", "等距圆柱投影（粗略）"),
  gm("map",       "地图投影",         "坐标系", "mapproj 投影"),
  gm("sf",        "空间坐标",         "坐标系", "sf 空间数据坐标系"),
  gm("trans",     "变换",             "坐标系", "对轴做非线性变换"),
  gm("transform", "变换（底层）",     "坐标系", "trans 的底层版本"),
  gm("equal",     "等比例",           "坐标系", "coord_fixed 别名")
)
COORD_META <- setNames(COORD_META, vapply(COORD_META, function(x) x$name, character(1)))

COORD_PARAM_WIDGETS <- list(
  xlim      = pv("xlim", "text", "x 范围 c(min,max)", exprOk = TRUE),
  ylim      = pv("ylim", "text", "y 范围 c(min,max)", exprOk = TRUE),
  expand    = pv("expand", "text", "扩展（R 表达式）", exprOk = TRUE),
  clip      = pv("clip", "select", "裁剪", c("on", "off")),
  reverse   = pv("reverse", "select", "轴反转", c("none", "x", "y", "xy")),
  ratio     = pv("ratio", "number", "纵横比 y/x", step = 0.1),
  default   = pv("default", "bool", "作为默认坐标系"),
  theta     = pv("theta", "select", "角度映射", c("x", "y")),
  start     = pv("start", "number", "起始角度", min = 0, max = 2, step = 0.05),
  end       = pv("end", "number", "结束角度", min = 0, max = 2, step = 0.05),
  direction = pv("direction", "number", "方向 (1/-1)", step = 1),
  r.axis.inside = pv("r.axis.inside", "bool", "径向轴内置"),
  rotate.angle  = pv("rotate.angle", "bool", "随角度旋转文本"),
  inner.radius  = pv("inner.radius", "number", "内半径", min = 0, step = 0.05),
  thetalim  = pv("thetalim", "text", "角度范围", exprOk = TRUE),
  rlim      = pv("rlim", "text", "半径范围", exprOk = TRUE),
  projection= pv("projection", "text", "投影名称"),
  orientation = pv("orientation", "text", "投影方向", exprOk = TRUE),
  parameters= pv("parameters", "text", "投影参数", exprOk = TRUE),
  crs       = pv("crs", "text", "目标 CRS", exprOk = TRUE),
  default_crs = pv("default_crs", "text", "输入 CRS", exprOk = TRUE),
  datum     = pv("datum", "text", "网格基准", exprOk = TRUE),
  label_graticule = pv("label_graticule", "text", "经纬网标签边", exprOk = TRUE),
  label_axes = pv("label_axes", "text", "轴标签边", exprOk = TRUE),
  lims_method = pv("lims_method", "select", "限值方法", c("cross", "clip", "box", "geometry")),
  ndiscr    = pv("ndiscr", "number", "离散采样数", step = 1),
  x         = pv("x", "select", "x 变换", c("identity", "log10", "log2", "sqrt", "log1p", "pseudo_log_trans()"), exprOk = TRUE),
  y         = pv("y", "select", "y 变换", c("identity", "log10", "log2", "sqrt", "log1p", "pseudo_log_trans()"), exprOk = TRUE),
  limx      = pv("limx", "text", "x 范围", exprOk = TRUE),
  limy      = pv("limy", "text", "y 范围", exprOk = TRUE)
)

# ---- 分面 -------------------------------------------------------------------
FACET_SCHEMA <- list(
  wrap = list(
    label = "facet_wrap 一维分面",
    params = list(
      nrow    = pv("nrow", "number", "行数", min = 1, step = 1),
      ncol    = pv("ncol", "number", "列数", min = 1, step = 1),
      scales  = pv("scales", "select", "标度", c("fixed", "free_x", "free_y", "free")),
      space   = pv("space", "select", "面板空间", c("fixed", "free_x", "free_y", "free")),
      shrink  = pv("shrink", "bool", "收缩到统计值范围"),
      labeller= pv("labeller", "select", "标签器",
                   c("label_value", "label_both", "label_context", "label_parsed", "label_wrap_gen(12)"), exprOk = TRUE),
      as.table= pv("as.table", "bool", "从左上排布"),
      switch  = pv("switch", "select", "切换条带位置", c("x", "y", "both")),
      drop    = pv("drop", "bool", "丢弃空组合"),
      dir     = pv("dir", "select", "排布方向", c("h", "v")),
      strip.position = pv("strip.position", "select", "条带位置", c("top", "bottom", "left", "right")),
      axes    = pv("axes", "select", "绘制哪些轴", c("margins", "all_x", "all_y", "all")),
      axis.labels = pv("axis.labels", "select", "轴标签", c("margins", "all_x", "all_y", "all"))
    )
  ),
  grid = list(
    label = "facet_grid 二维分面",
    params = list(
      scales  = pv("scales", "select", "标度", c("fixed", "free_x", "free_y", "free")),
      space   = pv("space", "select", "面板空间", c("fixed", "free_x", "free_y", "free")),
      shrink  = pv("shrink", "bool", "收缩到统计值范围"),
      labeller= pv("labeller", "select", "标签器",
                   c("label_value", "label_both", "label_context", "label_parsed", "label_wrap_gen(12)"), exprOk = TRUE),
      as.table= pv("as.table", "bool", "从左上排布"),
      switch  = pv("switch", "select", "切换条带位置", c("x", "y", "both")),
      drop    = pv("drop", "bool", "丢弃空组合"),
      margins = pv("margins", "bool", "边际汇总", exprOk = TRUE),
      axes    = pv("axes", "select", "绘制哪些轴", c("margins", "all_x", "all_y", "all")),
      axis.labels = pv("axis.labels", "select", "轴标签", c("margins", "all_x", "all_y", "all"))
    )
  )
)

# ---- 图例/引导 --------------------------------------------------------------
GUIDE_META <- list(
  gm("legend",      "图例",             "图例", "标准图例"),
  gm("colorbar",    "颜色条",           "图例", "连续颜色的渐变条"),
  gm("colourbar",   "颜色条（别名）",   "图例", "colorbar 别名"),
  gm("bins",        "分箱图例",         "图例", "分箱样式的图例"),
  gm("colorsteps",  "阶梯色带",         "图例", "分箱颜色阶梯条"),
  gm("coloursteps", "阶梯色带（别名）", "图例", "colorsteps 别名"),
  gm("axis",        "轴样式",           "图例", "以轴形式呈现的图例"),
  gm("axis_logticks","对数刻度轴",      "图例", "对数刻度轴"),
  gm("axis_theta",  "角度轴",           "图例", "极坐标角度轴"),
  gm("axis_stack",  "组合轴",           "图例", "多轴叠加"),
  gm("none",        "隐藏",             "图例", "不显示图例"),
  gm("custom",      "自定义图形",       "图例", "完全自定义的 grob"),
  # ggprism
  gm("prism_minor",        "Prism 次刻度",        "图例", "ggprism：带次刻度的坐标轴"),
  gm("prism_offset",       "Prism 偏移轴",        "图例", "ggprism：轴线偏移（避免与数据重叠）"),
  gm("prism_offset_minor", "Prism 偏移+次刻度",   "图例", "ggprism：偏移轴 + 次刻度"),
  gm("prism_bracket",      "Prism 括号",          "图例", "ggprism：带括号的图例分组")
)
GUIDE_META <- setNames(GUIDE_META, vapply(GUIDE_META, function(x) x$name, character(1)))

GUIDE_PARAM_WIDGETS <- list(
  title       = pv("title", "text", "标题", exprOk = TRUE),
  theme       = pv("theme", "text", "主题元素（R 表达式）", exprOk = TRUE),
  nbin        = pv("nbin", "number", "色带分格数", min = 2, step = 1),
  display     = pv("display", "select", "显示形式", c("raster", "rectangles", "colourkey")),
  raster      = pv("raster", "bool", "光栅化色带"),
  draw.ulim   = pv("draw.ulim", "bool", "显示上限"),
  draw.llim   = pv("draw.llim", "bool", "显示下限"),
  alpha       = pv("alpha", "number", "透明度", min = 0, max = 1, step = 0.05),
  angle       = pv("angle", "number", "标签角度", step = 5),
  position    = pv("position", "select", "位置", c("right", "left", "top", "bottom", "inside")),
  direction   = pv("direction", "select", "方向", c("vertical", "horizontal")),
  reverse     = pv("reverse", "bool", "反转"),
  order       = pv("order", "number", "绘制顺序", step = 1),
  nrow        = pv("nrow", "number", "行数", min = 1, step = 1),
  ncol        = pv("ncol", "number", "列数", min = 1, step = 1),
  byrow       = pv("byrow", "bool", "按行填充"),
  even.steps  = pv("even.steps", "bool", "等距阶梯"),
  show.limits = pv("show.limits", "bool", "显示边界刻度"),
  ticks       = pv("ticks", "bool", "显示刻度"),
  available_aes = NULL,
  spacing     = pv("spacing", "number", "间隔", step = 0.05),
  vjust       = pv("vjust", "number", "垂直对齐", step = 0.05),
  hjust       = pv("hjust", "number", "水平对齐", step = 0.05),
  rotation    = pv("rotation", "number", "旋转", step = 5),
  force.guide = pv("force.guide", "bool", "强制覆盖"),
  check.overlap = pv("check.overlap", "bool", "检查标签重叠"),
  n.dodge     = pv("n.dodge", "number", "错行数", min = 1, step = 1),
  width       = pv("width", "number", "括号宽度", min = 0, step = 0.05),
  outside     = pv("outside", "bool", "画在绘图区外")
)

# ---- 标度类型标签（纯中文；R 函数名在选项右侧显示） -------------------------
SCALE_TYPE_LABELS <- list(
  continuous = "连续", discrete = "离散", binned = "分箱",
  date = "日期", datetime = "日期时间", time = "时间",
  reverse = "反转", log10 = "log10 变换", sqrt = "平方根", pseudo_log = "伪对数",
  identity = "恒等", manual = "手动指定", brewer = "配色板（Brewer）",
  gradient = "渐变", gradient2 = "双向渐变", gradientn = "多段渐变",
  steps = "阶梯渐变", stepsn = "多段阶梯", fermenter = "分箱渐变",
  distiller = "连续配色板（Brewer）", viridis_b = "viridis 分箱", viridis_c = "viridis 连续",
  hue = "色相环", grey = "灰度", viridis = "viridis",
  ordinal = "顺序", datetime2 = "日期时间",
  `date_short` = "日期"
)

SCALE_AES_ORDER <- c("x", "y", "colour", "fill", "alpha", "size", "linewidth",
                     "linetype", "shape", "radius")

# ---- 标度通用参数（几乎所有 scale 都接受） ----------------------------------
SCALE_COMMON_PARAMS <- list(
  name    = pv("name", "text", "标度标题", exprOk = TRUE),
  breaks  = pv("breaks", "text", "刻度位置", exprOk = TRUE),
  labels  = pv("labels", "text", "刻度标签", exprOk = TRUE),
  limits  = pv("limits", "text", "数据范围 limits", exprOk = TRUE),
  expand  = pv("expand", "text", "扩展 expansion（R 表达式）", exprOk = TRUE),
  n.breaks= pv("n.breaks", "number", "刻度数量", min = 2, step = 1),
  position= pv("position", "select", "轴/图例位置", c("left", "right", "top", "bottom")),
  guide   = pv("guide", "select", "图例类型", c("legend", "colourbar", "colorbar", "bins", "colorsteps", "axis", "none"), exprOk = TRUE),
  na.value= pv("na.value", "text", "缺失值样式", exprOk = TRUE),
  trans   = pv("trans", "select", "变换", c("identity", "log10", "log2", "log1p", "sqrt", "reverse", "pseudo_log_trans()", "date", "probit", "atanh"), exprOk = TRUE),
  aesthetics = pv("aesthetics", "text", "应用的 aes", exprOk = TRUE),
  sec.axis   = NULL
)

# ---- 主题 -------------------------------------------------------------------
THEME_BASE_THEMES <- c("gray", "bw", "linedraw", "light", "dark", "minimal", "classic", "void", "test")
THEME_LABELS <- list(
  gray = "默认灰底 theme_gray", bw = "黑白 theme_bw", linedraw = "细线 theme_linedraw",
  light = "浅色 theme_light", dark = "深色 theme_dark", minimal = "极简 theme_minimal",
  classic = "经典 theme_classic", void = "无框 theme_void", test = "测试 theme_test"
)
# ggprism 主题中文标签（key 为 theme_ 之后的名字）
GGPRISM_THEME_LABELS <- list(
  prism = "Prism 期刊风"
)
ELEMENT_PROP_SCHEMA <- list(
  text = list(
    pv("family", "text", "字体"),
    pv("face", "select", "字体样式", c("plain", "bold", "italic", "bold.italic")),
    pv("size", "number", "字号", min = 1, step = 1),
    pv("colour", "color", "颜色"),
    pv("hjust", "number", "水平对齐", min = 0, max = 1, step = 0.05),
    pv("vjust", "number", "垂直对齐", min = 0, max = 1, step = 0.05),
    pv("angle", "number", "角度", step = 5),
    pv("lineheight", "number", "行距", step = 0.1),
    pv("margin", "margins", "边距"),
    pv("debug", "bool", "调试框")
  ),
  line = list(
    pv("colour", "color", "颜色"),
    pv("linewidth", "number", "线宽", min = 0, step = 0.1),
    pv("linetype", "linetype", "线型"),
    pv("lineend", "select", "线端", c("butt", "round", "square"))
  ),
  rect = list(
    pv("fill", "color", "填充"),
    pv("colour", "color", "边框色"),
    pv("linewidth", "number", "边框宽", min = 0, step = 0.1),
    pv("linetype", "linetype", "边框线型")
  ),
  point = list(
    pv("shape", "shape", "形状"),
    pv("colour", "color", "颜色"),
    pv("fill", "color", "填充"),
    pv("size", "number", "大小", step = 0.5),
    pv("stroke", "number", "描边", step = 0.1),
    pv("alpha", "number", "透明度", min = 0, max = 1, step = 0.05)
  ),
  polygon = list(
    pv("fill", "color", "填充"),
    pv("colour", "color", "边框色"),
    pv("linewidth", "number", "边框宽", min = 0, step = 0.1)
  ),
  geom = list(
    pv("colour", "color", "颜色"),
    pv("fill", "color", "填充"),
    pv("linewidth", "number", "线宽", min = 0, step = 0.1),
    pv("linetype", "linetype", "线型"),
    pv("size", "number", "大小", step = 0.5),
    pv("shape", "shape", "形状"),
    pv("alpha", "number", "透明度", min = 0, max = 1, step = 0.05)
  )
)
# value 型主题项的专用控件
THEME_VALUE_WIDGETS <- list(
  legend.position      = pv("legend.position", "select", "图例位置", c("right", "left", "top", "bottom", "inside", "none")),
  legend.position.inside = pv("legend.position.inside", "text", "内部位置 c(x,y)", exprOk = TRUE),
  legend.justification = pv("legend.justification", "text", "图例对齐", exprOk = TRUE),
  legend.justification.top = pv("legend.justification.top", "text", "顶部对齐", exprOk = TRUE),
  legend.box           = pv("legend.box", "select", "图例排列", c("vertical", "horizontal")),
  legend.box.just      = pv("legend.box.just", "select", "图例组对齐", c("top", "bottom", "left", "right", "center")),
  legend.margin        = pv("legend.margin", "margins", "图例边距"),
  legend.spacing       = pv("legend.spacing", "unit", "图例间距"),
  legend.spacing.x     = pv("legend.spacing.x", "unit", "水平间距"),
  legend.spacing.y     = pv("legend.spacing.y", "unit", "垂直间距"),
  plot.margin          = pv("plot.margin", "margins", "绘图边距"),
  plot.background      = pv("plot.background", "rect", NULL),
  plot.subtitle        = pv("plot.subtitle", "text", NULL),
  plot.caption         = pv("plot.caption", "text", NULL),
  plot.tag             = pv("plot.tag", "text", NULL),
  panel.spacing        = pv("panel.spacing", "unit", "面板间距"),
  panel.spacing.x      = pv("panel.spacing.x", "unit", "水平间距"),
  panel.spacing.y      = pv("panel.spacing.y", "unit", "垂直间距"),
  panel.ontop          = pv("panel.ontop", "bool", "面板置顶"),
  axis.ticks.length    = pv("axis.ticks.length", "unit", "刻度长度"),
  axis.ticks.length.x  = pv("axis.ticks.length.x", "unit", "刻度长度 x"),
  axis.ticks.length.y  = pv("axis.ticks.length.y", "unit", "刻度长度 y"),
  axis.mini.ticks.length = pv("axis.mini.ticks.length", "unit", "小刻度长度"),
  prism.ticks.length   = pv("prism.ticks.length", "unit", "Prism 刻度长度"),
  prism.ticks.length.x = pv("prism.ticks.length.x", "unit", "Prism x 刻度长度"),
  prism.ticks.length.x.top = pv("prism.ticks.length.x.top", "unit", "Prism x 刻度长度(上)"),
  prism.ticks.length.x.bottom = pv("prism.ticks.length.x.bottom", "unit", "Prism x 刻度长度(下)"),
  prism.ticks.length.y = pv("prism.ticks.length.y", "unit", "Prism y 刻度长度"),
  prism.ticks.length.y.left = pv("prism.ticks.length.y.left", "unit", "Prism y 刻度长度(左)"),
  prism.ticks.length.y.right = pv("prism.ticks.length.y.right", "unit", "Prism y 刻度长度(右)"),
  strip.placement      = pv("strip.placement", "select", "条带位置", c("outside", "inside")),
  strip.text           = pv("strip.text", "text", NULL),
  strip.background     = pv("strip.background", "rect", NULL),
  strip.clip           = pv("strip.clip", "select", "条带裁剪", c("on", "off")),
  complete             = pv("complete", "bool", "完整主题标记"),
  validate             = pv("validate", "bool", "校验主题")
)
SHAPE_OPTIONS  <- as.character(0:25)
LINETYPE_OPTIONS <- c("blank", "solid", "dashed", "dotted", "dotdash", "longdash", "twodash")
UNIT_OPTIONS   <- c("pt", "mm", "cm", "inch", "lines")

# ---- 主题元素中文标签（未命中的用元素名本身） --------------------------------
THEME_ELEMENT_LABELS <- list(
  # 基础
  line = "基础线", rect = "基础矩形", text = "基础文本", title = "基础标题",
  `axis` = "坐标轴（总）", legend = "图例（总）", `panel` = "面板（总）",
  plot = "图区（总）", strip = "条带（总）", spacing = "间距（总）",
  margins = "边距（总）", geom = "几何元素", point = "基础点", polygon = "基础多边形",
  # 图区 plot.*
  `plot.title` = "主标题", `plot.subtitle` = "副标题", `plot.caption` = "注释",
  `plot.tag` = "角标", `plot.title.position` = "标题对齐基准",
  `plot.caption.position` = "注释对齐基准", `plot.tag.position` = "角标位置",
  `plot.background` = "整图背景", `plot.margin` = "整图边距",
  `plot.title.default` = "主标题(默认)",
  # 面板 panel.*
  `panel.background` = "面板背景", `panel.border` = "面板边框",
  `panel.grid` = "网格线（总）", `panel.grid.major` = "主网格线",
  `panel.grid.minor` = "次网格线", `panel.grid.major.x` = "主网格竖线",
  `panel.grid.major.y` = "主网格横线", `panel.grid.minor.x` = "次网格竖线",
  `panel.grid.minor.y` = "次网格横线", `panel.ontop` = "网格置于上层",
  `panel.spacing` = "面板间距", `panel.spacing.x` = "面板水平间距",
  `panel.spacing.y` = "面板垂直间距", `panel.widths` = "面板宽度",
  `panel.heights` = "面板高度", `panel.sidebar` = "侧边条",
  `panel.background.alt` = "alt 面板背景", `panel.border.alt` = "alt 面板边框",
  # 坐标轴 axis.*
  `axis.title` = "轴标题（总）", `axis.title.x` = "x 轴标题",
  `axis.title.y` = "y 轴标题", `axis.title.x.top` = "x 轴标题(上)",
  `axis.title.x.bottom` = "x 轴标题(下)", `axis.title.y.left` = "y 轴标题(左)",
  `axis.title.y.right` = "y 轴标题(右)",
  `axis.text` = "刻度文字（总）", `axis.text.x` = "x 刻度文字", `axis.text.y` = "y 刻度文字",
  `axis.text.x.top` = "x 刻度文字(上)", `axis.text.x.bottom` = "x 刻度文字(下)",
  `axis.text.y.left` = "y 刻度文字(左)", `axis.text.y.right` = "y 刻度文字(右)",
  `axis.text.theta` = "角度刻度文字", `axis.text.r` = "半径刻度文字",
  `axis.ticks` = "刻度线（总）", `axis.ticks.x` = "x 刻度线", `axis.ticks.y` = "y 刻度线",
  `axis.ticks.theta` = "角度刻度线", `axis.ticks.r` = "半径刻度线",
  `axis.minor.ticks.x.top` = "x 次刻度(上)", `axis.minor.ticks.x.bottom` = "x 次刻度(下)",
  `axis.minor.ticks.y.left` = "y 次刻度(左)", `axis.minor.ticks.y.right` = "y 次刻度(右)",
  `axis.minor.ticks.r` = "r 次刻度", `axis.minor.ticks.theta` = "theta 次刻度",
  `axis.minor.ticks` = "次刻度线（总）",
  `axis.line` = "轴线（总）", `axis.line.x` = "x 轴线", `axis.line.y` = "y 轴线",
  `axis.line.x.top` = "x 轴线(上)", `axis.line.x.bottom` = "x 轴线(下)",
  `axis.line.y.left` = "y 轴线(左)", `axis.line.y.right` = "y 轴线(右)",
  `axis.line.theta` = "角度轴线", `axis.line.r` = "半径轴线",
  `axis.ticks.length` = "刻度长度", `axis.ticks.length.x` = "x 刻度长度",
  `axis.ticks.length.y` = "y 刻度长度", `axis.ticks.length.theta` = "theta 刻度长度",
  `axis.ticks.length.r` = "r 刻度长度", `axis.ticks.length.x.top` = "x 刻度长度(上)",
  `axis.ticks.length.x.bottom` = "x 刻度长度(下)", `axis.ticks.length.y.left` = "y 刻度长度(左)",
  `axis.ticks.length.y.right` = "y 刻度长度(右)",
  `axis.minor.ticks.length` = "次刻度长度", `axis.minor.ticks.length.x` = "x 次刻度长度",
  `axis.minor.ticks.length.y` = "y 次刻度长度",
  `axis.short` = "短刻度", `axis.ticks.x.top` = "x 刻度线(上)",
  # 图例 legend.*
  `legend.background` = "图例背景", `legend.margin` = "图例边距",
  `legend.spacing` = "图例间距", `legend.spacing.x` = "图例水平间距",
  `legend.spacing.y` = "图例垂直间距", `legend.key` = "图例键",
  `legend.key.size` = "图例键尺寸", `legend.key.height` = "图例键高",
  `legend.key.width` = "图例键宽", `legend.key.spacing` = "键间距",
  `legend.key.spacing.x` = "键水平间距", `legend.key.spacing.y` = "键垂直间距",
  `legend.frame` = "图例外框", `legend.ticks` = "颜色条刻度",
  `legend.ticks.length` = "颜色条刻度长度", `legend.axis.line` = "颜色条轴线",
  `legend.text` = "图例文字", `legend.text.position` = "图例文字位置",
  `legend.title` = "图例标题", `legend.title.position` = "图例标题位置",
  `legend.position` = "图例位置", `legend.position.inside` = "图例内部坐标",
  `legend.justification` = "图例对齐", `legend.justification.top` = "顶部图例对齐",
  `legend.justification.bottom` = "底部图例对齐", `legend.justification.left` = "左图例对齐",
  `legend.justification.right` = "右图例对齐", `legend.location` = "图例定位方式",
  `legend.box` = "图例排列方向", `legend.box.just` = "图例组对齐",
  `legend.box.margin` = "图例组边距", `legend.box.background` = "图例组背景",
  `legend.box.spacing` = "图例组间距",
  # 条带 strip.*
  `strip.background` = "条带背景", `strip.background.x` = "条带背景(x)",
  `strip.background.y` = "条带背景(y)", `strip.clip` = "条带裁剪",
  `strip.placement` = "条带位置", `strip.text` = "条带文字",
  `strip.text.x` = "条带文字(x)", `strip.text.y` = "条带文字(y)",
  `strip.text.x.top` = "条带文字(x上)", `strip.text.x.bottom` = "条带文字(x下)",
  `strip.text.y.left` = "条带文字(y左)", `strip.text.y.right` = "条带文字(y右)",
  `strip.switch.pad.grid` = "切换时条带间距(grid)",
  `strip.switch.pad.wrap` = "切换时条带间距(wrap)",
  # ggprism 注册的轴刻度元素
  `prism.ticks.length` = "Prism 刻度长度",
  `prism.ticks.length.x` = "Prism x 刻度长度",
  `prism.ticks.length.x.top` = "Prism x 刻度长度(上)",
  `prism.ticks.length.x.bottom` = "Prism x 刻度长度(下)",
  `prism.ticks.length.y` = "Prism y 刻度长度",
  `prism.ticks.length.y.left` = "Prism y 刻度长度(左)",
  `prism.ticks.length.y.right` = "Prism y 刻度长度(右)"
)
