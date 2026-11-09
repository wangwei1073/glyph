// 验证「打开 spec 图库条目」方案 C：
// 1) 当前在数据集 A 上画图 → 打开一个用数据集 B 的 spec 条目
// 2) 应自动切到 B，图层/映射完整还原，可直接编辑
// 3) 未保存改动时应有确认
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9493
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-specpin',
  '--window-size=1600,900', 'about:blank'
], { stdio: 'ignore' })

async function gt() {
  for (let i = 0; i < 40; i++) {
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
  if (m.id && pending.has(m.id)) {
    const p = pending.get(m.id); pending.delete(m.id)
    m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result)
  }
})
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async (x) => {
  const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true })
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || ''))
  return r.result.value
}

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(6000)

const snap = () => ev(`(() => {
  const app = document.querySelector('#app').__vue_app__;
  const s = app.config.globalProperties.$pinia.state.value.spec;
  const d = app.config.globalProperties.$pinia.state.value.data;
  const img = document.querySelector('.gg-canvas-img');
  return {
    srcKey: d.srcKey,
    layers: s.spec.layers.length,
    layer0: s.spec.layers[0] ? {
      geom: s.spec.layers[0].geom,
      x: s.spec.layers[0].aes?.x?.map || null,
      y: s.spec.layers[0].aes?.y?.map || null
    } : null,
    dataSource: JSON.stringify(s.spec.data.source),
    fromCode: !!s.last.renderedFromCode,
    hasImg: !!img,
    naturalW: img ? img.naturalWidth : 0,
    dirty: s.dirty,
    colCount: (d.columns || []).length
  };
})()`)

// 1) 先在 mpg 上建自己的图
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
console.log('1) 当前（mpg 上的散点图）:', JSON.stringify(await snap()))

// 2) 进图库，点「经济线图 B」（spec 条目，数据集 economics）
const clicked = await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const labels = rails.map(b => b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2200);
  const cards = [...document.querySelectorAll('.pin-card')].filter(c => c.getBoundingClientRect().height > 0);
  const names = cards.map(c => (c.querySelector('.pc-name')?.textContent || '').trim());
  const idx = names.findIndex(n => n.includes('经济线图'));
  if (idx < 0) return { err: 'not found', names };
  cards[idx].click();
  await w(1000);
  // 可能有确认框
  const confirmBtn = document.querySelector('.el-message-box__btns .el-button--primary');
  const hadConfirm = !!confirmBtn;
  if (confirmBtn) { confirmBtn.click(); }
  await w(4000);
  return { ok: true, names, hadConfirm };
})()`)
console.log('2) 点击经济线图 B:', JSON.stringify(clicked))
await sleep(3000)
console.log('3) 打开后:', JSON.stringify(await snap()))

ws.close(); proc.kill(); process.exit(0)
