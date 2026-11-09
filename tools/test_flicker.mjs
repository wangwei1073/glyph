// 验证：resize 重渲染过程中，图片不出现透明度变化（无闪烁）
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9485
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-flicker',
  '--window-size=1600,900', 'about:blank'
], { stdio: 'ignore' })

async function gt() {
  for (let i = 0; i < 40; i++) {
    try {
      const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()
      const p = l.find(x => x.type === 'page'); if (p) return p
    } catch {}
    await sleep(250)
  }
  throw new Error('no cdp')
}
const t = await gt()
const ws = new WebSocket(t.webSocketDebuggerUrl)
let id = 0; const pending = new Map()
ws.addEventListener('message', e => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) {
    const p = pending.get(m.id); pending.delete(m.id)
    m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result)
  }
})
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async (x) => { const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.text); return r.result.value }

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(6000)

// 出图
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const sel = document.querySelector('.src-select input, .el-select input');
  if (sel) { sel.click(); await w(900);
    const o = [...document.querySelectorAll('.el-select-dropdown__item')].find(x => x.textContent.includes('汽车油耗'));
    if (o) { o.click(); await w(2500); } }
  const b = [...document.querySelectorAll('button')].find(x => x.textContent.includes('添加第一个图层'));
  if (b) { b.click(); await w(5000); }
  return 1;
})()`)
await sleep(1500)

// 安装一个采样器：每 60ms 记录一次 opacity 和是否存在图片
await ev(`(() => {
  window.__samples = [];
  window.__timer = setInterval(() => {
    const img = document.querySelector('.gg-canvas-img');
    window.__samples.push({
      t: Date.now(),
      exists: !!img,
      opacity: img ? getComputedStyle(img).opacity : null,
      cls: img ? img.className : null,
      naturalW: img ? img.naturalWidth : 0
    });
  }, 60);
  return 1;
})()`)

// 触发 resize
await send('Emulation.setDeviceMetricsOverride', { width: 1200, height: 820, deviceScaleFactor: 1, mobile: false })
await sleep(6000)

const report = await ev(`(() => {
  clearInterval(window.__timer);
  const s = window.__samples || [];
  const dimmed = s.filter(x => x.opacity !== null && parseFloat(x.opacity) < 0.99);
  const missing = s.filter(x => !x.exists);
  return {
    total: s.length,
    dimmedCount: dimmed.length,
    dimmedSamples: dimmed.slice(0, 3).map(x => ({ op: x.opacity, cls: x.cls })),
    missingCount: missing.length,
    detail: (() => {
      const a = document.querySelector('#app').__vue_app__;
      const st = a.config.globalProperties.$pinia.state.value.spec;
      return { size: { w: st.renderOpts.width, h: st.renderOpts.height }, rendering: st.rendering };
    })()
  };
})()`)

console.log('采样结果:', JSON.stringify(report, null, 0))
console.log('')
console.log(`透明度变化次数: ${report.dimmedCount} ${report.dimmedCount === 0 ? '✅ 无闪烁' : '❌ 仍有变暗'}`)
console.log(`图片消失次数: ${report.missingCount} ${report.missingCount === 0 ? '✅ 全程有图' : '❌ 有空白'}`)

ws.close(); proc.kill(); process.exit(0)
