// 独立验证脚本：不依赖 IDE，验证扩展的核心逻辑是否可行
// 1) 定位项目目录  2) 挑空闲端口  3) 起 R 子进程  4) 等就绪  5) 清理
const cp = require('child_process');
const fs = require('fs');
const net = require('net');
const path = require('path');
const http = require('http');

// 项目根：默认取本脚本所在目录的上一级（verify-core.js 在 positron-ext/ 内），
// 或用环境变量 GLYPH_ROOT 覆盖
const ROOT = process.env.GLYPH_ROOT || path.resolve(__dirname, '..');

function findFreePort(start = 4330) {
  return new Promise((resolve, reject) => {
    let port = start;
    const tryPort = () => {
      const srv = net.createServer();
      srv.once('error', () => {
        if (port >= start + 200) return reject(new Error('no free port'));
        port += 1;
        setTimeout(tryPort, 0);
      });
      srv.once('listening', () => srv.close(() => resolve(port)));
      srv.listen(port, '127.0.0.1');
    };
    tryPort();
  });
}

function waitForServer(port, timeoutMs = 60000) {
  const deadline = Date.now() + timeoutMs;
  return new Promise((resolve) => {
    const tick = () => {
      if (Date.now() > deadline) return resolve(false);
      const req = http.get(`http://127.0.0.1:${port}/api/meta`, (res) => {
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

(async () => {
  const ok = fs.existsSync(path.join(ROOT, 'run.R')) && fs.existsSync(path.join(ROOT, 'dist'));
  console.log('STEP1 项目目录校验:', ok ? 'PASS' : 'FAIL');

  const port = await findFreePort();
  console.log('STEP2 空闲端口:', port);

  // Rscript 定位：环境变量 GLYPH_RSCRIPT > PATH 里的 Rscript > 常见安装目录探测
  const rscript = process.env.GLYPH_RSCRIPT || 'Rscript';
  const proc = cp.spawn(
    rscript,
    ['run.R', '--port', String(port), '--no-browser'],
    { cwd: ROOT, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] }
  );
  const logs = [];
  proc.stdout.on('data', d => logs.push(d.toString()));
  proc.stderr.on('data', d => logs.push('[err] ' + d.toString()));
  console.log('STEP3 R 子进程 PID:', proc.pid);

  const ready = await waitForServer(port);
  console.log('STEP4 服务就绪:', ready ? 'PASS' : 'FAIL', `(${'http://127.0.0.1:' + port})`);
  console.log('     启动日志尾:', logs.join('').trim().split('\n').slice(-2).join(' | '));

  // 验证业务接口
  const fetchMeta = () => new Promise((resolve) => {
    const req = http.get(`http://127.0.0.1:${port}/api/meta`, (res) => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => resolve({ code: res.statusCode, len: b.length }));
    });
    req.on('error', () => resolve({ code: 0, len: 0 }));
  });
  const meta = await fetchMeta();
  console.log('STEP5 /api/meta:', meta.code === 200 ? 'PASS' : 'FAIL', `gzip 前 ${meta.len} 字节`);

  // 验证首页可访问（webview 要加载的就是这个）
  const home = await new Promise((resolve) => {
    const req = http.get(`http://127.0.0.1:${port}/`, (res) => {
      let b = '';
      res.on('data', c => b += c);
      res.on('end', () => resolve({ code: res.statusCode, hasApp: b.includes('id="app"') }));
    });
    req.on('error', () => resolve({ code: 0, hasApp: false }));
  });
  console.log('STEP6 首页可加载:', home.code === 200 && home.hasApp ? 'PASS' : 'FAIL');

  // 清理，并确认无残留
  try { cp.execSync(`taskkill /PID ${proc.pid} /T /F`, { stdio: 'ignore' }); } catch { proc.kill(); }
  await new Promise(r => setTimeout(r, 3000));
  const after = await fetchMeta();
  console.log('STEP7 清理后服务不可达:', after.code === 0 ? 'PASS' : 'FAIL');

  const ps = cp.execSync(
    `powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \\"Name='Rscript.exe'\\" | Measure-Object | Select-Object -ExpandProperty Count"`,
    { encoding: 'utf8' }
  ).trim();
  console.log('STEP8 残留 Rscript 进程数:', ps, ps === '0' ? 'PASS' : 'FAIL(有残留)');
})();
