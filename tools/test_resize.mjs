// 复现：改变窗口尺寸后画布图片消失 / 不自动渲染
// 用 CDP 的真实 resize（Emulation.setDeviceMetricsOverride）触发，而非改样式
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9477
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-resize-profile',
  '--window-size=1600,900', 'about:blank'
], { stdio: 'ignore' })

async function getTarget() {
  for (let i = 0; i < 40; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()
      const p = list.find(t => t.type === 'page')
      if (p) return p
    } catch { /* not ready */ }
    await sleep(250)
  }
  throw new Error('CDP 未就绪')
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
const send = (method, params = {}) => {
  const i = ++id
  ws.send(JSON.stringify({ id: i, method, params }))
  return new Promise((res, rej) => pending.set(i, { resolve: res, reject: rej }))
}

async function setSize(w, h) {
  await send('Emulation.setDeviceMetricsOverride', { width: w, height: h, deviceScaleFactor: 1, mobile: false })
}

async function evaluate(expr) {
  const r = await send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text)
  return r.result.value
}

const stateOf = () => evaluate(`(() => {
  const app = document.querySelector('#app').__vue_app__;
  if (!app) return { err: 'no app' };
  const st = app.config.globalProperties.$pinia.state.value.spec;
  const img = document.querySelector('.gg-canvas-img');
  const hint = document.querySelector('.gg-canvas-wrap .gg-empty-hint');
  return {
    layers: st.spec.layers.length,
    renderedFromCode: !!st.last.renderedFromCode,
    pngUrl: st.last.pngUrl ? st.last.pngUrl.slice(0, 30) : null,
    hasPng: !!st.last.pngUrl,
    ok: st.last.ok,
    error: st.last.error ? String(st.last.error).slice(0, 60) : null,
    rendering: st.rendering,
    renderOpts: { w: st.renderOpts.width, h: st.renderOpts.height },
    domImg: !!img,
    domImgComplete: img ? img.complete : null,
    domImgNaturalW: img ? img.naturalWidth : 0,
    emptyHintVisible: hint ? hint.getBoundingClientRect().height > 0 : false
  };
})()`)

await send('Page.enable')
await send('Runtime.enable')
await setSize(1600, 900)
await send('Page.navigate', { url: URL_ })
await sleep(6000)

console.log('初始:', JSON.stringify(await stateOf()))

// 选数据集 + 加图层，渲染一张正常图
await evaluate(`(async () => {
  const wait = (ms) => new Promise(r => setTimeout(r, ms));
  const sel = document.querySelector('.src-select input, .el-select input');
  if (sel) {
    sel.click(); await wait(900);
    const opt = [...document.querySelectorAll('.el-select-dropdown__item')].find(o => o.textContent.includes('汽车油耗'));
    if (opt) { opt.click(); await wait(2500); }
  }
  const addBtn = [...document.querySelectorAll('button')].find(b => b.textContent.includes('添加第一个图层'));
  if (addBtn) { addBtn.click(); await wait(5000); }
  return 'done';
})()`)
await sleep(2000)
console.log('出图后:', JSON.stringify(await stateOf()))

// 关键：改窗口尺寸
console.log('--- 缩小到 1200x800 ---')
await setSize(1200, 800)
await sleep(600)
console.log('resize +0.6s:', JSON.stringify(await stateOf()))
await sleep(3000)
console.log('resize +3.6s:', JSON.stringify(await stateOf()))
await sleep(4000)
console.log('resize +7.6s:', JSON.stringify(await stateOf()))

ws.close()
proc.kill()
process.exit(0)
