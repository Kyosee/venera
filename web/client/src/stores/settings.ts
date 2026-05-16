import { defineStore } from 'pinia'
import { ref } from 'vue'
import { apiPost } from '../services/api'

export interface SettingsData {
  thumbnailMode: string
  thumbnailSize: number
  showFavBadge: boolean
  showHistoryBadge: boolean
  reverseChapters: boolean
  defaultSearchTarget: string
  autoLangFilter: string
  initialPage: string
  comicListMode: string
  deviceSpecific: boolean
  tapToTurn: boolean
  reverseTap: boolean
  pageAnimation: boolean
  readingMode: string
  continuousChapter: boolean
  autoPageEnabled: boolean
  autoPageInterval: number
  volumeKeyTurn: boolean
  scrollSpeed: number
  doubleTapZoom: boolean
  longPressZoom: boolean
  longPressZoomPos: string
  limitImageWidth: boolean
  showTimeAndBattery: boolean
  showStatusBar: boolean
  quickFavImage: string
  preloadCount: number
  showPageNum: boolean
  showChapterComments: boolean
  showChapterCommentsAtEnd: boolean
  showSingleImageOnFirstPage: boolean
  readerScreenPicNumberForLandscape: number
  readerScreenPicNumberForPortrait: number
  themeMode: string
  themeColor: string
  showLocalFirst: boolean
  autoClosePanel: boolean
  addNewTo: string
  moveAfterRead: string
  quickFav: string
  clickFav: string
  language: string
  downloadThreads: number
  ignoreCertErrors: boolean
  followUpdatesFolder: string | null
}

const STORAGE_KEY = 'venera_settings'

const DEFAULTS: SettingsData = {
  thumbnailMode: 'detailed',
  thumbnailSize: 1,
  showFavBadge: true,
  showHistoryBadge: false,
  reverseChapters: false,
  defaultSearchTarget: '',
  autoLangFilter: 'none',
  initialPage: '0',
  comicListMode: 'paging',
  deviceSpecific: false,
  tapToTurn: true,
  reverseTap: false,
  pageAnimation: true,
  readingMode: 'galleryLeftToRight',
  continuousChapter: true,
  autoPageEnabled: false,
  autoPageInterval: 5,
  volumeKeyTurn: true,
  scrollSpeed: 1,
  doubleTapZoom: true,
  longPressZoom: true,
  longPressZoomPos: 'press',
  limitImageWidth: true,
  showTimeAndBattery: true,
  showStatusBar: false,
  quickFavImage: 'No',
  preloadCount: 4,
  showPageNum: true,
  showChapterComments: true,
  showChapterCommentsAtEnd: false,
  showSingleImageOnFirstPage: false,
  readerScreenPicNumberForLandscape: 1,
  readerScreenPicNumberForPortrait: 1,
  themeMode: 'system',
  themeColor: 'system',
  showLocalFirst: true,
  autoClosePanel: false,
  addNewTo: 'end',
  moveAfterRead: 'none',
  quickFav: '',
  clickFav: 'viewDetail',
  language: 'system',
  downloadThreads: 5,
  ignoreCertErrors: false,
  followUpdatesFolder: null,
}

const nativeToWeb: Record<string, keyof SettingsData> = {
  comicDisplayMode: 'thumbnailMode',
  comicTileScale: 'thumbnailSize',
  showFavoriteStatusOnTile: 'showFavBadge',
  showHistoryStatusOnTile: 'showHistoryBadge',
  reverseChapterOrder: 'reverseChapters',
  defaultSearchTarget: 'defaultSearchTarget',
  autoAddLanguageFilter: 'autoLangFilter',
  initialPage: 'initialPage',
  comicListDisplayMode: 'comicListMode',
  enableTapToTurnPages: 'tapToTurn',
  reverseTapToTurnPages: 'reverseTap',
  enablePageAnimation: 'pageAnimation',
  readerMode: 'readingMode',
  enableContinuousChapterReading: 'continuousChapter',
  autoPageTurningInterval: 'autoPageInterval',
  readerScrollSpeed: 'scrollSpeed',
  enableDoubleTapToZoom: 'doubleTapZoom',
  enableLongPressToZoom: 'longPressZoom',
  longPressZoomPosition: 'longPressZoomPos',
  limitImageWidth: 'limitImageWidth',
  enableClockAndBatteryInfoInReader: 'showTimeAndBattery',
  showSystemStatusBar: 'showStatusBar',
  quickCollectImage: 'quickFavImage',
  preloadImageCount: 'preloadCount',
  showPageNumberInReader: 'showPageNum',
  showChapterComments: 'showChapterComments',
  showChapterCommentsAtEnd: 'showChapterCommentsAtEnd',
  showSingleImageOnFirstPage: 'showSingleImageOnFirstPage',
  readerScreenPicNumberForLandscape: 'readerScreenPicNumberForLandscape',
  readerScreenPicNumberForPortrait: 'readerScreenPicNumberForPortrait',
  theme_mode: 'themeMode',
  color: 'themeColor',
  localFavoritesFirst: 'showLocalFirst',
  autoCloseFavoritePanel: 'autoClosePanel',
  newFavoriteAddTo: 'addNewTo',
  moveFavoriteAfterRead: 'moveAfterRead',
  quickFavorite: 'quickFav',
  onClickFavorite: 'clickFav',
  language: 'language',
  downloadThreads: 'downloadThreads',
  ignoreBadCertificate: 'ignoreCertErrors',
  followUpdatesFolder: 'followUpdatesFolder',
}

const webToNative = Object.fromEntries(
  Object.entries(nativeToWeb).map(([nativeKey, webKey]) => [webKey, nativeKey])
) as Record<keyof SettingsData, string>

function fromNativeSettings(raw: Record<string, any>): SettingsData {
  const next = { ...DEFAULTS }
  for (const [nativeKey, webKey] of Object.entries(nativeToWeb)) {
    if (raw[nativeKey] !== undefined) {
      ;(next as Record<string, any>)[webKey] = raw[nativeKey]
    }
  }
  for (const key of Object.keys(DEFAULTS) as Array<keyof SettingsData>) {
    if (raw[key] !== undefined) {
      ;(next as Record<string, any>)[key] = raw[key]
    }
  }
  next.deviceSpecific = raw.deviceSpecific === true || raw.deviceSpecificSettings?.enabled === true
  return next
}

function toNativeSettings(data: SettingsData, previous: Record<string, any> = {}) {
  const next = { ...previous }
  for (const key of Object.keys(data) as Array<keyof SettingsData>) {
    const nativeKey = webToNative[key]
    next[nativeKey ?? key] = data[key]
  }
  return next
}

export const useSettingsStore = defineStore('settings', () => {
  const settings = ref<SettingsData>({ ...DEFAULTS })
  const loaded = ref(false)
  const saving = ref(false)
  const rawAppdata = ref<Record<string, any>>({})

  function loadFromLocalStorage(): Partial<SettingsData> {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      return raw ? JSON.parse(raw) : {}
    } catch { return {} }
  }

  function saveToLocalStorage(data: SettingsData) {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(data))
  }

  async function loadSettings() {
    try {
      const res = await apiPost<any>('/api/server-db/appdata')
      const appdata = res?.data ?? res ?? {}
      rawAppdata.value = appdata
      settings.value = fromNativeSettings(appdata.settings ?? appdata)
      saveToLocalStorage(settings.value)
    } catch {
      const local = loadFromLocalStorage()
      settings.value = { ...DEFAULTS, ...local }
    }
    loaded.value = true
  }

  async function saveSettings() {
    saving.value = true
    saveToLocalStorage(settings.value)
    try {
      const current = rawAppdata.value
      const nativeSettings = toNativeSettings(settings.value, current.settings ?? {})
      await apiPost('/api/server-db/appdata/save', {
        data: { ...current, settings: nativeSettings, searchHistory: current.searchHistory ?? [] },
      })
      rawAppdata.value = { ...current, settings: nativeSettings }
    } catch {
      // localStorage remains the offline fallback.
    } finally {
      saving.value = false
    }
  }

  let debounceTimer: ReturnType<typeof setTimeout> | null = null
  function scheduleSave() {
    if (debounceTimer) clearTimeout(debounceTimer)
    debounceTimer = setTimeout(() => saveSettings(), 500)
  }

  function update<K extends keyof SettingsData>(key: K, value: SettingsData[K]) {
    settings.value[key] = value
    scheduleSave()
  }

  return { settings, loaded, saving, loadSettings, saveSettings, update }
})
