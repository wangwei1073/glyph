# ggplotGUI · ggplot2 可视化工作台

一个**本地 GUI 绘图工具**：用可视化界面构建任意 ggplot2 图形，实时生成**规范、可复制的 R 代码**。
覆盖最新 **ggplot2 4.0.x**（S7 架构）的全部图表类型与设置能力。

界面为三段式：左数据 / 中画布 / 右控制。

## 快速开始

环境要求：**R ≥ 4.2**（推荐 4.6+，并已安装 ggplot2 ≥ 3.5；依赖的扩展包按需自动识别）。

- **Windows**：直接双击 `run_app.bat` —— 自动找到 R、启动服务并打开浏览器。
- 其他平台：
  ```bash
  Rscript run.R            # 打开 http://127.0.0.1:4321
  ```

生成的代码可在「代码」标签一键复制 / 下载 `.R`，粘贴到 RStudio / Positron 即可复现图形。

## 功能总览

### 数据
- 40+ 内置数据集（ggplot2 的 mpg / diamonds / economics… 与 base R 数据集）
- 上传 CSV / TSV / TXT / XLSX / XLS / RDS / JSON / RData
- 粘贴表格文本（自动识别逗号/制表符分隔）
- 数据加工：行筛选（R 表达式）、新增列、随机抽样 + 种子
- 列面板带类型徽标（numeric / character / factor / date…）与唯一值预览

### 图层（graph 类型全覆盖）
- **全部 58 个 ggplot2 geom**（运行时从已安装版本自动枚举，永不缺漏），
  加上已安装扩展：ggrepel、ggthemes 的 geom
- 选择器带**示意图缩略图**（3 列卡片，可搜索中文名 / 英文名 / 函数名），
  tooltip 显示「说明 · 函数名 · 需要映射的 aes」
- 分组可在「**按图形族**」（点与线 / 分布 / 区间…）与「**按数据形态**」
  （一变量连续 / 两变量离散×连续 / 三变量…，即 cheatsheet 的组织方式）之间切换，选择会记住
- 每层可组合任意 **stat**（stat_bin / stat_summary / stat_smooth … 全部 30 个）与
  任意 **position**（dodge / stack / fill / jitter / nudge…，含参数）
- 图层排序、复制、删除；show.legend / inherit.aes 开关

### 美学与参数
- 每个 geom 自动提示 required / optional 美学映射
- **映射 vs 常量**双模：选数据列，或直接设定 size/shape/colour…（控件按类型渲染：颜色选择器、shape 线型预览、数值微调）
- **R 表达式模式（fx）**：任何映射/参数可切换为 R 代码，如 `after_stat(count)`、`hwy / displ`
- geom / stat / position 参数表单由元数据自动生成（binwidth、bins、method、se …）

### 标度 · 坐标 · 分面
- 全部 scale 家族按 aesthetic 分组（continuous / discrete / binned / date / manual /
  brewer / gradient / gradient2 / viridis / hue / grey / reverse / log10 / sqrt …），
  含 **sec_axis 次轴**、轴位置、expansion、变换
- ggsci 学术配色、ggthemes 标度与 **ggprism 的 65 套 Prism 配色**（自动识别）
- 坐标系：cartesian / fixed / polar / radial / sf / map / trans…（含 4.0 新 API；
  flip 以 superseded 标注）
- facet_wrap / facet_grid 全参数（scales、space、margins、labeller…）

### 标签 · 图例 · 注释 · 主题
- labs 全字段 + 按映射的图例标题
- guides：legend / colorbar / bins / colorsteps / axis…（含参数），装 ggprism 后还有
  **次刻度 / 偏移轴 / 括号**四种 Prism 轴样式
- annotate()（任意 geom）与 annotation_logticks 等函数；ggprism 的 annotation_ticks 轴刻度
- **全部 160+ 个 theme() 元素**：中文标签、按类型（text / line / rect / …）渲染对应属性；
  9 个内置主题 + ggthemes 主题 + **ggprism 的 Prism 期刊风主题**；base_family 支持微软雅黑/黑体等中文字体预设
- **默认出图风格**：Prism 期刊风（`theme_prism` + `floral` 配色），新建图时自动套用；
  在「主题」「标度」面板可随时更换（未安装 ggprism 时自动回落为 minimal）

### 输出
- 实时自动渲染（可暂停手动），预览尺寸 / dpi 可调
- **物理尺寸模式**：按 mm 设置预览与导出尺寸（单栏 85 / 1.5 栏 114 / 双栏 170 / Nature 89 预设），
  自动换算像素；界面提示字号以 pt 输出、与 dpi 无关
- 导出 **PNG（300dpi）/ SVG / PDF** 矢量
- **导出前检查**：白底 / 分辨率 / 物理尺寸 / 矢量格式 / 字体可用性 / 最小字号 / 能否真正渲染；
  有警告或失败时弹窗列出原因，可选择「仍然导出」；也可从导出菜单单独触发
- **可复现包（.zip）**：一次导出 图（PNG+PDF）+ 原始数据 CSV + 可运行 `figure.R` +
  `sessionInfo.txt` + 图注草稿 + 项目文件；解压后 `Rscript figure.R` 即可复现
- **期刊模板**：Nature / Science / Cell / PLOS / IEEE / 中文核心 / 通用，按模板检查栏宽、字号下限、
  字体白名单、格式与 dpi，并给出一键修复（套用栏宽、补 300dpi、提字号、改白底/字体/格式）
- 交互式 plotly 预览（自动转换，部分 geom 不支持）
- **项目保存 / 载入**（JSON 格式，随时续作）：上传/粘贴的数据会以 CSV 快照内嵌进项目文件，
  手工编辑一并带上，换机器或重启后可直接打开；本机上传数据同时落盘在 `userdata/`
- **自动保存草稿**：编辑过程中每 1.5s 存一份本机快照，崩溃 / 误关后重开可一键恢复；
  顶栏常驻「新建 / 未保存 / 已保存」状态
- 高级模式：原始代码编辑器（CodeMirror，R 高亮），直接改代码运行；数据以 `df` 变量提供

## 架构与目录

```
├── run.R                 # 启动：httpuv 服务 (127.0.0.1:4321)，伺服 dist/ + /api/*
├── run_app.bat           # Windows 一键启动
├── R/                    # 后端（纯 R，零额外安装）
│   ├── registry_core.R   #   运行时枚举已装 ggplot2 的全部 geom/stat/scale/coord/…（自省）
│   ├── registry_meta.R   #   中文标签 / 分组 / 控件元数据覆盖表
│   ├── spec_to_code.R    #   绘图规格(JSON) → 规范 R 代码（唯一事实来源）
│   ├── render.R          #   代码求值 + ragg 渲染 + 导出 + plotly 转换
│   ├── datasets.R        #   内置数据集注册表
│   ├── dataio.R          #   上传/粘贴/加工
│   └── api.R             #   HTTP 路由 + 静态文件
├── frontend/             # Vue 3 + Element Plus + Pinia 前端源码
│   ├── public/geom-thumbs/   # geom 示意图（由 tools/make_geom_thumbs.R 生成，构建时拷进 dist）
│   └── (npm run build → ../dist)
├── tools/
│   └── make_geom_thumbs.R    # 重新生成 geom 示意图（改了主题/默认值后跑一次）
├── dist/                 # 构建产物（已提交；R-only 用户无需 Node）
└── tests/                # test_specs / test_codegen_exec / test_edits / test_patchwork / test_api_guard
```

**核心设计**：界面只产出声明式「绘图规格 (spec)」→ 后端把 spec 编译为 R 代码 →
渲染 = eval 该代码。**代码面板与图形共用同一份代码**（含筛选/新增列/抽样/手工编辑
的可复现语句）；注册表运行时自省，随 ggplot2 版本升级自动同步。

## 开发

```bash
# 前端热更开发（需 Node ≥ 18）
cd frontend && npm install && npm run dev   # http://localhost:5180（代理 /api → 4321）

# 后端
Rscript run.R --no-browser

# 测试（全部在项目根目录运行）
Rscript tests/test_specs.R          # 29 个代表性 spec：生成 → 解析 → 渲染
Rscript tests/test_codegen_exec.R   # 展示代码必须可执行，且数据与渲染路径一致
Rscript tests/test_edits.R          # 手工编辑引擎 + 行锚 + 因子列
Rscript tests/test_patchwork.R      # 图库存取 + 拼图组合
Rscript tests/test_api_guard.R      # 请求来源校验（防跨站 / DNS 重绑定）
Rscript tests/test_project_data.R   # 项目数据：落盘 / 快照 / 重建 / 手工编辑恢复
Rscript tests/test_bundle.R         # 可复现包：图 + 数据 + 代码 + 图注 + 项目文件
Rscript tests/test_export_check.R   # 导出前检查：白底 / dpi / 尺寸 / 字号 / 可渲染性

# 重新生成 geom 示意图（改了默认主题/映射后跑一次，产物在 frontend/public/geom-thumbs）
Rscript tools/make_geom_thumbs.R
```

## 常见问题

- **中文乱码**：主题面板把 base_family 设为「微软雅黑」即可；PNG 走 ragg 引擎，默认无碍。
- **首次启动较慢**：元数据注册表需枚举全部 geom/scale（约 1–10 秒）。
- **端口冲突**：`run_app.bat` 或手动 `Rscript run.R --port 4322`。
- **大图渲染慢**：后端是单线程 httpuv，一次重渲染会阻塞其它请求（包括取图）；
  渲染已在前端串行化并给到 300s 超时，数据量大时建议先抽样（数据 → 加工 → 抽样）。
- **上传体积**：单文件上限 35MB（请求体 base64 后约 47MB，受后端 50MB 限制）。
- **选 Prism guide 后出现 S3 弃用警告**：ggprism 的 guide 仍基于 ggplot2 旧 S3 机制
  （ggplot2 4.0 已弃用但兼容），功能正常；标度与主题不受影响。
- **只能本机访问**：默认绑定 127.0.0.1，并校验 Host/Origin/Content-Type，防止网页跨站调用；
  如需局域网访问请显式 `--host 0.0.0.0`（会放宽 Host 校验，请自行评估风险）。
- dev 模式下 vite 代理对 >64KB 响应有截断问题（生产模式无代理，不受影响），
  建议直接运行 `run_app.bat`（生产形态）。

## 依赖

后端：R、ggplot2、httpuv、jsonlite、ragg（PNG）、readr/readxl（导入）、
自动识别：ggsci / ggthemes / ggprism / ggrepel / patchwork / plotly / scales。
前端：Vue 3、Element Plus、Pinia、CodeMirror 6、plotly.js。
