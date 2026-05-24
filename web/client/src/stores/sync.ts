import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import { getWebDavConfig, saveWebDavConfig as apiSaveConfig, triggerDownload, triggerUpload } from '../services/sync'
import { useSettingsStore } from './settings'

interface SyncConfig {
  url: string
  user: string
  pass: string
  autoSync: boolean
  disableSyncFields: string
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error || '未知错误')
}

export const useSyncStore = defineStore('sync', () => {
  const isDownloading = ref(false)
  const isUploading = ref(false)
  const lastError = ref<string | null>(null)
  const configured = ref(false)
  const config = ref<SyncConfig>({ url: '', user: '', pass: '', autoSync: false, disableSyncFields: '' })
  const isEnabled = computed(() => configured.value)
  const autoSyncEnabled = computed(() => configured.value && config.value.autoSync)
  let autoUploadTimer: ReturnType<typeof setTimeout> | null = null
  let startupDownloadPromise: Promise<void> | null = null

  function applyConfig(data: Awaited<ReturnType<typeof getWebDavConfig>> | null) {
    const hasConfig = !!(data && (data.configured === true || (data.url && data.user)))
    configured.value = hasConfig
    config.value = {
      url: hasConfig ? data?.url || '' : '',
      user: hasConfig ? data?.user || '' : '',
      pass: hasConfig ? data?.pass || '' : '',
      autoSync: hasConfig && data?.autoSync === true,
      disableSyncFields: hasConfig ? data?.disableSyncFields || '' : '',
    }
  }

  async function loadConfig() {
    try {
      const data = await getWebDavConfig()
      applyConfig(data)
    } catch (error) {
      applyConfig(null)
      lastError.value = errorMessage(error)
    }
  }

  async function download() {
    isDownloading.value = true
    lastError.value = null
    try {
      await triggerDownload()
      await useSettingsStore().loadSettings()
    } catch (error) {
      lastError.value = errorMessage(error)
      throw error
    } finally {
      isDownloading.value = false
    }
  }

  async function upload(options?: { force?: boolean }) {
    isUploading.value = true
    lastError.value = null
    try {
      await triggerUpload(options)
    } catch (error) {
      const msg = errorMessage(error)
      if (msg.includes('INITIAL_SYNC_REQUIRED') || msg.includes('Initial sync not completed')) {
        lastError.value = '请先完成首次同步下载'
      } else if (msg.includes('FAVORITE_DB_EMPTY') || msg.includes('Favorite database is empty')) {
        lastError.value = '收藏数据为空，上传已阻止'
      } else {
        lastError.value = msg
      }
      throw error
    } finally {
      isUploading.value = false
    }
  }

  async function saveConfig(url: string, user: string, pass: string, autoSync: boolean, disableSyncFields = '') {
    const nextPass = pass || config.value.pass
    const data = await apiSaveConfig(url, user, nextPass, autoSync, disableSyncFields)
    applyConfig({ ...data, pass: data.pass || nextPass })
    if (autoSyncEnabled.value) {
      void bootstrapAutoDownload(true)
    }
  }

  function queueAutoUpload(delay = 1500) {
    if (!autoSyncEnabled.value) return
    if (autoUploadTimer) clearTimeout(autoUploadTimer)
    autoUploadTimer = setTimeout(() => {
      autoUploadTimer = null
      if (!autoSyncEnabled.value) return
      if (isDownloading.value || isUploading.value) {
        queueAutoUpload(1000)
        return
      }
      void upload().catch(() => {})
    }, delay)
  }

  async function bootstrapAutoDownload(force = false) {
    if (startupDownloadPromise && !force) return startupDownloadPromise
    startupDownloadPromise = (async () => {
      try {
        await loadConfig()
        if (autoSyncEnabled.value) {
          await download()
        }
      } catch (error) {
        lastError.value = errorMessage(error)
      } finally {
        if (force) startupDownloadPromise = null
      }
    })()
    return startupDownloadPromise
  }

  return {
    isDownloading,
    isUploading,
    lastError,
    isEnabled,
    configured,
    autoSyncEnabled,
    config,
    loadConfig,
    download,
    upload,
    saveConfig,
    queueAutoUpload,
    bootstrapAutoDownload,
  }
})
