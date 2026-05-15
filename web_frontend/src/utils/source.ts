export interface SourceKeyItem {
  sourceKey?: string | null
  source_key?: string | null
  type?: number | string | null
}

export interface SourceKeySource {
  key?: string | null
  canonicalKey?: string | null
  canonical_key?: string | null
  type?: number | string | null
  intKey?: number | string | null
  int_key?: number | string | null
  legacyInt?: number | string | null
  legacyIntType?: number | string | null
  legacy_int_type?: number | string | null
}

export interface NormalizedComicSource extends SourceKeySource {
  name: string
  key: string
  version: string
  url: string
  [key: string]: unknown
}

const LEGACY_SOURCE_KEYS: Record<number, string> = {
  0: 'local',
  1: 'ehentai',
  2: 'jm',
  3: 'hitomi',
  4: 'wnacg',
  5: 'nhentai',
  6: 'nhentai',
  29663848: 'hot_manga',
  42816288: 'manwaba',
  150465061: 'zaimanhua',
  233488852: 'baozi',
  236897507: 'hcomic',
  258019538: 'hitomi',
  264196719: 'nhentai',
  331263271: 'shonen_jump_plus',
  385625716: 'ehentai',
  550146035: 'goda',
  553570794: 'picacg',
  557997769: 'copy_manga',
  577341847: 'mh1234',
  577718694: 'manga_dex',
  631413104: 'manhuaren',
  637999886: 'Komiic',
  716010982: 'ikmmh',
  740690276: 'jcomic',
  769844263: 'jm',
  771282371: 'mxs',
  778108598: 'mh18',
  798816513: 'ykmh',
  807338462: 'ccc',
  823512256: 'wnacg',
  964788560: 'comick',
  977805693: 'happy',
  981441865: 'ManHuaGui',
}

function stringValue(value: unknown): string {
  return typeof value === 'string' ? value.trim() : ''
}

function numberValue(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value
  if (typeof value !== 'string' || !value.trim()) return null
  const parsed = Number(value)
  return Number.isFinite(parsed) ? parsed : null
}

function sourceLegacyType(source: SourceKeySource): number | null {
  const candidates = [
    source.type,
    source.intKey,
    source.int_key,
    source.legacyInt,
    source.legacyIntType,
    source.legacy_int_type,
  ]
  for (const candidate of candidates) {
    const value = numberValue(candidate)
    if (value !== null) return value
  }
  return null
}

function sourceDisplayName(source: Record<string, unknown>): string {
  const name = stringValue(source.name)
  return name.replace(/^comic_source[\\/]/, '').replace(/\.js$/i, '').replace(/\s*\(\d+\)$/i, '')
}

function decodeBase64Text(value: unknown): string {
  const dataBase64 = stringValue(value)
  if (!dataBase64) return ''
  try {
    const binary = atob(dataBase64)
    const bytes = Uint8Array.from(binary, char => char.charCodeAt(0))
    return new TextDecoder().decode(bytes)
  } catch {
    return ''
  }
}

function extractScriptMeta(script: string): Partial<NormalizedComicSource> {
  const pick = (keys: string[]) => {
    for (const key of keys) {
      const match = script.match(new RegExp(`${key}\\s*[:=]\\s*['"\`]([^'"\`]+)['"\`]`))
      if (match?.[1]) return match[1].trim()
    }
    return ''
  }
  return {
    key: pick(['key', 'sourceKey']),
    name: pick(['name', 'title', 'displayName']),
    version: pick(['version']),
    url: pick(['url', 'website']),
  } as Partial<NormalizedComicSource>
}

function stableSourceTypeHash(sourceKey: string): number {
  let hash = 0
  for (let i = 0; i < sourceKey.length; i++) {
    hash = ((hash * 31) + sourceKey.charCodeAt(i)) | 0
  }
  return Math.abs(hash)
}

export function normalizeComicSource(item: unknown): NormalizedComicSource | null {
  if (!item || typeof item !== 'object') return null

  const source = item as Record<string, unknown>
  const rawName = stringValue(source.name)
  const rawKey = stringValue(source.key)
  const filename = (rawName || rawKey).replace(/^comic_source[\\/]/, '')
  if (filename.toLowerCase().endsWith('.data')) return null

  const scriptMeta = extractScriptMeta(decodeBase64Text(source.dataBase64))
  const derivedName = sourceDisplayName(source) || rawKey
  const executableKey = rawKey || filename.replace(/\.js$/i, '')
  const canonicalKey = stringValue(scriptMeta.key) || executableKey.replace(/\s*\(\d+\)$/i, '') || derivedName
  const key = executableKey || canonicalKey
  if (!key) return null

  const name = rawName && !rawName.toLowerCase().endsWith('.js')
    ? rawName
    : stringValue(scriptMeta.name) || derivedName || key
  return {
    ...source,
    name,
    key,
    canonicalKey,
    version: stringValue(source.version) || stringValue(scriptMeta.version),
    url: stringValue(source.url) || stringValue(scriptMeta.url),
  } as NormalizedComicSource
}

export function normalizeComicSources(items: unknown[]): NormalizedComicSource[] {
  const result: NormalizedComicSource[] = []
  const seen = new Set<string>()

  for (const item of items) {
    const source = normalizeComicSource(item)
    if (!source) continue

    const dedupeKey = stringValue(source.canonicalKey) || source.key
    if (seen.has(dedupeKey)) continue

    seen.add(dedupeKey)
    result.push(source)
  }

  return result.sort((a, b) => a.name.localeCompare(b.name))
}

export function sourceKeyFromType(type: number | string | null | undefined): string {
  const value = numberValue(type)
  if (value === null) return stringValue(type)
  return LEGACY_SOURCE_KEYS[value] ?? `Unknown:${value}`
}

export function sourceTypeFromKey(sourceKey: string | number | null | undefined): number {
  if (typeof sourceKey === 'number' && Number.isFinite(sourceKey)) return sourceKey
  const key = stringValue(sourceKey)
  if (!key || key === 'local') return 0
  if (/^-?\d+$/.test(key)) return Number(key)
  if (key.startsWith('Unknown:')) return Number(key.slice('Unknown:'.length)) || 0
  const legacy = Object.entries(LEGACY_SOURCE_KEYS)
    .find(([, value]) => value === key)
  if (legacy) return Number(legacy[0])
  return stableSourceTypeHash(key)
}

export function resolveSourceKey(
  item: SourceKeyItem,
  sources: SourceKeySource[] = [],
  fallback = 'local',
): string {
  const explicit = stringValue(item.sourceKey) || stringValue(item.source_key)
  if (explicit) {
    const matched = sources.find(source => {
      const key = stringValue(source.key)
      const canonicalKey = stringValue(source.canonicalKey) || stringValue(source.canonical_key) || key
      return key === explicit || canonicalKey === explicit
    })
    return stringValue(matched?.key) || explicit
  }

  const type = numberValue(item.type)
  if (type === null) return fallback
  if (type === 0) return 'local'

  const canonicalKey = sourceKeyFromType(type)
  const matched = sources.find(source => {
    if (!source.key) return false
    const sourceCanonicalKey = stringValue(source.canonicalKey) || stringValue(source.canonical_key) || stringValue(source.key)
    return sourceLegacyType(source) === type || sourceCanonicalKey === canonicalKey
  })
  return stringValue(matched?.key) || sourceKeyFromType(type)
}
