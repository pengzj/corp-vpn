import { CheckCircle2, Circle, Lock, MoreVertical, Plug, PlugZap, Trash2 } from 'lucide-react'
import { useState } from 'react'
import type { Endpoint } from '../types'
import { protocolLabel } from '../types'

interface Props {
  endpoints: Endpoint[]
  onConnect: (id: string) => void
  onDisconnect: () => void
  onDelete: (id: string) => void
  connecting: string | null
}

const protocolBadge: Record<string, string> = {
  socks5: 'bg-violet-900/60 text-violet-300',
  http_connect: 'bg-amber-900/60 text-amber-300',
  shadowsocks: 'bg-emerald-900/60 text-emerald-300',
}

const authBadgeColor: Record<string, string> = {
  none: 'text-gray-600',
  userpass: 'text-sky-500',
  shadowsocks: 'text-emerald-500',
}

export function EndpointList({ endpoints, onConnect, onDisconnect, onDelete, connecting }: Props) {
  const [menuOpen, setMenuOpen] = useState<string | null>(null)

  if (endpoints.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-gray-600">
        <Plug className="w-10 h-10 mb-3 opacity-40" />
        <p className="text-sm">No endpoints yet — add one to get started</p>
      </div>
    )
  }

  return (
    <div className="divide-y divide-gray-800">
      {endpoints.map((ep) => {
        const isConnecting = connecting === ep.id
        const isActive = ep.active

        return (
          <div
            key={ep.id}
            className={`flex items-center gap-4 px-5 py-4 hover:bg-gray-800/50 transition-colors ${
              isActive ? 'bg-sky-950/30' : ''
            }`}
          >
            {/* Status dot */}
            <div className="flex-shrink-0">
              {isActive ? (
                <CheckCircle2 className="w-5 h-5 text-emerald-400" />
              ) : (
                <Circle className="w-5 h-5 text-gray-600" />
              )}
            </div>

            {/* Info */}
            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="text-white font-medium truncate">{ep.label}</span>
                <span className={`text-xs px-1.5 py-0.5 rounded font-mono ${protocolBadge[ep.protocol] ?? 'bg-gray-700 text-gray-300'}`}>
                  {protocolLabel[ep.protocol]}
                </span>
                {ep.auth_type !== 'none' && (
                  <span title={`Auth: ${ep.auth_type}`}><Lock className={`w-3.5 h-3.5 ${authBadgeColor[ep.auth_type]}`} /></span>
                )}
                {!ep.enabled && (
                  <span className="text-xs text-gray-500 italic">disabled</span>
                )}
              </div>
              <div className="text-xs text-gray-500 font-mono mt-0.5">
                {ep.host}:{ep.port}
                {ep.tls && <span className="ml-2 text-sky-600">TLS</span>}
              </div>
            </div>

            {/* Connect / Disconnect button */}
            <div className="flex items-center gap-2 flex-shrink-0">
              {isActive ? (
                <button
                  onClick={onDisconnect}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-900/50 hover:bg-red-800/70 text-red-300 text-sm transition-colors"
                >
                  <PlugZap className="w-4 h-4" />
                  Disconnect
                </button>
              ) : (
                <button
                  onClick={() => onConnect(ep.id)}
                  disabled={isConnecting || !ep.enabled}
                  className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-sky-700/50 hover:bg-sky-600/70 text-sky-300 text-sm transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
                >
                  {isConnecting ? (
                    <span className="w-4 h-4 border-2 border-sky-400 border-t-transparent rounded-full animate-spin" />
                  ) : (
                    <Plug className="w-4 h-4" />
                  )}
                  Connect
                </button>
              )}

              {/* Actions menu */}
              <div className="relative">
                <button
                  onClick={() => setMenuOpen(menuOpen === ep.id ? null : ep.id)}
                  className="p-1.5 text-gray-500 hover:text-gray-300 rounded-lg hover:bg-gray-700"
                >
                  <MoreVertical className="w-4 h-4" />
                </button>
                {menuOpen === ep.id && (
                  <div className="absolute right-0 mt-1 w-36 bg-gray-800 border border-gray-700 rounded-lg shadow-xl z-10 overflow-hidden">
                    <button
                      onClick={() => { onDelete(ep.id); setMenuOpen(null) }}
                      className="flex items-center gap-2 w-full px-3 py-2 text-sm text-red-400 hover:bg-gray-700"
                    >
                      <Trash2 className="w-4 h-4" />
                      Delete
                    </button>
                  </div>
                )}
              </div>
            </div>
          </div>
        )
      })}
    </div>
  )
}
