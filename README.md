# DesktopPet

Objective-C macOS desktop pet scaffold evolving toward a Character OS:

- import a `.webp`
- decode static or animated frames with `ImageIO`
- spawn one draggable transparent pet window on the desktop
- keep architecture ready for semantic character runtime, OCR, AI routing, and future gameplay modules

Current platform status:

- macOS app target: supported now
- iOS deployment target preset: `16.0`
- iPhone/iPad runtime target: not added yet, because the current windowing layer still depends on `AppKit`

## Project structure

- `DesktopPet/App`: app lifecycle and menu entry
- `DesktopPet/Config`: persisted app settings
- `DesktopPet/Managers`: import flow and multi-pet lifecycle
- `DesktopPet/Models`: pet profile and animation frame models
- `DesktopPet/Services`: WEBP decoder, OCR placeholder, AI placeholder
- `DesktopPet/UI`: pet window and animated pet view
- `DesktopPet/Resources`: `Info.plist`

## Current milestone

1. Open `DesktopPet.xcworkspace` after `pod install`, or open `DesktopPet.xcodeproj` if you are not using CocoaPods yet
2. Build and run the `DesktopPet` target
3. The app opens a manager window by default
4. Configure `BaseURL`, add one or more `.webp` pets, and toggle pet visibility
5. Imported pets appear as borderless draggable desktop windows

## Architecture notes for the next phase

- `PETWebPDecoder`: can be swapped to `libwebp` later if you need more predictable animated WEBP support across macOS versions
- `PETOCRService`: intended for `ScreenCaptureKit + Vision`
- `PETAIService`: intended for configurable provider routing via Base URL and API key storage
- `PETPetManager`: centralizes multi-pet lifecycle and now hosts per-pet semantic runtime snapshots
- `PETCharacterRuntimeController`: bridges intent, emotion, behavior, and resolved animation state
- `PETPetWindow`: remains embodiment/input runtime, but now emits structured runtime events instead of being the only place where reactions live

## Suggested next implementation steps

1. Add a settings window for AI Base URL, API key, OCR switch, and pet limits
2. Replace placeholder OCR with real desktop capture and text recognition
3. Introduce action/state machines for idle, walk, follow, talk, and event reactions
4. Add plugin-style interaction modules so gameplay extensions are isolated from the base app
