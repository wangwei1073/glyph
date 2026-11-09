// 验证方案 B：编辑自图库条目 → 主按钮「更新到 Pn」→ 覆盖该条，条目数不变、标签不变
// 并验证「另存为新条目」仍然可用
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9499
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-upd',
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
const pinsOf = async () => {
  const j = await (await fetch(`${URL_}/api/pins`)).json()
  return j.pins
}

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(6000)

const before = await pinsOf()
const target = before.find(p => p.label === '散点图 A')
console.log(`起点: ${before.length} 条，目标 ${target.id}「${target.label}」`)

// 打开「散点图 A」→ 改 geom 为 boxplot → 点主按钮「更新到…」
const upd = await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const labels = rails.map(b => b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2500);

  const cards = [...document.querySelectorAll('.pin-card')].filter(c => c.getBoundingClientRect().height > 0);
  const names = cards.map(c => (c.querySelector('.pc-name')?.textContent || '').trim());
  const idx = names.findIndex(n => n.includes('散点图 A'));
  if (idx < 0) return { err: 'card not found', names };
  cards[idx].click();
  await w(1200);
  const cbtn = document.querySelector('.el-message-box__btns .el-button--primary');
  if (cbtn) cbtn.click();
  await w(4000);

  const store = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia._s.get('spec');
  const srcPin = store.sourcePinId;
  store.spec.layers[0].geom = 'boxplot';
  store.renderNow();
  await w(4000);

  rails[labels.indexOf('图库')].click(); await w(1800);
  // 找「更新到「…」」主按钮
  const btns = [...document.querySelectorAll('.gg-right button, .el-dropdown button')];
  const mainBtn = btns.find(b => (b.textContent || '').includes('更新到'));
  if (!mainBtn) return { err: 'no update button', srcPin, btnTexts: btns.map(b => (b.textContent||'').trim()).filter(Boolean).slice(0,10) };
  mainBtn.click();
  await w(3500);
  return { ok: true, srcPin, srcLabel: store.sourcePinLabel };
})()`)
console.log('更新操作:', JSON.stringify(upd))
await sleep(1200)

const after = await pinsOf()
console.log(`更新后: ${after.length} 条`)
const t2 = after.find(p => p.id === target.id)
console.log(`  ${target.id}: 标签 ${target.label} → ${t2?.label}`)

// 再验证「另存为新条目」
const asNew = await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const triggers = [...document.querySelectorAll('.el-dropdown .el-dropdown__caret-button, .el-dropdown__caret-button')];
  if (!triggers.length) return { err: 'no caret' };
  triggers[0].click();
  await w(1200);
  const items = [...document.querySelectorAll('.el-dropdown-menu__item')];
  const texts = items.map(i => (i.textContent || '').trim());
  const newItem = items.find(i => (i.textContent || '').includes('另存为'));
  if (!newItem) return { err: 'no new item', texts };
  newItem.click();
  await w(3500);
  return { ok: true, texts };
})()`)
console.log('另存操作:', JSON.stringify(asNew))
await sleep(1200)

const final = await pinsOf()
console.log(`另存后: ${final.length} 条`)
console.log(' 新增:', final.filter(p => !after.some(a => a.id === p.id)).map(p => `${p.id}:${p.label}`).join(', ') || '无')

console.log('')
console.log(`更新不新增条目: ${after.length === before.length ? '✅' : '❌ ' + before.length + '→' + after.length}`)
console.log(`更新后标签不变: ${t2 && t2.label === target.label ? '✅' : '❌'}`)
console.log(`另存为新条目可用: ${final.length === after.length + 1 ? '✅' : '❌'}`)

ws.close(); proc.kill(); process.exit(0)
