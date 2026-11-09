// 重拍右栏面板截图：按内容实际高度裁切，去掉底部空白（否则每张 400×900 竖图几乎占满一页）
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9541
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'
const OUT = path.join(process.cwd(), 'docs', 'manual', 'shots')
const PROFILE = path.join(process.env.TEMP, 'gg-panels-' + Date.now())

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + PROFILE, '--window-size=1600,900', 'about:blank'
], { stdio: 'ignore' })

async function gt() {
  for (let i = 0; i < 60; i++) {
    try { const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json(); const p = l.find(x => x.type === 'page'); if (p) return p } catch {}
    await sleep(250)
  }
  throw new Error('no cdp')
}
const t = await gt()
const ws = new WebSocket(t.webSocketDebuggerUrl)
let id = 0; const pending = new Map()
ws.addEventListener('message', e => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result) }
})
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async (x) => {
  const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true })
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || ''))
  return r.result.value
}
const shot = async (name, clip) => {
  const params = { format: 'png' }
  if (clip) params.clip = { ...clip, scale: 1 }
  const { data } = await send('Page.captureScreenshot', params)
  fs.writeFileSync(path.join(OUT, name), Buffer.from(data, 'base64'))
  console.log('  ✓', name, clip ? `${clip.width}x${clip.height}` : 'full')
}

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(7000)

// 丢草稿、选数据、加图层、设成 displ × hwy
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const drop = [...document.querySelectorAll('span,button')].find(b => (b.textContent||'').trim() === '丢弃');
  if (drop) { drop.click(); await w(1200); }
  const sel = document.querySelector('.src-select input, .el-select input');
  if (sel) { sel.click(); await w(900);
    const o = [...document.querySelectorAll('.el-select-dropdown__item')].find(x => x.textContent.includes('汽车油耗'));
    if (o) { o.click(); await w(3000); } }
  const b = [...document.querySelectorAll('button')].find(x => x.textContent.includes('添加第一个图层'));
  if (b) { b.click(); await w(6000); }
  const store = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia._s.get('spec');
  store.spec.layers[0].aes = { x: { map: 'displ' }, y: { map: 'hwy' } };
  store.renderNow();
  await w(5000);
  return 1;
})()`)
await sleep(2000)

const panels = [
  ['图层', '04-panel-layers.png'],
  ['美学', '05-panel-aes.png'],
  ['参数', '06-panel-params.png'],
  ['标度', '07-panel-scale.png'],
  ['坐标', '08-panel-coord.png'],
  ['标签', '09-panel-labs.png'],
  ['注释', '10-panel-annot.png'],
  ['主题', '11-panel-theme.png'],
  ['图库', '12-gallery.png'],
  ['拼图', '13-patchwork.png']
]

for (const [label, file] of panels) {
  const r = await ev(`(async () => {
    const w = (ms) => new Promise(r => setTimeout(r, ms));
    const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
    const hit = rails.find(b => b.innerText.trim() === ${JSON.stringify(label)});
    if (hit) hit.click();
    await w(1600);
    const right = document.querySelector('.gg-right');
    // 多个面板都渲染在 DOM 里（v-show），必须取「可见」的那个，否则拿到隐藏面板的 0 高度
    const scroll = [...document.querySelectorAll('.gg-right .gg-tab-scroll')]
      .find(el => el.getBoundingClientRect().height > 0);
    const rb = right.getBoundingClientRect();
    const contentH = scroll ? scroll.scrollHeight : Math.round(rb.height);
    return {
      x: Math.round(rb.x), y: Math.round(rb.y), width: Math.round(rb.width), height: Math.round(rb.height),
      contentH: Math.round(contentH)
    };
  })()`)
  await sleep(900)
  // 高度取「内容实际高度」与「可视高度」的较小者，并留一点下边距
  const h = Math.min(r.height, r.contentH + 10)
  await shot(file, { x: r.x, y: r.y, width: r.width, height: h })
}

ws.close(); proc.kill(); process.exit(0)
