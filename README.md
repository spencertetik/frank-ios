# Frank — iOS Companion for OpenClaw

A native iOS app for interacting with your [OpenClaw](https://github.com/openclaw/openclaw) AI agent. Chat, voice, quick commands, agent monitoring — all from your phone.

![Swift](https://img.shields.io/badge/Swift-6.0-orange) ![iOS](https://img.shields.io/badge/iOS-18.0+-blue) ![Xcode](https://img.shields.io/badge/Xcode-16+-purple)

## Features

- **Chat** — Real-time WebSocket chat with your OpenClaw agent, markdown rendering, image attachments
- **Voice Input** — Tap the mic to record, transcribed via OpenAI Whisper, dropped into the text field for review
- **Voice Output (TTS)** — Tap the speaker icon on any assistant message to hear it read aloud (OpenAI TTS)
- **Quick Commands** — Cached dashboard cards for common requests (morning report, weather, email, project status). Results stay in their own pages, not in chat
- **Agent Org Chart** — Visual hierarchy of your agent team with named specialists and live status
- **Widgets** — Home screen and Lock Screen widgets showing connection status and recent activity
- **Live Activities** — Dynamic Island support for active sessions
- **Push Notifications** — APNs integration for alerts from your agent
- **Dark Theme** — Liquid glass aesthetic throughout

## Requirements

- iOS 18.0+
- Xcode 16+
- An OpenClaw gateway running and accessible (local network or via Tailscale)
- OpenAI API key (for voice features — Whisper transcription + TTS)

## Setup

### 1. Clone & Open

```bash
git clone https://github.com/spencertetik/frank-ios.git
cd frank-ios/Frank
open Frank.xcodeproj
```

### 2. Configure Connection

In the app's **Settings** tab:

- **Host** — Your OpenClaw gateway address (e.g., `192.168.1.100` for LAN, or your Tailscale hostname)
- **Port** — Default `18789` (ignored if using Tailscale Serve)
- **Token** — Your gateway auth token (from `~/.openclaw/openclaw.json` → `auth.token`)
- **Use Tailscale Serve** — Toggle on if your gateway is exposed via `tailscale serve` (uses `wss://` on port 443)

### 3. Configure Voice (Optional)

In **Settings → Voice**:

- **OpenAI API Key** — Required for mic transcription (Whisper) and text-to-speech. Get one at [platform.openai.com](https://platform.openai.com/api-keys)
- **Auto-play Voice Responses** — Toggle to automatically read every assistant response aloud

### 4. Build & Run

Select your device and hit Run (⌘R). The app uses automatic code signing.

If building from CLI:
```bash
xcodebuild -project Frank.xcodeproj -scheme Frank \
  -destination "platform=iOS,id=YOUR_DEVICE_UDID" \
  -allowProvisioningUpdates build
```

Find your device UDID with:
```bash
xcrun devicectl list devices
```

## Architecture

| File | Purpose |
|------|---------|
| `FrankApp.swift` | App entry point, environment setup |
| `GatewayClient.swift` | WebSocket connection to OpenClaw gateway, chat history, session management |
| `ChatView.swift` | Main chat interface with voice input/output |
| `DashboardView.swift` | Home screen with status cards and quick commands |
| `AgentTreeView.swift` | Org chart showing agent hierarchy (Frank → Rex, Iris, Scout, Dash) |
| `QuickCommandsView.swift` | Dashboard quick command grid |
| `QuickCommandCache.swift` | Caches quick command results locally, manages fetch/staleness |
| `QuickCommandDetailView.swift` | Detail page for each quick command with speaker button |
| `AudioService.swift` | Recording (AVAudioRecorder), Whisper transcription, TTS, playback |
| `SettingsView.swift` | Connection config, API keys, preferences |
| `Theme.swift` | Centralized colors, fonts, spacing, glass card styles |
| `CalendarManager.swift` | EventKit calendar integration |
| `NotificationManager.swift` | APNs push notification handling |
| `SharedStateWriter.swift` | Syncs state to App Group for widgets |
| `ContentView.swift` | Tab bar root (Dashboard, Chat, Agents, Settings) |

## Agent Team

The Agents tab shows a permanent org chart:

| Name | Model | Role |
|------|-------|------|
| 🧠 **Frank** | Opus | Project Manager — orchestrates everything |
| 💻 **Rex** | Codex/GPT-5.1 | Lead Developer — coding tasks |
| 👁 **Iris** | Kimi | Visual QA — screenshots, design verification |
| 🔍 **Scout** | Grok | Intel & Search — web/X monitoring |
| ⚡ **Dash** | Sonnet | Fast Ops — quick tasks, sub-agents |

Specialists are always visible. They light up when a matching live session is detected.

## Customization

### Accent Color
The app uses an orange accent by default. Change it in `Theme.swift` → `accent` property, or use the accent color picker in Settings.

### Voice
TTS uses OpenAI's `echo` voice. To change it, edit `AudioService.swift` → the `"voice"` parameter in the `speak()` method. Options: `alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer`.

### Quick Commands
Add new commands in `QuickCommandCache.swift` → `CommandType` enum. Each command needs a `title`, `icon` (SF Symbol name), and `prompt`.

## Networking

The app connects via WebSocket to your OpenClaw gateway. Two modes:

1. **LAN** — Direct connection to `ws://host:port` (requires same network)
2. **Tailscale Serve** — Connects to `wss://your-machine.tailnet.ts.net` (works from anywhere, encrypted)

Quick commands use `deliver: false` so they don't appear in the main chat session — results are cached locally in the app.

## Troubleshooting

- **Can't connect** — Check the connection indicator (top-right of Chat). Verify host/port/token in Settings. Make sure your gateway is running (`openclaw gateway status`).
- **Voice not working** — Check Settings → Voice for your OpenAI API key. The red error banner at the top of Chat will show specific errors.
- **Quick commands showing in chat** — Update to latest; quick command prompts are now filtered from chat history.
- **Widgets not updating** — Make sure the App Group is configured in both the main app and widget extension targets.

## License

Private repository. Contact Spencer Tetik for access.
