async function request(path, options = {}) {
  const res = await fetch(`/api${path}`, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    const body = await res.json().catch(() => ({}))
    const detail = Array.isArray(body.detail) ? body.detail.map((d) => d.msg).join(', ') : body.detail
    throw new Error(detail || `HTTP ${res.status}`)
  }
  return res.json()
}

export const api = {
  info: () => request('/info'),
  list: () => request('/trips'),
  create: (trip) => request('/trips', { method: 'POST', body: JSON.stringify(trip) }),
  update: (id, trip) => request(`/trips/${id}`, { method: 'PUT', body: JSON.stringify(trip) }),
  remove: (id) => request(`/trips/${id}`, { method: 'DELETE' }),
}
