// 远程数据库会话 store：关闭弹层后连接与表/预览状态保留
import { defineStore } from 'pinia'
import { ElMessage } from 'element-plus'
import {
  getDbDrivers, dbTest, dbConnect, dbTables, dbPreview, dbImport, dbDisconnect,
  installExtension, getInstallStatus
} from '../api'

export const useRemoteDbStore = defineStore('remoteDb', {
  state: () => ({
    drivers: [],
    driver: 'postgres',
    form: {
      host: '127.0.0.1', port: 5432, dbname: '', user: '', password: '',
      sslmode: 'prefer', dsn: '', driverName: ''
    },
    connId: '',
    connInfo: null,
    tables: [],
    tableSel: null,
    preview: null,
    sqlMode: false,
    sql: '',
    label: '',
    search: '',
    error: '',
    testMsg: '',
    testing: false,
    connecting: false,
    loading: false,
    importing: false,
    installing: ''
  }),
  getters: {
    driverDef(state) { return state.drivers.find(d => d.id === state.driver) },
    installed(state) { return !!state.drivers.find(d => d.id === state.driver)?.installed },
    schemas(state) {
      const map = {}
      for (const t of state.tables) {
        const k = t.schema || ''
        if (!map[k]) map[k] = []
        map[k].push(t)
      }
      return Object.entries(map).map(([name, tables]) => ({ name, tables }))
    },
    filteredSchemas(state) {
      const q = state.search.trim().toLowerCase()
      if (!q) return this.schemas
      return this.schemas
        .map(s => ({ ...s, tables: s.tables.filter(t => t.name.toLowerCase().includes(q)) }))
        .filter(s => s.tables.length)
    },
    importCount(state) {
      if (!state.sqlMode && state.tableSel?.rows != null) return Number(state.tableSel.rows)
      return state.preview?.previewRows ?? null
    }
  },
  actions: {
    async loadDrivers() {
      try {
        const res = await getDbDrivers()
        this.drivers = res.drivers || []
        const pg = this.drivers.find(d => d.id === 'postgres' && d.installed)
        if (pg && !this.connId) this.driver = 'postgres'
      } catch { /* 忽略 */ }
    },
    setDriver(id) {
      if (this.connId) this.disconnect()
      this.driver = id
      this.form.port = this.drivers.find(d => d.id === id)?.port || this.form.port
      this.error = ''
      this.testMsg = ''
    },
    async test() {
      this.testing = true
      this.error = ''
      this.testMsg = ''
      try {
        const res = await dbTest({ driver: this.driver, ...this.form })
        if (!res.ok) throw new Error(res.error || '连接失败')
        this.testMsg = `连接成功 · ${res.result.version || ''} · ${res.result.elapsedMs}ms`
      } catch (e) {
        this.error = e.message
      } finally {
        this.testing = false
      }
    },
    async connect() {
      this.connecting = true
      this.error = ''
      try {
        const res = await dbConnect({ driver: this.driver, ...this.form })
        if (!res.ok) throw new Error(res.error || '连接失败')
        this.connId = res.connection.connId
        this.connInfo = res.connection
        this.testMsg = `已连接 · ${res.connection.version || ''}`
        await this.loadTables()
      } catch (e) {
        this.error = e.message
      } finally {
        this.connecting = false
      }
    },
    async loadTables() {
      if (!this.connId) return
      this.loading = true
      try {
        const res = await dbTables(this.connId)
        if (!res.ok) throw new Error(res.error || '读取表失败')
        this.tables = res.tables || []
        const first = this.tables[0]
        if (first) {
          this.tableSel = first
          this.label = first.name
          await this.previewTable()
        }
      } catch (e) {
        this.error = e.message
      } finally {
        this.loading = false
      }
    },
    async previewTable() {
      if (!this.connId || !this.tableSel) return
      this.loading = true
      this.error = ''
      try {
        const res = await dbPreview({
          conn: this.connId,
          schema: this.tableSel.schema || '',
          table: this.tableSel.name,
          limit: 100
        })
        if (!res.ok) throw new Error(res.error || '预览失败')
        this.preview = res.preview
        this.sqlMode = false
      } catch (e) {
        this.error = e.message
      } finally {
        this.loading = false
      }
    },
    selectTable(t) {
      this.tableSel = t
      this.label = t.name
      this.sqlMode = false
      this.sql = ''
      this.previewTable()
    },
    enterSql() {
      this.sqlMode = true
      // 先取预览里保存的 SQL 再清 preview（原顺序永远读到空串）
      this.sql = this.preview?.sql || ''
      this.preview = null
    },
    async runSql() {
      if (!this.connId || !this.sql.trim()) return
      this.loading = true
      this.error = ''
      try {
        const res = await dbPreview({ conn: this.connId, sql: this.sql, limit: 100 })
        if (!res.ok) throw new Error(res.error || '查询失败')
        this.preview = res.preview
      } catch (e) {
        this.error = e.message
      } finally {
        this.loading = false
      }
    },
    async importData() {
      if (!this.connId || !this.preview) return null
      this.importing = true
      try {
        const res = await dbImport({
          conn: this.connId,
          schema: this.sqlMode ? '' : (this.tableSel?.schema || ''),
          table: this.sqlMode ? '' : (this.tableSel?.name || ''),
          sql: this.sqlMode ? this.sql : '',
          label: this.label || (this.sqlMode ? '查询结果' : (this.tableSel?.name || '数据库表'))
        })
        if (!res.ok) throw new Error(res.error || '导入失败')
        return res.source
      } catch (e) {
        this.error = e.message
        return null
      } finally {
        this.importing = false
      }
    },
    async disconnect() {
      try { await dbDisconnect(this.connId) } catch { /* 忽略 */ }
      this.connId = ''
      this.connInfo = null
      this.tables = []
      this.tableSel = null
      this.preview = null
      this.sqlMode = false
      this.sql = ''
      this.error = ''
      this.testMsg = ''
    },
    async installDriver() {
      const pkg = this.driverDef?.pkg
      if (!pkg || this.installing) return
      this.installing = pkg
      try {
        await installExtension(pkg)
        const poll = async () => {
          const st = await getInstallStatus()
          if (st.job?.status === 'running') return setTimeout(poll, 1200)
          this.installing = ''
          if (st.job?.status === 'done') {
            ElMessage.success(`${pkg} 安装完成`)
            await this.loadDrivers()
          } else {
            ElMessage.error('安装失败：' + (st.job?.log || '未知错误'))
          }
        }
        poll()
      } catch (e) {
        this.installing = ''
        ElMessage.error('安装失败：' + e.message)
      }
    }
  }
})
