// 通用：把一个本地 HTML 渲染成 PNG（2x 缩放，按内容自适应高度）
// 用法: node tools/shot_html.mjs <html相对路径> <png输出路径> [宽]
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const [htmlRel, pngRel, widthArg] = process.argv.slice(2)
if (!htmlRel || !pngRel) {
  console.error('用法: node tools/shot_html.mjs <html> <png> [宽]')
  process.exit(1)
}
const W = Number(widthArg || 1280)
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9900 + Math.floor(Math.random() * 90)
const PROFILE = path.join(process.env.TEMP, 'gg-shot-' + Date.now())
const FILE = 'file:///' + path.resolve(htmlRel).replace(/\\/g, '/')

const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu',
  '--hide-scrollbars', '--no-first-run', '--user-data-dir=' + PROFILE,
  `--window-size=${W},1200`], { stdio: 'ignore' })

async function gt() {
  for (let i = 0; i < 80; i++) {
    try {
      const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json()
      const p = l.find(x => x.type === 'page')
      if (p) return p
    } catch {}
    await sleep(250)
  }
  throw new Error('no cdp')
}

const t = await gt()
const ws = new WebSocket(t.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.addEventListener('message', e => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) {
    const p = pending.get(m.id); pending.delete(m.id)
    m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result)
  }
})
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async x => { const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.text); return r.result.value }

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: W, height: 1200, deviceScaleFactor: 2, mobile: false })
await send('Page.navigate', { url: FILE })
await sleep(2200)

const h = await ev('Math.ceil(document.body.scrollHeight)')
await send('Emulation.setDeviceMetricsOverride', { width: W, height: h, deviceScaleFactor: 2, mobile: false })
await sleep(600)

const { data } = await send('Page.captureScreenshot', { format: 'png' })
fs.mkdirSync(path.dirname(path.resolve(pngRel)), { recursive: true })
fs.writeFileSync(path.resolve(pngRel), Buffer.from(data, 'base64'))
console.log(`saved ${pngRel}  ${W}x${h} @2x`)
ws.close(); proc.kill(); process.exit(0)
