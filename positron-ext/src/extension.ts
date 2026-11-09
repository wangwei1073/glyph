// Glyph for Positron —— 最小验证原型
//
// 思路：复用 Glyph 现有的「R 后端 + dist 前端」，本扩展只做三件事：
//   1) 找到 Glyph 项目目录（含 run.R 与 dist/）
//   2) 起一个 Rscript 子进程（动态挑空闲端口）
//   3) 用 positron.window.previewUrl 把界面开成 webview 面板
// 退出时确保子进程被杀掉，不留僵尸。

import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as fs from 'fs';
import * as net from 'net';
import * as path from 'path';

// ---------- 定位 Glyph 项目目录 ----------
function resolveGlyphRoot(): string | null {
  const cfg = vscode.workspace.getConfiguration('glyph');
  const configured = cfg.get<string>('projectPath');
  const candidates: string[] = [];
  if (configured) candidates.push(configured);

  // 当前工作区根目录及其父级（扩展可能装在项目里）
  for (const folder of vscode.workspace.workspaceFolders ?? []) {
    let dir = folder.uri.fsPath;
    for (let i = 0; i < 3; i++) {
      candidates.push(dir);
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }

  for (const dir of candidates) {
    try {
      if (fs.existsSync(path.join(dir, 'run.R')) && fs.existsSync(path.join(dir, 'dist'))) {
        return dir;
      }
    } catch { /* 忽略无权限目录 */ }
  }
  return null;
}

// ---------- 挑一个空闲端口 ----------
function findFreePort(start = 4330): Promise<number> {
  return new Promise((resolve, reject) => {
    let port = start;
    const tryPort = () => {
      const srv = net.createServer();
      srv.once('error', () => {
        if (port >= start + 200) return reject(new Error('找不到空闲端口'));
        port += 1;
        setTimeout(tryPort, 0);
      });
      srv.once('listening', () => {
        srv.close(() => resolve(port));
      });
      srv.listen(port, '127.0.0.1');
    };
    tryPort();
  });
}

// ---------- 轮询等待服务就绪 ----------
function waitForServer(port: number, timeoutMs = 60000): Promise<boolean> {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve) => {
    const tick = () => {
      if (Date.now() > deadline) return resolve(false);
      const url = `http://127.0.0.1:${port}/api/meta`;
      const http = require('http') as typeof import('http');
      const req = http.get(url, (res: any) => {
        res.resume();
        if (res.statusCode === 200) return resolve(true);
        setTimeout(tick, 500);
      });
      req.on('error', () => setTimeout(tick, 500));
      req.setTimeout(2000, () => { req.destroy(); setTimeout(tick, 500); });
    };
    tick();
  });
}

// ---------- 服务管理 ----------
interface ServerHandle {
  proc: cp.ChildProcess;
  port: number;
  url: string;
  root: string;
  heartbeat?: NodeJS.Timeout;
}

let current: ServerHandle | null = null;
let output: vscode.OutputChannel;

// 每 10 秒发一次心跳，告诉 R 侧「IDE 还活着」
function startHeartbeat(h: ServerHandle): void {
  const ping = () => {
    const http = require('http') as typeof import('http');
    const req = http.get(`${h.url}/api/heartbeat`, (res: any) => res.resume());
    req.on('error', () => { /* 服务已停，心跳自然结束 */ });
    req.setTimeout(3000, () => req.destroy());
  };
  ping();
  h.heartbeat = setInterval(ping, 10000);
  h.heartbeat.unref?.();
}

function stopHeartbeat(h: ServerHandle): void {
  if (h.heartbeat) {
    clearInterval(h.heartbeat);
    h.heartbeat = undefined;
  }
}

function stopServer(): void {
  if (!current) return;
  const { proc, port } = current;
  stopHeartbeat(current);      // 先停心跳，再置空
  current = null;
  output.appendLine(`[glyph] 停止服务（端口 ${port}，PID ${proc.pid ?? '?'}）`);

  // Windows：Rscript 会派生 x64 子进程，必须整棵树杀掉。
  // 注意顺序：先 taskkill /T /F（对树有效），再兜底直接 kill。
  if (process.platform === 'win32' && proc.pid) {
    try {
      cp.execSync(`taskkill /PID ${proc.pid} /T /F`, { stdio: 'ignore' });
      output.appendLine('[glyph] 已通过 taskkill /T 结束进程树');
      return;
    } catch (e) {
      output.appendLine(`[glyph] taskkill 失败，回退 kill：${String(e)}`);
    }
  }
  try {
    proc.kill();
  } catch (e) {
    output.appendLine(`[glyph] kill 失败：${String(e)}`);
  }
}

function rscriptPath(): string {
  const cfg = vscode.workspace.getConfiguration('glyph').get<string>('rscriptPath');
  if (cfg && fs.existsSync(cfg)) return cfg;
  return process.platform === 'win32' ? 'Rscript.exe' : 'Rscript';
}

async function startServer(): Promise<ServerHandle> {
  if (current) return current;

  const root = resolveGlyphRoot();
  if (!root) {
    throw new Error(
      '找不到 Glyph 项目目录（需要包含 run.R 与 dist/）。'
      + '可在设置 glyph.projectPath 中指定。'
    );
  }

  const port = await findFreePort();
  const rs = rscriptPath();
  output.appendLine(`[glyph] 启动：${rs} run.R --port ${port}  (cwd=${root})`);

  // IDE 存活防护：用「心跳」而不是 PID 判断。
  // 原因：扩展宿主是 IDE 的子孙进程，PID 会变；tasklist 在不同会话下也不可靠。
  // 扩展每 10 秒 ping 一次 /api/heartbeat；IDE 被强杀后心跳停止，
  // R 侧超过 60 秒没收到就自行退出，避免孤儿进程。
  const proc = cp.spawn(
    rs,
    ['run.R', '--port', String(port), '--no-browser', '--heartbeat', '--heartbeat-timeout', '60'],
    {
      cwd: root,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    }
  );
  proc.stdout?.on('data', (d) => output.append(d.toString()));
  proc.stderr?.on('data', (d) => output.append(d.toString()));
  proc.on('exit', (code) => {
    output.appendLine(`[glyph] R 进程退出，code=${code}`);
    if (current && current.proc === proc) current = null;
  });

  const handle: ServerHandle = { proc, port, url: `http://127.0.0.1:${port}`, root };
  current = handle;

  const ok = await waitForServer(port);
  if (!ok) {
    stopServer();
    throw new Error(`服务在 60 秒内未就绪，详见输出面板「Glyph」。`);
  }
  startHeartbeat(handle);
  output.appendLine(`[glyph] 服务就绪：${handle.url}`);
  return handle;
}

// ---------- 命令实现 ----------
async function openGlyph(context: vscode.ExtensionContext): Promise<void> {
  output.show(true);
  try {
    const handle = await startServer();
    output.appendLine(`[glyph] 环境：VSCode=${vscode.version}，进程=${process.execPath}`);

    // 优先走 Positron 官方 API（能复用真实 http 服务的同源能力）
    const positron = getPositron();
    if (positron) {
      output.appendLine(`[glyph] Positron API 可用，命名空间：${Object.keys(positron).join(', ')}`);
      output.appendLine(`[glyph] window API：${positron.window ? Object.keys(positron.window).join(', ') : '无'}`);
    } else {
      output.appendLine('[glyph] 未取得 Positron API（可能运行在普通 VS Code）');
    }

    if (positron?.window?.previewUrl) {
      positron.window.previewUrl(vscode.Uri.parse(handle.url));
      output.appendLine(`[glyph] 已通过 positron.window.previewUrl 打开：${handle.url}`);
      return;
    }

    // 回退：普通 webview 面板（CSP 更严，作为兜底）
    const panel = vscode.window.createWebviewPanel(
      'glyph', 'Glyph', vscode.ViewColumn.One,
      { enableScripts: true, retainContextWhenHidden: true }
    );
    panel.webview.html = `<!DOCTYPE html><html><head><meta charset="utf-8">
      <style>html,body{margin:0;height:100%}iframe{border:0;width:100%;height:100%}
      .tip{padding:24px;font-family:system-ui}</style></head>
      <body><iframe src="${handle.url}"></iframe></body></html>`;
    panel.onDidDispose(() => { /* 面板关闭不自动停服务，保留给多次打开 */ });
    output.appendLine('[glyph] 已通过 webview 面板打开（回退模式）');
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    output.appendLine(`[glyph] 失败：${msg}`);
    vscode.window.showErrorMessage(`Glyph: ${msg}`);
  }
}

// 取 Positron API。
// 注意：为让 VSIX 不依赖 node_modules，这里不走 npm 包，而是直接读 Positron 注入的 API 对象。
// Positron 在窗口内通过全局 vscode 模块暴露同一套接口，扩展可用 require('vscode') 后
// 通过 positron 专用的公开入口获得；若拿不到则回退到 webview 面板。
function getPositron(): any | null {
  try {
    // 1) 若恰好装了 npm 包（开发者场景）
    const mod = require('@posit-dev/positron');
    if (typeof mod?.tryAcquirePositronApi === 'function') {
      const api = mod.tryAcquirePositronApi();
      if (api) return api;
    }
  } catch { /* 未安装 npm 包，忽略 */ }
  try {
    // 2) Positron 内置扩展使用的公开通道
    const vscode: any = require('vscode');
    const api = vscode?.positron ?? (vscode as any)?.extensions?.getExtension?.('positron.positron-r')?.exports?.positron;
    if (api?.window?.previewUrl) return api;
  } catch { /* 普通 VS Code */ }
  return null;
}

export function activate(context: vscode.ExtensionContext) {
  output = vscode.window.createOutputChannel('Glyph');
  context.subscriptions.push(output);

  context.subscriptions.push(
    vscode.commands.registerCommand('glyph.open', () => openGlyph(context)),
    vscode.commands.registerCommand('glyph.stop', () => {
      if (current) {
        stopServer();
        vscode.window.showInformationMessage('Glyph 服务已停止');
      } else {
        vscode.window.showInformationMessage('Glyph 服务未在运行');
      }
    }),
    vscode.commands.registerCommand('glyph.status', () => {
      if (current) {
        vscode.window.showInformationMessage(
          `Glyph 运行中：${current.url}（PID ${current.proc.pid}）`
        );
      } else {
        vscode.window.showInformationMessage('Glyph 服务未在运行');
      }
    })
  );

  // 扩展卸载/IDE 退出时清理子进程
  context.subscriptions.push({ dispose: () => stopServer() });

  // URI handler：便于自动化验证，也方便用户从浏览器/脚本唤起
  //   positron://glyph.glyph-positron/open
  context.subscriptions.push(
    vscode.window.registerUriHandler({
      handleUri(uri: vscode.Uri) {
        output.appendLine(`[glyph] URI: ${uri.toString()}`);
        if (uri.path === '/open' || uri.path === '/preview') {
          vscode.commands.executeCommand('glyph.open');
        } else if (uri.path === '/stop') {
          vscode.commands.executeCommand('glyph.stop');
        }
      }
    })
  );
}

export function deactivate() {
  stopServer();
}
