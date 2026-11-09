// 验证：打开 spec 条目后能继续编辑（改图层 → 重新渲染生效）
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9494
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-specedit',
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

// 直接打开 spec 条目（未 dirty，不应弹确认）
const opened = await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const labels = rails.map(b => b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2200);
  const cards = [...document.querySelectorAll('.pin-card')].filter(c => c.getBoundingClientRect().height > 0);
  const names = cards.map(c => (c.querySelector('.pc-name')?.textContent || '').trim());
  const idx = names.findIndex(n => n.includes('散点图 A'));
  if (idx < 0) return { err: 'not found', names };
  cards[idx].click();
  await w(1200);
  const confirmBtn = document.querySelector('.el-message-box__btns .el-button--primary');
  const hadConfirm = !!confirmBtn;
  if (confirmBtn) confirmBtn.click();
  await w(4000);
  return { ok: true, hadConfirm };
})()`)
console.log('打开散点图 A:', JSON.stringify(opened))
await sleep(2000)

const before = await ev(`(() => {
  const app = document.querySelector('#app').__vue_app__;
  const s = app.config.globalProperties.$pinia.state.value.spec;
  const d = app.config.globalProperties.$pinia.state.value.data;
  return {
    srcKey: d.srcKey, geom: s.spec.layers[0]?.geom,
    x: s.spec.layers[0]?.aes?.x?.map, y: s.spec.layers[0]?.aes?.y?.map,
    png: (s.last.pngUrl || '').slice(-18)
  };
})()`)
console.log('打开后状态:', JSON.stringify(before))

// 编辑：把 geom 改成 boxplot（模拟用户继续编辑）
const edited = await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const app = document.querySelector('#app').__vue_app__;
  const store = app.config.globalProperties.$pinia._s.get('spec');
  store.spec.layers[0].geom = 'boxplot';
  store.renderNow();
  await w(4500);
  return {
    geom: store.spec.layers[0].geom,
    png: (store.last.pngUrl || '').slice(-18),
    ok: store.last.ok,
    err: store.last.error ? String(store.last.error).slice(0, 60) : null
  };
})()`)
console.log('编辑为 boxplot:', JSON.stringify(edited))

console.log('')
console.log(`未 dirty 时不弹确认: ${opened.hadConfirm === false ? '✅' : '⚠️ 弹了确认'}`)
console.log(`打开后数据集正确: ${before.srcKey === 'dataset:mpg' ? '✅' : '❌ ' + before.srcKey}`)
console.log(`打开后可继续编辑: ${edited.geom === 'boxplot' && edited.ok ? '✅' : '❌'}`)
console.log(`编辑后重新渲染: ${edited.png !== before.png ? '✅' : '❌ 图未变'}`)

ws.close(); proc.kill(); process.exit(0)
