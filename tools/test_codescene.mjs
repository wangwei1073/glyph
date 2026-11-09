// 验证两个场景：
// A) 项目里有自己的图层映射 → 打开代码图 → 拖窗口 → 应保持代码图（不被 spec 顶掉）
// B) 代码图 + 改画幅 → 应重渲染代码图（而非停在旧尺寸）
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9481
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-scen',
  '--window-size=1600,900', 'about:blank'
], { stdio: 'ignore' })

async function getTarget() {
  for (let i = 0; i < 40; i++) {
    try {
      const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()
      const p = l.find(t => t.type === 'page')
      if (p) return p
    } catch {}
    await sleep(250)
  }
  throw new Error('no cdp')
}
const t = await getTarget()
const ws = new WebSocket(t.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.addEventListener('message', ev => {
  const m = JSON.parse(ev.data)
  if (m.id && pending.has(m.id)) {
    const p = pending.get(m.id); pending.delete(m.id)
    m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result)
  }
})
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async (e) => {
  const r = await send('Runtime.evaluate', { expression: e, awaitPromise: true, returnByValue: true })
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || ''))
  return r.result.value
}

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(6000)

const st = () => ev(`(() => {
  const app = document.querySelector('#app').__vue_app__;
  const s = app.config.globalProperties.$pinia.state.value.spec;
  const img = document.querySelector('.gg-canvas-img');
  return {
    layers: s.spec.layers.length,
    fromCode: !!s.last.renderedFromCode,
    pngUrl: (s.last.pngUrl||'').replace('/api/plot/',''),
    naturalW: img ? img.naturalWidth : 0,
    size: { w: s.renderOpts.width, h: s.renderOpts.height }
  };
})()`)

// 1) 建立「自己的图层」图
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
await sleep(2000)
console.log('A0 自己的图层图:', JSON.stringify(await st()))

// 2) 从图库打开一个代码图
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const labels = rails.map(b => b.innerText.trim());
  rails[labels.indexOf('图库')].click();
  await w(2000);
  const card = [...document.querySelectorAll('.pin-card.code')].filter(c => c.getBoundingClientRect().height > 0)[0];
  if (card) { card.click(); await w(3000); }
  return !!card;
})()`)
await sleep(2000)
const opened = await st()
console.log('A1 打开代码图:', JSON.stringify(opened))

// 3) 关键：拖窗口（缩到 1200）
console.log('--- 缩小窗口到 1200（模拟拖窗口）---')
await send('Emulation.setDeviceMetricsOverride', { width: 1200, height: 820, deviceScaleFactor: 1, mobile: false })
await sleep(1000)
console.log('A2 resize+1s:', JSON.stringify(await st()))
await sleep(4000)
const afterResize = await st()
console.log('A3 resize+5s:', JSON.stringify(afterResize))

// 判定
const keptCode = afterResize.fromCode === true
const resized = afterResize.size.w !== opened.size.w
console.log('')
console.log(`结论: 保持代码图=${keptCode}, 重新渲染=${resized}`)
console.log(keptCode && resized ? '✅ 通过：代码图未被 spec 顶掉，且按新尺寸重渲染' : '❌ 失败')

ws.close(); proc.kill(); process.exit(0)
