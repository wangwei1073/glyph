# Simulate integrating ggprism / ggpubr / ggstatsplot into the ggplotGUI registry.
# 用法（项目根目录）: Rscript tools/extension-eval/integration_sim.R
# 预期结果：case 2 (geom_signif)、case 3 (geom_bracket) 渲染成功；
#           case 1 (stat_compare_means 放在图层级映射) 渲染失败 —— 这正是 ggpubr 的
#           plot 级 aes 依赖，见 EXTENSIONS.md 第三节。
options(width = 250, warn = 1)
suppressPackageStartupMessages({ library(ggplot2); library(jsonlite) })
# 用法（项目根目录）: Rscript tools/extension-eval/integration_sim.R
root <- "."
setwd(root)
for (f in sort(list.files(file.path(root, "R"), pattern = "\\.R$", full.names = TRUE))) source(f, encoding = "UTF-8", local = FALSE)

STATE <- list(
  version = "1.0.0", meta = NULL, data_store = DataStore, pin_store = Pins,
  edit_store = EditStore, dist_dir = file.path(root, "dist"), raw_data = NULL,
  plot_dir = file.path(tempdir(), "ggpkg-plots"),
  pin_file = file.path(root, "pins.json"),
  allowed_hosts = c("127.0.0.1", "localhost"), allow_any_host = FALSE
)
dir.create(STATE$plot_dir, showWarnings = FALSE, recursive = TRUE)
OUT <- file.path(tempdir(), "ggpkg-eval")
dir.create(OUT, showWarnings = FALSE, recursive = TRUE)

meta <- ggspec_build_meta()
cat("baseline: geoms", length(meta$geoms), "scales", length(meta$scales),
    "themes", length(meta$themes), "guides", length(meta$guides), "\n")

# extension theme args: .ggspec_theme_args() only looks in ggplot2 namespace -> needs a pkg-aware variant
theme_args_of <- function(fn, pkg) {
  fm <- formals(get(fn, envir = asNamespace(pkg)))
  lapply(setdiff(names(fm), "..."), function(nm) {
    switch(nm,
      base_size = pv(nm, "number", "base font size", min = 4, max = 48, step = 1),
      base_family = pv(nm, "text", "base font family"),
      base_line_size = pv(nm, "number", "base line width", min = 0, step = 0.1),
      base_rect_size = pv(nm, "number", "base rect width", min = 0, step = 0.1),
      pv(nm, "text")
    )
  })
}

pal <- as.list(names(ggprism::ggprism_data$colour_palettes))

## ---- ggprism ----
meta$themes[[length(meta$themes) + 1]] <- list(
  name = "prism", fn = "theme_prism", package = "ggprism", label = "Prism (ggprism)",
  args = (function() { a <- theme_args_of("theme_prism", "ggprism");
                       a$palette <- pv("palette", "select", "Prism palette", options = pal); a })()
)
for (s in .ggspec_scan_pkg_scales("ggprism")) {
  s$label <- paste0("Prism ", s$aes)
  s$params$palette <- pv("palette", "select", "palette", options = pal)
  meta$scales[[length(meta$scales) + 1]] <- s
}

## ---- ggpubr themes + geoms ----
for (fn in c("theme_pubr", "theme_pubclean", "theme_classic2", "theme_cleveland", "theme_transparent")) {
  meta$themes[[length(meta$themes) + 1]] <- list(
    name = sub("^theme_", "", fn), fn = fn, package = "ggpubr",
    label = paste0(sub("^theme_", "", fn), " (ggpubr)"), args = theme_args_of(fn, "ggpubr"))
}
for (s in .ggspec_scan_pkg_geoms("ggpubr", NULL)) {
  if (!s$name %in% c("signif", "pwc", "bracket")) next
  f <- get(s$fn, envir = asNamespace("ggpubr"))
  layer <- tryCatch(suppressWarnings(f()), error = function(e) NULL)
  s$aes <- if (!is.null(layer)) .ggspec_aes_list(layer$geom) else list(required = list("x", "y"), optional = list())
  s$params <- lapply(setdiff(names(formals(f)), c("mapping", "data", "stat", "position", "...",
                                                  "show.legend", "inherit.aes")),
                     function(nm) PARAM_WIDGETS[[nm]] %||% pv(nm, "text"))
  s$statParams <- list(); s$defaultStat <- "identity"; s$defaultPosition <- "identity"
  s$group <- "extension"; s$shape <- "special"; s$label <- paste0(s$name, " (ggpubr)")
  meta$geoms[[length(meta$geoms) + 1]] <- s
}
## ggpubr stat layer as a "layer function" entry
meta$geoms[[length(meta$geoms) + 1]] <- list(
  fn = "stat_compare_means", name = "compare_means", package = "ggpubr",
  label = "compare means (ggpubr)", group = "extension", shape = "special",
  desc = "ggpubr::stat_compare_means",
  aes = list(required = list(), optional = list("x", "y", "group", "colour", "fill")),
  params = lapply(setdiff(names(formals(ggpubr::stat_compare_means)),
                          c("mapping", "data", "stat", "position", "...", "show.legend", "inherit.aes")),
                  function(nm) PARAM_WIDGETS[[nm]] %||% pv(nm, "text")),
  statParams = list(), defaultStat = "identity", defaultPosition = "identity"
)
## ggstatsplot theme
meta$themes[[length(meta$themes) + 1]] <- list(
  name = "ggstatsplot", fn = "theme_ggstatsplot", package = "ggstatsplot",
  label = "ggstatsplot theme", args = list())

meta <- meta_build_lookup(meta)
cat("extended: geoms", length(meta$geoms), "scales", length(meta$scales),
    "themes", length(meta$themes), "\n")

render_spec <- function(tag, spec, file) {
  cat("\n---- ", tag, " ----\n", sep = "")
  gen <- tryCatch(spec_to_code(spec, meta, STATE), error = function(e) e)
  if (inherits(gen, "error")) { cat("codegen ERROR:", conditionMessage(gen), "\n"); return(invisible(NULL)) }
  cat(gen$code, "\n")
  res <- tryCatch(ggspec_render_preview(spec, meta, STATE, 900, 520, 110, png_dir = STATE$plot_dir),
                  error = function(e) e)
  if (inherits(res, "error")) { cat("render ERROR:", conditionMessage(res), "\n"); return(invisible(NULL)) }
  cat("render ok:", isTRUE(res$ok), "| warnings:", length(res$warnings), "| rows:", res$nrow, "\n")
  if (length(res$warnings)) cat("  W:", paste(head(unlist(res$warnings), 4), collapse = " || "), "\n")
  if (!is.null(res$pngUrl)) file.copy(file.path(STATE$plot_dir, sub("^/api/plot/", "", res$pngUrl)),
                                      file.path(OUT, file), overwrite = TRUE)
  invisible(res)
}

base_spec <- function(layers, theme = NULL, scales = list(), data = "mpg") {
  s <- list(data = list(source = list(type = "dataset", name = data)),
            layers = layers, scales = scales, labs = list(), guides = list())
  if (!is.null(theme)) s$theme <- theme
  s
}

spec1 <- base_spec(
  layers = list(
    list(geom = "boxplot", aes = list(x = list(map = "class"), y = list(map = "hwy"),
                                      fill = list(map = "class")), params = list(), stat = ""),
    list(geom = "compare_means", aes = list(x = list(map = "class"), y = list(map = "hwy")),
         params = list(method = "t.test", label = "p.signif",
                       comparisons = list(expr = 'list(c("compact", "suv"))')), stat = "")
  ),
  theme = list(base = "prism", args = list(palette = "floral", base_size = 12)),
  scales = list(list(aes = "fill", type = "prism", params = list(palette = "floral")))
)
render_spec("ggprism theme+scale and ggpubr stat_compare_means layer", spec1, "sim_mix.png")

spec2 <- base_spec(
  layers = list(
    list(geom = "boxplot", aes = list(x = list(map = "class"), y = list(map = "hwy"),
                                      fill = list(map = "class")), params = list(), stat = ""),
    list(geom = "signif", aes = list(x = list(map = "class"), y = list(map = "hwy")),
         params = list(comparisons = list(expr = 'list(c("compact", "suv"))'),
                       map_signif_level = TRUE), stat = "")
  ),
  theme = list(base = "pubr", args = list(base_size = 12))
)
render_spec("ggpubr geom_signif layer + theme_pubr", spec2, "sim_signif.png")

spec3 <- base_spec(
  layers = list(
    list(geom = "boxplot", aes = list(x = list(map = "class"), y = list(map = "hwy")),
         params = list(), stat = ""),
    list(geom = "bracket", aes = list(),
         params = list(xmin = 1, xmax = 2, y.position = 44, label = "p < 0.05"), stat = "")
  )
)
render_spec("ggpubr geom_bracket (zero-arg call fails at scan time)", spec3, "sim_bracket.png")
cat("\nSIMULATION DONE\n")
