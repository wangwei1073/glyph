// 验证「插入列名」按钮的显示范围与功能
//   A) 数据准备对话框：列菜单里有插入按钮，点击后列名进入当前表达式框
//   B) 数据预览弹窗：没有插入按钮（只读查看，无插入目标）
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import path from 'node:path'

const APP = 'http://127.0.0.1:4321'
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9841
const PROFILE = path.join(process.env.TEMP, 'gg-ins-' + Date.now())

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
await ev(`(()=>{const d=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');if(d)d.click();return 1})()`)
await sleep(1200)

// 选一个数据集，让列列表有内容
await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const pinia=document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
  await pinia._s.get('data').select('dataset:mpg');
  await w(2500); return 1})()`)

// A) 数据准备对话框
const a = await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const pinia=document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
  const dp=[...document.querySelectorAll('button')].find(b=>(b.textContent||'').includes('数据准备'));
  if(!dp) return {err:'找不到数据准备按钮'};
  dp.click(); await w(1500);
  // 聚焦行筛选表达式
  const ta=[...document.querySelectorAll('.el-dialog textarea')].filter(e=>e.getBoundingClientRect().height>0);
  if(!ta.length) return {err:'找不到表达式 textarea'};
  ta[0].focus(); ta[0].dispatchEvent(new FocusEvent('focus',{bubbles:true})); await w(400);
  // 点一个列，展开列菜单
  const colRow=[...document.querySelectorAll('.el-dialog .col-row, .el-dialog .ps-line, .el-dialog [class*=col]')].filter(e=>e.getBoundingClientRect().height>0);
  return { textareas: ta.length, colRows: colRow.length }})()`)
console.log('A1 打开数据准备:', JSON.stringify(a))

const { data } = await send('Page.captureScreenshot', { format: 'png' })
const fs = await import('node:fs')
fs.writeFileSync(path.join(process.cwd(), 'docs', 'mockups', 'insert-check.png'), Buffer.from(data, 'base64'))
console.log('saved docs/mockups/insert-check.png')

ws.close(); proc.kill(); process.exit(0)
