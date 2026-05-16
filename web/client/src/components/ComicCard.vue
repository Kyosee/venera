<script setup lang="ts">
import { computed } from 'vue'
import { useRouter } from 'vue-router'
import ComicTile from './ComicTile.vue'
import { extractComicId, extractSourceKey } from '@/utils/comic-display'

const props = withDefaults(defineProps<{
  comic: Record<string, any>
  displayMode?: 'brief' | 'detailed'
  sourceName?: string
  sourceKey?: string
  isFavorite?: boolean
  readProgress?: { page?: number; maxPage?: number }
  currentChapter?: string
  latestChapter?: string
}>(), {
  displayMode: undefined,
  sourceName: undefined,
  sourceKey: undefined,
  isFavorite: undefined,
  readProgress: undefined,
  currentChapter: undefined,
  latestChapter: undefined,
})

const emit = defineEmits<{
  click: [payload: { comic: Record<string, any>; id: string; sourceKey: string }]
}>()

const router = useRouter()

const effectiveSourceKey = computed(() =>
  extractSourceKey(props.comic, props.sourceKey)
)

const effectiveSourceName = computed(() =>
  props.sourceName || props.comic.sourceName || ''
)

const comicId = computed(() => extractComicId(props.comic))

const normalizedComic = computed(() => ({
  ...props.comic,
  sourceKey: effectiveSourceKey.value,
  sourceName: effectiveSourceName.value,
}))

function handleClick() {
  emit('click', {
    comic: props.comic,
    id: comicId.value,
    sourceKey: effectiveSourceKey.value,
  })
  if (effectiveSourceKey.value && comicId.value) {
    router.push(
      `/comic/${encodeURIComponent(effectiveSourceKey.value)}/${encodeURIComponent(comicId.value)}`
    )
  }
}
</script>

<template>
  <ComicTile
    :comic="normalizedComic"
    :source-name="effectiveSourceName"
    :display-mode="displayMode"
    :is-favorite="isFavorite"
    :read-progress="readProgress as any"
    :current-chapter="currentChapter"
    :latest-chapter="latestChapter"
    @click="handleClick"
  />
</template>
