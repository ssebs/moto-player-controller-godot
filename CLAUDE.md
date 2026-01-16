# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Godot 4.5 motorcycle physics simulation and player controller. Uses GDScript with a component-based architecture where a main `PlayerController` (CharacterBody3D) orchestrates specialized components for physics, gearing, tricks, crash handling, audio, and UI.

## Architecture

### Component System

See [scenes/bike/README.md](scenes/bike/README.md) for detailed bike architecture documentation.

The player controller ([player_controller.gd](scenes/bike/player_controller.gd)) delegates to specialized components in `scenes/bike/components/`.

All components inherit from `BikeComponent` base class ([_bike_component.gd](scenes/bike/components/_bike_component.gd)) which provides:
- `player_controller` reference
- `_bike_setup(p_controller)` - override to receive PlayerController, connect signals
- `_bike_update(delta)` - override for per-frame logic
- `_bike_reset()` - override for respawn reset
- `_on_player_state_changed(old_state, new_state)` - override to react to state transitions

| Component | Responsibility |
|-----------|----------------|
| `BikeInput` | Input handling, emits signals for throttle/brake/steer/lean/clutch/gear changes |
| `BikeState` | Player state machine, shared physics/trick state storage |
| `BikePhysics` | Speed, acceleration, braking, steering, lean angles, ground alignment |
| `BikeGearing` | 6-speed transmission, RPM, clutch with rev-matching, gear shifting |
| `BikeTricks` | Wheelies, stoppies, fishtail physics, trick scoring, combo system, boost |
| `BikeCrash` | Crash detection thresholds, crash physics, respawn timer |
| `BikeAnimation` | Mesh rotation, lean animation, brake lights, training wheels |
| `BikeAudio` | Engine pitch scaling, tire screech, gear grinding, exhaust pops |
| `BikeUI` | HUD elements, trick feed, controller vibration feedback |
| `BikeCamera` | Camera follow behavior |

### BikeState

Centralized state management ([bike_state.gd](scenes/bike/components/bike_state.gd)) containing:

**Player State Machine:**
```
IDLE          - Stationary, no throttle
RIDING        - On ground, moving normally
AIRBORNE      - In air, no trick active
TRICK_AIR     - In air with pitch control
TRICK_GROUND  - Wheelie/stoppie/fishtail on ground
CRASHING      - Crash in progress
CRASHED       - Waiting for respawn
```

State changes via `state.request_state_change(new_state)` which validates against allowed transitions and emits `state_changed(old, new)`.

**Shared State Variables:**
- Physics: `speed`, `lean_angle`, `pitch_angle`, `fishtail_angle`, `ground_pitch`, `grip_usage`
- Gearing: `current_gear`, `current_rpm`, `clutch_value`, `rpm_ratio`, `is_stalled`
- Tricks: `active_trick`, `trick_score`, `total_score`, `combo_multiplier`, `combo_count`
- Boost: `is_boosting`, `boost_count`

**Difficulty Modes:**
- `EASY` - Automatic transmission, auto-clutch
- `MEDIUM` - Semi-auto (no clutch needed for shifts)
- `HARD` - Full manual (clutch required)

### Communication Pattern

Components communicate via Godot signals. Signal connections are made in `_bike_setup()` where each component has access to `player_controller` and can reference sibling components.

**Input signals** (`BikeInput` → all components):
- `throttle_changed`, `front_brake_changed`, `rear_brake_changed`, `steer_changed`, `lean_changed`
- `clutch_held_changed`, `gear_up_pressed`, `gear_down_pressed`
- `difficulty_toggled`, `trick_changed`, `bike_switch_pressed`

**Component signals** (connected in `_bike_setup`):
- `bike_crash.crashed` → `bike_audio`, `bike_tricks`, `bike_ui`
- `bike_gearing.gear_changed`, `gear_grind`, `engine_stalled`, `engine_started` → `bike_audio`
- `bike_tricks.trick_started/ended/cancelled` → `bike_audio`, `bike_ui`, `bike_animation`
- `bike_tricks.boost_started/ended` → `bike_audio`, `bike_ui`, `bike_animation`
- `bike_tricks.tire_screech_start/stop` → `bike_audio`

### Input System

`BikeInput` emits signals for all input state changes each physics frame. Components subscribe to these signals in `_bike_setup()` and store input values locally. This decouples components from direct input access.

### Node References

Uses Godot's unique name syntax (`%NodeName`) for reliable node access. Components access shared state through `player_controller.state.*`.

### Component Structure

Each component extends `BikeComponent` and follows this pattern:
1. Component signals (at top)
2. Shared state vars (other component refs as needed)
3. Local vars
4. `_bike_setup(p_controller)` - call `super()`, connect signals
5. Signal handlers
6. `_bike_update(delta)` - state-driven logic via `match player_controller.state.player_state:`
7. `_bike_reset()` - reset to default values for respawn
8. `_on_player_state_changed(old, new)` - react to state transitions

### Update Loop

```gdscript
_physics_process(delta):
    # Early return during crash
    if state.player_state in [CRASHED, CRASHING]:
        bike_crash._bike_update(delta)
        bike_animation._bike_update(delta)
        return

    bike_input._bike_update(delta)      # Process input first
    _update_player_state()              # Auto-detect IDLE/RIDING/AIRBORNE

    # Component updates
    bike_gearing._bike_update(delta)
    bike_physics._bike_update(delta)
    bike_tricks._bike_update(delta)
    bike_crash._bike_update(delta)
    bike_audio._bike_update(delta)
    bike_ui._bike_update(delta)
    bike_camera._bike_update(delta)

    bike_physics.apply_movement(delta)
    move_and_slide()

    bike_animation._bike_update(delta)  # Visual updates last
```

## BikeResource

Physics, audio, and gearing values are configured per-bike via [BikeResource](scenes/bike/resources/bike_resource.gd). This enables different bike variants (sport, dirt, pocket bikes) with unique handling characteristics.

Key configurable categories:
- **Visual:** mesh_scene, mesh_scale, mesh_rotation
- **IK Targets:** head, arms, butt, legs positions/rotations
- **Gearing:** gear_ratios, num_gears, RPM ranges, clutch speeds
- **Physics:** max_speed, acceleration, brake_strength, lean angles, turn radius
- **Audio:** engine_sound_stream, pitch ranges

## Trick System

Tricks are managed by `bike_tricks.gd` using enum-based detection and scoring.

**Available Tricks:**
```
NONE, WHEELIE_SITTING, WHEELIE_STANDING, STOPPIE, FISHTAIL, DRIFT, HEEL_CLICKER, BOOST, KICKFLIP
```

**Scoring:**
- Tricks accumulate `points_per_sec * combo_multiplier * delta` while active
- Score banks when trick ends
- Combo: +0.25x per trick (max 4x), 2 second window
- Crash loses current trick score and resets combo

**Boost System:**
- Earned from completing tricks
- Triggered by double-tap trick button
- Auto-shifts to optimal gear during boost

## Clutch System

Button-based input with tap/hold behavior:
- **Tap**: Instantly adds `clutch_tap_amount` to clutch value
- **Hold**: After delay, pulls clutch in at `clutch_engage_speed`
- **Release**: Clutch slowly releases at `clutch_release_speed`

Clutch engagement is linear: `clutch_value` 0→1 maps to disengagement (0 = engaged, 1 = free rev). RPM blends between throttle-driven and wheel-driven based on clutch position.

## Crash Thresholds

- Wheelie crash: 75°
- Stoppie crash: 55°
- Lean crash: 80°
- Stoppie + turning triggers lowside crash
- Collision with layer 2 triggers crash

## Input Actions

Defined in `project.godot`: `throttle_pct`, `brake_front_pct`, `brake_rear`, `steer_left/right`, `lean_forward/back`, `clutch` (button), `gear_up/down`, `trick`, `pause`

## Collision Layers

- Layer 1: Ground/terrain
- Layer 2: Obstacles that trigger crashes on collision

## Mods

External components can extend `BikeComponent` and be auto-setup:
1. Add `add_to_group("Mods", true)` in `_ready()`
2. Override `_bike_setup()`, `_bike_update()`, `_bike_reset()` as needed
3. Use `player_controller._save_mod_targets_to_config()` to persist transforms
4. Load transforms in `_bike_reset()` (see `tail_light_mod` for reference)
