// 单独验证插件宿主半：加载 → apply → 控制服务 + Glyph 进程
// 用法: node tools/test_host.mjs
// 成功标准: 打印「Glyph 就绪」后自动 stop + 退出（Ctrl+C 可随时中断）
import { apply } from '../plugin/lib/index.js'
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { join } from 'node:path'

apply({})
console.log('[test] plugin applied')

// apply() 内部会生成/读取 token 并写入 ~/.dsh/glyph-plugin.json —— 之后才读得到
let cfg = {}
try { cfg = JSON.parse(readFileSync(join(homedir(), '.dsh', 'glyph-plugin.json'), 'utf8')) } catch { /* 忽略 */ }
const PORT = cfg.port || process.env.GLYPH_PORT || 4399
const TOKEN = cfg.token || ''
const H = TOKEN ? { 'x-glyph-token': TOKEN } : {}

// 修复记录：旧版把 interval id 存进 globalThis.__t 却从不赋值，
// clearInterval 永远清不掉，进程永不退出
let stopping = false
let timer = setInterval(async () => {
  if (stopping) return
  try {
    const r = await fetch(`http://127.0.0.1:${PORT}/status`, { headers: H })
    const s = await r.json()
    console.log('[test] status:', JSON.stringify(s))
    if (s.running) {
      console.log('[test] Glyph 就绪:', s.url, '—— 停止 Glyph 并退出')
      try {
        await fetch(`http://127.0.0.1:${PORT}/stop`, { method: 'POST', headers: H })
      } catch { /* 忽略 */ }
      clearInterval(timer)
      // 不要立刻 process.exit：停止请求的响应可能还在飞，强退会触发 libuv 断言
      // （Assertion failed: !(handle->flags & UV_HANDLE_CLOSING)）。
      // 清掉定时器后事件循环会自然结束。
      stopping = true
      timer = null
    }
  } catch (e) {
    console.log('[test] 控制服务未就绪:', e.message)
  }
}, 3000)
