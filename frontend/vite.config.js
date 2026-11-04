import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 5180,
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:4321',
        changeOrigin: true,
        // 关键：禁用 keep-alive，避免 R 后端重启后代理复用失效 socket
        agent: false,
        https: false
      }
    }
  },
  build: {
    outDir: '../dist',
    emptyOutDir: true,
    // plotly（4.7MB）与 CodeMirror 都是按需 import()，交给 rollup 自然分包；
    // 之前手写 manualChunks 会生成空 chunk，还会把 plotly 变成入口的静态依赖被预加载。
    chunkSizeWarningLimit: 6000
  }
})
