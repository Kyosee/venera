<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { apiPost, imageProxyUrl } from '@/services/api'
import { upsertHistory } from '@/services/server-db'
import { useSettingsStore } from '@/stores/settings'
import { sourceTypeFromKey } from '@/utils/source'
import type { Chapter, ChapterGroup } from '@/types'
import { showToast } from 'vant'

const route = useRoute()
const router = useRouter()
const settingsStore = useSettingsStore()
const sourceKey = computed(() => route.params.sourceKey as string)
const comicId = computed(() => route.params.id as string)

const images = ref<string[]>([])
const loading = ref(true)
const error = ref('')
const currentPage = ref(0)
const showToolbar = ref(false)
const showSettings = ref(false)
const showChapterPicker = ref(false)
const chapterIndex = ref(0)
const currentChapterId = ref('')
const chapterTitle = ref('')
const comicTitle = ref('')
const comicCover = ref('')
const continuousEl = ref<HTMLElement | null>(null)
const chapters = ref<Chapter[] | ChapterGroup[]>([])

type ReadingMode = 'galleryLeftToRight' | 'galleryRightToLeft' | 'galleryTopToBottom'
  | 'continuousTopToBottom' | 'continuousLeftToRight' | 'continuousRightToLeft'
const readingMode = ref<ReadingMode>('galleryLeftToRight')
const tapToTurnPages = ref(true)
const reverseTapToTurnPages = ref(false)

const touchStartX = ref(0)
const touchStartY = ref(0)
const translateX = ref(0)
const isSwiping = ref(false)
let saveTimer: ReturnType<typeof setTimeout> | null = null
let lastSavedPage = -1

// Auto page turning
const autoPageEnabled = ref(false)
const autoPageInterval = ref(4)
const autoPageCountdown = ref(0)
let countdownTimer: ReturnType<typeof setInterval> | null = null

// Double-tap zoom
const isZoomed = ref(false)
const zoomScale = ref(1)
const zoomOriginX = ref(50)
const zoomOriginY = ref(50)
let lastTapTime = 0
let lastTapX = 0
let lastTapY = 0

// Long-press
const showImageActions = ref(false)
let longPressTimer: ReturnType<typeof setTimeout> | null = null
let longPressTriggered = false

// Continuous mode page indicator
const showPageIndicator = ref(false)
let pageIndicatorTimer: ReturnType<typeof setTimeout> | null = null
let applyingSettings = false

// Fullscreen
const isFullscreen = ref(false)

const totalPages = computed(() => images.value.length)
const isGallery = computed(() => readingMode.value.startsWith('gallery'))
const isContinuous = computed(() => readingMode.value.startsWith('continuous'))
const isRTL = computed(() => readingMode.value.includes('RightToLeft'))
const isVerticalMode = computed(() => readingMode.value.includes('TopToBottom'))
const isContinuousHorizontal = computed(() => isContinuous.value && !isVerticalMode.value)
const pageDisplay = computed(() => totalPages.value ? `E${chapterIndex.value + 1} : P${currentPage.value + 1}` : '')
const showPageNumber = computed(() => settingsStore.settings.showPageNum)
const canDoubleTapZoom = computed(() => settingsStore.settings.doubleTapZoom)
const canLongPressZoom = computed(() => settingsStore.settings.longPressZoom)
const limitContinuousImageWidth = computed(() => settingsStore.settings.limitImageWidth)
const sliderVal = computed({
  get: () => currentPage.value + 1,
  set: (v: number) => { currentPage.value = Math.max(0, v - 1) }
})

const isGrouped = computed(() => {
  if (!chapters.value.length) return false
  return 'chapters' in chapters.value[0]
})
const flatChapters = computed(() => {
  if (!chapters.value.length) return [] as Array<Chapter & { groupIndex: number; chapterIndex: number; groupTitle: string }>
  if (!isGrouped.value) {
    return (chapters.value as Chapter[]).map((chapter, index) => ({
      ...chapter,
      groupIndex: 0,
      chapterIndex: index,
      groupTitle: '默认',
    }))
  }
  return (chapters.value as ChapterGroup[]).flatMap((group, groupIndex) =>
    (group.chapters ?? []).map((chapter, chapterIndex) => ({
      ...chapter,
      groupIndex,
      chapterIndex,
      groupTitle: group.title,
    }))
  )
})
const currentChapter = computed(() =>
  flatChapters.value.find(chapter => chapter.id === currentChapterId.value)
)

const autoPageProgress = computed(() => {
  if (!autoPageEnabled.value || autoPageCountdown.value <= 0) return 0
  return ((autoPageInterval.value - autoPageCountdown.value) / autoPageInterval.value) * 100
})

async function fetchPages() {
  loading.value = true; error.value = ''
  try {
    const ep = route.query.ep?.toString() || flatChapters.value[0]?.id || '0'
    currentChapterId.value = ep
    const listIndex = flatChapters.value.findIndex(chapter => chapter.id === ep)
    chapterIndex.value = listIndex >= 0 ? listIndex : Math.max(0, Number.parseInt(ep, 10) || 0)
    const res = await apiPost<any>('/api/server-db/reader/pages', {
      sourceKey: sourceKey.value, comicId: comicId.value, chapterId: ep
    })
    if (res.ok && res.data) {
      images.value = res.data
      chapterTitle.value = res.title || currentChapter.value?.title || `E${chapterIndex.value + 1}`
      comicTitle.value = res.comicTitle || comicTitle.value || route.query.title?.toString() || ''
      const page = Math.max(1, Number.parseInt(route.query.page?.toString() || '1', 10) || 1)
      currentPage.value = Math.min(page - 1, Math.max(0, images.value.length - 1))
    } else { throw new Error('Failed to load pages') }
  } catch (e: any) { error.value = e.message || 'Load failed' }
  finally { loading.value = false }
}

async function fetchChapters() {
  try {
    const res = await apiPost<any>('/api/server-db/comic/detail', {
      sourceKey: sourceKey.value,
      comicId: comicId.value,
    })
    chapters.value = res?.chapters || []
    comicTitle.value = res?.comic?.title || route.query.title?.toString() || comicTitle.value
    comicCover.value = res?.comic?.cover || route.query.cover?.toString() || comicCover.value
  } catch {
    comicTitle.value = route.query.title?.toString() || comicTitle.value
    comicCover.value = route.query.cover?.toString() || comicCover.value
  }
}

function scheduleSave() {
  if (saveTimer) clearTimeout(saveTimer)
  saveTimer = setTimeout(() => {
    if (currentPage.value !== lastSavedPage) {
      lastSavedPage = currentPage.value
      upsertHistory({
        id: comicId.value,
        type: sourceTypeFromKey(sourceKey.value),
        sourceKey: sourceKey.value,
        title: comicTitle.value,
        cover: comicCover.value,
        time: Date.now(),
        ep: chapterIndex.value + 1,
        page: currentPage.value + 1,
        readEpisode: currentChapterId.value ? [currentChapterId.value] : [],
        maxPage: totalPages.value,
        max_page: totalPages.value,
        group: currentChapter.value ? currentChapter.value.groupIndex + 1 : null,
        chapter_group: currentChapter.value ? currentChapter.value.groupIndex + 1 : null,
      }).catch(() => {})
    }
  }, 1000)
}

function goPage(p: number) { if (p >= 0 && p < totalPages.value) currentPage.value = p }
function nextPage() { isRTL.value ? goPage(currentPage.value - 1) : goPage(currentPage.value + 1) }
function prevPage() { isRTL.value ? goPage(currentPage.value + 1) : goPage(currentPage.value - 1) }
function goFirst() { currentPage.value = 0 }
function goLast() { currentPage.value = Math.max(0, totalPages.value - 1) }
function goChapterByOffset(offset: number) {
  const list = flatChapters.value
  const current = list.findIndex(chapter => chapter.id === currentChapterId.value)
  const fallback = current >= 0 ? current : chapterIndex.value
  const next = fallback + offset
  if (next < 0 || next >= list.length) {
    showToast(offset > 0 ? '已经是最后一话' : '已经是第一话')
    return
  }
  selectChapter(list[next].id)
}
function nextChapter() { goChapterByOffset(1) }
function prevChapter() { goChapterByOffset(-1) }
function selectChapter(id: string) {
  showChapterPicker.value = false
  router.replace({ path: route.path, query: { ...route.query, ep: id, page: '1' } })
}
function onBack() { router.back() }

function normalizeReadingMode(value: string): ReadingMode {
  const modes: ReadingMode[] = [
    'galleryLeftToRight',
    'galleryRightToLeft',
    'galleryTopToBottom',
    'continuousTopToBottom',
    'continuousLeftToRight',
    'continuousRightToLeft',
  ]
  return modes.includes(value as ReadingMode) ? value as ReadingMode : 'galleryLeftToRight'
}

function applyReaderSettings() {
  applyingSettings = true
  readingMode.value = normalizeReadingMode(settingsStore.settings.readingMode)
  tapToTurnPages.value = settingsStore.settings.tapToTurn
  reverseTapToTurnPages.value = settingsStore.settings.reverseTap
  autoPageInterval.value = settingsStore.settings.autoPageInterval
  nextTick(() => { applyingSettings = false })
}

// Auto page turning
function startAutoPage() {
  stopAutoPage()
  if (!isGallery.value) return
  autoPageCountdown.value = autoPageInterval.value
  countdownTimer = setInterval(() => {
    if (showToolbar.value) return // pause when toolbar shown
    autoPageCountdown.value -= 0.1
    if (autoPageCountdown.value <= 0) {
      autoPageCountdown.value = autoPageInterval.value
      if (currentPage.value < totalPages.value - 1) nextPage()
      else stopAutoPage()
    }
  }, 100)
}
function stopAutoPage() {
  if (countdownTimer) { clearInterval(countdownTimer); countdownTimer = null }
  autoPageCountdown.value = 0
}

// Fullscreen
function toggleFullscreen() {
  if (document.fullscreenElement) {
    document.exitFullscreen?.()
  } else {
    document.documentElement.requestFullscreen?.()
  }
}
function onFullscreenChange() {
  isFullscreen.value = !!document.fullscreenElement
}

// Double-tap zoom
function handleDoubleTap(x: number, y: number, rect: DOMRect) {
  if (!isGallery.value || !canDoubleTapZoom.value) return
  if (isZoomed.value) {
    isZoomed.value = false
    zoomScale.value = 1
  } else {
    const px = ((x - rect.left) / rect.width) * 100
    const py = ((y - rect.top) / rect.height) * 100
    zoomOriginX.value = px
    zoomOriginY.value = py
    zoomScale.value = 2
    isZoomed.value = true
  }
}

// Long-press image actions
function onImagePointerDown(_e: PointerEvent) {
  if (!canLongPressZoom.value) return
  longPressTriggered = false
  longPressTimer = setTimeout(() => {
    longPressTriggered = true
    showImageActions.value = true
  }, 600)
}
function onImagePointerUp() {
  if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null }
}
function onImagePointerCancel() {
  if (longPressTimer) { clearTimeout(longPressTimer); longPressTimer = null }
}

async function saveImage() {
  showImageActions.value = false
  const url = imageProxyUrl(images.value[currentPage.value])
  try {
    const resp = await fetch(url)
    const blob = await resp.blob()
    const a = document.createElement('a')
    a.href = URL.createObjectURL(blob)
    a.download = `page_${currentPage.value + 1}.jpg`
    document.body.appendChild(a)
    a.click()
    document.body.removeChild(a)
    URL.revokeObjectURL(a.href)
  } catch { /* silent fail */ }
}

async function copyImage() {
  showImageActions.value = false
  const url = imageProxyUrl(images.value[currentPage.value])
  try {
    const resp = await fetch(url)
    const blob = await resp.blob()
    const pngBlob = blob.type === 'image/png' ? blob : await convertToPng(blob)
    await navigator.clipboard.write([new ClipboardItem({ 'image/png': pngBlob })])
  } catch { /* silent fail */ }
}

function convertToPng(blob: Blob): Promise<Blob> {
  return new Promise((resolve) => {
    const img = new Image()
    img.onload = () => {
      const canvas = document.createElement('canvas')
      canvas.width = img.width; canvas.height = img.height
      canvas.getContext('2d')!.drawImage(img, 0, 0)
      canvas.toBlob((b) => resolve(b!), 'image/png')
    }
    img.src = URL.createObjectURL(blob)
  })
}

function handleTap(e: MouseEvent | TouchEvent) {
  if (longPressTriggered) { longPressTriggered = false; return }
  const t = e.target as HTMLElement
  if (t.closest('.toolbar-top') || t.closest('.toolbar-bottom')) return
  const rect = (e.currentTarget as HTMLElement).getBoundingClientRect()
  const cx = 'touches' in e ? e.changedTouches[0].clientX : e.clientX
  const cy = 'touches' in e ? e.changedTouches[0].clientY : e.clientY
  const xr = (cx - rect.left) / rect.width
  const yr = (cy - rect.top) / rect.height

  // Double-tap detection
  const now = Date.now()
  if (canDoubleTapZoom.value && isGallery.value && now - lastTapTime < 300 && Math.abs(cx - lastTapX) < 30 && Math.abs(cy - lastTapY) < 30) {
    handleDoubleTap(cx, cy, rect)
    lastTapTime = 0
    return
  }
  lastTapTime = now; lastTapX = cx; lastTapY = cy

  if (isZoomed.value) return // don't navigate when zoomed

  const position = isVerticalMode.value ? yr : xr
  if (position > 0.3 && position < 0.7) { showToolbar.value = !showToolbar.value }
  else if (isGallery.value && tapToTurnPages.value && !showToolbar.value) {
    const forward = reverseTapToTurnPages.value ? position <= 0.3 : position > 0.7
    if (forward) nextPage(); else prevPage()
  }
}

function onTouchStart(e: TouchEvent) {
  if (!isGallery.value || showToolbar.value) return
  touchStartX.value = e.touches[0].clientX; touchStartY.value = e.touches[0].clientY
  isSwiping.value = true; translateX.value = 0
}
function onTouchMove(e: TouchEvent) {
  if (!isSwiping.value || !isGallery.value) return
  const dx = e.touches[0].clientX - touchStartX.value
  if (Math.abs(e.touches[0].clientY - touchStartY.value) > Math.abs(dx)) { isSwiping.value = false; return }
  translateX.value = dx
}
function onTouchEnd() {
  if (!isSwiping.value) return; isSwiping.value = false
  if (translateX.value < -60) { isRTL.value ? prevPage() : nextPage() }
  else if (translateX.value > 60) { isRTL.value ? nextPage() : prevPage() }
  translateX.value = 0
}

function onKeydown(e: KeyboardEvent) {
  if (e.key === 'ArrowRight') nextPage()
  else if (e.key === 'ArrowLeft') prevPage()
  else if (e.key === 'Escape') onBack()
  else if (e.key === 'F11') { e.preventDefault(); toggleFullscreen() }
}

function preloadImages() {
  const count = Math.max(0, Number(settingsStore.settings.preloadCount) || 0)
  for (let i = currentPage.value + 1; i < Math.min(currentPage.value + count + 1, totalPages.value); i++) {
    const img = new Image(); img.src = imageProxyUrl(images.value[i])
  }
}

function onScroll() {
  if (!continuousEl.value || !isContinuous.value) return
  const el = continuousEl.value
  const imgs = el.querySelectorAll('img')
  const mid = isContinuousHorizontal.value
    ? el.scrollLeft + el.clientWidth / 2
    : el.scrollTop + el.clientHeight / 2
  let p = 0
  for (let i = 0; i < imgs.length; i++) {
    const img = imgs[i] as HTMLElement
    const center = isContinuousHorizontal.value
      ? img.offsetLeft + img.offsetWidth / 2
      : img.offsetTop + img.offsetHeight / 2
    if (center > mid) break
    p = i
  }
  if (p !== currentPage.value) currentPage.value = p
  // Show page indicator on scroll
  showPageIndicator.value = true
  if (pageIndicatorTimer) clearTimeout(pageIndicatorTimer)
  pageIndicatorTimer = setTimeout(() => { showPageIndicator.value = false }, 2000)
}

watch(currentPage, () => {
  scheduleSave(); preloadImages()
  // Reset zoom on page change
  if (isZoomed.value) { isZoomed.value = false; zoomScale.value = 1 }
})
watch(() => route.query.ep, () => { fetchPages() })
watch(readingMode, () => {
  if (isContinuous.value) nextTick(() => {
    const imgs = continuousEl.value?.querySelectorAll('img')
    if (imgs?.[currentPage.value]) imgs[currentPage.value].scrollIntoView()
  })
  // Stop auto page if switching to continuous
  if (isContinuous.value && autoPageEnabled.value) {
    autoPageEnabled.value = false; stopAutoPage()
  }
})
watch(autoPageEnabled, (v) => { v && isGallery.value ? startAutoPage() : stopAutoPage() })
watch(autoPageInterval, () => { if (autoPageEnabled.value) startAutoPage() })
watch([readingMode, tapToTurnPages, reverseTapToTurnPages, autoPageInterval], () => {
  if (applyingSettings) return
  settingsStore.update('readingMode', readingMode.value)
  settingsStore.update('tapToTurn', tapToTurnPages.value)
  settingsStore.update('reverseTap', reverseTapToTurnPages.value)
  settingsStore.update('autoPageInterval', autoPageInterval.value)
})

onMounted(async () => {
  await settingsStore.loadSettings()
  applyReaderSettings()
  await fetchChapters()
  await fetchPages()
  document.addEventListener('keydown', onKeydown)
  document.addEventListener('fullscreenchange', onFullscreenChange)
})
onUnmounted(() => {
  document.removeEventListener('keydown', onKeydown)
  document.removeEventListener('fullscreenchange', onFullscreenChange)
  if (saveTimer) clearTimeout(saveTimer)
  stopAutoPage()
  if (longPressTimer) clearTimeout(longPressTimer)
  if (pageIndicatorTimer) clearTimeout(pageIndicatorTimer)
})
</script>

<template>
  <div class="reader" @click="handleTap" @touchstart="onTouchStart" @touchmove.passive="onTouchMove" @touchend="onTouchEnd">
    <div v-if="loading" class="center"><van-loading size="48" color="#fff" /></div>
    <div v-else-if="error" class="center">
      <p style="color:#ff6b6b;font-size:14px">{{ error }}</p>
      <van-button type="primary" size="small" @click.stop="fetchPages">重试</van-button>
    </div>
    <template v-else>
      <div v-if="isGallery" class="gallery">
        <img
          :src="imageProxyUrl(images[currentPage])"
          class="gallery-img"
          :class="{ 'zoom-transition': true }"
          :style="{
            transform: `translateX(${translateX}px) scale(${zoomScale})`,
            transformOrigin: `${zoomOriginX}% ${zoomOriginY}%`
          }"
          draggable="false"
          @pointerdown="onImagePointerDown"
          @pointerup="onImagePointerUp"
          @pointercancel="onImagePointerCancel"
          @contextmenu.prevent
        />
      </div>
      <div
        v-else
        ref="continuousEl"
        class="continuous"
        :class="{ horizontal: isContinuousHorizontal, limited: limitContinuousImageWidth }"
        @scroll="onScroll"
      >
        <img
          v-for="(url, i) in images" :key="i"
          :src="imageProxyUrl(url)"
          class="continuous-img" loading="lazy"
          @pointerdown="onImagePointerDown"
          @pointerup="onImagePointerUp"
          @pointercancel="onImagePointerCancel"
          @contextmenu.prevent
        />
      </div>
    </template>

    <!-- Auto page indicator -->
    <div v-if="autoPageEnabled && isGallery && !showToolbar" class="auto-page-indicator">
      <svg width="36" height="36" viewBox="0 0 36 36">
        <circle cx="18" cy="18" r="15" fill="none" stroke="rgba(255,255,255,0.2)" stroke-width="3" />
        <circle cx="18" cy="18" r="15" fill="none" stroke="#1989fa" stroke-width="3"
          stroke-linecap="round" :stroke-dasharray="94.2" :stroke-dashoffset="94.2 - (autoPageProgress / 100) * 94.2"
          transform="rotate(-90 18 18)" />
      </svg>
    </div>

    <!-- Continuous mode page indicator -->
    <transition name="fade">
      <div v-if="isContinuous && showPageNumber && showPageIndicator && totalPages > 0" class="page-indicator-pill">
        {{ currentPage + 1 }} / {{ totalPages }}
      </div>
    </transition>

    <!-- Top toolbar -->
    <transition name="slide-top">
      <div v-if="showToolbar" class="toolbar-top" @click.stop>
        <van-icon name="arrow-left" size="22" color="#fff" @click="onBack" />
        <div class="title-section">
          <div class="comic-name">{{ comicTitle }}</div>
          <div class="chapter-name">{{ chapterTitle }}</div>
        </div>
        <span v-if="showPageNumber" class="page-badge">{{ pageDisplay }}</span>
        <van-icon :name="isFullscreen ? 'shrink' : 'expand-o'" size="20" color="#fff" @click="toggleFullscreen" />
        <van-icon name="setting-o" size="20" color="#fff" @click="showSettings = true" />
      </div>
    </transition>

    <!-- Bottom toolbar -->
    <transition name="slide-bottom">
      <div v-if="showToolbar" class="toolbar-bottom" @click.stop>
        <van-icon name="arrow-left" size="20" color="#fff" class="tb-btn" @click="goFirst" />
        <div class="slider-wrap">
          <van-slider v-model="sliderVal" :min="1" :max="Math.max(totalPages, 1)" :step="1" active-color="#1989fa" />
        </div>
        <van-icon name="arrow" size="20" color="#fff" class="tb-btn" @click="goLast" />
        <div class="chapter-btns">
          <van-button size="mini" plain hairline color="#fff" @click="prevChapter">上一话</van-button>
          <van-button size="mini" plain hairline color="#fff" @click="showChapterPicker = true">章节</van-button>
          <van-button size="mini" plain hairline color="#fff" @click="nextChapter">下一话</van-button>
        </div>
      </div>
    </transition>

    <!-- Settings panel -->
    <van-popup v-model:show="showSettings" position="right" :style="{ width: '300px', height: '100%' }">
      <div class="settings">
        <h3 style="margin:16px">阅读设置</h3>
        <van-cell-group inset>
          <van-cell title="阅读模式">
            <template #value>
              <select v-model="readingMode" class="mode-select">
                <option value="galleryLeftToRight">分页：从左到右</option>
                <option value="galleryRightToLeft">分页：从右到左</option>
                <option value="galleryTopToBottom">分页：从上到下</option>
                <option value="continuousTopToBottom">连续：从上到下</option>
                <option value="continuousLeftToRight">连续：从左到右</option>
                <option value="continuousRightToLeft">连续：从右到左</option>
              </select>
            </template>
          </van-cell>
          <van-cell title="点击翻页">
            <template #right-icon><van-switch v-model="tapToTurnPages" size="20" /></template>
          </van-cell>
          <van-cell title="反转点击区域">
            <template #right-icon><van-switch v-model="reverseTapToTurnPages" size="20" /></template>
          </van-cell>
          <van-cell title="自动翻页" v-if="isGallery">
            <template #right-icon><van-switch v-model="autoPageEnabled" size="20" /></template>
          </van-cell>
          <van-cell title="自动翻页间隔（秒）" v-if="isGallery && autoPageEnabled">
            <template #value>
              <van-stepper v-model="autoPageInterval" :min="1" :max="10" :step="1" theme="round" />
            </template>
          </van-cell>
        </van-cell-group>
      </div>
    </van-popup>

    <!-- Chapter picker -->
    <van-popup v-model:show="showChapterPicker" position="right" :style="{ width: '320px', maxWidth: '88vw', height: '100%' }">
      <div class="chapter-panel">
        <div class="chapter-panel-title">章节</div>
        <div class="chapter-list">
          <button
            v-for="chapter in flatChapters"
            :key="chapter.id"
            type="button"
            class="chapter-item"
            :class="{ active: chapter.id === currentChapterId }"
            @click="selectChapter(chapter.id)"
          >
            <span class="chapter-main">{{ chapter.title || `第 ${chapter.chapterIndex + 1} 话` }}</span>
            <span class="chapter-sub">{{ chapter.groupTitle }}</span>
          </button>
        </div>
      </div>
    </van-popup>

    <!-- Image action sheet (long-press) -->
    <van-action-sheet
      v-model:show="showImageActions"
      :actions="[{ name: '保存图片' }, { name: '复制图片' }]"
      cancel-text="取消"
      @select="(action: any) => action.name === '保存图片' ? saveImage() : copyImage()"
      @cancel="showImageActions = false"
    />
  </div>
</template>

<style scoped>
.reader { position: fixed; inset: 0; background: #000; color: #fff; user-select: none; overflow: hidden; z-index: 100; }
.center { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 16px; }
.gallery { width: 100%; height: 100%; display: flex; align-items: center; justify-content: center; overflow: hidden; }
.gallery-img { max-width: 100%; max-height: 100%; object-fit: contain; }
.zoom-transition { transition: transform 0.25s cubic-bezier(0.25, 0.1, 0.25, 1); }
.continuous { width: 100%; height: 100%; overflow-y: auto; -webkit-overflow-scrolling: touch; }
.continuous.horizontal { display: flex; overflow-x: auto; overflow-y: hidden; scroll-snap-type: x mandatory; }
.continuous-img { display: block; width: 100%; height: auto; }
.continuous.limited:not(.horizontal) .continuous-img { max-width: min(100%, 980px); margin: 0 auto; }
.continuous.horizontal .continuous-img { width: auto; height: 100%; max-width: none; flex: 0 0 auto; object-fit: contain; scroll-snap-align: center; }
.continuous.horizontal.limited .continuous-img { max-width: 100vw; }
.toolbar-top {
  position: absolute; top: 0; left: 0; right: 0; z-index: 50;
  display: flex; align-items: center; gap: 12px;
  padding: 12px 16px; padding-top: calc(env(safe-area-inset-top, 0px) + 12px);
  background: rgba(30,30,30,0.92); backdrop-filter: blur(10px);
  border-bottom: 0.5px solid rgba(128,128,128,0.5);
}
.title-section { flex: 1; min-width: 0; }
.comic-name { font-size: 16px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.chapter-name { font-size: 12px; opacity: 0.7; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.page-badge { font-size: 13px; background: rgba(100,100,100,0.5); padding: 2px 8px; border-radius: 8px; white-space: nowrap; }
.toolbar-bottom {
  position: absolute; bottom: 0; left: 0; right: 0; z-index: 50;
  display: flex; align-items: center; gap: 8px; flex-wrap: wrap;
  padding: 12px 16px; padding-bottom: calc(env(safe-area-inset-bottom, 0px) + 12px);
  background: rgba(30,30,30,0.92); backdrop-filter: blur(10px);
  border-top: 0.5px solid rgba(128,128,128,0.5);
}
.tb-btn { cursor: pointer; padding: 4px; }
.slider-wrap { flex: 1; min-width: 100px; padding: 0 4px; }
.chapter-btns { display: flex; gap: 6px; }
.settings { padding-bottom: env(safe-area-inset-bottom, 0px); }
.mode-select { background: transparent; color: inherit; border: 1px solid #ddd; border-radius: 4px; padding: 4px 8px; font-size: 13px; }
.chapter-panel { height: 100%; background: #111; color: #fff; display: flex; flex-direction: column; }
.chapter-panel-title { padding: calc(env(safe-area-inset-top, 0px) + 16px) 16px 12px; font-size: 16px; font-weight: 600; border-bottom: 0.5px solid rgba(255,255,255,0.12); }
.chapter-list { flex: 1; overflow-y: auto; padding: 8px; }
.chapter-item { width: 100%; display: flex; align-items: center; justify-content: space-between; gap: 12px; border: 0; border-radius: 6px; padding: 12px 10px; background: transparent; color: inherit; text-align: left; cursor: pointer; }
.chapter-item.active { background: rgba(25,137,250,0.22); color: #6bb6ff; }
.chapter-main { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-size: 14px; }
.chapter-sub { flex: 0 0 auto; font-size: 12px; opacity: 0.62; }

/* Auto page indicator */
.auto-page-indicator {
  position: absolute; bottom: 24px; right: 24px; z-index: 40;
  width: 36px; height: 36px; opacity: 0.8;
}
/* Page indicator pill for continuous mode */
.page-indicator-pill {
  position: absolute; bottom: 24px; left: 50%; transform: translateX(-50%); z-index: 40;
  background: rgba(0,0,0,0.65); color: #fff; font-size: 13px;
  padding: 4px 14px; border-radius: 14px; white-space: nowrap;
  backdrop-filter: blur(4px);
}
/* Transitions */
.slide-top-enter-active, .slide-top-leave-active { transition: transform 140ms cubic-bezier(0.33,1,0.68,1); }
.slide-top-enter-from, .slide-top-leave-to { transform: translateY(-100%); }
.slide-bottom-enter-active, .slide-bottom-leave-active { transition: transform 140ms cubic-bezier(0.33,1,0.68,1); }
.slide-bottom-enter-from, .slide-bottom-leave-to { transform: translateY(100%); }
.fade-enter-active, .fade-leave-active { transition: opacity 0.3s ease; }
.fade-enter-from, .fade-leave-to { opacity: 0; }
</style>
