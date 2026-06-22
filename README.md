# ops_vpn

A lightweight universal proxy client with a web UI. Add proxy endpoints, connect, and route your traffic — no vendor client needed.

Supports **SOCKS5**, **HTTP CONNECT**, and **Shadowsocks (AEAD)**. Ships as a single binary with the UI embedded — no Node.js or runtime required for end users.

```
Your app → ops_vpn (local proxy) → remote proxy server → internet
           :7890 SOCKS5
           :7891 HTTP CONNECT
           :7070 Web UI
```

---

## ⚡ Download & Run (no coding required)

**Download the latest release from GitLab:**  
👉 **https://git.ringcentral.com/rc-ai-learning/francis-peng-vpn/-/releases/latest**

Pick the zip for your platform, unzip, and run.

---

### macOS

| Your Mac | Download |
|----------|---------|
| M1 / M2 / M3 (Apple Silicon) | `ops_vpn-macOS-M1.zip` |
| Intel Mac | `ops_vpn-macOS-Intel.zip` |

> **Not sure which chip?** Apple menu → About This Mac → if it says "Apple M1/M2/M3" use M1, if it says "Intel" use Intel.

```bash
# Unzip, remove quarantine flag, and run:
unzip ops_vpn-macOS-M1.zip       # or ops_vpn-macOS-Intel.zip
xattr -d com.apple.quarantine ops_vpn-M1   # removes the "unverified developer" block
chmod +x ops_vpn-M1
./ops_vpn-M1
```

Open **http://localhost:7070** in your browser.

> **Still blocked?** macOS may show "cannot verify malware" on unsigned binaries.  
> Fix: System Settings → Privacy & Security → scroll down → click **Allow Anyway** → run again → click **Open**.

---

### Linux

Download `ops_vpn-Linux.zip`:

```bash
unzip ops_vpn-Linux.zip
chmod +x ops_vpn
./ops_vpn
```

Open **http://localhost:7070**.

---

### Windows (64-bit only)

Download `ops_vpn-Windows.zip`, unzip, double-click `ops_vpn.exe`.  
Open **http://localhost:7070** in your browser.

> Requires Windows 10/11 64-bit. Windows 10/11 is always 64-bit — no need to check.

---

That's it. No install, no dependencies.

---

## Requirements (dev only)

| Tool | Version |
|------|---------|
| [Zig](https://ziglang.org/download/) | 0.16.0 |
| Node.js | 18+ |
| yarn | any |

End users only need the binary — nothing else.

---

## Quick Start (development)

```bash
# 1. Build the frontend
cd frontend
yarn install
yarn build          # outputs to backend/src/www/

# 2. Build and run the backend
cd ../backend
zig build run
```

Open **http://localhost:7070** in your browser.

For hot-reload frontend development:
```bash
# Terminal 1 — backend
cd backend && zig build run

# Terminal 2 — frontend dev server (proxies /api to backend)
cd frontend && yarn dev
# open http://localhost:5173
```

---

## How to Use

### 1. Add a proxy endpoint

Click **Add** in the UI and fill in:

| Field | Example |
|-------|---------|
| Label | My SOCKS5 Server |
| Protocol | SOCKS5 / HTTP CONNECT / Shadowsocks |
| Host | proxy.example.com |
| Port | 1080 |
| Auth | none / user+password / SS cipher+password |

### 2. Connect

Click **Connect** next to the endpoint. The status bar turns green.

### 3. Route your traffic

Point any app at the local proxy:

| Protocol | Address |
|----------|---------|
| SOCKS5 | `127.0.0.1:7890` |
| HTTP CONNECT | `127.0.0.1:7891` |

**curl:**
```bash
curl --socks5 127.0.0.1:7890 https://httpbin.org/ip
curl --proxy  http://127.0.0.1:7891 https://httpbin.org/ip
```

**Chrome (isolated window):**
```bash
open -a "Google Chrome" --args \
  --proxy-server="socks5://127.0.0.1:7890" \
  --user-data-dir="/tmp/chrome-vpn-profile"
```

**macOS system-wide proxy:**
System Settings → Network → your interface → Details → Proxies → SOCKS Proxy → `127.0.0.1:7890`

---

## Modes

| Mode | Behaviour |
|------|-----------|
| **Off** | Proxy inactive — connections refused |
| **Global** | All traffic through active endpoint |
| **Local** | Manual — only apps pointed at `:7890`/`:7891` |

Switch modes anytime from the top bar without reconnecting.

---

## Supported Protocols

### SOCKS5
```
Protocol: SOCKS5
Host:     proxy.example.com
Port:     1080
Auth:     none  OR  username + password
```

### HTTP CONNECT
```
Protocol: HTTP CONNECT
Host:     proxy.example.com
Port:     8080
Auth:     none  OR  username + password (Basic)
```

### Shadowsocks (AEAD)
```
Protocol: Shadowsocks
Host:     ss.example.com
Port:     8388
Password: your-password
Cipher:   aes-256-gcm  OR  chacha20-poly1305
```

---

## Build for Distribution (single binary)

The binary embeds the frontend — users just download and run it.

```bash
# From the project root
chmod +x build.sh
./build.sh
```

Outputs to `releases/`:

```
releases/
├── macOS/
│   ├── ops_vpn-M1            # Apple Silicon (M1/M2/M3)
│   └── ops_vpn-Intel         # Intel Mac
├── Linux/
│   └── ops_vpn               # Linux 64-bit
└── Windows/
    └── ops_vpn.exe           # Windows 64-bit
```

All targets build from a single Mac — Zig cross-compiles natively.

### Manual cross-compile

```bash
cd backend
zig build -Dtarget=aarch64-macos   -Doptimize=ReleaseSafe   # macOS ARM
zig build -Dtarget=x86_64-macos    -Doptimize=ReleaseSafe   # macOS Intel
zig build -Dtarget=x86_64-windows  -Doptimize=ReleaseSafe   # Windows
zig build -Dtarget=x86_64-linux    -Doptimize=ReleaseSafe   # Linux
zig build -Dtarget=aarch64-linux   -Doptimize=ReleaseSafe   # Linux ARM
```

> Yes — you can build Windows and Linux binaries directly on a Mac Intel. Zig cross-compiles with no extra toolchain needed.

---

## API Reference

The backend exposes a REST API on `:7070`:

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/endpoints` | List all endpoints |
| `POST` | `/api/endpoints` | Add endpoint |
| `PUT` | `/api/endpoints/:id` | Update endpoint |
| `DELETE` | `/api/endpoints/:id` | Remove endpoint |
| `POST` | `/api/connect/:id` | Set active endpoint |
| `POST` | `/api/disconnect` | Disconnect |
| `GET` | `/api/mode` | Get current mode |
| `POST` | `/api/mode` | Set mode (`off`/`global`/`local`) |
| `GET` | `/api/status` | Health + proxy addresses |

---

## Project Structure

```
ops_vpn/
├── backend/                        # Zig 0.16
│   ├── build.zig
│   ├── build.zig.zon
│   └── src/
│       ├── main.zig                # Entry point + thread spawning
│       ├── runtime.zig             # Global std.Io instance
│       ├── config.zig              # Endpoint + mode persistence
│       ├── api.zig                 # REST API + embedded UI server
│       ├── frontend.zig            # @embedFile wrappers
│       └── proxy/
│           ├── local.zig           # SOCKS5 (:7890) + HTTP (:7891) listeners
│           └── protocols/
│               ├── socks5.zig      # SOCKS5 outbound (RFC 1928/1929)
│               ├── http_connect.zig# HTTP CONNECT outbound
│               └── shadowsocks.zig # SS AEAD outbound
│
├── frontend/                       # React + TypeScript + Tailwind
│   └── src/
│       ├── App.tsx
│       ├── api/client.ts
│       ├── types/index.ts
│       └── components/
│           ├── EndpointList.tsx
│           ├── EndpointForm.tsx    # Protocol-aware auth fields
│           ├── ModeToggle.tsx
│           └── StatusBar.tsx
│
├── build.sh                        # Cross-platform release builder
├── build.bat                       # Windows release builder
└── README.md
```

---

## Local Testing (without a real proxy server)

Use [gost](https://github.com/go-gost/gost) to simulate a local proxy:

```bash
brew install gost

# SOCKS5
gost -L socks5://:1080

# SOCKS5 with auth
gost -L socks5://alice:secret@:1080

# HTTP CONNECT
gost -L http://:8080

# Shadowsocks
gost -L ss://chacha20-ietf-poly1305:mypassword@:8388
```

Then add `127.0.0.1` with the matching port/protocol in the UI.
