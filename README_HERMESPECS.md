# HermeSpecs 🕶️🤖

**Voice-controlled AI for Meta Ray-Ban Glasses**

HermeSpecs brings the full Hermes Agent ecosystem to your Meta Ray-Ban smart glasses. Speak naturally, see contextually, and execute 80+ tools entirely hands-free.

---

## What is HermeSpecs?

HermeSpecs is a fork of [TurboMeta](https://github.com/Turbo1123/turbometa-rayban-ai) that replaces the OpenClaw integration with [Hermes Agent](https://github.com/hermes/agent), giving you:

- **80+ tools** accessible via voice
- **Multi-modal AI** with visual context from glasses camera
- **Hands-free operation** through glasses speaker and microphone
- **Cross-platform** iOS and Android support
- **Display notifications** on compatible glasses

---

## Features

### Voice Commands
- *"Send a message to John saying I'm running late"*
- *"What am I looking at?"*
- *"Add milk to my shopping list"*
- *"Turn off the living room lights"*
- *"Remember this restaurant has great pasta"*

### Tool Ecosystem
| Category | Tools |
|----------|-------|
| Messaging | iMessage, Telegram |
| Productivity | Reminders, Notes, Calendar, Gmail |
| Smart Home | Philips Hue |
| Development | GitHub, Linear |
| Search | Web search, Grok |
| Vision | Identify objects, Read text, Remember scenes |

### Technical
- **Low latency**: <500ms response time
- **Background streaming**: HEVC codec for efficiency
- **Vision context**: Camera feeds visual understanding
- **Secure**: End-to-end encryption, local token storage

---

## Architecture

```
Meta Ray-Ban Glasses
    ↓ (BLE/WiFi)
iOS/Android App (HermeSpecs)
    ├── Managers (Glasses, Audio, Stream, Display)
    ├── Services (Hermes, Vision, TTS)
    ├── ViewModels (MVVM pattern)
    └── Intents (Siri Shortcuts)
    ↓ (WebRTC/HTTPS)
Hermes Agent Infrastructure
    ├── WebRTC Gateway
    ├── Vision Processor
    └── Tool Ecosystem (80+)
```

---

## Getting Started

### Requirements
- Meta Ray-Ban smart glasses
- iPhone 11+ (iOS 17+) or Android (Pixel 6+, Samsung S21+)
- Meta AI app with Developer Mode enabled
- Hermes Agent account

### Installation

1. **Enable Developer Mode** on your glasses:
   - Open Meta AI app → Settings → Developer Mode

2. **Build from source**:
   ```bash
   git clone https://github.com/radfordben/hermespecs.git
   cd hermespecs/ios  # or /android
   # Open in Xcode or Android Studio
   # Build and run on device
   ```

3. **Configure Hermes**:
   - Open HermeSpecs settings
   - Enter your Hermes server URL
   - Add API token
   - Test connection

### Usage

1. Put on your glasses
2. Tap the AI button or say "Hey Hermes"
3. Speak your command
4. Get results via glasses speaker

---

## Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | 🟡 In Progress | Foundation - HermesService, basic voice routing |
| Phase 2 | ⚪ Planned | Vision integration - camera streaming, visual Q&A |
| Phase 3 | ⚪ Planned | Tool ecosystem - 80+ tools via voice |
| Phase 4 | ⚪ Planned | Polish - performance, distribution |

---

## Development

### Project Structure
```
hermespecs/
├── ios/                    # iOS app (Swift/SwiftUI)
│   ├── HermeSpecs/
│   │   ├── Managers/       # Connection managers
│   │   ├── Services/       # Hermes, Vision, TTS
│   │   ├── ViewModels/     # MVVM layer
│   │   └── Views/          # SwiftUI views
│   └── HermeSpecs.xcodeproj
├── android/                # Android app (Kotlin)
├── gateway/                # WebRTC gateway server
└── docs/                   # Documentation
```

### Contributing
1. Fork the repository
2. Create a feature branch
3. Submit a pull request

See [IMPLEMENTATION_TASKS.md](./IMPLEMENTATION_TASKS.md) for detailed tasks.

---

## Credits

- **Base**: [TurboMeta](https://github.com/Turbo1123/turbometa-rayban-ai) by Turbo1123
- **SDK**: [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios)
- **Agent**: [Hermes Agent](https://github.com/hermes/agent)

---

## License

MIT License - See [LICENSE](./LICENSE)

---

## Disclaimer

This project requires Meta Ray-Ban Developer Mode. It is not affiliated with Meta or Ray-Ban. Use at your own risk.

---

**HermeSpecs** - *See the world, speak your mind, get things done.*
