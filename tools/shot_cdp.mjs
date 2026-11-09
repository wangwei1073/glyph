// 用 CDP 驱动无头 Edge：可点击、可截图，用于验证界面改动
// 用法: node tools/shot_cdp.mjs <outPrefix> [width] [height]
import { spawn } from 'node:child_process'
import { writeFileSync, mkdirSync } from 'node:fs'
import { setTimeout as sleep } from 'node:timers/promises'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const out = process.argv[2] || 'shot'
const W = Number(process.argv[3] || 1600)
const H = Number(process.argv[4] || 900)
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'
const PORT = 9333

const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--user-data-dir=' + process.env.TEMP + '\\gg-cdp-profile',
  `--window-size=${W},${H}`, 'about:blank'
], { stdio: 'ignore' })

async function targets() {
  for (let i = 0; i < 40; i++) {
    try {
      const r = await fetch(`http://127.0.0.1:${PORT}/json/list`)
      const list = await r.json()
      const page = list.find(t => t.type === 'page')
      if (page) return page
    } catch { /* 尚未就绪 */ }
    await sleep(250)
  }
  throw new Error('CDP 未就绪')
}

const page = await targets()
const ws = new WebSocket(page.webSocketDebuggerUrl)
let id = 0
const pending = new Map()
ws.addEventListener('message', (ev) => {
  const msg = JSON.parse(ev.data)
  if (msg.id && pending.has(msg.id)) {
    const { resolve, reject } = pending.get(msg.id)
    pending.delete(msg.id)
    msg.error ? reject(new Error(JSON.stringify(msg.error))) : resolve(msg.result)
  }
})
await new Promise(r => ws.addEventListener('open', r, { once: true }))
function send(method, params = {}) {
  const myId = ++id
  ws.send(JSON.stringify({ id: myId, method, params }))
  return new Promise((resolve, reject) => pending.set(myId, { resolve, reject }))
}

await send('Page.enable')
await send('Runtime.enable')
const DPR = Number(process.env.DPR || 1)
await send('Emulation.setDeviceMetricsOverride', { width: W, height: H, deviceScaleFactor: DPR, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(6000)

async function evaluate(expression) {
  const r = await send('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true })
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || ''))
  return r.result.value
}
async function shot(name) {
  const { data } = await send('Page.captureScreenshot', { format: 'png' })
  mkdirSync('.', { recursive: true })
  writeFileSync(name, Buffer.from(data, 'base64'))
  console.log('saved', name)
}

// 步骤来源优先级：STEPS_FILE（文件，避免 shell 转义地狱）> STEPS（内联 JSON）> 无
import { readFileSync } from 'node:fs'
let steps = []
if (process.env.STEPS_FILE) {
  try {
    steps = JSON.parse(readFileSync(process.env.STEPS_FILE, 'utf8'))
  } catch (e) {
    console.error('读取 STEPS_FILE 失败：', e.message)
    process.exit(1)
  }
} else {
  steps = JSON.parse(process.env.STEPS || '[]')
}
await shot(`${out}_0.png`)
let i = 1
for (const step of steps) {
  const res = await evaluate(step)
  console.log('step', i, JSON.stringify(res))
  await sleep(1200)
  await shot(`${out}_${i}.png`)
  i++
}
ws.close()
proc.kill()
process.exit(0)