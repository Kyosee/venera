<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { listImageFavorites } from '@/services/server-db'
import { imageProxyUrl } from '@/services/api'
import ProxiedImage from '@/components/ProxiedImage.vue'
import { showImagePreview } from 'vant'

interface ImageFavorite {
  id: string
  url: string
  sourceKey: string
  comicId: string
  comicTitle: string
  ep: number
  page: number
  tags?: string[]
  author?: string
}

const items = ref<ImageFavorite[]>([])
const loading = ref(true)
const searchQuery = ref('')
const isDesktop = ref(window.innerWidth >= 720)
const showStats = ref(false)
const activeStatTab = ref<'tags' | 'authors' | 'comics'>('tags')

function handleResize() {
  isDesktop.value = window.innerWidth >= 720
}

onMounted(async () => {
  window.addEventListener('resize', handleResize)
  await loadData()
})

onUnmounted(() => {
  window.removeEventListener('resize', handleResize)
})

async function loadData() {
  loading.value = true
  try {
    items.value = await listImageFavorites()
  } catch (e) {
    console.error('Failed to load image favorites', e)
  } finally {
    loading.value = false
  }
}

// Filtered items
const filteredItems = computed(() => {
  if (!searchQuery.value.trim()) return items.value
  const q = searchQuery.value.toLowerCase()
  return items.value.filter(item => {
    const matchTitle = item.comicTitle?.toLowerCase().includes(q)
    const matchAuthor = item.author?.toLowerCase().includes(q)
    const matchTags = item.tags?.some(t => t.toLowerCase().includes(q))
    return matchTitle || matchAuthor || matchTags
  })
})

// Statistics
const tagStats = computed(() => {
  const map = new Map<string, number>()
  items.value.forEach(item => {
    item.tags?.forEach(tag => map.set(tag, (map.get(tag) || 0) + 1))
  })
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, 30)
})

const authorStats = computed(() => {
  const map = new Map<string, number>()
  items.value.forEach(item => {
    if (item.author) map.set(item.author, (map.get(item.author) || 0) + 1)
  })
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, 20)
})

const comicStats = computed(() => {
  const map = new Map<string, number>()
  items.value.forEach(item => {
    if (item.comicTitle) map.set(item.comicTitle, (map.get(item.comicTitle) || 0) + 1)
  })
  return [...map.entries()].sort((a, b) => b[1] - a[1]).slice(0, 20)
})

function filterByTag(tag: string) {
  searchQuery.value = tag
  showStats.value = false
}
function filterByAuthor(author: string) {
  searchQuery.value = author
  showStats.value = false
}
function filterByComic(comic: string) {
  searchQuery.value = comic
  showStats.value = false
}

function openPreview(index: number) {
  const images = filteredItems.value.map(item => imageProxyUrl(item.url))
  showImagePreview({ images, startPosition: index, closeable: true })
}
</script>

<template>
  <div class="image-favorites-page">
    <van-nav-bar title="Image Favorites">
      <template #right>
        <van-icon
          name="chart-trending-o"
          size="20"
          @click="showStats = !showStats"
        />
      </template>
    </van-nav-bar>

    <div class="search-bar">
      <van-search
        v-model="searchQuery"
        placeholder="Search by tag, author, or comic"
        shape="round"
        clearable
      />
    </div>

    <!-- Statistics panel -->
    <div v-if="showStats && items.length > 0" class="stats-panel">
      <div class="stats-header">
        <span class="stats-title">Statistics</span>
        <span class="stats-total">{{ items.length }} images</span>
      </div>
      <div class="stats-tabs">
        <span
          :class="['stats-tab', { active: activeStatTab === 'tags' }]"
          @click="activeStatTab = 'tags'"
        >Tags</span>
        <span
          :class="['stats-tab', { active: activeStatTab === 'authors' }]"
          @click="activeStatTab = 'authors'"
        >Authors</span>
        <span
          :class="['stats-tab', { active: activeStatTab === 'comics' }]"
          @click="activeStatTab = 'comics'"
        >Comics</span>
      </div>
      <div class="stats-chips">
        <template v-if="activeStatTab === 'tags'">
          <van-tag v-for="[tag, count] in tagStats" :key="tag"
            plain type="primary" class="stat-chip" @click="filterByTag(tag)"
          >{{ tag }} ({{ count }})</van-tag>
          <span v-if="tagStats.length === 0" class="no-stats">No tags</span>
        </template>
        <template v-if="activeStatTab === 'authors'">
          <van-tag v-for="[author, count] in authorStats" :key="author"
            plain type="success" class="stat-chip" @click="filterByAuthor(author)"
          >{{ author }} ({{ count }})</van-tag>
          <span v-if="authorStats.length === 0" class="no-stats">No authors</span>
        </template>
        <template v-if="activeStatTab === 'comics'">
          <van-tag v-for="[comic, count] in comicStats" :key="comic"
            plain type="warning" class="stat-chip" @click="filterByComic(comic)"
          >{{ comic }} ({{ count }})</van-tag>
          <span v-if="comicStats.length === 0" class="no-stats">No comics</span>
        </template>
      </div>
    </div>

    <!-- Loading state -->
    <div v-if="loading" class="loading-container">
      <van-loading size="36px" vertical>Loading favorites...</van-loading>
    </div>

    <!-- Empty state -->
    <van-empty
      v-else-if="items.length === 0"
      image="search"
      description="No image favorites yet"
    />

    <!-- No search results -->
    <van-empty
      v-else-if="filteredItems.length === 0"
      image="search"
      :description="`No results for '${searchQuery}'`"
    />

    <!-- Image grid -->
    <div v-else class="image-grid" :class="{ desktop: isDesktop }">
      <div
        v-for="(item, index) in filteredItems"
        :key="item.id"
        class="grid-item"
        @click="openPreview(index)"
      >
        <ProxiedImage
          :src="item.url"
          :alt="item.comicTitle"
          class="grid-image"
        />
        <div class="grid-overlay">
          <span class="grid-title">{{ item.comicTitle }}</span>
          <span v-if="item.author" class="grid-author">{{ item.author }}</span>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.image-favorites-page {
  height: 100%;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}

.search-bar {
  padding: 0 8px;
  flex-shrink: 0;
}

.loading-container {
  flex: 1;
  display: flex;
  align-items: center;
  justify-content: center;
}

/* Statistics panel */
.stats-panel {
  margin: 0 12px 8px;
  padding: 12px;
  background: #f8f9fa;
  border-radius: 10px;
  flex-shrink: 0;
  max-height: 200px;
  overflow-y: auto;
}

.stats-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 8px;
}

.stats-title {
  font-size: 14px;
  font-weight: 600;
  color: #333;
}

.stats-total {
  font-size: 12px;
  color: #999;
}

.stats-tabs {
  display: flex;
  gap: 12px;
  margin-bottom: 10px;
}

.stats-tab {
  font-size: 12px;
  color: #999;
  cursor: pointer;
  padding: 2px 0;
  border-bottom: 2px solid transparent;
  transition: all 0.2s;
}

.stats-tab.active {
  color: #4f6ef7;
  border-bottom-color: #4f6ef7;
}

.stats-chips {
  display: flex;
  flex-wrap: wrap;
  gap: 6px;
}

.stat-chip {
  cursor: pointer;
  transition: opacity 0.2s;
}

.stat-chip:hover {
  opacity: 0.7;
}

.no-stats {
  font-size: 12px;
  color: #999;
}

/* Image grid */
.image-grid {
  flex: 1;
  overflow-y: auto;
  padding: 8px;
  display: grid;
  grid-template-columns: repeat(2, 1fr);
  gap: 8px;
  align-content: start;
}

.image-grid.desktop {
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
  padding: 12px;
}

.grid-item {
  position: relative;
  border-radius: 8px;
  overflow: hidden;
  cursor: pointer;
  background: #f0f0f0;
  aspect-ratio: 3 / 4;
  transition: transform 0.2s;
}

.grid-item:hover {
  transform: scale(1.02);
}

.grid-image {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.grid-overlay {
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  padding: 24px 8px 8px;
  background: linear-gradient(transparent, rgba(0, 0, 0, 0.7));
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.grid-title {
  font-size: 12px;
  color: #fff;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.grid-author {
  font-size: 10px;
  color: rgba(255, 255, 255, 0.8);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
