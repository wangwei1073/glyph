// ggplotGUI - 图库 store：保存当前绘图、管理槽位，供拼图面板使用
// 图库按项目隔离：条目带 project 字段；旧条目（无 project）对所有项目可见
import { defineStore } from 'pinia'
import { getPins, savePin, deletePin } from '../api'
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
    async saveCurrent(label = null) {
      const spec = useSpecStore()
      const obj = JSON.parse(JSON.stringify(spec.spec))
      delete obj.combine       // 图库条目永远是单图
      this.saving = true
      try {
        const res = await savePin(JSON.stringify(obj), label, spec.projectId)
        if (res.ok) {
          this.all = res.pins || []
          return res.id
        }
        throw new Error(res.error || '保存失败')
      } finally {
        this.saving = false
      }
    },
    async remove(id) {
      const res = await deletePin(id)
      if (res.ok) this.all = res.pins || []
    }
  }
})
