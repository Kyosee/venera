<script setup lang="ts">
import { useRouter } from 'vue-router'
import ProxiedImage from './ProxiedImage.vue'

const props = defineProps<{
  comic: {
    title: string
    cover: string
    id: string
    sourceKey: string
    subtitle?: string
  }
}>()

const router = useRouter()
function goToComic() {
  router.push(`/comic/${props.comic.sourceKey}/${props.comic.id}`)
}
</script>

<template>
  <div class="comic-card" @click="goToComic">
    <div class="cover-wrapper">
      <ProxiedImage :src="comic.cover" :alt="comic.title" />
    </div>
    <div class="title">{{ comic.title }}</div>
    <div v-if="comic.subtitle" class="subtitle">{{ comic.subtitle }}</div>
  </div>
</template>

<style scoped>
.comic-card {
  cursor: pointer;
  overflow: hidden;
  transition: transform 0.15s;
}
.comic-card:active { transform: scale(0.97); }
.cover-wrapper {
  width: 100%;
  aspect-ratio: 0.64;
  border-radius: 4px;
  overflow: hidden;
  background: #f0f0f0;
}
.cover-wrapper :deep(img) {
  width: 100%; height: 100%; object-fit: cover;
}
.title {
  margin-top: 6px;
  font-size: 13px;
  font-weight: 500;
  line-height: 1.3;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
}
.subtitle {
  font-size: 11px;
  color: var(--color-text-tertiary);
  margin-top: 2px;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
</style>
