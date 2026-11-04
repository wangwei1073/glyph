// 界面状态：右侧页签 + 左右面板折叠（持久化到 localStorage）
import { defineStore } from 'pinia'

const LS_KEY = 'ggplotgui-ui'

function loadStored() {
  try {
    const raw = JSON.parse(localStorage.getItem(LS_KEY) || '{}')
    return raw && typeof raw === 'object' ? raw : {}
  } catch {
    return {}
  }
}

export const useUiStore = defineStore('ui', {
  state: () => ({ tab: 'layers', leftOpen: true, rightOpen: true, statsOpen: false, statsHeight: 304, ...loadStored() }),
  actions: {
    setTab(tab) {
      this.tab = tab
      this.persist()
    },
    toggleLeft() {
      this.leftOpen = !this.leftOpen
      this.persist()
    },
    toggleRight() {
      this.rightOpen = !this.rightOpen
      this.persist()
    },
    toggleStats() {
      this.statsOpen = !this.statsOpen
      this.persist()
    },
    // 抽屉高度可拖拽调整，范围 160-900px
    setStatsHeight(h) {
      this.statsHeight = Math.min(900, Math.max(160, Math.round(h)))
      this.persist()
    },
    persist() {
      try {
        localStorage.setItem(LS_KEY, JSON.stringify({
          tab: this.tab, leftOpen: this.leftOpen, rightOpen: this.rightOpen,
          statsOpen: this.statsOpen, statsHeight: this.statsHeight
        }))
      } catch { /* 隐私模式下忽略 */ }
    }
  }
})
