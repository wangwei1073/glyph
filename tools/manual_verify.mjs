// 验证 PDF 排版：按 #page=N 直接跳页截图
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9535
const PDF = path.join(process.cwd(), 'docs', 'manual', 'Glyph用户手册.pdf')
const OUT = path.join(process.cwd(), 'docs', 'manual', 'verify')
fs.mkdirSync(OUT, { recursive: true })
const PROFILE = path.join(process.env.TEMP, 'gg-pdfview2-' + Date.now())
const PAGES = (process.env.PAGES || '1,4,8,11').split(',').map(Number)

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu',
  '--no-first-run', '--user-data-dir=' + PROFILE, '--window-size=900,1250', 'about:blank'
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

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 900, height: 1250, deviceScaleFactor: 1, mobile: false })

const base = 'file:///' + PDF.replace(/\\/g, '/')
for (const pg of PAGES) {
  // 先回空白页：同一文档内只改 hash 不会重新加载，PDF 阅读器会停在原页
  await send('Page.navigate', { url: 'about:blank' })
  await sleep(600)
  await send('Page.navigate', { url: `${base}#page=${pg}` })
  await sleep(5000)
  const { data } = await send('Page.captureScreenshot', { format: 'png' })
  fs.writeFileSync(path.join(OUT, `p${String(pg).padStart(2, '0')}.png`), Buffer.from(data, 'base64'))
  console.log('saved page', pg)
}

ws.close(); proc.kill(); process.exit(0)
