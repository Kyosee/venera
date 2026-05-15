import { defineStore } from 'pinia'
import { ref } from 'vue'
import { apiPost } from '../services/api'
import { listHistory, deleteHistory } from '../services/server-db'
import type { History } from '../types'

export const useHistoryStore = defineStore('history', () => {
  const items = ref<History[]>([])
  const loading = ref(false)
  const loaded = ref(false)

  async function fetchHistory() {
    loading.value = true
    try {
      const result = await listHistory()
      items.value = result.items.sort((a, b) => b.time - a.time)
      loaded.value = true
    } finally {
      loading.value = false
    }
  }

  async function removeHistory(id: string, type: number) {
    await deleteHistory(id, type)
    items.value = items.value.filter(h => !(h.id === id && h.type === type))
  }

  async function clearAll() {
    await apiPost('/api/server-db/history/clear', {})
    items.value = []
  }

  return { items, loading, loaded, fetchHistory, removeHistory, clearAll }
})
