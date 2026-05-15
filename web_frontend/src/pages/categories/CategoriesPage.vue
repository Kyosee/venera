<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { apiPost, imageProxyUrl } from '@/services/api'
import { getComicSources } from '@/services/server-db'
import { useSettingsStore } from '@/stores/settings'
import ComicTile from '@/components/ComicTile.vue'
import type { ComicSource } from '@/types'

interface CategoryItem {
  title: string
  cover?: string
  link?: string
}

interface CategoryComic {
  id: string
  title: string
  cover: string
  subtitle?: string
}

const router = useRouter()
const route = useRoute()
const settingsStore = useSettingsStore()
const sources = ref<ComicSource[]>([])
const activeTab = ref(0)
const categories = ref<Record<string, CategoryItem[]>>({})
const catLoading = ref<Record<string, boolean>>({})
const catError = ref<Record<string, string | null>>({})

// Category comics sub-view state
const selectedCategory = ref<string | null>(null)
const selectedCategoryTitle = ref('')
const comics = ref<CategoryComic[]>([])
const comicsPage = ref(1)
const comicsLoading = ref(false)
const comicsError = ref<string | null>(null)
const comicsHasMore = ref(false)

const currentSourceKey = computed(() => sources.value[activeTab.value]?.key ?? '')
const currentSourceName = computed(() => sources.value[activeTab.value]?.name ?? currentSourceKey.value)
const showComicsList = computed(() => selectedCategory.value !== null)
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

watch(() => route.query.cat, (val) => {
  if (val && typeof val === 'string') {
    selectedCategory.value = val
    const t = route.query.title
    selectedCategoryTitle.value = typeof t === 'string' ? t : val
    loadCategoryComics(currentSourceKey.value, val, true)
  } else {
    selectedCategory.value = null
    selectedCategoryTitle.value = ''
    comics.value = []
    comicsPage.value = 1
    comicsHasMore.value = false
  }
}, { immediate: true })

async function loadCategories(sourceKey: string) {
  if (!sourceKey || categories.value[sourceKey]) return
  catLoading.value[sourceKey] = true
  catError.value[sourceKey] = null
  try {
    const res = await apiPost<any>('/api/server-db/categories', { sourceKey })
    if (res?.ok === false) throw new Error(res?.error ?? 'Failed to load categories')
    categories.value[sourceKey] = res?.categories ?? []
  } catch (e: any) {
    catError.value[sourceKey] = e.message ?? 'Failed to load categories'
    categories.value[sourceKey] = []
  } finally {
    catLoading.value[sourceKey] = false
  }
}

async function loadCategoryComics(sourceKey: string, categoryId: string, reset = false) {
  if (!sourceKey || !categoryId) return
  if (comicsLoading.value) return
  comicsLoading.value = true
  comicsError.value = null
  const page = reset ? 1 : comicsPage.value + 1
  try {
    const res = await apiPost<any>('/api/server-db/category/comics', { sourceKey, categoryId, page })
    if (res?.ok === false) throw new Error(res?.error ?? 'Failed to load comics')
    const items: CategoryComic[] = res?.comics ?? []
    if (reset) {
      comics.value = items
    } else {
      comics.value = [...comics.value, ...items]
    }
    comicsPage.value = page
    comicsHasMore.value = res?.hasMore ?? false
  } catch (e: any) {
    comicsError.value = e.message ?? 'Failed to load comics'
  } finally {
    comicsLoading.value = false
  }
}

async function retryCategories() {
  const key = currentSourceKey.value
  if (!key) return
  delete categories.value[key]
  await loadCategories(key)
}

function onTabChange(index: number) {
  activeTab.value = index
  const key = sources.value[index]?.key
  if (key) loadCategories(key)
}

function onCategoryClick(cat: CategoryItem) {
  const id = cat.link || cat.title
  router.push({ path: route.path, query: { cat: id, title: cat.title } })
}

function onBackFromComics() {
  router.push({ path: route.path })
}

function goComic(comic: CategoryComic) {
  router.push(`/comic/${currentSourceKey.value}/${comic.id}`)
}

async function loadMoreComics() {
  if (!selectedCategory.value) return
  await loadCategoryComics(currentSourceKey.value, selectedCategory.value, false)
}

async function retryComics() {
  if (!selectedCategory.value) return
  await loadCategoryComics(currentSourceKey.value, selectedCategory.value, true)
}

onMounted(async () => {
  await settingsStore.loadSettings()
  try {
    const list = await getComicSources()
    sources.value = list
    if (list.length > 0) {
      await loadCategories(list[0].key)
    }
  } catch (e) {
    console.error('Failed to load sources:', e)
  }
})
</script>

<template>
  <div class="categories-page">
    <!-- Comics list sub-view -->
    <template v-if="showComicsList">
      <van-nav-bar
        :title="selectedCategoryTitle"
        left-arrow
        @click-left="onBackFromComics"
      />
      <div class="comics-content">
        <div v-if="comicsLoading && !comics.length" class="loading-state">
          <van-loading size="36px" color="#4f6ef7" vertical>Loading...</van-loading>
        </div>

        <div v-if="comicsError && !comics.length && !comicsLoading" class="error-state">
          <van-empty image="error" :description="comicsError" />
          <van-button type="primary" size="small" @click="retryComics">Retry</van-button>
        </div>

        <div v-if="comics.length" class="comic-grid" :style="gridStyle">
          <ComicTile
            v-for="comic in comics"
            :key="comic.id"
            :comic="{ ...comic, sourceKey: currentSourceKey }"
            :source-name="currentSourceName"
            class="comic-card"
            @click="goComic(comic)"
          />
        </div>

        <div v-if="comics.length && comicsHasMore" class="load-more">
          <van-loading v-if="comicsLoading" size="24px" />
          <van-button v-else size="small" plain @click="loadMoreComics">Load more</van-button>
        </div>

        <van-empty
          v-if="!comicsLoading && !comics.length && !comicsError"
          description="No comics in this category"
          image="search"
        />
      </div>
    </template>

    <!-- Main categories view -->
    <template v-else>
      <van-empty v-if="!sources.length" description="No comic sources available" />

      <van-tabs
        v-if="sources.length"
        v-model:active="activeTab"
        class="categories-tabs"
        color="#4f6ef7"
        title-active-color="#4f6ef7"
        swipeable
        sticky
        @change="onTabChange"
      >
        <van-tab v-for="source in sources" :key="source.key" :title="source.name">
          <div class="categories-content">
            <div v-if="catLoading[source.key]" class="loading-state">
              <van-loading size="36px" color="#4f6ef7" vertical>Loading categories...</van-loading>
            </div>

            <div v-if="catError[source.key] && !catLoading[source.key]" class="error-state">
              <van-empty image="error" :description="catError[source.key]!" />
              <van-button type="primary" size="small" @click="retryCategories">Retry</van-button>
            </div>

            <div
              v-if="!catLoading[source.key] && !catError[source.key] && categories[source.key]?.length"
              class="category-grid"
            >
              <div
                v-for="cat in categories[source.key]"
                :key="cat.title"
                class="category-item"
                @click="onCategoryClick(cat)"
              >
                <div class="category-cover-wrap">
                  <img
                    v-if="cat.cover"
                    class="category-cover"
                    :src="imageProxyUrl(cat.cover)"
                    :alt="cat.title"
                    loading="lazy"
                  />
                  <div v-else class="category-cover-placeholder">
                    <van-icon name="apps-o" size="28" color="#999" />
                  </div>
                </div>
                <div class="category-name">{{ cat.title }}</div>
              </div>
            </div>

            <van-empty
              v-if="!catLoading[source.key] && !catError[source.key] && !categories[source.key]?.length"
              description="No categories available"
              image="search"
            />
          </div>
        </van-tab>
      </van-tabs>
    </template>
  </div>
</template>

<style scoped>
.categories-page {
  height: 100%;
  display: flex;
  flex-direction: column;
}

.categories-tabs {
  flex: 1;
  display: flex;
  flex-direction: column;
}

:deep(.van-tabs__content) {
  flex: 1;
  overflow: hidden;
}

:deep(.van-tab__panel) {
  height: 100%;
}

.categories-content {
  height: calc(100vh - 94px);
  overflow-y: auto;
  padding: 16px;
  -webkit-overflow-scrolling: touch;
}

.comics-content {
  flex: 1;
  overflow-y: auto;
  padding: 16px;
  -webkit-overflow-scrolling: touch;
}

/* Category grid */
.category-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 12px;
}

@media (min-width: 720px) {
  .category-grid {
    grid-template-columns: repeat(5, 1fr);
  }
}

@media (min-width: 480px) and (max-width: 719px) {
  .category-grid {
    grid-template-columns: repeat(4, 1fr);
  }
}

.category-item {
  cursor: pointer;
  text-align: center;
  transition: transform 0.15s ease;
}

.category-item:active {
  transform: scale(0.95);
}

.category-cover-wrap {
  width: 100%;
  aspect-ratio: 1;
  border-radius: 8px;
  overflow: hidden;
  background: #f5f5f5;
}

.category-cover {
  width: 100%;
  height: 100%;
  object-fit: cover;
  display: block;
}

.category-cover-placeholder {
  width: 100%;
  height: 100%;
  display: flex;
  align-items: center;
  justify-content: center;
  background: linear-gradient(135deg, #f0f0f0, #e8e8e8);
}

.category-name {
  margin-top: 8px;
  font-size: 13px;
  line-height: 1.3;
  color: #333;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-overflow: ellipsis;
  word-break: break-all;
}

/* Comic grid */
.comic-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(120px, 192px));
  gap: 12px;
  justify-content: center;
}

.comic-card {
  cursor: pointer;
  transition: transform 0.15s ease;
}

.comic-card:active {
  transform: scale(0.97);
}

.comic-cover {
  width: 100%;
  aspect-ratio: 0.64;
  object-fit: cover;
  border-radius: 4px;
  background: #f0f0f0;
  display: block;
}

.comic-title {
  margin-top: 6px;
  font-size: 14px;
  line-height: 1.3;
  color: #333;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-overflow: ellipsis;
  word-break: break-all;
}

.comic-subtitle {
  margin-top: 2px;
  font-size: 12px;
  color: #999;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

/* States */
.loading-state {
  display: flex;
  justify-content: center;
  padding: 48px 0;
}

.error-state {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 16px 0;
}

.load-more {
  display: flex;
  justify-content: center;
  padding: 16px 0 24px;
}
</style>
