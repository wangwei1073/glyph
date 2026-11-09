// 验证：代码图状态下从 UI 导出/检查，请求体里带上了 code
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import path from 'node:path'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9661
const PROFILE = path.join(process.env.TEMP, 'gg-exp2-' + Date.now())
const proc = spawn(EDGE, [`--remote-debugging-port=${PORT}`,'--headless=new','--disable-gpu','--hide-scrollbars','--no-first-run','--user-data-dir='+PROFILE,'--window-size=1600,900','about:blank'], { stdio: 'ignore' })
async function gt(){for(let i=0;i<60;i++){try{const l=await(await fetch(`http://127.0.0.1:${PORT}/json/list`)).json();const p=l.find(x=>x.type==='page');if(p)return p}catch{}await sleep(250)}throw new Error('no cdp')}
const t=await gt();const ws=new WebSocket(t.webSocketDebuggerUrl)
let id=0;const pending=new Map();const reqs=[]
ws.addEventListener('message',e=>{
  const m=JSON.parse(e.data)
  if (m.method === 'Network.requestWillBeSent') {
    const u = m.params.request.url || ''
    if (u.includes('/api/export') || u.includes('/api/bundle')) {
      const pd = m.params.request.postData || ''
      reqs.push({ url: u.replace('http://127.0.0.1:4321',''), hasCode: pd.includes('"code"'), codeLen: (() => { try { return (JSON.parse(pd).code || '').length } catch { return -1 } })(), layers: (() => { try { return (JSON.parse(pd).spec?.layers || []).length } catch { return -1 } })() })
    }
  }
  if(m.id&&pending.has(m.id)){const p=pending.get(m.id);pending.delete(m.id);m.error?p.reject(new Error(JSON.stringify(m.error))):p.resolve(m.result)}
})
await new Promise(r=>ws.addEventListener('open',r,{once:true}))
const send=(m,p={})=>{const i=++id;ws.send(JSON.stringify({id:i,method:m,params:p}));return new Promise((a,b)=>pending.set(i,{resolve:a,reject:b}))}
const ev=async x=>{const r=await send('Runtime.evaluate',{expression:x,awaitPromise:true,returnByValue:true});if(r.exceptionDetails)throw new Error(r.exceptionDetails.text+' '+(r.exceptionDetails.exception?.description||''));return r.result.value}
await send('Page.enable');await send('Runtime.enable');await send('Network.enable')
await send('Emulation.setDeviceMetricsOverride',{width:1600,height:900,deviceScaleFactor:1,mobile:false})
await send('Page.navigate',{url:'http://127.0.0.1:4321'});await sleep(7000)

// 打开代码图，然后点导出（会先弹导出检查，再点仍然导出）
const click = await ev(`(async()=>{
  const w=(ms)=>new Promise(r=>setTimeout(r,ms));
  const drop=[...document.querySelectorAll('span,button')].find(b=>(b.textContent||'').trim()==='丢弃');
  if(drop){drop.click();await w(1200)}
  const rails=[...document.querySelectorAll('.rail-btn')].filter(b=>!b.classList.contains('rail-collapse'));
  const labels=rails.map(b=>b.innerText.trim());
  rails[labels.indexOf('图库')].click(); await w(2200);
  const card=[...document.querySelectorAll('.pin-card.code')].filter(c=>c.getBoundingClientRect().height>0)[0];
  if(!card) return {err:'no code card'};
  card.click(); await w(4500);
  const st=document.querySelector('#app').__vue_app__.config.globalProperties.$pinia._s.get('spec');
  // 点底栏「导出」（主按钮）
  const btn=[...document.querySelectorAll('.gg-footer button')].find(b=>(b.textContent||'').includes('导出'));
  if(!btn) return {err:'no export button'};
  btn.click(); await w(2500);
  // 导出前检查弹层：点「仍然导出 PNG」
  const again=[...document.querySelectorAll('.el-dialog button, .el-message-box button')].find(b=>(b.textContent||'').includes('仍然导出'));
  if(again){again.click(); await w(6000)}
  return {fromCode:!!st.last.renderedFromCode, codeLen:(st.last.code||'').length, layers:st.spec.layers.length, clickedAgain:!!again}})()`)
console.log('UI 操作:', JSON.stringify(click))
await sleep(3500)
console.log('导出的请求:', JSON.stringify(reqs, null, 1))
ws.close();proc.kill();process.exit(0)
