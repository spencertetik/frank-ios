# Tailscale Connectivity Guide

## Goal
Connect the Frank iOS app to the OpenClaw gateway running on a Mac mini, so you can chat with Frank from anywhere (cellular, remote Wi-Fi, etc.) — not just your local network.

## What We Tried

### Attempt 1: Tailscale Serve (wss://) ❌
- **Setup:** OpenClaw gateway bound to `loopback`, Tailscale Serve proxying `https://spencers-mac-mini.tail6878f.ts.net` → `http://127.0.0.1:18789`
- **Result:** Worked perfectly from the Mac mini itself (Python websockets connected, got challenge). Failed from iOS.
- **Why it failed:** Tailscale Serve uses its own TLS certificates that iOS doesn't trust by default. We added a custom `URLSessionDelegate` to trust `*.ts.net` certs, but iOS still wouldn't complete the TLS handshake over cellular.
- **Lesson:** Tailscale Serve is great for browser access but problematic for native iOS apps due to certificate trust.

### Attempt 2: Direct Tailscale IP (ws://) ✅
- **Setup:** OpenClaw gateway bound to `auto` (listens on all interfaces), Tailscale Serve disabled. iOS app connects via `ws://100.118.254.15:18789` (the Mac mini's Tailscale IP).
- **Result:** Works on Wi-Fi AND cellular.
- **Why it works:** Tailscale creates a WireGuard VPN tunnel between devices. The Mac mini's Tailscale IP (`100.118.254.15`) is reachable from the iPhone (`100.114.25.124`) regardless of what network the phone is on. Plain `ws://` avoids TLS certificate issues entirely — the Tailscale tunnel itself is already encrypted (WireGuard).

### Attempt 2.5: `tailnet` bind ❌ (partially)
- **Setup:** Tried `gateway.bind: "tailnet"` to only listen on the Tailscale interface.
- **Result:** iOS would have worked, but it broke the web GUI (which connects via localhost). Localhost was no longer listening.
- **Fix:** Switched to `gateway.bind: "auto"` which listens on ALL interfaces (loopback + LAN + Tailscale). Both web GUI and iOS app work.

## Final Working Configuration

### OpenClaw Config (`~/.openclaw/openclaw.json`)
```json
{
  "gateway": {
    "bind": "auto",
    "port": 18789,
    "tailscale": {
      "mode": "off"
    }
  }
}
```

### iOS App Settings
- **Host:** `100.118.254.15` (Mac mini's Tailscale IP)
- **Port:** `18789`
- **Use Tailscale toggle:** OFF (direct IP mode, not Serve mode)
- **Protocol:** `ws://` (plain WebSocket — Tailscale tunnel handles encryption)

### Xcode Project (pbxproj)
```
INFOPLIST_KEY_NSAppTransportSecurity_AllowsLocalNetworking = YES
INFOPLIST_KEY_NSAppTransportSecurity_AllowsArbitraryLoads = YES
```
These App Transport Security exceptions allow iOS to make plain `ws://` connections to non-localhost IPs.

## Prerequisites
1. **Tailscale installed** on both the Mac mini and iPhone
2. **Both devices on the same Tailnet** (logged into same Tailscale account)
3. **Tailscale VPN active on iPhone** (the Tailscale app must be running/connected)
4. **OpenClaw gateway running** on Mac mini

## Troubleshooting
- **Can't connect from iOS:** Make sure Tailscale VPN is active on the iPhone (check Tailscale app)
- **Web GUI broken:** Make sure `gateway.bind` is `"auto"`, not `"tailnet"` or `"lan"`
- **Connection refused:** Verify gateway is running (`curl http://127.0.0.1:18789/health` on Mac mini)
- **Tailscale IPs changed:** Check `tailscale ip` on each device to get current IPs

## Security Notes
- `gateway.bind: "auto"` exposes the gateway on LAN (`192.168.1.x`) too — this is fine for a home network
- The gateway requires token authentication regardless of bind mode
- Tailscale traffic is encrypted via WireGuard — plain `ws://` inside the tunnel is safe
- If you want to restrict to ONLY Tailscale + localhost, you'd need OpenClaw to support multi-bind (not currently available)
