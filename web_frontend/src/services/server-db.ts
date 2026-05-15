import { apiPost } from './api'
import type { History, FavoriteItem, FavoriteFolder, ComicSource } from '../types'
import { normalizeComicSources, sourceKeyFromType } from '../utils/source'

function normalizeHistory(item: any): History {
  const type = Number(item?.type ?? 0)
  const readEpisode = Array.isArray(item?.readEpisode)
    ? item.readEpisode.map(String)
    : String(item?.readEpisode ?? '').split(',').filter(Boolean)
  return {
    ...item,
    type,
    sourceKey: item?.sourceKey ?? sourceKeyFromType(type),
    readEpisode,
    maxPage: item?.maxPage ?? item?.max_page ?? null,
    group: item?.group ?? item?.chapter_group ?? null,
  }
}

export async function listHistory(limit = 500, offset = 0): Promise<{ items: History[], total: number }> {
  const res = await apiPost<any>('/api/server-db/history/list', { limit, offset })
  const items = (res?.items ?? res ?? []).map(normalizeHistory)
  const total = res?.total ?? items.length
  return { items, total }
}

export async function upsertHistory(data: Partial<History>): Promise<void> {
  await apiPost('/api/server-db/history/upsert', { history: data })
}

export async function deleteHistory(id: string, type: number): Promise<void> {
  await apiPost('/api/server-db/history/delete', { id, type })
}

export async function clearHistory(): Promise<void> {
  await apiPost('/api/server-db/history/clear')
}

export async function listFolders(): Promise<FavoriteFolder[]> {
  const res = await apiPost<any>('/api/server-db/favorites/folders')
  return res?.folders ?? res ?? []
}

export async function listFavorites(folderId?: string): Promise<FavoriteItem[]> {
  const res = await apiPost<any>('/api/server-db/favorites/list', { folderId })
  return res?.favorites ?? res ?? []
}

export async function addFavorite(data: Partial<FavoriteItem>): Promise<void> {
  await apiPost('/api/server-db/favorites/add', data)
}

export async function deleteFavorite(favoriteId: string): Promise<void> {
  await apiPost('/api/server-db/favorites/delete', { favoriteId })
}

export async function moveFavorite(favoriteId: string, folderId: string): Promise<void> {
  await apiPost('/api/server-db/favorites/move', { favoriteId, folderId })
}

export async function createFolder(name: string): Promise<void> {
  await apiPost('/api/server-db/favorites/folder/create', { name })
}

export async function deleteFolder(folderId: string): Promise<void> {
  await apiPost('/api/server-db/favorites/folder/delete', { folderId })
}

export async function renameFolder(folderId: string, name: string): Promise<void> {
  await apiPost('/api/server-db/favorites/folder/rename', { folderId, name })
}

export async function reorderFolders(folderIds: string[]): Promise<void> {
  await apiPost('/api/server-db/favorites/folder/order', { folderIds })
}

export async function batchDeleteFavorites(favoriteIds: string[]): Promise<void> {
  await apiPost('/api/server-db/favorites/batch-delete', { favoriteIds })
}

export async function batchMoveFavorites(favoriteIds: string[], folderId: string): Promise<void> {
  await apiPost('/api/server-db/favorites/batch-move', { favoriteIds, folderId })
}

export async function getAppdata(): Promise<Record<string, any>> {
  const res = await apiPost<any>('/api/server-db/appdata')
  return res?.data ?? res ?? {}
}

export async function getComicSources(): Promise<ComicSource[]> {
  const res = await apiPost<any>('/api/server-db/comic-sources')
  const items = res?.items ?? res ?? []
  return normalizeComicSources(items)
}

export async function searchComics(sourceKey: string, keyword: string, page = 1, options?: Record<string, unknown>): Promise<{ comics: any[], hasMore: boolean }> {
  const res = await apiPost<any>('/api/server-db/search', { sourceKey, keyword, page, options })
  return { comics: res?.comics ?? [], hasMore: res?.hasMore ?? false }
}

export async function listImageFavorites(): Promise<any[]> {
  const res = await apiPost<any>('/api/server-db/image-favorites/list')
  return res?.items ?? res?.favorites ?? res ?? []
}
