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

## 批次 9 — 拼图与扩展包（2026-11-04）

| 问题 | 改动 | 位置 |
|---|---|---|
| 拼图渲染报 `'package' must be of length 1` | `ggspec_compose_code()` 里的 `pkgs` 收集的是 `spec_to_code()` 返回的 `library(pkg)` 文本，又被二次包成 `library(library(pkg))`。改为先剥成包名再 union；同时去掉子图块里重复的 `library()` 行，只保留顶层一次 | [R/spec_to_code.R](R/spec_to_code.R) |
| 回归缺失 | `test_patchwork.R` 新增「ggprism 主题 + 标度」的拼图用例（两个 Prism 图），断言代码含 `library(ggprism)`、不含 `library(library(`，并真实渲染 | [tests/test_patchwork.R](tests/test_patchwork.R) |

触发条件：图库里的图用了扩展包（默认 Prism 主题就会带 `ggprism`），普通 ggplot2 图不会触发，所以此前测试没覆盖。
## 批次 10 — 走查修复（2026-11-09）

| 问题 | 改动 | 位置 |
|---|---|---|
| `theme_prism` 的 palette 等控件退化成文本框 | 扩展主题扫描在生成 args 后补 `.ggprism_theme_args()`，恢复 65 选 1 下拉 / 字号 / 边框控件 | [R/registry_core.R](R/registry_core.R) |
| 基线表 `add_p()` 失败被静默吞掉、生成代码不可跑 | 记录 `p_error` 写进 notes 与 `warnings`；生成代码对 `add_p` 与 Word 导出加 `requireNamespace("stringr")` 守卫，缺依赖时跳过并 message | [R/table1.R](R/table1.R) |
| 缺可选包时 5 个测试套件直接失败 | `ext_batch2/3`、`newscale` 缺少包时打印 `[SKIP]` 并以 0 退出；`ext_batch1` 的 ggtext 用例缺 stringi 时跳过 | `tests/test_ext_batch*.R`、`tests/test_newscale.R` |
| 「已安装但缺运行期依赖」误报为可用 | `ext_catalog()` 增加 `missingDeps`/`usable`（ggtext → stringi）；高级面板显示「缺依赖 stringi」标签 | [R/extensions.R](R/extensions.R)、[AdvancedPanel.vue](frontend/src/components/AdvancedPanel.vue) |
| 1100px 下图层名竖排 | `.layer-name` 加 nowrap + ellipsis | [LayerPanel.vue](frontend/src/components/LayerPanel.vue) |
| Positron 扩展：spawn 失败空等 60s、POSIX 留子进程、webview iframe 可能被 CSP 拦 | 增加 `proc.on('error')` 快速失败；POSIX 用 detached + 进程组 kill；心跳超时 120s；兜底改为系统浏览器打开；`@posit-dev/positron` 移到 devDependencies | [positron-ext/src/extension.ts](positron-ext/src/extension.ts)、[package.json](positron-ext/package.json) |
| 品牌改名不彻底 | README / REVIEW / UI_REVIEW / EXTENSIONS / RESEARCH_WORKFLOW 统一为 Glyph，并注明 `app: "ggplotgui"` 等兼容标识保留 | 各文档 |
| 未安装扩展无法在界面内处理 | 新增一键安装：白名单校验 + 后台 Rscript 安装 + 状态轮询 + 完成后自动重建注册表；高级面板对未安装/缺依赖显示「安装」按钮 | [R/ext_install.R](R/ext_install.R)、[AdvancedPanel.vue](frontend/src/components/AdvancedPanel.vue) |
| 安装/启停扩展后 `/api/meta` 仍返回旧注册表 | `run.R` 的 `STATE` 改为 environment（引用语义），请求内的 `state$meta <-` 才能真正生效 | [run.R](run.R) |

验证：全套测试 20 个套件全绿（3 个因缺少可选扩展打印 SKIP）；`test_extension_prism` 3/3、`test_table1_l5` 42/42；Positron 扩展 `tsc` 编译通过。
## 批次 11 — 数据导入向导（2026-11-09）

| 内容 | 说明 |
|---|---|
| 统一导入弹层 | 文件 / 剪贴板 / SQLite 三种来源；文件先配置（分隔符、编码、表头、跳过行、NA）再预览前 50 行 |
| 后端会话 | 上传一次返回 token，预览/建表/导入复用；预览只读前 N 行，提交才整表读入 |
| SQLite | 选择 .db/.sqlite 文件 → 表列表（含行数）→ 预览 100 行 → 导入；驱动缺失可一键安装 |
| 来源记录 | DataStore origin 落盘（kind/file/table/importedAt），重新加载仍在；供图注/可复现包使用 |
| 左栏入口 | 「添加数据」下拉改为「导入数据」按钮，导入后自动选中新数据源 |
| 测试 | 新增 tests/test_import.R（12 项：预览/类型/来源/持久化/SQLite/拒绝不支持类型） |
| P0 细节 | 文件大小、导入按钮显示总行数（文本按行数估算）、列统计页签内可改列类型、两步指示、更换文件/库 |
| 修复 | SQLite「选择数据库文件…」点击无反应：模板用了 `dbInput` 但未声明 ref，补 `const dbInput = ref(null)` | 
| 设计稿 | docs/import_mock_file.png、docs/import_mock_db.png |## 批次 12 — 远程数据库（P1，2026-11-09）

| 内容 | 说明 |
|---|---|
| 驱动 | PostgreSQL（RPostgres）、MySQL/MariaDB（RMariaDB）、ODBC；未安装可在面板内一键装 |
| 连接 | 主机/端口/库/用户/密码/SSL（ODBC 支持 DSN），测试连接返回版本与耗时 |
| 浏览 | schema 表列表（含估算行数）、只读预览 100 行、自定义 SELECT（单语句守卫，包一层 LIMIT） |
| 安全 | 连接对象只存后端内存（connId）；密码不回传/不落盘；短密码不做全局替换避免破坏错误信息 |
| 导入 | 表或查询结果快照进 DataStore，origin 记录 driver/host/database/schema/table |
| 测试 | 新增 tests/test_db_p1.R（18 项：SQL 守卫、标识符、驱动清单、错误脱敏、未知连接） |
| 边界 | 连接成功路径需真实数据库实例验证；保存的连接/keyring 留待 P2 |## 批次 13 — 导入弹层 v2 重构（2026-11-09）

| 内容 | 说明 |
|---|---|
| 顶部标签 | 文件 / SQLite / 远程数据库 / 剪贴板，无步骤条；标签按内容宽度，切换保留现场 |
| 远程库 | 三栏（连接 / schema 表树 / 预览）+ 常驻只读 SQL 条；连接状态放入 Pinia store，关闭弹层不断开 |
| 底部栏 | 来源靠左，数据源名称 + 取消 + 导入靠右，单行 |
| 文件 | 预览/列统计/原始文本、类型覆盖、文件大小、总行数 |
| SQLite | 表列表 + 预览 + 行数摘要 |
| 剪贴板 | 粘贴 → 解析预览 → 导入 |
| 交互说明 | docs/IMPORT_DIALOG_V2.md 更新为“已实现”，四张设计稿 docs/import_design_*.png |## 批次 14 — 数据源卡片列表（2026-11-09）

| 内容 | 说明 |
|---|---|
| 我的数据 | 左栏由下拉改为卡片列表：来源图标 + 名称 + 来源/维度，点击切换活动数据集，选中高亮 |
| 内置数据集 | 保留可搜索下拉，与「我的数据」分区，避免 50+ 数据集撑满左栏 |
| 删除 | 卡片 hover 出现删除按钮（popconfirm），删除后自动切换 |
| 滚动 | 卡片区最高 220px，选中项自动滚入可视区 |## 批次 15 — 列清单统一到加工后数据（2026-11-09）

- `/api/columns` 新增 POST：带 `prep`（filter/mutate/sample）时先走 `.prepared_full()`（含手工编辑），
  返回加工后的列；`.gg_rid` 不出现在列清单。
- 前端 `data.refresh()` 改为 POST 并携带当前加工配置；加工弹层「应用并刷新预览」同时刷新列清单，
  新增列会立即出现在左栏。
- 加工表达式暂时不合法时，列清单回退到原始列，避免面板突然清空（预览仍显示具体错误）。
- 行锚补全：导入提交（文件 / SQLite / 远程库）与 `DataStore` 加载旧数据时自动补 `.gg_rid`；
  `test_project_data` 比较时忽略锚列。
- 加工弹层「常用列」点击插入改为直接写 Vue 状态（默认行筛选，聚焦新增列则写该行），不再依赖 DOM 焦点。## 批次 16 — 「加工」更名「数据准备」与入口分层（2026-11-09）

- 按钮、弹层标题、重置按钮、提示文案统一改名「数据准备」；README 同步。
- 三个数据动作等宽均分（导入数据主按钮，数据准备 / 预览为次级按钮）。
- 数据集卡片 hover 增加「数据准备」快捷入口：先选中该数据集再打开弹层。
- 导入成功提示补充「可在『数据准备』中清洗与转换」。
- 位置维持数据面板顶部：准备是高频、作用于当前数据集，导入是低频一次性会话，两者不合并。## 批次 17 — 数据准备：过程可见（2026-11-09）

- 弹层顶部显示「原始 26×31 → 当前 24×31」，并注明原始数据不会被修改、可随时重置。
- 步骤摘要 chips：`新增 ratio`、`筛选 −2 行`、`抽样 100 行`，随输入实时更新。
- 可折叠查看生成的 R 代码（mutate / subset / sample + seed）。
- 新增 `POST /api/prep/summary`：逐步计算影响（mutate → filter → sample），最终行数列数取 `.prepared_full()`（含手工编辑）。
- 修复：`data_prepare` 定义处误合并换行（仅格式）。## 批次 18 — 数据准备：步骤化（2026-11-09）

- 弹层改为三张编号步骤卡：① 新增列 → ② 行筛选 → ③ 抽样。
- 每步可**单独停用/启用**：筛选 `filterDisabled`、抽样 `sampleDisabled`、新增列逐行 `disabled`；
  停用后预览行数、列清单、生成代码、汇总 chips 同步忽略该步。
- `data_prepare`、`data_prep_summary`、`spec_to_code` 三处统一尊重停用标记；
  历史项目没有标记时默认启用，无需迁移。
- 步骤顺序固定为 新增列 → 筛选 → 抽样（语义依赖：新列可被筛选使用），暂不支持拖拽重排。
- 前端所有 prep 请求（预览、列清单、统计、基线表、数据预览弹窗）补齐停用标记。## 批次 19 — 数据准备：类型转换（2026-11-09）

- 新增步骤①类型转换：逐行选择列 + 目标类型（num/chr/fct/lgl/date），可单独停用、删除、新增。
- 类型转换在新增列之前执行，后续筛选/派生使用转换后的类型。
- `data_prepare`、`data_prep_summary`、`spec_to_code` 均支持 `prep$types`，
  生成代码如 `df$年龄 <- as.character(df$年龄)`。
- 步骤编号更新：① 类型转换 → ② 新增列 → ③ 缺失值 → ④ 行筛选 → ⑤ 去重 → ⑥ 抽样。
- 所有前端 prep 请求（预览、列清单、统计、基线表、数据预览）补齐 types / dropna / dedup 字段。## 批次 20 — 数据准备：文本清洗（2026-11-09）

- 新增步骤②文本清洗：按列执行 去空格 / 转大写 / 转小写 / 替换（查找→替换为），逐行可停用、删除。
- 执行顺序：类型转换 → 文本清洗 → 新增列 → 缺失值 → 行筛选 → 去重 → 抽样。
- 后端 `data_prepare` / `data_prep_summary` / `spec_to_code` 支持 `prep$text`，
  记录影响行数（changed）并生成 `trimws` / `toupper` / `tolower` / `gsub` 代码。
- 清理了残留 R 服务进程后重启，验证 `/api/prep/summary` 返回 `text 备注 op=trim` 与对应代码。## 批次 21 — 数据准备：异常值（2026-11-09）

- 新增步骤③异常值：按数值列选择 IQR / z-score 与倍数 k，动作支持 标记 / 删除行 / 缩尾。
- 默认「标记」：新增 `<列>_outlier` 布尔列，不静默删数据；删除/缩尾需显式选择。
- 执行顺序：类型转换 → 文本清洗 → 异常值 → 新增列 → 缺失值 → 行筛选 → 去重 → 抽样。
- `data_prepare` / `data_prep_summary` / `spec_to_code` 统一支持 `prep$outliers`，
  生成边界与处理代码（quantile/mean+sd、pmax/pmin）。
- API 验证：`年龄` IQR 1.5 → 边界 39.375/94.375，步骤 `outlier 年龄 action=flag`。## 批次 22 — 数据准备：缺失值填充（2026-11-09）

- 新增步骤⑥缺失值填充：按列选择 常数 / 均值 / 中位数 / 众数，逐行可停用、删除。
- 执行顺序：类型转换 → 文本清洗 → 异常值 → 新增列 → 缺失值删除 → 缺失值填充 →
  行筛选 → 去重 → 抽样。
- `data_prepare` / `data_prep_summary` / `spec_to_code` 支持 `prep$fillna`，
  summary 返回 `filled` 个数并生成 mean/median/mode/常数填充代码。
- 修复 codegen 插入时丢失换行导致的 `}  if` 语法错误（已 parse 校验）。
- 验证：含 NA 数据 1,NA,3 → 均值填充为 1,2,3；字符列众数填充；步骤记录 filled=1。## 批次 23 — 数据准备：文本拆分列 + 填充（2026-11-09）

- 文本清洗新增「拆分列」：按分隔符拆成两个新列（可指定新列名），生成
  `tidyr::separate(...)` 代码。
- 新增缺失值填充步骤（常数/均值/中位数/众数），summary 记录 filled 数量。
- 步骤顺序：类型 → 文本 → 异常值 → 新增列 → 缺失删除 → 缺失填充 → 筛选 → 去重 → 抽样。
- 修复 codegen/摘要块插入时丢失换行导致的 `}  if`、`}    new` 语法错误（已 parse 校验）。
- 验证：code = "A-1","B-2" 拆分后得到 grp=A,B / num=1,2。## 批次 24 — 图库 P0：缩略图网格（2026-11-09）

- 图库改为缩略图卡片网格：预览图 + 名称 + 类型徽标 + 层数/数据源 + 操作
- 搜索框 + 类型筛选（全部 / 图 / 代码）
- 缩略图懒生成：spec 图按 spec 渲染 480×300，代码图按代码渲染，首次访问缓存到 Pxx.png
- 图库卡片显示代码图「代码」徽标，打开仍走缺包检查与代码恢复
- 验证：新建 spec 图缩略图 HTTP 200（37KB）；代码图卡片 img 自然宽 900## 仍未处理（有意留下）

1. **httpuv 单线程**：已用前端串行化 + 长超时缓解，但重渲染期间取图仍会排队；彻底解决需要异步任务队列或子进程渲染。
2. **`state$raw_data` 全局**：原始代码模式的 df 仍挂在全局，多标签页并发时可能互相覆盖。
3. **预览图仍走「渲染 + 二次取图」**：极端时序下（渲染中立刻再渲染）可能取到上一张图。
4. **`Rplots.pdf` / `rt2.json`**：仓库里的历史产物，已在 `.gitignore` 中忽略，但文件仍在，可自行删除。
5. **`exprInsert` 的全局焦点元素**未在弹窗关闭时清理（影响很小）。
