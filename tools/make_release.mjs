// Glyph 发布打包：git archive（干净源码树）+ dist 构建产物 → releases/glyph-<版本>.zip
//
// 用法（仓库根目录）:
//   node tools/make_release.mjs              # 先 npm run build 再打包
//   node tools/make_release.mjs --skip-build # dist 已是最新时直接打包
//
// 说明：dist/ 已不入库，所以 R-only 用户拿到的是发布包而不是克隆。
// 步骤：1) frontend 构建出 dist；2) git archive HEAD 导出干净源码（自动排除
// gitignore 的东西）；3) 拷入 dist；4) 平台原生 zip 压缩到 releases/。

import { spawnSync } from 'node:child_process'
import { cpSync, createWriteStream, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const SKIP_BUILD = process.argv.includes('--skip-build')

function run(cmd, args, opts = {}) {
  // 默认不走 shell：参数由 Node 精确转义（路径含空格也安全）；npm.cmd 这类批处理才需要 shell
  const r = spawnSync(cmd, args, { cwd: ROOT, stdio: 'inherit', ...opts })
  if (r.error) throw new Error(`${cmd} 启动失败：${r.error.message}`)
  if (r.status !== 0) throw new Error(`${cmd} ${args.join(' ')} 失败（exit ${r.status}）`)
}

// ---- 版本号：git describe（无 tag 时退回短 SHA）----
function version() {
  const r = spawnSync('git', ['describe', '--tags', '--always', '--dirty'], { cwd: ROOT, encoding: 'utf8' })
  return (r.stdout || 'dev').trim() || 'dev'
}

// ---- 1) 构建前端 ----
if (!SKIP_BUILD) {
  console.log('== 构建前端（frontend → ../dist）==')
  // npm 在 Windows 上是 .cmd 批处理，必须经 shell 启动
  run(process.platform === 'win32' ? 'npm.cmd' : 'npm', ['run', 'build'],
      { cwd: join(ROOT, 'frontend'), shell: process.platform === 'win32' })
}
if (!existsSync(join(ROOT, 'dist', 'index.html'))) {
  throw new Error('dist/index.html 不存在 —— 先构建（node tools/make_release.mjs 不带 --skip-build）')
}

// ---- 2) git archive 干净源码树 ----
const staging = mkdtempSync(join(tmpdir(), 'glyph-release-'))
try {
  console.log('== 导出干净源码树（git archive）==')
  const srcDir = join(staging, 'src')
  mkdirSync(srcDir)
  // 不用系统 tar 解 zip：Windows 上 PATH 里的 tar 常是 Git Bash 的 GNU tar（不支持 zip）。
  // win32 用 PowerShell Expand-Archive（Win10+ 自带），unix 用 tar 格式（原生 tar 即可）。
  if (process.platform === 'win32') {
    const archiveZip = join(staging, 'src.zip').replace(/\\/g, '/')
    run('git', ['archive', '--format=zip', '-o', archiveZip, 'HEAD'])
    run('powershell', ['-NoProfile', '-Command',
      `Expand-Archive -Path '${archiveZip}' -DestinationPath '${srcDir.replace(/\\/g, '/')}'`])
  } else {
    const archiveTar = join(staging, 'src.tar')
    run('git', ['archive', '--format=tar', '-o', archiveTar, 'HEAD'])
    run('tar', ['-xf', archiveTar, '-C', srcDir])
  }

  // ---- 3) 拷入构建产物 ----
  console.log('== 拷入 dist/ ==')
  cpSync(join(ROOT, 'dist'), join(staging, 'src', 'dist'), { recursive: true })

  // ---- 4) 压缩 ----
  const outDir = join(ROOT, 'releases')
  mkdirSync(outDir, { recursive: true })
  const out = join(outDir, `glyph-${version()}.zip`)
  console.log('== 压缩 →', out, '==')
  if (process.platform === 'win32') {
    run('powershell', ['-NoProfile', '-Command',
      `Compress-Archive -Path (Join-Path '${staging.replace(/'/g, "''")}' 'src\\*') -DestinationPath '${out.replace(/'/g, "''")}' -Force`])
  } else {
    // 从 staging 里打包 src 内容，使解压后直接得到仓库结构
    rmSync(join(staging, 'src.zip'), { force: true })
    run('zip', ['-r', '-q', out, '.'], { cwd: join(staging, 'src') })
  }
  console.log('完成:', out)
} finally {
  rmSync(staging, { recursive: true, force: true })
}
