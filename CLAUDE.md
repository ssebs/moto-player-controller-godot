# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Godot 4.5 motorcycle physics simulation and player controller. Uses GDScript with a component-based architecture where a main `PlayerController` (CharacterBody3D) orchestrates specialized components for physics, gearing, tricks, crash handling, audio, and UI.

## Architecture

### Component System

See [scenes/bike/README.md](scenes/bike/README.md) for detailed bike architecture documentation.

The player controller ([player_controller.gd](scenes/bike/player_controller.gd)) delegates to specialized components in `scenes/bike/components/`.

All components inherit from `BikeComponent` base class (`_bike_component.gd`) which provides:
- `player_controller` reference
- `_bike_setup(p_controller)` - override to receive PlayerController
- `_bike_update(delta)` - override for per-frame logic
- `_bike_reset()` - override for respawn reset

| Component | Responsibility |
|-----------|----------------|
| `BikeInput` | Input handling, emits signals for throttle/brake/steer/lean/clutch/gear changes |
| `BikePhysics` | Speed, acceleration, braking, steering, lean angles, countersteering/fall physics, gravity |
| `BikeGearing` | 6-speed transmission, RPM, clutch with rev-matching, gear shifting |
| `BikeTricks` | Wheelies, stoppies, fishtail/skid physics, skid mark spawning |
| `BikeCrash` | Crash detection thresholds, respawn timer, collision handling |
| `BikeAnimation` | Mesh rotation, visual feedback for bike state |
| `BikeAudio` | Engine pitch scaling, tire screech, gear grinding sounds |
| `BikeUI` | HUD elements, controller vibration feedback |

### Communication Pattern

Components communicate via Godot signals. The main controller only handles signal routing between components that don't have direct references to each other.

**Input signals** (`BikeInput` → all components):
- `throttle_changed`, `front_brake_changed`, `rear_brake_changed`, `steer_changed`, `lean_changed`
- `clutch_held_changed`, `gear_up_pressed`, `gear_down_pressed`

**Component-to-component signals** (connected in `_bike_setup`):
- `bike_crash.force_stoppie_requested` → `bike_tricks.force_pitch()`

**Signals routed through main controller** (connected in `_ready`):
- `bike_gearing.gear_grind` → `bike_audio.play_gear_grind()`
- `bike_gearing.gear_changed` → `bike_audio.on_gear_changed()`
- `bike_tricks.tire_screech_start/stop` → `bike_audio`
- `bike_crash.crashed` → `player_controller._on_crashed()`

### Input System

`BikeInput` emits signals for all input state changes each physics frame:
- `throttle_changed(value)`, `front_brake_changed(value)`, `rear_brake_changed(value)`
- `steer_changed(value)`, `lean_changed(value)`
- `clutch_held_changed(held, just_pressed)`
- `gear_up_pressed`, `gear_down_pressed`, `difficulty_toggled`

Components subscribe to these signals in their `setup()` function and store input values locally. This decouples components from direct input access.

### Node References

Uses Godot's unique name syntax (`%NodeName`) for reliable node access. Components receive shared state, physics reference, and input signals via `setup()` calls in `_ready()`.

### Component Structure

Each component extends `BikeComponent` and follows this pattern:
1. Component signals (at top)
2. Shared state vars (other component refs as needed)
3. Local vars
4. `_bike_setup(p_controller)` - call `super()`, then setup signal connections
5. Signal handlers
6. `_bike_update(delta)` - called from main `_physics_process()`
7. `_bike_reset()` - reset to default values for respawn

### Event Loop

- `@onready` - Node references using `%NodeName` syntax
- `_ready()` - Call component `_bike_setup()`, connect signals
- `_physics_process(delta)` - Call component `_bike_update(delta)`

Input is handled by `BikeInput` which emits signals; components subscribe and store values locally.

## Key Physics Values

- **BikePhysics:** max_speed=60, acceleration=20, brake_force=25, max_steering=35°, max_lean=45°, gyro_stability_speed=15, fall_acceleration=2.0, countersteer_factor=0.8
- **BikeGearing:** gear_ratios=[2.92, 2.05, 1.6, 1.46, 1.15, 1.0], idle_rpm=1000, max_rpm=9000, stall_rpm=800, throttle_response=3.0, rpm_blend_speed=4.0
- **BikeTricks:** max_wheelie=80°, max_stoppie=50°, wheelie_rpm_range=65%-95%
- **BikeCrash:** wheelie_crash=75°, stoppie_crash=55°, lean_crash=80°

## Clutch System

The clutch uses a button-based input with tap/hold behavior:
- **Tap**: Instantly adds `clutch_tap_amount` (0.35) to clutch value
- **Hold**: After `clutch_hold_delay` (0.05s), pulls clutch in at `clutch_engage_speed` (6.0/s)
- **Release**: Clutch slowly releases at `clutch_release_speed` (2.5/s)

Clutch engagement is linear: `clutch_value` 0→1 maps directly to disengagement (0 = engaged to wheel, 1 = disengaged/free rev). RPM blends smoothly between throttle-driven and wheel-driven based on clutch position, enabling rev-matching for smooth shifts and launches.

## Input Actions

Defined in `project.godot`. Main inputs: `throttle_pct`, `brake_front_pct`, `brake_rear`, `steer_left/right`, `lean_forward/back`, `clutch` (button), `gear_up/down`, `trick`, `pause`

## Collision Layers

- Layer 1: Ground/terrain
- Layer 2: Obstacles that trigger crashes on collision
