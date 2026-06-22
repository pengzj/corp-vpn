import { describe, it, expect } from 'vitest'
import {
  defaultFormData,
  protocolLabel,
  protocolDefaultPort,
  type Protocol,
  type Mode,
  type Auth,
} from './index'

describe('defaultFormData', () => {
  it('returns socks5 as default protocol', () => {
    const form = defaultFormData()
    expect(form.protocol).toBe('socks5')
  })

  it('returns default port 1080 for socks5', () => {
    const form = defaultFormData()
    expect(form.port).toBe('1080')
  })

  it('returns auth type none by default', () => {
    const form = defaultFormData()
    expect(form.auth.type).toBe('none')
  })

  it('returns enabled true by default', () => {
    const form = defaultFormData()
    expect(form.enabled).toBe(true)
  })

  it('returns tls false by default', () => {
    const form = defaultFormData()
    expect(form.tls).toBe(false)
  })

  it('returns empty label and host by default', () => {
    const form = defaultFormData()
    expect(form.label).toBe('')
    expect(form.host).toBe('')
  })
})

describe('protocolLabel', () => {
  it('has correct label for socks5', () => {
    expect(protocolLabel['socks5']).toBe('SOCKS5')
  })

  it('has correct label for http_connect', () => {
    expect(protocolLabel['http_connect']).toBe('HTTP CONNECT')
  })

  it('has correct label for shadowsocks', () => {
    expect(protocolLabel['shadowsocks']).toBe('Shadowsocks')
  })

  it('covers all supported protocols', () => {
    const protocols: Protocol[] = ['socks5', 'http_connect', 'shadowsocks']
    for (const p of protocols) {
      expect(protocolLabel[p]).toBeTruthy()
    }
  })
})

describe('protocolDefaultPort', () => {
  it('socks5 defaults to 1080', () => {
    expect(protocolDefaultPort['socks5']).toBe('1080')
  })

  it('http_connect defaults to 8080', () => {
    expect(protocolDefaultPort['http_connect']).toBe('8080')
  })

  it('shadowsocks defaults to 8388', () => {
    expect(protocolDefaultPort['shadowsocks']).toBe('8388')
  })

  it('all ports are valid numeric strings', () => {
    const protocols: Protocol[] = ['socks5', 'http_connect', 'shadowsocks']
    for (const p of protocols) {
      const port = parseInt(protocolDefaultPort[p], 10)
      expect(port).toBeGreaterThan(0)
      expect(port).toBeLessThanOrEqual(65535)
    }
  })
})

describe('Protocol type coverage', () => {
  it('socks5 is a valid protocol', () => {
    const p: Protocol = 'socks5'
    expect(p).toBe('socks5')
  })

  it('shadowsocks auth requires password and cipher', () => {
    const auth: Auth = {
      type: 'shadowsocks',
      password: 'secret',
      cipher: 'aes-256-gcm',
    }
    expect(auth.type).toBe('shadowsocks')
    if (auth.type === 'shadowsocks') {
      expect(auth.cipher).toBe('aes-256-gcm')
      expect(auth.password).toBe('secret')
    }
  })

  it('userpass auth has username and password', () => {
    const auth: Auth = { type: 'userpass', username: 'alice', password: 'pw' }
    expect(auth.type).toBe('userpass')
    if (auth.type === 'userpass') {
      expect(auth.username).toBe('alice')
    }
  })
})

describe('Mode values', () => {
  const modes: Mode[] = ['off', 'global', 'local']

  it('all modes are non-empty strings', () => {
    for (const m of modes) {
      expect(typeof m).toBe('string')
      expect(m.length).toBeGreaterThan(0)
    }
  })

  it('off mode exists', () => {
    const m: Mode = 'off'
    expect(m).toBe('off')
  })

  it('global mode exists', () => {
    const m: Mode = 'global'
    expect(m).toBe('global')
  })
})
