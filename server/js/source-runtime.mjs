import fs from 'node:fs/promises'
import vm from 'node:vm'

class ComicSource {
  loadSetting() {
    return null
  }
}

function json(value) {
  process.stdout.write(`${JSON.stringify(value)}\n`)
}

function fail(error) {
  json({ ok: false, error: error instanceof Error ? error.message : String(error) })
  process.exitCode = 1
}

function normalizeHeaders(headers) {
  return Object.fromEntries(headers.entries())
}

async function sendRequest(method, url, headers = {}, data = null) {
  const response = await fetch(url, {
    method,
    headers,
    body: data ?? undefined
  })
  return {
    status: response.status,
    headers: normalizeHeaders(response.headers),
    body: await response.text()
  }
}

const Network = {
  sendRequest,
  get: (url, headers) => sendRequest('GET', url, headers),
  post: (url, headers, data) => sendRequest('POST', url, headers, data),
  put: (url, headers, data) => sendRequest('PUT', url, headers, data),
  patch: (url, headers, data) => sendRequest('PATCH', url, headers, data),
  delete: (url, headers) => sendRequest('DELETE', url, headers)
}

function createContext() {
  const sandbox = {
    ComicSource,
    Network,
    URL,
    URLSearchParams,
    TextDecoder,
    TextEncoder,
    atob,
    btoa,
    fetch,
    setTimeout,
    clearTimeout,
    console: {
      log: (...args) => console.error('[source]', ...args),
      warn: (...args) => console.error('[source]', ...args),
      error: (...args) => console.error('[source]', ...args)
    }
  }
  sandbox.globalThis = sandbox
  return vm.createContext(sandbox)
}

async function loadSource(sourcePath) {
  const code = await fs.readFile(sourcePath, 'utf8')
  const match = code.match(/\bclass\s+([A-Za-z_$][\w$]*)\s+extends\s+ComicSource\b/)
  if (!match) {
    throw new Error('source must define class extends ComicSource')
  }

  const context = createContext()
  const script = new vm.Script(`${code}\nglobalThis.__SourceClass = ${match[1]};`, {
    filename: sourcePath
  })
  script.runInContext(context, { timeout: 5000 })
  const SourceClass = context.__SourceClass
  const source = new SourceClass()
  if (typeof source.init === 'function') {
    await source.init()
  }
  return source
}

function text(value) {
  if (value == null) return null
  return String(value)
}

function normalizeComic(item, index) {
  const raw = item && typeof item === 'object' ? item : { value: item }
  const title = text(raw.title ?? raw.name ?? raw.label ?? raw.id ?? `Comic ${index + 1}`) ?? ''
  const id = text(raw.id ?? raw.comicId ?? raw.url ?? raw.link ?? title) ?? title
  const tags = Array.isArray(raw.tags)
    ? raw.tags.map((tag) => String(tag))
    : raw.tag
      ? [String(raw.tag)]
      : []

  return {
    id,
    title,
    subtitle: text(raw.subtitle ?? raw.subTitle ?? raw.description ?? raw.author),
    cover: text(raw.cover ?? raw.coverUrl ?? raw.thumbnail ?? raw.pic ?? raw.image),
    url: text(raw.url ?? raw.link),
    tags,
    raw
  }
}

async function search(source, keyword, page) {
  if (typeof source.search?.load === 'function') {
    const result = await source.search.load(keyword, [], page)
    return normalizeSearchResult(result)
  }
  if (typeof source.search?.loadNext === 'function') {
    const result = await source.search.loadNext(keyword, [], null)
    return normalizeSearchResult(result)
  }
  throw new Error('source does not implement search.load')
}

async function comicInfo(source, comicId) {
  if (typeof source.comic?.loadInfo !== 'function') {
    throw new Error('source does not implement comic.loadInfo')
  }
  const result = await source.comic.loadInfo(comicId)
  return normalizeComicInfo(result, comicId)
}

async function comicPages(source, comicId, episodeId) {
  if (typeof source.comic?.loadEp !== 'function') {
    throw new Error('source does not implement comic.loadEp')
  }
  const result = await source.comic.loadEp(comicId, episodeId)
  const images = Array.isArray(result?.images)
    ? result.images
    : Array.isArray(result?.pages)
      ? result.pages
      : Array.isArray(result?.data)
        ? result.data
        : Array.isArray(result)
          ? result
          : []

  return {
    images: images.map((image) => String(image)).filter(Boolean)
  }
}

function normalizeSearchResult(result) {
  const comics = Array.isArray(result?.comics)
    ? result.comics
    : Array.isArray(result?.data)
      ? result.data
      : Array.isArray(result)
        ? result
        : []

  return {
    max_page: result?.maxPage ?? result?.max_page ?? null,
    next: result?.next ?? null,
    comics: comics.map(normalizeComic)
  }
}

function normalizeComicInfo(result, fallbackId) {
  const raw = result && typeof result === 'object' ? result : { value: result }
  const title = text(raw.title ?? raw.name ?? raw.label ?? fallbackId) ?? fallbackId
  return {
    id: text(raw.id ?? raw.comicId ?? fallbackId) ?? fallbackId,
    title,
    subtitle: text(raw.subtitle ?? raw.subTitle ?? raw.author),
    cover: text(raw.cover ?? raw.coverUrl ?? raw.thumbnail ?? raw.pic ?? raw.image),
    description: text(raw.description ?? raw.introduction ?? raw.summary),
    tags: normalizeTags(raw.tags ?? raw.categories),
    episodes: normalizeEpisodes(raw.episodes ?? raw.eps ?? raw.chapters ?? raw.chapter),
    raw
  }
}

function normalizeTags(value) {
  if (!Array.isArray(value)) return []
  return value.map((item) => String(item)).filter(Boolean)
}

function normalizeEpisodes(value) {
  const items = flattenEpisodes(value)
  return items.map((item, index) => {
    const raw = item && typeof item === 'object' ? item : { title: item }
    const title = text(raw.title ?? raw.name ?? raw.label ?? raw.id ?? `EP ${index + 1}`) ?? `EP ${index + 1}`
    return {
      id: text(raw.id ?? raw.epId ?? raw.chapterId ?? raw.url ?? title) ?? title,
      title
    }
  })
}

function flattenEpisodes(value) {
  if (Array.isArray(value)) return value
  if (!value || typeof value !== 'object') return []
  return Object.values(value).flatMap((item) => (Array.isArray(item) ? item : [item]))
}

async function main() {
  const [action, sourcePath, first = '', second = '1'] = process.argv.slice(2)
  const source = await loadSource(sourcePath)
  let data
  if (action === 'search') {
    data = await search(source, first, Number.parseInt(second, 10) || 1)
  } else if (action === 'info') {
    data = await comicInfo(source, first)
  } else if (action === 'pages') {
    data = await comicPages(source, first, second)
  } else {
    throw new Error(`unsupported runtime action: ${action}`)
  }
  json({ ok: true, data })
}

main().catch(fail)
