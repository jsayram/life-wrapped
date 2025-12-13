#!/bin/bash
# =============================================================================
# Life Wrapped — Build Script
# =============================================================================
# Usage: ./Scripts/build.sh [target]
# Targets: ios, watch, widgets, packages, all, clean
# =============================================================================

set -e  # Exit on error

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
WORKSPACE="LifeWrapped.xcworkspace"
SCHEME_IOS="LifeWrapped"
SCHEME_WATCH="LifeWrappedWatch"
SCHEME_WIDGETS="LifeWrappedWidgets"

DESTINATION_IOS="platform=iOS Simulator,name=iPhone 16 Pro"
DESTINATION_WATCH="platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)"

DERIVED_DATA_PATH="./DerivedData"
BUILD_DIR="./build"

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

# Check if workspace exists
check_workspace() {
    if [ ! -d "$WORKSPACE" ]; then
        print_warning "Workspace not found. Building packages only..."
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Build Functions
# -----------------------------------------------------------------------------
build_ios() {
    print_header "Building iOS App"
    
    if ! check_workspace; then
        print_error "Cannot build iOS without workspace"
        return 1
    fi
    
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME_IOS" \
        -destination "$DESTINATION_IOS" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -configuration Debug \
        build \
        | xcbeautify || xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME_IOS" \
            -destination "$DESTINATION_IOS" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -configuration Debug \
            build
    
    print_success "iOS build completed"
}

build_watch() {
    print_header "Building watchOS App"
    
    if ! check_workspace; then
        print_error "Cannot build Watch without workspace"
        return 1
    fi
    
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME_WATCH" \
        -destination "$DESTINATION_WATCH" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -configuration Debug \
        build \
        | xcbeautify 2>/dev/null || xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME_WATCH" \
            -destination "$DESTINATION_WATCH" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -configuration Debug \
            build
    
    print_success "watchOS build completed"
}

build_widgets() {
    print_header "Building Widgets Extension"
    
    if ! check_workspace; then
        print_error "Cannot build Widgets without workspace"
        return 1
    fi
    
    xcodebuild \
        -workspace "$WORKSPACE" \
        -scheme "$SCHEME_WIDGETS" \
        -destination "$DESTINATION_IOS" \
        -derivedDataPath "$DERIVED_DATA_PATH" \
        -configuration Debug \
        build \
        | xcbeautify 2>/dev/null || xcodebuild \
            -workspace "$WORKSPACE" \
            -scheme "$SCHEME_WIDGETS" \
            -destination "$DESTINATION_IOS" \
            -derivedDataPath "$DERIVED_DATA_PATH" \
            -configuration Debug \
            build
    
    print_success "Widgets build completed"
}

build_packages() {
    print_header "Building Swift Packages"
    
    PACKAGES_DIR="./Packages"
    
    if [ ! -d "$PACKAGES_DIR" ]; then
        print_warning "Packages directory not found"
        return 0
    fi
    
    for package in "$PACKAGES_DIR"/*/; do
        if [ -f "${package}Package.swift" ]; then
            package_name=$(basename "$package")
            echo "Building package: $package_name"
            (cd "$package" && swift build) || {
                print_error "Failed to build $package_name"
                return 1
            }
            print_success "Built $package_name"
        fi
    done
    
    print_success "All packages built"
}

clean_all() {
    print_header "Cleaning Build Artifacts"
    
    # Clean Xcode derived data
    if [ -d "$DERIVED_DATA_PATH" ]; then
        rm -rf "$DERIVED_DATA_PATH"
        print_success "Removed DerivedData"
    fi
    
    # Clean build directory
    if [ -d "$BUILD_DIR" ]; then
        rm -rf "$BUILD_DIR"
        print_success "Removed build directory"
    fi
    
    # Clean SPM build directories
    if [ -d "./Packages" ]; then
        find ./Packages -name ".build" -type d -exec rm -rf {} + 2>/dev/null || true
        print_success "Removed package .build directories"
    fi
    
    # Clean root .build
    if [ -d "./.build" ]; then
        rm -rf "./.build"
        print_success "Removed root .build"
    fi
    
    print_success "Clean completed"
}

build_all() {
    print_header "Building All Targets"
    
    build_packages
    
    if check_workspace; then
        build_ios
        build_watch
        build_widgets
    fi
    
    print_success "All builds completed"
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
TARGET="${1:-all}"

case "$TARGET" in
    ios)
        build_ios
        ;;
    watch)
        build_watch
        ;;
    widgets)
        build_widgets
        ;;
    packages)
        build_packages
        ;;
    all)
        build_all
        ;;
    clean)
        clean_all
        ;;
    *)
        echo "Usage: $0 [ios|watch|widgets|packages|all|clean]"
        exit 1
        ;;
esac

echo ""
print_success "Done!"
