// Glyph - 图库 store：保存当前绘图、管理槽位，供拼图面板使用
// 图库按项目隔离：条目带 project 字段；旧条目（无 project）对所有项目可见
import { defineStore } from 'pinia'
import { getPins, savePin, updatePin, deletePin, renamePin, saveCodePin, openPin } from '../api'
import { useSpecStore } from './spec'

export const usePinStore = defineStore('pins', {
  state: () => ({
    all: [],          // 全部图库条目 [{id,label,project,t,src,srcType,layers}]
    loading: false,
    saving: false
  }),
  getters: {
    // 当前项目可见的条目（旧的全局条目也显示，避免升级后"图库突然空了"）
    items(state) {
      const spec = useSpecStore()
      const pid = spec.projectId || ''
      return state.all.filter(p => !p.project || p.project === pid)
    },
    byId() {
      return Object.fromEntries(this.items.map(p => [p.id, p]))
    }
  },
  actions: {
    async load() {
      this.loading = true
      try {
        const { pins } = await getPins()
        this.all = pins || []
      } finally {
        this.loading = false
      }
    },
    // 把当前画布存入图库。
    // 若画布是「从某个图库条目打开并编辑」而来（spec.sourcePinId），
    // mode='update' 会覆盖那条（标签不变），mode='new' 则另存为新条目。
    // 默认 auto：有来源就更新，否则新建。
    async saveCurrent(label = null, mode = 'auto') {
      const spec = useSpecStore()
      const obj = JSON.parse(JSON.stringify(spec.spec))
      delete obj.combine       // 图库条目永远是单图
      this.saving = true
      try {
        const wantUpdate = mode === 'update' || (mode === 'auto' && !!spec.sourcePinId)
        if (wantUpdate && spec.sourcePinId) {
          const res = await updatePin(spec.sourcePinId, JSON.stringify(obj), label, spec.projectId)
          if (!res.ok) throw new Error(res.error || '更新失败')
          this.all = res.pins || []
          // 后端在条目已被删除时会回退为新建，这里同步记住新 id
          spec.sourcePinId = res.id
          spec.sourcePinLabel = this.all.find(p => p.id === res.id)?.label || spec.sourcePinLabel
          return { id: res.id, created: !!res.created }
        }
        const res = await savePin(JSON.stringify(obj), label, spec.projectId)
        if (!res.ok) throw new Error(res.error || '保存失败')
        this.all = res.pins || []
        // 另存后，画布对应的就是新条目
        spec.sourcePinId = res.id
        spec.sourcePinLabel = this.all.find(p => p.id === res.id)?.label || ''
        return { id: res.id, created: true }
      } finally {
        this.saving = false
      }
    },
    async saveCode({ label, code, packages, source, prep, renderOpts, pngUrl }) {
      this.saving = true
      try {
        const res = await saveCodePin({ label, code, packages, source, prep, renderOpts, pngUrl })
        if (res.ok) { this.all = res.pins || []; return res.id }
        throw new Error(res.error || '保存失败')
      } finally { this.saving = false }
    },
    async openCode(id) {
      return await openPin(id)
    },
    async remove(id) {
      const res = await deletePin(id)
      if (res.ok) this.all = res.pins || []
    },
    // 重命名图库条目（只改显示名，不影响规格与缩略图）
    async rename(id, label) {
      const res = await renamePin(id, label)
      if (!res.ok) throw new Error(res.error || '重命名失败')
      this.all = res.pins || []
      return res.label
    }
  }
})
