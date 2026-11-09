import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9633
const OUT = path.join(process.cwd(), 'docs', 'manual', 'shots')
const PROFILE = path.join(process.env.TEMP, 'gg-codetheme2-' + Date.now())
const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`,'--headless=new','--disable-gpu','--hide-scrollbars','--no-first-run','--user-data-dir='+PROFILE,'--window-size=1600,900','about:blank'], { stdio: 'ignore' })
async function gt(){for(let i=0;i<60;i++){try{const l=await(await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();const p=l.find(x=>x.type==='page');if(p)return p}catch{}await sleep(250)}throw new Error('no cdp')}
const t=await gt();const ws=new WebSocket(t.webSocketDebuggerUrl);let id=0;const pending=new Map()
ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result)}})
await new Promise(r=>ws.addEventListener('open',r,{once:true}))
const send=(m,p={})=>{const i=++id;ws.send(JSON.stringify({id:i,method:m,params:p}));return new Promise((a,b)=>pending.set(i,{resolve:a,reject:b}))}
const ev=async x=>{const r=await send('Runtime.evaluate',{expression:x,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.text+' '+(r.exceptionDetails.exception?.description||''));return r.result.value}
await send('Page.enable');await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride',{width:1600,height:900,deviceScaleFactor:1,mobile:false})
await send('Page.navigate',{url:'http://127.0.0.1:4321'});await sleep(7000)
const r = await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const drop=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');
  if(drop){drop.click();await w(1200)}
  const rails=[...document.querySelectorAll('.rail-btn')].filter(b=>!b.classList.contains('rail-collapse'));
  const labels=rails.map(b=>b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2200);
  const card=[...document.querySelectorAll('.pin-card.code')].filter(c=>c.getBoundingClientRect().height>0)[0];
  if(!card) return {err:'no code card'};
  card.click(); await w(4000);
  const st=document.querySelector('#app').__vue_app__.config.globalProperties.$pinia._s.get('spec');
  const before={fromCode:!!st.last.renderedFromCode, naturalW:document.querySelector('.gg-canvas-img')?.naturalWidth||0};
  // 用 UI 改主题：切到主题页签，打开基础主题下拉选「黑白 theme_bw」
  rails[labels.indexOf('主题')].click(); await w(1800);
  const sel=[...document.querySelectorAll('.gg-right .el-select')][0];
  if(sel){sel.querySelector('input').click();await w(1200);
    const opt=[...document.querySelectorAll('.el-select-dropdown__item')].find(o=>(o.textContent||'').includes('theme_bw'));
    if(opt){opt.click()}}
  await w(6000);
  const img=document.querySelector('.gg-canvas-img');
  return {before, after:{fromCode:!!st.last.renderedFromCode, ok:st.last.ok,
    err:st.last.error?String(st.last.error).slice(0,80):null,
    naturalW:img?img.naturalWidth:0, hasImg:!!img,
    badge:document.querySelector('.head-code-tag')?.textContent?.trim()||null,
    themeBase:st.spec.theme.base}}})()`)
console.log(JSON.stringify(r, null, 0))
await sleep(1000)
const {data}=await send('Page.captureScreenshot',{format:'png'})
fs.writeFileSync(path.join(OUT,'29-code-image-theme.png'),Buffer.from(data,'base64'))
console.log('saved 29-code-image-theme.png')
ws.close();proc.kill();process.exit(0)
