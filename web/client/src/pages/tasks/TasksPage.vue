<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { showToast, showConfirmDialog } from 'vant'
import { useRoute, useRouter } from 'vue-router'
import { listHistory, getComicSources, upsertHistory } from '@/services/server-db'
import { apiPost } from '@/services/api'
import { useTasksStore, type Task, type TaskType, type TaskStatus } from '@/stores/tasks'

const store = useTasksStore()
const route = useRoute()
const router = useRouter()

const activeTab = ref(0)
const showActionSheet = ref(false)

function getTaskIcon(type: TaskType): string {
  switch (type) {
    case 'follow_update': return 'bell'
    case 'history_refresh': return 'replay'
    case 'source_update': return 'upgrade'
    case 'source_migration': return 'exchange'
  }
}

function getTaskTypeLabel(type: TaskType): string {
  switch (type) {
    case 'follow_update': return '检查追更'
    case 'history_refresh': return '刷新历史'
    case 'source_update': return '更新漫画源'
    case 'source_migration': return '迁移漫画源'
  }
}

function getStatusText(task: Task): string {
  switch (task.status) {
    case 'pending': return '等待中...'
    case 'running':
      return task.currentItem
        ? `${task.currentItem} (${task.progress}/${task.total})`
        : `${task.progress}/${task.total}`
    case 'completed': return `完成 (${task.total} 项)`
    case 'failed': return task.error || '失败'
    case 'cancelled': return '已取消'
  }
}

function getStatusColor(status: TaskStatus): string {
  switch (status) {
    case 'running': return '#4f6ef7'
    case 'completed': return '#27ae60'
    case 'failed': return '#e74c3c'
    case 'cancelled': return '#999'
    default: return '#666'
  }
}

function formatDuration(start: number, end?: number): string {
  const ms = (end || Date.now()) - start
  const s = Math.floor(ms / 1000)
  if (s < 60) return `${s}秒`
  return `${Math.floor(s / 60)}分${s % 60}秒`
}

function createTask(type: TaskType): Task {
  return {
    id: `${type}_${Date.now()}`,
    type,
    title: getTaskTypeLabel(type),
    status: 'pending',
    progress: 0,
    total: 0,
    currentItem: '',
    startTime: Date.now()
  }
}

function startTask(type: TaskType) {
  if (store.currentTasks.some(t => t.type === type)) {
    showToast('该任务正在运行中')
    return
  }
  const task = createTask(type)
  store.addTask(task)
  showActionSheet.value = false

  switch (type) {
    case 'follow_update': runFollowUpdateTask(task); break
    case 'history_refresh': runHistoryRefreshTask(task); break
    case 'source_update': runSourceUpdateTask(task); break
    case 'source_migration': showToast('请从收藏页面使用迁移功能'); break
  }
}

async function runFollowUpdateTask(task: Task) {
  const controller = new AbortController()
  store.setAbortController(task.id, controller)
  store.updateTask(task.id, { status: 'running' })

  try {
    const { useSettingsStore } = await import('@/stores/settings')
    const settingsStore = useSettingsStore()
    const folder = settingsStore.settings.followUpdatesFolder
    if (!folder) {
      store.updateTask(task.id, { error: '未设置追更文件夹', status: 'failed', endTime: Date.now() })
      return
    }

    const { startAsyncFollowUpdateCheck, getFollowUpdateCheckStatus, cancelFollowUpdateCheck } = await import('@/services/server-db')
    const serverTaskId = await startAsyncFollowUpdateCheck(folder)
    if (!serverTaskId) {
      store.updateTask(task.id, { error: '启动检查失败', status: 'failed', endTime: Date.now() })
      return
    }
    store.setActiveFollowTaskId(serverTaskId)
    store.updateTask(task.id, { currentItem: `正在检查 ${folder}...`, serverTaskId })

    let pollTimer: ReturnType<typeof setInterval> | null = null
    const stopPolling = () => { if (pollTimer) { clearInterval(pollTimer); pollTimer = null } }
    let pollResolve: (() => void) | null = null
    controller.signal.addEventListener('abort', async () => {
      stopPolling()
      store.updateTask(task.id, { status: 'cancelled', endTime: Date.now() })
      cancelFollowUpdateCheck(serverTaskId).catch(() => {})
      store.clearActiveFollowTaskId()
      pollResolve?.()
    })

    await new Promise<void>((resolve) => {
      pollResolve = resolve
      pollTimer = setInterval(async () => {
        try {
          const state = await getFollowUpdateCheckStatus(serverTaskId)
          if (!state) {
            stopPolling()
            store.updateTask(task.id, { error: '检查任务丢失', status: 'failed', endTime: Date.now() })
            store.clearActiveFollowTaskId()
            resolve()
            return
          }
          store.updateTask(task.id, { progress: state.checked, total: state.total, currentItem: state.currentItem || task.currentItem })
          if (state.status === 'completed') {
            stopPolling()
            const events = Array.isArray(state.updated) ? state.updated.map((u: any) => ({
              comic: u?.title || u?.id || '',
              result: u?.updateTime ? `更新于 ${new Date(u.updateTime).toLocaleDateString()}` : '有更新',
            })) : []
            store.updateTask(task.id, { progress: state.checked, total: state.checked, currentItem: state.currentItem || `完成，检查了 ${state.checked} 项`, status: 'completed', endTime: state.endTime ?? Date.now(), events })
            store.clearActiveFollowTaskId()
            resolve()
          } else if (state.status === 'failed') {
            stopPolling()
            store.updateTask(task.id, { error: state.error || '检查失败', status: 'failed', endTime: state.endTime ?? Date.now() })
            store.clearActiveFollowTaskId()
            resolve()
          } else if (state.status === 'cancelled') {
            stopPolling()
            store.updateTask(task.id, { status: 'cancelled', endTime: state.endTime ?? Date.now() })
            store.clearActiveFollowTaskId()
            resolve()
          }
        } catch { /* network errors — keep polling */ }
      }, 2000)
    })
  } catch (e: any) {
    store.updateTask(task.id, { error: e.message || '未知错误', status: 'failed' })
    store.clearActiveFollowTaskId()
  } finally {
    store.updateTask(task.id, { endTime: store.tasks.find(t => t.id === task.id)?.endTime || Date.now() })
    store.deleteAbortController(task.id)
  }
}

async function runHistoryRefreshTask(task: Task) {
  const controller = new AbortController()
  store.setAbortController(task.id, controller)
  store.updateTask(task.id, { status: 'running' })

  try {
    const historyResult = await listHistory()
    const historyItems = historyResult.items
    store.updateTask(task.id, { total: historyItems.length })
    if (historyItems.length === 0) {
      store.updateTask(task.id, { status: 'completed', endTime: Date.now() })
      return
    }

    let refreshed = 0
    for (let i = 0; i < historyItems.length; i++) {
      if (controller.signal.aborted) {
        store.updateTask(task.id, { status: 'cancelled', endTime: Date.now() })
        return
      }
      const item = historyItems[i]
      store.updateTask(task.id, { currentItem: item.title, progress: i + 1 })
      try {
        await upsertHistory({ ...item })
        refreshed++
      } catch { /* skip */ }
    }
    store.updateTask(task.id, { currentItem: `完成，刷新了 ${refreshed} 项`, status: 'completed' })
  } catch (e: any) {
    store.updateTask(task.id, { error: e.message || '未知错误', status: 'failed' })
  } finally {
    store.updateTask(task.id, { endTime: store.tasks.find(t => t.id === task.id)?.endTime || Date.now() })
    store.deleteAbortController(task.id)
  }
}

async function runSourceUpdateTask(task: Task) {
  const controller = new AbortController()
  store.setAbortController(task.id, controller)
  store.updateTask(task.id, { status: 'running' })

  try {
    const sources = await getComicSources()
    store.updateTask(task.id, { total: sources.length })
    if (sources.length === 0) {
      store.updateTask(task.id, { status: 'completed', endTime: Date.now() })
      return
    }

    let checked = 0
    for (let i = 0; i < sources.length; i++) {
      if (controller.signal.aborted) {
        store.updateTask(task.id, { status: 'cancelled', endTime: Date.now() })
        return
      }
      const src = sources[i]
      store.updateTask(task.id, { currentItem: src.name, progress: i + 1 })
      try {
        await apiPost('/api/source/check-update', { sourceKey: src.key })
        checked++
      } catch { /* skip */ }
    }
    store.updateTask(task.id, { currentItem: `完成，检查了 ${checked} 个源`, status: 'completed' })
  } catch (e: any) {
    store.updateTask(task.id, { error: e.message || '未知错误', status: 'failed' })
  } finally {
    store.updateTask(task.id, { endTime: store.tasks.find(t => t.id === task.id)?.endTime || Date.now() })
    store.deleteAbortController(task.id)
  }
}

function cancelTask(task: Task) {
  showConfirmDialog({ title: '取消任务', message: `确定取消「${task.title}」？` })
    .then(() => {
      const controller = store.getAbortController(task.id)
      if (controller) controller.abort()
      else store.updateTask(task.id, { status: 'cancelled', endTime: Date.now() })
    })
    .catch(() => {})
}

function clearHistoryTasks() {
  store.clearHistory()
}

function progressPercent(task: Task): number {
  if (task.total === 0) return 0
  return Math.round((task.progress / task.total) * 100)
}

const taskActions = [
  { name: '检查追更', value: 'follow_update' as TaskType, icon: 'bell' },
  { name: '刷新历史', value: 'history_refresh' as TaskType, icon: 'replay' },
  { name: '更新漫画源', value: 'source_update' as TaskType, icon: 'upgrade' },
]

// Reconnect to a server-side task that was started in a previous browser session
async function reconnectToTask(serverTaskId: string) {
  const { getFollowUpdateCheckStatus, cancelFollowUpdateCheck } = await import('@/services/server-db')
  try {
    const state = await getFollowUpdateCheckStatus(serverTaskId)
    if (!state) {
      store.clearActiveFollowTaskId()
      return
    }
    const task: Task = {
      id: `follow_update_reconnect_${serverTaskId}`,
      type: 'follow_update',
      title: '检查追更',
      status: 'running',
      progress: state.checked,
      total: state.total,
      currentItem: state.currentItem || '正在检查...',
      startTime: state.startTime || Date.now(),
      serverTaskId,
    }
    store.addTask(task)

    if (state.status === 'completed' || state.status === 'failed' || state.status === 'cancelled') {
      const events = state.status === 'completed' && Array.isArray(state.updated) ? state.updated.map((u: any) => ({
        comic: u?.title || u?.id || '',
        result: u?.updateTime ? `更新于 ${new Date(u.updateTime).toLocaleDateString()}` : '有更新',
      })) : []
      store.updateTask(task.id, { progress: state.checked, total: state.checked, status: state.status as TaskStatus, currentItem: state.currentItem || '', error: state.error ?? undefined, endTime: state.endTime ?? Date.now(), events })
      store.clearActiveFollowTaskId()
      return
    }

    const controller = new AbortController()
    store.setAbortController(task.id, controller)
    let pollTimer: ReturnType<typeof setInterval> | null = null
    const stopPolling = () => { if (pollTimer) { clearInterval(pollTimer); pollTimer = null } }

    let pollResolve: (() => void) | null = null
    controller.signal.addEventListener('abort', async () => {
      stopPolling()
      store.updateTask(task.id, { status: 'cancelled', endTime: Date.now() })
      cancelFollowUpdateCheck(serverTaskId).catch(() => {})
      store.clearActiveFollowTaskId()
      pollResolve?.()
    })

    await new Promise<void>((resolve) => {
      pollResolve = resolve
      pollTimer = setInterval(async () => {
        try {
          const s = await getFollowUpdateCheckStatus(serverTaskId)
          if (!s) return
          store.updateTask(task.id, { progress: s.checked, total: s.total, currentItem: s.currentItem || task.currentItem })
          if (s.status === 'completed') {
            stopPolling()
            store.updateTask(task.id, { progress: s.checked, total: s.checked, currentItem: s.currentItem || `完成，检查了 ${s.checked} 项`, status: 'completed', endTime: s.endTime ?? Date.now() })
            store.clearActiveFollowTaskId()
            resolve()
          } else if (s.status === 'failed') {
            stopPolling()
            store.updateTask(task.id, { error: s.error || '检查失败', status: 'failed', endTime: s.endTime ?? Date.now() })
            store.clearActiveFollowTaskId()
            resolve()
          } else if (s.status === 'cancelled') {
            stopPolling()
            store.updateTask(task.id, { status: 'cancelled', endTime: s.endTime ?? Date.now() })
            store.clearActiveFollowTaskId()
            resolve()
          }
        } catch { /* network errors — keep polling */ }
      }, 2000)
    })
  } catch {
    store.clearActiveFollowTaskId()
  }
}

onMounted(() => {
  const storedTaskId = store.getActiveFollowTaskId()
  if (storedTaskId) {
    reconnectToTask(storedTaskId)
  }
  const autoStart = route.query.autoStart as string | undefined
  if (autoStart === 'follow_update') {
    router.replace({ path: '/tasks', query: {} })
    startTask('follow_update')
  }
})
</script>

<template>
  <div class="tasks-page">
    <van-nav-bar title="任务">
      <template #right>
        <van-icon
          v-if="store.historyTasks.length > 0 && activeTab === 1"
          name="delete-o"
          size="20"
          @click="clearHistoryTasks"
        />
      </template>
    </van-nav-bar>

    <van-tabs v-model:active="activeTab" sticky>
      <van-tab title="当前">
        <div class="task-list">
          <div v-if="store.currentTasks.length === 0" class="empty-state">
            <van-empty description="没有正在运行的任务" image="search" />
          </div>
          <div
            v-for="task in store.currentTasks"
            :key="task.id"
            class="task-card"
          >
            <div class="task-header">
              <van-icon
                :name="getTaskIcon(task.type)"
                class="task-icon"
                size="22"
              />
              <div class="task-info">
                <div class="task-title">{{ task.title }}</div>
                <div
                  class="task-status"
                  :style="{ color: getStatusColor(task.status) }"
                >
                  {{ getStatusText(task) }}
                </div>
              </div>
              <van-button
                v-if="task.status === 'running'"
                size="small"
                type="danger"
                plain
                round
                @click="cancelTask(task)"
              >
                取消
              </van-button>
            </div>
            <van-progress
              v-if="task.status === 'running' && task.total > 0"
              :percentage="progressPercent(task)"
              :show-pivot="true"
              color="#4f6ef7"
              class="task-progress"
            />
          </div>
        </div>
      </van-tab>

      <van-tab title="历史">
        <div class="task-list">
          <div v-if="store.historyTasks.length === 0" class="empty-state">
            <van-empty description="没有历史任务" image="search" />
          </div>
          <div
            v-for="task in store.historyTasks"
            :key="task.id"
            class="task-card"
            :class="{ 'task-card--failed': task.status === 'failed' }"
          >
            <div class="task-header">
              <van-icon
                :name="getTaskIcon(task.type)"
                class="task-icon"
                size="22"
              />
              <div class="task-info">
                <div class="task-title">{{ task.title }}</div>
                <div
                  class="task-status"
                  :style="{ color: getStatusColor(task.status) }"
                >
                  {{ getStatusText(task) }}
                </div>
                <div class="task-time">
                  {{ formatDuration(task.startTime, task.endTime) }}
                </div>
              </div>
              <van-icon
                v-if="task.status === 'completed'"
                name="checked"
                color="#27ae60"
                size="20"
              />
              <van-icon
                v-else-if="task.status === 'failed'"
                name="warning-o"
                color="#e74c3c"
                size="20"
              />
              <van-icon
                v-else-if="task.status === 'cancelled'"
                name="close"
                color="#999"
                size="20"
              />
            </div>
            <div v-if="task.events && task.events.length" class="task-events">
              <div v-for="(evt, idx) in task.events" :key="idx" class="task-event-item">
                <span class="event-comic">{{ evt.comic }}</span>
                <span class="event-result">{{ evt.result }}</span>
              </div>
            </div>
          </div>
        </div>
      </van-tab>
    </van-tabs>

    <!-- FAB to start new task -->
    <div class="fab-container">
      <van-button
        type="primary"
        round
        icon="plus"
        class="fab-button"
        @click="showActionSheet = true"
      />
    </div>

    <!-- Action sheet for task selection -->
    <van-action-sheet
      v-model:show="showActionSheet"
      title="选择任务"
      cancel-text="取消"
    >
      <div class="action-list">
        <div
          v-for="action in taskActions"
          :key="action.value"
          class="action-item"
          @click="startTask(action.value)"
        >
          <van-icon :name="action.icon" size="24" color="#4f6ef7" />
          <span class="action-name">{{ action.name }}</span>
          <van-icon name="arrow" color="#ccc" />
        </div>
      </div>
    </van-action-sheet>
  </div>
</template>

<style scoped>
.tasks-page {
  height: 100%;
  display: flex;
  flex-direction: column;
  background: #f5f5f5;
}

.task-list {
  padding: 12px;
  padding-bottom: 80px;
}

.empty-state {
  padding-top: 40px;
}

.task-card {
  background: #fff;
  border-radius: 12px;
  padding: 14px 16px;
  margin-bottom: 10px;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
}

.task-card--failed {
  border-left: 3px solid #e74c3c;
}

.task-header {
  display: flex;
  align-items: center;
  gap: 12px;
}

.task-icon {
  color: #4f6ef7;
  flex-shrink: 0;
}

.task-info {
  flex: 1;
  min-width: 0;
}

.task-title {
  font-size: 15px;
  font-weight: 500;
  color: #333;
  margin-bottom: 2px;
}

.task-status {
  font-size: 12px;
  color: #666;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.task-time {
  font-size: 11px;
  color: #999;
  margin-top: 2px;
}

.task-progress {
  margin-top: 10px;
}

.task-events {
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid #f0f0f0;
}

.task-event-item {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4px 0;
  font-size: 12px;
}

.event-comic {
  color: #333;
  flex: 1;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.event-result {
  color: #4f6ef7;
  margin-left: 8px;
  white-space: nowrap;
}

.fab-container {
  position: fixed;
  bottom: calc(env(safe-area-inset-bottom, 0px) + 70px);
  right: 20px;
  z-index: 100;
}

.fab-button {
  width: 52px;
  height: 52px;
  background: #4f6ef7;
  box-shadow: 0 4px 12px rgba(79, 110, 247, 0.4);
}

.action-list {
  padding: 8px 0 16px;
}

.action-item {
  display: flex;
  align-items: center;
  gap: 14px;
  padding: 14px 20px;
  cursor: pointer;
  transition: background 0.15s;
}

.action-item:active {
  background: #f5f5f5;
}

.action-name {
  flex: 1;
  font-size: 15px;
  color: #333;
}
</style>
