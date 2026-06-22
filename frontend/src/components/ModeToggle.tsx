import type { Mode } from '../types'

interface Props {
  mode: Mode
  onChange: (mode: Mode) => void
  disabled?: boolean
}

const modes: { value: Mode; label: string; desc: string }[] = [
  { value: 'off', label: 'Off', desc: 'Direct connection' },
  { value: 'global', label: 'Global', desc: 'All traffic proxied' },
  { value: 'local', label: 'Local', desc: 'Manual per-app only' },
]

export function ModeToggle({ mode, onChange, disabled }: Props) {
  return (
    <div className="flex items-center gap-1 bg-gray-800 rounded-lg p-1">
      {modes.map((m) => (
        <button
          key={m.value}
          onClick={() => onChange(m.value)}
          disabled={disabled}
          title={m.desc}
          className={`px-3 py-1.5 rounded-md text-sm font-medium transition-colors ${
            mode === m.value
              ? 'bg-sky-600 text-white shadow'
              : 'text-gray-400 hover:text-white hover:bg-gray-700'
          } disabled:opacity-50 disabled:cursor-not-allowed`}
        >
          {m.label}
        </button>
      ))}
    </div>
  )
}
