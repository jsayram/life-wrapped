#!/bin/bash
# =============================================================================
# Life Wrapped — Format Script
# =============================================================================
# Usage: ./Scripts/format.sh [path]
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

# Check for swift-format
SWIFT_FORMAT_PATH=""
if command -v swift-format &> /dev/null; then
    SWIFT_FORMAT_PATH="swift-format"
elif [ -f "/opt/homebrew/bin/swift-format" ]; then
    SWIFT_FORMAT_PATH="/opt/homebrew/bin/swift-format"
elif [ -f "/usr/local/bin/swift-format" ]; then
    SWIFT_FORMAT_PATH="/usr/local/bin/swift-format"
fi

if [ -z "$SWIFT_FORMAT_PATH" ]; then
    echo "swift-format not found. Installing..."
    brew install swift-format || {
        echo "Failed to install swift-format. Please install manually:"
        echo "  brew install swift-format"
        exit 1
    }
    SWIFT_FORMAT_PATH="swift-format"
fi

# -----------------------------------------------------------------------------
# Format
# -----------------------------------------------------------------------------
print_header "Formatting Swift Code"

# Directories to format
if [ -n "$1" ]; then
    FORMAT_DIRS="$1"
else
    FORMAT_DIRS="App Extensions WatchApp Packages"
fi

CONFIG_FILE=".swift-format"
CONFIG_ARG=""
if [ -f "$CONFIG_FILE" ]; then
    CONFIG_ARG="--configuration $CONFIG_FILE"
    echo "Using config: $CONFIG_FILE"
fi

FILE_COUNT=0

for dir in $FORMAT_DIRS; do
    if [ -d "$dir" ]; then
        echo "Formatting $dir..."
        
        # Find and format Swift files
        while IFS= read -r -d '' file; do
            "$SWIFT_FORMAT_PATH" format --in-place $CONFIG_ARG "$file" 2>/dev/null || true
            ((FILE_COUNT++)) || true
        done < <(find "$dir" -name "*.swift" -type f -print0)
    fi
done

echo ""
print_success "Formatted $FILE_COUNT Swift files"
