#!/bin/bash
# =============================================================================
# Life Wrapped — Privacy Verification Script
# =============================================================================
# Searches for unauthorized network/cloud usage in the codebase.
# This is part of our "no network calls by default" proof.
# =============================================================================
# Usage: ./Scripts/verify-privacy.sh
# =============================================================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

# Source directories (exclude Tests and generated code)
SOURCE_DIRS="App Extensions WatchApp MacApp Packages"

print_header "Privacy Verification"
echo "This script searches for potentially unauthorized network usage."
echo "Lines marked with '// PRIVACY-ALLOWED:' are expected and whitelisted."
echo ""

ISSUES_FOUND=0

# -----------------------------------------------------------------------------
# Check 1: URLSession / URLRequest usage
# -----------------------------------------------------------------------------
echo -e "${CYAN}━━━ Check 1: URLSession / URLRequest Usage ━━━${NC}"
echo ""

NETWORK_PATTERNS="URLSession|URLRequest|URL\(string:|URLComponents"

for dir in $SOURCE_DIRS; do
    if [ -d "$dir" ]; then
        RESULTS=$(grep -rn --include="*.swift" -E "$NETWORK_PATTERNS" "$dir" 2>/dev/null \
            | grep -v "PRIVACY-ALLOWED:" \
            | grep -v "Tests/" \
            | grep -v ".build/" \
            | grep -v "// Example:" \
            || true)
        
        if [ -n "$RESULTS" ]; then
            print_warning "Found URL/Network usage in $dir:"
            echo "$RESULTS" | head -20
            ((ISSUES_FOUND++)) || true
        fi
    fi
done

if [ $ISSUES_FOUND -eq 0 ]; then
    print_success "No unauthorized URLSession/URLRequest usage found"
fi
echo ""

# -----------------------------------------------------------------------------
# Check 2: Third-party networking libraries
# -----------------------------------------------------------------------------
echo -e "${CYAN}━━━ Check 2: Third-Party Network Libraries ━━━${NC}"
echo ""

THIRD_PARTY_PATTERNS="Alamofire|AFNetworking|Moya|Apollo|import Combine.*URL"

THIRD_PARTY_FOUND=false
for dir in $SOURCE_DIRS; do
    if [ -d "$dir" ]; then
        RESULTS=$(grep -rn --include="*.swift" -E "$THIRD_PARTY_PATTERNS" "$dir" 2>/dev/null \
            | grep -v "PRIVACY-ALLOWED:" \
            | grep -v "Tests/" \
            | grep -v ".build/" \
            || true)
        
        if [ -n "$RESULTS" ]; then
            print_warning "Found third-party network library usage in $dir:"
            echo "$RESULTS"
            THIRD_PARTY_FOUND=true
            ((ISSUES_FOUND++)) || true
        fi
    fi
done

if [ "$THIRD_PARTY_FOUND" = false ]; then
    print_success "No third-party networking libraries found"
fi
echo ""

# -----------------------------------------------------------------------------
# Check 3: Cloud/Remote API patterns
# -----------------------------------------------------------------------------
echo -e "${CYAN}━━━ Check 3: Cloud/Remote API Patterns ━━━${NC}"
echo ""

CLOUD_PATTERNS="api\.openai\.com|api\.anthropic\.com|googleapis\.com|azure\.com"
CLOUD_PATTERNS+="|firebase|analytics|crashlytics|sentry"

CLOUD_FOUND=false
for dir in $SOURCE_DIRS; do
    if [ -d "$dir" ]; then
        RESULTS=$(grep -rni --include="*.swift" -E "$CLOUD_PATTERNS" "$dir" 2>/dev/null \
            | grep -v "PRIVACY-ALLOWED:" \
            | grep -v "Tests/" \
            | grep -v ".build/" \
            | grep -v "// Doc:" \
            || true)
        
        if [ -n "$RESULTS" ]; then
            print_warning "Found cloud/remote API references in $dir:"
            echo "$RESULTS"
            CLOUD_FOUND=true
            ((ISSUES_FOUND++)) || true
        fi
    fi
done

if [ "$CLOUD_FOUND" = false ]; then
    print_success "No unauthorized cloud API references found"
fi
echo ""

# -----------------------------------------------------------------------------
# Check 4: Allowed CloudKit usage (should be user-triggered only)
# -----------------------------------------------------------------------------
echo -e "${CYAN}━━━ Check 4: CloudKit Usage (Must Be User-Triggered) ━━━${NC}"
echo ""

CLOUDKIT_USAGE=$(grep -rn --include="*.swift" "CKContainer\|CKDatabase\|CKRecord" \
    App Extensions WatchApp MacApp Packages 2>/dev/null \
    | grep -v "Tests/" \
    | grep -v ".build/" \
    || true)

if [ -n "$CLOUDKIT_USAGE" ]; then
    print_info "CloudKit usage found (verify it's user-triggered):"
    echo "$CLOUDKIT_USAGE" | head -10
    echo ""
    print_info "CloudKit is allowed if explicitly user-initiated"
else
    print_success "No CloudKit usage found (will be added in Phase 2)"
fi
echo ""

# -----------------------------------------------------------------------------
# Check 5: Speech Recognition (must be on-device)
# -----------------------------------------------------------------------------
echo -e "${CYAN}━━━ Check 5: Speech Recognition Configuration ━━━${NC}"
echo ""

SPEECH_USAGE=$(grep -rn --include="*.swift" "SFSpeechRecognizer\|requiresOnDeviceRecognition" \
    Packages App 2>/dev/null \
    | grep -v "Tests/" \
    | grep -v ".build/" \
    || true)

if [ -n "$SPEECH_USAGE" ]; then
    # Check for on-device flag
    ON_DEVICE_CHECK=$(echo "$SPEECH_USAGE" | grep -c "requiresOnDeviceRecognition.*=.*true" || true)
    
    if [ "$ON_DEVICE_CHECK" -gt 0 ]; then
        print_success "Speech recognition configured for on-device only"
    else
        print_warning "Speech recognition found - verify requiresOnDeviceRecognition = true"
        echo "$SPEECH_USAGE"
        ((ISSUES_FOUND++)) || true
    fi
else
    print_info "No speech recognition code found yet"
fi
echo ""

# -----------------------------------------------------------------------------
# Check 6: Verify no secrets in code
# -----------------------------------------------------------------------------
echo -e "${CYAN}━━━ Check 6: Hardcoded Secrets Check ━━━${NC}"
echo ""

SECRET_PATTERNS="api[_-]?key.*=.*\"|secret.*=.*\"|password.*=.*\"|token.*=.*\""

SECRETS_FOUND=false
for dir in $SOURCE_DIRS; do
    if [ -d "$dir" ]; then
        RESULTS=$(grep -rni --include="*.swift" -E "$SECRET_PATTERNS" "$dir" 2>/dev/null \
            | grep -v "PRIVACY-ALLOWED:" \
            | grep -v "Tests/" \
            | grep -v ".build/" \
            | grep -v "Example" \
            | grep -v "placeholder" \
            | grep -v "your.*here" \
            || true)
        
        if [ -n "$RESULTS" ]; then
            print_error "Potential hardcoded secrets found in $dir:"
            echo "$RESULTS"
            SECRETS_FOUND=true
            ((ISSUES_FOUND++)) || true
        fi
    fi
done

if [ "$SECRETS_FOUND" = false ]; then
    print_success "No hardcoded secrets detected"
fi
echo ""

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
print_header "Privacy Verification Summary"

if [ $ISSUES_FOUND -eq 0 ]; then
    print_success "All privacy checks passed!"
    echo ""
    echo "Additional manual verification steps:"
    echo "  1. Run app with Charles Proxy - verify no HTTP traffic"
    echo "  2. Use Instruments Network template - verify no connections"
    echo "  3. Enable Network Link Conditioner 100% loss - app should work"
    echo ""
    exit 0
else
    print_error "Found $ISSUES_FOUND potential privacy issue(s)"
    echo ""
    echo "Review the warnings above and either:"
    echo "  1. Remove the unauthorized network code"
    echo "  2. Add '// PRIVACY-ALLOWED: <reason>' comment if legitimate"
    echo ""
    exit 1
fi
