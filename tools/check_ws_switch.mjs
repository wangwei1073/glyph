import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9675
const PROFILE = path.join(process.env.TEMP, 'gg-ws3-' + Date.now())
const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`,'--headless=new','--disable-gpu','--hide-scrollbars','--no-first-run','--user-data-dir='+PROFILE,'--window-size=1400,900','about:blank'], { stdio: 'ignore' })
async function gt(){for(let i=0;i<60;i++){try{const l=await(await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();const p=l.find(x=>x.type==='page');if(p)return p}catch{}await sleep(250)}throw new Error('no cdp')}
const t=await gt();const ws=new WebSocket(t.webSocketDebuggerUrl)
let id=0;const pending=new Map()
ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result)}})
await new Promise(r=>ws.addEventListener('open',r,{once:true}))
const send=(m,p={})=>{const i=++id;ws.send(JSON.stringify({id:i,method:m,params:p}));return new Promise((a,b)=>pending.set(i,{resolve:a,reject:b}))}
const ev=async x=>{const r=await send('Runtime.evaluate',{expression:x,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.text+' '+(r.exceptionDetails.exception?.description||''));return r.result.value}
await send('Page.enable');await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride',{width:1400,height:900,deviceScaleFactor:1,mobile:false})
await send('Page.navigate',{url:'http://127.0.0.1:4321'});await sleep(8000)

const target = process.env.TARGET_WS || ''
const step1 = await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const drop=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');
  if(drop){drop.click();await w(1000)}
  const projBtn=[...document.querySelectorAll('.act-actions button')].find(b=>(b.textContent||'').includes('项目'));
  if(!projBtn) return {err:'no project button'};
  projBtn.click(); await w(1000);
  const item=[...document.querySelectorAll('.el-dropdown-menu__item')].find(i=>(i.textContent||'').includes('切换工作目录'));
  if(!item) return {err:'no menu item'};
  item.click(); await w(1500);
  const box=document.querySelector('.el-message-box');
  const input=box?.querySelector('input');
  return { dialog: !!box, title: box?.querySelector('.el-message-box__title')?.textContent?.trim(),
           current: input?.value || null }})()`)
console.log('打开对话框:', JSON.stringify(step1))

const done = await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const box=document.querySelector('.el-message-box');
  if(!box) return {err:'dialog gone'};
  const input=box.querySelector('input');
  const setter=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
  setter.call(input, ${JSON.stringify(target)});
  input.dispatchEvent(new Event('input',{bubbles:true}));
  await w(500);
  const ok=box.querySelector('.el-message-box__btns .el-button--primary');
  ok.click(); await w(4000);
  const pinia=document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
  const meta=pinia._s.get('meta'); const spec=pinia._s.get('spec'); const pins=pinia._s.get('pins');
  return { wsRoot: meta.workspace?.root, pid: spec.projectId, pins: pins.all.length,
           toast: [...document.querySelectorAll('.el-message')].map(m=>m.textContent.trim()).join(' | ') }})()`)
console.log('执行切换:', JSON.stringify(done))
await sleep(1500)
const { data } = await send('Page.captureScreenshot', { format: 'png' })
fs.writeFileSync(path.join(process.cwd(), 'docs', 'manual', 'shots', '31-workspace-switch.png'), Buffer.from(data, 'base64'))
console.log('saved 31-workspace-switch.png')
ws.close();proc.kill();process.exit(0)
