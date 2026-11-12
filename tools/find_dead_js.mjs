// 找前端里「没人引用」的组件与导出，输出候选供人工确认后再删
import { readdirSync, readFileSync, statSync } from 'node:fs'
import { join, basename, extname } from 'node:path'

const SRC = 'frontend/src'

function walk(dir, out = []) {
  for (const ent of readdirSync(dir)) {
    const p = join(dir, ent)
    const st = statSync(p)
    if (st.isDirectory()) walk(p, out)
    else if (/\.(vue|js)$/.test(ent)) out.push(p.replace(/\\/g, '/'))
  }
  return out
}

const files = walk(SRC)
const texts = new Map(files.map(f => [f, readFileSync(f, 'utf8')]))

// ---------- 1. 组件：有没有被 import ----------
console.log('=== 未被任何文件 import 的组件 ===')
let vueDead = 0
for (const f of files.filter(f => f.endsWith('.vue'))) {
  const name = basename(f, '.vue')
  // main.js 里可能全局注册；App.vue 是根
  if (name === 'App') continue
  const re = new RegExp(`['"\`][^'"\`]*/${name}\\.vue['"\`]|['"\`]\\./${name}\\.vue['"\`]|\\b${name}\\b`)
  let used = false
  for (const [g, t] of texts) {
    if (g === f) continue
    if (re.test(t)) { used = true; break }
  }
  if (!used) { console.log('  ' + f); vueDead++ }
}
console.log(`  小计: ${vueDead}`)

// ---------- 2. JS 导出：有没有被别处引用 ----------
console.log('\n=== 未被引用的 JS 导出 ===')
const exportRe = /^export\s+(?:async\s+)?(?:function|const|let|class)\s+([A-Za-z_$][\w$]*)/gm
let jsDead = 0
for (const f of files.filter(f => f.endsWith('.js'))) {
  const t = texts.get(f)
  let m
  while ((m = exportRe.exec(t))) {
    const nm = m[1]
    let used = false
    for (const [g, s] of texts) {
      if (g === f) continue
      if (new RegExp(`\\b${nm}\\b`).test(s)) { used = true; break }
    }
    if (!used) { console.log(`  ${f}: ${nm}`); jsDead++ }
  }
}
console.log(`  小计: ${jsDead}`)

// ---------- 3. store actions：定义了但没人 dispatch ----------
console.log('\n=== 疑似未使用的 store action ===')
let actDead = 0
for (const f of files.filter(f => /stores[\\/].*\.js$/.test(f))) {
  const t = texts.get(f)
  const actionsBlock = t.indexOf('actions:')
  if (actionsBlock < 0) continue
  const body = t.slice(actionsBlock)
  const actRe = /^\s{4}(?:async\s+)?([A-Za-z_$][\w$]*)\s*\(/gm
  let m
  while ((m = actRe.exec(body))) {
    const nm = m[1]
    if (['if', 'for', 'return', 'const'].includes(nm)) continue
    let used = false
    for (const [g, s] of texts) {
      if (g === f) continue
      if (new RegExp(`\\.${nm}\\s*\\(`).test(s)) { used = true; break }
    }
    // 同一 store 内部也可能互相调用
    const selfUses = (t.match(new RegExp(`this\\.${nm}\\s*\\(`, 'g')) || []).length
    if (!used && selfUses === 0) { console.log(`  ${f}: ${nm}`); actDead++ }
  }
}
console.log(`  小计: ${actDead}`)
