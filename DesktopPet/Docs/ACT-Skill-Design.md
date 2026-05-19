# DesktopPet ACT / Skill Design

## Goal

Build an ACT-style combat core for desktop pets that supports:

- movement and jump
- primary / secondary attacks
- skill and ultimate casting
- pixel-level hit confirmation
- hit reactions such as hit stun, launch, air suspend, knockdown
- multi-phase skills such as launch, hold, return, and delayed follow-up
- data-driven skill authoring through JSON

This document is the stable design anchor for combat progress.

## Current Status

### Done

- movement component and movement system
- jump state stabilization
- pixel-level pet-vs-pet collision snapshot
- ACT core skeleton:
  - `PETAttackDefinition`
  - `PETCombatStateComponent`
  - `PETHitResult`
  - `PETHitResolver`
- game engine integration for combat tick and hit resolution
- skill runtime classes:
  - `PETSkillDefinition`
  - `PETSkillPhase`
  - `PETActiveSkillInstance`
  - `PETSkillLibrary`
- `skills.json` loader wired into `PETGameEngine`
- skill hit windows resolved by the same pixel collision pipeline
- manager panel combat debug + collision debug snapshot
- skill `onHit` phase transition runtime path
- keyboard combat trigger path for `j / k / l / u / i / o`
- skill phase change presentation bridge and cancel-end presentation recovery

### In Progress

- reaction effect execution beyond hit result generation
- richer skill panel controls in manager UI
- projectile placeholder support

### Not Started

- reaction-driven animation mapping
- combo chain system
- damage / hp / poise model
- editor or in-app skill inspection UI
- projectile runtime

## Design Principles

1. Keep combat runtime deterministic and data-driven.
2. Keep JSON declarative, not script-like.
3. Separate attack definition from skill orchestration.
4. Separate hit confirmation from hit reaction.
5. Allow simple attacks to be represented as small skills.
6. Reuse the same runtime path for:
   - primary attacks
   - skills
   - ultimates
   - projectile-based follow-up hits

## Layer Model

### Layer 1: ACT Core

This is the lowest combat layer.

Main responsibilities:

- receive combat commands
- maintain combat state
- maintain active attack windows
- resolve hits through pixel collision callbacks
- emit hit and state-change events

Core types:

- `PETAttackDefinition`
- `PETCombatStateComponent`
- `PETHitResult`
- `PETHitResolver`

### Layer 2: Skill Runtime

This layer orchestrates multi-phase skills.

Main responsibilities:

- load skill definitions
- advance active skill instances
- switch phases
- open and close hit windows
- spawn projectiles or delayed effects
- apply reactions to targets

Core planned types:

- `PETSkillDefinition`
- `PETSkillPhase`
- `PETSkillHitWindow`
- `PETSkillEffectDefinition`
- `PETSkillReactionDefinition`
- `PETActiveSkillInstance`
- `PETSkillLibrary`

### Layer 3: Presentation / Debug

Main responsibilities:

- display current combat state
- display active skill instance state
- display latest hit result
- display pixel collision point
- map combat state to animation state
- expose active hit window ids, hit target trace, and collision metadata in manager UI

## Runtime Flow

### Basic Flow

1. Input submits a command:
   - `attack.primary`
   - `attack.secondary`
   - `skill.cast`
   - `ultimate.cast`
2. Session creates an attack or skill instance.
3. Game engine ticks all sessions.
4. Active hit windows are evaluated.
5. Pixel collision evaluator returns overlap snapshot.
6. Hit resolver builds `PETHitResult`.
7. Target combat state is updated:
   - hit stun
   - launched
   - knocked down
8. Events are emitted for debug and presentation.

### Multi-Phase Skill Flow

1. Start skill instance.
2. Enter phase A.
3. At phase timing, activate hit window.
4. On hit, apply reaction and optional transition.
5. Enter hold or follow-up phase.
6. Spawn projectile or delayed return phase.
7. Re-check hit on return.
8. End skill and release state lock.

## ACT Core Data Model

### Combat State

`PETCombatStateComponent`

States:

- `combat.idle`
- `combat.attacking`
- `combat.hitstun`
- `combat.launched`
- `combat.knockeddown`

Future states:

- `combat.air_suspend`
- `combat.guard`
- `combat.invulnerable`
- `combat.wakeup`

### Attack Definition

`PETAttackDefinition` is a lightweight runtime object used by the current combat core.

Fields:

- `attackIdentifier`
- `sourcePetIdentifier`
- `attackKind`
- `skillIdentifier`
- `startupDuration`
- `activeDuration`
- `recoveryDuration`
- `hitStunDuration`
- `knockdownDuration`
- `launchVector`
- `causesKnockdown`
- `sampleSpacing`
- `maxHitCountPerTarget`

This should remain small. Complex multi-stage behavior moves to skill runtime.

### Hit Result

`PETHitResult`

Fields:

- `hitIdentifier`
- `sourcePetIdentifier`
- `targetPetIdentifier`
- `attackIdentifier`
- `attackKind`
- `hitStunDuration`
- `knockdownDuration`
- `launchVector`
- `causesKnockdown`
- `collisionSnapshot`

## Skill Runtime Data Model

## Skill Definition

Represents the whole skill.

Suggested fields:

- `skillId`
- `displayName`
- `castType`
- `entryPhase`
- `tags`
- `phases`

## Skill Phase

Represents a stage in a skill sequence.

Suggested fields:

- `phaseId`
- `startTime`
- `duration`
- `animationState`
- `movementLock`
- `casterMotion`
- `gravityScale`
- `hitWindows`
- `effects`
- `transitions`

`casterMotion` is optional root-motion data for the caster. Current runtime supports:

- `startTime`
- `endTime`
- `dx`
- `dy`
- `relativeToFacing`

## Skill Hit Window

Represents a window that can hit targets.

Suggested fields:

- `windowId`
- `startTime`
- `endTime`
- `collisionMode`
- `sampleSpacing`
- `maxHitsPerTarget`
- `rehitInterval`
- `reactionId`
- `targetFilter`

Notes:

- `maxHitsPerTarget` is now enforced per target, per phase-window.
- `rehitInterval` is optional. When omitted and `maxHitsPerTarget > 1`, runtime derives a default cadence from the window duration.

Collision modes v1:

- `pixelOverlap`
- `projectilePath`
- `area`

## Skill Effect Definition

Represents side effects that happen during a phase.

Effect types planned for v1:

- `applyReaction`
- `launchTarget`
- `airSuspendTarget`
- `knockdownTarget`
- `spawnProjectile`
- `returnProjectile`
- `dealDamage`
- `emitDebugMarker`

## Skill Reaction Definition

Represents how a target behaves after being hit.

Fields:

- `reactionId`
- `combatState`
- `animationState`
- `duration`
- `gravityScale`
- `lockHorizontal`
- `lockVertical`
- `knockdown`

## Active Skill Instance

Runtime object that tracks one cast of one skill.

Suggested fields:

- `instanceId`
- `skillId`
- `casterPetIdentifier`
- `currentPhaseId`
- `elapsedTime`
- `phaseElapsedTime`
- `phaseStartTimestamp`
- `hitTargetHistory`
- `spawnedProjectileIds`
- `waitingConditions`
- `finished`

## JSON Strategy

Use JSON as a data table, not as a scripting language.

### Do

- fixed field names
- fixed effect types
- fixed transition types
- explicit timing
- explicit identifiers

### Do Not

- arbitrary code in JSON
- nested expression language
- free-form condition syntax in v1
- custom callback names embedded everywhere

## Runtime Progress Snapshot

### Completed in repo

1. ACT core can tick sessions, resolve attack hits, and apply combat state changes.
2. Skill table loads from `Resources/Skills/skills.json`.
3. `PETGameSession` can create `PETActiveSkillInstance` from `skill.cast`.
4. Skill hit windows participate in the same pixel collision path as primary / secondary attacks.
5. `onHit` phase transition now works for multi-phase skills such as `spear_sky_pierce`.
6. Manager panel can inspect:
   - combat state
   - current action
   - active skill id and phase id
   - phase animation state
   - active hit window ids
   - latest collision point / attack id / timestamp
7. Keyboard combat bindings now route:
   - `j`: primary skill-style strike
   - `k`: secondary attack
   - `l`: skill cast
   - `u`: ultimate cast
   - `i`: quick strike
   - `o`: cancel
8. Presentation bridge now updates combat animation on:
   - attack start
   - skill phase change
   - attack / skill end

### Recommended Next Step

1. Start executing phase `effects` with a narrow v1 list:
   - `emitDebugMarker`
   - `launchTarget`
   - `airSuspendTarget`
   - `knockdownTarget`
2. Add manager debug controls for manual skill / ultimate cast and cancel per pet.
3. Finish reaction-driven animation mapping so reaction definitions can actively drive presentation instead of only contributing hit-state data.

## JSON v1 Scope

The first version of `skills.json` should support:

- skill metadata
- phases
- hit windows
- effects
- transitions
- reactions

Transition types for v1:

- `onTimer`
- `onHit`
- `onPhaseComplete`
- `onProjectileReturn`

## Example Skill: Spear Sky Pierce

Design target:

1. caster thrusts spear upward
2. enemy hit in air gets launched
3. enemy enters air suspend
4. spear pauses / waits
5. spear returns downward or backward
6. enemy can be hit again by return path
7. second hit can knock down

Phase suggestion:

1. `cast`
2. `launch_hit`
3. `air_hold`
4. `return_hit`
5. `recovery`

## Implementation Roadmap

### Phase A

- [x] ACT core skeleton
- [x] pixel collision callback into engine
- [x] combat debug snapshot exposure in manager UI

### Phase B

- [x] `PETSkillDefinition`
- [x] `PETSkillPhase`
- [ ] `PETSkillReactionDefinition`
- [x] `PETActiveSkillInstance`
- [x] skill library JSON loader

### Phase C

- [x] first sample skill from JSON
- [x] runtime phase transitions
- [ ] reaction application from skill data
- [ ] projectile placeholder support

### Phase D

- [ ] combat test panel
- [x] in-panel phase and hit inspection
- [ ] animation mapping for launched / knocked down

## Progress Notes

When adding new work, update:

- this checklist
- `Resources/Skills/skills.json`
- runtime classes that own the feature

That keeps memory in the repo instead of only in chat.
