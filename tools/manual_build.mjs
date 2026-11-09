// 构建用户手册 PDF：把 shots/ 里的截图以 base64 内嵌进 HTML，再用无头 Edge 打印
// 内嵌而非相对路径引用，避免 file:// 下的资源加载差异导致图片缺失
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const ROOT = process.cwd()
const DIR = path.join(ROOT, 'docs', 'manual')
const SHOTS = path.join(DIR, 'shots')
const TPL = path.join(DIR, 'manual.template.html')
const OUT_HTML = path.join(DIR, 'manual.html')
const OUT_PDF = path.join(DIR, 'Glyph用户手册.pdf')

// ---- 1. 内嵌图片 ----
let html = fs.readFileSync(TPL, 'utf8')
const used = []
html = html.replace(/\{\{SHOT:([^}]+)\}\}/g, (_, name) => {
  const p = path.join(SHOTS, name)
  if (!fs.existsSync(p)) {
    console.warn('  ! 缺少截图', name)
    return ''
  }
  used.push(name)
  const b64 = fs.readFileSync(p).toString('base64')
  return `data:image/png;base64,${b64}`
})
fs.writeFileSync(OUT_HTML, html, 'utf8')
console.log(`内嵌截图 ${used.length} 张，HTML ${(html.length / 1024 / 1024).toFixed(2)} MB`)

// ---- 2. 打印 PDF ----
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9531
const PROFILE = path.join(process.env.TEMP, 'gg-pdf-' + Date.now())
const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + PROFILE, '--window-size=1400,1000', 'about:blank'
], { stdio: 'ignore' })

async function gt() {
  for (let i = 0; i < 60; i++) {
    try { const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json(); const p = l.find(x => x.type === 'page'); if (p) return p } catch {}
    await sleep(250)
  }
  throw new Error('CDP 未就绪')
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

await send('Page.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1400, height: 1000, deviceScaleFactor: 1, mobile: false })
const fileUrl = 'file:///' + OUT_HTML.replace(/\\/g, '/')
await send('Page.navigate', { url: fileUrl })
await sleep(4000)

// 等所有图片解码完成
const imgsOk = await send('Runtime.evaluate', {
  expression: `(async () => {
    const imgs = [...document.images];
    await Promise.all(imgs.map(i => i.complete ? Promise.resolve() : new Promise(r => { i.onload = i.onerror = r })));
    return { total: imgs.length, broken: imgs.filter(i => !i.naturalWidth).length };
  })()`,
  awaitPromise: true, returnByValue: true
})
console.log('图片检查:', JSON.stringify(imgsOk.result.value))

const { data } = await send('Page.printToPDF', {
  printBackground: true,
  preferCSSPageSize: true,
  displayHeaderFooter: true,
  headerTemplate: '<div style="font-size:7pt;color:#9aa5b1;width:100%;padding:0 16mm;text-align:right;">Glyph 用户手册</div>',
  footerTemplate: '<div style="font-size:7pt;color:#9aa5b1;width:100%;padding:0 16mm;text-align:center;">第 <span class="pageNumber"></span> / <span class="totalPages"></span> 页</div>',
  marginTop: 0.71, marginBottom: 0.63, marginLeft: 0.63, marginRight: 0.63
})
fs.writeFileSync(OUT_PDF, Buffer.from(data, 'base64'))
const kb = (fs.statSync(OUT_PDF).size / 1024).toFixed(0)
console.log(`PDF 已生成: ${OUT_PDF} (${kb} KB)`)

ws.close(); proc.kill(); process.exit(0)
