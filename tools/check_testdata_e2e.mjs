// 端到端：打开 Glyph → 通过 /api/code/push 推送绘图脚本(run=true) → 自动渲染出图
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const APP = 'http://127.0.0.1:4321'
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9691
const PROFILE = path.join(process.env.TEMP, 'gg-e2e-' + Date.now())

const scriptPath = path.join(process.cwd(), 'testdata', 'simple_plot.R')
const code = fs.readFileSync(scriptPath, 'utf8')

const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`,'--headless=new','--disable-gpu','--hide-scrollbars','--no-first-run','--user-data-dir='+PROFILE,'--window-size=1600,900','about:blank'], { stdio: 'ignore' })
async function gt(){for(let i=0;i<60;i++){try{const l=await(await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();const p=l.find(x=>x.type==='page');if(p)return p}catch{}await sleep(250)}throw new Error('no cdp')}
const t = await gt()
const ws = new WebSocket(t.webSocketDebuggerUrl)
let id = 0; const pending = new Map()
ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result) } })
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async x => { const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || '')); return r.result.value }

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: APP })
await sleep(8000)

// 关掉可能的草稿提示
await ev(`(()=>{const d=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');if(d)d.click();return 1})()`)
await sleep(1000)

// 推送（run=true）
const res = await fetch(`${APP}/api/code/push`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json; charset=utf-8' },
  body: JSON.stringify({ code, run: true })
}).then(r => r.json())
console.log('推送结果:', JSON.stringify(res))

// 等待轮询 + 渲染（脚本含 patchwork，渲染稍慢）
await sleep(15000)

const state = await ev(`(()=>{
  const pinia = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
  const spec = pinia._s.get('spec'); const ui = pinia._s.get('ui');
  const img = document.querySelector('.gg-canvas-img');
  const cm = [...document.querySelectorAll('.gg-right .cm-content')].filter(c=>c.getBoundingClientRect().height>0)[0];
  return {
    tab: ui.tab,
    renderedFromCode: !!spec.last.renderedFromCode,
    ok: spec.last.ok,
    err: spec.last.error ? String(spec.last.error).slice(0, 120) : null,
    elapsedMs: spec.last.elapsed,
    hasImg: !!img,
    naturalW: img ? img.naturalWidth : 0, naturalH: img ? img.naturalHeight : 0,
    editorHead: (cm?.textContent || '').slice(0, 40),
    warnings: (spec.last.warnings || []).length
  };
})()`)
console.log('界面状态:', JSON.stringify(state, null, 1))

const { data } = await send('Page.captureScreenshot', { format: 'png' })
fs.writeFileSync(path.join(process.cwd(), 'testdata', 'glyph_simple.png'), Buffer.from(data, 'base64'))
console.log('saved testdata/glyph_render.png')

ws.close(); proc.kill(); process.exit(0)
