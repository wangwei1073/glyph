# ggplotGUI 代码走查报告

> 状态：P0/P1 全部已修，P2/P3 已清理主要项 —— 修复明细与验证见 [FIXES.md](FIXES.md)。
> 本文保留为走查当时的原始记录（问题描述与证据），便于对照。

- 走查对象：`E:\Desktop\vibecoding\ggplot-gui`（R 4.6.1 / ggplot2 4.0.3 / Node 24 / Vue 3 + Element Plus）
- 走查方式：全量阅读源码（R 后端 9 个文件 ≈ 2 000 行，前端 20 个组件/Store ≈ 3 000 行）+ 实际执行验证
- 已做验证：
  - `Rscript tests/test_specs.R` → **29 通过 / 0 失败**，注册表 2.8 s 构建完成（59 geoms / 30 stats / 276 scales / 160 主题元素）
  - `vite build` → **构建通过**，产物 hash 与仓库内 `dist/` 完全一致（说明 `dist` 未过期）
  - 针对可疑点编写了可复现脚本 [tests/review_findings.R](tests/review_findings.R)（全部用临时目录，不污染项目）
- 结论：**架构选型正确、骨架扎实**（spec → 代码 → eval 单一管线、注册表运行时自省是真正的亮点），但**「上传数据」和「数据加工」两条主链路上存在阻断级缺陷**，且「界面所见 = 复制代码」这一核心承诺在特定组合下不成立。建议先修 P0/P1 再谈扩展。

## 问题总览

| 级别 | 数量 | 含义 |
|---|---|---|
| P0 | 4 | 主功能不可用 / 返回错误数据，必须修 |
| P1 | 7 | 常见路径出错、数据静默损坏、安全问题 |
| P2 | 15 | 体验与健壮性问题，建议修 |
| P3 | 10 | 整洁度 / 一致性 / 文档 |

---

## P0 阻断级

### P0-1 上传数据的「预览 / 手工编辑 / 导出 CSV」全链路失效

**现象**：上传 CSV 后，左侧「预览」按钮的行数徽标为空，数据预览弹窗显示「没有数据」；打开「编辑」模式后任何单元格编辑都报「编辑被拒绝」。

**证据**（脚本 A 段）：

```
前端实际发送 {type:'user', id:'u1'}   -> HTTP 400
后端能解析  {type:'user', name:'u1'} -> HTTP 200  nrow=5
上传数据手工编辑 /api/edits/add -> HTTP 400 : 数据缺少行锚列（.gg_rid），编辑不可用
```

**根因**：同一个「用户数据」在前端被两种字段名描述，后端两条路径各认一种。

- 前端发的是 `id`：[DataPreviewDialog.vue:59](frontend/src/components/DataPreviewDialog.vue#L59)、[DataPreviewDialog.vue:129](frontend/src/components/DataPreviewDialog.vue#L129)、[data.js:63-64](frontend/src/stores/data.js#L63-L64)
- 预览/编辑链路只读 `name`：[api.R:110-116](R/api.R#L110-L116) 的 `.prepared_full()` → `resolve_source_df(paste0(src$type, ":", src$name))`；[api.R:34](R/api.R#L34) 的 `.keyof()` 同样只读 `src$name`
- 而渲染链路读的是 `id`：[render.R:227](R/render.R#L227) `state$data_store$get(src$id)` —— 所以**图能画出来，但预览和编辑是坏的**，用户很难判断到底哪一步出了问题。

**修复**：抽一个 `src_id_of(src) <- src$id %||% src$name`，在 `resolve_source_df`、`.prepared_full`、`.keyof`、`.edits/add`、`.edits/undo`、`.edits/clear` 全部改用；`.keyof` 目前在 [api.R:34](R/api.R#L34) 和 [dataio.R:153](R/dataio.R#L153) 各有一份实现，建议只保留一份。

### P0-2 生成的「行筛选」代码不是可执行 R（对所有数据源）

**现象**：`/api/code` 与代码面板给出的筛选行是

```r
df <- df[hwy > 20 & !is.na(hwy > 20), , drop = FALSE]  # 行筛选
```

`[.data.frame` / `[.tbl_df` **不做数据掩码求值**，直接执行必然报「找不到对象'hwy'」。用户把代码复制到 RStudio 后 100% 失败。

**证据**（脚本 D1 段，两种类型都试过）：

```
mpg 的类是: tbl_df/tbl/data.frame
把这段代码整段执行的结果: 失败 -> 找不到对象'hwy'
base data.frame 单独验证:  d[a > 2, ]  ->  找不到对象'a'
with() 写法:               d[with(d, a > 2), ]  ->  3 行（正确）
```

**根因**：[spec_to_code.R:361-364](R/spec_to_code.R#L361-L364) 用 `df[<表达式>, ]` 模拟 `data_prepare()` 的语义，但 `data_prepare()` 用的是 `eval(parse(text=flt), envir = df)`（[dataio.R:88-94](R/dataio.R#L88-L94)），两者语义不同 —— 渲染路径能跑，复制出去的代码不能跑。

**修复**：改成 `df <- subset(df, <expr>)` 或 `df <- df[with(df, <expr> & !is.na(<expr>)), , drop = FALSE]`。顺带把 `!is.na(<flt>)` 里重复拼接的整个表达式收敛成一次求值（现在表达式被拼了两遍，长表达式可读性很差）。

### P0-3 高级模式的代码编辑器从未初始化

**现象**：右侧「高级」标签里的 CodeMirror 区域永远是空白框，「载入当前图形的生成代码」点了也看不到内容，「运行代码」只能运行空字符串。

**根因**：[AdvancedPanel.vue:20-49](frontend/src/components/AdvancedPanel.vue#L20-L49) 定义了 `initEditor()`，但**没有任何地方调用它**；同时 [AdvancedPanel.vue:3](frontend/src/components/AdvancedPanel.vue#L3) 引入的 `onMounted / onBeforeUnmount / nextTick` 全部未使用 —— 这是典型的「写完忘了挂载」。`editor` 恒为 `null`，`loadFromSpec()` 里的 `if (editor)` 分支永远不执行。

**修复**：`onMounted(initEditor)`，并在 `onBeforeUnmount` 里 `editor?.destroy()`；`loadFromSpec()` 在 `editor` 为空时应先 `await initEditor()`。

### P0-4 预览分页越界时返回反向索引，一次性吐出几百行垃圾数据

**现象**：在最后一页删行、或直接请求 `start` 超过总行数时，接口不报错，而是返回 **767 行全 NA**（`length` 请求的是 50）。

**证据**（脚本 B 段）：

```
请求 start=1000 / length=50，mpg 只有 234 行；返回 page.length = 767
后端 idx = seq(1000, min(234, 1049)) 前 6 个: 1000, 999, 998, 997, 996, 995  <- 反向递减
```

**根因**：[api.R:134-136](R/api.R#L134-L136)

```r
start <- max(1L, as.integer(body$start %||% 1L))
idx <- seq(start, min(total, start + len - 1L))
```

`start > total` 时 `seq()` 自动倒序；`d[1000:234, ]` 里越界下标产生 NA 行。前端 [DataPreviewDialog.vue:184-186](frontend/src/components/DataPreviewDialog.vue#L184-L186) 删行后不会把 `page` 回夹，所以这条路径在真实操作中可达。

**修复**：`if (start > total) start <- max(1L, total - len + 1L)`；`idx <- if (total == 0) integer(0) else seq.int(start, min(total, start + len - 1L))`；并让前端在 `nrow` 变化后把 `page` 夹到 `total_pages` 内。

---

## P1 严重

### P1-1 手工编辑把因子列改成新水平 → 静默变 NA

**证据**（脚本 C 段，用 iris$Species）：

```
Species[1]: 'setosa' -> 写入 '新物种' -> 实际值: NA
warning: 因子水平有错误，产生了NA
/api/edits/add 的预校验会拒绝吗？ 不会（放行）
```

**根因**：[dataio.R:155-174](R/dataio.R#L155-L174) 的 `.coerce_value()` 只处理 numeric / logical / Date，其余一律 `as.character()`；随后 [dataio.R:182-188](R/dataio.R#L182-L188) 把字符直接赋进因子列 → R 按「非法水平」处理成 NA + warning。而 `/api/edits/add` 的预校验只捕获 error（[api.R:287-294](R/api.R#L287-L294)），warning 放行，于是**用户的修改被静默丢弃**。

**修复**：`.coerce_value` 增加 factor 分支（要么 `factor(v, levels = union(levels(template), v))` 并回写 levels，要么明确报错提示「请改用列重命名/类型转换」）；预校验改为 `withCallingHandlers` 把 warning 也当失败。

### P1-2 「筛选 + 手工编辑」同时使用时，复制的代码改的是另一行

**证据**（脚本 D2 段，筛选 `displ > 2`，编辑 `rid = 5`）：

```
渲染路径里被改成 99 的行: 2.8 / a4
复制代码里被改成 99 的行: 2.8 / a4 quattro
逐行不同的单元格数: 2
```

**根因**：两条路径对行锚 `.gg_rid` 的编号时机不同。

- 渲染：[render.R:232-240](R/render.R#L232-L240) 先 `data_prepare()`（筛选/抽样）→ 再用**加载时的原始 rid** 应用编辑；
- 展示代码：[spec_to_code.R:375-381](R/spec_to_code.R#L375-L381) 把 `df$.gg_rid <- seq_len(nrow(df))` 放在筛选/抽样行**之后**，等于对筛选后的数据重新编号。

两者只在「筛选没删掉前几行」时才碰巧一致。

**修复**：把锚列赋值移到筛选之前（`df$.gg_rid <- seq_len(nrow(df))` 紧跟数据加载），或干脆改用「按主键定位」而不是行号。

### P1-3 空的新增行操作会丢掉此前全部编辑语句

**证据**（脚本 E 段）：`含空 rowIns 时生成 0 行；只有 cell 时 1 行`。

**根因**：[spec_to_code.R:309](R/spec_to_code.R#L309) 在 `for (op in ops)` 循环里写了 `return()`（应为 `next`），直接结束整个函数，已累积的 `lines` 全部丢弃。触发条件是 `rowIns` 的 `values` 为空 —— 前端 [DataPreviewDialog.vue:188-191](frontend/src/components/DataPreviewDialog.vue#L188-L191) 恰好会发这种请求。

### P1-4 拼图槽位缺失导致运算符错位

**证据**（脚本 F 段）：槽位 `[P1, 缺失, P2]`、中间运算符 `|`，生成的是 `p <- (p1 + p2)`，`|` 丢了。

**根因**：[spec_to_code.R:565-574](R/spec_to_code.R#L565-L574)：`ops` 按**全部**槽位收集，`plot_names` 只包含**成功解析**的槽位，用 `ops[j-1]` 取值时下标错位。

**修复**：在循环里收集 `used_ops`（与 `plot_names` 同步 push），或先过滤掉解析失败的槽位再统一取运算符。

### P1-5 注释坐标在「文本」控件里输入数字会被加引号

**证据**（脚本 G 段）：

```r
annotate("text", x = "5", y = "40", label = "高油耗区")
渲染结果: 失败 -> Discrete value supplied to a continuous scale. Example values: "5"
```

**根因**：[AnnotatePanel.vue:12-20](frontend/src/components/AnnotatePanel.vue#L12-L20) 把 `x/y/xmin/xmax/...` 定义成 `widget: 'text'`，而 [ParamControl.vue:112](frontend/src/components/ParamControl.vue#L112) 的文本控件产出字符串，[utils.R:28](R/utils.R#L28) 再 `r_string()` 加引号。用户必须自己点 `fx` 切到表达式模式才能输入数字 —— 这与「注释坐标就是数字」的直觉相反。

**修复**：这些坐标参数改用 `widget: 'number'`（或新增 `numberOrExpr` 控件：输入能被 `as.numeric` 解析就发数字，否则发 `{expr}`）。

### P1-6 前端 20 s 硬超时 + httpuv 单线程，重图会「假死」

**根因**：

- [api.js:4-6](frontend/src/api.js#L4-L6) 给**所有**请求套了 `AbortController` 20 s；`/api/render`、`/api/plotly`、大文件上传都可能超过。
- [run.R:74](R/run.R#L74) 用 `httpuv::runServer` 单线程处理：一次 30 s 的渲染会**阻塞同一进程内所有请求**，包括 `<img src="/api/plot/xxx.png">` 的取图和 `/api/plotdata/...` 的 plotly JSON。
- 结果：预览图加载超时 → 浏览器显示破图；用户以为程序挂了。

**修复**：至少按路由区分超时（渲染/导出/plotly 不设或设 120 s）；渲染任务改为异步（先返回 `jobId`，前端轮询 `/api/job/<id>`），或把渲染放到 `promises`/子进程里，避免阻塞静态与图片请求。

### P1-7 本地服务无任何来源校验：任意网页可对本机执行任意 R 代码（RCE）

**根因**：

- [api.R:355-366](R/api.R#L355-L366) 对所有 `/api/*` 直接路由，**不校验 `Origin` / `Sec-Fetch-Site` / `Content-Type`**；
- [utils.R:109-113](R/utils.R#L109-L113) 不关心 `Content-Type`，把 body 当 JSON 解析；
- [render.R:191-205](R/render.R#L191-L205) 的 `/api/rawrender` 会对请求体里的 `code` 直接 `parse` + `eval`（这是设计功能，但暴露给了浏览器同源策略管不到的地方）。

因此用户开着这个应用浏览任意恶意页面时，对方用 `fetch('http://127.0.0.1:4321/api/rawrender', {method:'POST', headers:{'Content-Type':'text/plain'}, body:'{"code":"system(\\"calc\\")"}'})` 这类**简单请求**（无预检）即可在本机执行任意代码 —— 不需要读到响应。

**修复（按性价比排序）**：① 校验 `Origin` 为 `http://127.0.0.1:<port>` 或 `Sec-Fetch-Site: same-origin`，否则 403；② 要求 `Content-Type: application/json`（强制预检）；③ 启动时生成一次性 token，注入 `index.html`，所有 `/api/*` 校验；④ 对 `/api/rawrender` 增加显式「高级模式已启用」开关。

---

## P2 中等

| # | 问题 | 位置 | 说明 / 建议 |
|---|---|---|---|
| 1 | 撤销覆盖不一致，且「清空画布」的提示是假的 | [spec.js:147-198](frontend/src/stores/spec.js#L147-L198)、[LabsGuidePanel.vue:38-66](frontend/src/components/LabsGuidePanel.vue#L38-L66)、[App.vue:100-111](frontend/src/App.vue#L100-L111) | `setLayerAes/setLayerParam/setLayerAesParam`、labs/guides 直接改状态不 `pushHistory()`；于是改一个参数再 Ctrl+Z 会回退到更早的结构性快照，静默丢掉中间的参数修改。`clearCanvas()` 先 `pushHistory()` 再 `spec.reset()`，而 `reset()` 会清空 `history/future`（[spec.js:65-70](frontend/src/stores/spec.js#L65-L70)），提示里的「可 Ctrl+Z 撤销」不成立 |
| 2 | 内联数据把内部锚列 `.gg_rid` 泄露给用户 | [spec_to_code.R:333-345](R/spec_to_code.R#L333-L345) | 生成的 `data.frame()` 里出现 `.gg_rid = c(1, 2, ...)`（脚本 H 段已复现）。用户复制出去会看到无意义列；建议内联时剔除，编辑语句改用 `df$<col>[<row index>]` 直接定位 |
| 3 | `NA_character_` 被序列化成字符串 `"NA"` | [utils.R:39-45](R/utils.R#L39-L45) | `r_string(NA_character_)` → `"NA"`；`labs(title = NA)` 会画出字面量 "NA"。应在 `r_literal()` 里先判 `is.na()` |
| 4 | 筛选表达式返回数值时被当成行号，静默产出错误数据 | [dataio.R:88-94](R/dataio.R#L88-L94) | `filter = "hwy"` 不报错，`df[<hwy 向量>, ]` 按行号重复取行。应校验 `is.logical(keep)` |
| 5 | 数据预览弹窗里的死代码 / 永远为 0 的计数 | [DataPreviewDialog.vue:69](frontend/src/components/DataPreviewDialog.vue#L69)、[L210-L222](frontend/src/components/DataPreviewDialog.vue#L210-L222) | `(await (await fetch('/api/edits')).ok) ? 0 : 0` 恒为 0；`undoLast()` 里用 `JSON.stringify(srcObj)` 当 `key`，而后端要的是 `"dataset:mpg"` / `"user:u1"`，永远查不到；`editCount` 也没在模板里用过 |
| 6 | 列改名/删列失败也提示「已改名 / 列已删除」 | [DataPreviewDialog.vue:197-209](frontend/src/components/DataPreviewDialog.vue#L197-L209) | `await commitOp(...)` 的返回值被忽略；取消 prompt 时还会产生未捕获的 Promise rejection |
| 7 | 切换数据源不清空失效映射 | [spec.js:90-100](frontend/src/stores/spec.js#L90-L100) | 从 mpg 换到 iris 后，`aes(x = displ)` 仍指向不存在的列 → 渲染报错。建议切换时按新列集过滤 `aes/aesParams`（可复用 `changeGeom` 的过滤思路） |
| 8 | 上传体积隐式上限约 37 MB，且失败信息不可读 | [utils.R:84](R/utils.R#L84)、[api.js:48-56](frontend/src/api.js#L48-L56) | `readBin(n = 5e7)` 静默截断 → JSON 解析失败；前端整文件 base64 进内存（体积 ×1.37）。建议前置校验大小并给出明确提示 |
| 9 | plotly 4.7 MB 被打进首屏预加载，`manualChunks` 产生空 chunk | [vite.config.js:17-24](frontend/vite.config.js#L17-L24)、`dist/index.html` | 构建输出里有 `codemirror-*.js` 1 B、`plotly.min-*.js` 465 B 两个空 chunk；同时 `dist/index.html` 对 `plotly-*.js` 打了 `modulepreload`，而它只在打开交互预览时才需要。去掉 `manualChunks` 里对动态导入包的手工分组，或改用 `import()` 边界自然分包 |
| 10 | 标度排序里的死代码 | [meta.js:77-82](frontend/src/stores/meta.js#L77-L82) | `x.type.localeCompare(b.type) * 0` —— 乘以 0 的无效项，且 `b` 是外层闭包变量，可读性差 |
| 11 | 每次 `/api/sources` 都全量枚举数据集 | [datasets.R:18-36](R/datasets.R#L18-L36)、[api.R:75-77](R/api.R#L75-L77) | 遍历 `data(package=)` 并 `get()` 每个数据集（含 diamonds 53k 行），每次上传后都会触发；建议启动时算一次缓存 |
| 12 | `run.R` 混用 `getwd()` 与 `scriptdir` | [run.R:20-23](R/run.R#L20-L23)、[run.R:41](R/run.R#L41) | `DIST` 用脚本目录，`root`（决定 `R/` 源码、`pins.json`、`edits.json` 位置）用当前目录。从别的目录 `Rscript <path>/run.R` 会直接失败；装在只读目录会写不进 pins.json |
| 13 | `pins.json` / `edits.json` 非原子写 | [pins.R:9-14](R/pins.R#L9-L14)、[dataio.R:121-125](R/dataio.R#L121-L125) | 直接 `writeLines` 覆盖，进程中断会留下半个 JSON；下次启动 `fromJSON` 失败后**静默丢弃全部图库/编辑**。建议写临时文件 + `file.rename()` |
| 14 | 静态文件路径清洗偏弱 | [api.R:13-30](R/api.R#L13-L30) | `gsub("\\.\\.", "", rel)` 只是删字符串，不是规范化。当前组合下没能穿越（`file.path` 会拼在 dist 下），但建议改成 `normalizePath(full)` 后校验 `startsWith(full, normalizePath(root))` |
| 15 | 渲染状态挂在全局 `state$raw_data` 上 | [api.R:194](R/api.R#L194)、[render.R:191-205](R/render.R#L191-L205) | 原始代码渲染依赖「上一次请求写入的 df」，并发/重放时行为不确定；建议把 df 随请求传入或按 session 隔离 |

---

## P3 整洁度 / 一致性

1. **调试接口留在生产路由**：`/api/ping` 会把请求体解析结果回显（[api.R:58-67](R/api.R#L58-L67)），建议移除或加开关。
2. **重复定义**：`.keyof` 在 [api.R:34](R/api.R#L34) 与 [dataio.R:153](R/dataio.R#L153) 各一份；`.scale_call` 里 `meta$scale_fn[[key]]` 查了两次（[spec_to_code.R:81-85](R/spec_to_code.R#L81-L85)）。
3. **未使用的函数/导入**：`Canvas.vue` 的 `resetCompose()`（[L74-77](frontend/src/components/Canvas.vue#L74-L77)）、`DataPanel.vue` 的 `onMounted` 导入（[L3](frontend/src/components/DataPanel.vue#L3)）、`ThemePanel.vue` 的 `isValueType/isUnitVal/isMarginsVal`（[L80-85](frontend/src/components/ThemePanel.vue#L80-L85)）、`AdvancedPanel.vue` 的 `nextTick/onBeforeUnmount`。
4. **`addFirstLayer()` 冗余**：`spec.addLayer()` 内部已经调过 `guessAes`（[Canvas.vue:86-89](frontend/src/components/Canvas.vue#L86-L89) vs [spec.js:118-124](frontend/src/stores/spec.js#L118-L124)）。
5. **`AesPanel` 映射→常量会把列名变成字符串**：[AesPanel.vue:42-50](frontend/src/components/AesPanel.vue#L42-L50)，切到「常量」后得到 `colour = "class"`，多数情况不是用户想要的。
6. **`ScalePanel` 提示「已有，将覆盖」但实际不覆盖**：[ScalePanel.vue:74](frontend/src/components/ScalePanel.vue#L74) 文案 vs [spec.js:201-205](frontend/src/stores/spec.js#L201-L205) 逻辑。
7. **拼图面板只能上移不能下移**：[PinPanel.vue:127-129](frontend/src/components/PinPanel.vue#L127-L129)；且 `cb()` 在模板渲染期写 store（[PinPanel.vue:12-18](frontend/src/components/PinPanel.vue#L12-L18)），属渲染期副作用。
8. **载入项目是浅合并**：[spec.js:227-232](frontend/src/stores/spec.js#L227-L232)，旧版/手改的 JSON 缺 `mutate` 时会在 `DataPanel` 里 `.push` 报错；`renderOpts` 也不随项目保存。
9. **文档与实现不符**：README 首屏图片链接是 `https://localhost.invalid`（[README.md:6](README.md#L6)）；「代码面板与图形 100% 一致」（[README.md:85](README.md#L85)）在 P0-2 / P1-2 修复前不成立。
10. **仓库卫生**：没有版本控制（无 `.git`、无 `.gitignore`）；根目录混入运行产物 `Rplots.pdf`(0 B)、`rt2.json`(调试请求体)、`pins.json`、`edits.json`，`tests/out/*.png` 有 20 个测试产物，`frontend/tools/patch_dialog.py` 是一次性改文件脚本。建议加 `.gitignore`（`pins.json`、`edits.json`、`Rplots.pdf`、`tests/out/`、`node_modules/`、`_dist_check/`）。

---

## 做得好的地方（建议保留）

1. **单一事实来源**：spec → `spec_to_code()` → `eval()`，代码面板与图形共用一份代码，方向完全正确（P0-2/P1-2 只是生成器细节没打磨到位，不是架构问题）。
2. **运行时自省注册表**：`geom_/stat_/scale_/coord_/guide_/theme element` 全部从已装 ggplot2 枚举（[registry_core.R](R/registry_core.R)），升级 ggplot2 不用改代码；2.8 s 构建、59/30/276/160 的覆盖面很实在。
3. **渲染结果落盘 + URL 返回**（[render.R:131-155](R/render.R#L131-L155)）避开了 base64 大 JSON；缓存只保留最近 24 个，细节到位。
4. **错误/警告/消息三通道回传**并在画布下方折叠展示，调试体验好。
5. **测试基线可用**：29 个代表性 spec 覆盖了扩展包、拼图、编辑、主题、分面等，`test_edits.R` / `test_patchwork.R` 也断言了关键不变量（如「未编辑时不得出现锚行」），是很清醒的回归意识。
6. **中文化程度高**、控件按类型渲染（颜色选择器、shape/linetype 预览）、fx 表达式双模 —— 产品打磨明显。

---

## 建议修复顺序

1. **P0-1**（id/name 统一）—— 改 3~5 行，解锁上传数据全部功能。
2. **P0-2 + P1-2**（筛选代码 + 锚列时机）—— 兑现「代码可复现」的核心承诺；同时补一个「把展示代码真的执行一遍」的测试。
3. **P0-4 + P1-3 + P1-4**（分页夹取、`return()`→`next`、运算符对齐）—— 都是几行的小修，但都是「静默给错数据」的类型。
4. **P0-3**（挂载 CodeMirror）+ **P1-5**（注释数值控件）—— 恢复两个被宣传的功能。
5. **P1-1**（因子编辑）+ 预校验把 warning 当失败。
6. **P1-7**（Origin/token 校验）—— 本地工具也要防浏览器侧 CSRF。
7. **P1-6**（超时与阻塞）—— 需要一点结构调整，可放在功能修完之后。
8. P2/P3 按表逐条清理；同时加 `.gitignore` 与「展示代码可执行」的回归测试。

---

## 附录：复现方式

```bash
# 全部走查结论的机器可验证版本（只写临时目录）
Rscript tests/review_findings.R
```

脚本逐段输出 A~J（11 组）证据，与上文编号对应。原有的 `tests/test_specs.R`、`tests/test_edits.R`、`tests/test_patchwork.R` 保持原样、仍然全绿。
