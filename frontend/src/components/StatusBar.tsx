import { Activity, Globe, MapPin, WifiOff } from 'lucide-react'
import type { Mode, Status } from '../types'

interface Props {
  status: Status | null
  loading: boolean
}

export function StatusBar({ status, loading }: Props) {
  const modeIcon = () => {
    if (!status || status.mode === 'off') return <WifiOff className="w-4 h-4" />
    if (status.mode === 'global') return <Globe className="w-4 h-4" />
    return <MapPin className="w-4 h-4" />
  }

  const modeColor = (mode?: Mode) => {
    if (!mode || mode === 'off') return 'text-gray-400'
    if (mode === 'global') return 'text-emerald-400'
    return 'text-sky-400'
  }

  const dot = () => {
    if (loading) return <span className="w-2 h-2 rounded-full bg-yellow-400 animate-pulse" />
    if (!status || status.mode === 'off') return <span className="w-2 h-2 rounded-full bg-gray-500" />
    return <span className="w-2 h-2 rounded-full bg-emerald-400" />
  }

  return (
    <div className="flex items-center gap-6 px-4 py-2 bg-gray-900 border-b border-gray-800 text-sm">
      <div className="flex items-center gap-2 font-semibold text-white">
        <Activity className="w-4 h-4 text-sky-400" />
        ops_vpn
      </div>

      <div className="flex items-center gap-1.5">
        {dot()}
        <span className={modeColor(status?.mode)}>
          {loading ? 'connecting…' : status?.mode ?? 'off'}
        </span>
      </div>

      {status && status.mode !== 'off' && (
        <div className={`flex items-center gap-1 ${modeColor(status.mode)}`}>
          {modeIcon()}
          <span className="capitalize">{status.mode} mode</span>
        </div>
      )}

      <div className="ml-auto flex items-center gap-4 text-gray-500 font-mono text-xs">
        {status && (
          <>
            <span>SOCKS5 {status.local_socks5}</span>
            <span>HTTP {status.local_http}</span>
          </>
        )}
      </div>
    </div>
  )
}
