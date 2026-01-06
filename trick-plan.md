# Trick System Implementation Plan

## Goal
Implement enum + dict based trick detection and scoring system in `bike_tricks.gd`.

## Files to Modify

| File | Changes |
|------|---------|
| `scenes/bike/components/bike_tricks.gd` | Add enum, TRICK_DATA dict, detection logic, scoring |
| `scenes/bike/components/bike_state.gd` | Add `active_trick`, `trick_score`, `combo_multiplier` vars |

---

## Step 1: Trick Enum + Data Dict (`bike_tricks.gd`)

```gdscript
enum Trick {
    NONE,
    WHEELIE_SITTING,
    WHEELIE_STANDING,
    STOPPIE,
    FISHTAIL,
    DRIFT,
    HEEL_CLICKER,
    BOOST,
}

const TRICK_DATA: Dictionary = {
    Trick.WHEELIE_SITTING: {"name": "Sitting Wheelie", "mult": 1.0, "points_per_sec": 10.0},
    Trick.WHEELIE_STANDING: {"name": "Standing Wheelie", "mult": 1.5, "points_per_sec": 20.0},
    Trick.STOPPIE: {"name": "Stoppie", "mult": 1.2, "points_per_sec": 15.0},
    Trick.FISHTAIL: {"name": "Fishtail", "mult": 1.0, "points_per_sec": 8.0},
    Trick.DRIFT: {"name": "Drift", "mult": 1.3, "points_per_sec": 12.0},
    Trick.HEEL_CLICKER: {"name": "Heel Clicker", "mult": 2.0, "points_per_sec": 50.0},
    Trick.BOOST: {"name": "Boost", "mult": 1.5, "points_per_sec": 25.0, "is_modifier": true},
}
```

## Step 2: State Tracking (`bike_state.gd`)

```gdscript
var active_trick: int = 0  # BikeTricks.Trick enum (0 = NONE)
var trick_start_time: float = 0.0
var trick_score: float = 0.0
var boost_trick_score: float = 0.0  # Separate score for boost modifier
var total_score: float = 0.0
var combo_multiplier: float = 1.0
var combo_count: int = 0
```

## Step 3: Detection Logic (`bike_tricks.gd`)

```gdscript
func _detect_trick() -> Trick:
    var is_airborne = player_controller.state.player_state in [
        BikeState.PlayerState.AIRBORNE, BikeState.PlayerState.TRICK_AIR
    ]

    # Air tricks (RB + direction)
    if is_airborne and player_controller.bike_input.trick:
        if player_controller.bike_input.lean < -0.5:
            return Trick.HEEL_CLICKER

    # Ground tricks
    if not is_airborne:
        if player_controller.state.pitch_angle > deg_to_rad(15):
            return Trick.WHEELIE_STANDING if player_controller.bike_input.trick else Trick.WHEELIE_SITTING
        if player_controller.state.pitch_angle < deg_to_rad(-10):
            return Trick.STOPPIE
        if abs(player_controller.state.fishtail_angle) > deg_to_rad(10):
            return Trick.DRIFT if player_controller.bike_input.throttle > 0.5 else Trick.FISHTAIL

    return Trick.NONE
```

## Step 4: Trick Lifecycle

```gdscript
signal trick_started(trick: Trick)
signal trick_ended(trick: Trick, score: float, duration: float)
signal trick_cancelled(trick: Trick)
signal combo_expired

const COMBO_WINDOW: float = 2.0
const COMBO_INCREMENT: float = 0.25
const MAX_COMBO_MULT: float = 4.0

var _trick_timer: float = 0.0
var _combo_timer: float = 0.0

func _update_active_trick(delta: float):
    var detected = _detect_trick()
    var current = player_controller.state.active_trick

    if detected != current:
        if current != Trick.NONE:
            _end_trick(current)
        if detected != Trick.NONE:
            _start_trick(detected)

    if player_controller.state.active_trick != Trick.NONE:
        _continue_trick(delta)

func _start_trick(trick: Trick):
    player_controller.state.active_trick = trick
    player_controller.state.trick_score = 0.0
    _trick_timer = 0.0
    trick_started.emit(trick)

func _continue_trick(delta: float):
    var data = TRICK_DATA[player_controller.state.active_trick]
    _trick_timer += delta
    player_controller.state.trick_score += data.points_per_sec * delta * data.mult

func _end_trick(trick: Trick):
    var final_score = player_controller.state.trick_score * player_controller.state.combo_multiplier
    player_controller.state.total_score += final_score
    player_controller.state.combo_count += 1
    player_controller.state.combo_multiplier = minf(
        player_controller.state.combo_multiplier + COMBO_INCREMENT, MAX_COMBO_MULT
    )
    _combo_timer = COMBO_WINDOW
    player_controller.state.active_trick = Trick.NONE
    player_controller.state.trick_score = 0.0
    trick_ended.emit(trick, final_score, _trick_timer)

func _update_combo_timer(delta: float):
    if _combo_timer > 0:
        _combo_timer -= delta
        if _combo_timer <= 0:
            player_controller.state.combo_multiplier = 1.0
            player_controller.state.combo_count = 0
            combo_expired.emit()
```

## Step 5: Crash Handling

```gdscript
func _on_crashed():
    if player_controller.state.active_trick != Trick.NONE:
        var trick = player_controller.state.active_trick
        player_controller.state.active_trick = Trick.NONE
        player_controller.state.trick_score = 0.0
        player_controller.state.combo_multiplier = 1.0
        trick_cancelled.emit(trick)
```

## Step 6: Integration in `_bike_update()`

```gdscript
func _bike_update(delta):
    _update_active_trick(delta)
    _update_combo_timer(delta)
    _update_boost(delta)
    # ... existing match statement ...
```

---

## Detection Priority
1. Air tricks with input (RB + direction)
2. Ground trick variants with input (RB during wheelie = standing)
3. Base ground tricks (from state)

## Boost as a Trick

Boost is a **modifier trick** that stacks with other active tricks:
- Has `is_modifier: true` flag in TRICK_DATA
- Points accumulate separately and add to total when boost ends
- Multipliers stack: `boost.mult * active_trick.mult * combo_multiplier`

Example: Boosted Standing Wheelie = 25 * 1.5 + 20 * 1.5 = 67.5 points/sec (before combo)

### Boost Activation: RB+RB Double-Tap

Boost requires double-tapping the trick button (RB) within 1 second:

```gdscript
# In bike_tricks.gd
const BOOST_DOUBLE_TAP_WINDOW: float = 1.0
var _last_trick_press_time: float = 0.0

func _on_trick_changed(btn_pressed: bool):
    if not btn_pressed:
        return

    var current_time = Time.get_ticks_msec() / 1000.0
    var time_since_last = current_time - _last_trick_press_time

    if time_since_last <= BOOST_DOUBLE_TAP_WINDOW and time_since_last > 0.05:
        # Double-tap detected - activate boost
        _activate_boost()
        _last_trick_press_time = 0.0  # Reset to prevent triple-tap
    else:
        # First tap - record time, single tap = other trick actions
        _last_trick_press_time = current_time

func _activate_boost():
    if player_controller.state.is_boosting:
        return
    if player_controller.state.boost_count <= 0:
        return

    player_controller.state.boost_count -= 1
    player_controller.state.is_boosting = true
    boost_timer = boost_duration
    boost_started.emit()
```

Integration with existing boost system:
- `boost_started` signal triggers boost trick start
- `boost_ended` signal triggers boost trick end + score banking
- Boost still costs boost_count, earns boost from wheelies unchanged

Detection in `_detect_trick()`:
```gdscript
# After detecting base trick, check for boost modifier
var base_trick = _detect_base_trick()
var is_boosting = player_controller.state.is_boosting

# Return both if boosting during a trick
if is_boosting:
    player_controller.state.is_boost_active = true
    # Boost points tracked separately in _continue_trick()
```

## Crash Behavior
- Lose all score for current trick
- Reset combo multiplier

## Combo System
- 2 second window to chain tricks
- +0.25 multiplier per trick (max 4x)

---

## Existing Code to Preserve/Integrate

These features from current `bike_tricks.gd` must be integrated:

### Existing Boost Earning
```gdscript
# Wheelies earn boost after 5 seconds held
@export var wheelie_time_for_boost: float = 5.0
var wheelie_time_held: float = 0.0

func _update_wheelie_distance(delta):
    if is_in_wheelie():
        wheelie_time_held += delta
        if wheelie_time_held >= wheelie_time_for_boost:
            wheelie_time_held -= wheelie_time_for_boost
            player_controller.state.boost_count += 1
            boost_earned.emit()
    else:
        wheelie_time_held = 0.0
```

### Existing TrickTypes Dict
The current code has a nested dict structure:
```gdscript
const TrickTypes = {
    "wheelie": {"sitting": {...}, "standing": {...}},
    "stoppie": {"basic": {...}},
    "fishtail": {"skid": {...}, "drift": {...}},
    "boost": {"speedboost": {...}},
    "heelclicker": {"in_air": {...}}
}
```
**Decision needed:** Keep nested dict or flatten to enum? ANSWER: flatten to enum

### Clutch Dump Detection (for wheelies)
```gdscript
var clutch_dump = last_clutch_input > 0.7 and player_controller.state.clutch_value < 0.3 and player_controller.bike_input.throttle > 0.5
```

### Existing Signals
```gdscript
signal tire_screech_start(volume: float)
signal tire_screech_stop
signal stoppie_stopped
signal boost_started
signal boost_ended
signal boost_earned
```

### Helper Functions to Keep
- `is_in_wheelie()` - pitch > 5 deg
- `is_in_stoppie()` - pitch < -5 deg
- `is_in_ground_trick()` - any pitch or fishtail > 5 deg
- `is_in_air_trick(is_airborne)` - airborne with pitch control
- `get_fishtail_speed_loss(delta)` - friction from sliding
- `get_fishtail_vibration()` - controller feedback
- `get_boosted_max_speed(base)` - speed multiplier
- `get_boosted_throttle(base)` - throttle override during boost

---

# Migration Plan: Remove Trick Handlers from Other Files

## Overview

All trick-related logic should be consolidated into `bike_tricks.gd`. Other components should only:
1. **Emit signals** that `bike_tricks.gd` listens to
2. **Subscribe to signals** from `bike_tricks.gd` for reactions (audio, UI, animation)
3. **Call helper functions** from `bike_tricks.gd` when needed (e.g., `get_boosted_max_speed()`)

---

## File: `player_controller.gd`

### REMOVE: State detection logic (lines 152-173)

Current `_update_player_state()` directly calls trick detection:
```gdscript
# REMOVE these lines:
var is_ground_trick = bike_tricks.is_in_ground_trick()
var is_air_trick = bike_tricks.is_in_air_trick(is_airborne)
```

### MIGRATE TO: `bike_tricks.gd` owns state transitions

`bike_tricks.gd` should request state changes via signals or direct calls:
```gdscript
# In bike_tricks.gd - after detecting trick
func _update_active_trick(delta):
    var detected = _detect_trick()
    # ... trick lifecycle ...

    # Request appropriate state based on trick
    if detected != Trick.NONE:
        var is_airborne = not player_controller.is_on_floor()
        if is_airborne:
            player_controller.state.request_state_change(BikeState.PlayerState.TRICK_AIR)
        else:
            player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
```

### KEEP: Component update calls
```gdscript
# KEEP - still call bike_tricks._bike_update(delta)
bike_tricks._bike_update(delta)
```

---

## File: `bike_crash.gd`

### REMOVE: Trick crash threshold checks (lines 76-91)

Current code directly checks pitch/lean for crash:
```gdscript
# REMOVE - bike_tricks should emit crash signals instead
if player_controller.state.pitch_angle > crash_wheelie_threshold:
    crash_reason = "wheelie"
elif player_controller.state.pitch_angle < -crash_stoppie_threshold:
    crash_reason = "stoppie"
elif player_controller.state.pitch_angle < deg_to_rad(-15) and abs(player_controller.state.steering_angle) > deg_to_rad(15):
    crash_reason = "stoppie_turn"
```

### REMOVE: `force_stoppie_requested` signal (line 6)
```gdscript
# REMOVE - stoppie forcing moves to bike_tricks
signal force_stoppie_requested(target_pitch: float, rate: float)
```

### REMOVE: `_check_force_stoppie()` function (lines 172-178)
```gdscript
# REMOVE - moves to bike_tricks
func _check_force_stoppie():
    ...
```

### MIGRATE TO: `bike_tricks.gd` emits crash request

```gdscript
# In bike_tricks.gd
signal trick_crash_requested(reason: String, pitch_dir: float, lean_dir: float)

func _check_trick_crash():
    # Wheelie too far
    if player_controller.state.pitch_angle > crash_wheelie_threshold:
        trick_crash_requested.emit("wheelie", 1.0, 0.0)
    # Stoppie too far
    elif player_controller.state.pitch_angle < -crash_stoppie_threshold:
        trick_crash_requested.emit("stoppie", -1.0, 0.0)
    # Stoppie + turn = lowside
    elif is_in_stoppie() and abs(player_controller.state.steering_angle) > deg_to_rad(15):
        trick_crash_requested.emit("stoppie_turn", 0.0, sign(player_controller.state.steering_angle))
```

### KEEP: Thresholds as exports (but consider moving)
```gdscript
# KEEP in bike_crash.gd OR move to bike_tricks.gd
@export var crash_wheelie_threshold: float = deg_to_rad(75)
@export var crash_stoppie_threshold: float = deg_to_rad(55)
```

### KEEP: `is_front_wheel_locked()` helper
```gdscript
# KEEP - other components need this
func is_front_wheel_locked() -> bool:
    return player_controller.state.brake_grab_level > brake_grab_crash_threshold
```

---

## File: `bike_physics.gd`

### REMOVE: `_update_trick_ground()` (lines 90-92)
```gdscript
# REMOVE - unnecessary wrapper
func _update_trick_ground(delta):
    _update_riding(delta)
```

### REMOVE: Direct fishtail physics in `apply_movement()` (lines 248-250)
```gdscript
# REMOVE - bike_tricks should call these via signal/method
if abs(player_controller.state.fishtail_angle) > 0.01:
    player_controller.rotate_y(player_controller.state.fishtail_angle * delta * 1.5)
    apply_fishtail_friction(delta, player_controller.bike_tricks.get_fishtail_speed_loss(delta))
```

### MIGRATE TO: Signal-based fishtail application

```gdscript
# In bike_tricks.gd
signal fishtail_rotation_requested(angle: float, speed_loss: float)

func _update_fishtail(delta):
    if abs(player_controller.state.fishtail_angle) > 0.01:
        var speed_loss = get_fishtail_speed_loss(delta)
        fishtail_rotation_requested.emit(player_controller.state.fishtail_angle, speed_loss)
```

```gdscript
# In bike_physics.gd - connect in _bike_setup
player_controller.bike_tricks.fishtail_rotation_requested.connect(_on_fishtail_rotation)

func _on_fishtail_rotation(angle: float, speed_loss: float):
    player_controller.rotate_y(angle * get_physics_process_delta_time() * 1.5)
    apply_fishtail_friction(get_physics_process_delta_time(), speed_loss)
```

### KEEP: `apply_fishtail_friction()` helper
```gdscript
# KEEP - called by signal handler
func apply_fishtail_friction(_delta, fishtail_speed_loss: float):
    player_controller.state.speed = move_toward(player_controller.state.speed, 0, fishtail_speed_loss)
```

---

## File: `bike_gearing.gd`

### KEEP: Boost throttle integration (line 211)
```gdscript
# KEEP - this is correct signal-based integration
var effective_throttle = player_controller.bike_tricks.get_boosted_throttle(player_controller.bike_input.throttle)
```

### KEEP: `is_clutch_dump()` helper (lines 215-217)
```gdscript
# KEEP - bike_tricks uses this for wheelie detection
func is_clutch_dump(last_clutch: float) -> bool:
    return last_clutch > 0.7 and player_controller.state.clutch_value < 0.3 and player_controller.bike_input.throttle > 0.5
```

---

## File: `bike_animation.gd`

### KEEP: All boost animation handlers (lines 68-83)
```gdscript
# KEEP - proper signal-based reactions
func _on_boost_started():
    player_controller.anim_player.play("naruto_run_start")
func _on_boost_ended():
    player_controller.anim_player.play_backwards("naruto_run_start")
```

### KEEP: Mesh rotation using state values (lines 145-163)
```gdscript
# KEEP - reads from state, doesn't calculate
if player_controller.state.pitch_angle != 0:
    _rotate_around_pivot(...)
```

### ADD: Trick animation signals connection
```gdscript
# ADD in _bike_setup
player_controller.bike_tricks.trick_started.connect(_on_trick_started)
player_controller.bike_tricks.trick_ended.connect(_on_trick_ended)

func _on_trick_started(trick: int):
    match trick:
        BikeTricks.Trick.WHEELIE_STANDING:
            # Play standing wheelie animation
            pass
```

---

## File: `bike_audio.gd`

### KEEP: All signal connections (lines 33-36)
```gdscript
# KEEP - proper signal-based reactions
player_controller.bike_tricks.tire_screech_start.connect(play_tire_screech)
player_controller.bike_tricks.tire_screech_stop.connect(stop_tire_screech)
player_controller.bike_tricks.boost_started.connect(play_nos)
player_controller.bike_tricks.boost_ended.connect(stop_nos)
```

### ADD: Trick audio signals
```gdscript
# ADD in _bike_setup
player_controller.bike_tricks.trick_started.connect(_on_trick_started)
player_controller.bike_tricks.trick_ended.connect(_on_trick_ended)

func _on_trick_started(trick: int):
    # Play trick-specific sound
    pass
```

---

## File: `bike_ui.gd`

### KEEP: All boost UI handlers (lines 139-160)
```gdscript
# KEEP - proper signal-based reactions
func _on_boost_started():
    show_speed_lines()
func _on_boost_ended():
    hide_speed_lines()
func show_boost_toast():
    ...
```

### ADD: Trick score UI
```gdscript
# ADD in _bike_setup
player_controller.bike_tricks.trick_started.connect(_on_trick_started)
player_controller.bike_tricks.trick_ended.connect(_on_trick_ended)
player_controller.bike_tricks.combo_expired.connect(_on_combo_expired)

# ADD UI elements for:
# - Current trick name
# - Current trick score (building)
# - Combo multiplier display
# - Total score
```

---

## File: `bike_state.gd`

### ADD: New trick state variables
```gdscript
# ADD these variables
var active_trick: int = 0  # BikeTricks.Trick enum
var trick_score: float = 0.0
var boost_trick_score: float = 0.0
var total_score: float = 0.0
var combo_multiplier: float = 1.0
var combo_count: int = 0
```

### KEEP: Existing state variables
```gdscript
# KEEP - still needed
var pitch_angle: float = 0.0
var fishtail_angle: float = 0.0
var is_boosting: bool = false
var boost_count: int = 2
```

---

## Summary: Signal Flow After Migration

```
bike_input.gd
    └─► trick_changed ─────────────────────────────► bike_tricks.gd
                                                         │
bike_crash.gd                                            │
    └─► is_front_wheel_locked() ◄──────────── (call) ────┤
                                                         │
bike_tricks.gd (CENTRAL HUB)                             │
    ├─► trick_started ──────────────────────────────► bike_animation.gd
    ├─► trick_ended ────────────────────────────────► bike_audio.gd
    ├─► trick_cancelled ────────────────────────────► bike_ui.gd
    ├─► combo_expired ──────────────────────────────► bike_ui.gd
    ├─► tire_screech_start/stop ────────────────────► bike_audio.gd
    ├─► boost_started/ended ────────────────────────► bike_audio.gd
    │                                                   bike_animation.gd
    │                                                   bike_ui.gd
    ├─► boost_earned ───────────────────────────────► bike_ui.gd
    ├─► trick_crash_requested ──────────────────────► bike_crash.gd
    ├─► fishtail_rotation_requested ────────────────► bike_physics.gd
    │
    ├─► get_boosted_max_speed() ◄──────────── (call) ── bike_physics.gd
    └─► get_boosted_throttle() ◄───────────── (call) ── bike_gearing.gd
```

---

## Implementation Order

1. **Add new state vars** to `bike_state.gd`
2. **Add new signals** to `bike_tricks.gd` (`trick_started`, `trick_ended`, `trick_cancelled`, `combo_expired`, `trick_crash_requested`, `fishtail_rotation_requested`)
3. **Implement trick detection** with new enum system
4. **Implement trick lifecycle** (start/continue/end)
5. **Implement combo system**
6. **Migrate crash checks** from `bike_crash.gd` to `bike_tricks.gd`
7. **Migrate fishtail physics** from `bike_physics.gd` to signal-based
8. **Remove state detection** from `player_controller.gd`
9. **Connect new signals** in consuming components
10. **Add UI elements** for trick/combo display
