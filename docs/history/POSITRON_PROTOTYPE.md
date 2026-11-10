# Glyph for Positron · 最小验证原型报告

> 验证日期：2026-11-09
> 环境：Positron 2026.09.1（Code OSS 1.130.0）、Node 24、R 4.6.1
> 结论：**技术路线完全可行，核心难点已逐一击破并留有实测证据。**

## 一、结论

| 项 | 结果 |
|---|---|
| 能否在 Positron 内打开 Glyph 完整界面 | ✅ 通过 `positron.window.previewUrl` 实现 |
| 现有 R 后端与前端是否需要改动 | ✅ 前端**零改动**，R 后端仅新增两个可选启动参数与一个心跳路由 |
| 出图能力 | ✅ 界面完整渲染，数据源/画布/面板均正常 |
| 停止服务是否干净 | ✅ 端口释放、无残留进程 |
| IDE 崩溃/强杀后是否泄漏孤儿进程 | ✅ 心跳机制兜底，60 秒后自动退出 |
| 扩展体积 | 237 KB（含依赖） |

## 二、实现方式

扩展只做三件事，把 Glyph 当作黑盒服务：

```
命令 "Glyph: 打开 Glyph 界面"
  ├─ 定位项目目录（设置 glyph.projectPath，或从工作区向上查找含 run.R + dist/ 的目录）
  ├─ 挑空闲端口（从 4330 起，避开被占用端口）
  ├─ spawn: Rscript run.R --port <p> --no-browser --heartbeat --heartbeat-timeout 60
  ├─ 轮询 /api/meta 直到 200（最长 60 秒）
  ├─ positron.window.previewUrl('http://127.0.0.1:<p>')
  └─ 每 10 秒 GET /api/heartbeat
```

**为什么用 `previewUrl` 而不是 webview 内嵌**：

`previewUrl` 让 webview 直接以 `http://127.0.0.1:<port>` 为源，前端 `api.js` 里的相对路径 `/api/...` **原样可用**，同源策略与后端现有的来源校验都自然生效。若改用 `webview.html` 内嵌 HTML，则所有请求要改绝对 URL，还会撞上 CSP 限制。

## 三、验证证据

### 3.1 扩展被正确识别

```
$ positron --list-extensions --show-versions
glyph.glyph-positron@0.0.1
```

命令面板中出现三条命令：查看服务状态 / 打开 Glyph 界面 / 停止 Glyph 服务。

### 3.2 界面完整打开

`previewUrl` 调用后，Positron 内出现独立的 Glyph 面板，顶部地址栏显示 `http://127.0.0.1:4330/`，左侧数据面板、中间画布、右侧图层栏、底部工具条全部正常渲染。

### 3.3 服务健康

```
GET /api/meta   → 200（612 KB 元数据）
GET /           → 200（前端首页，含 id="app"）
```

### 3.4 停止与清理

| 场景 | 结果 |
|---|---|
| 执行 `glyph.stop` | 端口释放、无残留 Rscript |
| 强杀 Positron（不执行 stop） | 心跳停止 → 60 秒后 R 进程自行退出、端口释放 |

## 四、踩过的坑（对后续正式开发的直接输入）

这四项都是有代价的发现，写进正式版能省大量时间。

### 4.1 `httpuv::runServer` 无法从请求内部停止

`runServer` 是 C 层阻塞循环，`stopServer()` / `stopAllServers()` 在请求处理函数内均无法生效。

**解法**：改用 `startServer()` + `service(20)` 短超时轮询。注意超时必须短（20ms），
用 `service(200)` 会让 httpuv 在 C 层久留、读不到标志位。

### 4.2 `STATE` 是 `list`，值语义导致标志位失效

`state$shutdown_requested <- TRUE` 只改函数内局部副本，主循环永远读到 `FALSE`。

**解法**：用 `new.env()` 传递可变状态。这是本次排查耗时最久的一个问题——
日志显示 "收到退出请求" 已打印，但循环里标志始终为 FALSE。

### 4.3 扩展宿主 PID 不能用作存活基准

最初把 `process.pid`（扩展宿主）传给 R 判断存活，结果 **界面刚打开服务就被杀**，
因为扩展宿主是 Positron 的子孙进程，生命周期比主窗口短。

改用 `process.ppid` 同样不可靠（随着宿主重启而变化）。

**最终解法**：放弃 PID 判断，改用**心跳**——扩展每 10 秒 ping `/api/heartbeat`，
R 侧超过 60 秒没收到就自行退出。这个方案不依赖任何进程关系，最稳健。

### 4.4 打包必须包含 `node_modules`

`vsce package --no-dependencies` 会漏掉 `@posit-dev/positron`，
导致 `require()` 抛错被 try/catch 吞掉，静默回退到 webview 分支，
表现为「命令执行了但什么都没发生」。

**解法**：不带 `--no-dependencies` 打包（体积仅从 13 KB 增至 237 KB）。

### 4.5 命令面板首项不是目标命令

搜 `Glyph` 时首项是「查看 Glyph 服务状态」，回车执行的是状态查询。
自动化测试要搜命令 ID（`glyph.open`）才能精确定位。

## 五、当前原型的能力边界

已完成（可用）：

- 打开 / 停止 / 查看状态三条命令
- 项目目录可通过设置指定
- 心跳保活与孤儿进程防护
- 端口自动避让

未做（正式版需要）：

| 项 | 说明 | 预估 |
|---|---|---|
| 与 Positron R 会话联动 | `positron.runtime.executeCode` 把生成的代码送进 Console | 0.5 天 |
| 「用当前环境的数据」 | 读取 Positron 变量面板里的 df | 1 天 |
| 侧边栏常驻入口 | `webviewView` 而非独立面板 | 0.5 天 |
| 多工作区/多实例 | 目前只维护单例服务 | 0.5 天 |
| 图标、README、发布 Open VSX | 上架流程 | 1 天 |

## 六、成本复核

原评估 3–5 人日，本次原型（含全部坑）实际投入约 **2 小时**，已打通最难的进程管理部分。

剩余工作量：

| 阶段 | 内容 | 预估 |
|---|---|---|
| 收尾 | 图标、README、错误提示打磨 | 0.5 天 |
| 联动 | executeCode / 当前环境数据 | 1.5 天 |
| 体验 | 侧边栏入口、状态栏、启动进度提示 | 0.5 天 |
| 发布 | Open VSX 打包上架 | 1 天 |
| **合计** | | **3.5 天** |

与原估 3–5 人日吻合，且最不确定的部分（进程生命周期）已经验证完毕。

## 七、如何试用

```bash
# 安装
"D:\Positron\bin\positron.cmd" --install-extension positron-ext\glyph-positron.vsix --force

# 配置（若不把扩展放在 Glyph 项目内）
# settings.json:
#   "glyph.projectPath": "E:/Desktop/vibecoding/ggplot-gui"
#   "glyph.rscriptPath": "D:/R/R-4.6.1/bin/Rscript.exe"
```

然后在命令面板执行 **Glyph: 打开 Glyph 界面**。

## 八、建议

**可以继续投入。** 三点理由：

1. 最难的部分（进程生命周期、服务停止、孤儿进程）已经解决并有实测证据
2. 前端 6591 行、后端 5597 行**零改动**即可复用，这是这条路线最大的价值
3. Positron 是 Posit 官方主推的新一代 IDE，与项目目标用户（科研绘图）高度重合

建议下一步先做「与 R 会话联动」这一项——它能让插件从「打开一个网页」升级为「真正嵌进工作流」，
是判断这个插件值不值得继续做的关键里程碑。
