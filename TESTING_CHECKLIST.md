# HermeSpecs Testing Checklist

## ⚠️ Known Untested Areas

This checklist documents what has been implemented but **NOT tested**.

---

## Build Validation

### Phase 1: Foundation
- [ ] `HermesService.swift` compiles
- [ ] `HermesCommandRouter.swift` compiles
- [ ] `HermesModels.swift` compiles
- [ ] `HermesChatView.swift` compiles

### Phase 2: Vision
- [ ] `VisionFrameProcessor.swift` compiles
- [ ] `VisionFrameBuffer.swift` compiles
- [ ] `HermesCommandRouter+Vision.swift` compiles

### Phase 3: Tools
- [ ] `ToolRegistry.swift` compiles
- [ ] `ToolExecutors.swift` compiles
- [ ] `ToolIntegrationManager.swift` compiles

### Phase 4: Performance
- [ ] `PerformanceMonitor.swift` compiles (import fixed: MWDATCamera/MWDATCore)
- [ ] `AdaptiveStreamManager.swift` compiles
- [ ] `MultimodalMemory.swift` compiles
- [ ] `ConnectionRecoveryManager.swift` compiles

---

## Integration Tests Needed

### Meta SDK Integration
- [ ] `StreamSession` reference in `PerformanceMonitor` matches actual SDK type
- [ ] `WearablesInterface` properly injected
- [ ] `videoFramePublisher` events received correctly
- [ ] `statePublisher` events handled correctly

### Hermes API Integration
- [ ] WebSocket connection to Hermes server
- [ ] Authentication with API token
- [ ] Message serialization format matches Hermes expectations
- [ ] Tool execution responses parsed correctly

### iOS Framework Integration
- [ ] EventKit permissions (Reminders)
- [ ] Contacts access (iMessage recipient lookup)
- [ ] Location permissions (memory tagging)
- [ ] Camera/microphone permissions (streaming)

---

## Runtime Validation

### Vision Pipeline
```
Glasses Camera -> StreamSession -> VisionFrameProcessor -> 
HermesService -> Hermes Agent -> Response
```
- [ ] Frame capture at ~1fps
- [ ] JPEG compression under 200KB
- [ ] Base64 encoding works
- [ ] Vision context injected in commands

### Voice Commands
- [ ] "What am I looking at?" triggers vision analysis
- [ ] "Remind me to..." creates reminder
- [ ] "Text [person] [message]" sends iMessage
- [ ] "Turn on lights" controls Hue

### Performance Adaptation
- [ ] Frame rate drops at <20% battery
- [ ] Quality reduces at thermal .serious
- [ ] HEVC background streaming works
- [ ] Reconnection after network loss

### Memory System
- [ ] "Remember this" saves with photo
- [ ] Location tagged correctly
- [ ] Search retrieves memories
- [ ] Old memories auto-purged after 90 days

---

## Device Testing

### Meta Ray-Ban Stories
- [ ] Developer Mode enabled
- [ ] App pairs with glasses
- [ ] Streaming starts/stops correctly
- [ ] Audio output via glasses speaker
- [ ] Camera frames received

### iOS Device
- [ ] iPhone 12+ or compatible
- [ ] iOS 16.0+
- [ ] Bluetooth permissions
- [ ] Local network permissions (for mDNS)

---

## Error Scenarios

- [ ] Network unavailable -> graceful degradation
- [ ] Hermes server down -> retry with backoff
- [ ] Glasses disconnected -> pause streaming
- [ ] Low battery -> enter power save mode
- [ ] Thermal throttling -> reduce quality

---

## Known Issues to Fix

1. **Import Statements**
   - FIXED: `MetaWearablesSDK` -> `MWDATCamera` + `MWDATCore`

2. **StreamSession Type**
   - Check: `PerformanceMonitor.setStreamSession()` parameter type matches SDK

3. **WebSocket Messages**
   - TODO: Define actual Hermes API message format
   - Current: Placeholder implementations

4. **Tool Execution**
   - TODO: Implement actual Hermes tool call API
   - Current: Placeholder responses

5. **iOS Permissions**
   - TODO: Add NSRemindersUsageDescription to Info.plist
   - TODO: Add NSContactsUsageDescription to Info.plist
   - TODO: Add NSLocationWhenInUseUsageDescription to Info.plist

---

## Quick Build Test Commands

```bash
cd ~/projects/hermespecs

# Open in Xcode
open CameraAccess.xcodeproj

# Or build from command line (requires xcodebuild)
xcodebuild -project CameraAccess.xcodeproj \
  -scheme CameraAccess \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  clean build
```

---

## Estimated Test Time

| Component | Setup | Testing | Total |
|-----------|-------|---------|-------|
| Build fixes | 30 min | 1 hour | 1.5 hrs |
| Meta glasses pairing | 15 min | 30 min | 45 min |
| Hermes integration | 15 min | 2 hours | 2.25 hrs |
| Vision pipeline | 0 min | 1 hour | 1 hour |
| Tool execution | 0 min | 2 hours | 2 hours |
| Performance | 0 min | 30 min | 30 min |
| **TOTAL** | | | **~8 hours** |

---

## Success Criteria

- [ ] App builds without errors
- [ ] App launches on iOS device
- [ ] Pairs with Meta glasses
- [ ] Streaming shows video feed
- [ ] Voice command triggers action
- [ ] Action completes successfully
- [ ] Response spoken via glasses

---

**Status**: Implementation complete, testing pending
**Last Updated**: 2026-04-13
