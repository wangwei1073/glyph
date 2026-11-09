// 决定性测试：一个浏览器 → 推送 → 从外部查队列是否被取走 → 查 UI 状态
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const APP = 'http://127.0.0.1:4321'
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9711
const PROFILE = path.join(process.env.TEMP, 'gg-single-' + Date.now())
const code = fs.readFileSync(path.join(process.cwd(), 'testdata', 'simple_plot.R'), 'utf8')

const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`,'--headless=new','--disable-gpu','--hide-scrollbars','--no-first-run','--user-data-dir='+PROFILE,'--window-size=1500,900','about:blank'], { stdio: 'ignore' })
async function gt(){for(let i=0;i<60;i++){try{const l=await(await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();const p=l.find(x=>x.type==='page');if(p)return p}catch{}await sleep(250)}throw new Error('no cdp')}
const t = await gt()
const ws = new WebSocket(t.webSocketDebuggerUrl)
let id = 0; const pending = new Map()
ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result) } })
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async x => { const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || '')); return r.result.value }

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1500, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: APP })
await sleep(9000)
await ev(`(()=>{const d=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');if(d)d.click();return 1})()`)
await sleep(1500)

const before = await fetch(`${APP}/api/code/pending`).then(r => r.json())
console.log('推送前队列:', JSON.stringify({ seq: before.seq }))

const pushed = await fetch(`${APP}/api/code/push`, {
  method: 'POST', headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify({ code, run: true })
}).then(r => r.json())
console.log('推送:', JSON.stringify(pushed))

await sleep(5000)
const after = await fetch(`${APP}/api/code/pending`).then(r => r.json())
console.log('5s 后队列（从外部查）:', JSON.stringify({ seq: after.seq, len: (after.code || '').length }))

const state = await ev(`(()=>{
  const pinia=document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
  const spec=pinia._s.get('spec'); const ui=pinia._s.get('ui');
  const img=document.querySelector('.gg-canvas-img');
  return { tab:ui.tab, fromCode:!!spec.last.renderedFromCode, ok:spec.last.ok,
    hasImg:!!img, naturalW:img?img.naturalWidth:0,
    err: spec.last.error?String(spec.last.error).slice(0,80):null,
    warnings:(spec.last.warnings||[]).length }})()`)
console.log('UI 状态:', JSON.stringify(state))

const { data } = await send('Page.captureScreenshot', { format: 'png' })
fs.writeFileSync(path.join(process.cwd(), 'testdata', 'glyph_simple.png'), Buffer.from(data, 'base64'))
console.log('saved')

ws.close(); proc.kill(); process.exit(0)
