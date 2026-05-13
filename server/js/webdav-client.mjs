import { mkdir, writeFile } from 'node:fs/promises'
import { dirname, basename } from 'node:path'

const [action, payloadText] = process.argv.slice(2)

function finish(payload) {
  process.stdout.write(JSON.stringify(payload))
}

function fail(error) {
  finish({ ok: false, error })
}

function textBetween(source, tag) {
  const escaped = tag.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  const match = source.match(new RegExp(`<[^>]*:?${escaped}[^>]*>([\\s\\S]*?)<\\/[^>]*:?${escaped}>`, 'i'))
  return match ? decodeXml(match[1].trim()) : ''
}

function decodeXml(value) {
  return value
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&apos;', "'")
}

function encodePath(path) {
  return path
    .split('/')
    .filter(Boolean)
    .map((part) => encodeURIComponent(part))
    .join('/')
}

function joinRemotePath(...parts) {
  const value = parts
    .flatMap((part) => String(part ?? '').split('/'))
    .filter(Boolean)
    .join('/')
  return value ? `/${value}` : '/'
}

function buildUrl(config, path) {
  const base = new URL(config.endpoint_url)
  const remotePath = joinRemotePath(base.pathname, config.root_path, path)
  base.pathname = encodePath(remotePath)
  return base
}

function authHeader(config) {
  if (!config.username) return {}
  const token = Buffer.from(`${config.username}:${config.password ?? ''}`).toString('base64')
  return { Authorization: `Basic ${token}` }
}

function responseBlocks(xml) {
  return Array.from(xml.matchAll(/<[^>]*:?response\b[^>]*>([\s\S]*?)<\/[^>]*:?response>/gi)).map(
    (match) => match[1]
  )
}

function relativePathFromHref(config, href) {
  let decoded = decodeURIComponent(href)
  try {
    decoded = decodeURIComponent(new URL(href).pathname)
  } catch {
    // href can be a path-only value.
  }

  const basePath = decodeURIComponent(buildUrl(config, '/').pathname)
  const baseNoSlash = basePath.replace(/\/+$/, '')
  if (decoded === baseNoSlash) {
    decoded = ''
  } else if (decoded.startsWith(`${baseNoSlash}/`)) {
    decoded = decoded.slice(baseNoSlash.length + 1)
  }
  return decoded.replace(/^\/+/, '').replace(/\/+$/, '')
}

async function list(config) {
  const url = buildUrl(config, config.path)
  const response = await fetch(url, {
    method: 'PROPFIND',
    headers: {
      ...authHeader(config),
      Depth: '1',
      'Content-Type': 'application/xml'
    },
    body: '<?xml version="1.0"?><propfind xmlns="DAV:"><prop><displayname/><resourcetype/><getcontentlength/><getlastmodified/></prop></propfind>'
  })

  if (!response.ok) {
    throw new Error(`webdav list returned ${response.status}`)
  }

  const xml = await response.text()
  const currentPath = joinRemotePath(config.path).replace(/^\/+/, '').replace(/\/+$/, '')
  const entries = responseBlocks(xml)
    .map((block) => {
      const href = textBetween(block, 'href')
      const path = relativePathFromHref(config, href)
      if (path === currentPath) return null
      const isDir = /<[^>]*:?collection\b/i.test(block)
      const displayName = textBetween(block, 'displayname')
      const name = displayName || basename(path)
      return {
        name,
        path,
        is_dir: isDir,
        size: Number(textBetween(block, 'getcontentlength')) || null,
        modified: textBetween(block, 'getlastmodified') || null
      }
    })
    .filter(Boolean)
    .sort((a, b) => Number(b.is_dir) - Number(a.is_dir) || a.name.localeCompare(b.name))

  return { path: currentPath, entries }
}

async function download(config) {
  if (!config.local_path) {
    throw new Error('missing local path')
  }
  const url = buildUrl(config, config.path)
  const response = await fetch(url, {
    method: 'GET',
    headers: authHeader(config)
  })
  if (!response.ok) {
    throw new Error(`webdav download returned ${response.status}`)
  }
  const buffer = new Uint8Array(await response.arrayBuffer())
  await mkdir(dirname(config.local_path), { recursive: true })
  await writeFile(config.local_path, buffer)

  return {
    path: joinRemotePath(config.path).replace(/^\/+/, ''),
    file_name: basename(config.local_path),
    local_path: config.local_path,
    size: buffer.byteLength,
    content_type: response.headers.get('content-type')
  }
}

try {
  if (!action || !payloadText) {
    throw new Error('missing webdav action or payload')
  }
  const config = JSON.parse(payloadText)
  if (action === 'list') {
    finish({ ok: true, data: await list(config) })
  } else if (action === 'download') {
    finish({ ok: true, data: await download(config) })
  } else {
    throw new Error(`unsupported webdav action: ${action}`)
  }
} catch (error) {
  fail(error instanceof Error ? error.message : String(error))
}
