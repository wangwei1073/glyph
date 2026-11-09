// Glyph DSH 插件 —— 浏览器半
//
// 模块格式与官方产物一致：自注册 CJS 工厂，由 __ModuleLoader__ 在首次 import 时物化。
// 只 require("react")（shell 提供），其余全部原生 DOM / React 元素。
//
// 入口（原生）：
//   1. 右栏「+」→ Glyph，作为原生页签打开（和内置「浏览器」并列）
//   2. 聊天里每个代码块右上角的「推送」按钮
//
// 不使用 window.prompt / alert / confirm：Electron 禁用原生对话框，
// 调用即抛错，表现为「点了没反应」——一律用页签内的输入卡片。

window.__ModuleLoader__.load({
  id: 'dsh-plugin-glyph',
  factory: (require) => {
    const exports = {}
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })

    const API = 'http://127.0.0.1:4399'
    const STYLE_ID = 'glyph-dsh-style'
    const TAB_ID = 'glyph'

    const CSS = [
      '.gp-code-host{position:relative}',
      '.gp-code-btn{position:absolute;top:6px;right:6px;z-index:5;border:1px solid rgba(255,255,255,.28);background:rgba(47,111,191,.92);color:#fff;border-radius:5px;padding:2px 8px;font-size:11px;cursor:pointer;font-family:system-ui,sans-serif}',
      '.gp-code-btn:hover{background:#2f6fbf}',
      '.gp-code-btn:disabled{opacity:.6;cursor:default}'
    ].join('\n')

    function injectStyle() {
      if (document.getElementById(STYLE_ID)) return
      const s = document.createElement('style')
      s.id = STYLE_ID
      s.textContent = CSS
      document.head.appendChild(s)
    }

    function report(event, extra) {
      try {
        fetch(API + '/log', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(Object.assign({ event: event }, extra || {})),
          keepalive: true
        }).catch(function () {})
      } catch (e) { /* 忽略 */ }
    }

    function api(path, body) {
      const opt = body === undefined
        ? { method: 'GET' }
        : { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) }
      return fetch(API + path, opt).then(r => r.json())
    }

    // ---------- 原生页签主体 ----------
    // 就是一个铺满的 iframe：不加工具栏（推送走聊天代码块按钮，其余 Glyph 自带）。
    // 只在 Glyph 没起来时显示提示 + 重试。
    function makePane(React) {
      const h = React.createElement

      const S = {
        root: { width: '100%', height: '100%', minHeight: 0, position: 'relative', background: '#f2f4f7' },
        center: { height: '100%', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: '10px', padding: '24px', color: '#6b7280', textAlign: 'center', font: '12px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif' },
        err: { color: '#c0392b' },
        btn: { border: '1px solid rgba(0,0,0,.16)', background: '#fff', color: '#1f2329', borderRadius: '6px', padding: '4px 12px', fontSize: '12px', cursor: 'pointer' }
      }

      return function GlyphPane() {
        const [state, setState] = React.useState({ running: false, starting: true, url: '', error: '' })

        React.useEffect(() => {
          let alive = true
          const load = () => {
            api('/status').then(st => { if (alive) setState(st || {}) }).catch(() => {
              if (alive) setState({ running: false, starting: false, url: '', error: '无法连接 Glyph 控制服务（端口 4399）' })
            })
          }
          load()
          api('/start', {}).catch(() => {})
          const t = setInterval(load, 3000)
          return () => { alive = false; clearInterval(t) }
        }, [])

        const retry = () => {
          setState({ running: false, starting: true, url: '', error: '' })
          api('/stop', {}).catch(() => null)
            .then(() => api('/start', {}).catch(() => null))
            .then(() => api('/status').then(st => setState(st || {})))
        }

        if (state.running && state.url) {
          return h('div', { style: S.root },
            h('iframe', {
              key: state.url,
              src: state.url,
              allow: 'clipboard-write; clipboard-read',
              style: { width: '100%', height: '100%', border: 0, display: 'block' }
            })
          )
        }

        if (state.starting) {
          return h('div', { style: S.root }, h('div', { style: S.center }, '正在启动 Glyph …'))
        }

        return h('div', { style: S.root },
          h('div', { style: S.center },
            h('div', { style: state.error ? Object.assign({}, S.err) : {} },
              state.error || 'Glyph 未运行'),
            h('button', { type: 'button', style: S.btn, onClick: retry }, '重试')
          )
        )
      }
    }

    // ---------- 注册原生页签 ----------
    function installNativeTab(ctx) {
      const React = require('react')
      const Pane = makePane(React)
      ctx.inject(['slots', 'sidebarRightTabs'], (scope) => {
        scope.effect(() => scope.sidebarRightTabs.register({
          id: TAB_ID,
          kind: TAB_ID,
          multiple: true,
          title: () => 'Glyph',
          guide: [{
            id: 'new',
            commandId: 'glyph.open',
            order: 40,
            title: () => 'Glyph',
            description: () => '在右栏打开 Glyph 绘图面板'
          }]
        }))
        scope.effect(() => scope.slots.register({
          name: 'sidebar.right.pane.tab',
          key: TAB_ID,
          inject: () => ({}),
          Component: Pane
        }, Pane))
      }, 'glyph: native tab')
    }

    // ---------- 代码块推送按钮 ----------
    function codeOf(pre) {
      const codeEl = pre.querySelector('code')
      const node = codeEl || pre
      return (node.innerText || node.textContent || '').replace(/\u00a0/g, ' ')
    }

    function decorate(root) {
      const blocks = root.querySelectorAll('pre')
      for (let i = 0; i < blocks.length; i++) {
        const pre = blocks[i]
        if (pre.dataset.gpDone === '1') continue
        pre.dataset.gpDone = '1'

        const parent = pre.parentElement
        let host = null
        if (parent && parent.classList.contains('gp-code-host')) {
          host = parent
        } else if (parent && parent.querySelectorAll('pre').length === 1) {
          parent.classList.add('gp-code-host')
          host = parent
        } else {
          host = document.createElement('div')
          host.className = 'gp-code-host'
          if (pre.parentNode) {
            pre.parentNode.insertBefore(host, pre)
            host.appendChild(pre)
          }
        }

        const btn = document.createElement('button')
        btn.type = 'button'
        btn.className = 'gp-code-btn'
        btn.textContent = '推送'
        btn.title = '把这段代码推送到 Glyph 渲染'
        btn.addEventListener('click', (ev) => {
          ev.preventDefault()
          ev.stopPropagation()
          const text = codeOf(pre)
          if (!text.trim()) return
          btn.disabled = true
          btn.textContent = '推送中…'
          api('/push', { code: text, run: true }).then(res => {
            if (res && res.ok) {
              btn.textContent = '已出图'
              setTimeout(() => { btn.textContent = '推送'; btn.disabled = false }, 1500)
            } else {
              btn.textContent = '失败'
              btn.title = (res && res.error) || ''
              setTimeout(() => { btn.textContent = '推送'; btn.disabled = false }, 2500)
            }
          }).catch(err => {
            btn.textContent = '失败'
            btn.title = String(err && err.message || err)
            setTimeout(() => { btn.textContent = '推送'; btn.disabled = false }, 2500)
          })
        })
        if (host) host.appendChild(btn)
      }
    }

    // ---------- 入口 ----------
    let lastBtnCount = -1

    function apply(ctx) {
      report('apply-called')
      try {
        if (typeof document === 'undefined') return

        const boot = () => {
          try {
            injectStyle()
            decorate(document)
            const obs = new MutationObserver(() => {
              try {
                decorate(document)
                const n = document.querySelectorAll('.gp-code-btn').length
                if (n !== lastBtnCount) { lastBtnCount = n; report('decorate-change', { buttons: n }) }
              } catch (e) { /* 忽略 */ }
            })
            obs.observe(document.body, { childList: true, subtree: true })
            if (ctx && typeof ctx.effect === 'function') {
              ctx.effect(() => () => {
                obs.disconnect()
                const s = document.getElementById(STYLE_ID)
                if (s) s.remove()
              })
            }
          } catch (e) {
            report('boot-error', { message: String(e && e.message || e) })
          }
        }

        if (document.body) boot()
        else document.addEventListener('DOMContentLoaded', boot, { once: true })

        try {
          installNativeTab(ctx)
          report('native-tab-registered')
        } catch (e) {
          report('native-tab-error', { message: String(e && e.message || e), stack: String(e && e.stack || '') })
        }
      } catch (e) {
        report('apply-error', { message: String(e && e.message || e) })
      }
    }

    exports.name = 'glyph-client'
    exports.inject = []
    exports.apply = apply
    return exports
  }
})
