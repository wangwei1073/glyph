// 在 app.asar 内定向检索：列出各客户端插件注册的 slot 名称与关键 API
import fs from 'node:fs'

const ASAR = 'D:\\DeepSeek Harness\\resources\\app.asar'
const buf = fs.readFileSync(ASAR)
const jsonLen = buf.readUInt32LE(12)
const header = JSON.parse(buf.slice(16, 16 + jsonLen).toString('utf8'))
const dataStart = 16 + jsonLen
const base = dataStart + ((4 - (dataStart % 4)) % 4)

const files = []
function walk(node, prefix) {
  for (const [k, v] of Object.entries(node.files || {})) {
    const full = prefix + '/' + k
    if (v.files) walk(v, full)
    else files.push({ path: full, size: Number(v.size), offset: Number(v.offset) })
  }
}
walk(header, '')

const read = (f) => buf.slice(base + f.offset, base + f.offset + f.size).toString('utf8')

// 只看客户端 UI 插件的 client.js
const uiFiles = files.filter(f => /@deepseek-ai\/dsh-client-ui-[^/]+\/lib\/client\.js$/.test(f.path))
console.log('客户端 UI 插件数:', uiFiles.length)

const slotNames = new Map()
for (const f of uiFiles) {
  const code = read(f)
  for (const m of code.matchAll(/slots\.register\(\s*\{\s*name:\s*["']([^"']+)["']/g)) {
    const n = m[1]
    if (!slotNames.has(n)) slotNames.set(n, new Set())
    slotNames.get(n).add(f.path.match(/dsh-client-ui-([^/]+)/)[1])
  }
  // 另一种写法：name 在 set 之前
  for (const m of code.matchAll(/name:\s*["']([a-z][a-z0-9.]*\.[a-z0-9.]+)["']/g)) {
    const n = m[1]
    if (!n.includes('.')) continue
    if (!slotNames.has(n)) slotNames.set(n, new Set())
    slotNames.get(n).add(f.path.match(/dsh-client-ui-([^/]+)/)[1])
  }
}
console.log('\n可用的 slot 名称（按名称排序）:')
for (const [n, owners] of [...slotNames].sort((a, b) => a[0].localeCompare(b[0]))) {
  console.log(`  ${n.padEnd(42)} ← ${[...owners].slice(0, 3).join(', ')}`)
}
