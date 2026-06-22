import { X } from 'lucide-react'
import { useState } from 'react'
import type { Auth, EndpointFormData, Protocol, SsCipher } from '../types'
import { defaultFormData, protocolDefaultPort, protocolLabel } from '../types'

interface Props {
  initial?: EndpointFormData
  onSave: (data: EndpointFormData) => void
  onCancel: () => void
  saving?: boolean
}

export function EndpointForm({ initial, onSave, onCancel, saving }: Props) {
  const [form, setForm] = useState<EndpointFormData>(initial ?? defaultFormData())

  const set = <K extends keyof EndpointFormData>(key: K, value: EndpointFormData[K]) =>
    setForm((f) => ({ ...f, [key]: value }))

  const setAuth = (auth: Auth) => set('auth', auth)

  const handleProtocolChange = (p: Protocol) => {
    set('protocol', p)
    set('port', protocolDefaultPort[p])
    // Reset auth to appropriate default
    if (p === 'shadowsocks') {
      setAuth({ type: 'shadowsocks', password: '', cipher: 'aes-256-gcm' })
    } else {
      setAuth({ type: 'none' })
    }
  }

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    onSave(form)
  }

  return (
    <div className="fixed inset-0 bg-black/60 flex items-center justify-center z-50 p-4">
      <div className="bg-gray-900 border border-gray-700 rounded-xl w-full max-w-md shadow-2xl">
        <div className="flex items-center justify-between px-5 py-4 border-b border-gray-800">
          <h2 className="text-white font-semibold">{initial ? 'Edit Endpoint' : 'Add Endpoint'}</h2>
          <button onClick={onCancel} className="text-gray-400 hover:text-white">
            <X className="w-5 h-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-5 space-y-4">
          {/* Label */}
          <Field label="Label">
            <input
              className={input}
              placeholder="My Proxy Node"
              value={form.label}
              onChange={(e) => set('label', e.target.value)}
              required
            />
          </Field>

          {/* Protocol */}
          <Field label="Protocol">
            <select
              className={input}
              value={form.protocol}
              onChange={(e) => handleProtocolChange(e.target.value as Protocol)}
            >
              {(Object.keys(protocolLabel) as Protocol[]).map((p) => (
                <option key={p} value={p}>{protocolLabel[p]}</option>
              ))}
            </select>
          </Field>

          {/* Host + Port */}
          <div className="flex gap-3">
            <Field label="Host" className="flex-1">
              <input
                className={input}
                placeholder="proxy.example.com"
                value={form.host}
                onChange={(e) => set('host', e.target.value)}
                required
              />
            </Field>
            <Field label="Port" className="w-24">
              <input
                className={input}
                type="number"
                min={1}
                max={65535}
                value={form.port}
                onChange={(e) => set('port', e.target.value)}
                required
              />
            </Field>
          </div>

          {/* Auth — adapts to protocol */}
          <AuthFields protocol={form.protocol} auth={form.auth} onChange={setAuth} />

          {/* TLS toggle */}
          {form.protocol !== 'shadowsocks' && (
            <label className="flex items-center gap-2 text-sm text-gray-300 cursor-pointer">
              <input
                type="checkbox"
                className="w-4 h-4 rounded"
                checked={form.tls}
                onChange={(e) => set('tls', e.target.checked)}
              />
              Use TLS
            </label>
          )}

          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={onCancel}
              className="flex-1 px-4 py-2 rounded-lg border border-gray-700 text-gray-300 hover:bg-gray-800 text-sm"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={saving}
              className="flex-1 px-4 py-2 rounded-lg bg-sky-600 hover:bg-sky-500 text-white font-medium text-sm disabled:opacity-50"
            >
              {saving ? 'Saving…' : 'Save'}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ---- Auth sub-form ----

function AuthFields({ protocol, auth, onChange }: {
  protocol: Protocol
  auth: Auth
  onChange: (a: Auth) => void
}) {
  if (protocol === 'shadowsocks') {
    const ss = auth.type === 'shadowsocks' ? auth : { type: 'shadowsocks' as const, password: '', cipher: 'aes-256-gcm' as SsCipher }
    return (
      <>
        <Field label="Password">
          <input
            className={input}
            type="password"
            placeholder="Shadowsocks password"
            value={ss.password}
            onChange={(e) => onChange({ ...ss, password: e.target.value })}
            required
          />
        </Field>
        <Field label="Cipher">
          <select
            className={input}
            value={ss.cipher}
            onChange={(e) => onChange({ ...ss, cipher: e.target.value as SsCipher })}
          >
            <option value="aes-256-gcm">AES-256-GCM</option>
            <option value="chacha20-poly1305">ChaCha20-Poly1305</option>
          </select>
        </Field>
      </>
    )
  }

  // SOCKS5 / HTTP CONNECT — optional user+pass
  const up = auth.type === 'userpass' ? auth : { type: 'userpass' as const, username: '', password: '' }
  const hasAuth = auth.type === 'userpass'

  return (
    <>
      <label className="flex items-center gap-2 text-sm text-gray-300 cursor-pointer">
        <input
          type="checkbox"
          className="w-4 h-4 rounded"
          checked={hasAuth}
          onChange={(e) => onChange(e.target.checked ? { type: 'userpass', username: '', password: '' } : { type: 'none' })}
        />
        Require authentication
      </label>
      {hasAuth && (
        <div className="flex gap-3">
          <Field label="Username" className="flex-1">
            <input
              className={input}
              value={up.username}
              onChange={(e) => onChange({ ...up, username: e.target.value })}
              required
            />
          </Field>
          <Field label="Password" className="flex-1">
            <input
              className={input}
              type="password"
              value={up.password}
              onChange={(e) => onChange({ ...up, password: e.target.value })}
              required
            />
          </Field>
        </div>
      )}
    </>
  )
}

// ---- Helpers ----

function Field({ label, children, className }: { label: string; children: React.ReactNode; className?: string }) {
  return (
    <div className={className}>
      <label className="block text-xs text-gray-400 mb-1">{label}</label>
      {children}
    </div>
  )
}

const input = 'w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2 text-sm text-white placeholder-gray-500 focus:outline-none focus:border-sky-500'
