<script setup lang="ts">
import { computed } from 'vue'
import ProxiedImage from './ProxiedImage.vue'
import { useSettingsStore } from '@/stores/settings'

const props = defineProps<{
  comic: Record<string, any>
  sourceName?: string
}>()

const settingsStore = useSettingsStore()
const mode = computed(() => settingsStore.settings.thumbnailMode === 'brief' ? 'brief' : 'detailed')
const scale = computed(() => Number(settingsStore.settings.thumbnailSize || 1))
const title = computed(() => String(props.comic.title || props.comic.name || ''))
const cover = computed(() => String(props.comic.cover || props.comic.coverPath || ''))
const author = computed(() => String(props.comic.author || props.comic.subtitle || '').replace(/\n/g, ''))
const sourceText = computed(() => props.sourceName || props.comic.sourceName || props.comic.sourceKey || '')
const metaText = (value: unknown) => {
  const text = String(value || '').trim()
  return text.startsWith('__') ? '' : text
}
const statusText = computed(() => metaText(props.comic.status || props.comic.language))
const updateText = computed(() => metaText(props.comic.updateTime || props.comic.lastUpdateTime))
const pagesText = computed(() => metaText(props.comic.pagesText || props.comic.maxPage || props.comic.max_page))
const pagesLabel = computed(() => pagesText.value && /^\d+$/.test(pagesText.value) ? `${pagesText.value}P` : pagesText.value)
const description = computed(() => String(props.comic.description || props.comic.subtitle || '').replace(/\|/g, '\n'))
const tags = computed(() => {
  const raw = props.comic.tags
  const normalize = (value: string) => value.trim()
  const visible = (value: string) => {
    const text = normalize(value)
    return text && !text.startsWith('__') && !/^类型:?$/i.test(text)
  }
  if (Array.isArray(raw)) return raw.map(String).map(normalize).filter(visible).slice(0, 4)
  if (!raw || typeof raw !== 'object') return []
  return Object.values(raw).flatMap(value => Array.isArray(value) ? value.map(String) : String(value || '').split(','))
    .map(item => item.trim())
    .filter(visible)
    .slice(0, 4)
})
const briefLines = computed(() => description.value.split('\n').map(item => item.trim()).filter(Boolean).slice(0, 3))
const styleVars = computed(() => ({
  '--tile-scale': String(scale.value),
}))
</script>

<template>
  <article class="comic-tile" :class="mode" :style="styleVars">
    <div class="cover-wrap">
      <ProxiedImage :src="cover" :alt="title" class="cover" />
      <div v-if="mode === 'brief' && briefLines.length" class="brief-overlay">
        <span v-for="line in briefLines" :key="line">{{ line }}</span>
      </div>
    </div>

    <div v-if="mode === 'detailed'" class="detail-body">
      <div class="detail-title">{{ title }}</div>
      <div v-if="author" class="detail-author">{{ author }}</div>
      <div v-if="description" class="detail-desc">{{ description }}</div>
      <div class="detail-meta">
        <span v-if="sourceText" class="meta-pill">{{ sourceText }}</span>
        <span v-if="statusText" class="meta-pill">{{ statusText }}</span>
        <span v-if="updateText" class="meta-pill">{{ updateText }}</span>
        <span v-if="pagesLabel" class="meta-pill">{{ pagesLabel }}</span>
      </div>
      <div v-if="tags.length" class="tag-row">
        <span v-for="tag in tags" :key="tag" class="tag">{{ tag }}</span>
      </div>
    </div>

    <div v-else class="brief-title">{{ title }}</div>
  </article>
</template>

<style scoped>
.comic-tile {
  cursor: pointer;
  transition: transform 0.15s ease;
}

.comic-tile:active {
  transform: scale(0.97);
}

.comic-tile.brief {
  width: 100%;
}

.comic-tile.detailed {
  height: calc(168px * var(--tile-scale));
  min-height: 128px;
  display: flex;
  gap: 14px;
  padding: 8px 14px 8px 8px;
  border-radius: 8px;
}

.cover-wrap {
  position: relative;
  overflow: hidden;
  border-radius: 8px;
  background: #f0f0f0;
}

.brief .cover-wrap {
  width: 100%;
  aspect-ratio: 0.64;
}

.detailed .cover-wrap {
  width: calc((168px * var(--tile-scale) - 44px) * 0.68);
  min-width: 70px;
  height: 100%;
  flex-shrink: 0;
}

.cover {
  width: 100%;
  height: 100%;
  display: block;
}

.cover :deep(img) {
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.detail-body {
  min-width: 0;
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.detail-title {
  font-size: 15px;
  font-weight: 600;
  line-height: 1.25;
  color: #222;
  overflow: hidden;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}

.detail-author,
.detail-desc {
  font-size: 12px;
  line-height: 1.35;
  color: #666;
  overflow: hidden;
  display: -webkit-box;
  -webkit-box-orient: vertical;
}

.detail-author {
  -webkit-line-clamp: 1;
}

.detail-desc {
  -webkit-line-clamp: 2;
}

.detail-meta,
.tag-row {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
  min-width: 0;
}

.meta-pill,
.tag {
  max-width: 100%;
  padding: 2px 6px;
  border-radius: 6px;
  font-size: 11px;
  line-height: 1.25;
  color: #4f6ef7;
  background: rgba(79, 110, 247, 0.1);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.tag {
  color: #666;
  background: #f4f4f4;
}

.brief-overlay {
  position: absolute;
  right: 2px;
  bottom: 2px;
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  gap: 2px;
  max-width: calc(100% - 4px);
}

.brief-overlay span {
  max-width: 100%;
  padding: 2px 5px;
  border-radius: 6px;
  color: #fff;
  background: rgba(0, 0, 0, 0.55);
  font-size: 11px;
  line-height: 1.2;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.brief-title {
  margin-top: 4px;
  padding: 0 4px;
  font-size: 14px;
  font-weight: 500;
  line-height: 1.25;
  color: #222;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: clip;
}
</style>
