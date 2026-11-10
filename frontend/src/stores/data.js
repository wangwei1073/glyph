// Glyph - 数据源 store
import { defineStore } from 'pinia'
import { getSources, getColumns, uploadData, pasteData, deleteData, previewData } from '../api'
import { useSpecStore } from './spec'

// ---- prep 构造唯一入口 ----
// spec.spec.data → 后端 data_prepare 的参数。列面板/预览/统计/导出统一从这里取，
// 新增加工字段只改这里（此前 7 处手抄曾漏掉 text 字段，导致文本变换后统计/预览不同步）
export function buildPrep(sd = {}) {
  return {
    filter: sd.filter || '', mutate: sd.mutate || [],
    sample: sd.sample, seed: sd.seed,
    filterDisabled: !!sd.filterDisabled, sampleDisabled: !!sd.sampleDisabled,
    types: sd.types || [], text: sd.text || [], outliers: sd.outliers || [],
    fillna: sd.fillna || [], dropnaCols: sd.dropnaCols || [],
    dropnaHow: sd.dropnaHow || 'any', dropnaDisabled: !!sd.dropnaDisabled,
    dedupCols: sd.dedupCols || [], dedupEnabled: !!sd.dedupEnabled
  }
}

export const useDataStore = defineStore('data', {
  state: () => ({
    sources: [],
    srcKey: 'none',          // 'dataset:mpg' | 'user:u1' | 'none'
    columns: [],             // [{name,type,nUnique,preview...}]
    preview: { rows: [], nrow: 0, ncol: 0 },
    previewLoading: false,
    _refreshSeq: 0,          // refresh 请求序号：慢请求晚归时丢弃过期结果
    _previewSeq: 0           // refreshPreview 请求序号：同上
  }),
  getters: {
    current(state) {
      return state.sources.find(s => `${s.type}:${s.name}` === state.srcKey) || null
    },
    colNames(state) { return state.columns.map(c => c.name) },
    srcSpec() {
      const c = this.current
      if (!c || c.type === 'none') return { type: 'none' }
      if (c.type === 'dataset') return { type: 'dataset', name: c.name }
      return { type: 'user', id: c.name }
    },
    columnOptions(state) {
      return state.columns.map(c => ({
        value: c.name,
        label: c.name,
        type: c.type,
        nUnique: c.nUnique
      }))
    }
  },
  actions: {
    async load() {
      const { sources } = await getSources()
      this.sources = sources
      if (this.srcKey !== 'none' && !this.current) this.srcKey = 'none'
      if (this.current) await this.refresh()
    },
    async select(key) {
      this.srcKey = key
      await this.refresh()
    },
    async refresh() {
      const c = this.current
      if (!c || c.type === 'none') {
        this.columns = []
        this.preview = { rows: [], nrow: 0, ncol: 0 }
        return
      }
      // 请求序号：没有 abort 机制，慢请求（如非法加工表达式）晚归时会覆盖新数据源的列
      // —— 用序号丢弃过期结果（含错误回退路径发出的第二次请求）
      const token = ++this._refreshSeq
      try {
        const sd = useSpecStore().spec.data
        const prep = buildPrep(sd)
        const source = c.type === 'dataset'
          ? { type: 'dataset', name: c.name }
          : { type: 'user', id: c.name }
        const { columns } = await getColumns(source, prep)
        if (token !== this._refreshSeq) return
        // 换源继承：先记下旧列名（赋值前），改绑仍存在的映射（大小写不敏感唯一匹配），
        // 再由 pruneMappings 清掉新数据里没有的
        const oldCols = this.colNames.slice()
        this.columns = columns
        if (oldCols.length) {
          try { useSpecStore().remapMappings(oldCols, this.colNames) } catch { /* 循环依赖兜底 */ }
        }
      } catch {
        // 加工表达式暂时不合法时回退到原始列，避免列面板突然清空
        try {
          const src = c.type === 'dataset'
            ? { type: 'dataset', name: c.name }
            : { type: 'user', id: c.name }
          const { columns } = await getColumns(src)
          if (token !== this._refreshSeq) return
          const oldCols2 = this.colNames.slice()
          this.columns = columns
          if (oldCols2.length) {
            try { useSpecStore().remapMappings(oldCols2, this.colNames) } catch { /* 循环依赖兜底 */ }
          }
        } catch {
          if (token !== this._refreshSeq) return
          this.columns = []
        }
      }
      if (token !== this._refreshSeq) return
      await this.refreshPreview()
      // 换了数据源后，清掉指向旧列的 aes 映射，避免渲染报「找不到对象」
      try { useSpecStore().pruneMappings(this.colNames) } catch { /* 循环依赖兜底 */ }
    },
    async refreshPreview() {
      const c = this.current
      if (!c || c.type === 'none') return
      const token = ++this._previewSeq
      this.previewLoading = true
      try {
        const src = c.type === 'dataset' ? { type: 'dataset', name: c.name }
          : { type: 'user', id: c.name }
        // 数据加工参数以 spec.data 为准（单一事实来源）
        const sd = useSpecStore().spec.data
        const prep = buildPrep(sd)
        const res = await previewData(src, prep)
        if (token !== this._previewSeq) return
        this.preview = res
      } catch (e) {
        if (token !== this._previewSeq) return
        this.preview = { rows: [], nrow: 0, ncol: 0, error: e.message }
      } finally {
        // 过期请求不去动 previewLoading —— 它归最新那次请求管
        if (token === this._previewSeq) this.previewLoading = false
      }
    },
    // sheet：Excel 工作表（1 起始下标）；多 sheet 快速上传时由 DataPanel 弹窗选择后传入
    async upload(file, sheet) {
      const res = await uploadData(file, sheet)
      if (res && res.needSheet) return res
      const { source } = res
      await this.load()
      await this.select(`${source.type}:${source.name}`)
      return res
    },
    async paste(text) {
      const { source } = await pasteData(text)
      await this.load()
      await this.select(`${source.type}:${source.name}`)
    },
    async remove(id) {
      await deleteData(id)
      await this.load()
    }
  }
})
