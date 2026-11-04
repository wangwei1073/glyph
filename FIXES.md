# 修复记录（对应 [REVIEW.md](REVIEW.md)）

按批次修复，每批改完都跑回归。所有结论均可用脚本复现：

```bash
Rscript tests/test_specs.R          # 29/29
Rscript tests/test_codegen_exec.R   # 9/9（新增：展示代码必须可执行且数据一致）
Rscript tests/test_edits.R          # 全通过（新增因子列用例）
Rscript tests/test_patchwork.R      # 全通过
Rscript tests/test_api_guard.R      # 7/7（新增：来源校验）
Rscript tests/review_findings.R     # 走查证据脚本，逐条对照修复状态
```

---

## 批次 1 — 数据链路与代码生成（P0-1 / P0-2 / P1-2 / P1-3 / P1-4）

| 问题 | 改动 | 位置 |
|---|---|---|
| 上传数据预览/编辑 400 | 新增 `src_id_of()`，`id`/`name` 两种写法统一；`.keyof()` 只保留一份并兼容两者；`render.R` 改用 `.keyof()` | [R/dataio.R](R/dataio.R)、[R/api.R](R/api.R)、[R/render.R](R/render.R) |
| 行筛选代码不可执行 | 生成 `df <- subset(df, <expr>)`（`subset()` 按列名求值且自动剔除 NA 行），替换 `df[<expr>, ]` | [R/spec_to_code.R](R/spec_to_code.R) |
| 筛选+编辑行锚错位 | `.gg_rid` 赋值移到筛选/抽样**之前**；内联数据不再带 `.gg_rid` 列 | [R/spec_to_code.R](R/spec_to_code.R) |
| 空 rowIns 丢弃编辑语句 | `return()` → `next`；rowIns 自动补 `.gg_rid = max(...) + 1L` | [R/spec_to_code.R](R/spec_to_code.R) |
| 拼图运算符错位 | `used_ops` 只收集成功解析的槽位；运算符取值改为 `used_ops[j]`（与 PinPanel 的「存在后一个槽位」语义一致） | [R/spec_to_code.R](R/spec_to_code.R) |

新增回归：[tests/test_codegen_exec.R](tests/test_codegen_exec.R) —— 9 个场景把展示代码**真的执行一遍**，并与渲染路径的数据逐列比对（含 mpg/economics/iris、筛选、新增列、抽样、cell/rowDel 编辑、内联用户数据）。

## 批次 2 — 分页（P0-4）

- `start` 超过总行数时夹到最后一页；`length` 夹到 1..1000；`idx` 用 `seq.int` 且 `total == 0` 返回空。
- 修复前：`start=1000`（mpg 234 行）返回 **767 行全 NA**；修复后返回最后一页 50 行。
- 位置：[R/api.R](R/api.R) `/api/data/preview`。

## 批次 3 — 前端两处「功能没接上」（P0-3 / P1-5）

- **CodeMirror 从未初始化**：补 `onMounted(initEditor)`、`onBeforeUnmount(destroy)`，用 `initPromise` 防并发重复初始化；`loadFromSpec()` 改为 async 并确保编辑器就绪；`runRaw()` 对空代码给出提示。位置：[AdvancedPanel.vue](frontend/src/components/AdvancedPanel.vue)。
- **注释坐标被加引号**：新增 `numberOrExpr` 控件（输入 `5` → 数字 5；输入 `mean(df$x)` → R 表达式），注释的 x/y/xmin/xmax/ymin/ymax/xend/yend 全部改用它。位置：[ParamControl.vue](frontend/src/components/ParamControl.vue)、[AnnotatePanel.vue](frontend/src/components/AnnotatePanel.vue)。

## 批次 4 — 手工编辑与校验（P1-1）

- `.coerce_value()` 增加 factor 分支；cell 写入走 `.set_factor_cell()`，自动追加水平（不再静默变 NA）。
- rowIns 的因子列按 `union(levels)` 对齐后再 `rbind`，避免类型不匹配；空列模板改用 `.template_of()`。
- `/api/edits/add` 的预校验把 **warning 也视为失败**（`withCallingHandlers` + `stop`）。
- 位置：[R/dataio.R](R/dataio.R)、[R/api.R](R/api.R)；回归用例加到 [tests/test_edits.R](tests/test_edits.R)。

## 批次 5 — 请求来源校验（P1-7）

- 新增 `.request_guard()`：① Host 白名单（防 DNS 重绑定）② `Origin` 必须与 `Host` 同源 ③ `Sec-Fetch-Site: cross-site` 直接拒 ④ POST 必须 `Content-Type: application/json`（强制 CORS 预检）。
- `run.R` 注入 `allowed_hosts`；`--host 0.0.0.0` 时显式放宽 Host 校验。
- 位置：[R/api.R](R/api.R)、[run.R](run.R)；回归 [tests/test_api_guard.R](tests/test_api_guard.R)（10 项，含 `text/plain` 简单请求与 `Host: evil.example`）。
- **回归修补（同日）**：首版 `.host_name()` 忘了去掉 `Origin` 的 scheme，导致同源 POST 也被判成跨站（界面报「预览加载失败: 跨站请求被拒绝」）。已改为 `authority`（host:port）比较并保留「端口缺省时只比主机名」的回退；测试补了 3 条**正向**用例（同源 `127.0.0.1`、同源 `localhost`、同主机不同端口应拒），此前只有负向用例才漏掉了这个 bug。

## 批次 6 — 超时与阻塞（P1-6）

- `api.js` 分路由超时：普通 20s，渲染/导出/plotly 300s，上传不设限；超时给出可读错误（原来统一 20s，重图必失败）。
- 渲染串行化：`renderNow()` 在渲染中只置 `renderQueued`，结束后自动补一次，避免请求堆积把单线程后端压死。
- 位置：[frontend/src/api.js](frontend/src/api.js)、[frontend/src/stores/spec.js](frontend/src/stores/spec.js)；README 补充了单线程说明。

## 批次 7 — 健壮性与整洁度（P2/P3 节选）

| 项 | 改动 |
|---|---|
| `NA` 被序列化成 `"NA"` | `r_string()` 对 `NA` 返回 `NA`（[R/utils.R](R/utils.R)） |
| 筛选返回数值被当行号 | `data_prepare()` 校验 `is.logical(keep)`，报「必须返回 TRUE/FALSE」 |
| 请求体过大信息不可读 | `GG_BODY_LIMIT` 显式检测并报「上限 50MB」；前端上传前拦截 >35MB（[api.js](frontend/src/api.js)） |
| pins/edits 非原子写 | 新增 `write_file_atomic()`（临时文件 + rename，Windows 回退覆盖拷贝） |
| `run.R` 混用 `getwd()` | `root <- scriptdir`，从任意目录启动都成立 |
| 静态文件路径清洗 | `normalizePath` 后做根目录包含校验，越界返回 403 |
| 调试接口 `/api/ping` | 删除 |
| 数据集枚举无缓存 | `GGSPEC_DATASET_LIST` 缓存（每次 `/api/sources` 不再全量 `get()`） |
| `.scale_call` 重复查表 | 删除冗余分支 |
| plotly 首屏预加载 4.7MB | 去掉 `manualChunks` 手写分组，改为自然分包；`dist/index.html` 不再 `modulepreload` plotly |
| 死代码 | `meta.js` 的 `* 0` 排序项、`Canvas.resetCompose`、`DataPanel` 未用导入、`ThemePanel` 三个未用 helper |
| `ElMessageBox` 未导入 | 列改名会直接 ReferenceError，已补导入；改名/删列失败不再假报成功，取消 prompt 不再抛未捕获异常 |
| 编辑条数恒为 0 | `/api/edits?key=` 改用 `dataset:mpg` / `user:u1` 格式，并在弹窗顶栏显示「手工编辑 N 条」 |
| 切数据源留失效映射 | 新增 `spec.pruneMappings()`，`data.refresh()` 后清理指向旧列的 aes 与分面变量 |
| 项目载入不深合并 / 数据面板不同步 | `loadProject()` 逐层补默认值；载入后把 `spec.data.source` 同步到左侧数据面板 |
| 映射↔常量切换产生 `colour = "class"` | 切换时清空重选，并用本地 mode 记住选择（不再被推断回「映射」） |
| 拼图槽位只能上移 | 补「下移」按钮 |
| 标度面板「已有，将覆盖」不实 | 文案改为「（已有）」 |
| 仓库卫生 | 新增 [.gitignore](.gitignore)（pins.json / edits.json / Rplots.pdf / tests/out / node_modules / _dist_check） |

---

## 验证记录

| 检查 | 结果 |
|---|---|
| `Rscript tests/test_specs.R` | 29 通过 / 0 失败 |
| `Rscript tests/test_codegen_exec.R` | 9 通过 / 0 失败 |
| `Rscript tests/test_edits.R` | 全部通过（含因子列） |
| `Rscript tests/test_patchwork.R` | 全部通过 |
| `Rscript tests/test_api_guard.R` | 7 项全部通过 |
| `npm run build` | 通过；`dist/index.html` 不再预加载 plotly |
| 真实服务端到端（httpuv 4323 端口） | 上传 CSV → 预览 3 行 → 编辑 → 渲染 → 取图 5.9KB 全通；`/../run.R`、`/%2e%2e/run.R`、`/assets/../../run.R` 均回落到 index.html（无穿越）；`text/plain`、跨站 Origin、`Host: evil.example` 均 403 |

## 批次 8 — 界面改进（走查后追加）

| 项 | 改动 |
|---|---|
| 标签统一中文 | 59 个 geom + 30 stat + 8 position + 11 coord + 12 guide + 30 标度类型全部改为纯中文；R 函数名改在 tooltip / 选项右侧显示（[registry_meta.R](R/registry_meta.R)、[registry_core.R](R/registry_core.R)） |
| 补齐缺失标签 | 8 个原本回退成英文/包名的 geom（curve、bin2d、density2d、density2d_filled、marquee_repel、rangeframe、tufteboxplot…）补上中文标签并归入正确分组 |
| 修掉假 geom | `geom_column` 是取 sf 几何列名的**内部工具函数**，被注册表当成 geom 列在"添加图层"里，点了必报错。现在「拿不到 LayerInstance 且匹配不到 Geom 对象」的函数会被跳过（58 个 geom） |
| 修掉假 guide | guide 列表里混入 7 个内部泛型方法（guide_train / guide_gengrob / guide_geom / guide_grid / guide_merge / guide_transform 及 .default），选到会生成非法代码；已剔除，并补回被误排除的 guide_custom |
| geom 示意图 | 新增 [tools/make_geom_thumbs.R](tools/make_geom_thumbs.R)：为每个 geom 生成 96×72 示意图（走同一条 spec→代码→渲染 管线），产物在 `frontend/public/geom-thumbs/`（58 张，51 张真实渲染 + 7 张占位）；选择器改为 3 列卡片网格，tooltip 显示「说明 · 函数名 · 需要映射的 aes」 |
| 分组切换 | geom 选择器支持「按图形族 / 按数据形态」两种分组（后者即 cheatsheet 的一变量/两变量/三变量/地图组织方式），选择写入 localStorage；分类表在 [registry_meta.R](R/registry_meta.R) 的 `GEOM_SHAPE`（每个 geom 单归属，11 组） |
| 预览表格紧凑化 | 字号 11.5px、行高 ~19px、表头按钮缩小并悬停变实、行悬停高亮 |
| 映射操作左移 | 新增 [ColumnActions.vue](frontend/src/components/ColumnActions.vue)：点击左栏列行就地展开「映射到第 N 层（按 geom 过滤 aes）+ 插入列名 + 统计 + 取值预览」，预览弹窗的列菜单复用同一组件 |

## 仍未处理（有意留下）

1. **httpuv 单线程**：已用前端串行化 + 长超时缓解，但重渲染期间取图仍会排队；彻底解决需要异步任务队列或子进程渲染。
2. **`state$raw_data` 全局**：原始代码模式的 df 仍挂在全局，多标签页并发时可能互相覆盖。
3. **预览图仍走「渲染 + 二次取图」**：极端时序下（渲染中立刻再渲染）可能取到上一张图。
4. **`Rplots.pdf` / `rt2.json`**：仓库里的历史产物，已在 `.gitignore` 中忽略，但文件仍在，可自行删除。
5. **`exprInsert` 的全局焦点元素**未在弹窗关闭时清理（影响很小）。
