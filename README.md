```
    __  __                        _____                     
   / / / /__  _________ ___  ___ / ___/____  ___  __________
  / /_/ / _ \/ ___/ __ `__ \/ _ \\__ \/ __ \/ _ \/ ___/ ___/
 / __  /  __/ /  / / / / / /  __/__/ / /_/ /  __/ /__(__  ) 
/_/ /_/\___/_/  /_/ /_/ /_/\___/____/ .___/\___/\___/____/  
                                   /_/                      
```

# HermeSpecs 🕶️🤖

**Voice-controlled AI for Meta Ray-Ban Glasses**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20Android-blue.svg)]()
[![Status](https://img.shields.io/badge/status-Phase%201%20Complete-success.svg)]()

---

## What is HermeSpecs?

HermeSpecs brings the full [Hermes Agent](https://github.com/hermes/agent) ecosystem to your Meta Ray-Ban smart glasses. Speak naturally, see contextually, and execute **80+ tools** entirely hands-free.

```
┌─────────────────────────────────────────────────────────────┐
│  You: "Send a message to John saying I'm running late"      │
│                                                             │
│  HermeSpecs: [Sends iMessage]                               │
│              "Message sent to John"                         │
└─────────────────────────────────────────────────────────────┘
```

---

## ✨ Features

### 🎙️ Voice Commands
- *"What am I looking at?"* - AI analyzes camera view
- *"Add milk to my shopping list"* - Updates Apple Reminders
- *"Turn off the living room lights"* - Controls Philips Hue
- *"Remember this restaurant has great pasta"* - Saves with photo
- *"Search for the best coffee nearby"* - Web search via Grok

### 🧰 Tool Ecosystem (80+)

| Category | Tools |
|----------|-------|
| **Messaging** | iMessage, Telegram |
| **Productivity** | Reminders, Notes, Calendar, Gmail |
| **Smart Home** | Philips Hue |
| **Development** | GitHub, Linear |
| **Search** | Web search, Grok, arXiv |
| **Vision** | Identify objects, Read text, Remember scenes |

### 🔧 Technical

| Feature | Implementation |
|---------|---------------|
| **Low Latency** | <500ms response time via WebRTC |
| **Background Streaming** | HEVC codec for efficiency |
| **Vision Context** | Camera feeds visual understanding |
| **Secure** | End-to-end encryption, Keychain storage |
| **Cross-Platform** | iOS + Android from day one |

---

## 🏗️ Architecture

```
┌────────────────────────────────────────────────────────────────┐
│                    META RAY-BAN GLASSES                        │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────────┐   │
│  │  Camera  │  │  Microphone │  │ Speaker  │  │  Display    │   │
│  │ (~1fps)  │  │ (Voice In) │  │(Voice Out)│  │(Notifications)│  │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └──────┬───────┘   │
└───────┴─────────────┴─────────────┴────────────────┴───────────┘
                          │ BLE/WiFi
                          ▼
┌────────────────────────────────────────────────────────────────┐
│              iOS / ANDROID APP (HermeSpecs)                    │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Managers: Glasses │ Audio │ Stream │ Display          │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  Services: Hermes │ Vision │ TTS                      │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  ViewModels: Chat │ Vision │ Settings                 │   │
│  ├─────────────────────────────────────────────────────────┤   │
│  │  Views: SwiftUI / Jetpack Compose                      │   │
│  └─────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────┘
                          │ HTTPS/WSS
                          ▼
┌────────────────────────────────────────────────────────────────┐
│                 HERMES AGENT INFRASTRUCTURE                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐ │
│  │ WebRTC       │  │ Vision       │  │ Tool Ecosystem       │ │
│  │ Gateway      │  │ Processor    │  │ (80+ tools)          │ │
│  └──────────────┘  └──────────────┘  └──────────────────────┘ │
└────────────────────────────────────────────────────────────────┘
```

---

## 📱 Installation

### Requirements

- Meta Ray-Ban smart glasses (1st or 2nd gen)
- iPhone 11+ (iOS 17+) **or** Android (Pixel 6+, Samsung S21+)
- Meta AI app with **Developer Mode** enabled
- Hermes Agent account

### Step 1: Enable Developer Mode

1. Open **Meta AI** app on your phone
2. Go to **Settings**
3. Enable **Developer Mode**
4. Pair your Ray-Ban glasses

### Step 2: Build HermeSpecs

```bash
# Clone the repository
git clone https://github.com/radfordben/hermespecs-app.git
cd hermespecs-app

# iOS
open ios/HermeSpecs.xcodeproj
# Build and run on device (requires Apple Developer account)

# Android
open android/ in Android Studio
# Build and install APK
```

### Step 3: Configure Hermes

1. Open HermeSpecs app
2. Go to **Settings** → **Hermes Integration**
3. Enter your Hermes server URL
4. Add your API token
5. Tap **Test Connection**

---

## 🚀 Usage

### Getting Started

1. **Put on your glasses**
2. **Tap the AI button** on the glasses temple (or say "Hey Hermes" if enabled)
3. **Speak your command**
4. **Get results via glasses speaker**

### Example Interactions

```
You: "What am I looking at?"
HermeSpecs: "You're looking at a modern office space with a desk, 
             computer monitor, and a window showing a city view."

You: "Send a message to John saying I'll be 10 minutes late"
HermeSpecs: "Message sent to John: 'I'll be 10 minutes late'"

You: "Add milk, eggs, and bread to my shopping list"
HermeSpecs: "Added 3 items to your shopping list"

You: "Turn off all the lights"
HermeSpecs: "Turned off 4 lights in your home"

You: "Remember this place has great wifi"
HermeSpecs: "Saved with photo. Location noted as having great wifi."
```

---

## 📊 Project Status

| Phase | Status | Description |
|-------|--------|-------------|
| **Phase 1** | ✅ Complete | Foundation - HermesService, basic voice routing |
| **Phase 2** | 🟡 In Progress | Vision integration - camera streaming, visual Q&A |
| **Phase 3** | ⚪ Planned | Tool ecosystem - 80+ tools via voice |
| **Phase 4** | ⚪ Planned | Polish - performance optimization, App Store |

---

## 🛠️ Development

### Project Structure

```
hermespecs/
├── ios/
│   └── HermeSpecs/
│       ├── Managers/          # Glasses, Audio, Stream, Display
│       ├── Services/          # Hermes, Vision, TTS
│       │   └── Hermes/
│       │       ├── HermesService.swift
│       │       ├── HermesCommandRouter.swift
│       │       └── HermesModels.swift
│       ├── ViewModels/        # Chat, Vision, Settings
│       └── Views/             # SwiftUI views
│           └── HermesChatView.swift
├── android/                   # Kotlin implementation
├── gateway/                   # WebRTC gateway server
└── docs/                      # Documentation
```

### Key Components

| Component | File | Purpose |
|-----------|------|---------|
| `HermesService` | `Services/Hermes/HermesService.swift` | WebSocket client for Hermes Agent |
| `HermesCommandRouter` | `Services/Hermes/HermesCommandRouter.swift` | Routes commands & tool execution |
| `HermesChatView` | `Views/HermesChatView.swift` | Voice command UI |
| `HermesModels` | `Services/Hermes/HermesModels.swift` | Request/response models |

### Building

```bash
# iOS
cd ios
xcodebuild -scheme HermeSpecs -destination 'platform=iOS Simulator,name=iPhone 15'

# Android
cd android
./gradlew assembleDebug
```

---

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

See [IMPLEMENTATION_TASKS.md](./IMPLEMENTATION_TASKS.md) for detailed development tasks.

---

## 🙏 Credits

- **Base Project**: [TurboMeta](https://github.com/Turbo1123/turbometa-rayban-ai) by Turbo1123
- **SDK**: [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios)
- **Agent**: [Hermes Agent](https://github.com/hermes/agent)
- **Inspired by**: VisionClaw, meta-lens-ai, NoteBuddy, RaybanAI

---

## 📄 License

```
MIT License

Copyright (c) 2026 HermeSpecs Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
```

---

## ⚠️ Disclaimer

This project requires **Meta Ray-Ban Developer Mode**. It is not affiliated with Meta Platforms, Inc. or Ray-Ban. Use at your own risk. The Hermes Agent integration requires a separate Hermes account.

---

<div align="center">

**HermeSpecs** — *See the world, speak your mind, get things done.*

🕶️🤖🗣️

</div>
