import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9479
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-ro-test',
  '--window-size=1600,900', 'about:blank'
], { stdio: 'ignore' })

async function getTarget() {
  for (let i = 0; i < 40; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()
      const p = list.find(t => t.type === 'page')
      if (p) return p
    } catch {}
    await sleep(250)
  }
  throw new Error('no cdp')
}
const target = await getTarget()
const ws = new WebSocket(target.webSocketDebuggerUrl)
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
const evaluate = async (expr) => {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description||''))
  return r.result.value
}

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(6000)

// 出图
await evaluate(`(async () => {
  const wait = (ms) => new Promise(r => setTimeout(r, ms));
  const sel = document.querySelector('.src-select input, .el-select input');
  if (sel) { sel.click(); await wait(900);
    const o = [...document.querySelectorAll('.el-select-dropdown__item')].find(x => x.textContent.includes('汽车油耗'));
    if (o) { o.click(); await wait(2500); } }
  const b = [...document.querySelectorAll('button')].find(x => x.textContent.includes('添加第一个图层'));
  if (b) { b.click(); await wait(5000); }
  return 1;
})()`)
await sleep(1500)

// 检查 ResizeObserver 是否被注册
const roInfo = await evaluate(`(() => {
  const app = document.querySelector('#app').__vue_app__;
  const wrap = document.querySelector('.gg-canvas-wrap');
  return {
    wrapExists: !!wrap,
    wrapW: wrap ? Math.round(wrap.getBoundingClientRect().width) : 0,
    hasRO: typeof ResizeObserver !== 'undefined',
    // Vue 组件实例上的 canvasWrapEl 是否已绑定
    vueHasRef: !!(wrap && wrap.__vueParentComponent)
  };
})()`)
console.log('RO 检查:', JSON.stringify(roInfo))

// 用真实拖动（Input 事件）改右栏宽度
console.log('--- 真实拖动右栏边界 ---')
await evaluate(`(() => {
  const handle = document.querySelector('.gg-resizer');
  if (!handle) return { err: 'no resizer' };
  const r = handle.getBoundingClientRect();
  window.__dragStart = { x: r.x + 2, y: r.y + 100 };
  return { found: true, x: Math.round(r.x), y: Math.round(r.y) };
})()`)

const dragInfo = await evaluate(`(() => {
  const handle = document.querySelector('.gg-resizer');
  const r = handle.getBoundingClientRect();
  return { x: Math.round(r.x), y: Math.round(r.y) };
})()`)
console.log('resizer 位置:', JSON.stringify(dragInfo))

// 用 CDP 派发真实鼠标事件
await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: dragInfo.x, y: dragInfo.y + 100, button: 'left', clickCount: 1 })
await sleep(200)
for (let i = 1; i <= 6; i++) {
  await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: dragInfo.x - i * 25, y: dragInfo.y + 100, button: 'left' })
  await sleep(80)
}
await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: dragInfo.x - 150, y: dragInfo.y + 100, button: 'left', clickCount: 1 })

const snap = () => evaluate(`(() => {
  const app = document.querySelector('#app').__vue_app__;
  const st = app.config.globalProperties.$pinia.state.value.spec;
  const wrap = document.querySelector('.gg-canvas-wrap');
  return {
    renderOpts: { w: st.renderOpts.width, h: st.renderOpts.height },
    wrapW: wrap ? Math.round(wrap.getBoundingClientRect().width) : 0,
    rendering: st.rendering
  };
})()`)

await sleep(1200)
console.log('拖动后 +1.2s:', JSON.stringify(await snap()))
await sleep(3500)
console.log('拖动后 +4.7s:', JSON.stringify(await snap()))

ws.close(); proc.kill(); process.exit(0)
