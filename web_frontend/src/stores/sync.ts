import { defineStore } from 'pinia'
import { ref } from 'vue'
import { getWebDavConfig, saveWebDavConfig as apiSaveConfig, triggerDownload, triggerUpload } from '../services/sync'

export const useSyncStore = defineStore('sync', () => {
  const isDownloading = ref(false)
  const isUploading = ref(false)
  const lastError = ref<string | null>(null)
  const isEnabled = ref(false)
  const config = ref({ url: '', user: '', autoSync: false })

  async function loadConfig() {
    try {
      const data = await getWebDavConfig()
      config.value = { url: data.url || '', user: data.user || '', autoSync: data.autoSync || false }
      isEnabled.value = !!(data.url && data.user && data.autoSync)
    } catch (e: any) {
      lastError.value = e.message
    }
  }

  async function download() {
    isDownloading.value = true
    lastError.value = null
    try {
      await triggerDownload()
    } catch (e: any) {
      lastError.value = e.message
    } finally {
      isDownloading.value = false
    }
  }

  async function upload() {
    isUploading.value = true
    lastError.value = null
    try {
      await triggerUpload()
    } catch (e: any) {
      lastError.value = e.message
    } finally {
      isUploading.value = false
    }
  }

  async function saveConfig(url: string, user: string, pass: string, autoSync: boolean) {
    await apiSaveConfig(url, user, pass, autoSync)
    config.value = { url, user, autoSync }
    isEnabled.value = !!(url && user)
  }

  return { isDownloading, isUploading, lastError, isEnabled, config, loadConfig, download, upload, saveConfig }
})
