import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export type TaskType = 'follow_update' | 'history_refresh' | 'source_update' | 'source_migration'
export type TaskStatus = 'pending' | 'running' | 'completed' | 'failed' | 'cancelled'

export interface TaskEvent {
  comic: string
  result: string
}

export interface Task {
  id: string
  type: TaskType
  title: string
  status: TaskStatus
  progress: number
  total: number
  currentItem: string
  error?: string
  startTime: number
  endTime?: number
  serverTaskId?: string
  events?: TaskEvent[]
}

const STORAGE_KEY = 'venera_tasks_history'
const MAX_HISTORY = 50
const ACTIVE_FOLLOW_TASK_KEY = 'venera_active_follow_task'

function loadFromStorage(): Task[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) return []
    return JSON.parse(raw)
  } catch { return [] }
}

function saveToStorage(tasks: Task[]) {
  const history = tasks
    .filter(t => t.status !== 'running' && t.status !== 'pending')
    .slice(0, MAX_HISTORY)
  localStorage.setItem(STORAGE_KEY, JSON.stringify(history))
}

export const useTasksStore = defineStore('tasks', () => {
  const tasks = ref<Task[]>(loadFromStorage())
  const abortControllers = new Map<string, AbortController>()

  const currentTasks = computed(() =>
    tasks.value.filter(t => t.status === 'running' || t.status === 'pending')
  )
  const historyTasks = computed(() =>
    tasks.value.filter(t => t.status === 'completed' || t.status === 'failed' || t.status === 'cancelled')
  )

  function persist() { saveToStorage(tasks.value) }

  function addTask(task: Task) {
    tasks.value.unshift(task)
  }

  function updateTask(id: string, patch: Partial<Task>) {
    const t = tasks.value.find(x => x.id === id)
    if (t) Object.assign(t, patch)
    if (patch.status && patch.status !== 'running' && patch.status !== 'pending') persist()
  }

  function removeTask(id: string) {
    const idx = tasks.value.findIndex(x => x.id === id)
    if (idx >= 0) tasks.value.splice(idx, 1)
    persist()
  }

  function clearHistory() {
    tasks.value = tasks.value.filter(t => t.status === 'running' || t.status === 'pending')
    persist()
  }

  function getAbortController(id: string) { return abortControllers.get(id) }
  function setAbortController(id: string, ctrl: AbortController) { abortControllers.set(id, ctrl) }
  function deleteAbortController(id: string) { abortControllers.delete(id) }

  function getActiveFollowTaskId(): string | null {
    return localStorage.getItem(ACTIVE_FOLLOW_TASK_KEY)
  }
  function setActiveFollowTaskId(id: string) {
    localStorage.setItem(ACTIVE_FOLLOW_TASK_KEY, id)
  }
  function clearActiveFollowTaskId() {
    localStorage.removeItem(ACTIVE_FOLLOW_TASK_KEY)
  }

  return {
    tasks, currentTasks, historyTasks,
    addTask, updateTask, removeTask, clearHistory, persist,
    getAbortController, setAbortController, deleteAbortController,
    getActiveFollowTaskId, setActiveFollowTaskId, clearActiveFollowTaskId,
  }
})