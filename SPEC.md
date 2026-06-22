# SPEC.md — ops_vpn

## Project Overview

ops_vpn is a universal proxy client that allows users to connect to remote proxy endpoints (SOCKS5, HTTP CONNECT, Shadowsocks) without installing vendor-specific client software. It runs as a local binary with an embedded web UI and exposes local proxy listeners that any application can route traffic through.

---

## Scope Definition

### In Scope
- Managing a list of proxy endpoints (add, edit, delete)
- Connecting to proxy servers via SOCKS5, HTTP CONNECT, and Shadowsocks (AEAD)
- Authentication: none, username/password, and Shadowsocks cipher+password
- Local proxy listeners: SOCKS5 on `:7890`, HTTP CONNECT on `:7891`
- Web UI served from an embedded binary (no Node.js required to run)
- Global and Local routing modes
- Persistent endpoint configuration (saved to `data/config.json`)
- Cross-platform binaries: macOS (M1, Intel), Linux (x86_64), Windows (x64)

### Out of Scope
- TUN/TAP kernel-level VPN (system-wide transparent proxy)
- WireGuard, OpenVPN, Trojan, VMess/VLESS protocol support (v1)
- Mobile clients (iOS, Android)
- Per-app routing rules / split tunneling rules engine
- Subscription/import of proxy lists

---

## Functional Requirements

### FR-1: Endpoint Management
- User can add a proxy endpoint with: label, protocol, host, port, auth
- User can delete an endpoint
- User can enable/disable an endpoint without deleting it
- Endpoints persist across restarts

### FR-2: Protocol Support
| Protocol | Auth Options |
|----------|-------------|
| SOCKS5 | None / Username+Password |
| HTTP CONNECT | None / Username+Password (Basic) |
| Shadowsocks | Password + AES-256-GCM or ChaCha20-Poly1305 |

### FR-3: Local Proxy Listeners
- SOCKS5 listener on `127.0.0.1:7890` — accepts SOCKS5 CONNECT from any app
- HTTP CONNECT listener on `127.0.0.1:7891` — accepts HTTP CONNECT from any app
- Both listeners route through the currently active endpoint

### FR-4: Routing Modes
- **Off**: Proxy inactive; connections refused
- **Global**: All traffic from local listeners routes through active endpoint
- **Local**: Listeners available but mode is manual (user points apps explicitly)

### FR-5: Web UI
- Accessible at `http://localhost:7070`
- Shows endpoint list with connect/disconnect per endpoint
- Protocol-aware add form (Shadowsocks shows cipher; SOCKS5/HTTP shows optional user+pass)
- Mode toggle (Off / Global / Local)
- Status bar showing active endpoint, mode, and local proxy addresses

### FR-6: Single Binary Distribution
- `yarn build` + `zig build` produces a self-contained binary
- Binary embeds the frontend (no external files needed)
- Cross-compiled from Mac to macOS, Linux, Windows

---

## Acceptance Criteria

| ID | Criterion | Pass |
|----|-----------|------|
| AC-1 | Binary starts and serves UI at `http://localhost:7070` | ✓ |
| AC-2 | User can add a SOCKS5 endpoint and connect to it | ✓ |
| AC-3 | `curl --socks5 127.0.0.1:7890` routes through the active endpoint | ✓ |
| AC-4 | `curl --proxy http://127.0.0.1:7891` routes through the active endpoint | ✓ |
| AC-5 | Chrome launched with `--proxy-server=socks5://127.0.0.1:7890` routes correctly | ✓ |
| AC-6 | Endpoints survive a restart | ✓ |
| AC-7 | Disconnecting sets mode to Off and stops routing | ✓ |
| AC-8 | Binary runs on macOS M1, macOS Intel, and Linux without install | ✓ |
| AC-9 | `zig build test` passes all 11 Zig unit tests | ✓ |
| AC-10 | `yarn test` passes all 20 frontend unit tests | ✓ |
