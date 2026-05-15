import { defineStore } from 'pinia'
import { ref } from 'vue'
import { getComicSources } from '../services/server-db'
import type { ComicSource } from '../types'

export const useSourcesStore = defineStore('sources', () => {
  const sources = ref<ComicSource[]>([])
  const loading = ref(false)

  async function fetchSources() {
    loading.value = true
    try {
      sources.value = await getComicSources()
    } finally {
      loading.value = false
    }
  }

  return { sources, loading, fetchSources }
})
