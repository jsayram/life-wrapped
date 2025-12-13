#!/bin/bash
# =============================================================================
# Life Wrapped — Test Script
# =============================================================================
# Usage: ./Scripts/test.sh [target]
# Targets: unit, integration, ui, performance, packages, all
# =============================================================================

set -e  # Exit on error

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
WORKSPACE="LifeWrapped.xcworkspace"
SCHEME_TESTS="LifeWrappedTests"
SCHEME_UI_TESTS="LifeWrappedUITests"

DESTINATION_IOS="platform=iOS Simulator,name=iPhone 16 Pro"
DERIVED_DATA_PATH="./DerivedData"
RESULT_BUNDLE_PATH="./TestResults"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Helper Functions
# -----------------------------------------------------------------------------
print_header() {
    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

check_workspace() {
    if [ ! -d "$WORKSPACE" ]; then
        print_warning "Workspace not found."
        return 1
    fi
    return 0
}

# Ensure result bundle directory exists
mkdir -p "$RESULT_BUNDLE_PATH"

# -----------------------------------------------------------------------------
# Test Functions
# -----------------------------------------------------------------------------
test_packages() {
    print_header "Running Package Tests"
    
    PACKAGES_DIR="./Packages"
    
    if [ ! -d "$PACKAGES_DIR" ]; then
        print_warning "Packages directory not found"
        return 0
    fi
    
    local failed=0
    
    for package in "$PACKAGES_DIR"/*/; do
        if [ -f "${package}Package.swift" ]; then
            package_name=$(basename "$package")
            echo ""
            echo "Testing package: $package_name"
            echo "─────────────────────────────────────"
            
            (cd "$package" && swift test --parallel) || {
                print_error "Tests failed for $package_name"
                failed=1
            }
        fi
    done
    
    if [ $failed -eq 0 ]; then
        print_success "All package tests passed"
    else
        print_error "Some package tests failed"
        return 1
    fi
}

test_unit() {
    print_header "Running Unit Tests"
    
    if ! check_workspace; then
        print_warning "Falling back to package tests only"
        test_packages
        return
    fi
    
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME_TESTS" \
        -destination "$DESTINATION_IOS" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -resultBundlePath "$RESULT_BUNDLE_PATH/UnitTests.xcresult" \
        -only-testing:LifeWrappedTests/UnitTests \
        test \
        | xcbeautify 2>/dev/null || xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME_TESTS" \
            -destination "$DESTINATION_IOS" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -resultBundlePath "$RESULT_BUNDLE_PATH/UnitTests.xcresult" \
            -only-testing:LifeWrappedTests/UnitTests \
            test
    
    print_success "Unit tests completed"
}

test_integration() {
    print_header "Running Integration Tests"
    
    if ! check_workspace; then
        print_error "Integration tests require workspace"
        return 1
    fi
    
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME_TESTS" \
        -destination "$DESTINATION_IOS" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -resultBundlePath "$RESULT_BUNDLE_PATH/IntegrationTests.xcresult" \
        -only-testing:LifeWrappedTests/IntegrationTests \
        test \
        | xcbeautify 2>/dev/null || xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME_TESTS" \
            -destination "$DESTINATION_IOS" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -resultBundlePath "$RESULT_BUNDLE_PATH/IntegrationTests.xcresult" \
            -only-testing:LifeWrappedTests/IntegrationTests \
            test
    
    print_success "Integration tests completed"
}

test_ui() {
    print_header "Running UI Tests"
    
    if ! check_workspace; then
        print_error "UI tests require workspace"
        return 1
    fi
    
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME_UI_TESTS" \
        -destination "$DESTINATION_IOS" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -resultBundlePath "$RESULT_BUNDLE_PATH/UITests.xcresult" \
        test \
        | xcbeautify 2>/dev/null || xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME_UI_TESTS" \
            -destination "$DESTINATION_IOS" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -resultBundlePath "$RESULT_BUNDLE_PATH/UITests.xcresult" \
            test
    
    print_success "UI tests completed"
}

test_performance() {
    print_header "Running Performance Tests"
    
    if ! check_workspace; then
        print_error "Performance tests require workspace"
        return 1
    fi
    
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME_TESTS" \
        -destination "$DESTINATION_IOS" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -resultBundlePath "$RESULT_BUNDLE_PATH/PerformanceTests.xcresult" \
        -only-testing:LifeWrappedTests/PerformanceTests \
        test \
        | xcbeautify 2>/dev/null || xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME_TESTS" \
            -destination "$DESTINATION_IOS" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -resultBundlePath "$RESULT_BUNDLE_PATH/PerformanceTests.xcresult" \
            -only-testing:LifeWrappedTests/PerformanceTests \
            test
    
    print_success "Performance tests completed"
    echo ""
    echo "View results in Xcode: open $RESULT_BUNDLE_PATH/PerformanceTests.xcresult"
}

test_all() {
    print_header "Running All Tests"
    
    test_packages
    
    if check_workspace; then
        # Run all Xcode tests
        xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME_TESTS" \
            -destination "$DESTINATION_IOS" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -resultBundlePath "$RESULT_BUNDLE_PATH/AllTests.xcresult" \
            test \
            | xcbeautify 2>/dev/null || xcodebuild \
                -workspace "$WORKSPACE" \
                -scheme "$SCHEME_TESTS" \
                -destination "$DESTINATION_IOS" \
                -derivedDataPath "$DERIVED_DATA_PATH" \
                -resultBundlePath "$RESULT_BUNDLE_PATH/AllTests.xcresult" \
                test
    fi
    
    print_success "All tests completed"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
TARGET="${1:-all}"

case "$TARGET" in
    unit)
        test_unit
        ;;
    integration)
        test_integration
        ;;
    ui)
        test_ui
        ;;
    performance)
        test_performance
        ;;
    packages)
        test_packages
        ;;
    all)
        test_all
        ;;
    *)
        echo "Usage: $0 [unit|integration|ui|performance|packages|all]"
        exit 1
        ;;
esac

echo ""
print_success "Testing complete!"
echo "Results available at: $RESULT_BUNDLE_PATH"
