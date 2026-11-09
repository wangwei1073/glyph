// 补拍：数据准备弹窗
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9522
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'
const OUT = path.join(process.cwd(), 'docs', 'manual', 'shots')
const PROFILE = path.join(process.env.TEMP, 'gg-prep-' + Date.now())

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
  console.log('saved', name)
}
const box = (sel) => ev(`(() => {
  const el = document.querySelector(${JSON.stringify(sel)});
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
})()`)

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(7000)

// 丢弃草稿 + 选数据集
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const drop = [...document.querySelectorAll('span,button')].find(b => (b.textContent||'').trim() === '丢弃');
  if (drop) { drop.click(); await w(1200); }
  const sel = document.querySelector('.src-select input, .el-select input');
  if (sel) { sel.click(); await w(900);
    const o = [...document.querySelectorAll('.el-select-dropdown__item')].find(x => x.textContent.includes('汽车油耗'));
    if (o) { o.click(); await w(3000); } }
  return 1;
})()`)
await sleep(2500)

const opened = await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const btn = [...document.querySelectorAll('button')].find(b => (b.textContent || '').includes('数据准备'));
  if (!btn) return { err: 'no button' };
  btn.click();
  await w(2800);
  return { ok: true };
})()`)
console.log(JSON.stringify(opened))
await sleep(2000)

const b = await box('.el-dialog')
console.log('dialog box:', JSON.stringify(b))
await shot('18-data-prep.png', b || undefined)

ws.close(); proc.kill(); process.exit(0)
