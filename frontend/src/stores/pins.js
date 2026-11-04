// ggplotGUI - 图库 store：保存当前绘图、管理槽位，供拼图面板使用
import { defineStore } from 'pinia'
import { getPins, savePin, deletePin } from '../api'
import { useSpecStore } from './spec'

export const usePinStore = defineStore('pins', {
  state: () => ({
    items: [],        // [{id,label,t,src,srcType,layers}]
    loading: false,
    saving: false
  }),
  getters: {
    byId(state) {
      return Object.fromEntries(state.items.map(p => [p.id, p]))
    }
  },
  actions: {
    async load() {
      this.loading = true
      try {
        const { pins } = await getPins()
        this.items = pins || []
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
        const res = await savePin(JSON.stringify(obj), label)
        if (res.ok) {
          this.items = res.pins || []
          return res.id
        }
        throw new Error(res.error || '保存失败')
      } finally {
        this.saving = false
      }
    },
    async remove(id) {
      const res = await deletePin(id)
      if (res.ok) this.items = res.pins || []
    }
  }
})
