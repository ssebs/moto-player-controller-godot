class_name BikeTricks extends BikeComponent

# Existing signals
signal tire_screech_start(volume: float)
signal tire_screech_stop
signal stoppie_stopped # Emitted when bike comes to rest during a stoppie
signal boost_started
signal boost_ended
signal boost_earned # Emitted when a boost is earned from tricks

# Trick lifecycle signals
signal trick_started(trick: Trick)
signal trick_ended(trick: Trick, score: float, duration: float)
signal trick_cancelled(trick: Trick)
signal combo_expired


#region Trick Object Definition
# Trick enum
enum Trick {
    NONE,
    WHEELIE_SITTING,
    WHEELIE_STANDING,
    STOPPIE,
    FISHTAIL,
    DRIFT,
    HEEL_CLICKER,
    BOOST,
    KICKFLIP,
}
# Trick data configuration
# base_points: instant score when trick completes
# points_per_sec: score accumulated per second while trick is active
const TRICK_DATA: Dictionary[Trick, Dictionary] = {
    Trick.WHEELIE_SITTING: {"name": "Sitting Wheelie", "base_points": 50, "points_per_sec": 10.0},
    Trick.WHEELIE_STANDING: {"name": "Standing Wheelie", "base_points": 100, "points_per_sec": 20.0},
    Trick.STOPPIE: {"name": "Stoppie", "base_points": 75, "points_per_sec": 15.0},
    Trick.FISHTAIL: {"name": "Fishtail", "base_points": 25, "points_per_sec": 8.0},
    Trick.DRIFT: {"name": "Drift", "base_points": 50, "points_per_sec": 12.0},
    Trick.HEEL_CLICKER: {"name": "Heel Clicker", "base_points": 200, "points_per_sec": 50.0},
    Trick.BOOST: {"name": "Boost", "base_points": 0, "points_per_sec": 25.0, "is_modifier": true},
    Trick.KICKFLIP: {"name": "Kickflip", "base_points": 200, "points_per_sec": 0.0},
}
#endregion

# Difficulty score multipliers
const DIFFICULTY_MULT: Dictionary = {
    BikeState.PlayerDifficulty.EASY: 0.8,
    BikeState.PlayerDifficulty.MEDIUM: 1.0,
    BikeState.PlayerDifficulty.HARD: 1.5,
}

@export var starting_boosts: int = 2
@export var wheelie_time_for_boost: float = 5.0 # seconds
@export var combo_window: float = 2.0
@export var combo_increment: float = 0.25
@export var max_combo_multiplier: float = 4.0

#region Tunables (export vars)
# Stoppie
@export var stoppie_reference_speed: float = 15.0 # full stoppie available at this speed

# Rotation
@export var max_wheelie_angle: float = deg_to_rad(85) # in radians
@export var max_stoppie_angle: float = deg_to_rad(55) # in radians
@export var wheelie_balance_point_angle: float = deg_to_rad(60) # in radians
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0
@export var balance_point_decay_mult: float = 0.25 # Slower decay when in balance point zone

# Wheelie RPM
@export var wheelie_rpm_threshold: float = 0.65 # RPM ratio where wheelies can start

# Fishtail/drift
@export var max_fishtail_angle: float = deg_to_rad(30)
@export var fishtail_speed: float = 8.0
@export var fishtail_recovery_speed: float = 3.0

# Skid marks
@export var skidmark_texture = preload("res://assets/textures/skidmarktex.png")
@export var skid_volume: float = 0.5
@export var skid_spawn_interval: float = 0.025
@export var skid_tex_lifetime: float = 5.0

# Boost
@export var boost_double_tap_window: float = 1.0
@export var boost_speed_multiplier: float = 1.5
@export var boost_duration: float = 2.0
@export var boost_steering_multiplier: float = 0.5 # Reduce steering during boost

# Trick detection thresholds
@export var wheelie_threshold: float = deg_to_rad(15) # Pitch angle to detect wheelie
@export var stoppie_threshold: float = deg_to_rad(10) # Pitch angle to detect stoppie (positive value, used as negative)
@export var fishtail_threshold: float = deg_to_rad(10) # Fishtail angle to detect fishtail/drift
#endregion

#region Local State
var _boost_timer: float = 0.0
var _wheelie_time_held: float = 0.0 # For boost earning during wheelie
var _combo_timer: float = 0.0
var _last_trick_press_time: float = 0.0 # Double-tap boost detection

var _skid_spawn_timer: float = 0.0
var _front_skid_spawn_timer: float = 0.0

# Clutch dump detection (single frame comparison)
var _last_clutch_value: float = 0.0

# Force stoppie state (set by signal handler, applied in _update_stoppie)
var _force_stoppie_target: float = 0.0
var _force_stoppie_rate: float = 0.0
var _force_stoppie_active: bool = false
#endregion

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    player_controller.bike_input.trick_changed.connect(_on_trick_btn_changed)
    player_controller.bike_crash.crashed.connect(_on_crashed)
    player_controller.bike_physics.launched.connect(_on_launched)
    stoppie_stopped.connect(_on_stoppie_stopped)

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


func _bike_reset():
    player_controller.state.pitch_angle = 0.0
    player_controller.state.fishtail_angle = 0.0
    player_controller.state.is_boosting = false
    player_controller.state.boost_count = starting_boosts
    _boost_timer = 0.0
    _wheelie_time_held = 0.0
    _skid_spawn_timer = 0.0
    _front_skid_spawn_timer = 0.0
    _last_clutch_value = 0.0

    # Reset trick scoring state
    player_controller.state.active_trick = Trick.NONE
    player_controller.state.trick_score = 0.0
    player_controller.state.boost_trick_score = 0.0
    player_controller.state.combo_multiplier = 1.0
    player_controller.state.combo_count = 0
    _combo_timer = 0.0
    _last_trick_press_time = 0.0

    # Reset force stoppie state
    _force_stoppie_target = 0.0
    _force_stoppie_rate = 0.0
    _force_stoppie_active = false
    player_controller.state.grip_usage = 0.0
#endregion

#region State Handlers

## Updates riding state - checks for wheelie, stoppie, and skidding.
func _update_riding(delta):
    _update_wheelie(delta)
    _update_stoppie(delta)
    _update_skidding(delta)


## Airborne with no active pitch control. Transitions to TRICK_AIR or RIDING.
func _update_airborne(delta):
    _update_airborne_pitch(delta)
    # if player_controller.is_on_floor():
    #     player_controller.state.request_state_change(BikeState.PlayerState.RIDING)


## Airborne with pitch control active. Transitions to TRICK_GROUND or RIDING on land.
func _update_trick_air(delta):
    _update_wheelie_distance(delta)
    _update_airborne_pitch(delta)
    if player_controller.is_on_floor():
        if abs(player_controller.state.pitch_angle) > deg_to_rad(5):
            player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
        else:
            player_controller.state.request_state_change(BikeState.PlayerState.RIDING)


## Updates trick ground state - wheelie/stoppie/fishtail physics.
func _update_trick_ground(delta):
    _update_wheelie(delta)
    _update_stoppie(delta)
    _update_skidding(delta)


## Airborne pitch control - free rotation with lean input.
func _update_airborne_pitch(delta: float):
    var was_in_air_trick = abs(player_controller.state.pitch_angle) > deg_to_rad(5)

    if abs(player_controller.bike_input.lean) > 0.1:
        var air_pitch_target = player_controller.bike_input.lean * max_wheelie_angle
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, air_pitch_target, rotation_speed * 1.5 * delta)

    # State transitions for air tricks
    var is_in_air_trick = abs(player_controller.state.pitch_angle) > deg_to_rad(5)
    if is_in_air_trick and not was_in_air_trick:
        player_controller.state.request_state_change(BikeState.PlayerState.TRICK_AIR)
    elif not is_in_air_trick and was_in_air_trick:
        player_controller.state.request_state_change(BikeState.PlayerState.AIRBORNE)


## Handles wheelie initiation and continuation based on RPM, throttle, and clutch dump.
func _update_wheelie(delta: float):
    _update_wheelie_distance(delta)

    # Detect if we can / are in a wheelie
    var in_wheelie = player_controller.state.pitch_angle > wheelie_threshold

    # Detect clutch dump
    var clutch_dump = _last_clutch_value > 0.7 and player_controller.state.clutch_value < 0.3 and player_controller.bike_input.throttle > 0.5
    _last_clutch_value = player_controller.state.clutch_value

    # Can't START a wheelie while turning, but can continue one
    var can_start = not player_controller.bike_physics.is_turning()

    # Wheelie initiation requires RPM above threshold or clutch dump
    var rpm_above_threshold = player_controller.state.rpm_ratio >= wheelie_rpm_threshold
    var can_pop = player_controller.bike_input.lean > 0.3 and player_controller.bike_input.throttle > 0.7 and (rpm_above_threshold or clutch_dump)
    var fast_enough = player_controller.state.speed > 1

    # Calculate the target angle
    var in_balance_point = player_controller.state.pitch_angle > wheelie_balance_point_angle

    var wheelie_target = 0.0
    if fast_enough and (in_wheelie or (can_pop and can_start)):
        if player_controller.bike_input.throttle > 0.3:
            wheelie_target = max_wheelie_angle * player_controller.bike_input.throttle
            if player_controller.bike_input.lean > 0:
                wheelie_target += max_wheelie_angle * player_controller.bike_input.lean * 0.15

    # Balance point wheelie - stable zone where bike is easier to balance but still unstable
    if in_balance_point:
        player_controller.wheelie_sweetspot_label.show() # TODO: move to ui
        # Lean input adjusts target within balance zone
        var lean_influence = player_controller.bike_input.lean * (max_wheelie_angle - wheelie_balance_point_angle)
        var balance_target = player_controller.state.pitch_angle + lean_influence * 0.5

        if player_controller.bike_input.throttle >= 0.5:
            # Throttle ≥ 0.5: can go higher, lean still affects
            wheelie_target = maxf(wheelie_target, balance_target)
        else:
            # Throttle < 0.5: drift toward balance point, lean still affects
            # wheelie_target = clampf(balance_target, wheelie_balance_point_angle, max_wheelie_angle)
            var midpoint = (wheelie_balance_point_angle + max_wheelie_angle) / 2

            if balance_target <= midpoint:
                wheelie_target = clampf(balance_target, wheelie_balance_point_angle, player_controller.bike_input.throttle)
                print("NOT past midpoint")
            else:
                print("past midpoint")
                wheelie_target = clampf(balance_target, midpoint, max_wheelie_angle + deg_to_rad(1))

            # randomness!
            # wheelie_target *= randf_range(deg_to_rad(-1),deg_to_rad(1))

    else:
        player_controller.wheelie_sweetspot_label.hide() # TODO: move to ui
        # Normal wheelie: lean forward brings wheel down
        if player_controller.bike_input.lean < 0 and in_wheelie:
            player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, return_speed * abs(player_controller.bike_input.lean) * 2.0 * delta)

    # Apply wheelie pitch
    if wheelie_target > 0:
        var speed = rotation_speed * balance_point_decay_mult if in_balance_point else rotation_speed
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, wheelie_target, speed * delta)
    elif player_controller.state.pitch_angle > 0:
        # Use slower decay when in balance point zone
        var decay_speed = return_speed * balance_point_decay_mult if in_balance_point else return_speed
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, decay_speed * delta)

    # EASY mode clamp
    if player_controller.state.isEasyDifficulty():
        var safe_limit = player_controller.bike_crash.crash_wheelie_threshold - deg_to_rad(5)
        player_controller.state.pitch_angle = min(player_controller.state.pitch_angle, safe_limit)


## Handles stoppie initiation, continuation, and forced stoppie from crash system.
func _update_stoppie(delta: float):
    var front_wheel_locked = is_front_wheel_locked()
    var was_in_stoppie = player_controller.state.pitch_angle < -stoppie_threshold

    # Handle forced stoppie from crash system
    if _force_stoppie_active:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, _force_stoppie_target, _force_stoppie_rate * delta)
        if abs(player_controller.state.pitch_angle - _force_stoppie_target) < 0.01:
            _force_stoppie_active = false
        return

    # Can't START a stoppie while turning, but can continue one
    var can_start_trick = not player_controller.bike_physics.is_turning()

    # Scale max stoppie angle by speed - full angle only available at reference speed
    var speed_scale = clamp(player_controller.state.speed / stoppie_reference_speed, 0.0, 1.0)
    var effective_max_stoppie = max_stoppie_angle * speed_scale

    # Stoppie logic - only works with progressive braking (not grabbed)
    # If front wheel is locked (brake grabbed), no stoppie - just skid
    var stoppie_target = 0.0
    if not front_wheel_locked:
        var wants_stoppie = player_controller.bike_input.lean < -0.1 and player_controller.bike_input.front_brake > 0.5
        if player_controller.state.speed > 1 and (was_in_stoppie or (wants_stoppie and can_start_trick)):
            stoppie_target = - effective_max_stoppie * player_controller.bike_input.front_brake * (1.0 - player_controller.bike_input.throttle * 0.5)
            stoppie_target += -effective_max_stoppie * (-player_controller.bike_input.lean) * 0.15

    # Apply stoppie pitch
    if stoppie_target < 0:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, stoppie_target, rotation_speed * delta)
        if not was_in_stoppie:
            tire_screech_start.emit(skid_volume)
        # Check if bike stopped during stoppie - soft reset without position change
        var currently_in_stoppie = player_controller.state.pitch_angle < -stoppie_threshold
        if player_controller.state.speed < 0.5 and currently_in_stoppie:
            player_controller.state.pitch_angle = 0.0
            tire_screech_stop.emit()
            stoppie_stopped.emit()
    elif player_controller.state.pitch_angle < 0:
        # Return to neutral if not in wheelie territory
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, return_speed * delta)
        if was_in_stoppie and player_controller.state.pitch_angle >= -stoppie_threshold:
            tire_screech_stop.emit()


## Updates rear and front wheel skidding, fishtail physics, and spawns skid marks.
func _update_skidding(delta: float):
    var is_on_floor = player_controller.is_on_floor()
    var front_wheel_locked = is_front_wheel_locked()
    var rear_wheel_pos = player_controller.rear_wheel.global_position
    var front_wheel_pos = player_controller.front_wheel.global_position
    var bike_rot = player_controller.global_rotation

    var is_rear_skidding = player_controller.bike_input.rear_brake > 0.5 and player_controller.state.speed > 2 and is_on_floor
    var is_front_skidding = front_wheel_locked and player_controller.state.speed > 2 and is_on_floor

    # Rear wheel skid
    if is_rear_skidding:
        _skid_spawn_timer += delta
        if _skid_spawn_timer >= skid_spawn_interval:
            _skid_spawn_timer = 0.0
            _spawn_skid_mark(rear_wheel_pos, bike_rot)

        # Fishtail calculation - lean induces fishtail direction
        var steer_influence = player_controller.state.lean_angle / player_controller.bike_resource.max_lean_angle_rad
        var target_fishtail = - steer_influence * max_fishtail_angle * player_controller.bike_input.rear_brake

        # Small natural wobble when skidding straight (random direction, small amplitude)
        if abs(steer_influence) < 0.1:
            var wobble_direction = 1.0 if player_controller.state.fishtail_angle >= 0 else -1.0
            if abs(player_controller.state.fishtail_angle) < deg_to_rad(2):
                wobble_direction = [-1.0, 1.0][randi() % 2]
            target_fishtail = wobble_direction * deg_to_rad(8) * player_controller.bike_input.rear_brake

        var speed_factor = clamp(player_controller.state.speed / 20.0, 0.5, 1.5)
        target_fishtail *= speed_factor

        if abs(player_controller.state.fishtail_angle) > deg_to_rad(15):
            target_fishtail *= 1.1 # Amplify once sliding

        player_controller.state.fishtail_angle = move_toward(player_controller.state.fishtail_angle, target_fishtail, fishtail_speed * delta)
    else:
        _skid_spawn_timer = 0.0
        player_controller.state.fishtail_angle = move_toward(player_controller.state.fishtail_angle, 0, fishtail_recovery_speed * delta)

    # Front wheel skid (locked brake)
    if is_front_skidding:
        _front_skid_spawn_timer += delta
        if _front_skid_spawn_timer >= skid_spawn_interval:
            _front_skid_spawn_timer = 0.0
            _spawn_skid_mark(front_wheel_pos, bike_rot)
        tire_screech_start.emit(skid_volume)
    else:
        _front_skid_spawn_timer = 0.0

    # Tire screech for rear skid (only if not already screeching from front)
    if is_rear_skidding and not is_front_skidding:
        tire_screech_start.emit(skid_volume)

## Updates boost timer and ends boost when expired.
func _update_boost(delta):
    if not player_controller.state.is_boosting:
        return

    _boost_timer -= delta
    if _boost_timer <= 0:
        player_controller.state.is_boosting = false
        _commit_boost_score()
        boost_ended.emit()


## Tracks wheelie time for boost earning.
func _update_wheelie_distance(delta):
    if player_controller.state.pitch_angle > wheelie_threshold:
        _wheelie_time_held += delta
        if _wheelie_time_held >= wheelie_time_for_boost:
            _wheelie_time_held -= wheelie_time_for_boost
            player_controller.state.boost_count += 1
            boost_earned.emit()
    else:
        _wheelie_time_held = 0.0


## Expires combo after window closes.
func _update_combo_timer(delta: float):
    if _combo_timer > 0:
        _combo_timer -= delta
        if _combo_timer <= 0:
            player_controller.state.combo_multiplier = 1.0
            player_controller.state.combo_count = 0
            combo_expired.emit()

#endregion

#region Trick Detection

## Detects ground tricks based on pitch, fishtail, and input.
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

#region Trick Scoring

## Main scoring update - detects trick changes and manages scoring lifecycle.
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


## Initializes scoring for a new trick.
func _begin_trick_scoring(trick: Trick):
    player_controller.state.active_trick = trick
    player_controller.state.trick_score = 0.0
    player_controller.state.trick_start_time = Time.get_ticks_msec() / 1000.0
    trick_started.emit(trick)


## Adds points while trick is active.
func _accumulate_trick_score(delta: float):
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


## Finalizes boost score when boost ends.
func _commit_boost_score():
    var final_score = player_controller.state.boost_trick_score * player_controller.state.combo_multiplier * DIFFICULTY_MULT[player_controller.state.difficulty]
    player_controller.state.total_score += final_score

    # Update combo for boost ending
    if player_controller.state.boost_trick_score > 0:
        player_controller.state.combo_count += 1
        player_controller.state.combo_multiplier = minf(
            player_controller.state.combo_multiplier + combo_increment, max_combo_multiplier
        )
        _combo_timer = combo_window

    player_controller.state.boost_trick_score = 0.0

#endregion


#region Signal Handlers

## Cancels active trick and resets combo on crash.
func _on_crashed():
    var trick = player_controller.state.active_trick
    if trick != Trick.NONE:
        player_controller.state.active_trick = Trick.NONE
        player_controller.state.trick_score = 0.0
        player_controller.state.boost_trick_score = 0.0
        trick_cancelled.emit(trick)

    # Always reset combo on crash
    player_controller.state.combo_multiplier = 1.0
    player_controller.state.combo_count = 0
    _combo_timer = 0.0

## Resets bike when coming to rest during stoppie.
func _on_stoppie_stopped():
    player_controller.bike_physics._bike_reset()
    player_controller.state.speed = 0.0
    player_controller.velocity = Vector3.ZERO

## Transitions to TRICK_AIR when launching from TRICK_GROUND.
func _on_launched():
    if player_controller.state.player_state == BikeState.PlayerState.TRICK_GROUND:
        player_controller.state.request_state_change(BikeState.PlayerState.TRICK_AIR)


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

    # Double-tap detection for boost activation
    if time_since_last <= boost_double_tap_window and time_since_last > 0.05:
        # Double-tap detected - activate boost
        _activate_boost()
        _last_trick_press_time = 0.0 # Reset to prevent triple-tap
    else:
        # First tap - record time (single tap used for other trick actions)
        _last_trick_press_time = current_time
#endregion

#region Utils

## Returns true if the trick is a ground-based trick (wheelie, stoppie, fishtail, drift).
func _is_ground_trick(trick: Trick) -> bool:
    return trick in [Trick.WHEELIE_SITTING, Trick.WHEELIE_STANDING, Trick.STOPPIE, Trick.FISHTAIL, Trick.DRIFT]

## Spawns a skid mark decal at the given position.
func _spawn_skid_mark(pos: Vector3, rot: Vector3):
    var decal = Decal.new()
    decal.texture_albedo = skidmark_texture
    decal.size = Vector3(0.15, 0.5, 0.4)
    decal.cull_mask = 1

    get_tree().current_scene.add_child(decal)

    decal.global_position = Vector3(pos.x, pos.y - 0.05, pos.z)
    decal.global_rotation = rot

    var timer = get_tree().create_timer(skid_tex_lifetime)
    timer.timeout.connect(func(): if is_instance_valid(decal): decal.queue_free())

## Activates boost if available.
func _activate_boost():
    if player_controller.state.is_boosting:
        return
    if player_controller.state.boost_count <= 0:
        return

    player_controller.state.boost_count -= 1
    player_controller.state.is_boosting = true
    player_controller.state.boost_trick_score = 0.0 # Reset boost score
    _boost_timer = boost_duration
    boost_started.emit()
#endregion

#region Public API

## Returns the display name of the current active trick.
func get_current_trick_name() -> String:
    var trick = player_controller.state.active_trick
    if trick == Trick.NONE:
        return ""
    return TRICK_DATA[trick].name


## Returns vibration intensity (weak, strong) for fishtail skidding.
func get_fishtail_vibration() -> Vector2:
    var fishtail_intensity = abs(player_controller.state.fishtail_angle) / max_fishtail_angle if max_fishtail_angle > 0 else 0.0
    if fishtail_intensity > 0.1:
        var weak = fishtail_intensity * 0.6
        var strong = fishtail_intensity * fishtail_intensity * 0.8
        return Vector2(weak, strong)
    return Vector2.ZERO


## Returns how much speed to lose due to fishtail sliding.
func get_fishtail_speed_loss(delta) -> float:
    if abs(player_controller.state.fishtail_angle) > 0.01:
        var slide_friction = abs(player_controller.state.fishtail_angle) / max_fishtail_angle
        return slide_friction * 15.0 * delta
    return 0.0

## Returns max speed, higher if boosting.
func get_effective_max_speed() -> float:
    if player_controller.state.is_boosting:
        return player_controller.bike_gearing.get_max_speed_for_gear() * boost_speed_multiplier
    return player_controller.bike_gearing.get_max_speed_for_gear()


## Returns full throttle if boosting, otherwise base throttle.
func get_boosted_throttle(base_throttle: float) -> float:
    if player_controller.state.is_boosting:
        return 1.0
    return base_throttle


## Returns true if front brake was grabbed (quick 0→100%) causing wheel lock/skid.
func is_front_wheel_locked() -> bool:
    return player_controller.bike_crash.is_front_wheel_locked()


## Returns vibration intensity (weak, strong) for grip usage.
func get_grip_vibration() -> Vector2:
    if player_controller.state.grip_usage > 0.1:
        var intensity = 3.0
        var weak = player_controller.state.grip_usage * intensity
        var strong = player_controller.state.grip_usage * player_controller.state.grip_usage * intensity
        return Vector2(weak, strong)
    return Vector2.ZERO
#endregion
