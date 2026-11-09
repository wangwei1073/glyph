// 采集用户手册所需截图：一个会话内按「选数据 → 加图层 → 逐页签」推进
import { spawn } from 'node:child_process'
import { setTimeout as sleep } from 'node:timers/promises'
import fs from 'node:fs'
import path from 'node:path'

const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe'
const PORT = 9520
const URL_ = process.env.APP_URL || 'http://127.0.0.1:4321'
const OUT = path.join(process.cwd(), 'docs', 'manual', 'shots')
fs.mkdirSync(OUT, { recursive: true })

// 每次用全新的浏览器配置：否则 localStorage 里的页签 / 草稿会串进截图
const PROFILE = path.join(process.env.TEMP, 'gg-manual-' + Date.now())
const proc = spawn(EDGE, [
  `--remote-debugging-port=${PORT}`, '--headless=new', '--disable-gpu', '--hide-scrollbars',
  '--no-first-run', '--force-device-scale-factor=1',
  '--user-data-dir=' + PROFILE,
  '--window-size=1600,900', 'about:blank'
], { stdio: 'ignore' })

async function gt() {
  for (let i = 0; i < 60; i++) {
    try { const l = await (await fetch(`http://127.0.0.1:${PORT}/json/list`)).json(); const p = l.find(x => x.type === 'page'); if (p) return p } catch {}
    await sleep(250)
  }
  throw new Error('no cdp')
}
const t = await gt()
const ws = new WebSocket(t.webSocketDebuggerUrl)
let id = 0; const pending = new Map()
ws.addEventListener('message', e => {
  const m = JSON.parse(e.data)
  if (m.id && pending.has(m.id)) {
    const p = pending.get(m.id); pending.delete(m.id)
    m.error ? p.reject(new Error(JSON.stringify(m.error))) : p.resolve(m.result)
  }
})
await new Promise(r => ws.addEventListener('open', r, { once: true }))
const send = (m, p = {}) => { const i = ++id; ws.send(JSON.stringify({ id: i, method: m, params: p })); return new Promise((a, b) => pending.set(i, { resolve: a, reject: b })) }
const ev = async (x) => {
  const r = await send('Runtime.evaluate', { expression: x, awaitPromise: true, returnByValue: true })
  if (r.exceptionDetails) throw new Error(r.exceptionDetails.text + ' ' + (r.exceptionDetails.exception?.description || ''))
  return r.result.value
}

async function shot(name, clip) {
  const params = { format: 'png' }
  if (clip) params.clip = { ...clip, scale: 1 }
  const { data } = await send('Page.captureScreenshot', params)
  fs.writeFileSync(path.join(OUT, name), Buffer.from(data, 'base64'))
  console.log('  ✓', name)
}

// 取区域盒子（CSS 像素）
const box = (sel) => ev(`(() => {
  const el = document.querySelector(${JSON.stringify(sel)});
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return { x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) };
})()`)

await send('Page.enable'); await send('Runtime.enable')
await send('Emulation.setDeviceMetricsOverride', { width: 1600, height: 900, deviceScaleFactor: 1, mobile: false })
await send('Page.navigate', { url: URL_ })
await sleep(7000)

// 关掉可能弹出的草稿恢复提示
await ev(`(() => {
  const btns = [...document.querySelectorAll('.el-message-box__btns button')];
  const cancel = btns.find(b => /不|否|取消|丢弃/.test(b.textContent || ''));
  if (cancel) cancel.click();
  return 1;
})()`)
await sleep(800)

// 顶部「发现上次未保存的草稿」横幅：点「丢弃」，避免出现在截图里
await ev(`(() => {
  const spans = [...document.querySelectorAll('span, button')];
  const drop = spans.find(b => (b.textContent || '').trim() === '丢弃');
  if (drop) drop.click();
  return 1;
})()`)
await sleep(1200)

// 统一从「图层」页签开始，避免继承任何残留状态
await ev(`(() => {
  const store = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia._s.get('ui');
  if (store) { store.tab = 'layers'; store.statsOpen = false; }
  return 1;
})()`)
await sleep(600)

console.log('1. 总览（空状态）')
await shot('01-overview.png')

// 2. 选择内置数据集
console.log('2. 选择数据集')
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const sel = document.querySelector('.src-select input, .el-select input');
  if (sel) { sel.click(); await w(900);
    const o = [...document.querySelectorAll('.el-select-dropdown__item')].find(x => x.textContent.includes('汽车油耗'));
    if (o) { o.click(); await w(3000); } }
  return 1;
})()`)
await sleep(2500)
const leftBox = await box('.gg-left')
await shot('02-dataset.png', leftBox)

// 3. 添加第一个图层
console.log('3. 添加图层')
await ev(`(async () => {
  const b = [...document.querySelectorAll('button')].find(x => x.textContent.includes('添加第一个图层'));
  if (b) b.click();
  return 1;
})()`)
await sleep(6000)
// 默认自动猜的映射（displ × year）不适合做示例：显式改成「排量 × 高速油耗」的散点
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const store = document.querySelector('#app').__vue_app__.config.globalProperties.$pinia._s.get('spec');
  const L = store.spec.layers[0];
  L.aes = { x: { map: 'displ' }, y: { map: 'hwy' } };
  store.renderNow();
  await w(5000);
  return 1;
})()`)
await sleep(1500)
await shot('03-first-chart.png')

// 4~11. 逐个页签（截右栏）
const panels = [
  ['图层', '04-panel-layers.png'],
  ['美学', '05-panel-aes.png'],
  ['参数', '06-panel-params.png'],
  ['标度', '07-panel-scale.png'],
  ['坐标', '08-panel-coord.png'],
  ['标签', '09-panel-labs.png'],
  ['注释', '10-panel-annot.png'],
  ['主题', '11-panel-theme.png']
]
for (const [label, file] of panels) {
  console.log(`4. 页签 ${label}`)
  await ev(`(async () => {
    const w = (ms) => new Promise(r => setTimeout(r, ms));
    const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
    const hit = rails.find(b => b.innerText.trim() === ${JSON.stringify(label)});
    if (hit) hit.click();
    await w(900);
    return 1;
  })()`)
  await sleep(900)
  const rb = await box('.gg-right')
  await shot(file, rb)
}

// 12. 图库
console.log('5. 图库')
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const hit = rails.find(b => b.innerText.trim() === '图库');
  if (hit) hit.click();
  await w(2200);
  return 1;
})()`)
await sleep(1200)
await shot('12-gallery.png', await box('.gg-right'))

// 13. 拼图
console.log('6. 拼图')
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const hit = rails.find(b => b.innerText.trim() === '拼图');
  if (hit) hit.click();
  await w(1500);
  return 1;
})()`)
await sleep(1200)
await shot('13-patchwork.png', await box('.gg-right'))

// 14. 代码视图
console.log('7. 代码视图')
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const tab = [...document.querySelectorAll('.el-radio-button')].find(b => b.textContent.includes('代码'));
  if (tab) tab.click();
  await w(1800);
  return 1;
})()`)
await sleep(1500)
await shot('14-code-view.png')

// 15. 代码补全（高级页 + geom_ 触发）
console.log('8. 代码补全')
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const hit = rails.find(b => b.innerText.trim() === '高级');
  if (hit) hit.click();
  await w(2500);
  const tab = [...document.querySelectorAll('.el-radio-button')].find(b => b.textContent.includes('图表'));
  const cm = [...document.querySelectorAll('.gg-right .cm-content')].filter(c => c.getBoundingClientRect().height > 0)[0];
  if (cm) {
    cm.focus();
    await w(300);
    document.execCommand('insertText', false, 'theme_');
  }
  await w(1800);
  return 1;
})()`)
await sleep(1500)
await shot('15-completion.png', await box('.gg-right'))


// ---- 收尾：切回图表视图与「图层」页签，保证后续截图状态一致 ----
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const tab = [...document.querySelectorAll('.el-radio-button')].find(b => b.textContent.includes('图表'));
  if (tab) tab.click();
  await w(600);
  const rails = [...document.querySelectorAll('.rail-btn')].filter(b => !b.classList.contains('rail-collapse'));
  const hit = rails.find(b => b.innerText.trim() === '图层');
  if (hit) hit.click();
  await w(1200);
  return 1;
})()`)
await sleep(1500)

// 16. 数据统计（真的算一次，让截图里有结果）
console.log('9. 数据统计')
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const t = document.querySelector('.sd-toggle');
  if (t) t.click();
  await w(1800);
  const calc = [...document.querySelectorAll('button')].find(b => (b.textContent || '').includes('计算'));
  if (calc) calc.click();
  await w(3500);
  return 1;
})()`)
await sleep(2500)
const statsBox = await box('.stats-drawer')
await shot('16-stats.png', statsBox || undefined)

// 关掉统计抽屉，避免挡住导出弹层
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const t = document.querySelector('.sd-toggle');
  if (t) t.click();
  await w(1000);
  return 1;
})()`)
await sleep(1200)

// 17. 导出 → 导出前检查
console.log('10. 导出前检查')
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const btn = [...document.querySelectorAll('button')].find(b => (b.textContent || '').trim().includes('导出'));
  if (btn) btn.click();
  await w(1500);
  // 出现在下拉/弹层里的导出项
  const items = [...document.querySelectorAll('.el-dropdown-menu__item, .el-popover button, .el-dialog button')];
  const png = items.find(b => /PNG/i.test(b.textContent || ''));
  if (png) png.click();
  await w(3500);
  return 1;
})()`)
await sleep(2500)
await shot('17-export-check.png')

// 关掉检查弹层
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const btn = [...document.querySelectorAll('.el-dialog__headerbtn, .el-message-box__headerbtn')].pop();
  if (btn) btn.click();
  await w(1200);
  return 1;
})()`)
await sleep(1200)

// 18. 数据准备弹窗
console.log('11. 数据准备')
await ev(`(async () => {
  const w = (ms) => new Promise(r => setTimeout(r, ms));
  const btn = [...document.querySelectorAll('button')].find(b => (b.textContent || '').includes('数据准备'));
  if (btn) btn.click();
  await w(2500);
  return 1;
})()`)
await sleep(2000)
const prepBox = await box('.el-dialog')
await shot('18-data-prep.png', prepBox || undefined)

console.log('完成')
ws.close(); proc.kill(); process.exit(0)
