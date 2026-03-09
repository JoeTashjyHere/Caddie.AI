# Fix: "Cannot find 'CourseMapperService' in scope"

## Quick Fix Steps

1. **Open Xcode**
2. **In Project Navigator**, find `CourseMapperService.swift` under `ios/Services/`
3. **Select the file** (click on it once)
4. **Open File Inspector** (right sidebar, or View → Inspectors → File)
5. **Under "Target Membership"**, ensure your app target (likely "Caddie") is **checked**
6. **Clean Build Folder**: Product → Clean Build Folder (⇧⌘K)
7. **Rebuild**: Product → Build (⌘B)

## Alternative Method

1. Select `CourseMapperService.swift` in Project Navigator
2. Right-click → "Get Info"
3. Check the box next to your target under "Target Membership"
4. Build again

## If Still Not Working

The file must be included in the same target as `CourseService.swift`. Both files should show up in:
- Project Navigator under your target's "Compile Sources"
- File Inspector showing the same target checked


