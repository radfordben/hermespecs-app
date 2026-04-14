#!/bin/bash

# HermeSpecs Test Runner
# This script runs all tests and generates a report

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================="
echo "  HermeSpecs Test Suite Runner"
echo "========================================="
echo ""

# Check if Xcode is installed
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}Error: xcodebuild not found. Please install Xcode.${NC}"
    exit 1
fi

# Configuration
PROJECT="CameraAccess.xcodeproj"
SCHEME="CameraAccess"
DESTINATION="platform=iOS Simulator,name=iPhone 15,OS=latest"
TEST_TARGET="CameraAccessTests"

# Parse arguments
RUN_UNIT_TESTS=true
RUN_UI_TESTS=false
RUN_PERF_TESTS=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --ui)
            RUN_UI_TESTS=true
            shift
            ;;
        --perf)
            RUN_PERF_TESTS=true
            shift
            ;;
        --all)
            RUN_UI_TESTS=true
            RUN_PERF_TESTS=true
            shift
            ;;
        --verbose|-v)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --ui       Run UI tests"
            echo "  --perf     Run performance tests"
            echo "  --all      Run all tests (unit + UI + perf)"
            echo "  --verbose  Verbose output"
            echo "  --help     Show this help"
            echo ""
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Build flags
BUILD_FLAGS="-project $PROJECT -scheme $SCHEME -destination '$DESTINATION'"
if [ "$VERBOSE" = false ]; then
    BUILD_FLAGS="$BUILD_FLAGS -quiet"
fi

echo "Configuration:"
echo "  Project: $PROJECT"
echo "  Scheme: $SCHEME"
echo "  Destination: $DESTINATION"
echo ""

# Check if test target exists
echo "Checking test target..."
if ! xcodebuild -project $PROJECT -list 2>/dev/null | grep -q "$TEST_TARGET"; then
    echo -e "${YELLOW}Warning: Test target '$TEST_TARGET' not found in project.${NC}"
    echo "Make sure to:"
    echo "  1. Open CameraAccess.xcodeproj in Xcode"
    echo "  2. Create a Unit Test target named 'CameraAccessTests'"
    echo "  3. Add the test files from CameraAccessTests/"
    echo ""
fi

# Run unit tests
if [ "$RUN_UNIT_TESTS" = true ]; then
    echo "========================================="
    echo "  Running Unit Tests"
    echo "========================================="
    echo ""
    
    # Build for testing
    echo "Building for testing..."
    if xcodebuild $BUILD_FLAGS build-for-testing 2>&1 | tee build.log; then
        echo -e "${GREEN}✓ Build successful${NC}"
    else
        echo -e "${RED}✗ Build failed${NC}"
        echo "See build.log for details"
        exit 1
    fi
    echo ""
    
    # Run tests
    echo "Running tests..."
    if xcodebuild $BUILD_FLAGS test -only-testing:$TEST_TARGET 2>&1 | tee test.log; then
        echo -e "${GREEN}✓ All tests passed${NC}"
    else
        echo -e "${RED}✗ Some tests failed${NC}"
        echo "See test.log for details"
        
        # Parse and display failed tests
        echo ""
        echo "Failed tests:"
        grep -A 2 "failed" test.log | head -20
        exit 1
    fi
    echo ""
fi

# Run performance tests
if [ "$RUN_PERF_TESTS" = true ]; then
    echo "========================================="
    echo "  Running Performance Tests"
    echo "========================================="
    echo ""
    
    # Run with performance measurement
    if xcodebuild $BUILD_FLAGS test -only-testing:$TEST_TARGET -testPlan Performance 2>&1 | tee perf.log; then
        echo -e "${GREEN}✓ Performance tests completed${NC}"
    else
        echo -e "${RED}✗ Performance tests failed${NC}"
        exit 1
    fi
    echo ""
fi

# Run UI tests
if [ "$RUN_UI_TESTS" = true ]; then
    echo "========================================="
    echo "  Running UI Tests"
    echo "========================================="
    echo ""
    
    UI_TEST_TARGET="CameraAccessUITests"
    
    if xcodebuild $BUILD_FLAGS test -only-testing:$UI_TEST_TARGET 2>&1 | tee ui_test.log; then
        echo -e "${GREEN}✓ UI tests passed${NC}"
    else
        echo -e "${RED}✗ UI tests failed${NC}"
        exit 1
    fi
    echo ""
fi

# Generate coverage report
echo "========================================="
echo "  Generating Coverage Report"
echo "========================================="
echo ""

# Check if coverage data exists
COVERAGE_DIR="$(xcodebuild -project $PROJECT -showBuildSettings 2>/dev/null | grep -i "BUILD_DIR" | head -1 | cut -d= -f2 | tr -d ' ')/Coverage"

if [ -d "$COVERAGE_DIR" ]; then
    echo "Coverage report available at:"
    echo "  $COVERAGE_DIR"
    echo ""
    echo "Open in Xcode:"
    echo "  xed $COVERAGE_DIR"
else
    echo -e "${YELLOW}Coverage data not found. Enable 'Gather coverage data' in scheme settings.${NC}"
fi

echo ""
echo "========================================="
echo "  Test Summary"
echo "========================================="
echo ""

# Count test results
if [ -f test.log ]; then
    PASSED=$(grep -c "Test Case.*passed" test.log 2>/dev/null || echo "0")
    FAILED=$(grep -c "Test Case.*failed" test.log 2>/dev/null || echo "0")
    
    echo "Unit Tests:"
    echo "  Passed: $PASSED"
    echo "  Failed: $FAILED"
    echo ""
fi

if [ -f perf.log ]; then
    echo "Performance Tests: Completed"
    echo ""
fi

if [ -f ui_test.log ]; then
    UI_PASSED=$(grep -c "Test Case.*passed" ui_test.log 2>/dev/null || echo "0")
    UI_FAILED=$(grep -c "Test Case.*failed" ui_test.log 2>/dev/null || echo "0")
    
    echo "UI Tests:"
    echo "  Passed: $UI_PASSED"
    echo "  Failed: $UI_FAILED"
    echo ""
fi

echo -e "${GREEN}Test run complete!${NC}"
echo ""
echo "Logs:"
echo "  Build: build.log"
echo "  Tests: test.log"
[ -f perf.log ] && echo "  Performance: perf.log"
[ -f ui_test.log ] && echo "  UI Tests: ui_test.log"
