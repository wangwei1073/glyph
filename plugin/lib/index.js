// Glyph DSH 插件 —— 宿主半（Node）
//
// 职责：
//   1. 管理 Glyph 的 R 服务进程（启动 / 健康检查 / 退出 / 心跳）
//   2. 起一个本地控制服务，供浏览器半调用（start / stop / status / push）
//
// 为什么要有控制服务：
//   浏览器半无法启动进程，而 Glyph 是一个常驻的 R 进程，
//   两者需要一个通道。用本地 HTTP 最简单，也便于外部调试（curl）。
//
// 安全模型（重要）：
//   控制服务只绑 127.0.0.1，且所有路由要求 x-glyph-token 头。
//   token 由宿主生成一次、持久化在配置文件里，并在启动时回写进 lib/client.js
//   （浏览器半没有文件系统权限，只能靠宿主改写源文件把 token 交到它手里；
//   token 绝不经 HTTP 提供，因此被 CORS 放行的来源也拿不到它）。
//   CORS 只对非公网来源放行（file:// 的 null、127.0.0.1/localhost、配置允许的来源）：
//   公网页面既读不到响应、POST 预检也会被拒 —— 用户浏览任意网页都无法驱动本服务。
//   若 client.js 无法回写（只读安装目录等），则放弃 token 校验、退回纯 CORS 白名单。
//
// 配置（环境变量，都有默认值）：
//   GLYPH_HOME      Glyph 安装目录     默认自动探测
//   GLYPH_RSCRIPT   Rscript 可执行文件  默认自动探测
//   GLYPH_PORT      控制服务端口        默认 4399
//   GLYPH_DATADIR   项目目录（数据存放） 默认取 DSH 工作区，再退回 process.cwd()
//   配置文件 ~/.dsh/glyph-plugin.json 还支持 token（自动生成，勿手填）与
//   allowedOrigins（额外放行的 CORS 来源数组，仅当 DSH 渲染层不是 file:// 时才需要）

import { spawn, execFileSync } from 'node:child_process'
import { createServer } from 'node:http'
import { existsSync, readFileSync, writeFileSync, readdirSync } from 'node:fs'
import { createServer as createNetServer } from 'node:net'
import { randomUUID } from 'node:crypto'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

// ---- 配置 ----
// 优先级：环境变量 > 配置文件 > 自动探测
// 配置文件：~/.dsh/glyph-plugin.json  { "glyphHome": "...", "rscript": "...", "port": 4399, "appPort": 4321 }
const CONFIG_FILE = join(homedir(), '.dsh', 'glyph-plugin.json')
const PLUGIN_DIR = dirname(dirname(fileURLToPath(import.meta.url)))

function readConfigFile() {
  try {
    const obj = JSON.parse(readFileSync(CONFIG_FILE, 'utf8'))
    return (obj && typeof obj === 'object') ? obj : {}
  } catch { return {} }
}

/** 在若干候选位置里找 Rscript.exe */
function detectRscript() {
  // 1) PATH 里能直接找到
  try {
    const out = execFileSync(process.platform === 'win32' ? 'where' : 'which',
      ['Rscript'], { encoding: 'utf8', timeout: 4000 })
    const first = out.split(/\r?\n/).map(s => s.trim()).filter(Boolean)[0]
    if (first && existsSync(first)) return first
  } catch { /* 继续 */ }
  // 2) 常见安装目录
  const roots = [
    'C:/Program Files/R', 'C:/Program Files (x86)/R',
    'D:/R', 'E:/R', '/usr/lib/R', '/usr/local/lib/R', '/Library/Frameworks/R.framework/Resources'
  ]
  for (const root of roots) {
    if (!existsSync(root)) continue
    let entries = []
    try { entries = readdirSync(root).sort().reverse() } catch { continue }
    for (const e of entries) {
      const cands = [
        join(root, e, 'bin', 'x64', 'Rscript.exe'),
        join(root, e, 'bin', 'Rscript.exe'),
        join(root, e, 'bin', 'Rscript')
      ]
      for (const c of cands) if (existsSync(c)) return c
    }
    const direct = join(root, 'bin', 'Rscript')
    if (existsSync(direct)) return direct
  }
  return ''
}

/** 在若干候选位置里找 Glyph 的 run.R */
function detectHome() {
  const cands = [
    process.env.GLYPH_HOME || '',
    // 插件放在仓库内部时的常见布局：<repo>/plugin/lib/index.js
    join(PLUGIN_DIR, '..', '..'),
    join(PLUGIN_DIR, '..'),
    join(homedir(), 'ggplot-gui'),
    join(homedir(), 'Documents', 'ggplot-gui')
  ]
  for (const c of cands) {
    if (!c) continue
    try { if (existsSync(join(c, 'run.R'))) return c.replace(/\\/g, '/') } catch { /* 忽略 */ }
  }
  return ''
}

function loadConfig() {
  const f = readConfigFile()
  return {
    home: process.env.GLYPH_HOME || f.glyphHome || detectHome(),
    rscript: process.env.GLYPH_RSCRIPT || f.rscript || detectRscript(),
    controlPort: Number(process.env.GLYPH_PORT || f.port || 4399),
    glyphPort: Number(process.env.GLYPH_APP_PORT || f.appPort || 4321),
    dataDir: process.env.GLYPH_DATADIR || f.dataDir || ''
  }
}

const DEFAULTS = loadConfig()

// ---- token（控制服务的访问凭证）----
// 生成一次、持久化到配置文件；启动时回写进 client.js（见 syncClientFile）。
function ensureToken() {
  const f = readConfigFile()
  if (typeof f.token === 'string' && f.token) return f.token
  const t = randomUUID()
  try {
    writeFileSync(CONFIG_FILE, JSON.stringify({ ...f, token: t }, null, 2), 'utf8')
  } catch { /* 写不进则每次启动生成新的；client 回写也会失败，最终自动放弃 token 校验 */ }
  return t
}

/** 把控制端口 / token 回写进 lib/client.js（浏览器半从同一目录加载它）。 */
function syncClientFile(token, controlPort) {
  try {
    const file = join(dirname(fileURLToPath(import.meta.url)), 'client.js')
    const src = readFileSync(file, 'utf8')
    const next = src
      .replace(/^(\s*)const CONTROL_PORT = \d+.*$/m, `$1const CONTROL_PORT = ${controlPort}`)
      .replace(/^(\s*)const GLYPH_TOKEN = '[^']*'.*$/m, `$1const GLYPH_TOKEN = '${token}'`)
    // 占位行没匹配到 → client.js 版本与宿主不一致，不能保证客户端带 token
    if (next === src) return false
    writeFileSync(file, next, 'utf8')
    return true
  } catch { return false }
}

// 记住上次选的项目目录（只在用户显式指定过之后才写）
const WS_FILE = join(homedir(), '.dsh', 'glyph-workspace.txt')

// 浏览器半的调试日志：客户端把加载/报错写回宿主，方便在没有开发者工具时定位问题
const CLIENT_LOG = join(homedir(), '.dsh', 'glyph-client.log')

function appendClientLog(obj) {
  try {
    const line = JSON.stringify({ at: new Date().toISOString(), ...obj }) + '\n'
    writeFileSync(CLIENT_LOG, line, { flag: 'a' })
  } catch { /* 忽略 */ }
}

function readClientLog(limit) {
  try {
    const txt = readFileSync(CLIENT_LOG, 'utf8')
    return txt.split('\n').filter(Boolean).slice(-limit).join('\n')
  } catch {
    return ''
  }
}

function loadSavedDir() {
  try {
    const d = readFileSync(WS_FILE, 'utf8').trim()
    return d || ''
  } catch { return '' }
}

function saveDir(dir) {
  try { writeFileSync(WS_FILE, dir, 'utf8') } catch { /* 忽略 */ }
}

// ---- 运行时状态（模块级：一个 DSH 进程只有一个 Glyph 实例）----
const state = {
  child: null,        // R 进程
  port: 0,            // Glyph 端口
  starting: false,
  lastError: '',
  workspace: '',      // 当前项目目录
  controlPort: DEFAULTS.controlPort,
  server: null,
  token: '',          // 控制服务访问凭证；空串表示未启用校验（client.js 回写失败时）
  hbTimer: null       // 心跳定时器（宿主 → Glyph /api/heartbeat）
}

/** 挑一个空闲端口，避免和用户自己的 Glyph 实例冲突。 */
function freePort() {
  return new Promise((resolve, reject) => {
    const srv = createNetServer()
    srv.unref()
    srv.on('error', reject)
    srv.listen(0, '127.0.0.1', () => {
      const p = srv.address().port
      srv.close(() => resolve(p))
    })
  })
}

/** 指定端口可用就用它，否则退回随机空闲端口。 */
async function pickPort() {
  const want = DEFAULTS.glyphPort
  if (!want) return freePort()
  const ok = await new Promise((resolve) => {
    const srv = createNetServer()
    srv.once('error', () => resolve(false))
    srv.listen(want, '127.0.0.1', () => srv.close(() => resolve(true)))
  })
  return ok ? want : freePort()
}

/** 轮询 /api/meta，直到服务就绪或超时。 */
async function waitReady(port, timeoutMs = 45000) {
  const t0 = Date.now()
  while (Date.now() - t0 < timeoutMs) {
    try {
      const r = await fetch(`http://127.0.0.1:${port}/api/meta`, { signal: AbortSignal.timeout(2000) })
      if (r.ok) return true
    } catch { /* 还没起来 */ }
    await new Promise(r => setTimeout(r, 500))
  }
  return false
}

/** 启动 Glyph R 服务。已运行则直接返回。 */
async function start(dir) {
  if (state.child && state.port && (!dir || dir === state.workspace)) return status()
  if (state.starting) {
    // 并发调用：等它起来
    for (let i = 0; i < 90; i++) {
      await new Promise(r => setTimeout(r, 500))
      if (!state.starting) break
    }
    return status()
  }
  state.starting = true
  state.lastError = ''
  try {
    const runR = join(DEFAULTS.home || '.', 'run.R')
    if (!DEFAULTS.home || !existsSync(runR)) {
      throw new Error(
        `找不到 Glyph 入口（run.R）。\n` +
        `当前配置的 Glyph 目录：${DEFAULTS.home || '(未设置)'}\n` +
        `请设置环境变量 GLYPH_HOME，或写入配置文件 ${CONFIG_FILE}：` +
        `{"glyphHome":"<Glyph 目录>","rscript":"<Rscript 路径>"}`
      )
    }
    if (!DEFAULTS.rscript || !existsSync(DEFAULTS.rscript)) {
      throw new Error(
        `找不到 Rscript。当前值：${DEFAULTS.rscript || '(未检测到)'}\n` +
        `请把 R 加入 PATH，或写入配置文件 ${CONFIG_FILE}：` +
        `{"glyphHome":"<Glyph 目录>","rscript":"<Rscript 路径>"}`
      )
    }

    const port = await pickPort()
    const ws = dir || state.workspace || DEFAULTS.dataDir || loadSavedDir() || DEFAULTS.home
    state.workspace = ws
    if (dir) saveDir(dir)

    const args = ['run.R', '--port', String(port), '--no-browser', '--data-dir', ws,
      // 心跳自监：宿主每隔几秒 ping 一次 /api/heartbeat；DSH 退出后没人 ping，
      // 超过 --heartbeat-timeout（120 秒，容忍 R 渲染/装包期间的短暂卡顿）R 进程会自行结束，
      // 避免宿主崩溃后留下孤儿 R 服务（run.R 专为插件实现的机制，这里必须接上）
      '--heartbeat', '--heartbeat-timeout', '120']
    const child = spawn(DEFAULTS.rscript, args, {
      cwd: DEFAULTS.home,
      windowsHide: true,
      stdio: ['ignore', 'pipe', 'pipe']
    })
    state.child = child
    state.port = port

    // 收集输出，出错时能看到原因
    let errBuf = ''
    child.stderr?.on('data', (b) => { errBuf = (errBuf + b.toString()).slice(-4000) })
    child.stdout?.on('data', () => {})
    child.on('exit', (code) => {
      stopHeartbeat()
      state.child = null
      if (code !== 0 && !state.lastError) {
        state.lastError = `Glyph 进程退出（code=${code}）${errBuf ? '：' + errBuf.slice(-300) : ''}`
      }
      state.port = 0
    })

    const ready = await waitReady(port)
    if (!ready) {
      state.lastError = 'Glyph 启动超时' + (errBuf ? '：' + errBuf.slice(-300) : '')
      try { child.kill() } catch { /* 忽略 */ }
      state.child = null
      state.port = 0
    } else {
      startHeartbeat(port)
    }
  } catch (e) {
    state.lastError = String(e && e.message || e)
  } finally {
    state.starting = false
  }
  return status()
}

/** 心跳：让 Glyph 知道宿主还活着（详见 run.R 的 --heartbeat 说明）。 */
function startHeartbeat(port) {
  stopHeartbeat()
  state.hbTimer = setInterval(() => {
    fetch(`http://127.0.0.1:${port}/api/heartbeat`, { signal: AbortSignal.timeout(3000) })
      .catch(() => { /* 服务忙或正在重启，超时判定交给 R 侧 */ })
  }, 10_000)
}

function stopHeartbeat() {
  if (state.hbTimer) { clearInterval(state.hbTimer); state.hbTimer = null }
}

function stop() {
  stopHeartbeat()
  if (state.child) {
    try {
      if (process.platform === 'win32' && state.child.pid) {
        // R 会派生渲染/装包子进程，直接 kill 只杀得到父进程 —— 必须整树杀
        execFileSync('taskkill', ['/pid', String(state.child.pid), '/T', '/F'], { stdio: 'ignore' })
      } else {
        state.child.kill()
      }
    } catch { try { state.child.kill() } catch { /* 忽略 */ } }
  }
  state.child = null
  state.port = 0
  return status()
}

function status() {
  return {
    running: !!state.child && !!state.port,
    starting: state.starting,
    port: state.port,
    url: state.port ? `http://127.0.0.1:${state.port}` : '',
    workspace: state.workspace,
    home: DEFAULTS.home,
    rscript: DEFAULTS.rscript,
    configFile: CONFIG_FILE,
    tokenEnforced: !!state.token,
    error: state.lastError
  }
}

/** 把代码推给 Glyph 的编辑器。 */
async function push(code, run) {
  if (!status().running) {
    const st = await start()
    if (!st.running) return { ok: false, error: st.error || 'Glyph 未运行' }
  }
  const r = await fetch(`http://127.0.0.1:${state.port}/api/code/push`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify({ code: String(code ?? ''), run: !!run })
  })
  const j = await r.json().catch(() => ({}))
  if (!r.ok || !j.ok) return { ok: false, error: j.error || `HTTP ${r.status}` }
  return { ok: true, seq: j.seq, url: `http://127.0.0.1:${state.port}` }
}

// ---- 控制服务 ----
/** CORS 来源白名单：只放行非公网来源（file:// 渲染层、本机环回、显式配置的来源）。
 *  公网页面（evil.com 等）拿不到 CORS 头：读不了响应、POST 预检也过不去。 */
function originAllowed(origin) {
  if (!origin) return false
  const o = String(origin)
  if (o === 'null') return true   // Electron file:// 渲染层的 fetch
  if (/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/i.test(o)) return true
  const extra = readConfigFile().allowedOrigins
  return Array.isArray(extra) && extra.some(e => String(e) === o)
}

function json(res, code, obj, origin) {
  const headers = { 'Content-Type': 'application/json; charset=utf-8' }
  if (origin && originAllowed(origin)) {
    // 只回显白名单内的来源，绝不使用 *
    headers['Access-Control-Allow-Origin'] = origin
    headers['Access-Control-Allow-Headers'] = 'Content-Type, X-Glyph-Token'
    headers['Access-Control-Allow-Methods'] = 'GET,POST,OPTIONS'
    headers['Vary'] = 'Origin'
    headers['Cache-Control'] = 'no-store'
  }
  // 204 不允许带响应体
  if (code === 204) { res.writeHead(204, headers); return res.end() }
  res.writeHead(code, headers)
  res.end(JSON.stringify(obj))
}

function readBody(req) {
  return new Promise((resolve) => {
    const chunks = []
    req.on('data', c => chunks.push(c))
    req.on('end', () => {
      const raw = Buffer.concat(chunks).toString('utf8')
      if (!raw) return resolve({})
      try { resolve(JSON.parse(raw)) } catch { resolve({}) }
    })
    req.on('error', () => resolve({}))
  })
}

function startControlServer() {
  if (state.server) return
  const srv = createServer(async (req, res) => {
    const origin = req.headers.origin || ''
    const url = new URL(req.url || '/', 'http://127.0.0.1')
    const p = url.pathname
    // 预检：只给白名单来源过（公网页面的 JSON POST 在这一步就死掉）
    if (req.method === 'OPTIONS') {
      if (originAllowed(origin)) return json(res, 204, {}, origin)
      return json(res, 403, { ok: false, error: '来源不被允许' })
    }
    // token 校验（GET/POST 一律要求）：token 只存在于配置文件与 client.js，
    // 不经 HTTP 提供，所以即使来源被 CORS 放行也伪造不了它
    if (state.token && req.headers['x-glyph-token'] !== state.token) {
      return json(res, 403, {
        ok: false,
        error: 'token 缺失或不匹配（客户端与宿主不同步？重启 DSH 或硬刷新页面）'
      }, origin)
    }
    try {
      if (p === '/status' && req.method === 'GET') return json(res, 200, { ok: true, ...status() }, origin)
      if (p === '/start' && req.method === 'POST') {
        const b = await readBody(req)
        // 指定了不同目录且正在运行 → 先停再起（切工作区）
        const wantDir = (b.dir && String(b.dir).trim()) || ''
        if (wantDir && state.child && wantDir !== state.workspace) stop()
        return json(res, 200, { ok: true, ...(await start(wantDir || undefined)) }, origin)
      }
      if (p === '/stop' && req.method === 'POST') return json(res, 200, { ok: true, ...stop() }, origin)
      if (p === '/push' && req.method === 'POST') {
        const b = await readBody(req)
        if (!b.code || !String(b.code).trim()) return json(res, 400, { ok: false, error: '缺少 code' }, origin)
        return json(res, 200, { ok: true, ...(await push(b.code, b.run)) }, origin)
      }
      // 配置读写：换机器时不用改代码，写配置文件即可
      if (p === '/config' && req.method === 'GET') {
        return json(res, 200, {
          ok: true,
          configFile: CONFIG_FILE,
          config: {
            glyphHome: DEFAULTS.home,
            rscript: DEFAULTS.rscript,
            appPort: DEFAULTS.glyphPort,
            controlPort: DEFAULTS.controlPort
          }
        }, origin)
      }
      if (p === '/config' && req.method === 'POST') {
        const b = await readBody(req)
        const next = readConfigFile()  // 含 token / allowedOrigins，只改下面三个键，其余原样保留
        if (b.glyphHome !== undefined) next.glyphHome = String(b.glyphHome || '')
        if (b.rscript !== undefined) next.rscript = String(b.rscript || '')
        if (b.appPort !== undefined) next.appPort = Number(b.appPort) || 4321
        try {
          writeFileSync(CONFIG_FILE, JSON.stringify(next, null, 2), 'utf8')
        } catch (e) {
          return json(res, 500, { ok: false, error: '写配置文件失败：' + String(e && e.message || e) }, origin)
        }
        if (b.glyphHome !== undefined) DEFAULTS.home = String(b.glyphHome || '')
        if (b.rscript !== undefined) DEFAULTS.rscript = String(b.rscript || '')
        if (b.appPort !== undefined) DEFAULTS.glyphPort = Number(b.appPort) || 4321
        // 路径变了要重启才生效
        stop()
        return json(res, 200, { ok: true, configFile: CONFIG_FILE, ...(await start()) }, origin)
      }
      // 浏览器半上报的调试事件
      if (p === '/log' && req.method === 'POST') {
        const b = await readBody(req)
        appendClientLog(b)
        return json(res, 200, { ok: true }, origin)
      }
      if (p === '/log' && req.method === 'GET') {
        const n = Number(url.searchParams.get('n') || 60)
        return json(res, 200, { ok: true, text: readClientLog(n) }, origin)
      }
      return json(res, 404, { ok: false, error: 'not found' }, origin)
    } catch (e) {
      return json(res, 500, { ok: false, error: String(e && e.message || e) }, origin)
    }
  })
  srv.on('error', (e) => {
    state.lastError = `控制服务端口 ${state.controlPort} 不可用：${e.message}`
  })
  srv.listen(state.controlPort, '127.0.0.1')
  state.server = srv
}

// ---- 插件入口 ----
// cordis 约定：模块要同时导出 name 与 apply（缺少 name 时加载器不会把它当作插件行）。
export const name = 'glyph'

// 注意：cordis 对未在 inject 里声明的服务会直接抛错，所以这里不碰 ctx.workspace，
// 项目目录取「DSH 进程的工作目录」——也就是用户启动 DSH 的项目文件夹。
export function apply(ctx) {
  // 整个启动过程包在 try/catch 里：插件出问题绝不能影响 DSH 自身启动
  try {
    // token：生成/读取 → 回写 client.js（浏览器半从同一目录加载它，刷新后即持有 token）。
    // 回写失败（只读目录/版本不一致）时放弃 token 校验，退回纯 CORS 白名单模式。
    state.token = ensureToken()
    if (!syncClientFile(state.token, DEFAULTS.controlPort)) state.token = ''
    startControlServer()
    const ws = DEFAULTS.dataDir || loadSavedDir() || DEFAULTS.home
    start(ws).catch(() => { /* 失败信息记录在 status 里 */ })
    ctx?.effect?.(() => () => { stop() })
  } catch (e) {
    // 记录但不抛出
    state.lastError = String(e && e.message || e)
  }
}
