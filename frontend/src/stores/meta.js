// ggplotGUI - 元数据 store（自省注册表，一次加载）
import { defineStore } from 'pinia'
import { getMeta } from '../api'

const GEOM_GROUP_ORDER = ['点与线', '条形与频数', '分布', '区间与误差', '文本与标签',
  '二维分箱与密度', '瓦片与栅格', '多边形与地图', '参考线', '特殊', '扩展', '其他']

export const useMetaStore = defineStore('meta', {
  state: () => ({
    loaded: false,
    error: null,
    version: '',
    ggplot2Version: '',
    geoms: [],
    geomGroups: [],
    geomShapeGroups: [],
    shapeOrder: [],
    geomByName: {},
    stats: [],
    statByName: {},
    positions: [],
    positionByName: {},
    scalesByAes: {},
    scaleAesOrder: [],
    scaleCommonParams: [],
    coords: [],
    coordByName: {},
    facets: null,
    guides: [],
    guideByName: {},
    themes: [],
    themeByName: {},
    themeElements: [],
    themeElementsGrouped: [],
    themePropSchema: {},
    themeUnitOptions: [],
    shapeOptions: [],
    linetypeOptions: [],
    fonts: [],
    aesMeta: [],
    aesByName: {},
    annotations: [],
    ext: {}
  }),
  actions: {
    async load() {
      if (this.loaded) return
      try {
        const { meta } = await getMeta()
        Object.assign(this, meta)
        this.ext = meta.extensions || {}
        this.version = meta.ggplot2Version

        // geom 分组
        const groups = new Map()
        for (const g of meta.geoms) {
          if (!groups.has(g.group)) groups.set(g.group, [])
          groups.get(g.group).push(g)
        }
        this.geomGroups = [...groups.keys()].sort((a, b) => {
          const ia = GEOM_GROUP_ORDER.indexOf(a), ib = GEOM_GROUP_ORDER.indexOf(b)
          return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
        }).map(name => ({ name, geoms: groups.get(name) }))

        // 同一批 geom 的第二种分组：按数据形态（cheatsheet 式）
        const order = meta.shapeOrder || []
        const sgroups = new Map()
        for (const g of meta.geoms) {
          const k = g.shape || '其他'
          if (!sgroups.has(k)) sgroups.set(k, [])
          sgroups.get(k).push(g)
        }
        this.shapeOrder = order
        this.geomShapeGroups = [...sgroups.keys()].sort((a, b) => {
          const ia = order.indexOf(a), ib = order.indexOf(b)
          return (ia < 0 ? 99 : ia) - (ib < 0 ? 99 : ib)
        }).map(name => ({ name, geoms: sgroups.get(name) }))

        this.geomByName = Object.fromEntries(meta.geoms.map(g => [g.name, g]))

        this.statByName = Object.fromEntries(meta.stats.map(s => [s.name, s]))
        this.positionByName = Object.fromEntries(meta.positions.map(p => [p.name, p]))
        this.coordByName = Object.fromEntries(meta.coords.map(c => [c.name, c]))
        this.guideByName = Object.fromEntries(meta.guides.map(g => [g.name, g]))
        this.themeByName = Object.fromEntries(meta.themes.map(t => [t.name, t]))
        this.aesByName = Object.fromEntries(meta.aesMeta.map(a => [a.name, a]))

        // 标度按 aes 分组；核心类型排前，扩展在后
        const byAes = {}
        for (const s of meta.scales) {
          (byAes[s.aes] = byAes[s.aes] || []).push(s)
        }
        for (const aes of Object.keys(byAes)) {
          byAes[aes].sort((a, b) => {
            const core = (x) => (x.package === 'ggplot2' ? 0 : 1) * 1000 +
              (x.type === 'continuous' || x.type === 'discrete' || x.type === 'manual' ? -500 : 0)
            return core(a) - core(b) || a.type.localeCompare(b.type) || a.fn.localeCompare(b.fn)
          })
        }
        this.scalesByAes = byAes
        this.scaleAesOrder = meta.scaleAesOrder || []
        this.scaleCommonParams = Object.values(meta.scaleCommonParams || {})

        // 主题元素分组
        const groupLabels = { plot: '图区 plot', panel: '面板 panel', axis: '坐标轴 axis', legend: '图例 legend', strip: '条带 strip', base: '基础（全局继承）' }
        const tg = {}
        for (const el of meta.themeElements) {
          (tg[el.group] = tg[el.group] || []).push(el)
        }
        this.themeElementsGrouped = Object.keys(tg).sort((a, b) =>
          (groupLabels[a] ? Object.keys(groupLabels).indexOf(a) : 50) -
          (groupLabels[b] ? Object.keys(groupLabels).indexOf(b) : 50)
        ).map(g => ({ key: g, label: groupLabels[g] || g, elements: tg[g].sort((a, b) => a.name.localeCompare(b.name)) }))
        this.themePropSchema = meta.themePropSchema || {}
        this.themeUnitOptions = meta.themeUnitOptions || []
        this.loaded = true
      } catch (e) {
        this.error = e.message
        throw e
      }
    },
    // 某图层可用的 aes 列表（required + optional）
    layerAes(geomName) {
      const g = this.geomByName[geomName]
      if (!g) return []
      return [...(g.aes.required || []), ...(g.aes.optional || [])]
    },
    layerParams(geomName) {
      const g = this.geomByName[geomName]
      return g ? Object.values(g.params || {}) : []
    },
    layerStatParams(geomName) {
      const g = this.geomByName[geomName]
      return g ? Object.values(g.statParams || {}) : []
    },
    statParamsOf(statName) {
      const s = this.statByName[statName]
      return s ? Object.values(s.params || {}) : []
    },
    positionParamsOf(name) {
      const p = this.positionByName[name]
      return p ? Object.values(p.params || {}) : []
    },
    scaleTypesOf(aes) {
      return this.scalesByAes[aes] || []
    },
    themeElementsOf(type) {
      return this.themePropSchema[type] || []
    }
  }
})
