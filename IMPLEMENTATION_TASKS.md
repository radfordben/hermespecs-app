# HermeSpecs - Implementation Tasks

## Project Overview
Fork of TurboMeta to create HermeSpecs - Hermes Agent for Meta Ray-Ban Glasses.

**Goal**: Enable hands-free, voice-controlled access to 80+ Hermes tools through Meta Ray-Ban smart glasses.

**Repository**: https://github.com/radfordben/hermespecs
**Upstream**: https://github.com/Turbo1123/turbometa-rayban-ai

## Phase 1: Foundation (Weeks 1-3)

### Task 1.1: Project Setup & Architecture Review
**Priority**: P0 | **Estimated Time**: 2 days

**Objective**: Understand TurboMeta architecture and establish Hermes integration pattern.

**Steps**:
1. Review TurboMeta directory structure:
   - `CameraAccess/Managers/` - Connection managers
   - `CameraAccess/Services/` - API services (currently OpenClaw)
   - `CameraAccess/ViewModels/` - MVVM pattern
   - `CameraAccess/Views/` - SwiftUI views
   - `CameraAccess/Intents/` - Siri Shortcuts

2. Document key components:
   - `GlassesManager.swift` - Meta glasses connection
   - `AudioManager.swift` - Audio I/O
   - `StreamManager.swift` - Video streaming
   - `OpenClawService.swift` - Current tool integration
   - `ChatViewModel.swift` - Main view model

3. Identify integration points for Hermes:
   - Where to replace OpenClaw with Hermes
   - How to route voice commands
   - Where to inject vision context

**Deliverable**: Architecture document with integration points identified.

---

### Task 1.2: Create HermesService
**Priority**: P0 | **Estimated Time**: 3 days

**Objective**: Create service layer to communicate with Hermes Agent API.

**Implementation**:
1. Create `CameraAccess/Services/HermesService.swift`:
```swift
protocol HermesServiceProtocol {
    func sendCommand(_ command: String, completion: @escaping (Result<HermesResponse, Error>) -> Void)
    func sendVisionCommand(_ command: String, imageData: Data, completion: @escaping (Result<HermesResponse, Error>) -> Void)
    func streamAudio(_ audioData: Data)
    func connect()
    func disconnect()
}

class HermesService: HermesServiceProtocol {
    // WebSocket or HTTP client to Hermes gateway
    // Authentication with Hermes tokens
    // Response parsing
}
```

2. Create response models:
   - `HermesResponse` - Standard response format
   - `ToolExecution` - Tool execution results
   - `VisionContext` - Visual analysis results

3. Add configuration:
   - Hermes server URL (configurable)
   - API key/token management
   - Timeout settings

**Deliverable**: Working HermesService with test connectivity.

---

### Task 1.3: Configuration UI
**Priority**: P1 | **Estimated Time**: 2 days

**Objective**: Add settings screen for Hermes configuration.

**Implementation**:
1. Add to existing Settings view:
   - Hermes server URL input
   - API key/token input
   - Connection test button
   - Model selection (if applicable)

2. Secure storage:
   - Keychain integration for tokens
   - UserDefaults for server URL

**Deliverable**: Settings UI for Hermes configuration.

---

### Task 1.4: Basic Voice Command Routing
**Priority**: P0 | **Estimated Time**: 3 days

**Objective**: Route voice commands from glasses to Hermes.

**Implementation**:
1. Modify `ChatViewModel`:
   - Replace OpenClaw calls with HermesService
   - Handle text responses
   - Route TTS responses to AudioManager

2. Update conversation flow:
   - User speaks → Audio captured → Text transcription
   - Text sent to Hermes → Response received
   - Response spoken via glasses speaker

3. Basic error handling:
   - Network errors
   - Hermes service errors
   - Timeout handling

**Deliverable**: End-to-end voice command working with Hermes.

---

### Task 1.5: Tool Response Handling
**Priority**: P1 | **Estimated Time**: 2 days

**Objective**: Handle tool execution results from Hermes.

**Implementation**:
1. Parse tool execution responses:
   - Tool name executed
   - Success/failure status
   - Result summary
   - Error messages

2. Voice feedback:
   - "Message sent to John"
   - "Added milk to your shopping list"
   - "Could not find contact John"

3. Visual feedback (on phone):
   - Show conversation history
   - Display tool execution cards

**Deliverable**: Tool execution with voice confirmation.

---

## Phase 2: Vision Integration (Weeks 4-6)

### Task 2.1: Video Streaming Setup
**Priority**: P0 | **Estimated Time**: 3 days

**Objective**: Enable camera frame streaming to Hermes.

**Implementation**:
1. Use existing `StreamManager`:
   - Capture frames at ~1fps
   - Encode frames (JPEG/HEVC)
   - Send to Hermes gateway

2. Add WebRTC or HTTP streaming:
   - Frame upload endpoint
   - Session management
   - Connection quality handling

3. Optimize for bandwidth:
   - Frame resizing
   - Compression
   - Adaptive quality

**Deliverable**: Video frames streaming to Hermes server.

---

### Task 2.2: Vision Context Injection
**Priority**: P0 | **Estimated Time**: 3 days

**Objective**: Inject visual context into Hermes prompts.

**Implementation**:
1. Modify command flow:
   - User speaks → Capture frame simultaneously
   - Send command + frame to Hermes
   - Hermes analyzes image + processes command

2. Add vision-specific commands:
   - "What am I looking at?"
   - "Describe this scene"
   - "Read this text"

3. Response handling:
   - Vision analysis results
   - Object identification
   - Text OCR results

**Deliverable**: Visual Q&A working through glasses.

---

### Task 2.3: Vision Tools
**Priority**: P1 | **Estimated Time**: 4 days

**Objective**: Implement vision-specific Hermes tools.

**Implementation**:
1. `RememberThis` tool:
   - Capture frame + transcribe note
   - Store in knowledge base
   - "Remember this restaurant has great pasta"

2. `IdentifyObject` tool:
   - Analyze frame for objects
   - Return identification
   - "What is this?" → "That's a Philips Hue Bridge"

3. `ReadText` tool:
   - OCR on captured frame
   - Read text aloud
   - "Read this sign" → "No Parking 8am-6pm"

**Deliverable**: Vision tools working end-to-end.

---

## Phase 3: Tool Ecosystem (Weeks 7-9)

### Task 3.1: Core Tools Integration
**Priority**: P0 | **Estimated Time**: 5 days

**Objective**: Integrate top 10 Hermes tools.

**Tools to implement**:
1. iMessage - Send messages
2. Telegram - Send messages
3. Apple Reminders - Add reminders
4. Apple Notes - Create notes
5. Search (Grok) - Web search
6. Philips Hue - Smart home control
7. Linear - Issue management
8. GitHub - Repo/issue access
9. Gmail - Send/read emails
10. Calendar - Check/add events

**Implementation**:
- Ensure each tool works via voice
- Voice-optimized confirmations
- Error handling with voice feedback

**Deliverable**: 10 core tools working via voice.

---

### Task 3.2: Tool Optimization
**Priority**: P1 | **Estimated Time**: 3 days

**Objective**: Optimize tools for voice/glasses context.

**Implementation**:
1. Quick mode for common actions:
   - No confirmation for low-risk actions
   - "Text John I'm late" → sends immediately

2. Context-aware defaults:
   - Use recent contacts
   - Default to common apps
   - Smart reminders ("Remind me later")

3. Batch operations:
   - Chain multiple tools
   - "Add milk and eggs to shopping list, then text Sarah"

**Deliverable**: Streamlined voice interactions.

---

### Task 3.3: Full Tool Suite
**Priority**: P2 | **Estimated Time**: 7 days

**Objective**: Enable all 80+ Hermes tools.

**Implementation**:
- Systematically enable remaining tools
- Test each via voice interface
- Document any issues

**Deliverable**: Full Hermes ecosystem accessible via glasses.

---

## Phase 4: Polish & Production (Weeks 10-12)

### Task 4.1: Performance Optimization
**Priority**: P0 | **Estimated Time**: 3 days

**Objective**: Optimize for battery, latency, and reliability.

**Implementation**:
1. Video optimization:
   - Use HEVC codec for background streaming
   - Adaptive frame rate (reduce when idle)
   - Smart frame sampling

2. Audio optimization:
   - Noise suppression
   - Echo cancellation
   - Voice activity detection

3. Network optimization:
   - Connection pooling
   - Retry logic
   - Fallback handling

**Deliverable**: <500ms response time, <20% battery/hour.

---

### Task 4.2: Advanced Features
**Priority**: P1 | **Estimated Time**: 4 days

**Implementation**:
1. Multi-modal memory:
   - Remember what user saw + said
   - Context across sessions
   - "What was that restaurant I saw yesterday?"

2. Display notifications (if supported):
   - Show tool status on glasses display
   - Quick visual alerts

3. Siri Intents:
   - "Hey Siri, ask Hermes..."
   - Shortcuts integration

**Deliverable**: Advanced features enabled.

---

### Task 4.3: Testing & Distribution
**Priority**: P0 | **Estimated Time**: 5 days

**Implementation**:
1. Testing:
   - Unit tests for HermesService
   - Integration tests
   - Field testing with real glasses

2. Documentation:
   - Setup guide
   - User manual
   - API documentation

3. Distribution:
   - TestFlight setup (iOS)
   - Play Console (Android)
   - App Store preparation

**Deliverable**: Production-ready app.

---

## Current State

- ✅ Repository created: https://github.com/radfordben/hermespecs
- ✅ TurboMeta forked and set up
- ✅ Task 1.1: Architecture reviewed - MVVM + Managers + Services pattern identified
- ✅ Task 1.2: HermesService created with WebSocket, auth, request/response handling
- ✅ Task 1.3: HermesSettingsView created for server/API configuration
- ✅ Task 1.4: HermesChatView created with basic voice command routing
- ✅ Integration: SettingsView updated with Hermes option
- ✅ Integration: TurboMetaHomeView updated with Hermes feature card
- ⏳ Task 1.5: Tool response handling - partially implemented in HermesCommandRouter

## Next Actions

1. Test HermesService connection end-to-end
2. Implement ASR service integration for voice input
3. Add vision context injection (Task 2.2)
4. Implement core tool integrations (Task 3.1)

## Notes

- Keep TurboMeta's Manager pattern
- Maintain dual-platform support (iOS/Android)
- Preserve Siri Intents integration
- Use WebRTC for low-latency audio
- Test on real Meta Ray-Ban glasses
