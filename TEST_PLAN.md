# HermeSpecs Test Plan

## Overview

This document outlines the comprehensive test suite for HermeSpecs.

**Test Files Created:**
1. HermesServiceTests.swift (234 lines)
2. VisionFrameProcessorTests.swift (248 lines)
3. ToolRegistryTests.swift (195 lines)
4. ToolExecutorsTests.swift (378 lines)
5. VisionFrameBufferTests.swift (274 lines)
6. PerformanceMonitorTests.swift (303 lines)
7. MultimodalMemoryTests.swift (433 lines)
8. ConnectionRecoveryTests.swift (373 lines)

**Total Test Lines:** ~2,438 lines of test code

---

## Unit Test Coverage

### Phase 1: Foundation

#### HermesServiceTests (12 tests)
- Connection establishment with valid/invalid configs
- Authentication handling
- Command sending with JSON validation
- Vision command with image data
- Response parsing
- Connection timeout handling
- Authentication failure
- Reconnection after disconnect

**Status:** ✅ Written, ❌ Not executed

### Phase 2: Vision

#### VisionFrameProcessorTests (11 tests)
- Image processing with valid UIImage
- Large image resizing
- File size limits (200KB)
- Compression quality adjustment
- Custom configuration
- Sample buffer processing
- Performance benchmarks
- Multiple consecutive frames

**Status:** ✅ Written, ❌ Not executed

#### VisionFrameBufferTests (12 tests)
- Basic add/get operations
- Max capacity enforcement
- Oldest frame removal (circular buffer)
- Get latest frame
- Capture frame for command
- Timing/cooldown enforcement
- Age-based cleanup
- Clear all frames
- Thread safety - concurrent access
- Thread safety - add/remove
- Statistics calculation

**Status:** ✅ Written, ❌ Not executed

### Phase 3: Tools

#### ToolRegistryTests (14 tests)
- Tool registration counts
- Get tool by valid/invalid ID
- Get all tools
- Get tools by category
- Search tools by query
- Case-insensitive search
- Search by shortcut
- No results handling
- Tool parameter validation
- Local vs remote execution
- Executor registration
- Category count aggregation
- All categories have tools

**Status:** ✅ Written, ❌ Not executed

#### ToolExecutorsTests (18 tests)
- Reminders: validate parameters
- Reminders: missing title
- Reminders: execution
- Timer: validate parameters
- Timer: parse minutes
- Timer: parse hours
- Timer: parse seconds
- iMessage: validate parameters
- iMessage: missing fields
- iMessage: create SMS URL
- iMessage: URL encoding
- Music: play action
- Music: pause action
- Music: skip action
- Music: play with query
- Voice confirmation: communication tools
- Voice confirmation: destructive actions
- Voice confirmation: message generation
- Voice confirmation: success messages

**Status:** ✅ Written, ❌ Not executed

### Phase 4: Performance

#### PerformanceMonitorTests (19 tests)
- Initialization with defaults
- Latency tracking: excellent quality
- Latency tracking: fair quality
- Latency tracking: poor quality
- Latency average calculation
- Frame tracking: increment count
- Frame tracking: dropped frames
- Frame drop rate calculation
- Recommendations: low battery
- Recommendations: thermal throttling
- Recommendations: critical thermal
- Recommendations: high latency
- Performance report: all metrics
- Performance report: health status
- Performance report: unhealthy battery
- Performance report: high drops
- Memory usage tracking
- Cleanup on stop

**Status:** ✅ Written, ❌ Not executed

#### MultimodalMemoryTests (21 tests)
- Remember: create memory
- Remember: with image
- Remember: with tags
- Remember: adds to memories list
- Remember: adds to recent memories
- Remember from frame: creates vision memory
- Search: by text
- Search: by tag
- Search: by date range
- Search: by source
- Search: limits results
- NL query: today
- NL query: yesterday
- Delete memory: removes from lists
- Add tag: updates memory
- Cleanup: removes old entries
- Cleanup: respects max count
- Export: returns valid data

**Status:** ✅ Written, ❌ Not executed

#### ConnectionRecoveryTests (26 tests)
- Initial state
- Connect success
- Connect failure
- Disconnect resets state
- Recovery: increments retry count
- Recovery: max retries reached
- Recovery: non-recoverable error
- Reset retry count
- State transitions: disconnected to connecting
- State transitions: connected to disconnected
- Callback: onStateChanged
- Callback: onRecoveryAttempt
- Callback: onRecovered
- Callback: onPermanentlyFailed
- Status: returns current state
- Status: shows retry UI
- Status: recovery progress
- Error classification: recoverable
- Error classification: non-recoverable
- Error descriptions

**Status:** ✅ Written, ❌ Not executed

---

## Integration Tests Needed

### WebSocket Integration
- [ ] Connect to real Hermes server
- [ ] Send/receive messages
- [ ] Handle reconnection
- [ ] Authentication flow

### Meta SDK Integration
- [ ] StreamSession lifecycle
- [ ] Video frame capture
- [ ] Device pairing
- [ ] Permission handling

### iOS Framework Integration
- [ ] EventKit (Reminders)
- [ ] Contacts (iMessage lookup)
- [ ] CoreLocation (memory tagging)
- [ ] AVFoundation (audio)

### Tool Execution Integration
- [ ] Local tool execution on device
- [ ] Remote tool execution via Hermes
- [ ] Voice confirmation flow
- [ ] Error handling

---

## UI Tests Needed

### Navigation Flows
- [ ] Launch app
- [ ] Navigate to settings
- [ ] Configure Hermes integration
- [ ] Start/stop streaming
- [ ] Execute voice command

### Voice Interaction
- [ ] Trigger voice input
- [ ] Display response
- [ ] Confirmation dialog
- [ ] Error states

---

## Performance Tests

### Load Testing
- [ ] 1000+ memories in database
- [ ] 10fps frame processing
- [ ] Multiple concurrent commands

### Battery Testing
- [ ] 1 hour continuous streaming
- [ ] Battery drain rate
- [ ] Thermal throttling behavior

### Network Testing
- [ ] Poor connection (2G)
- [ ] Intermittent connection
- [ ] High latency (>1s)
- [ ] Packet loss scenarios

---

## Device Tests

### Meta Ray-Ban Glasses
- [ ] Developer Mode enabled
- [ ] Pairing process
- [ ] Audio output
- [ ] Camera streaming
- [ ] Display notifications

### iOS Devices
- [ ] iPhone 12
- [ ] iPhone 14
- [ ] iPhone 15 Pro
- [ ] iOS 16.0+

---

## Running Tests

### Command Line
```bash
cd ~/projects/hermespecs

# Run all tests
xcodebuild test \
  -project CameraAccess.xcodeproj \
  -scheme CameraAccess \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:CameraAccessTests

# Run specific test class
xcodebuild test \
  -project CameraAccess.xcodeproj \
  -scheme CameraAccess \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:CameraAccessTests/HermesServiceTests

# Run specific test method
xcodebuild test \
  -project CameraAccess.xcodeproj \
  -scheme CameraAccess \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -only-testing:CameraAccessTests/HermesServiceTests/testConnection_WithValidConfig_ReturnsConnected
```

### Xcode IDE
1. Open `CameraAccess.xcodeproj`
2. Select test navigator (Cmd+6)
3. Click play button next to test class or method
4. View results in Report Navigator

---

## Coverage Goals

| Component | Target | Current |
|-----------|--------|---------|
| HermesService | 90% | N/A (not measured) |
| VisionFrameProcessor | 85% | N/A |
| ToolRegistry | 90% | N/A |
| ToolExecutors | 80% | N/A |
| PerformanceMonitor | 85% | N/A |
| MultimodalMemory | 85% | N/A |
| ConnectionRecovery | 90% | N/A |
| **Overall** | **85%** | **N/A** |

---

## Known Issues

1. **Import statements** need verification for actual SDK names
2. **Mock implementations** are minimal - need full mocks for dependencies
3. **Async testing** patterns need refinement for Swift concurrency
4. **Test data setup** could be extracted to shared fixtures
5. **Some tests** may fail in CI without actual iOS simulator

---

## Test Execution Checklist

- [ ] All unit tests compile
- [ ] All unit tests pass in simulator
- [ ] All unit tests pass on device
- [ ] Code coverage measured
- [ ] Integration tests pass
- [ ] UI tests pass
- [ ] Performance benchmarks met
- [ ] Memory leaks checked
- [ ] Thread sanitizer clean
- [ ] Accessibility tests pass

---

## Next Steps

1. **Add test target** to Xcode project
2. **Run tests** and fix compilation errors
3. **Fix failing tests** based on actual behavior
4. **Add mocks** for dependencies
5. **Measure coverage** with Xcode's coverage tool
6. **Add integration tests** for real services
7. **Add UI tests** for critical flows

---

**Status:** Test suite created, execution pending
**Last Updated:** 2026-04-13
