// 图库卡片内联重命名：干净的端到端断言
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9509
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'
const NEW_NAME = '销售趋势-改'

const openRes = await (await fetch(`${URL_}/api/pins/open`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: 'P2' })
})).json()
const saveRes = await (await fetch(`${URL_}/api/pins/save`, {
  method: 'POST', headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ specJson: openRes.specJson, label: '临时改名测试', project: '' })
})).json()
const tid = saveRes.id
console.log('临时条目:', tid)

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-rename3',
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

const s1 = await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const labels = rails.map(b => b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2500);
  const card = [...document.querySelectorAll('.pin-card')].filter(c => c.getBoundingClientRect().height > 0)
    .find(c => (c.querySelector('.pc-name')?.textContent || '').includes('临时改名测试'));
  if (!card) return { err: 'no card' };
  card.querySelector('.pc-edit').click();
  await w(900);
  const input = document.querySelector('.pin-card .pc-rename input');
  if (!input) return { err: 'no input' };
  input.focus(); input.select();
  const r = input.getBoundingClientRect();
  return { ok: true, x: Math.round(r.x + r.width/2), y: Math.round(r.y + r.height/2), before: input.value };
})()`)
console.log('进入编辑态:', JSON.stringify(s1))
if (!s1.ok) { ws.close(); proc.kill(); process.exit(1) }

// 聚焦后用 insertText 替换选中文本
await send('Input.dispatchMouseEvent', { type: 'mousePressed', x: s1.x, y: s1.y, button: 'left', clickCount: 1 })
await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x: s1.x, y: s1.y, button: 'left', clickCount: 1 })
await sleep(300)
await ev(`(() => { const i = document.querySelector('.pin-card .pc-rename input'); i.focus(); i.select(); return 1 })()`)
await sleep(200)
await send('Input.insertText', { text: NEW_NAME })
await sleep(700)
console.log('输入后 DOM 值:', JSON.stringify(await ev(`document.querySelector('.pin-card .pc-rename input')?.value`)))

await send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 })
await send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 })
await sleep(3500)

const after = await ev(`(() => {
  const card = [...document.querySelectorAll('.pin-card')].filter(c => c.getBoundingClientRect().height > 0)
    .find(c => (c.querySelector('.pc-name')?.textContent || '').includes('销售趋势'));
  const store = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia._s.get('pins');
  const inStore = store.all.find(p => p.id === ${JSON.stringify(tid)});
  return {
    cardName: card ? card.querySelector('.pc-name').textContent.trim() : null,
    storeLabel: inStore ? inStore.label : null,
    stillEditing: !!document.querySelector('.pc-rename input')
  };
})()`)
const finalPins = await (await fetch(`${URL_}/api/pins`)).json()
const target = finalPins.pins.find(p => p.id === tid)

console.log('卡片:', JSON.stringify(after.cardName), '| store:', JSON.stringify(after.storeLabel), '| 后端:', JSON.stringify(target?.label))
console.log('')
console.log(`卡片显示新名: ${after.cardName === NEW_NAME ? '✅' : '❌'}`)
console.log(`store 已更新: ${after.storeLabel === NEW_NAME ? '✅' : '❌'}`)
console.log(`后端已保存: ${target?.label === NEW_NAME ? '✅' : '❌'}`)
console.log(`编辑态已退出: ${after.stillEditing === false ? '✅' : '❌'}`)

await fetch(`${URL_}/api/pins/delete`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ id: tid }) })
console.log(`已删除临时条目 ${tid}`)
ws.close(); proc.kill(); process.exit(0)
