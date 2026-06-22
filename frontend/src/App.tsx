import { Plus, RefreshCw } from 'lucide-react'
import { useCallback, useEffect, useState } from 'react'
import { api } from './api/client'
import { EndpointForm } from './components/EndpointForm'
import { EndpointList } from './components/EndpointList'
import { ModeToggle } from './components/ModeToggle'
import { StatusBar } from './components/StatusBar'
import type { Endpoint, EndpointFormData, Mode, Status } from './types'

export default function App() {
  const [endpoints, setEndpoints] = useState<Endpoint[]>([])
  const [status, setStatus] = useState<Status | null>(null)
  const [loadingStatus, setLoadingStatus] = useState(true)
  const [showForm, setShowForm] = useState(false)
  const [saving, setSaving] = useState(false)
  const [connecting, setConnecting] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const loadAll = useCallback(async () => {
    setLoadingStatus(true)
    try {
      const [eps, st] = await Promise.all([api.listEndpoints(), api.getStatus()])
      setEndpoints(eps)
      setStatus(st)
      setError(null)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to connect to backend')
    } finally {
      setLoadingStatus(false)
    }
  }, [])

  useEffect(() => {
    loadAll()
    const interval = setInterval(loadAll, 5000)
    return () => clearInterval(interval)
  }, [loadAll])

  const handleModeChange = async (mode: Mode) => {
    try {
      await api.setMode(mode)
      setStatus((s) => s ? { ...s, mode } : s)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to set mode')
    }
  }

  const handleConnect = async (id: string) => {
    setConnecting(id)
    try {
      const res = await api.connect(id)
      setEndpoints((eps) => eps.map((e) => ({ ...e, active: e.id === id })))
      setStatus((s) => s ? { ...s, active_endpoint_id: id, mode: res.mode } : s)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to connect')
    } finally {
      setConnecting(null)
    }
  }

  const handleDisconnect = async () => {
    try {
      await api.disconnect()
      setEndpoints((eps) => eps.map((e) => ({ ...e, active: false })))
      setStatus((s) => s ? { ...s, active_endpoint_id: null, mode: 'off' } : s)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to disconnect')
    }
  }

  const handleDelete = async (id: string) => {
    try {
      await api.deleteEndpoint(id)
      setEndpoints((eps) => eps.filter((e) => e.id !== id))
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to delete endpoint')
    }
  }

  const handleSave = async (data: EndpointFormData) => {
    setSaving(true)
    try {
      const ep = await api.createEndpoint(data)
      setEndpoints((eps) => [...eps, ep])
      setShowForm(false)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to save endpoint')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="min-h-screen bg-gray-950 text-white flex flex-col">
      <StatusBar status={status} loading={loadingStatus} />

      <div className="flex-1 max-w-3xl mx-auto w-full p-6 space-y-6">
        {/* Header row */}
        <div className="flex items-center justify-between gap-4 flex-wrap">
          <div>
            <h1 className="text-xl font-bold text-white">Proxy Endpoints</h1>
            <p className="text-sm text-gray-500 mt-0.5">
              {endpoints.length} endpoint{endpoints.length !== 1 ? 's' : ''}
            </p>
          </div>

          <div className="flex items-center gap-3">
            <ModeToggle
              mode={status?.mode ?? 'off'}
              onChange={handleModeChange}
              disabled={loadingStatus}
            />
            <button
              onClick={loadAll}
              disabled={loadingStatus}
              className="p-2 text-gray-400 hover:text-white hover:bg-gray-800 rounded-lg disabled:opacity-40"
              title="Refresh"
            >
              <RefreshCw className={`w-4 h-4 ${loadingStatus ? 'animate-spin' : ''}`} />
            </button>
            <button
              onClick={() => setShowForm(true)}
              className="flex items-center gap-1.5 px-4 py-2 bg-sky-600 hover:bg-sky-500 rounded-lg text-sm font-medium transition-colors"
            >
              <Plus className="w-4 h-4" />
              Add
            </button>
          </div>
        </div>

        {/* Error banner */}
        {error && (
          <div className="bg-red-950/60 border border-red-800 rounded-lg px-4 py-3 text-sm text-red-300 flex items-center justify-between">
            <span>{error}</span>
            <button onClick={() => setError(null)} className="text-red-400 hover:text-red-200 ml-4">✕</button>
          </div>
        )}

        {/* Endpoint list */}
        <div className="bg-gray-900 border border-gray-800 rounded-xl overflow-hidden">
          <EndpointList
            endpoints={endpoints}
            onConnect={handleConnect}
            onDisconnect={handleDisconnect}
            onDelete={handleDelete}
            connecting={connecting}
          />
        </div>

        {/* Local proxy info */}
        {status && (
          <div className="bg-gray-900/60 border border-gray-800 rounded-xl p-4">
            <p className="text-xs text-gray-500 uppercase tracking-wide mb-3 font-semibold">Local Proxy Addresses</p>
            <div className="grid grid-cols-2 gap-3">
              <ProxyAddr label="SOCKS5" addr={status.local_socks5} />
              <ProxyAddr label="HTTP CONNECT" addr={status.local_http} />
            </div>
            <p className="text-xs text-gray-600 mt-3">
              Point your apps at these addresses to route traffic through the active endpoint.
            </p>
          </div>
        )}
      </div>

      {showForm && (
        <EndpointForm
          onSave={handleSave}
          onCancel={() => setShowForm(false)}
          saving={saving}
        />
      )}
    </div>
  )
}

function ProxyAddr({ label, addr }: { label: string; addr: string }) {
  return (
    <div className="bg-gray-800/60 rounded-lg px-3 py-2">
      <p className="text-xs text-gray-500 mb-1">{label}</p>
      <p className="font-mono text-sm text-sky-300">{addr}</p>
    </div>
  )
}
