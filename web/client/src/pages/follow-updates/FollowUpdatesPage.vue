<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRouter } from 'vue-router'
import ComicCard from '@/components/ComicCard.vue'
import { getComicSources, listFavorites, listFolders, listHistory } from '@/services/server-db'
import { useSettingsStore } from '@/stores/settings'
import type { ComicSource, FavoriteFolder, FavoriteItem, History } from '@/types'
import { resolveSourceKey } from '@/utils/source'

const router = useRouter()
const settingsStore = useSettingsStore()
const folders = ref<FavoriteFolder[]>([])
const sources = ref<ComicSource[]>([])
const favorites = ref<FavoriteItem[]>([])
const histories = ref<History[]>([])
const loading = ref(false)
const activeTab = ref<'updates' | 'unread' | 'ended'>('updates')

const selectedFolder = computed(() => settingsStore.settings.followUpdatesFolder)
const hasFolder = computed(() => Boolean(selectedFolder.value))
const historyKeys = computed(() => {
  const keys = new Set<string>()
  for (const item of histories.value) {
    keys.add(`${item.id}\u0000${item.type}`)
  }
  return keys
})

const sortedFavorites = computed(() => {
  return [...favorites.value].sort((a, b) => compareUpdateTime(a.lastUpdateTime, b.lastUpdateTime))
})
const updateItems = computed(() => sortedFavorites.value.filter(item => item.hasNewUpdate))
const unreadItems = computed(() => sortedFavorites.value.filter(item => !historyKeys.value.has(`${item.id}\u0000${item.type}`)))
const endedItems = computed(() => sortedFavorites.value.filter(isEndedComic))
const currentItems = computed(() => {
  if (activeTab.value === 'unread') return unreadItems.value
  if (activeTab.value === 'ended') return endedItems.value
  return updateItems.value
})
const gridStyle = computed(() => {
  const scale = Number(settingsStore.settings.thumbnailSize || 1)
  return settingsStore.settings.thumbnailMode === 'brief'
    ? {
        '--tile-scale': String(scale),
        gridTemplateColumns: `repeat(auto-fill, minmax(96px, ${Math.round(192 * scale)}px))`,
      }
    : {
        '--tile-scale': String(scale),
        gridTemplateColumns: 'repeat(auto-fit, minmax(min(100%, 360px), 1fr))',
      }
})

onMounted(async () => {
  await settingsStore.loadSettings()
  await loadFoldersAndSources()
  await loadFollowData()
})

async function loadFoldersAndSources() {
  const [folderList, sourceList] = await Promise.all([listFolders(), getComicSources()])
  folders.value = folderList
  sources.value = sourceList
}

async function loadFollowData() {
  loading.value = true
  try {
    const folder = selectedFolder.value
    if (!folder || !folders.value.some(item => item.name === folder)) {
      favorites.value = []
      histories.value = []
      if (folder) settingsStore.update('followUpdatesFolder', null)
      return
    }
    const [favoriteItems, historyItems] = await Promise.all([
      listFavorites(folder),
      loadAllHistory(),
    ])
    favorites.value = favoriteItems
    histories.value = historyItems
  } finally {
    loading.value = false
  }
}

async function loadAllHistory(): Promise<History[]> {
  const items: History[] = []
  let offset = 0
  let total = Number.POSITIVE_INFINITY
  while (offset < total) {
    const page = await listHistory(500, offset)
    items.push(...page.items)
    total = page.total
    if (page.items.length === 0 || page.items.length < 500) break
    offset += page.items.length
  }
  return items
}

function compareUpdateTime(a?: string | null, b?: string | null) {
  const aTime = parseUpdateTime(a)
  const bTime = parseUpdateTime(b)
  if (aTime == null && bTime == null) return 0
  if (aTime == null) return 1
  if (bTime == null) return -1
  return bTime - aTime
}

function parseUpdateTime(value?: string | null): number | null {
  if (!value) return null
  const timestamp = Date.parse(value)
  return Number.isNaN(timestamp) ? null : timestamp
}

function isEndedComic(item: FavoriteItem): boolean {
  const text = [
    item.status,
    ...(Array.isArray(item.tags) ? item.tags : []),
  ].filter(Boolean).join(' ').toLowerCase()
  if (!text) return false
  if (text.includes('ongoing') || text.includes('连载')) return false
  return text.includes('completed') ||
    text.includes('finished') ||
    text.includes('ended') ||
    text.includes('完结') ||
    text.includes('已完结')
}

function chooseFolder(folder: FavoriteFolder) {
  settingsStore.update('followUpdatesFolder', folder.name)
  loadFollowData()
}

function sourceNameFor(item: FavoriteItem) {
  const key = resolveSourceKey(item, sources.value)
  const source = sources.value.find(s => s.key === key || s.canonicalKey === key)
  return source?.name || source?.sourceName || source?.displayName || key
}


</script>

<template>
  <div class="follow-page">
    <van-nav-bar title="追更" left-arrow @click-left="router.back()" />

    <div v-if="!hasFolder" class="choose-state">
      <van-empty description="选择追更文件夹">
        <div class="folder-list">
          <button
            v-for="folder in folders"
            :key="folder.id"
            class="folder-button"
            @click="chooseFolder(folder)"
          >
            <van-icon name="folder-o" />
            <span>{{ folder.name }}</span>
          </button>
        </div>
      </van-empty>
    </div>

    <div v-else class="follow-content">
      <div class="folder-bar">
        <div class="folder-title">
          <span>{{ selectedFolder }}</span>
          <small>{{ favorites.length }} 项</small>
        </div>
        <van-popover placement="bottom-end" :actions="folders.map(folder => ({ text: folder.name, folder }))" @select="(action: any) => chooseFolder(action.folder)">
          <template #reference>
            <van-button size="small" icon="exchange">切换</van-button>
          </template>
        </van-popover>
      </div>

      <van-tabs v-model:active="activeTab" sticky>
        <van-tab name="updates" :title="`更新 ${updateItems.length}`" />
        <van-tab name="unread" :title="`未读 ${unreadItems.length}`" />
        <van-tab name="ended" :title="`完结 ${endedItems.length}`" />
      </van-tabs>

      <van-loading v-if="loading" class="loading-state" />
      <div v-else-if="currentItems.length" class="comic-grid" :style="gridStyle">
        <div v-for="item in currentItems" :key="`${item.folder}:${item.type}:${item.id}`" class="comic-card">
          <ComicCard
            :comic="item"
            :source-key="resolveSourceKey(item, sources)"
            :source-name="sourceNameFor(item)"
          />
        </div>
      </div>
      <van-empty v-else description="暂无内容" />
    </div>
  </div>
</template>

<style scoped>
.follow-page {
  min-height: 100%;
  background: #fff;
}

.choose-state {
  padding: 16px;
}

.folder-list {
  width: min(420px, calc(100vw - 48px));
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.folder-button {
  height: 44px;
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 0 14px;
  border: 0.6px solid #e5e5e5;
  border-radius: 8px;
  background: #fff;
  color: #222;
  font-size: 14px;
  text-align: left;
}

.folder-button span {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.follow-content {
  display: flex;
  flex-direction: column;
}

.folder-bar {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 10px 16px;
  border-bottom: 0.6px solid #eee;
}

.folder-title {
  min-width: 0;
  display: flex;
  align-items: baseline;
  gap: 8px;
}

.folder-title span {
  min-width: 0;
  font-size: 16px;
  font-weight: 600;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.folder-title small {
  color: #888;
  white-space: nowrap;
}

.loading-state {
  margin: 48px auto;
}

.comic-grid {
  display: grid;
  gap: 10px;
  padding: 12px;
  align-items: start;
}

.comic-card {
  min-width: 0;
}
</style>
