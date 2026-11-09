// 验证：工作区感知的前端（projectId 跟随目录、项目菜单有切换入口、图库来自目录）
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import path from 'node:path'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9671
const PROFILE = path.join(process.env.TEMP, 'gg-ws-' + Date.now())
const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`,'--headless=new','--disable-gpu','--hide-scrollbars','--no-first-run','--user-data-dir='+PROFILE,'--window-size=1600,900','about:blank'], { stdio: 'ignore' })
async function gt(){for(let i=0;i<60;i++){try{const l=await(await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();const p=l.find(x=>x.type==='page');if(p)return p}catch{}await sleep(250)}throw new Error('no cdp')}
const t=await gt();const ws=new WebSocket(t.webSocketDebuggerUrl)
let id=0;const pending=new Map()
ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result)}})
await new Promise(r=>ws.addEventListener('open',r,{once:true}))
const send=(m,p={})=>{const i=++id;ws.send(JSON.stringify({id:i,method:m,params:p}));return new Promise((a,b)=>pending.set(i,{resolve:a,reject:b}))}
const ev=async x=>{const r=await send('Runtime.evaluate',{expression:x,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.text+' '+(r.exceptionDetails.exception?.description||''));return r.result.value}
await send('Page.enable');await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride',{width:1600,height:900,deviceScaleFactor:1,mobile:false})
await send('Page.navigate',{url:'http://127.0.0.1:4321'});await sleep(8000)

const r = await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const drop=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');
  if(drop){drop.click();await w(1200)}
  const pinia = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
  const meta = pinia._s.get('meta');
  const spec = pinia._s.get('spec');
  // 打开「项目」下拉，读菜单项
  const projBtn=[...document.querySelectorAll('.act-actions button')].find(b=>(b.textContent||'').includes('项目'));
  if(projBtn){projBtn.click(); await w(1200)}
  const items=[...document.querySelectorAll('.el-dropdown-menu__item')].map(i=>(i.textContent||'').trim()).filter(Boolean);
  return {
    workspace: meta.workspace,
    projectId: spec.projectId,
    projectIdMatchesWorkspace: !!(meta.workspace && meta.workspace.id === spec.projectId),
    menuItems: items
  }})()`)
console.log(JSON.stringify(r, null, 1))

// 图库是否来自工作区
const g = await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const rails=[...document.querySelectorAll('.rail-btn')].filter(b=>!b.classList.contains('rail-collapse'));
  const labels=rails.map(b=>b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2500);
  const cards=[...document.querySelectorAll('.pin-card')].filter(c=>c.getBoundingClientRect().height>0);
  return { count: cards.length, names: cards.map(c=>(c.querySelector('.pc-name')?.textContent||'').trim()) }})()`)
console.log('图库:', JSON.stringify(g))
ws.close();proc.kill();process.exit(0)
