// 验证数据源分组下拉：分组顺序、组内倒序、搜索、选中态、操作按钮
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const APP = process.env.GLYPH_URL || 'http://127.0.0.1:4321'
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9811
const PROFILE = path.join(process.env.TEMP, 'gg-src-' + Date.now())

const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu',
  '--hide-scrollbars', '--no-first-run', '--user-data-dir=' + PROFILE,
  '--window-size=1500,950'], { stdio: 'ignore' })

async function gt(){for(let i=0;i<80;i++){try{const l=await(await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();const p=l.find(x=>x.type==='page');if(p)return p}catch{}await sleep(250)}throw new Error('no cdp')}
const t = await gt()
const ws = new WebSocket(t.webSocketDebuggerUrl)
let id = 0; const pending = new Map()
ws.addEventListener('message', e => { const m = JSON.parse(e.data); if (m.id && pending.has(m.id)) { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result) } })
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async x => { const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true }); if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || '')); return r.result.value }

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1500, height: 950, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: APP })
await sleep(8000)

// 关掉草稿提示
await ev(`(()=>{const d=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');if(d)d.click();return 1})()`)
await sleep(1200)

// 1) 收起态：面板高度 + 结构
const collapsed = await ev(`(()=>{
  const src = document.querySelector('.dp-src');
  if (!src) return { err: 'no .dp-src' };
  const r = src.getBoundingClientRect();
  const input = src.querySelector('.el-select__placeholder, .el-select__selected-item');
  return {
    height: Math.round(r.height),
    label: src.querySelector('.dp-subhead')?.textContent?.trim(),
    shown: (input?.textContent || '').trim(),
    hasCurRow: !!src.querySelector('.dp-cur'),
    legacyCards: document.querySelectorAll('.src-card').length,
    legacySubheads: [...document.querySelectorAll('.dp-subhead')].map(e => e.textContent.trim())
  }})()`)
console.log('收起态:', JSON.stringify(collapsed))

// 2) 展开：分组顺序与组内顺序
const opened = await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const sel = document.querySelector('.dp-src .el-select');
  sel.querySelector('.el-select__wrapper, .el-input__wrapper').click();
  await w(700);
  const pop = [...document.querySelectorAll('.el-select-dropdown')].filter(e=>e.getBoundingClientRect().height>0)[0];
  if (!pop) return { err: 'dropdown not open' };
  const groups = [...pop.querySelectorAll('.el-select-group__title')].map(e=>e.textContent.trim());
  const items = [...pop.querySelectorAll('.el-select-dropdown__item')].map(e=>({
    text: e.textContent.trim().replace(/\\s+/g,' ').slice(0,46),
    selected: e.classList.contains('is-selected'),
    hasActs: !!e.querySelector('.so-acts')
  }));
  return { groups, count: items.length, first: items.slice(0,6), selectedIdx: items.findIndex(i=>i.selected) };
})()`)
console.log('展开:', JSON.stringify(opened, null, 1))

const { data } = await send('Page.captureScreenshot', { format: 'png' })
const out = path.join(process.cwd(), 'docs', 'mockups', 'data-source-live.png')
fs.writeFileSync(out, Buffer.from(data, 'base64'))
console.log('saved', out)
ws.close(); proc.kill(); process.exit(0)
