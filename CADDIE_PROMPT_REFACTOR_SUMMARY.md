# Personalized Caddie Prompt Pipeline - Implementation Summary

## Overview
Refactored the AI prompt system to create a personalized, consistent caddie experience with learning capabilities from user history.

## Files Created

### 1. `ios/Services/CaddiePromptBuilder.swift`
- **Purpose**: Centralized prompt builder for all caddie recommendations
- **Key Components**:
  - `CaddieMindset.systemPrompt`: Permanent system prompt that never changes
  - `ShotContextData`: Structured shot context (course, distance, lie, hazards, etc.)
  - `PlayerProfileData`: Player profile with bag contents
  - `RecentTendencies`: Analyzes last 5 recommendations to extract patterns
  - `CaddiePromptBuilder`: Main builder class with methods:
    - `buildShotPrompt()`: Builds prompts for shot recommendations
    - `buildGreenReaderPrompt()`: Builds prompts for putting reads (same mindset, different structure)

## Files Modified

### 2. `ios/Models/ShotRecommendation.swift`
- **Changes**:
  - Added `StructuredShotRecommendation` struct matching new AI output format:
    - `clubRecommendation`
    - `shotPlan`
    - `targetLine`
    - `missToPlayFor`
    - `confidenceNote`
    - `tacticalTips`
  - Updated `ShotRecommendation` to include optional new fields for backward compatibility
  - Added `init(from: StructuredShotRecommendation)` converter

### 3. `ios/Services/RecommenderService.swift`
- **Changes**:
  - Now uses `CaddiePromptBuilder.shared` instead of inline prompt building
  - Added `historyStore` parameter to `getRecommendation()` method
  - Integrated `RecentTendencies` analysis from history
  - Added `parseRecommendation()` method that handles both new structured format and legacy format
  - Removed old `buildPrompts()` method (replaced by CaddiePromptBuilder)

### 4. `ios/ViewModels/CaddieUnifiedViewModel.swift`
- **Changes**:
  - Updated `requestRecommendation()` to pass `historyStore` to recommender
  - Updated `generatePuttingReadViaVision()` to use `CaddiePromptBuilder` for green reader prompts
  - Green reader now uses same caddie mindset but different output structure

## Key Features Implemented

### 1. Permanent Caddie Mindset System Prompt
- **Location**: `CaddiePromptBuilder.swift` → `CaddieMindset.systemPrompt`
- **Content**: Professional caddie persona that thinks in terms of miss patterns, risk vs reward, player tendencies
- **Usage**: Prepended to every shot and green-read request
- **Never changes**: Ensures consistent caddie voice across all recommendations

### 2. Structured Output Format
- **New Format**:
  ```json
  {
    "clubRecommendation": "...",
    "shotPlan": "...",
    "targetLine": "...",
    "missToPlayFor": "...",
    "confidenceNote": "...",
    "tacticalTips": ["...", "..."]
  }
  ```
- **Backward Compatibility**: Still supports legacy format for smooth transition
- **No Markdown**: System prompt explicitly forbids markdown code fences

### 3. History-Based Learning
- **Implementation**: `RecentTendencies` struct analyzes last 5 shot recommendations
- **Patterns Detected**:
  - Common clubs used
  - Shot shape preferences
  - Conservative vs aggressive tendencies
- **Integration**: Automatically included in prompts when `historyStore` is available
- **Example Output**: "Recent Tendencies: Player often uses 7i, prefers fade shots, tends toward conservative targets."

### 4. Comprehensive Context
- **Shot Context Includes**:
  - Course Name (required)
  - City, State (required)
  - Hole Number (optional)
  - Distance to Target
  - Lie
  - Known Hazards
  - Shot Type
  - Photo analysis summary (if available)
- **Player Profile Includes**:
  - Golf Goal
  - Bag contents (club name, distance, shot shape preference, miss tendencies)
- **Environmental Context**:
  - Wind speed/direction
  - Temperature
  - Elevation change
  - Inferred from course location (no GPS dependency)

### 5. Green Reader Alignment
- **Same Mindset**: Uses `CaddieMindset.systemPrompt`
- **Different Structure**: Putting-focused output (breakDirection, breakAmount, speed, narrative, puttingLine)
- **History Integration**: Also uses recent tendencies
- **Separate but Aligned**: Maintains distinct output while sharing caddie expertise

### 6. History Persistence
- **Already Implemented**: `CaddieUnifiedViewModel` saves all recommendations to history
- **Verification**: Both shot and green reader recommendations are saved via:
  - `saveShotRecommendationToHistory()`
  - `savePuttingReadToHistory()`
- **Immediate Updates**: History tab updates immediately after successful recommendations

## Testing Checklist

- [ ] Generate shot recommendation → verify new structured format is parsed correctly
- [ ] Generate shot recommendation → verify recent tendencies are included in prompt
- [ ] Generate green reader → verify same mindset but different structure
- [ ] Check history → verify all recommendations are saved
- [ ] Kill app → relaunch → verify history persists and influences future recommendations
- [ ] Verify backward compatibility with legacy format (if any old data exists)

## Notes

- The system prompt is permanent and never changes between requests
- All prompts now go through `CaddiePromptBuilder` for consistency
- History analysis is optional (gracefully handles nil historyStore)
- New structured format is backward compatible with legacy format
- Green reader maintains separate output structure while sharing caddie mindset
