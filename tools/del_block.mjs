// 按名字安全删除一个 { ... } 块（方法 / 函数），靠括号配平判断结束位置。
// 用法: node tools/del_block.mjs <file> <signatureRegex>
import { readFileSync, writeFileSync } from 'node:fs'

const [file, sigPattern] = process.argv.slice(2)
if (!file || !sigPattern) {
  console.error('用法: node tools/del_block.mjs <file> <signatureRegex>')
  process.exit(1)
}

const src = readFileSync(file, 'utf8')
const lines = src.split(/\r?\n/)
const re = new RegExp(sigPattern)

let start = -1
for (let i = 0; i < lines.length; i++) {
  if (re.test(lines[i])) { start = i; break }
}
if (start < 0) { console.error('未找到签名:', sigPattern); process.exit(2) }

// 从签名行开始做花括号配平（忽略字符串里的括号：这里代码风格简单，够用）
let depth = 0
let end = -1
let seenOpen = false
for (let i = start; i < lines.length; i++) {
  for (const ch of lines[i]) {
    if (ch === '{') { depth++; seenOpen = true }
    else if (ch === '}') depth--
  }
  if (seenOpen && depth === 0) { end = i; break }
}
if (end < 0) { console.error('花括号未配平'); process.exit(3) }

// 若结束行只有 "}," 则整体一起删；否则删到 end
let endLine = end
if (/^\s*\},\s*$/.test(lines[end]) && /^\s*$/.test(lines[end]) === false) endLine = end

// 连带删除紧邻其上的注释行
let from = start
while (from > 0 && /^\s*(\/\/|\*|\/\*)/.test(lines[from - 1])) from--

const removed = endLine - from + 1
const out = [...lines.slice(0, from), ...lines.slice(endLine + 1)]
writeFileSync(file, out.join('\n'), 'utf8')
console.log(`${file}: 删除 ${removed} 行（${from + 1}-${endLine + 1}），剩余 ${out.length} 行`)
