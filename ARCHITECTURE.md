# ARCHITECTURE.md — ops_vpn

## Technology Stack

| Layer | Technology |
|-------|-----------|
| Backend language | Zig 0.16.0 |
| Backend I/O model | `std.Io.Threaded` (Zig 0.16 native async/IO interface) |
| Frontend framework | React 18 + TypeScript |
| Frontend styling | Tailwind CSS v3 |
| Frontend build | Vite 5 |
| Frontend test | Vitest |
| Backend test | Zig built-in `test` blocks |
| Package manager | yarn |

---

## Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                   ops_vpn binary                     │
│                                                      │
│  ┌─────────────┐    ┌──────────────────────────────┐ │
│  │  Web UI     │    │   Proxy Engine               │ │
│  │  (embedded  │    │                              │ │
│  │  React SPA) │    │  SOCKS5 listener :7890       │ │
│  │             │◄──►│  HTTP CONNECT listener :7891 │ │
│  │  API :7070  │    │                              │ │
│  └─────────────┘    │  Outbound protocols:         │ │
│                     │  · SOCKS5                    │ │
│  ┌─────────────┐    │  · HTTP CONNECT              │ │
│  │  Config     │    │  · Shadowsocks AEAD          │ │
│  │  (JSON)     │    └──────────────────────────────┘ │
│  └─────────────┘                                     │
└─────────────────────────────────────────────────────┘
```

### Request Flow

```
App (Chrome/curl) → ops_vpn :7890/:7891 → active endpoint → internet
```

1. App sends SOCKS5 or HTTP CONNECT to ops_vpn's local listener
2. ops_vpn looks up the active endpoint from config
3. ops_vpn dials the remote proxy using the configured protocol + auth
4. Bidirectional pipe is established between app and remote proxy
5. App traffic flows transparently through the tunnel

---

## Component Breakdown

### `backend/src/main.zig`
Entry point. Initializes `std.Io.Threaded` runtime, loads config, spawns proxy listener threads, runs API server on main thread.

### `backend/src/api.zig`
HTTP/1.1 server on `:7070`. Serves the embedded frontend (index.html, JS, CSS via `@embedFile`) and handles REST API calls for endpoint CRUD, connect/disconnect, and mode changes.

### `backend/src/config.zig`
Endpoint and mode persistence. Reads/writes `data/config.json`. Defines `Protocol`, `Mode`, `SsCipher`, `Auth`, `Endpoint`, `Config` types. Contains 11 unit tests.

### `backend/src/proxy/local.zig`
Two concurrent listeners: SOCKS5 on `:7890` and HTTP CONNECT on `:7891`. Parses inbound protocol, resolves target, dials upstream via protocol modules, and runs bidirectional pipe.

### `backend/src/proxy/protocols/`
- **socks5.zig**: RFC 1928/1929 SOCKS5 outbound client (no-auth + user/pass)
- **http_connect.zig**: HTTP CONNECT outbound client (no-auth + Basic auth)
- **shadowsocks.zig**: SS AEAD outbound client (AES-256-GCM + ChaCha20-Poly1305, HKDF key derivation)

### `frontend/src/`
React SPA: `App.tsx` manages state, `EndpointList` shows endpoints, `EndpointForm` handles protocol-aware input, `ModeToggle` switches modes, `StatusBar` shows live status. API client in `api/client.ts`.

---

## Major Design Decisions

### 1. Single binary with embedded UI
The frontend is built with Vite into `backend/src/www/` with stable filenames, then embedded at compile time using Zig's `@embedFile`. Users receive one file with no external dependencies.

**Tradeoff**: Rebuilding the frontend requires re-running `zig build`. For development, Vite's dev server proxies to the backend, so hot reload works independently.

### 2. Zig 0.16 std.Io
Zig 0.16 introduced a major I/O rearchitecture. All networking (TCP server/client, DNS), file I/O, mutexes, and random bytes moved to `std.Io`. The backend uses `std.Io.Threaded` as the runtime, initialized once in `main()` and shared globally via `runtime.zig`.

**Impact**: Required significant migration from 0.13 patterns (std.net → std.Io.net, std.Thread.Mutex → std.Io.Mutex, ArrayList.init → .empty, etc.).

### 3. Thread-per-connection model
Each incoming connection spawns a goroutine (std.Thread). This is simple and sufficient for a local proxy with low connection counts. An evented/async model would be better for high-throughput scenarios but adds complexity.

### 4. No DNS at client (SOCKS5/HTTP pass-through)
For SOCKS5 and HTTP CONNECT outbound, the hostname is forwarded to the remote proxy server — DNS is resolved there, not locally. This is correct behavior for privacy and avoids DNS leaks. For proxy server hostname resolution (connecting to the proxy itself), we use `std.Io.net.HostName.lookup` with `io.concurrent`.

### 5. Bidirectional pipe buffer isolation
A critical bug discovered during testing: the `copyLoop` function must use a **separate transfer buffer** distinct from the reader's internal buffer. Aliasing the reader's internal buffer as the output buffer caused `readSliceShort` to return 0 immediately, closing the HTTP CONNECT tunnel. Fixed by using three separate buffers: `rbuf` (reader internal), `wbuf` (writer internal), `data` (transfer).

---

## AI Tooling Used

| Tool | Purpose |
|------|---------|
| **Claude (Cowork mode)** | Primary development — all code generation, debugging, architecture decisions, Zig 0.16 migration |
| **Claude Agent SDK** | Multi-step file writing, codebase exploration, cross-file refactoring |
| **Claude in Chrome** | Viewing internal GitLab pages |

The entire project was developed through a conversational AI-native workflow using Claude Cowork — no manual code editing outside of the AI session.

---

## Agent Workflow

```
User intent → Claude designs → Claude implements → User runs → Error paste → Claude fixes → repeat
```

1. **Design phase**: Claude presented design before implementation (per project instructions). User refined protocol support, UI approach, and distribution model through conversation.

2. **Implementation phase**: Claude wrote all files using Write/Edit tools. Multi-file changes were batched using the Agent sub-tool.

3. **Zig 0.16 migration**: The initial code targeted Zig 0.13. As each compiler error appeared, the user pasted the error and Claude fixed it. Approximately 15 build-fix iterations to migrate to Zig 0.16 `std.Io`.

4. **Debugging**: The HTTP CONNECT buffer aliasing bug was discovered through runtime errors. Claude diagnosed it by reasoning about the buffer lifecycle rather than having direct access to run the binary.

5. **Testing**: Claude wrote unit tests for pure/deterministic functions (config parsing, type validation) after the project was working, guided by the user's requirement to have non-zero test coverage before pushing.
