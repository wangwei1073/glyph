// 验证：自己的 spec 图 → 打开图库代码图 → 点「返回我的图」→ 恢复 spec 图
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9487
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-back',
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
const ev = async (x) => { const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || '')); return r.result.value }

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(6000)

const snap = () => ev(`(() => {
  const app = document.querySelector('#app').__vue_app__;
  const s = app.config.globalProperties.$pinia.state.value.spec;
  const img = document.querySelector('.gg-canvas-img');
  const badge = document.querySelector('.head-code-tag');
  return {
    fromCode: !!s.last.renderedFromCode,
    layers: s.spec.layers.length,
    pngUrl: (s.last.pngUrl || '').replace('/api/plot/', ''),
    naturalW: img ? img.naturalWidth : 0,
    badgeVisible: badge ? badge.getBoundingClientRect().height > 0 : false,
    badgeText: badge ? badge.innerText.replace(/\\n+/g, ' ') : null
  };
})()`)

// 1) 建自己的图
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
const own = await snap()
console.log('1) 自己的图:', JSON.stringify(own))

// 2) 打开图库代码图
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const labels = rails.map(b => b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2000);
  const card = [...document.querySelectorAll('.pin-card.code')].filter(c => c.getBoundingClientRect().height > 0)[0];
  if (card) { card.click(); await w(3500); }
  return !!card;
})()`)
await sleep(2500)
const codeState = await snap()
console.log('2) 打开代码图:', JSON.stringify(codeState))

// 3) 点「返回我的图」（按钮在顶栏，与 .head-code-tag 同属一个 ch-group）
const clicked = await ev(`(() => {
  const head = document.querySelector('.gg-canvas-head');
  if (!head) return 'no head';
  const btn = [...head.querySelectorAll('button')].find(b => b.textContent.includes('返回我的图'));
  if (!btn) return 'no button';
  btn.click();
  return 'clicked';
})()`)
console.log('3) 点击返回:', clicked)
await sleep(4500)
const back = await snap()
console.log('4) 返回后:', JSON.stringify(back))

console.log('')
const okBadge = codeState.badgeVisible === true
const okBtn = clicked === 'clicked'
const okBack = back.fromCode === false && back.pngUrl !== codeState.pngUrl
console.log(`状态条可见: ${okBadge ? '✅' : '❌'}`)
console.log(`返回按钮存在: ${okBtn ? '✅' : '❌'}`)
console.log(`成功回到自己的图: ${okBack ? '✅' : '❌'}`)

ws.close(); proc.kill(); process.exit(0)
