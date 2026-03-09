# 🔧 Fix: "Cannot find 'CourseMapperService' in scope"

## Problem
Xcode cannot find `CourseMapperService` because the file is not included in your app's target.

## Solution (Choose One Method)

### Method 1: Using File Inspector (Recommended)

1. **Open Xcode** with your Caddie project
2. **Select** `CourseMapperService.swift` in the Project Navigator (left sidebar)
   - Path: `ios/Services/CourseMapperService.swift`
3. **Open File Inspector**:
   - Click the right sidebar icon (looks like a document), OR
   - Press `⌥⌘1` (Option + Command + 1), OR
   - Go to: `View` → `Inspectors` → `File`
4. **Find "Target Membership"** section in the File Inspector
5. **Check the box** next to your app target (likely "Caddie")
   - ✅ This tells Xcode to compile this file with your app
6. **Clean Build Folder**: `Product` → `Clean Build Folder` (or `⇧⌘K`)
7. **Build**: `Product` → `Build` (or `⌘B`)

### Method 2: Using Right-Click Menu

1. **Right-click** `CourseMapperService.swift` in Project Navigator
2. Select **"Get Info"** or **"Show File Inspector"**
3. Check the **Target Membership** box for your target
4. Clean and rebuild

### Method 3: Using Build Phases

1. **Select your project** in Project Navigator (top item, blue icon)
2. **Select your target** ("Caddie") under "TARGETS"
3. Click **"Build Phases"** tab
4. Expand **"Compile Sources"**
5. Click **"+"** button
6. Find and add `CourseMapperService.swift`
7. Clean and rebuild

## ✅ Verification

After fixing, you should see:
- ✅ No "Cannot find" errors
- ✅ Both files compile successfully
- ✅ `CourseService.swift` can access `CourseMapperService.shared`

## 📋 Also Check These Files

Make sure these related files are also in your target:
- ✅ `ios/Models/HoleLayout.swift` (contains `HoleLayoutResponse`)
- ✅ `ios/Models/Course.swift` (contains `Course` struct)

If any are missing, add them using the same method above.

## 🐛 Still Not Working?

1. **Quit and reopen Xcode**
2. **Delete Derived Data**:
   - Xcode → Settings → Locations → Derived Data → Delete
3. **Re-add the file** if it was accidentally removed from the project
4. **Check for duplicate files** - make sure there aren't two versions

---

**The file `CourseMapperService.swift` exists and is correct - it just needs to be added to your Xcode target!**



