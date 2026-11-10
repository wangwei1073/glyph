# Glyph DSH 插件

把 Glyph（ggplot2 图形界面，本仓库 `run.R`）接进 DeepSeek Harness：
右栏多一个 **Glyph** 原生页签，聊天里的 R 代码块一键推送出图。

---

## 一、它是什么

| 组成 | 说明 |
|---|---|
| **宿主半** `lib/index.js` | 随 DSH 启动自动拉起 Glyph 的 R 服务，并提供一个本地控制服务 |
| **浏览器半** `lib/client.js` | 在 DSH 右栏注册一个原生页签，里面内嵌 Glyph 界面；并给聊天代码块加「推送」按钮 |

数据流：

```
聊天代码块 [推送] ──┐
                    ├─→ 控制服务(127.0.0.1:4399) ─→ Glyph(/api/code/push) ─→ 渲染
右栏 Glyph 页签 ────┘
```

---

## 二、前置条件

1. **R**（4.x）。安装后在命令行能跑 `Rscript --version`
2. **Glyph 仓库**（需要一个含 `run.R` 的目录）
3. Glyph 所需 R 包：

   ```r
   install.packages(c(
     "ggplot2", "jsonlite", "httpuv", "ragg", "systemfonts", "png",
     "ggrepel", "ggsci", "ggthemes", "ggprism", "ggpubr", "ggbeeswarm",
     "ggtext", "ggside", "ggstats", "ggridges", "ggh4x", "ggnewscale",
     "ggdist", "ggforce", "ggbreak", "hrbrthemes",
     "patchwork", "plotly", "readr", "readxl", "scales"
   ))
   ```

   缺包不会崩，对应功能会静默不可用；但 `ggplot2 / jsonlite / httpuv / ragg` 是必需的。

---

## 三、安装

### 方式 A：DSH 插件管理器（推荐）

1. 把本目录（`plugin/`）拷到目标机器任意位置，例如 `D:\tools\dsh-plugin-glyph`
2. 在 DSH 里打开插件管理，用「从本地安装」，填：

   ```
   file:D:/tools/dsh-plugin-glyph
   ```

   或命令行：

   ```bash
   dsh plugin --profile desktop add file:D:/tools/dsh-plugin-glyph
   ```

3. 重启 DSH（宿主侧代码只在重启后加载）

### 方式 B：手动安装

编辑 profile 目录（Windows 为 `%USERPROFILE%\.dsh\profiles\desktop`）：

1. `package.json` 的 `dependencies` 加一行：

   ```json
   "dsh-plugin-glyph": "file:D:/tools/dsh-plugin-glyph"
   ```

2. 同文件的 `dsh.profile.bundles` 数组末尾加一项：

   ```json
   "dsh-plugin-glyph"
   ```

3. 在该目录执行 `pnpm install`，然后重启 DSH

---

## 四、配置路径（换机器必做）

插件需要知道两件事：**Glyph 目录** 和 **Rscript 路径**。

### 自动探测（通常够用）

不放任何配置时，插件会尝试：

| 目标 | 探测顺序 |
|---|---|
| Rscript | `PATH` 里的 `Rscript` → `C:/Program Files/R/*/bin/x64/Rscript.exe` → `D:/R/*/...` → `/usr/lib/R/bin/Rscript` 等 |
| Glyph 目录 | 环境变量 `GLYPH_HOME` → 插件所在仓库的上级目录 → `~/ggplot-gui` → 若干常见路径 |

**如果你的 Glyph 就放在插件目录的上一级**（即 `plugin/` 与 `run.R` 同级），通常无需任何配置。

### 显式配置（推荐，最可靠）

写配置文件 `~/.dsh/glyph-plugin.json`：

```json
{
  "glyphHome": "D:/vibecoding/ggplot-gui",
  "rscript": "D:/R/R-4.6.1/bin/x64/Rscript.exe",
  "appPort": 4321
}
```

也可以只用环境变量（优先级高于配置文件）：

```
GLYPH_HOME       Glyph 目录
GLYPH_RSCRIPT    Rscript 可执行文件
GLYPH_APP_PORT   Glyph 端口（默认 4321）
GLYPH_PORT       控制服务端口（默认 4399）
GLYPH_DATADIR    Glyph 项目目录（数据/图库存这里）
```

### 运行时改配置

控制服务提供接口（改完会自动重启 Glyph）。所有请求都需要带 `x-glyph-token` 头
（见下方「安全模型」；token 存在配置文件里）：

```bash
TOKEN=$(node -p "require(require('os').homedir()+'/.dsh/glyph-plugin.json').token")
curl -s http://127.0.0.1:4399/status -H "x-glyph-token: $TOKEN"
curl -s http://127.0.0.1:4399/config -H "x-glyph-token: $TOKEN"
curl -s -X POST http://127.0.0.1:4399/config \
  -H "x-glyph-token: $TOKEN" -H 'Content-Type: application/json' \
  -d '{"glyphHome":"D:/vibecoding/ggplot-gui","rscript":"D:/R/R-4.6.1/bin/x64/Rscript.exe"}'
```

配置文件还支持两个可选键：

```json
{
  "allowedOrigins": ["http://127.0.0.1:5000"],
  "port": 4399
}
```

`allowedOrigins` 仅当 DSH 渲染层不是 `file://` 加载（CORS 来源不是 `null`）时才需要，
把渲染页面的完整来源加进去即可。

---

## 四点五、安全模型

控制服务能启动进程、执行 R 代码推送（`/push`），必须防止任意网页驱动它，做了三层：

1. **只绑 127.0.0.1** —— 外部机器连不上。
2. **CORS 来源白名单** —— 只对 `file://`（Electron 渲染层，来源为 `null`）、
   `127.0.0.1` / `localhost`、以及配置文件 `allowedOrigins` 里的来源回 CORS 头。
   公网页面读不到任何响应、POST 预检直接被拒。
3. **token 校验** —— 所有路由要求 `x-glyph-token` 头。token 由宿主生成一次、
   存在配置文件里，并在启动时回写进 `lib/client.js`（浏览器半没有文件系统权限，
   只能靠宿主改写源文件把 token 交到它手里；token 绝不经 HTTP 提供，
   因此被 CORS 放行的来源也拿不到它）。若 `client.js` 无法回写（只读安装目录等），
   自动放弃 token 校验、退回仅 CORS 白名单模式（`/status` 里 `tokenEnforced: false`）。

另外，宿主以 `--heartbeat` 启动 Glyph 并每 10 秒 ping 一次：DSH 退出后心跳停止，
Glyph 超过 120 秒没收到心跳会自行退出，不留孤儿 R 进程；停止时用 `taskkill /T /F`
整树杀进程（R 会派生渲染/装包子进程，普通 kill 杀不干净）。

---

## 五、验证

1. 重启 DSH
2. 右栏点 `+` → 应出现 **Glyph** 一项
3. 打开后应看到 Glyph 界面（数据 / 画布 / 设置三栏）
4. 在对话里让 AI 给一段 R 代码，代码块右上角点 **推送** → 图形出现在 Glyph 页签里

排查：

```bash
curl -s http://127.0.0.1:4399/status
```

返回里 `running` 为 true 即服务正常；`error` 字段会给出具体原因（找不到 run.R、找不到 Rscript、端口占用等）。

---

## 六、常见问题

**右栏没有 Glyph 页签**
浏览器半没加载。硬刷新（Ctrl+Shift+R）；仍不行则确认 `package.json` 里有 `dsh.client` 段，
且 profile 的 `bundles` 已包含本插件。

**页签里显示「找不到 Glyph 入口」/「找不到 Rscript」**
按第四节配好两个路径，然后重启 DSH（或调 `POST /config`）。

**Glyph 起不来但 curl /status 显示 running=false**
看 `error` 字段。常见原因：R 包缺失（先跑一次 `Rscript run.R --port 4321` 看报错）、
端口被占用（插件会自动换端口，但 `appPort` 指定的端口若被占则退回随机端口）。

**改了 `lib/index.js` 不生效**
宿主侧是 Node 模块，有缓存，必须重启 DSH。浏览器半（`lib/client.js`）硬刷新即可。

**数据存在哪**
存放在 `GLYPH_DATADIR`（或配置里的 `dataDir`）指向的目录：`pins.json`、`pins/`、`userdata/`、
`edits.json`。默认取 DSH 进程的工作目录。

---

## 七、卸载

```bash
dsh plugin --profile desktop remove dsh-plugin-glyph
```

或从 profile 的 `package.json` 里删掉 `dependencies` 与 `bundles` 中对应项，再 `pnpm install`。
Glyph 的数据目录不受影响，可手动删除。
