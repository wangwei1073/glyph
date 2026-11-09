// Glyph - 数据源 store
import { defineStore } from 'pinia'
import { getSources, getColumns, uploadData, pasteData, deleteData, previewData } from '../api'
import { useSpecStore } from './spec'

export const useDataStore = defineStore('data', {
  state: () => ({
    sources: [],
    srcKey: 'none',          // 'dataset:mpg' | 'user:u1' | 'none'
    columns: [],             // [{name,type,nUnique,preview...}]
    preview: { rows: [], nrow: 0, ncol: 0 },
    previewLoading: false
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
      try {
        const sd = useSpecStore().spec.data
        const prep = {
          filter: sd.filter || '', mutate: sd.mutate || [],
          sample: sd.sample, seed: sd.seed,
          filterDisabled: !!sd.filterDisabled, sampleDisabled: !!sd.sampleDisabled, types: sd.types || [], outliers: sd.outliers || [], fillna: sd.fillna || [], dropnaCols: sd.dropnaCols || [], dropnaHow: sd.dropnaHow || 'any', dropnaDisabled: !!sd.dropnaDisabled, dedupCols: sd.dedupCols || [], dedupEnabled: !!sd.dedupEnabled
        }
        const source = c.type === 'dataset'
          ? { type: 'dataset', name: c.name }
          : { type: 'user', id: c.name }
        const { columns } = await getColumns(source, prep)
        this.columns = columns
      } catch {
        // 加工表达式暂时不合法时回退到原始列，避免列面板突然清空
        try {
          const src = c.type === 'dataset'
            ? { type: 'dataset', name: c.name }
            : { type: 'user', id: c.name }
          const { columns } = await getColumns(src)
          this.columns = columns
        } catch { this.columns = [] }
      }
      await this.refreshPreview()
      // 换了数据源后，清掉指向旧列的 aes 映射，避免渲染报「找不到对象」
      try { useSpecStore().pruneMappings(this.colNames) } catch { /* 循环依赖兜底 */ }
    },
    async refreshPreview() {
      const c = this.current
      if (!c || c.type === 'none') return
      this.previewLoading = true
      try {
        const src = c.type === 'dataset' ? { type: 'dataset', name: c.name }
          : { type: 'user', id: c.name }
        // 数据加工参数以 spec.data 为准（单一事实来源）
        const sd = useSpecStore().spec.data
        const prep = { filter: sd.filter || '', mutate: sd.mutate || [], sample: sd.sample, seed: sd.seed, filterDisabled: !!sd.filterDisabled, sampleDisabled: !!sd.sampleDisabled, types: sd.types || [], outliers: sd.outliers || [], fillna: sd.fillna || [], dropnaCols: sd.dropnaCols || [], dropnaHow: sd.dropnaHow || 'any', dropnaDisabled: !!sd.dropnaDisabled, dedupCols: sd.dedupCols || [], dedupEnabled: !!sd.dedupEnabled }
        this.preview = await previewData(src, prep)
      } catch (e) {
        this.preview = { rows: [], nrow: 0, ncol: 0, error: e.message }
      } finally {
        this.previewLoading = false
      }
    },
    async upload(file) {
      const { source } = await uploadData(file)
      await this.load()
      await this.select(`${source.type}:${source.name}`)
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
