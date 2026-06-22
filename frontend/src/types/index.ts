export type Protocol = 'socks5' | 'http_connect' | 'shadowsocks'
export type Mode = 'off' | 'global' | 'local'
export type AuthType = 'none' | 'userpass' | 'shadowsocks'
export type SsCipher = 'aes-256-gcm' | 'chacha20-poly1305'

export interface AuthNone {
  type: 'none'
}
export interface AuthUserpass {
  type: 'userpass'
  username: string
  password: string
}
export interface AuthShadowsocks {
  type: 'shadowsocks'
  password: string
  cipher: SsCipher
}
export type Auth = AuthNone | AuthUserpass | AuthShadowsocks

export interface Endpoint {
  id: string
  label: string
  protocol: Protocol
  host: string
  port: number
  tls: boolean
  enabled: boolean
  active: boolean
  auth_type: AuthType
  // auth only present when creating/editing, not returned by API
  auth?: Auth
}

export interface Status {
  mode: Mode
  endpoint_count: number
  active_endpoint_id: string | null
  local_socks5: string
  local_http: string
}

// Form state for creating/editing an endpoint
export interface EndpointFormData {
  label: string
  protocol: Protocol
  host: string
  port: string
  tls: boolean
  enabled: boolean
  auth: Auth
}

export const defaultFormData = (): EndpointFormData => ({
  label: '',
  protocol: 'socks5',
  host: '',
  port: '1080',
  tls: false,
  enabled: true,
  auth: { type: 'none' },
})

export const protocolLabel: Record<Protocol, string> = {
  socks5: 'SOCKS5',
  http_connect: 'HTTP CONNECT',
  shadowsocks: 'Shadowsocks',
}

export const protocolDefaultPort: Record<Protocol, string> = {
  socks5: '1080',
  http_connect: '8080',
  shadowsocks: '8388',
}
