import type { Endpoint, EndpointFormData, Mode, Status } from '../types'

const BASE = '/api'

async function request<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE}${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : {},
    body: body ? JSON.stringify(body) : undefined,
  })
  const data = await res.json()
  if (!res.ok) throw new Error(data.error ?? `HTTP ${res.status}`)
  return data as T
}

export const api = {
  // Endpoints
  listEndpoints: () => request<Endpoint[]>('GET', '/endpoints'),
  createEndpoint: (data: EndpointFormData) => request<Endpoint>('POST', '/endpoints', {
    label: data.label,
    protocol: data.protocol,
    host: data.host,
    port: parseInt(data.port, 10),
    tls: data.tls,
    enabled: data.enabled,
    auth: data.auth,
  }),
  updateEndpoint: (id: string, data: Partial<EndpointFormData>) =>
    request<Endpoint>('PUT', `/endpoints/${id}`, data),
  deleteEndpoint: (id: string) => request<{ ok: boolean }>('DELETE', `/endpoints/${id}`),

  // Connection
  connect: (id: string) => request<{ active: string; mode: Mode }>('POST', `/connect/${id}`),
  disconnect: () => request<{ ok: boolean }>('POST', '/disconnect'),

  // Mode
  getMode: () => request<{ mode: Mode }>('GET', '/mode'),
  setMode: (mode: Mode) => request<{ mode: Mode }>('POST', '/mode', { mode }),

  // Status
  getStatus: () => request<Status>('GET', '/status'),
}
