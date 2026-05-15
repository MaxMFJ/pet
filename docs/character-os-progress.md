# Character OS Progress

## Current Status

Project phase: `Cross-Platform Shell Bring-up`

Architecture maturity:

- Intent Layer: functional and config-driven
- Emotion Layer: functional and config-driven
- Behavior Planner: functional and config-driven
- Animation Runtime: functional, partially decoupled from semantic decisions
- Embodiment Layer: functional on macOS, functional shell on iOS

Overall assessment:

- the project has crossed from "animation player scaffold" into "early Character OS runtime"
- the semantic pipeline now exists end to end
- persistence exists for semantic snapshot state
- short-lived goal persistence now exists above the planner
- first task stack foundation now exists above goals
- first memory timeline foundation now exists above tasks
- first OCR-to-intent perception bridge now exists
- first structured cognition protocol layer now exists
- iOS now runs the same semantic runtime shell, with remaining work mostly around richer planning, world input, and provider transport

## Completed

### 1. Final goal and architecture definition

Done:

- Character OS north star documented
- layered target architecture documented
- foundation phase milestones documented

Reference:

- [character-os-final-goal.md](/Users/lzz/Desktop/桌面天堂/docs/character-os-final-goal.md:1)

### 2. Character runtime snapshot

Done:

- semantic runtime snapshot model introduced
- snapshot serialization and restore implemented
- per-pet snapshot persistence wired into app session restore

Key files:

- [PETCharacterSnapshot.h](/Users/lzz/Desktop/桌面天堂/DesktopPet/Models/PETCharacterSnapshot.h:1)
- [PETAppDelegate.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/App/PETAppDelegate.m:118)

### 3. Runtime event bridge

Done:

- pet window emits structured runtime events
- manager/runtime layer listens and translates those events into semantic state updates

Key files:

- [PETPetWindow.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/UI/PETPetWindow.m:20)
- [PETPetManager.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Managers/PETPetManager.m:245)

### 4. Intent / Emotion / Behavior separation

Done:

- `PETCharacterRuntimeController` reduced to orchestration
- separate `IntentEngine`, `EmotionEngine`, `BehaviorPlanner` introduced
- layer data objects introduced for intent, emotion, and behavior decision

Key files:

- [PETCharacterRuntimeController.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETCharacterRuntimeController.m:1)
- [PETCharacterIntent.h](/Users/lzz/Desktop/桌面天堂/DesktopPet/Models/PETCharacterIntent.h:1)
- [PETCharacterEmotion.h](/Users/lzz/Desktop/桌面天堂/DesktopPet/Models/PETCharacterEmotion.h:1)
- [PETBehaviorDecision.h](/Users/lzz/Desktop/桌面天堂/DesktopPet/Models/PETBehaviorDecision.h:1)

### 5. Data-driven semantics

Done:

- intent rules externalized into config mapping
- emotion rules externalized into config mapping
- behavior rules externalized into config mapping
- semantic config loader reads rules from bundle resource

Key files:

- [PETCharacterSemanticConfig.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETCharacterSemanticConfig.m:1)
- [PETCharacterSemanticMappings.plist](/Users/lzz/Desktop/桌面天堂/DesktopPet/Resources/PETCharacterSemanticMappings.plist:1)

### 6. Runtime visibility in UI

Done:

- manager panel shows semantic runtime summary for selected pet

Key file:

- [PETManagerViewController.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/UI/PETManagerViewController.m:300)

### 7. Goal layer foundation

Done:

- short-lived goal model introduced
- goal engine derives or refreshes active goals from incoming intents
- active goal persists in semantic snapshot context
- planner can bias behavior selection toward an active goal

Key files:

- [PETCharacterGoal.h](/Users/lzz/Desktop/桌面天堂/DesktopPet/Models/PETCharacterGoal.h:1)
- [PETGoalEngine.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETGoalEngine.m:1)
- [PETCharacterRuntimeController.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETCharacterRuntimeController.m:1)

### 8. Task stack foundation

Done:

- task model introduced
- task engine persists and refreshes task stack from runtime events
- active task can outlive a single goal refresh
- active goal can now be projected from active task state
- runtime summary now surfaces task progress

Key files:

- [PETCharacterTask.h](/Users/lzz/Desktop/桌面天堂/DesktopPet/Models/PETCharacterTask.h:1)
- [PETTaskEngine.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETTaskEngine.m:1)
- [PETGoalEngine.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETGoalEngine.m:1)
- [PETCharacterRuntimeController.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETCharacterRuntimeController.m:1)

### 9. Memory timeline foundation

Done:

- memory event model introduced
- runtime writes a rolling memory timeline into snapshot context
- interaction and task lifecycle events become memory entries
- latest memory state is surfaced in runtime summary

Key files:

- [PETCharacterMemoryEvent.h](/Users/lzz/Desktop/桌面天堂/DesktopPet/Models/PETCharacterMemoryEvent.h:1)
- [PETMemoryEngine.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETMemoryEngine.m:1)
- [PETCharacterRuntimeController.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETCharacterRuntimeController.m:1)

### 10. OCR perception bridge

Done:

- desktop OCR service now performs real capture + Vision text recognition
- manager polls OCR and turns recognized text into structured runtime context
- OCR enters the system only through `recordActionKey` / `IntentEngine`
- OCR-driven intents now participate in the same goal, task, memory, and behavior pipeline

Key files:

- [PETOCRService.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETOCRService.m:1)
- [PETPetManager.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Managers/PETPetManager.m:1)
- [PETCharacterSemanticMappings.plist](/Users/lzz/Desktop/桌面天堂/DesktopPet/Resources/PETCharacterSemanticMappings.plist:1)

### 11. Structured cognition protocol layer

Done:

- structured cognition suggestion model introduced
- cognition engine now defines a strict JSON protocol contract
- runtime only accepts cognition via `actionKey + context`
- cognition suggestions are constrained to the `cognition.*` namespace
- manager can poll cognition and feed it back through the semantic runtime

Key files:

- [PETStructuredCognitionSuggestion.h](/Users/lzz/Desktop/桌面天堂/DesktopPet/Models/PETStructuredCognitionSuggestion.h:1)
- [PETStructuredCognitionEngine.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETStructuredCognitionEngine.m:1)
- [PETCharacterRuntimeController.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETCharacterRuntimeController.m:1)
- [PETPetManager.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Managers/PETPetManager.m:1)

### 12. iOS Character OS shell

Done:

- iOS target now compiles the same semantic runtime core used by macOS
- iOS shell now owns a real `PETCharacterRuntimeController` per loaded pet
- touch gestures now enter the runtime as structured tap / drag intent events
- runtime snapshot, scale, and stage offset now persist per pet package on iOS
- iOS shell now uses a landscape-first stage with a collapsible sidebar settings panel
- structured cognition on iOS is gated through the same protocol layer rather than direct animation control

Key files:

- [PETIOSViewController.m](/Users/lzz/Desktop/桌面天堂/DesktopPetiOS/UI/PETIOSViewController.m:1)
- [PETIOSAnimatedPetView.m](/Users/lzz/Desktop/桌面天堂/DesktopPetiOS/UI/PETIOSAnimatedPetView.m:1)
- [PETCharacterRuntimeController.m](/Users/lzz/Desktop/桌面天堂/DesktopPet/Services/PETCharacterRuntimeController.m:1)
- [DesktopPet.xcodeproj/project.pbxproj](/Users/lzz/Desktop/桌面天堂/DesktopPet.xcodeproj/project.pbxproj:1)

## In Progress

### 1. Behavior planner depth

Current:

- planner handles priorities, cooldowns, interruption classes, and yield rules
- planner now supports behavior categories plus both blocking and polite yielding
- planner now consumes short-lived goals
- planner now receives active task-backed goals
- planner now manages task-backed continuation
- planner still does not manage world-state-driven plans or durable self-directed loops

Needed next:

- task stack / long-lived goal continuation
- multi-step plan transitions
- world-state-driven arbitration
- richer OCR / perception selectors

### 2. Semantic config richness

Current:

- config supports exact and prefix matching
- config supports default fallback

Needed next:

- richer selectors
- per-profile overrides
- weighted rules
- time/context conditions

## Not Started

### 1. OCR as real intent producer

Missing:

- richer desktop perception coverage
- OCR permission / scheduling UX
- perception salience and dedup heuristics

### 2. LLM as structured cognition producer

Missing:

- provider transport beyond scaffolded AI service
- cognition enablement / API credential UX
- richer cognition-to-task planning semantics

### 3. World / task / memory systems

Missing:

- rich task lifecycle
- durable memory semantics
- relationship state
- long-lived goal persistence

### 4. iOS Character OS shell

Missing:

- higher-fidelity stage embodiment such as richer spatial controls, app lifecycle hooks, and perception adapters
- iOS-side shell parity for multi-pet management and deeper shell settings

## Milestone Check

### Foundation milestone

Target:

- `input -> intent -> emotion -> behavior -> animation`

Status:

- `completed on macOS foundation path`

### Cross-platform runtime milestone

Target:

- same semantic core reused by macOS and iOS shells

Status:

- `not complete`

### Cognition integration milestone

Target:

- OCR / LLM / tools inject structured intents without bypassing runtime layers

Status:

- `not complete`

## Suggested Next Step

Best next move:

1. add semantic conditions to rule config
2. extend OCR into richer perception conditions and app-aware signals
3. add structured cognition on top of the new perception/task/memory core

That would move the project from "layered foundation exists" to "character behavior can evolve over time without becoming chaotic."
