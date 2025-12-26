#!/bin/bash

# This script provides instructions to add the new files to Xcode

echo "========================================="
echo "📋 Instructions to Fix Build Errors"
echo "========================================="
echo ""
echo "The new files created during refactoring need to be added to the Xcode project."
echo ""
echo "Please follow these steps:"
echo ""
echo "1. Open LifeWrapped.xcworkspace in Xcode"
echo "2. In the Project Navigator (left sidebar), right-click on the 'App' folder"
echo "3. Select 'Add Files to \"LifeWrapped\"...'"
echo "4. Navigate to the following folders and add them (check 'Create groups'):"
echo "   - App/Helpers/ (4 files)"
echo "   - App/Components/ (all subdirectories)"
echo "   - App/Views/Tabs/ (4 tab files)"
echo "   - App/Models/ (TimeRange.swift)"
echo ""
echo "5. Make sure 'Add to targets: LifeWrapped' is checked"
echo "6. Click 'Add'"
echo "7. Build the project (Cmd+B)"
echo ""
echo "Files to add:"
find App/Helpers App/Components App/Views/Tabs App/Models -name "*.swift" -type f 2>/dev/null | sort
echo ""
echo "========================================="
