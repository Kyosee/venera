const API_BASE = ''  // same-origin

let _profile = localStorage.getItem('venera_profile') || 'default'

export function getProfile() { return _profile }
export function setProfile(p: string) { _profile = p; localStorage.setItem('venera_profile', p) }

export async function apiPost<T = any>(path: string, body: Record<string, unknown> = {}): Promise<T> {
  const res = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ profile: _profile, ...body })
  })
  if (!res.ok) {
    let detail = ''
    try {
      const errBody = await res.json()
      detail = errBody?.error || ''
    } catch { /* response not JSON */ }
    throw new Error(detail || `API ${path}: ${res.status}`)
  }
  return res.json()
}

export function imageProxyUrl(url: string, headers?: Record<string, string>): string {
  const params = new URLSearchParams({ url })
  if (headers) params.set('headers', JSON.stringify(headers))
  return `/api/image?${params}`
}
