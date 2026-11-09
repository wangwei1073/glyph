// 单独验证插件宿主半：加载 → apply → 控制服务 + Glyph 进程
import { apply } from '../plugin/lib/index.js'

apply({})
console.log('[test] plugin applied')

// 保持进程存活，并定期打印状态
setInterval(async () => {
  try {
    const r = await fetch('http://127.0.0.1:4399/status')
    const s = await r.json()
    console.log('[test] status:', JSON.stringify(s))
    if (s.running) {
      console.log('[test] Glyph 就绪:', s.url)
      clearInterval(globalThis.__t)
    }
  } catch (e) {
    console.log('[test] 控制服务未就绪:', e.message)
  }
}, 3000)
