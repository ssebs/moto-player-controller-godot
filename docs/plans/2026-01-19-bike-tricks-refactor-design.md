# bike_tricks.gd Refactor Design

## Goals
- Simplify / shorten code
- Remove duplicate logic / similar variables
- Add func doc comments per README
- Follow state machine architecture
- Reduce code, don't add more code

## File Structure

```
#region Signals
#region Constants (Trick enum, TRICK_DATA, DIFFICULTY_MULT)
#region Export Vars
#region Local State
#region BikeComponent Lifecycle (_bike_setup, _bike_update, _bike_reset)
#region State Handlers (_update_riding, _update_airborne, _update_trick_air, _update_trick_ground)
#region Trick Physics (_update_wheelie, _update_stoppie, _update_skidding, _update_airborne_pitch)
#region Trick Detection (_detect_ground_trick, _detect_air_trick)
#region Trick Scoring (_update_trick_scoring, _begin_trick_scoring, _accumulate_trick_score, _commit_trick_score, _update_combo_timer, _commit_boost_score)
#region Boost (_update_boost, _activate_boost)
#region Signal Handlers (_on_crashed, _on_stoppie_stopped, _on_trick_btn_changed)
#region Public API (get_current_trick_name, get_fishtail_vibration, etc.)
#region Utils (_spawn_skid_mark)
```

## Local State Cleanup

### Variables to REMOVE
| Variable | Reason |
|----------|--------|
| `_trick_timer` | Redundant with `state.trick_start_time` - calculate duration at end |
| `last_throttle_input` | Dead code - set but never read |
| `brake_grab_timer` | Moving to `bike_crash.gd` |
| `brake_was_zero` | Moving to `bike_crash.gd` |
| `brake_was_grabbed` | Moving to `bike_crash.gd` |

### Variables to KEEP (with underscore prefix)
```gdscript
#region Local State
var _boost_timer: float = 0.0
var _wheelie_time_held: float = 0.0  # For boost earning during wheelie
var _combo_timer: float = 0.0
var _last_trick_press_time: float = 0.0  # Double-tap boost detection

var _skid_spawn_timer: float = 0.0
var _front_skid_spawn_timer: float = 0.0

# Clutch dump detection (single frame comparison)
var _last_clutch_value: float = 0.0

# Force stoppie (from crash system)
var _force_stoppie_target: float = 0.0
var _force_stoppie_rate: float = 0.0
var _force_stoppie_active: bool = false
#endregion
```

## _bike_update Refactor

Clean state machine with no pre-checks:

```gdscript
func _bike_update(delta):
    # These run regardless of state - scoring/combo can persist across transitions,
    # and boost timer counts down even during tricks
    _update_trick_scoring(delta)
    _update_combo_timer(delta)
    _update_boost(delta)

    match player_controller.state.player_state:
        BikeState.PlayerState.IDLE:
            pass
        BikeState.PlayerState.RIDING:
            _update_riding(delta)
        BikeState.PlayerState.AIRBORNE:
            _update_airborne(delta)
        BikeState.PlayerState.TRICK_AIR:
            _update_trick_air(delta)
        BikeState.PlayerState.TRICK_GROUND:
            _update_trick_ground(delta)
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            pass
```

### State Handlers Own Their Transitions

```gdscript
func _update_airborne(delta):
    ## Airborne with no active pitch control. Transitions to TRICK_AIR or RIDING.
    _update_airborne_pitch(delta)
    if player_controller.is_on_floor():
        player_controller.state.request_state_change(BikeState.PlayerState.RIDING)

func _update_trick_air(delta):
    ## Airborne with pitch control active. Transitions to TRICK_GROUND or RIDING on land.
    _update_wheelie_distance(delta)
    _update_airborne_pitch(delta)
    if player_controller.is_on_floor():
        if abs(player_controller.state.pitch_angle) > deg_to_rad(5):
            player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
        else:
            player_controller.state.request_state_change(BikeState.PlayerState.RIDING)
```

## Trick Detection

Split `_detect_trick()` into two focused functions:

```gdscript
#region Trick Detection

## Detects ground tricks based on pitch, fishtail, and input.
func _detect_ground_trick() -> Trick:
    # Wheelie (pitch > 15 degrees)
    if player_controller.state.pitch_angle > deg_to_rad(15):
        if player_controller.bike_input.trick:
            return Trick.WHEELIE_STANDING
        return Trick.WHEELIE_SITTING

    # Stoppie (pitch < -10 degrees)
    if player_controller.state.pitch_angle < deg_to_rad(-10):
        return Trick.STOPPIE

    # Fishtail/Drift (fishtail angle > 10 degrees)
    if abs(player_controller.state.fishtail_angle) > deg_to_rad(10):
        if player_controller.bike_input.throttle > 0.5:
            return Trick.DRIFT
        return Trick.FISHTAIL

    # Kickflip (trick + left)
    if player_controller.bike_input.trick and Input.is_action_pressed("cam_left"):
        return Trick.KICKFLIP

    return Trick.NONE


## Detects air tricks based on input direction.
func _detect_air_trick() -> Trick:
    if player_controller.bike_input.trick:
        if Input.is_action_pressed("cam_down"):
            return Trick.HEEL_CLICKER
    return Trick.NONE

#endregion
```

## Trick Scoring

```gdscript
#region Trick Scoring

## Main scoring update - detects trick changes and manages scoring lifecycle.
func _update_trick_scoring(delta):
    var detected: Trick
    match player_controller.state.player_state:
        BikeState.PlayerState.RIDING, BikeState.PlayerState.TRICK_GROUND:
            detected = _detect_ground_trick()
        BikeState.PlayerState.AIRBORNE, BikeState.PlayerState.TRICK_AIR:
            detected = _detect_air_trick()
        _:
            detected = Trick.NONE

    var current = player_controller.state.active_trick

    if detected != current:
        if current != Trick.NONE:
            _commit_trick_score(current)
        if detected != Trick.NONE:
            _begin_trick_scoring(detected)

    if player_controller.state.active_trick != Trick.NONE:
        _accumulate_trick_score(delta)


## Initializes scoring for a new trick.
func _begin_trick_scoring(trick: Trick):
    player_controller.state.active_trick = trick
    player_controller.state.trick_score = 0.0
    player_controller.state.trick_start_time = Time.get_ticks_msec() / 1000.0
    trick_started.emit(trick)


## Adds points while trick is active.
func _accumulate_trick_score(delta):
    var trick = player_controller.state.active_trick
    if trick == Trick.NONE:
        return
    player_controller.state.trick_score += TRICK_DATA[trick].points_per_sec * delta


## Finalizes score, applies combo multiplier, updates combo state.
func _commit_trick_score(trick: Trick):
    var data = TRICK_DATA[trick]
    var base_points = data.get("base_points", 0)
    var difficulty_mult = DIFFICULTY_MULT[player_controller.state.difficulty]
    var final_score = (player_controller.state.trick_score + base_points) * player_controller.state.combo_multiplier * difficulty_mult
    player_controller.state.total_score += final_score

    # Update combo
    player_controller.state.combo_count += 1
    player_controller.state.combo_multiplier = minf(
        player_controller.state.combo_multiplier + combo_increment, max_combo_multiplier
    )
    _combo_timer = combo_window

    # Emit with duration calculated from start time
    var duration = (Time.get_ticks_msec() / 1000.0) - player_controller.state.trick_start_time
    player_controller.state.active_trick = Trick.NONE
    player_controller.state.trick_score = 0.0
    trick_ended.emit(trick, final_score, duration)


## Expires combo after window closes.
func _update_combo_timer(delta):
    if _combo_timer > 0:
        _combo_timer -= delta
        if _combo_timer <= 0:
            player_controller.state.combo_multiplier = 1.0
            player_controller.state.combo_count = 0
            combo_expired.emit()


## Finalizes boost score when boost ends.
func _commit_boost_score():
    var difficulty_mult = DIFFICULTY_MULT[player_controller.state.difficulty]
    var final_score = player_controller.state.boost_trick_score * player_controller.state.combo_multiplier * difficulty_mult
    player_controller.state.total_score += final_score

    if player_controller.state.boost_trick_score > 0:
        player_controller.state.combo_count += 1
        player_controller.state.combo_multiplier = minf(
            player_controller.state.combo_multiplier + combo_increment, max_combo_multiplier
        )
        _combo_timer = combo_window

    player_controller.state.boost_trick_score = 0.0

#endregion
```

## Trick Physics (Wheelie/Stoppie cleanup)

Replace `was_in_wheelie`/`was_in_stoppie` with `active_trick` checks:

```gdscript
#region Trick Physics

## Handles wheelie initiation and continuation based on RPM, throttle, and clutch dump.
func _update_wheelie(delta):
    var in_wheelie = player_controller.state.active_trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_STANDING]

    # Detect clutch dump
    var clutch_dump = _last_clutch_value > 0.7 and player_controller.state.clutch_value < 0.3 and player_controller.bike_input.throttle > 0.5
    _last_clutch_value = player_controller.state.clutch_value

    # Can't START a wheelie while turning, but can continue one
    var can_start = not player_controller.bike_physics.is_turning()

    # Wheelie initiation requires RPM above threshold or clutch dump
    var rpm_above_threshold = player_controller.state.rpm_ratio >= wheelie_rpm_threshold
    var can_pop = player_controller.bike_input.lean > 0.3 and player_controller.bike_input.throttle > 0.7 and (rpm_above_threshold or clutch_dump)

    var wheelie_target = 0.0
    if player_controller.state.speed > 1 and (in_wheelie or (can_pop and can_start)):
        if player_controller.bike_input.throttle > 0.3:
            wheelie_target = max_wheelie_angle * player_controller.bike_input.throttle
            if player_controller.bike_input.lean > 0:
                wheelie_target += max_wheelie_angle * player_controller.bike_input.lean * 0.15

    # Lean forward brings wheel down
    if player_controller.bike_input.lean < 0 and player_controller.state.pitch_angle > 0:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, return_speed * abs(player_controller.bike_input.lean) * 2.0 * delta)

    # Apply wheelie pitch
    if wheelie_target > 0:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, wheelie_target, rotation_speed * delta)
    elif player_controller.state.pitch_angle > 0:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, return_speed * delta)

    # EASY mode clamp
    if player_controller.state.isEasyDifficulty():
        var safe_limit = player_controller.bike_crash.crash_wheelie_threshold - deg_to_rad(5)
        player_controller.state.pitch_angle = min(player_controller.state.pitch_angle, safe_limit)

    # State transition
    var now_in_wheelie = player_controller.state.pitch_angle > deg_to_rad(5)
    if now_in_wheelie and not in_wheelie:
        player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
    elif not now_in_wheelie and in_wheelie:
        player_controller.state.request_state_change(BikeState.PlayerState.RIDING)
```

Similar pattern applies to `_update_stoppie`.

## Grip Logic Migration to bike_crash.gd

### Add to bike_crash.gd:

```gdscript
#region Brake Grab Detection
var _brake_grab_timer: float = 0.0
var _brake_was_zero: bool = true
var _brake_was_grabbed: bool = false

## Updates brake grab detection and grip-based crash triggering.
func _update_grip(delta):
    if player_controller.state.isEasyDifficulty():
        player_controller.state.grip_usage = 0.0
        _brake_was_grabbed = false
        return

    var front_brake = player_controller.bike_input.front_brake

    # Track brake grab timing
    if front_brake < 0.5:
        _brake_was_zero = true
        _brake_grab_timer = 0.0
        _brake_was_grabbed = false
    elif _brake_was_zero and front_brake > 0.1:
        _brake_was_zero = false
        _brake_grab_timer = 0.0
    elif not _brake_was_zero:
        _brake_grab_timer += delta
        if front_brake > 0.9 and not _brake_was_grabbed:
            _brake_was_grabbed = _brake_grab_timer < brake_grab_time_threshold

    # Calculate grip usage for UI
    var lean_ratio = abs(player_controller.state.lean_angle) / crash_lean_threshold
    var max_safe_brake = 1.0 - (lean_ratio * brake_lean_sensitivity)

    if front_brake > 0.1:
        player_controller.state.grip_usage = clamp(front_brake / max_safe_brake, 0.0, 1.0)
    else:
        player_controller.state.grip_usage = move_toward(player_controller.state.grip_usage, 0.0, 3.0 * delta)

    # Crash detection
    if player_controller.state.speed > 10:
        var is_turning = lean_ratio > 0.3
        var in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)

        if _brake_was_grabbed and (is_turning or in_stoppie):
            _trigger_crash()
        elif not _brake_was_grabbed and is_turning and front_brake > max_safe_brake:
            _trigger_crash()


## Returns true if front brake was grabbed causing wheel lock.
func is_front_wheel_locked() -> bool:
    if player_controller.state.isEasyDifficulty():
        return false
    return _brake_was_grabbed

#endregion
```

### Update bike_crash.gd _bike_update:

```gdscript
func _bike_update(delta):
    match player_controller.state.player_state:
        BikeState.PlayerState.RIDING:
            _update_grip(delta)
            _check_crash_thresholds()
        BikeState.PlayerState.TRICK_GROUND:
            _update_grip(delta)
            _check_crash_thresholds()
        BikeState.PlayerState.AIRBORNE, BikeState.PlayerState.TRICK_AIR:
            _check_landing_crash()
        BikeState.PlayerState.CRASHING:
            _update_crash_physics(delta)
        BikeState.PlayerState.CRASHED:
            _update_respawn_timer(delta)
```

### Export vars to move:
- `brake_grab_time_threshold`
- `brake_lean_sensitivity`

## Signal Handlers

```gdscript
#region Signal Handlers

## Cancels active trick and resets combo on crash.
func _on_crashed():
    var trick = player_controller.state.active_trick
    if trick != Trick.NONE:
        player_controller.state.active_trick = Trick.NONE
        player_controller.state.trick_score = 0.0
        player_controller.state.boost_trick_score = 0.0
        trick_cancelled.emit(trick)

    player_controller.state.combo_multiplier = 1.0
    player_controller.state.combo_count = 0
    _combo_timer = 0.0


## Resets bike when coming to rest during stoppie.
func _on_stoppie_stopped():
    player_controller.bike_physics._bike_reset()
    player_controller.state.speed = 0.0
    player_controller.velocity = Vector3.ZERO


## Sets force stoppie parameters from crash system.
func _on_force_stoppie_requested(target_pitch: float, rate: float):
    _force_stoppie_target = target_pitch
    _force_stoppie_rate = rate
    _force_stoppie_active = true


## Handles trick button - double-tap activates boost.
func _on_trick_btn_changed(btn_pressed: bool):
    if not btn_pressed:
        return

    var current_time = Time.get_ticks_msec() / 1000.0
    var time_since_last = current_time - _last_trick_press_time

    if time_since_last <= boost_double_tap_window and time_since_last > 0.05:
        _activate_boost()
        _last_trick_press_time = 0.0
    else:
        _last_trick_press_time = current_time

#endregion
```

## Summary of Changes

### Files changed:
- `bike_tricks.gd` - Refactored
- `bike_crash.gd` - Add grip/brake grab logic

### Removed from bike_tricks.gd:
- `_trick_timer` (use `trick_start_time` instead)
- `last_throttle_input` (dead code)
- `brake_grab_timer`, `brake_was_zero`, `brake_was_grabbed` (moved to crash)
- `_update_grip_usage()` (moved to crash)
- `is_front_wheel_locked()` (moved to crash)
- `grip_crash_triggered` signal (crash handles internally)
- `_detect_trick()` (split into `_detect_ground_trick`, `_detect_air_trick`)
- Landing checks before match statement (moved into state handlers)

### Renamed:
| Old | New |
|-----|-----|
| `last_clutch_input` | `_last_clutch_value` |
| `_update_active_trick` | `_update_trick_scoring` |
| `_start_trick` | `_begin_trick_scoring` |
| `_continue_trick` | `_accumulate_trick_score` |
| `_end_trick` | `_commit_trick_score` |
| `_bank_boost_trick_score` | `_commit_boost_score` |

### Estimated line reduction:
~50-70 lines (grip logic move + dead code + redundant vars)
