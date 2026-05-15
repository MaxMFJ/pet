# Character OS Final Goal

## First Principle

DesktopPet is not an animation player.

It is a sustainable digital life runtime:

- animation is expression
- JSON is asset transport
- LLM is optional cognition expansion
- state evolution is the real core

The product target is a `Character OS` that can keep a character alive across sessions, inputs, and runtime upgrades.

## North Star

Build a runtime where every pet is an evolving character instance with:

- continuity: the character persists its own state instead of replaying isolated clips
- interpretation: raw user/system events become semantic intent
- affect: intent changes emotional tone and internal tension
- planning: emotion and context drive behavior choice
- embodiment: behavior resolves into animation, physics, audio, and VFX
- extensibility: LLM, OCR, plugins, quests, tools, and world systems plug into stable runtime layers

## Target Architecture

```text
LLM / Tooling / OCR / System Events / User Input
                    |
                    v
               Intent Layer
                    |
                    v
               Emotion Layer
                    |
                    v
              Behavior Planner
                    |
                    v
             Animation Runtime
                    |
                    v
         Spine / Physics / Audio / VFX
```

## Layer Contract

### 1. Intent Layer

Responsibility:

- normalize raw events into semantic intents
- separate input transport from character meaning

Examples:

- `tap.head` -> `social.affection`
- `drag.move.right` -> `locomotion.guided`
- `ocr.deadline_detected` -> `attention.redirect`
- `llm.reply_ready` -> `conversation.respond`

Output:

- intent name
- source
- confidence
- context payload

### 2. Emotion Layer

Responsibility:

- accumulate short-term affect
- translate intent into valence, arousal, and emotional label
- provide a stable tone for downstream planning

Examples:

- calm
- alert
- playful
- focused
- frustrated

Output:

- emotion label
- valence
- arousal
- decay / persistence metadata

### 3. Behavior Planner

Responsibility:

- choose what the character does next
- arbitrate between ambient loops, interaction reactions, tasks, and scripted events
- own behavior transitions, priorities, cooldowns, and interruption rules

Examples:

- idle
- inspect
- greet
- follow
- evade
- celebrate
- think

Output:

- behavior state
- behavior mode
- reason
- desired embodiment state

### 4. Animation Runtime

Responsibility:

- map planned behavior to renderable runtime commands
- coordinate Spine state, sprites, timing, transitions, layering, and callbacks
- remain independent from high-level cognition logic

Output:

- resolved animation state
- playback policy
- runtime events

### 5. Embodiment Layer

Responsibility:

- render and simulate the character
- execute animation, physics, audio, VFX, hit regions, and presence on screen

## Engineering Principles

- Character-first, not asset-first
- State-first, not clip-first
- Layered contracts, not cross-layer shortcuts
- Persist semantic runtime state, not only UI toggles
- Let rendering stay replaceable
- LLM must consume and produce structured runtime signals, never directly drive animation

## Current Gap

Today the project mainly has:

- asset import
- profile loading
- animation preview
- window interaction

Missing core runtime pieces:

- semantic intent model
- emotional state model
- behavior planning state
- persistent character snapshot
- event bridge between interaction runtime and character runtime

## Foundation Phase

Phase objective: make the runtime ready for real evolution before adding more features.

### Must finish

1. Introduce a character runtime snapshot model
2. Introduce a runtime coordinator that owns intent/emotion/behavior/animation state
3. Route pet window interactions back into the runtime coordinator
4. Persist semantic runtime snapshot with each pet record
5. Expose runtime summary in manager/debug UI

### Must not do yet

- deeply integrate LLM decisions into animation playback
- add more asset formats without semantic runtime support
- scatter behavior rules across window/view/render classes

## Milestone Definition

The framework is considered structurally correct when:

- a pet can be restored with semantic runtime state
- a click/drag does not directly mean “play clip”, but “emit intent -> update emotion -> select behavior -> resolve animation”
- animation remains the final expression layer
- future OCR/LLM/tool modules can inject intents without touching rendering code

## Practical Roadmap

1. Build Character Runtime core
2. Move interaction semantics out of window-only logic
3. Persist runtime snapshots
4. Add planner rules and cooldowns
5. Connect OCR / LLM / task systems as intent producers
6. Expand embodiment to physics, audio, VFX, world events
