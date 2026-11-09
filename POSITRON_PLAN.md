# Glyph for Positron · 插件版实施计划

> 版本：v1.0 计划　｜　日期：2026-11-09
> 前置：最小验证原型已通过（见 [POSITRON_PROTOTYPE.md](POSITRON_PROTOTYPE.md)）
> 环境基线：Positron 2026.09.1（Code OSS 1.130.0）、Node ≥ 18、R 4.6.1

---

## 一、目标与边界

### 1.1 一句话目标

让 Glyph 成为 Positron 里**可以被发现、被调用、能反哺 Console** 的一等公民，而不是"点开弹出个网页"。

### 1.2 三级目标（决定投入多少）

| 级别 | 产出 | 判断标准 |
|---|---|---|
| **L1 · 可用** | 能在 IDE 内打开完整 Glyph，服务生命周期干净 | 用户不必知道背后有 R 子进程 |
| **L2 · 好用** | 与 R 会话双向联动 | 生成的代码能一键送进 Console；能用当前环境里的数据 |
| **L3 · 可分发** | 上架 Open VSX，有图标/文档/更新机制 | 陌生人能搜索安装 |

**本计划按 L1 → L2 → L3 推进**，每个阶段都可独立交付、独立验收。

### 1.3 明确不做

| 不做 | 原因 |
|---|---|
| 把前端改写为 Positron 原生视图 | 6591 行 Vue 资产是最大存量价值，重写等于放弃 |
| 内置 R 运行时 | 与桌面打包同一个坑，目标用户几乎必然已装 R |
| 在插件内实现绘图渲染 | 现有 `spec → 代码 → eval` 管线已经是可复用的正确抽象 |
| RStudio 版本 | RStudio 无 webview，Shiny Gadget 装不下三段式界面（详见可行性分析） |

---

## 二、总体架构

### 2.1 进程与通信模型

```
┌──────────────────────────────────────────────────────┐
│ Positron 主进程                                       │
│  ┌────────────────────────────────────────────────┐  │
│  │ 扩展宿主 (Extension Host, Node)                 │  │
│  │  - 定位项目、选端口、spawn R                    │  │
│  │  - 心跳保活（10s）                              │  │
│  │  - 命令/菜单/状态栏注册                          │  │
│  └───────────────┬────────────────────────────────┘  │
│                  │ spawn                              │
│  ┌───────────────▼──────────────┐   HTTP (127.0.0.1) │
│  │ Rscript run.R (Glyph 后端)    │◄──────────────┐    │
│  │  - httpuv 服务                │               │    │
│  │  - 心跳超时自杀（60s）         │               │    │
│  └───────────────────────────────┘               │    │
│  ┌──────────────────────────────────────────────┴─┐  │
│  │ Preview 面板（webview，源=http://127.0.0.1:port）│  │
│  │  - 现有 Vue 前端，零改动                        │  │
│  └────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────┘
```

### 2.2 关键设计决策（均已由原型验证）

| 决策 | 选择 | 理由 |
|---|---|---|
| 界面承载 | `positron.window.previewUrl` | webview 源 = 本地服务，前端相对路径 `/api/...` 原样可用 |
| 服务停止 | `startServer` + `service(20)` 轮询 + env 标志位 | `runServer` 是 C 层阻塞，请求内停不掉 |
| 孤儿防护 | 心跳（扩展 10s ping，R 侧 60s 无心跳自杀） | PID 判断不可靠；stdin 阻塞读会卡死事件循环 |
| 代码回传 | `positron.runtime.executeCode('r', code, focus)` | 官方 API，且有 `observer` 可拿输出 |
| 数据互通 | `positron.runtime.getSessionVariables` + `evaluateCode` | 读变量树；必要时用 `evaluateCode` 静默取 df |
| **数据根** | **`--data-dir <workspace>/.glyph`** | 图库/上传数据随项目走，切项目不串台 |
| **导出** | **`--export-dir` + `showSaveDialog`** | 用户明确选择落盘位置，默认指向 `<workspace>/figures/` |

---

## 三、阶段拆解

### 阶段 0.5 · 项目目录语义改造（1.5 天）★ 插件版新增，不可省略

> **这一阶段是原计划的重大遗漏。** 当前实现把「程序目录」和「数据目录」混为一谈，
> 在 IDE 里会直接产生错误行为，必须先修。

#### 问题现状

`run.R` 里 `root <- scriptdir`，一个变量同时承担三个角色：

```r
root <- scriptdir                                    # 程序目录（run.R 所在处）

DataStore$bind(file.path(root, "userdata"))          # 上传的数据
pin_file = file.path(root, "pins.json")              # 图库
EditStore$bind(file.path(root, "edits.json"))        # 手工编辑
ext_state_bind(file.path(root, "extensions.json"))   # 扩展开关
plot_dir = file.path(tempdir(), "ggplotgui-plots")   # 渲染/导出中转（临时目录）
```

在浏览器用法下（双击 bat、单项目）这没问题。但插件版中：

| 症状 | 后果 |
|---|---|
| 用户打开 A 项目，图库和上传数据落在 Glyph 安装目录 | **切换项目时数据串台**，A 项目的图库出现在 B 项目里 |
| `pins.json` 写到程序目录 | 若 Glyph 装在只读位置（Program Files / 容器），**直接写失败** |
| 导出的图先落 `tempdir()` 再由浏览器下载 | **无法落进项目目录**，与用户"文件都在项目里"的预期直接冲突 |

#### 要做的改造

**1) 拆分目录语义（0.5 天）**

```r
# 新增参数
DATA_ROOT <- .getarg("--data-dir", scriptdir)   # 可写数据根，默认保持旧行为

DataStore$bind(file.path(DATA_ROOT, "userdata"))
pin_file = file.path(DATA_ROOT, "pins.json")
EditStore$bind(file.path(DATA_ROOT, "edits.json"))
ext_state_bind(file.path(DATA_ROOT, "extensions.json"))
```

`dist` 仍从 `scriptdir` 取（程序资源），`DATA_ROOT` 只管可变数据。**默认值不变**，所以现有 bat 用法零影响。

**2) 导出目录参数（0.5 天）**

```r
EXPORT_DIR <- .getarg("--export-dir", "")       # 空 = 走临时目录 + 浏览器下载（旧行为）
```

- `/api/export` 若 `EXPORT_DIR` 非空，直接写该目录并返回绝对路径
- 新接口 `POST /api/export-to`：body 带 `{path}`，服务端校验路径合法性后写入
- 保留 `/api/plotfile/<fn>` 供预览与旧流程使用

**3) 插件侧接线（0.5 天）**

| 项 | 实现 |
|---|---|
| 数据根 | `--data-dir <workspaceFolder>/.glyph`（工作区内，随项目走） |
| 首次创建 | 目录不存在时自动创建，并写入 `.gitignore`（避免 pins/上传数据被提交） |
| 多工作区 | 每个 workspaceFolder 各自一份 `.glyph/`，天然隔离 |
| 导出 | 走 `vscode.window.showSaveDialog`，`defaultUri` 指向 `${workspaceFolder}/figures/` |

**4) 数据目录布局**

```
<workspace>/
├── .glyph/
│   ├── pins.json          # 图库（随项目）
│   ├── edits.json         # 手工编辑
│   ├── extensions.json    # 扩展开关
│   └── userdata/          # 上传/粘贴的数据
├── figures/               # 导出的图（用户可见，可直接放进论文）
└── .gitignore             # 自动追加 .glyph/
```

> `figures/` 与 `.glyph/` 分开：前者是用户资产、应该提交；后者是本机状态、应该忽略。

#### 验收

- [ ] 工作区 A 存的图，切到工作区 B 后**看不到**
- [ ] 导出的 PNG 出现在 `<workspace>/figures/`，保存框默认路径正确
- [ ] 删除 `.glyph/` 后重新打开，服务正常重建目录
- [ ] 不传 `--data-dir` 时行为与改造前**完全一致**（bat 回归）
- [ ] `.glyph/` 被自动加入 `.gitignore`

---

### 阶段 0 · 工程化收尾（0.5 天）

**目标**：把原型代码整理成可维护工程，不留技术债。

| 任务 | 产出 | 验收 |
|---|---|---|
| 工程分层 | `src/` 拆为 `extension.ts`（注册）、`server.ts`（进程管理）、`locate.ts`（项目定位）、`positron.ts`（API 适配） | 单文件 < 200 行 |
| 配置项补全 | `glyph.projectPath` / `glyph.rscriptPath` / `glyph.extraArgs` / `glyph.heartbeatTimeout` / `glyph.autoStart` | 设置面板可见且有描述 |
| 错误分类 | 区分「找不到项目」「R 未安装」「端口耗尽」「启动超时」「被其他实例占用」 | 每类有独立、可操作的提示文案 |
| ESLint + 格式化 | `.eslintrc`、`prettier` | `npm run lint` 通过 |
| 单元测试骨架 | `server.test.ts`（端口选择、路径解析纯函数） | `npm test` 可跑 |

**交付物**：重构后的 `positron-ext/`，功能等价于原型。

---

### 阶段 1 · 服务生命周期健壮性（0.5 天）
**目标**：让"服务管理"这件事在异常路径下也不出错。

| 任务 | 说明 |
|---|---|
| 单例保护 | 同一 IDE 内多次执行「打开」不重复 spawn；已有服务则直接 reveal 面板 |
| 多工作区 | 不同窗口各自维护自己的服务，互不干扰（按 `workspaceFolder` 隔离） |
| 端口回填 | 记住上次使用的端口，避免每次都从 4330 线性探测 |
| 启动进度 | 用 `vscode.window.withProgress` 显示「正在启动 R 服务…（约 3–8 秒）」 |
| 崩溃恢复 | R 进程意外退出时自动重启一次，并提示用户 |
| 清理兜底 | `deactivate` + 进程 `exit` 事件 + 心跳，三重保障 |

**验收清单**：

- [ ] 连点 5 次「打开」，只有 1 个 R 进程
- [ ] 两个窗口各开一次，互不影响，各自端口不同
- [ ] 手动 `taskkill` R 进程后，插件 5 秒内提示并自动重启
- [ ] 强杀 IDE，60 秒后无残留（原型已验证）

---

### 阶段 2 · 与 R 会话联动（1.5 天）★ 关键里程碑

**目标**：这是判断插件值不值得做下去的分水岭。做完后 Glyph 从"外挂网页"变成"工作流的一部分"。

#### 2.1 代码回传（0.5 天）

Glyph 的代码面板已有「复制」按钮。在插件内应能**直接送进 Console**：

| 入口 | 实现 | 可行性 |
|---|---|---|
| 插件命令 | `Glyph: 把当前代码发送到 Console`：取 `/api/code` 拿文本 → `executeCode('r', code, true)` | ✅ 确定可行 |
| Preview 面板停止按钮 | `previewUrl(url, { type: 'runtime', id: sessionId })` → Viewer 自动显示停止按钮，监听 `onDidRequestStop` | ✅ API 已确认存在 |
| 网页内自定义按钮 | 现有前端不变的前提下无法注入 bridge | ⚠️ 见下 |

**关于网页内按钮**：`previewUrl` 返回的 `PreviewPanel` **确实带 `.webview` 属性**，理论上可 `webview.onDidReceiveMessage`，但网页侧仍需 `acquireVsCodeApi()`——该函数由 VS Code 在 webview 加载时注入，`previewUrl` 加载的是**外部 http 源**，不会注入。

因此：
- **可行**：命令拉取代码 + 送 Console（阶段 2.1 主线）
- **可行**：用 Viewer 原生停止按钮（`PreviewSource` + `onDidRequestStop`），比自造按钮更地道
- **不可行（除非改前端）**：网页里点「发送到 Console」

> 若未来确实要网页内按钮，需把前端从 `previewUrl` 改为自建 `createWebviewPanel` 并注入 bridge —— 代价是绝对 URL + CSP + 同源校验全要改，**约 +1.5 天**。建议先用命令入口，收集反馈再定。

#### 2.1b Viewer 原生集成（顺带，0.2 天）

利用 `PreviewPanel` 的这些能力提升"像原生"的程度：

| API | 用途 |
|---|---|
| `previewUrl(url, source)` + `stoppable` | 地址栏出现停止按钮，点它触发 `onDidRequestStop` → 停服务并 dispose 面板 |
| `panel.reveal()` | 重复执行「打开」时复用面板而非新建 |
| `panel.onDidDispose` | 面板关闭时可选择是否停服务（建议保留服务，下次秒开） |
| `panel.title` | 显示 `Glyph — <数据名>`，让用户知道当前画的是什么 |

#### 2.2 使用当前环境数据（1 天）

用户场景：Console 里已有 `df`，想在 Glyph 里画它。

| 步骤 | 实现 | 关键 API |
|---|---|---|
| 取会话 | `getForegroundSession()` 拿当前 R 会话 | `runtime.getForegroundSession()` |
| 列出数据框 | `getSessionVariables(sessionId)` → 过滤 `has_children === true` 且 `display_type` 含 data.frame | 返回 `RuntimeVariable[]`（含 `access_key`、`display_name`、`length`、`size`） |
| 用户选择 | `window.showQuickPick`，标签显示 `mtcars（32 × 11）` | — |
| 导出为 CSV | `evaluateCode('r', 'write.csv(<name>, stdout(), row.names=FALSE)')` 静默执行 | `runtime.evaluateCode('r', code)` 返回 `EvalResult` |
| 传给 Glyph | POST `/api/data/paste`，body 为 CSV 文本 | 复用现有接口，无需落盘 |

**为什么用 `evaluateCode` 而不是 `executeCode`**：前者静默执行、不进 Console、不打扰用户，
适合"取数"这种辅助操作；`executeCode` 用于用户可见的代码执行（阶段 2.1）。

**验收**：

- [ ] Console 里 `mtcars` 存在时，`Glyph: 使用当前环境的 data.frame` 能列出 `mtcars（32 × 11）`
- [ ] 选中后 Glyph 自动切到该数据源，列面板正确显示 11 列
- [ ] 大表（5 万行）能在 5 秒内传入
- [ ] 变量很多（50+）时不卡顿，QuickPick 支持输入过滤

**里程碑判断**：如果 2.1 + 2.2 做完，插件已经值回投入；若用户反馈"还是习惯自己跑代码"，则不必继续投入 L3。

---

### 阶段 3 · 入口与可发现性（0.5 天）

| 入口 | 实现 | 说明 |
|---|---|---|
| 命令面板 | 已有 | 三条命令 |
| 编辑器标题栏 | `menus.editor/title` 加图标按钮 | 在有 `df` 选中时可用 |
| 资源管理器右键 | `menus.explorer/context` 加「用 Glyph 打开此 CSV」 | 直接读 CSV 文件 → 传给 Glyph |
| 状态栏 | 有服务时显示 `Glyph :4330`，点击打开面板 | 让用户知道服务在跑 |
| 快捷键 | `Ctrl+Alt+G` | 与现有快捷键不冲突（需实测） |

**验收**：五处入口都能打开同一个面板，不重复启动服务。

---

### 阶段 4 · 打磨与文档（0.5 天）

| 项 | 内容 |
|---|---|
| 图标 | 128×128 PNG，与 Glyph 品牌蓝一致 |
| README | 安装、配置、常见问题、截图 |
| CHANGELOG | 版本记录 |
| 错误文案 | 每条错误都告诉用户"下一步做什么"，而非只报错 |
| i18n | 中文为主，命令标题保留英文 key 便于搜索 |

---

### 阶段 5 · 发布（1 天）

| 任务 | 说明 |
|---|---|
| 打包 | `vsce package`，确认 `node_modules` 已包含（原型踩过坑） |
| Open VSX 账号 | 创建 `glyph` namespace（Positron 默认从 Open VSX / P3M 取扩展） |
| 发布 | `ovsx publish`，或 `vsce publish --registry` |
| 版本策略 | 语义化版本；`engines.positron` 声明下限，避免未来 API 变动导致崩溃 |
| 冒烟测试 | 在干净 Positron 上安装 → 打开 → 出图 → 停止 |

**注意**：Positron **不能**从 VS Code Marketplace 安装（授权限制），必须发到 Open VSX。

---

## 四、工作量汇总

| 阶段 | 内容 | 人日 | 可独立交付 |
|---|---|---|---|
| **0.5** | **项目目录语义改造（★ 新增）** | **1.5** | ✅ |
| 0 | 工程化收尾 | 0.5 | ✅ |
| 1 | 生命周期健壮性 | 0.5 | ✅ |
| 2.1 | 代码回传 Console | 0.5 | ✅ |
| 2.1b | Viewer 原生集成（停止按钮/复用面板） | 0.2 | ✅ |
| 2.2 | **环境数据互通（关键）** | 1.0 | ✅ |
| 3 | 入口与可发现性 | 0.5 | ✅ |
| 4 | 打磨与文档 | 0.5 | ✅ |
| 5 | 发布 | 1.0 | ✅ |
| — | **合计** | **6.2 人日** | |
| — | 缓冲（15%） | 0.9 | |
| — | **总计** | **≈ 7.1 人日** | |

> 相比上一版计划的 5.4 人日，**增加 1.5 天全部来自阶段 0.5**。
> 这部分不是"锦上添花"——不做的话，插件版会出现「切项目数据串台」「装到只读目录写失败」
> 「导出的图不知道去哪了」三类问题，属于必须做的范围。

对比原估 3–5 人日：**主要增量在阶段 2（会话联动）**，这是原型阶段无法预判的部分；阶段 0/1 因为原型已跑通所以比原估要快。

---

## 五、风险登记册

| ID | 风险 | 概率 | 影响 | 应对 |
|---|---|---|---|---|
| R1 | Positron API 演进导致不兼容 | 中 | 高 | 声明 `engines.positron` 下限；只用稳定 API（`previewUrl` 已存在多版本）；订阅 release notes |
| R2 | `previewUrl` 无法在网页内注入 `acquireVsCodeApi` | **已确认** | 中 | 走"命令拉取"路线；网页内按钮需改造前端（+1.5 天），暂不做。原生停止按钮用 `PreviewSource` + `onDidRequestStop` 实现 |
| R3 | 用户未装 R 或包不全 | 中 | 中 | 启动前预检 `Rscript --version`；缺失包时给出安装命令 |
| R4 | 端口被占用 / 多实例冲突 | 低 | 低 | 已实现自动避让 + 单例保护 |
| R5 | 大表传输慢（5 万行以上） | 中 | 中 | `/api/data/paste` 已支持；必要时改为分页或落盘 |
| **R8** | **`.glyph/` 被误提交到 git** | 中 | 低 | 创建时自动写 `.gitignore`；首次生成时提示用户 |
| **R9** | **工作区只读（只读挂载/受保护目录）** | 低 | 高 | 回退到 `%APPDATA%\Glyph\<hash>`，并提示用户 |
| **R10** | **导出路径含中文/空格导致写入失败** | 中 | 中 | 服务端做 `normalizePath` + 可写性预检，失败时回退到保存对话框重选 |
| R6 | 杀软误报（spawn Rscript） | 低 | 中 | 不在程序中做可疑操作；必要时说明可执行文件路径 |
| R7 | 打包漏依赖（原型已踩） | 低 | 高 | 发布前做"干净机器安装"冒烟测试 |

---

## 六、验收标准

### 6.1 L1 可用（阶段 0.5–1 完成）

- [ ] 命令面板可搜索到三条 Glyph 命令
- [ ] 30 秒内完成「打开 → 界面出现 → 可出图」
- [ ] 连续操作不出错，无重复进程
- [ ] 强杀 IDE 无孤儿进程
- [ ] 错误场景（无 R、无项目目录）有明确提示
- [ ] **图库/上传数据随工作区隔离，切换项目不串台**
- [ ] **导出的图落在工作区 `figures/`，保存框默认路径正确**
- [ ] **不传 `--data-dir` 时旧用法行为不变（bat 回归通过）**

### 6.2 L2 好用（阶段 2 完成）

- [ ] 一键把生成代码送进 Console 并执行
- [ ] 能列出当前环境的 data.frame 并载入
- [ ] 上述两项各不超过 3 次点击

### 6.3 L3 可分发（阶段 5 完成）

- [ ] Open VSX 上可搜索到
- [ ] 干净 Positron 安装后一次成功
- [ ] 有图标、README、CHANGELOG

---

## 七、建议的推进节奏

```
第 1 天       阶段 0.5（项目目录改造）   ← 必须最先做，否则后续全建在错误地基上
第 2 天上午   阶段 0（工程化）
第 2 天下午   阶段 1（生命周期）
第 3 天上午   阶段 2.1 + 2.1b（代码回传 + 原生集成）
第 3 天下午   阶段 2.2（环境数据）      ← 关键里程碑，做完先收集反馈
第 4 天       阶段 3 + 4（入口 + 打磨）
第 5 天       阶段 5（发布）
```

**建议在阶段 2 结束后暂停**，找 2–3 个真实用户试用。理由：

1. 此时功能闭环，足以判断"值不值得继续"
2. L3 发布有长期维护成本（响应 issue、跟进 API 变动）
3. 若反馈平平，停在这里的沉没成本最小（约 2.5 天）

---

## 八、当前资产清单

| 资产 | 位置 | 状态 |
|---|---|---|
| 验证原型 | [positron-ext/](positron-ext/) | 可运行，待工程化 |
| VSIX 包 | `positron-ext/glyph-positron.vsix` | 237 KB，可安装试用 |
| 验证报告 | [POSITRON_PROTOTYPE.md](POSITRON_PROTOTYPE.md) | 含 5 个已解决问题的细节 |
| 后端支撑 | `run.R` 的 `--heartbeat`、`R/api.R` 的 `/api/heartbeat` | 已实现并验证 |
