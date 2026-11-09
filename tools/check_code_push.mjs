// 验证：外部推送代码 → 前端轮询取走 → 切到「高级」→ 填入编辑器 →（可选）自动运行
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const APP = 'http://127.0.0.1:4321'
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9681
const PROFILE = path.join(process.env.TEMP, 'gg-push-' + Date.now())
const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`,'--headless=new','--disable-gpu','--hide-scrollbars','--no-first-run','--user-data-dir='+PROFILE,'--window-size=1600,900','about:blank'], { stdio: 'ignore' })
async function gt(){for(let i=0;i<60;i++){try{const l=await(await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();const p=l.find(x=>x.type==='page');if(p)return p}catch{}await sleep(250)}throw new Error('no cdp')}
const t=await gt();const ws=new WebSocket(t.webSocketDebuggerUrl)
let id=0;const pending=new Map()
ws.addEventListener('message',e=>{const m=JSON.parse(e.data);if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result)}})
await new Promise(r=>ws.addEventListener('open',r,{once:true}))
const send=(m,p={})=>{const i=++id;ws.send(JSON.stringify({id:i,method:m,params:p}));return new Promise((a,b)=>pending.set(i,{resolve:a,reject:b}))}
const ev=async x=>{const r=await send('Runtime.evaluate',{expression:x,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.text+' '+(r.exceptionDetails.exception?.description||''));return r.result.value}
const push = async (code, run) => {
  const r = await fetch(`${APP}/api/code/push`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ code, run })
  })
  return r.json()
}

await send('Page.enable');await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride',{width:1600,height:900,deviceScaleFactor:1,mobile:false})
await send('Page.navigate',{url:APP});await sleep(8000)

// 关闭可能出现的草稿提示
await ev(`(()=>{const d=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');if(d)d.click();return 1})()`)
await sleep(1000)

// 场景 1：只推送，不自动运行
const code1 = 'library(ggplot2)\np1 <- ggplot(mtcars, aes(wt, mpg, colour = factor(cyl))) + geom_point(size = 3)\np1'
console.log('推送 1:', JSON.stringify(await push(code1, false)))
await sleep(3500)
const s1 = await ev(`(async()=>{
  const pinia=document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
  const spec=pinia._s.get('spec'); const ui=pinia._s.get('ui');
  const cm=[...document.querySelectorAll('.gg-right .cm-content')].filter(c=>c.getBoundingClientRect().height>0)[0];
  return { tab: ui.tab, pending: spec.pendingCode, pendingRun: spec.pendingCodeRun,
           editorText: (cm?.textContent||'').slice(0,60), toast: [...document.querySelectorAll('.el-message')].map(m=>m.textContent.trim()).join('|') }})()`)
console.log('场景1(仅填充):', JSON.stringify(s1))

// 场景 2：推送并自动运行
const code2 = 'p2 <- ggplot(mtcars, aes(factor(cyl), mpg, fill = factor(cyl))) + geom_boxplot()\np2'
console.log('推送 2:', JSON.stringify(await push(code2, true)))
await sleep(8000)
const s2 = await ev(`(async()=>{
  const pinia=document.querySelector('#app').__vue_app__.config.globalProperties.$pinia;
  const spec=pinia._s.get('spec');
  const img=document.querySelector('.gg-canvas-img');
  return { renderedFromCode: !!spec.last.renderedFromCode, ok: spec.last.ok,
           err: spec.last.error?String(spec.last.error).slice(0,80):null,
           hasImg: !!img, naturalW: img?img.naturalWidth:0,
           codeHead: (spec.last.code||'').slice(0,40) }})()`)
console.log('场景2(自动运行):', JSON.stringify(s2))

const { data } = await send('Page.captureScreenshot', { format: 'png' })
fs.writeFileSync(path.join(process.cwd(), 'docs', 'manual', 'shots', '32-code-push.png'), Buffer.from(data, 'base64'))
console.log('saved 32-code-push.png')
ws.close();proc.kill();process.exit(0)
