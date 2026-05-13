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

async function main() {
  const [action, sourcePath, keyword = '', page = '1'] = process.argv.slice(2)
  if (action !== 'search') {
    throw new Error(`unsupported runtime action: ${action}`)
  }

  const source = await loadSource(sourcePath)
  const data = await search(source, keyword, Number.parseInt(page, 10) || 1)
  json({ ok: true, data })
}

main().catch(fail)
