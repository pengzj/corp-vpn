import type { Endpoint, EndpointFormData, Mode, Status } from '../types'

// Demo mode: when deployed to GitLab Pages (no backend available), show mock data
const IS_DEMO = typeof window !== 'undefined' && window.location.hostname !== 'localhost' && window.location.hostname !== '127.0.0.1'

const DEMO_ENDPOINTS: Endpoint[] = [
  { id: 'demo-1', label: 'SOCKS5 Example', protocol: 'socks5', host: 'proxy.example.com', port: 1080, tls: false, enabled: true, active: true, auth_type: 'none' },
  { id: 'demo-2', label: 'SS Node (AES)', protocol: 'shadowsocks', host: 'ss.example.com', port: 8388, tls: false, enabled: true, active: false, auth_type: 'shadowsocks' },
  { id: 'demo-3', label: 'HTTP Proxy', protocol: 'http_connect', host: 'http.example.com', port: 8080, tls: false, enabled: false, active: false, auth_type: 'userpass' },
]

const DEMO_STATUS: Status = {
  mode: 'global',
  endpoint_count: 3,
  active_endpoint_id: 'demo-1',
  local_socks5: '127.0.0.1:7890',
  local_http: '127.0.0.1:7891',
}

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
  listEndpoints: (): Promise<Endpoint[]> => IS_DEMO
    ? Promise.resolve(DEMO_ENDPOINTS)
    : request<Endpoint[]>('GET', '/endpoints'),

  createEndpoint: (data: EndpointFormData): Promise<Endpoint> => IS_DEMO
    ? Promise.resolve({ id: 'demo-new', label: data.label, protocol: data.protocol, host: data.host, port: parseInt(data.port, 10), tls: data.tls, enabled: data.enabled, active: false, auth_type: data.auth.type })
    : request<Endpoint>('POST', '/endpoints', { label: data.label, protocol: data.protocol, host: data.host, port: parseInt(data.port, 10), tls: data.tls, enabled: data.enabled, auth: data.auth }),

  updateEndpoint: (id: string, data: Partial<EndpointFormData>) =>
    IS_DEMO ? Promise.resolve(DEMO_ENDPOINTS[0]) : request<Endpoint>('PUT', `/endpoints/${id}`, data),

  deleteEndpoint: (id: string) =>
    IS_DEMO ? Promise.resolve({ ok: true }) : request<{ ok: boolean }>('DELETE', `/endpoints/${id}`),

  // Connection
  connect: (id: string): Promise<{ active: string; mode: Mode }> => IS_DEMO
    ? Promise.resolve({ active: id, mode: 'global' })
    : request<{ active: string; mode: Mode }>('POST', `/connect/${id}`),

  disconnect: () =>
    IS_DEMO ? Promise.resolve({ ok: true }) : request<{ ok: boolean }>('POST', '/disconnect'),

  // Mode
  getMode: (): Promise<{ mode: Mode }> => IS_DEMO
    ? Promise.resolve({ mode: 'global' })
    : request<{ mode: Mode }>('GET', '/mode'),

  setMode: (mode: Mode): Promise<{ mode: Mode }> => IS_DEMO
    ? Promise.resolve({ mode })
    : request<{ mode: Mode }>('POST', '/mode', { mode }),

  // Status
  getStatus: (): Promise<Status> => IS_DEMO
    ? Promise.resolve(DEMO_STATUS)
    : request<Status>('GET', '/status'),
}
