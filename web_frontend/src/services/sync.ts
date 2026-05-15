import { apiPost } from './api'
import type { SyncStatus } from '../types'

export function getWebDavConfig() {
  return apiPost<{ ok: boolean; url?: string; user?: string; pass?: string; autoSync?: boolean }>('/sync/webdav/config/get')
}

export function saveWebDavConfig(url: string, user: string, pass: string, autoSync: boolean) {
  return apiPost('/sync/webdav/config/save', { url, user, pass, autoSync })
}

export function triggerDownload() {
  return apiPost('/sync/webdav/download', {})
}

export function triggerUpload() {
  return apiPost('/sync/webdav/upload', {})
}

export async function getSyncStatus(): Promise<SyncStatus> {
  const res = await apiPost<any>('/api/server-db/sync/webdav', { action: 'status' })
  return {
    isDownloading: res?.isDownloading ?? false,
    isUploading: res?.isUploading ?? false,
    lastError: res?.lastError,
    isEnabled: res?.isEnabled ?? false,
  }
}
