# Simplify Bike Gearing Design

## Goal

Refactor `bike_gearing.gd` to use a binary clutch (held/released) instead of a gradual 0-1 value. Simplify RPM and power functions with clear doc comments.

## Changes by File

### bike_input.gd

- Rename signal `clutch_held_changed` to `clutch_changed(held: bool, just_pressed: bool)`
- Add `clutch_held: bool` property for direct access

### bike_state.gd

- Remove `clutch_value: float`

### bike_gearing.gd

**Remove:**
- `update_clutch()` - no gradual clutch
- `get_clutch_engagement()` - use `!clutch_held` directly
- `clutch_hold_time` variable
- `clutch_just_pressed` variable

**New exports:**
```gdscript
@export var stall_rpm_threshold: float = 0.1  # RPM ratio below this when releasing clutch = stall
@export var clutch_dump_rpm_threshold: float = 0.7  # RPM ratio needed for clutch dump wheelie
```

**New state:**
```gdscript
var clutch_held: bool = false
var was_clutch_held: bool = false  # For dump detection
```

**Simplified functions:**

```gdscript
## Returns 0-1 representing where RPM sits between idle and max
func get_rpm_ratio() -> float:
    var br := player_controller.bike_resource
    if br.max_rpm <= br.idle_rpm:
        return 0.0
    return (player_controller.state.current_rpm - br.idle_rpm) / (br.max_rpm - br.idle_rpm)


## Returns true if clutch was just dumped with high RPM. Used for wheelie initiation.
func is_clutch_dump() -> bool:
    if not (was_clutch_held and not clutch_held):
        return false
    return get_rpm_ratio() >= clutch_dump_rpm_threshold and player_controller.bike_input.throttle > 0.5


## Checks for stall/restart. Returns true if engine is running.
func _update_engine_state() -> bool:
    var br := player_controller.bike_resource

    if player_controller.state.is_stalled:
        player_controller.state.current_rpm = 0.0
        player_controller.state.rpm_ratio = 0.0

        # Restart: clutch held + throttle
        if clutch_held and player_controller.bike_input.throttle > 0.3:
            player_controller.state.is_stalled = false
            player_controller.state.current_rpm = br.idle_rpm
            engine_started.emit()
        return false

    # Stall check: clutch just released + low RPM + low speed (Easy mode exempt)
    if not player_controller.state.isEasyDifficulty():
        if was_clutch_held and not clutch_held:  # Clutch just released
            if get_rpm_ratio() < stall_rpm_threshold and player_controller.state.speed < 3.0:
                player_controller.state.is_stalled = true
                player_controller.state.current_gear = 1
                engine_stalled.emit()
                return false

    return true


## Updates RPM based on clutch state. Clutch held = free rev, released = wheel-driven.
func _update_rpm(delta: float):
    if player_controller.state.is_stalled:
        player_controller.state.current_rpm = 0.0
        return

    var br := player_controller.bike_resource

    if clutch_held:
        # Free rev - RPM follows throttle directly (fast response)
        var target = lerpf(br.idle_rpm, br.max_rpm, player_controller.bike_input.throttle)
        player_controller.state.current_rpm = lerpf(player_controller.state.current_rpm, target, 12.0 * delta)
    else:
        # Engaged - RPM tied to wheel speed
        var wheel_rpm = (player_controller.state.speed / get_max_speed_for_gear()) * br.max_rpm
        player_controller.state.current_rpm = wheel_rpm

    # Rev limiter
    if player_controller.state.current_rpm >= br.max_rpm - br.redline_threshold:
        player_controller.state.current_rpm = br.max_rpm - br.redline_threshold - br.redline_cut_amount

    player_controller.state.current_rpm = clamp(player_controller.state.current_rpm, br.idle_rpm, br.max_rpm)


## Returns power multiplier for acceleration. Zero if stalled or clutch held.
func get_power_output() -> float:
    if player_controller.state.is_stalled or clutch_held:
        return 0.0

    var rpm_ratio = get_rpm_ratio()
    var power_curve = rpm_ratio * (2.0 - rpm_ratio)  # Peaks ~75% RPM

    var br := player_controller.bike_resource
    var gear_ratio = br.gear_ratios[player_controller.state.current_gear - 1]
    var torque_mult = gear_ratio / br.gear_ratios[br.num_gears - 1]

    return player_controller.bike_input.throttle * power_curve * torque_mult
```

**_bike_update structure:**
```gdscript
func _bike_update(delta):
    match player_controller.state.player_state:
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            if not player_controller.state.is_stalled:
                player_controller.state.is_stalled = true
                engine_stalled.emit()
            player_controller.state.rpm_ratio = 0.0
            return

    if not _update_engine_state():
        return

    _update_rpm(delta)
    player_controller.state.rpm_ratio = get_rpm_ratio()

    if player_controller.state.isEasyDifficulty() or player_controller.state.is_boosting:
        _update_auto_shift()
```

### bike_tricks.gd

- Remove local clutch dump detection (`last_clutch_input` variable)
- Call `player_controller.bike_gearing.is_clutch_dump()` instead

### bike_ui.gd

- Change clutch bar to binary: `1.0 if player_controller.bike_input.clutch_held else 0.0`

## Behavior Summary

| Clutch State | RPM Behavior | Power Output |
|--------------|--------------|--------------|
| Held | Follows throttle (fast free rev) | 0 |
| Released | Tied to wheel speed | f(RPM, gear, throttle) |

**Stall conditions (Medium/Hard only):**
- Clutch released + RPM < 10% + speed < 3

**Restart:**
- Clutch held + throttle > 0.3

**Clutch dump (for wheelies):**
- Was held, now released + RPM > 70% + throttle > 0.5
