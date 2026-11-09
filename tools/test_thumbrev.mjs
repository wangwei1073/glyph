// 验证 UI 层：更新后卡片缩略图 URL（?v=rev）变化，且图片真的重新加载
// 用临时条目，测完删除，不碰用户既有条目
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9504
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

// 1) 用 P2 的 spec 建一个无项目的临时条目
const openRes = await (await fetch(`${URL_}/api/pins/open`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ id: 'P2' })
})).json()
const saveRes = await (await fetch(`${URL_}/api/pins/save`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ specJson: openRes.specJson, label: '缩略图UI测试', project: '' })
})).json()
const tid = saveRes.id
console.log('临时条目:', tid)

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-thumbui',
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

const cardImg = () => ev(`(() => {
  const cards = [...document.querySelectorAll('.pin-card')].filter(c => c.getBoundingClientRect().height > 0);
  const c = cards.find(x => (x.querySelector('.pc-name')?.textContent || '').includes('缩略图UI测试'));
  if (!c) return { err: 'card not found' };
  const img = c.querySelector('img');
  return { src: img.getAttribute('src'), naturalW: img.naturalWidth, complete: img.complete };
})()`)

// 打开临时条目 → 改 geom → 更新
const flow = await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const labels = rails.map(b => b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2500);
  const cards = [...document.querySelectorAll('.pin-card')].filter(c => c.getBoundingClientRect().height > 0);
  const target = cards.find(c => (c.querySelector('.pc-name')?.textContent || '').includes('缩略图UI测试'));
  if (!target) return { err: 'card not visible' };
  target.click();
  await w(1200);
  const cb = document.querySelector('.el-message-box__btns .el-button--primary');
  if (cb) cb.click();
  await w(4000);
  const store = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia._s.get('spec');
  store.spec.layers[0].geom = 'area';     // 视觉差异明显
  store.renderNow();
  await w(4500);
  rails[labels.indexOf('图库')].click(); await w(1800);
  const btns = [...document.querySelectorAll('.gg-right button')];
  const main = btns.find(b => (b.textContent || '').includes('更新到'));
  if (!main) return { err: 'no update button' };
  main.click();
  await w(4500);
  return { ok: true, srcPin: store.sourcePinId };
})()`)
console.log('流程:', JSON.stringify(flow))
await sleep(2500)

const after = await cardImg()
console.log('更新后卡片图:', JSON.stringify(after))

console.log('')
console.log(`URL 带版本号: ${after.src && after.src.includes('?v=') ? '✅ ' + after.src : '❌ ' + after.src}`)
console.log(`URL 版本 > 0: ${after.src && !after.src.endsWith('?v=0') ? '✅' : '❌ rev 未变'}`)
console.log(`图片已加载: ${after.naturalW > 0 ? '✅ ' + after.naturalW + 'px' : '❌'}`)

// 清理
await fetch(`${URL_}/api/pins/delete`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ id: tid })
})
console.log(`已删除临时条目 ${tid}`)

ws.close(); proc.kill(); process.exit(0)
