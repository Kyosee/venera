import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import Components from 'unplugin-vue-components/vite'
import { VantResolver } from '@vant/auto-import-resolver'

export default defineConfig({
  base: '/',
  resolve: {
    alias: { '@': '/src' }
  },
  build: {
    outDir: '../build/web-vue',
    emptyOutDir: true,
    rollupOptions: {
      output: {
        manualChunks: {
          'vendor-vue': ['vue', 'vue-router', 'pinia'],
          'vendor-vant': ['vant'],
        }
      }
    }
  },
  server: {
    proxy: {
      '/api': 'http://localhost:60098',
      '/sync': 'http://localhost:60098',
    }
  },
  plugins: [
    vue(),
    Components({ resolvers: [VantResolver()] }),
  ]
})
