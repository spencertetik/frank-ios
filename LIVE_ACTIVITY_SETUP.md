# Frank Live Activity Widget Extension Setup

## Overview
The Live Activity Widget Extension files have been created, but you need to manually add the Widget Extension target in Xcode since the pbxproj modifications would be complex for the FileSystemSynchronizedRootGroup setup.

## Files Created
- **`FrankLiveActivityAttributes.swift`** - Shared ActivityAttributes accessible to both main app and widget
- **`FrankLiveActivityWidget.swift`** - Widget implementation with lock screen and Dynamic Island views
- **`FrankLiveActivity-Info.plist`** - Info.plist for the widget extension

## Manual Xcode Setup Required

### Step 1: Create Widget Extension Target
1. In Xcode, go to **File → New → Target...**
2. Choose **iOS → Widget Extension**
3. Set the following:
   - **Product Name:** `FrankLiveActivity`
   - **Bundle Identifier:** `com.yourteam.Frank.FrankLiveActivity` (replace yourteam)
   - **Language:** Swift
   - **Use Core Data:** No
   - **Include Configuration Intent:** No

### Step 2: Replace Default Files
1. Delete the default widget files created by Xcode template
2. Copy these files into the new `FrankLiveActivity` target:
   - **`FrankLiveActivityWidget.swift`**
   - **`FrankLiveActivity-Info.plist`** (replace the default Info.plist)

### Step 3: Add Shared File to Both Targets
1. Select **`FrankLiveActivityAttributes.swift`** in the file navigator
2. In the **File Inspector** (right panel), under **Target Membership**, ensure both:
   - ✅ **Frank** (main app)
   - ✅ **FrankLiveActivity** (widget extension)

### Step 4: Configure Widget Target Settings
1. Select the **FrankLiveActivity** target in project settings
2. **General Tab:**
   - Set **Deployment Target** to iOS 16.1+ (minimum for Live Activities)
   - Set **Bundle Identifier** to match your app + `.FrankLiveActivity`
3. **Build Settings Tab:**
   - Set **Swift Language Version** to Swift 5
   - Set **Code Signing** to match your main app

### Step 5: Add Required Frameworks
In the **FrankLiveActivity** target, go to **General → Frameworks and Libraries** and add:
- **WidgetKit.framework**
- **SwiftUI.framework**
- **ActivityKit.framework**

### Step 6: Enable Live Activities in Main App
1. Select the **Frank** main app target
2. **Info Tab** → Add new key:
   - **Key:** `NSSupportsLiveActivities`
   - **Type:** Boolean
   - **Value:** YES

### Step 7: Test
1. Build and run the app on a physical device (Live Activities don't work in Simulator)
2. Connect to the gateway - a Live Activity should appear
3. Check Lock Screen and Dynamic Island for Frank's status

## Features Included

### Lock Screen View
- Frank's connection status with indicator
- Current task display
- Model name, sub-agent count, and uptime
- Orange theme matching the main app

### Dynamic Island
- **Compact Leading:** 🦞 emoji + connection dot
- **Compact Trailing:** Current task snippet
- **Expanded:** Full status with model, task, sub-agents, uptime
- **Minimal:** Just the 🦞 emoji

### Auto-Management
The `GatewayClient` automatically:
- Starts Live Activity on connection
- Updates Activity when session state changes
- Ends Activity on disconnection
- Provides haptic feedback for connection events

## Troubleshooting

### Live Activity Not Appearing
1. Ensure you're testing on a physical device
2. Check Settings → Frank → Live Activities is enabled
3. Verify the widget extension builds successfully
4. Check device console for any error messages

### Build Errors
1. Ensure `FrankLiveActivityAttributes.swift` is added to both targets
2. Check all framework dependencies are properly linked
3. Verify bundle identifiers are correctly set

### Dynamic Island Not Working
- Dynamic Island only works on iPhone 14 Pro and newer
- Lock Screen view should still work on all devices with Live Activities support

## Future Enhancements
Consider adding:
- Push notifications to update Live Activities remotely
- Interactive elements in the Lock Screen view
- Multiple activity types for different Frank states
- Rich media content in expanded Dynamic Island view