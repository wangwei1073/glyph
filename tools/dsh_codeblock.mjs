// 检查聊天渲染器里代码块的结构与可扩展性
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

const target = files.find(f => /dsh-client-ui-chat\/lib\/client\.js$/.test(f.path))
const code = read(target)
console.log('chat client.js 大小:', target.size)

// 找代码块相关标识
for (const kw of ['CodeBlock', 'codeBlock', 'copy', 'language', 'highlight', 'shiki', 'prism', 'slot']) {
  const n = [...code.matchAll(new RegExp(kw, 'g'))].length
  console.log(`  ${kw}: ${n}`)
}

// 打印 CodeBlock 组件附近代码
const i = code.indexOf('CodeBlock')
if (i >= 0) {
  console.log('\n=== CodeBlock 附近 ===')
  console.log(code.slice(Math.max(0, i - 400), i + 900))
}
