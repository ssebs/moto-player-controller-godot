# Grip Threshold System Design

## Overview

Replace the confusing "brake danger" system with a clearer "grip threshold" concept. Front tire grip is a finite resource consumed by braking and turning. When exceeded, consequences depend on context.

## Mental Model

On a real motorcycle, the front tire has limited grip. Hard braking uses grip. Turning uses grip. Do both at once and you exceed available grip → loss of control.

## Difficulty Behavior

| Difficulty | Grip System |
|------------|-------------|
| **EASY** | Disabled entirely - no grip limit, no forced stoppies, no brake-grab crashes, front wheel never locks |
| **MEDIUM** | Softer thresholds - slower buildup, higher crash thresholds, more forgiving |
| **HARD** | Current behavior - realistic grip limits |

## What Moves to `bike_tricks`

### Functions
- `_update_brake_danger()` → `_update_grip_usage()`
- `_check_force_stoppie()` → stays as helper, called from `_update_grip_usage()`
- `is_front_wheel_locked()` → moves to `bike_tricks`

### State (in BikeState)
- `brake_danger_level` → `grip_usage` (0-1, how much grip is being consumed)
- `brake_grab_level` → stays (threshold for front wheel lock detection)

## What Stays in `bike_crash`

- Crash angle thresholds (wheelie/stoppie/lean)
- `trigger_crash()` - still called by bike_tricks when grip exceeded while turning
- Collision crash detection
- Respawn logic
- Ragdoll handling

## Grip Usage Calculation

```
grip_usage = braking_grip + turning_grip

braking_grip = front_brake_intensity * speed_factor
turning_grip = max(turn_factor, lean_factor)

if grip_usage > 1.0:
    if turning_grip > 0.4:
        → trigger lowside crash (via bike_crash)
    else:
        → force stoppie
```

## Difficulty Tuning Values

### HARD (current behavior)
- `brake_grab_threshold`: 4.0 (rate/sec to count as grab)
- `grip_crash_threshold`: 0.9
- `grip_buildup_speed`: 5.0
- `grip_decay_speed`: 3.0

### MEDIUM (forgiving)
- `brake_grab_threshold`: 6.0 (harder to trigger lock)
- `grip_crash_threshold`: 1.2 (20% more headroom)
- `grip_buildup_speed`: 3.0 (slower buildup)
- `grip_decay_speed`: 5.0 (faster recovery)

### EASY
- All grip logic skipped entirely

## Implementation Steps

1. Add `grip_usage` to `BikeState`, keep `brake_grab_level`
2. Add difficulty tuning constants to `bike_tricks`
3. Move `_update_brake_danger()` to `bike_tricks` as `_update_grip_usage()`
4. Move `_check_force_stoppie()` to `bike_tricks`
5. Move `is_front_wheel_locked()` to `bike_tricks`
6. Add difficulty check - skip grip logic on EASY
7. Apply MEDIUM tuning values when difficulty is MEDIUM
8. Update `bike_crash` to remove moved code, keep crash triggering
9. Update `bike_physics` to get `is_front_wheel_locked()` from `bike_tricks`
10. Remove `brake_danger_level` from `BikeState` (replaced by `grip_usage`)

## Signal Changes

- `force_stoppie_requested` signal stays on `bike_crash` OR moves to `bike_tricks`
  - Recommendation: Move to `bike_tricks` since it now owns the logic
  - `bike_tricks` can call its own `_on_force_stoppie_requested()` directly (no signal needed)

## Files Changed

- `scenes/bike/components/bike_state.gd` - rename state var
- `scenes/bike/components/bike_tricks.gd` - add grip logic
- `scenes/bike/components/bike_crash.gd` - remove moved code
- `scenes/bike/components/bike_physics.gd` - update `is_front_wheel_locked()` reference
