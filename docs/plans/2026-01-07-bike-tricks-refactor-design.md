# bike_tricks.gd Refactor Design

## Goals

1. Separate wheelie from stoppie logic
2. Simplify complex math/logic and long functions
3. Remove `current_delta` hack
4. Remove duplicate variables and logic
5. Inline small functions that add indirection without clarity

## Key Changes

### 1. Remove `current_delta` Hack

**Problem:** `_on_force_stoppie_requested` is a signal handler that needs delta for `move_toward()`.

**Solution:** Store the request as state, apply in `_bike_update()`:

```gdscript
var _force_stoppie_target: float = 0.0
var _force_stoppie_rate: float = 0.0
var _force_stoppie_active: bool = false

func _on_force_stoppie_requested(target_pitch: float, rate: float):
    _force_stoppie_target = target_pitch
    _force_stoppie_rate = rate
    _force_stoppie_active = true
```

The forced stoppie is then handled inside `_update_stoppie(delta)`.

### 2. Split `handle_wheelie_stoppie()` into Focused Functions

**Current:** 60+ line function mixing airborne pitch, clutch dump, wheelie logic, stoppie logic, and tire screech signals.

**New structure:**

- `_update_wheelie(delta)` (~30 lines): Clutch dump detection, RPM-based power, pitch application, state transitions
- `_update_stoppie(delta)` (~30 lines): Brake-based stoppie, forced stoppie, tire screech, state transitions
- `_update_airborne_pitch(delta)` (~8 lines): Simple lean input to pitch angle

### 3. State-Driven Trick Management

Use `PlayerState.TRICK_GROUND` as source of truth instead of checking `pitch_angle` thresholds everywhere.

**State transitions managed by bike_tricks:**
- Enter `TRICK_GROUND`: Call `request_state_change(TRICK_GROUND)` when wheelie/stoppie starts
- Exit `TRICK_GROUND`: Call `request_state_change(RIDING)` when pitch returns to neutral

**Update flow:**
```gdscript
func _bike_update(delta):
    match player_controller.state.player_state:
        RIDING:
            _update_wheelie(delta)   # May enter TRICK_GROUND
            _update_stoppie(delta)   # May enter TRICK_GROUND
            _update_skidding(delta)
        TRICK_GROUND:
            _update_wheelie(delta)   # Continue or exit
            _update_stoppie(delta)   # Continue or exit
            _update_skidding(delta)
        AIRBORNE, TRICK_AIR:
            _update_airborne_pitch(delta)
```

### 4. Remove Helper Functions

| Function | Action |
|----------|--------|
| `is_in_wheelie()` | Inline `state.pitch_angle > deg_to_rad(5)` where needed |
| `is_in_stoppie()` | Remove (only used in `is_in_ground_trick`) |
| `is_in_ground_trick()` | Remove - use `state.player_state == TRICK_GROUND` |
| `is_in_air_trick()` | Remove - use `state.player_state == TRICK_AIR` |
| `_update_wheelie_distance()` | Inline into `_update_wheelie()` |

### 5. Simplify `player_controller._update_player_state()`

Trick states are now managed by `bike_tricks` via `request_state_change()`. The main controller only handles simple transitions:

```gdscript
func _update_player_state():
    if state.player_state in [BikeState.PlayerState.CRASHED, BikeState.PlayerState.CRASHING]:
        return
    # Trick states managed by bike_tricks
    if state.player_state in [BikeState.PlayerState.TRICK_GROUND, BikeState.PlayerState.TRICK_AIR]:
        return

    var is_airborne = not is_on_floor()
    var target: BikeState.PlayerState
    if is_airborne:
        target = BikeState.PlayerState.AIRBORNE
    elif state.speed < 0.5 and not bike_input.has_input():
        target = BikeState.PlayerState.IDLE
    else:
        target = BikeState.PlayerState.RIDING

    state.request_state_change(target)
```

## Final File Structure

```
bike_tricks.gd (~400 lines, down from 575)
├── Signals (unchanged)
├── Trick enum & TRICK_DATA (unchanged)
├── Export vars (unchanged)
├── Local state (remove current_delta, add force_stoppie vars)
│
├── _bike_setup()
├── _bike_update(delta) - simplified match
├── _bike_reset()
│
├── State updates:
│   ├── _update_riding(delta)
│   ├── _update_trick_ground(delta)
│   ├── _update_airborne(delta)
│   └── _update_trick_air(delta)
│
├── Wheelie: _update_wheelie(delta)
├── Stoppie: _update_stoppie(delta)
├── Skidding: _update_skidding(delta)
│
├── Boost:
│   ├── _update_boost(delta)
│   └── _activate_boost()
│
├── Trick lifecycle:
│   ├── _update_active_trick(delta)
│   ├── _detect_trick()
│   ├── _start_trick(), _continue_trick(), _end_trick()
│   └── _update_combo_timer(delta)
│
├── Signal handlers:
│   ├── _on_crashed()
│   ├── _on_force_stoppie_requested() - sets flags only
│   └── _on_trick_btn_changed()
│
├── Utils: _spawn_skid_mark()
│
└── Public API:
    ├── get_current_trick_name()
    ├── get_fishtail_vibration()
    ├── get_fishtail_speed_loss()
    ├── get_boosted_max_speed()
    └── get_boosted_throttle()
```

## Files to Modify

1. `scenes/bike/components/bike_tricks.gd` - Main refactor
2. `scenes/bike/player_controller.gd` - Simplify `_update_player_state()`
