import { createApp } from 'vue'
import { createPinia } from 'pinia'
import App from './App.vue'
import router from './router'
import { useSyncStore } from './stores/sync'
import 'vant/lib/index.css'
import './styles/global.css'

const app = createApp(App)
const pinia = createPinia()
app.use(pinia)
app.use(router)
app.mount('#app')

void useSyncStore(pinia).bootstrapAutoDownload()
