// Glyph DSH 插件 —— 浏览器半
//
// 模块格式与官方产物一致：自注册 CJS 工厂，由 __ModuleLoader__ 在首次 import 时物化。
// 不 require 任何模块（含 react）—— 全部原生 DOM，因此无打包产物、无外部依赖。
//
// 重要：不使用 window.prompt / alert / confirm。
// Electron 宿主会禁用原生对话框，点了会毫无反应 —— 一律用面板内嵌输入框。
//
// 入口：
//   1. 页面右侧边缘的 Glyph 竖条 → 右侧停靠面板（内嵌 Glyph 界面）
//   2. 面板内「推送代码」→ 内嵌输入框，粘贴代码直接出图
//   3. 聊天里每个代码块右上角的「推送」按钮

window.__ModuleLoader__.load({
  id: 'dsh-plugin-glyph',
  factory: (require) => {
    const exports = {}
    Object.defineProperty(exports, Symbol.toStringTag, { value: 'Module' })

    const API = 'http://127.0.0.1:4399'
    const STYLE_ID = 'glyph-dsh-style'

    const CSS = [
      '.gp-rail{position:fixed;right:0;top:45%;z-index:2140;display:flex;flex-direction:column;align-items:center;gap:5px;width:32px;padding:10px 0;cursor:pointer;background:#fff;border:1px solid rgba(0,0,0,.12);border-right:none;border-radius:8px 0 0 8px;box-shadow:-2px 0 10px rgba(0,0,0,.08);font:600 11px/1.2 system-ui,-apple-system,"Segoe UI",sans-serif;color:#2f6fbf;user-select:none}',
      '.gp-rail:hover{background:#f4f8ff}',
      '.gp-rail.gp-on{color:#1f9d55}',
      '.gp-rail-dot{width:6px;height:6px;border-radius:50%;background:#c9ced6}',
      '.gp-rail.gp-on .gp-rail-dot{background:#1f9d55}',
      '.gp-panel{position:fixed;right:0;top:0;bottom:0;z-index:2139;width:min(1160px,58vw);display:flex;flex-direction:column;background:#fff;border-left:1px solid rgba(0,0,0,.14);box-shadow:-8px 0 32px rgba(0,0,0,.14);overflow:hidden;font:12px/1.4 system-ui,-apple-system,"Segoe UI",sans-serif}',
      '.gp-head{display:flex;align-items:center;gap:8px;padding:8px 12px;background:#f7f9fc;border-bottom:1px solid rgba(0,0,0,.08);flex:none;min-height:38px}',
      '.gp-title{font-weight:600;color:#1f2329}',
      '.gp-ws{color:#6b7280;font-size:11px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1;min-width:0}',
      '.gp-btn{border:1px solid rgba(0,0,0,.14);background:#fff;color:#1f2329;border-radius:6px;padding:3px 9px;font-size:11px;cursor:pointer;flex:none;font-family:inherit}',
      '.gp-btn:hover{background:rgba(47,111,191,.10);border-color:#2f6fbf;color:#2f6fbf}',
      '.gp-btn:disabled{opacity:.5;cursor:default}',
      '.gp-btn.gp-primary{background:#2f6fbf;border-color:#2f6fbf;color:#fff}',
      '.gp-btn.gp-primary:hover{background:#255a9c;color:#fff}',
      '.gp-body{flex:1;min-height:0;background:#f2f4f7;position:relative;display:flex;flex-direction:column}',
      '.gp-frame{flex:1;min-height:0}',
      '.gp-frame iframe{width:100%;height:100%;border:0;display:block}',
      '.gp-hint{padding:24px;color:#6b7280;text-align:center}',
      '.gp-err{color:#c0392b}',
      '.gp-composer{position:absolute;inset:0;background:rgba(15,23,42,.34);display:flex;align-items:center;justify-content:center;padding:20px;z-index:8}',
      '.gp-card{background:#fff;border-radius:10px;box-shadow:0 12px 40px rgba(0,0,0,.24);width:min(720px,100%);max-height:100%;display:flex;flex-direction:column;overflow:hidden}',
      '.gp-card-h{padding:10px 14px;border-bottom:1px solid rgba(0,0,0,.08);font-weight:600;color:#1f2329;font-size:12.5px}',
      '.gp-card-b{padding:12px 14px;display:flex;flex-direction:column;gap:8px;min-height:0}',
      '.gp-card-f{padding:10px 14px;border-top:1px solid rgba(0,0,0,.08);display:flex;gap:8px;justify-content:flex-end}',
      '.gp-ta{width:100%;min-height:220px;border:1px solid rgba(0,0,0,.18);border-radius:6px;padding:8px;font:12px/1.5 ui-monospace,Consolas,monospace;resize:vertical;box-sizing:border-box}',
      '.gp-in{width:100%;border:1px solid rgba(0,0,0,.18);border-radius:6px;padding:7px 8px;font:12px/1.5 ui-monospace,Consolas,monospace;box-sizing:border-box}',
      '.gp-tip{color:#6b7280;font-size:11px}',
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

    function el(tag, cls, text) {
      const n = document.createElement(tag)
      if (cls) n.className = cls
      if (text !== undefined) n.textContent = text
      return n
    }

    // ---------- 面板 ----------
    function mountPanel() {
      const rail = el('div', 'gp-rail')
      rail.title = 'Glyph 绘图'
      rail.appendChild(el('span', 'gp-rail-dot'))
      rail.appendChild(el('span', '', 'Glyph'))

      const panel = el('div', 'gp-panel')
      panel.style.display = 'none'

      const head = el('div', 'gp-head')
      const title = el('span', 'gp-title', 'Glyph')
      const wsEl = el('span', 'gp-ws')
      head.appendChild(title)
      head.appendChild(wsEl)

      const mkBtn = (text, primary) => {
        const b = el('button', 'gp-btn' + (primary ? ' gp-primary' : ''), text)
        b.type = 'button'
        head.appendChild(b)
        return b
      }
      const codeBtn = mkBtn('推送代码', true)
      const dirBtn = mkBtn('项目目录')
      const restartBtn = mkBtn('重启')
      const closeBtn = mkBtn('收起')

      const body = el('div', 'gp-body')
      const frameWrap = el('div', 'gp-frame')
      body.appendChild(frameWrap)
      panel.appendChild(head)
      panel.appendChild(body)

      let iframe = null
      let lastUrl = ''
      let open = false
      let timer = null

      function hint(text, isErr) {
        frameWrap.innerHTML = ''
        const d = el('div', 'gp-hint' + (isErr ? ' gp-err' : ''), text)
        frameWrap.appendChild(d)
        iframe = null
        lastUrl = ''
      }

      function show(url, ws, running) {
        if (ws) wsEl.textContent = ws
        rail.classList.toggle('gp-on', !!running)
        if (!running) return
        if (iframe && lastUrl === url) return
        lastUrl = url
        frameWrap.innerHTML = ''
        iframe = document.createElement('iframe')
        iframe.src = url
        iframe.setAttribute('allow', 'clipboard-write; clipboard-read')
        frameWrap.appendChild(iframe)
      }

      function refresh() {
        return api('/status').then(st => {
          if (st.starting) { if (open) hint('正在启动 Glyph …'); return }
          if (st.error && open) { hint('启动失败：' + st.error, true); return }
          show(st.url, st.workspace, st.running)
          if (!st.running && open) hint('Glyph 未运行')
        }).catch(() => { if (open) hint('无法连接 Glyph 控制服务（端口 4399）', true) })
      }

      // ---- 内嵌输入卡片（替代 window.prompt）----
      let composer = null

      function closeComposer() {
        if (composer) { composer.remove(); composer = null }
      }

      function openComposer(mode) {
        closeComposer()
        composer = el('div', 'gp-composer')
        const card = el('div', 'gp-card')
        const h = el('div', 'gp-card-h', mode === 'dir' ? '设置 Glyph 项目目录' : '推送 R 代码到 Glyph')
        const b = el('div', 'gp-card-b')
        const f = el('div', 'gp-card-f')

        let input
        if (mode === 'dir') {
          input = el('input', 'gp-in')
          input.type = 'text'
          input.value = wsEl.textContent || ''
          input.placeholder = '例如 E:\\my-project'
          b.appendChild(input)
          b.appendChild(el('div', 'gp-tip', '图库、上传的数据与编辑记录都会存到这个目录。'))
        } else {
          input = el('textarea', 'gp-ta')
          input.placeholder = '在这里粘贴 R 代码（Ctrl+V），然后点「推送并渲染」'
          b.appendChild(input)
          b.appendChild(el('div', 'gp-tip', '代码会在 Glyph 里立刻运行，图形显示在面板中。'))
        }

        const ok = el('button', 'gp-btn gp-primary', mode === 'dir' ? '应用并重启' : '推送并渲染')
        ok.type = 'button'
        const cancel = el('button', 'gp-btn', '取消')
        cancel.type = 'button'
        f.appendChild(cancel)
        f.appendChild(ok)

        card.appendChild(h)
        card.appendChild(b)
        card.appendChild(f)
        composer.appendChild(card)
        panel.appendChild(composer)

        cancel.addEventListener('click', closeComposer)
        composer.addEventListener('click', (e) => { if (e.target === composer) closeComposer() })

        ok.addEventListener('click', () => {
          const val = input.value || ''
          if (mode === 'dir') {
            const dir = val.trim()
            if (!dir) { input.focus(); return }
            closeComposer()
            hint('正在切换项目目录并重启 Glyph …')
            lastUrl = ''
            api('/start', { dir }).catch(() => null).then(() => refresh())
          } else {
            if (!val.trim()) { input.focus(); return }
            ok.disabled = true
            ok.textContent = '推送中…'
            api('/push', { code: val, run: true }).then(res => {
              if (res && res.ok) {
                closeComposer()
                lastUrl = ''
                refresh()
              } else {
                ok.disabled = false
                ok.textContent = '推送并渲染'
                b.appendChild(el('div', 'gp-tip gp-err', '推送失败：' + ((res && res.error) || '未知错误')))
              }
            }).catch(err => {
              ok.disabled = false
              ok.textContent = '推送并渲染'
              b.appendChild(el('div', 'gp-tip gp-err', '推送失败：' + String(err && err.message || err)))
            })
          }
        })

        // 代码模式若剪贴板可读，自动预填（失败不影响使用）
        if (mode === 'code' && navigator.clipboard && navigator.clipboard.readText) {
          navigator.clipboard.readText().then(t => {
            if (t && t.trim() && input === composer?.querySelector('.gp-ta')) input.value = t
          }).catch(() => {})
        }
        input.focus()
      }

      function openPanel() {
        open = true
        rail.style.display = 'none'
        panel.style.display = 'flex'
        hint('正在启动 Glyph …')
        api('/start', {}).catch(() => null).then(() => refresh())
        if (timer) clearInterval(timer)
        timer = setInterval(() => { if (open) refresh() }, 3000)
      }

      function closePanel() {
        open = false
        closeComposer()
        panel.style.display = 'none'
        rail.style.display = 'flex'
        if (timer) { clearInterval(timer); timer = null }
      }

      rail.addEventListener('click', () => { if (open) closePanel(); else openPanel() })
      closeBtn.addEventListener('click', closePanel)
      codeBtn.addEventListener('click', () => openComposer('code'))
      dirBtn.addEventListener('click', () => openComposer('dir'))

      restartBtn.addEventListener('click', () => {
        restartBtn.disabled = true
        hint('正在重启 Glyph …')
        api('/stop', {}).catch(() => null)
          .then(() => api('/start', {}).catch(() => null))
          .then(() => { lastUrl = ''; return refresh() })
          .then(() => { restartBtn.disabled = false })
      })

      const onKey = (e) => {
        if (!open) return
        if (e.key === 'Escape') {
          if (composer) closeComposer()
          else closePanel()
        }
      }
      document.addEventListener('keydown', onKey)

      document.body.appendChild(rail)
      document.body.appendChild(panel)

      api('/status').then(st => {
        rail.classList.toggle('gp-on', !!st.running)
        if (st.workspace) wsEl.textContent = st.workspace
      }).catch(() => {})

      return () => {
        if (timer) clearInterval(timer)
        document.removeEventListener('keydown', onKey)
        rail.remove()
        panel.remove()
      }
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
          host = el('div', 'gp-code-host')
          if (pre.parentNode) {
            pre.parentNode.insertBefore(host, pre)
            host.appendChild(pre)
          }
        }

        const btn = el('button', 'gp-code-btn', '推送')
        btn.type = 'button'
        btn.title = '把这段代码推送到 Glyph 渲染'
        btn.addEventListener('click', (ev) => {
          ev.preventDefault()
          ev.stopPropagation()
          const code = codeOf(pre)
          if (!code.trim()) return
          btn.disabled = true
          btn.textContent = '推送中…'
          api('/push', { code: code, run: true }).then(res => {
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

    // ---------- 插件入口 ----------
    let lastBtnCount = -1

    function apply(ctx) {
      report('apply-called', { hasCtx: !!ctx })
      try {
        if (typeof document === 'undefined') return
        const cleanups = []

        const boot = () => {
          try {
            injectStyle()
            cleanups.push(mountPanel())
            report('boot-ok', { preCount: document.querySelectorAll('pre').length })
            decorate(document)
            const obs = new MutationObserver(() => {
              try {
                decorate(document)
                const n = document.querySelectorAll('.gp-code-btn').length
                if (n !== lastBtnCount) { lastBtnCount = n; report('decorate-change', { buttons: n }) }
              } catch (e) { /* 忽略 */ }
            })
            obs.observe(document.body, { childList: true, subtree: true })
            cleanups.push(() => obs.disconnect())
            cleanups.push(() => {
              const s = document.getElementById(STYLE_ID)
              if (s) s.remove()
            })
          } catch (e) {
            report('boot-error', { message: String(e && e.message || e), stack: String(e && e.stack || '') })
          }
        }

        if (document.body) boot()
        else document.addEventListener('DOMContentLoaded', boot, { once: true })

        if (ctx && typeof ctx.effect === 'function') {
          ctx.effect(() => () => {
            for (let i = 0; i < cleanups.length; i++) {
              try { cleanups[i]() } catch (e) { /* 忽略 */ }
            }
          })
        }
      } catch (e) {
        report('apply-error', { message: String(e && e.message || e), stack: String(e && e.stack || '') })
      }
    }

    exports.name = 'glyph-client'
    exports.inject = []
    exports.apply = apply
    return exports
  }
})
