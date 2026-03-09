# Code Usage Analysis

## ⚠️ Important: I Cannot Determine 100% Certainty

Without runtime data (code coverage, execution logs, debugging traces), I cannot determine with 100% certainty which code executed during your simulations. However, I can identify:

1. **Definitely Used** - Code that's directly wired into the active navigation
2. **Definitely NOT in Navigation** - Code not referenced in TabView
3. **Potentially Used** - Code that might be accessed via navigation links or conditional flows

## Current Navigation Structure (ContentView.swift)

The app uses a 3-tab TabView:
- Tab 0: `CaddieHomeView()` - ACTIVE
- Tab 1: `HistoryView()` - ACTIVE  
- Tab 2: `ProfileView()` - ACTIVE

## Files NOT Directly in TabView

These files exist but are NOT directly in the TabView:
- `HomeView.swift` - NOT in TabView
- `PlayView.swift` - NOT in TabView
- `StatsView.swift` - NOT in TabView

These MAY still be used if:
- Accessed via NavigationLink from within active views
- Used in previews or testing
- Referenced conditionally

## To Get 100% Certainty

Use Xcode's Code Coverage:
1. Edit Scheme → Test → Options → Code Coverage (Enable)
2. Run app and navigate through all features
3. View Coverage Report: Editor → Code Coverage
4. See exactly which lines executed

Or add logging:
- Add print/log statements at view init
- Check console output during simulation
- Track which views were instantiated

