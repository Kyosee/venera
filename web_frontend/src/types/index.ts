export interface History {
  id: string
  type: number
  sourceKey?: string
  title: string
  subtitle: string
  cover: string
  time: number
  ep: number
  page: number
  group: number | null
  readEpisode: string[] | string
  maxPage: number | null
  max_page?: number | null
  chapter_group?: number | null
}

export interface FavoriteItem {
  id: string
  name: string
  author: string
  type: number
  tags: string[]
  coverPath: string
  time: string
  lastUpdateTime?: string
  hasNewUpdate?: boolean
  displayOrder?: number
  sourceKey?: string
}

export interface FavoriteFolder {
  id: string
  name: string
  order: number
}

export interface Comic {
  title: string
  cover: string
  id: string
  subtitle?: string
  tags?: string[]
  description: string
  sourceKey: string
  maxPage?: number
  stars?: number
  language?: string
  favoriteId?: string
}

export interface Chapter {
  title: string
  id: string
  group?: string
}

export interface ChapterGroup {
  title: string
  chapters: Chapter[]
}

export interface Comment {
  userName: string
  avatar?: string
  content: string
  time?: string
  replyCount?: number
  id?: string
  score?: number
  isLiked?: boolean
}

export interface ComicSource {
  name: string
  key: string
  version: string
  url: string
}

export interface SyncStatus {
  isDownloading: boolean
  isUploading: boolean
  lastError?: string
  isEnabled: boolean
}

export interface ApiResponse {
  ok: boolean
  [key: string]: any
}
