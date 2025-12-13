#!/bin/bash
# =============================================================================
# Life Wrapped — Lint Script
# =============================================================================
# Usage: ./Scripts/lint.sh [--fix]
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

# Check for SwiftLint
SWIFTLINT_PATH=""
if command -v swiftlint &> /dev/null; then
    SWIFTLINT_PATH="swiftlint"
elif [ -f "/opt/homebrew/bin/swiftlint" ]; then
    SWIFTLINT_PATH="/opt/homebrew/bin/swiftlint"
elif [ -f "/usr/local/bin/swiftlint" ]; then
    SWIFTLINT_PATH="/usr/local/bin/swiftlint"
fi

# Check for swift-format
SWIFT_FORMAT_PATH=""
if command -v swift-format &> /dev/null; then
    SWIFT_FORMAT_PATH="swift-format"
elif [ -f "/opt/homebrew/bin/swift-format" ]; then
    SWIFT_FORMAT_PATH="/opt/homebrew/bin/swift-format"
elif [ -f "/usr/local/bin/swift-format" ]; then
    SWIFT_FORMAT_PATH="/usr/local/bin/swift-format"
fi

FIX_MODE=false
if [ "$1" == "--fix" ]; then
    FIX_MODE=true
fi

# -----------------------------------------------------------------------------
# SwiftLint
# -----------------------------------------------------------------------------
run_swiftlint() {
    print_header "Running SwiftLint"
    
    if [ -z "$SWIFTLINT_PATH" ]; then
        print_warning "SwiftLint not found. Install with: brew install swiftlint"
        return 0
    fi
    
    if [ ! -f ".swiftlint.yml" ]; then
        print_warning "No .swiftlint.yml found, using defaults"
    fi
    
    LINT_DIRS="App Extensions WatchApp Packages"
    
    if [ "$FIX_MODE" = true ]; then
        echo "Running SwiftLint with auto-fix..."
        for dir in $LINT_DIRS; do
            if [ -d "$dir" ]; then
                "$SWIFTLINT_PATH" lint --fix --path "$dir" || true
            fi
        done
    fi
    
    local has_errors=false
    for dir in $LINT_DIRS; do
        if [ -d "$dir" ]; then
            echo "Linting $dir..."
            "$SWIFTLINT_PATH" lint --path "$dir" --reporter emoji || has_errors=true
        fi
    done
    
    if [ "$has_errors" = true ]; then
        print_warning "SwiftLint found issues"
        return 1
    else
        print_success "SwiftLint passed"
    fi
}

# -----------------------------------------------------------------------------
# Swift Format (Check)
# -----------------------------------------------------------------------------
run_swift_format_check() {
    print_header "Checking Swift Format"
    
    if [ -z "$SWIFT_FORMAT_PATH" ]; then
        print_warning "swift-format not found. Install with: brew install swift-format"
        return 0
    fi
    
    LINT_DIRS="App Extensions WatchApp Packages"
    local has_issues=false
    
    for dir in $LINT_DIRS; do
        if [ -d "$dir" ]; then
            echo "Checking format in $dir..."
            # Find Swift files and check format
            find "$dir" -name "*.swift" -type f | while read -r file; do
                if ! "$SWIFT_FORMAT_PATH" lint "$file" 2>/dev/null; then
                    has_issues=true
                fi
            done
        fi
    done
    
    if [ "$has_issues" = true ]; then
        print_warning "Some files need formatting. Run ./Scripts/format.sh"
        return 1
    else
        print_success "Format check passed"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
print_header "Life Wrapped — Code Quality Check"

LINT_FAILED=false

run_swiftlint || LINT_FAILED=true
run_swift_format_check || LINT_FAILED=true

echo ""
if [ "$LINT_FAILED" = true ]; then
    print_warning "Some lint checks failed"
    echo "Run './Scripts/lint.sh --fix' to auto-fix some issues"
    echo "Run './Scripts/format.sh' to format code"
    exit 1
else
    print_success "All lint checks passed!"
fi
