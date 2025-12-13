#!/bin/bash
# =============================================================================
# Create Xcode Project for Life Wrapped
# =============================================================================
# This script will open Xcode and guide you through creating the project
# =============================================================================

set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Life Wrapped — Xcode Project Setup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Since xcodegen is not installed, we'll create the project in Xcode."
echo ""
echo "OPTION 1: Install xcodegen and generate automatically"
echo "  brew install xcodegen"
echo "  xcodegen generate"
echo ""
echo "OPTION 2: Create manually in Xcode (recommended for first time)"
echo ""
echo "Opening Xcode now..."
echo ""

# Check if we already have a project
if [ -f "LifeWrapped.xcodeproj/project.pbxproj" ]; then
    echo "✓ Project already exists"
    open LifeWrapped.xcworkspace 2>/dev/null || open LifeWrapped.xcodeproj
    exit 0
fi

echo "Please follow these steps in Xcode:"
echo ""
echo "1. File → New → Project"
echo "2. Choose: iOS → App"
echo "3. Product Name: LifeWrapped"
echo "4. Team: Your development team"
echo "5. Organization Identifier: com.jsayram (or your prefix)"
echo "6. Interface: SwiftUI"
echo "7. Language: Swift"
echo "8. Storage: None"
echo "9. Include Tests: Yes"
echo "10. Save Location: $(pwd)"
echo ""
echo "After creating the project:"
echo "11. File → Add Package Dependencies"
echo "12. Click 'Add Local...'"
echo "13. Navigate to: $(pwd)/Packages/SharedModels"
echo "14. Add Package"
echo ""
echo "Press ENTER to open Xcode..."
read

open -a Xcode .
