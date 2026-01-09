# Brake System Redesign

## Problem
Brakes are too sensitive - easy to crash when braking normally. The current `brake_grab_threshold` (input rate detection) is unintuitive and triggers too easily.

## New Mental Model

### Brake Grab Detection
Track time from brake 0→100%. Quick grab (< threshold) = locked wheel. Progressive = stoppie.

- `brake_grab_time_threshold`: export var, default 0.2s

### Behavior Matrix

| Brake Type | Going Straight | While Turning |
|------------|----------------|---------------|
| Grabbed (quick) | Skid (wheel locks) | Crash |
| Progressive | Stoppie | Safe (unless over lean threshold) |

### Stoppie Speed Scaling
Max stoppie angle scales linearly with speed:
```
effective_max = max_stoppie_angle * clamp(speed / stoppie_reference_speed, 0, 1)
```
- `stoppie_reference_speed`: export var, default 35.0

### Brake vs Lean Threshold
More lean = less brake allowed before crash:
```
max_safe_brake = 1.0 - (lean_ratio * brake_lean_sensitivity)
```
- `brake_lean_sensitivity`: export var, default 0.7

## Implementation

### Changes to bike_tricks.gd

1. **Replace GRIP_TUNING const** with simple export vars:
   - Remove `brake_grab_threshold`, `grip_crash_threshold`, `grip_buildup_speed`, `grip_decay_speed`
   - Add `brake_grab_time_threshold`, `stoppie_reference_speed`, `brake_lean_sensitivity`

2. **Replace grip state vars** (lines 139-141):
   - Remove `last_front_brake`, `front_brake_hold_time`
   - Add `brake_grab_timer: float` (tracks time since brake started increasing)
   - Add `brake_was_zero: bool` (tracks if brake was released)

3. **Simplify `_update_grip_usage()`**:
   - Track brake input timing (0→full)
   - Determine grabbed vs progressive
   - Apply behavior matrix

4. **Simplify `is_front_wheel_locked()`**:
   - Return true if brake was grabbed (time < threshold)

5. **Update `_update_stoppie()`**:
   - Scale `max_stoppie_angle` by `speed / stoppie_reference_speed`

### Code Removal
- Remove `GRIP_TUNING` dict entirely
- Remove `brake_grab_level` from state (unused after refactor)
- Simplify crash logic in `_update_grip_usage()`

## Export Vars (for easy tuning)
```gdscript
@export var brake_grab_time_threshold: float = 0.2  # seconds, 0→100%
@export var stoppie_reference_speed: float = 35.0   # full stoppie available at this speed
@export var brake_lean_sensitivity: float = 0.7     # how much lean reduces safe brake amount
```
