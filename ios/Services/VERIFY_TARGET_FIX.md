# Fix: "Cannot find 'CourseMapperService' in scope"

## Quick Fix (Most Common Solution)

This error occurs because `CourseMapperService.swift` is not included in your Xcode target.

### Steps to Fix:

1. **In Xcode Project Navigator**, select `CourseMapperService.swift`
2. **Open File Inspector** (right sidebar, or press `⌥⌘1`)
3. **Under "Target Membership"**, check the box next to **"Caddie"** (your app target)
4. **Clean Build Folder**: `Product` → `Clean Build Folder` (⇧⌘K)
5. **Rebuild**: `Product` → `Build` (⌘B)

### Alternative Method:

1. Right-click `CourseMapperService.swift` → `Get Info`
2. Check the "Target Membership" box for your target
3. Clean and rebuild

## Verification:

After fixing, verify:
- Both `CourseService.swift` AND `CourseMapperService.swift` show the same target checked
- Build succeeds without "Cannot find" errors
- The file appears in your target's "Compile Sources" build phase

## If Still Not Working:

Check that `HoleLayoutResponse` (from `ios/Models/HoleLayout.swift`) is also in the target, as `CourseMapperService` depends on it.
