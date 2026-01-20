# Wheelie/Stoppie Detection Refactor Design

## Problem

Wheelies and stoppies don't properly transition the player state back from `TRICK_GROUND` to `RIDING` when the trick ends. This is caused by:

1. **Mismatched thresholds**: State transitions use 5° threshold while trick scoring uses 15°/10°
2. **Dual detection**: Both physics methods (`_update_wheelie`/`_update_stoppie`) and trick scoring (`_detect_ground_trick`) independently detect tricks with different logic
3. **No single source of truth**: State and scoring are managed in separate places

## Solution

Make trick scoring the single source of truth for `TRICK_GROUND` state transitions. Unify thresholds as `@export` variables.

## Changes to `bike_tricks.gd`

### 1. Add @export Thresholds

Add near other tunables in the `#region Tunables` section:

```gdscript
# Trick detection thresholds
@export var wheelie_threshold: float = deg_to_rad(15)  # Pitch angle to detect wheelie
@export var stoppie_threshold: float = deg_to_rad(10)  # Pitch angle to detect stoppie (positive value, used as negative)
@export var fishtail_threshold: float = deg_to_rad(10) # Fishtail angle to detect fishtail/drift
```

### 2. Add Helper Function

Add to `#region Utils`:

```gdscript
## Returns true if the trick is a ground-based trick (wheelie, stoppie, fishtail, drift).
func _is_ground_trick(trick: Trick) -> bool:
    return trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_STANDING, Trick.STOPPIE, Trick.FISHTAIL, Trick.DRIFT]
```

### 3. Update `_detect_ground_trick()`

Replace hardcoded thresholds with exports:

```gdscript
func _detect_ground_trick() -> Trick:
    # Wheelie
    if player_controller.state.pitch_angle > wheelie_threshold:
        if player_controller.bike_input.trick:
            return Trick.WHEELIE_STANDING
        return Trick.WHEELIE_SITTING

    # Stoppie
    if player_controller.state.pitch_angle < -stoppie_threshold:
        return Trick.STOPPIE

    # Fishtail/Drift
    if abs(player_controller.state.fishtail_angle) > fishtail_threshold:
        if player_controller.bike_input.throttle > 0.5:
            return Trick.DRIFT
        return Trick.FISHTAIL

    # Kickflip
    if player_controller.bike_input.trick and Input.is_action_pressed("cam_left"):
        return Trick.KICKFLIP

    return Trick.NONE
```

### 4. Update `_update_trick_scoring()`

Add state transition logic when tricks start/end:

```gdscript
func _update_trick_scoring(delta: float):
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
            # Transition to trick state when ground trick starts
            if _is_ground_trick(detected):
                player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
        else:
            # Transition back to RIDING when ground trick ends
            if player_controller.state.player_state == BikeState.PlayerState.TRICK_GROUND:
                player_controller.state.request_state_change(BikeState.PlayerState.RIDING)

    if player_controller.state.active_trick != Trick.NONE:
        _accumulate_trick_score(delta)
```

### 5. Update `_update_wheelie()`

Remove state transition logic and use unified threshold:

**Remove** (lines 255-259):
```gdscript
var now_in_wheelie = player_controller.state.pitch_angle > deg_to_rad(5)
if now_in_wheelie and not in_wheelie:
    player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
elif not now_in_wheelie and in_wheelie:
    player_controller.state.request_state_change(BikeState.PlayerState.RIDING)
```

**Change** `in_wheelie` check (line 219):
```gdscript
# BEFORE:
var in_wheelie = player_controller.state.active_trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_STANDING]

# AFTER:
var in_wheelie = player_controller.state.pitch_angle > wheelie_threshold
```

### 6. Update `_update_stoppie()`

Remove state transition logic and use unified threshold:

**Remove** (lines 308-314):
```gdscript
var is_in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)
if is_in_stoppie and not was_in_stoppie:
    player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
elif not is_in_stoppie and was_in_stoppie and player_controller.state.pitch_angle <= 0:
    if player_controller.state.player_state == BikeState.PlayerState.TRICK_GROUND:
        player_controller.state.request_state_change(BikeState.PlayerState.RIDING)
```

**Change** `was_in_stoppie` check (line 265):
```gdscript
# BEFORE:
var was_in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)

# AFTER:
var was_in_stoppie = player_controller.state.pitch_angle < -stoppie_threshold
```

## Testing

After implementation, verify:

1. Starting a wheelie transitions to `TRICK_GROUND`
2. Ending a wheelie (pitch < 15°) transitions back to `RIDING`
3. Starting a stoppie transitions to `TRICK_GROUND`
4. Ending a stoppie (pitch > -10°) transitions back to `RIDING`
5. Trick scoring still works correctly (scores accumulate and bank)
6. Fishtail/drift detection still works
7. Crashing during a trick still cancels the trick properly
