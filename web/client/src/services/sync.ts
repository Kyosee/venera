import { apiPost } from './api'
import type { SyncStatus } from '../types'

export interface WebDavConfig {
  ok: boolean
  configured?: boolean
  url?: string
  user?: string
  pass?: string
  autoSync?: boolean
  disableSyncFields?: string
}

export type WebDavSyncStatus = SyncStatus & {
  configured: boolean
  autoSyncEnabled: boolean
}

export function getWebDavConfig() {
  return apiPost<WebDavConfig>('/sync/webdav/config/get')
}

export function saveWebDavConfig(
  url: string,
  user: string,
  pass: string,
  autoSync: boolean,
  disableSyncFields = '',
) {
  return apiPost<WebDavConfig>('/sync/webdav/config/save', { url, user, pass, autoSync, disableSyncFields })
}

export function triggerDownload() {
  return apiPost('/api/server-db/sync/webdav', {})
}

export function checkSyncSafety() {
  return apiPost<{
    ok: boolean
    hasCompletedInitialSync: boolean
    favoriteDbEmpty: boolean
    followFolderEmpty: boolean
  }>('/api/server-db/sync/safety-check')
}

function dataVersionFrom(appdata: Record<string, any>): number {
  const settings = appdata.settings
  const value = settings && typeof settings === 'object' ? settings.dataVersion : appdata.dataVersion
  const version = typeof value === 'number' ? value : Number(value)
  return Number.isFinite(version) ? Math.trunc(version) : 0
}

function cloneRecord(value: unknown): Record<string, any> {
  if (!value || typeof value !== 'object') return {}
  return JSON.parse(JSON.stringify(value))
}

function splitDisableSyncFields(value: string | undefined): string[] {
  return String(value || '')
    .split(',')
    .map(item => item.trim())
    .filter(Boolean)
}

function appdataSettings(appdata: Record<string, any>) {
  if (!appdata.settings || typeof appdata.settings !== 'object') {
    const existing = Object.keys(appdata).length ? { ...appdata } : {}
    appdata.settings = existing
  }
  if (!Array.isArray(appdata.searchHistory)) appdata.searchHistory = []
  return appdata.settings as Record<string, any>
}

const FIXED_DISABLE_SYNC_FIELDS = [
  'proxy',
  'authorizationRequired',
  'customImageProcessing',
  'webdav',
  'disableSyncFields',
  'deviceId',
  'followUpdatesFolder',
  'updateRepoOwner',
  'updateRepoName',
  'updateUsePrivateRepo',
  'updateRepoToken',
]

function appdataForUpload(appdata: Record<string, any>, dataVersion: number, disableSyncFields?: string) {
  const next = cloneRecord(appdata)
  const hadNestedSettings = next.settings && typeof next.settings === 'object'
  const settings = appdataSettings(next)
  settings.dataVersion = dataVersion
  for (const field of FIXED_DISABLE_SYNC_FIELDS) {
    delete settings[field]
    delete next[field]
  }
  for (const field of splitDisableSyncFields(disableSyncFields)) {
    delete settings[field]
    if (!hadNestedSettings) delete next[field]
  }
  return next
}

function appdataForLocalSave(appdata: Record<string, any>, dataVersion: number) {
  const next = cloneRecord(appdata)
  const settings = appdataSettings(next)
  settings.dataVersion = dataVersion
  return next
}

export async function triggerUpload(options?: { force?: boolean }) {
  const [config, dump] = await Promise.all([
    getWebDavConfig(),
    apiPost<any>('/api/server-db/dump'),
  ])
  const configured = config.configured === true || !!(config.url && config.user)
  if (!configured) {
    throw new Error('WebDAV 尚未配置')
  }

  const previousAppdata = cloneRecord(dump?.appdata)
  const previousVersion = dataVersionFrom(previousAppdata)
  const nextVersion = previousVersion + 1
  const daysSinceEpoch = Math.floor(Date.now() / 86400000)
  const fileName = `${daysSinceEpoch}-${nextVersion}.web.venera`
  const localAppdata = appdataForLocalSave(previousAppdata, nextVersion)
  const uploadAppdata = appdataForUpload(previousAppdata, nextVersion, config.disableSyncFields)
  const payload: Record<string, unknown> = {
    fileName,
    appdata: uploadAppdata,
    metadata: { dataVersion: nextVersion },
  }
  if (options?.force) {
    payload.force = true
  }
  if (Array.isArray(dump?.comicSources)) {
    payload.comicSources = dump.comicSources
  }

  try {
    const result = await apiPost('/api/server-db/upload/webdav', payload)
    await apiPost('/api/server-db/appdata/save', { data: localAppdata })
    return result
  } catch (error) {
    await apiPost('/api/server-db/appdata/save', { data: previousAppdata }).catch(() => {})
    throw error
  }
}

export interface SyncLogEntry {
  time: number
  action: string
  fileName: string | null
  success: boolean
  error: string | null
}

export function getSyncLogs() {
  return apiPost<{ ok: boolean; logs: SyncLogEntry[] }>('/sync/webdav/logs')
}

export async function getSyncStatus(): Promise<WebDavSyncStatus> {
  const [statusResult, configResult] = await Promise.allSettled([
    apiPost<any>('/api/server-db/status'),
    getWebDavConfig(),
  ])
  const status = statusResult.status === 'fulfilled' ? statusResult.value : null
  const config = configResult.status === 'fulfilled' ? configResult.value : null
  const configured = !!(config && (config.configured === true || (config.url && config.user)))
  const lastError = status?.metadata?.lastError
    || (statusResult.status === 'rejected' ? statusResult.reason?.message : undefined)
    || (configResult.status === 'rejected' ? configResult.reason?.message : undefined)
  return {
    isDownloading: false,
    isUploading: false,
    lastError,
    isEnabled: configured,
    configured,
    autoSyncEnabled: configured && config?.autoSync === true,
  }
}

export interface RemoteBackupInfo {
  fileName: string
  version: number
  platform: string
  date: string
}

export async function listBackups(): Promise<RemoteBackupInfo[]> {
  const data = await apiPost<{ ok: boolean; files: string[] }>('/sync/webdav/list')
  const files = data.files || []
  return files
    .filter(f => f.endsWith('.venera'))
    .map(parseBackupFileName)
    .sort((a, b) => b.version - a.version)
}

function parseBackupFileName(name: string): RemoteBackupInfo {
  const base = name.replace('.venera', '')
  const parts = base.split('-')
  const daysSinceEpoch = parseInt(parts[0] || '0', 10)
  const versionPart = parts[1] || '0'
  const dotParts = versionPart.split('.')
  const version = parseInt(dotParts[0] || '0', 10)
  const platform = dotParts[1] || 'unknown'
  const date = new Date(daysSinceEpoch * 86400000).toISOString().slice(0, 10)
  return { fileName: name, version, platform, date }
}

export async function downloadSpecificBackup(fileName: string) {
  return apiPost('/sync/webdav/download', { remoteFileName: fileName, force: true })
}
