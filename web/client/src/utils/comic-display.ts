export type ComicLike = Record<string, any>

export interface ParsedComicTags {
  authors: string[]
  statuses: string[]
  updates: string[]
  contentTags: string[]
}

export interface ComicDisplayInfo {
  title: string
  cover: string
  author: string
  status: string
  update: string
  tags: string[]
  rating: number
  description: string
  briefLines: string[]
}

const authorNamespaces = new Set([
  'author',
  'artist',
  'authors',
  'artists',
  'creator',
  '原作',
  '作者',
  '作家',
  '作画',
  '作畫',
  '漫畫',
  '漫画',
  '画师',
  '著者',
  '绘师',
  '繪師',
])
const statusNamespaces = new Set(['status', 'state', 'serialization', '連載', '连载', '狀態', '状态'])
const updateNamespaces = new Set([
  'date',
  'lastupdate',
  'time',
  'update',
  'updated',
  '更新',
  '最後更新',
  '最后更新',
  '時間',
  '时间',
  '日期',
])
const pagesNamespaces = new Set(['page', 'pages', '頁數', '页数'])
const tagNamespaces = new Set(['标签', 'tag', 'tags', 'genre', '类型', '類型'])
const metadataNamespaces = new Set([
  ...authorNamespaces,
  ...statusNamespaces,
  ...updateNamespaces,
  ...pagesNamespaces,
  'language',
  'source',
  'uploader',
  '語言',
  '语言',
  '來源',
  '来源',
  '上傳者',
  '上传者',
  ...tagNamespaces,
])

export function cleanComicText(value: unknown): string {
  const text = String(value || '').replace(/\n/g, ' ').trim()
  if (!text || text === 'Unknown' || text.startsWith('Unknown:') || text.startsWith('__')) return ''
  return text
}

export function comicTitle(comic: ComicLike): string {
  return String(comic.title || comic.name || '').replace(/\n/g, '')
}

export function comicCover(comic: ComicLike): string {
  return String(comic.cover || comic.coverPath || '')
}

function normalizeNamespace(value: string) {
  return value.trim().toLowerCase().replace(/\s+/g, '')
}

function hasTagContent(value: unknown) {
  if (Array.isArray(value)) return value.length > 0
  if (typeof value === 'string') return value.trim().length > 0
  return !!value && typeof value === 'object' && Object.keys(value as Record<string, unknown>).length > 0
}

function collectTags(raw: unknown, namespace?: string): string[] {
  if (Array.isArray(raw)) return raw.flatMap(item => collectTags(item, namespace))
  if (raw && typeof raw === 'object') {
    const record = raw as Record<string, unknown>
    const nsValue = record.namespace ?? record.nameSpace ?? record.ns
    const tagValue = record.value ?? record.tag ?? record.label ?? record.text
    if (tagValue != null && (nsValue != null || Object.prototype.hasOwnProperty.call(record, 'value'))) {
      return collectTags(tagValue, nsValue == null ? namespace : String(nsValue))
    }
    return Object.entries(record).flatMap(([key, value]) => collectTags(value, key))
  }
  const text = String(raw || '').trim()
  if (!text) return []
  return text.split(',').map(s => s.trim()).filter(Boolean).map(value => {
    if (!namespace || /[:：]/.test(value)) return value
    return `${namespace}:${value}`
  })
}

function tagSeparatorIndex(value: string) {
  const indexes = [value.indexOf(':'), value.indexOf('：')].filter(index => index >= 0)
  return indexes.length ? Math.min(...indexes) : -1
}

export function normalizeComicTags(raw: unknown): string[] {
  return [...new Set(collectTags(raw).filter(tag => cleanComicText(tag)))]
}

export function parseComicTags(comic: ComicLike): ParsedComicTags {
  const rawTags = comic.tags
  const raw = hasTagContent(rawTags) ? rawTags : comic.translatedTags
  const items = collectTags(raw)
  const authors: string[] = []
  const statuses: string[] = []
  const updates: string[] = []
  const contentTags: string[] = []

  for (const item of items) {
    const trimmed = cleanComicText(item)
    if (!trimmed) continue
    const colonIdx = tagSeparatorIndex(trimmed)
    if (colonIdx === -1) {
      contentTags.push(trimmed)
      continue
    }
    const namespace = normalizeNamespace(trimmed.substring(0, colonIdx))
    const value = cleanComicText(trimmed.substring(colonIdx + 1))
    if (!value) continue
    if (authorNamespaces.has(namespace)) authors.push(value)
    else if (statusNamespaces.has(namespace)) statuses.push(value)
    else if (updateNamespaces.has(namespace)) updates.push(value)
    else if (tagNamespaces.has(namespace)) contentTags.push(value)
    else if (!pagesNamespaces.has(namespace) && !metadataNamespaces.has(namespace)) contentTags.push(value)
  }

  return {
    authors: [...new Set(authors)],
    statuses: [...new Set(statuses)],
    updates: [...new Set(updates)],
    contentTags: [...new Set(contentTags)],
  }
}

export function comicAuthorText(comic: ComicLike): string {
  return cleanComicText(comic.author || comic.subtitle || comic.subTitle || comic.sub_title) || parseComicTags(comic).authors.join(', ')
}

export function comicStatusText(comic: ComicLike): string {
  return cleanComicText(comic.status) || parseComicTags(comic).statuses[0] || ''
}

export function comicUpdateText(comic: ComicLike): string {
  const direct = cleanComicText(comic.updateTime || comic.lastUpdateTime || comic.last_update_time || comic.update)
  if (direct) return direct
  const ts = Number(comic.time || comic.updateTime || comic.lastUpdateTime)
  if (Number.isFinite(ts) && ts > 0) {
    const d = new Date(ts < 1e12 ? ts * 1000 : ts)
    if (!Number.isNaN(d.getTime())) {
      return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
    }
  }
  return parseComicTags(comic).updates[0] || ''
}

export function comicVisibleTags(comic: ComicLike, limit = 5): string[] {
  const tags = parseComicTags(comic).contentTags
  return Number.isFinite(limit) ? tags.slice(0, limit) : tags
}

export function comicRatingValue(comic: ComicLike): number {
  const value = Number(comic.stars || comic.rating || 0)
  return value > 0 && value <= 5 ? value : 0
}

export function comicDescriptionText(comic: ComicLike): string {
  return String(comic.description || '').replace(/\|/g, '\n').replace(/\n/g, ' ').trim()
}

export function comicBriefLines(comic: ComicLike): string[] {
  return String(comic.description || comic.subtitle || comic.subTitle || comic.sub_title || '')
    .replace(/\|/g, '\n')
    .split('\n')
    .map(line => line.trim())
    .filter(Boolean)
    .slice(0, 3)
}

export function comicDisplayInfo(comic: ComicLike, tagLimit = 5): ComicDisplayInfo {
  const tags = Number.isFinite(tagLimit) ? comicVisibleTags(comic, tagLimit) : comicVisibleTags(comic, Number.POSITIVE_INFINITY)
  return {
    title: comicTitle(comic),
    cover: comicCover(comic),
    author: comicAuthorText(comic),
    status: comicStatusText(comic),
    update: comicUpdateText(comic),
    tags,
    rating: comicRatingValue(comic),
    description: comicDescriptionText(comic),
    briefLines: comicBriefLines(comic),
  }
}

/** Extract the comic id from any comic-like object. */
export function extractComicId(comic: ComicLike): string {
  return String(comic.id || '')
}

/** Extract sourceKey from a comic-like object. Falls back to provided key. */
export function extractSourceKey(comic: ComicLike, fallback?: string): string {
  const fromComic = comic.sourceKey || comic.source_key || comic.source
  if (fromComic) return String(fromComic)
  return fallback || ''
}

export interface ReadProgressInfo {
  page: number
  maxPage?: number
}

/** Extract read progress from a History item or similar object. */
export function extractReadProgress(comic: ComicLike): ReadProgressInfo | undefined {
  const page = Number(comic.page)
  if (!Number.isFinite(page) || page <= 0) return undefined
  const maxPage = comic.maxPage ?? comic.max_page
  const max = maxPage != null ? Number(maxPage) : undefined
  return { page, maxPage: max != null && Number.isFinite(max) && max > 0 ? max : undefined }
}
