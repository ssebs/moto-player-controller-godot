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

#region export vars
# Brake system tuning
@export var brake_grab_time_threshold: float = 0.4 # seconds, 0→100% - quick grab locks wheel
@export var stoppie_reference_speed: float = 25.0 # full stoppie available at this speed
@export var brake_lean_sensitivity: float = 0.7 # how much lean reduces safe brake amount
# Tunables
@export var combo_window: float = 2.0
@export var combo_increment: float = 0.25
@export var max_combo_multiplier: float = 4.0
@export var boost_double_tap_window: float = 1.0

# Rotation tuning
@export var max_wheelie_angle: float = deg_to_rad(80)
@export var max_stoppie_angle: float = deg_to_rad(50)
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0

# Wheelie RPM tuning
@export var wheelie_rpm_threshold: float = 0.65 # RPM ratio where wheelies can start

# Fishtail/drift tuning
@export var max_fishtail_angle: float = deg_to_rad(30)
@export var fishtail_speed: float = 8.0
@export var fishtail_recovery_speed: float = 3.0

# Skid marks
@export var skidmark_texture = preload("res://assets/textures/skidmarktex.png")
@export var skid_volume: float = 0.5
@export var skid_spawn_interval: float = 0.025
@export var skid_tex_lifetime: float = 5.0

# Boost tuning
@export var boost_speed_multiplier: float = 1.5
@export var boost_duration: float = 2.0
@export var starting_boosts: int = 2
@export var wheelie_time_for_boost: float = 5.0 # seconds
@export var boost_steering_multiplier: float = 0.5 # Reduce steering during boost
#endregion

#region local state
# Boost state
var boost_timer: float = 0.0
var wheelie_time_held: float = 0.0

# Trick lifecycle state
var _trick_timer: float = 0.0
var _combo_timer: float = 0.0
var _last_trick_press_time: float = 0.0

var skid_spawn_timer: float = 0.0
var front_skid_spawn_timer: float = 0.0

# Input tracking for clutch dump detection
var last_throttle_input: float = 0.0
var last_clutch_input: float = 0.0

# Force stoppie state (set by signal handler, applied in _update_stoppie)
var _force_stoppie_target: float = 0.0
var _force_stoppie_rate: float = 0.0
var _force_stoppie_active: bool = false

# Brake grab detection state (time-based)
var brake_grab_timer: float = 0.0 # tracks time since brake started increasing from 0
var brake_was_zero: bool = true # tracks if brake was released
var brake_was_grabbed: bool = false # true if current brake application was a grab (quick 0→100%)
#endregion

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    player_controller.state.state_changed.connect(_on_player_state_changed)

    player_controller.bike_input.trick_changed.connect(_on_trick_btn_changed)
    player_controller.bike_crash.crashed.connect(_on_crashed)
    stoppie_stopped.connect(_on_stoppie_stopped)

func _bike_update(delta):
    # Handle landing from air - transition out of air states when on floor
    if player_controller.is_on_floor():
        if player_controller.state.player_state == BikeState.PlayerState.TRICK_AIR:
            # Landed with pitch - go to TRICK_GROUND if still pitched, else RIDING
            if abs(player_controller.state.pitch_angle) > deg_to_rad(5):
                player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
            else:
                player_controller.state.request_state_change(BikeState.PlayerState.RIDING)
        elif player_controller.state.player_state == BikeState.PlayerState.AIRBORNE:
            player_controller.state.request_state_change(BikeState.PlayerState.RIDING)

    _update_active_trick(delta)
    _update_combo_timer(delta)
    _update_boost(delta)

    match player_controller.state.player_state:
        BikeState.PlayerState.IDLE:
            pass # No trick updates when idle
        BikeState.PlayerState.RIDING:
            _update_riding(delta)
        BikeState.PlayerState.AIRBORNE:
            _update_airborne(delta)
        BikeState.PlayerState.TRICK_AIR:
            _update_trick_air(delta)
        BikeState.PlayerState.TRICK_GROUND:
            _update_trick_ground(delta)
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            pass # Handled by crash system


func _bike_reset():
    player_controller.state.pitch_angle = 0.0
    player_controller.state.fishtail_angle = 0.0
    player_controller.state.is_boosting = false
    player_controller.state.boost_count = starting_boosts
    boost_timer = 0.0
    wheelie_time_held = 0.0
    skid_spawn_timer = 0.0
    front_skid_spawn_timer = 0.0
    last_throttle_input = 0.0
    last_clutch_input = 0.0

    # Reset trick scoring state
    player_controller.state.active_trick = Trick.NONE
    player_controller.state.trick_score = 0.0
    player_controller.state.boost_trick_score = 0.0
    player_controller.state.combo_multiplier = 1.0
    player_controller.state.combo_count = 0
    _trick_timer = 0.0
    _combo_timer = 0.0
    _last_trick_press_time = 0.0

    # Reset force stoppie state
    _force_stoppie_target = 0.0
    _force_stoppie_rate = 0.0
    _force_stoppie_active = false

    # Reset brake grab detection state
    brake_grab_timer = 0.0
    brake_was_zero = true
    brake_was_grabbed = false
    player_controller.state.grip_usage = 0.0

#endregion

#region _update / handlers

func _update_riding(delta):
    # Check for skidding, can initiate ground tricks
    _update_wheelie_distance(delta)
    _update_wheelie(delta)
    _update_stoppie(delta)
    _update_skidding(delta)
    _update_grip_usage(delta)


func _update_airborne(delta):
    # Can initiate air tricks with pitch control
    _update_airborne_pitch(delta)


func _update_trick_air(delta):
    # Actively controlling pitch in air
    _update_wheelie_distance(delta)
    _update_airborne_pitch(delta)


func _update_trick_ground(delta):
    # Wheelie/stoppie/fishtail active
    _update_wheelie_distance(delta)
    _update_wheelie(delta)
    _update_stoppie(delta)
    _update_skidding(delta)
    _update_grip_usage(delta)


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
    var rpm_ratio = player_controller.state.rpm_ratio
    var was_in_wheelie = player_controller.state.pitch_angle > deg_to_rad(5)

    # Detect clutch dump
    var clutch_dump = last_clutch_input > 0.7 and player_controller.state.clutch_value < 0.3 and player_controller.bike_input.throttle > 0.5
    last_throttle_input = player_controller.bike_input.throttle
    last_clutch_input = player_controller.state.clutch_value

    # Can't START a wheelie while turning, but can continue one
    var can_start_trick = not player_controller.bike_physics.is_turning()

    # Wheelie initiation requires RPM above threshold or clutch dump
    var rpm_above_threshold = rpm_ratio >= wheelie_rpm_threshold
    var can_pop_wheelie = player_controller.bike_input.lean > 0.3 and player_controller.bike_input.throttle > 0.7 and (rpm_above_threshold or clutch_dump)

    var wheelie_target = 0.0
    if player_controller.state.speed > 1 and (was_in_wheelie or (can_pop_wheelie and can_start_trick)):
        if player_controller.bike_input.throttle > 0.3:
            # Wheelie intensity scales with throttle and lean
            wheelie_target = max_wheelie_angle * player_controller.bike_input.throttle
            # Lean back (positive) adds to wheelie
            if player_controller.bike_input.lean > 0:
                wheelie_target += max_wheelie_angle * player_controller.bike_input.lean * 0.15

    # Lean forward actively brings wheel down (works even during wheelie)
    if player_controller.bike_input.lean < 0 and player_controller.state.pitch_angle > 0:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, return_speed * abs(player_controller.bike_input.lean) * 2.0 * delta)

    # Apply wheelie pitch
    if wheelie_target > 0:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, wheelie_target, rotation_speed * delta)
    elif player_controller.state.pitch_angle > 0:
        # Return to neutral if not in stoppie territory
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, return_speed * delta)

    # On EASY mode, clamp wheelie angle to prevent crash
    if player_controller.state.isEasyDifficulty():
        var safe_wheelie_limit = player_controller.bike_crash.crash_wheelie_threshold - deg_to_rad(5)
        player_controller.state.pitch_angle = min(player_controller.state.pitch_angle, safe_wheelie_limit)

    # State transitions for wheelies
    var is_in_wheelie = player_controller.state.pitch_angle > deg_to_rad(5)
    if is_in_wheelie and not was_in_wheelie:
        player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
    elif not is_in_wheelie and was_in_wheelie and player_controller.state.pitch_angle >= 0:
        # Only exit TRICK_GROUND if we're not in a stoppie
        if player_controller.state.player_state == BikeState.PlayerState.TRICK_GROUND:
            player_controller.state.request_state_change(BikeState.PlayerState.RIDING)


## Handles stoppie initiation, continuation, and forced stoppie from crash system.
func _update_stoppie(delta: float):
    var front_wheel_locked = is_front_wheel_locked()
    var was_in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)

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
        var currently_in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)
        if player_controller.state.speed < 0.5 and currently_in_stoppie:
            player_controller.state.pitch_angle = 0.0
            tire_screech_stop.emit()
            stoppie_stopped.emit()
    elif player_controller.state.pitch_angle < 0:
        # Return to neutral if not in wheelie territory
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, return_speed * delta)
        if was_in_stoppie and player_controller.state.pitch_angle >= deg_to_rad(-5):
            tire_screech_stop.emit()

    # State transitions for stoppies
    var is_in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)
    if is_in_stoppie and not was_in_stoppie:
        player_controller.state.request_state_change(BikeState.PlayerState.TRICK_GROUND)
    elif not is_in_stoppie and was_in_stoppie and player_controller.state.pitch_angle <= 0:
        # Only exit TRICK_GROUND if we're not in a wheelie
        if player_controller.state.player_state == BikeState.PlayerState.TRICK_GROUND:
            player_controller.state.request_state_change(BikeState.PlayerState.RIDING)


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
        skid_spawn_timer += delta
        if skid_spawn_timer >= skid_spawn_interval:
            skid_spawn_timer = 0.0
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
        skid_spawn_timer = 0.0
        player_controller.state.fishtail_angle = move_toward(player_controller.state.fishtail_angle, 0, fishtail_recovery_speed * delta)

    # Front wheel skid (locked brake)
    if is_front_skidding:
        front_skid_spawn_timer += delta
        if front_skid_spawn_timer >= skid_spawn_interval:
            front_skid_spawn_timer = 0.0
            _spawn_skid_mark(front_wheel_pos, bike_rot)
        tire_screech_start.emit(skid_volume)
    else:
        front_skid_spawn_timer = 0.0

    # Tire screech for rear skid (only if not already screeching from front)
    if is_rear_skidding and not is_front_skidding:
        tire_screech_start.emit(skid_volume)

func _update_boost(delta):
    if not player_controller.state.is_boosting:
        return

    boost_timer -= delta
    if boost_timer <= 0:
        player_controller.state.is_boosting = false
        _bank_boost_trick_score() # Bank boost trick score when boost ends
        boost_ended.emit()


func _update_grip_usage(delta) -> bool:
    """Updates grip usage for front tire. Returns true if crash should occur."""
    # Skip grip logic entirely on EASY difficulty
    if player_controller.state.isEasyDifficulty():
        player_controller.state.grip_usage = 0.0
        brake_was_grabbed = false
        return false

    var front_brake = player_controller.bike_input.front_brake

    # Track brake grab timing: time from 0 → 100%
    if front_brake < 0.5:
        # Brake released - reset tracking
        brake_was_zero = true
        brake_grab_timer = 0.0
        brake_was_grabbed = false
    elif brake_was_zero and front_brake > 0.1:
        # Brake just started being applied - start timer
        brake_was_zero = false
        brake_grab_timer = 0.0
    elif not brake_was_zero:
        # Brake is being held/increased - accumulate time
        brake_grab_timer += delta
        # Determine if this is a grab when brake reaches high value
        if front_brake > 0.9 and not brake_was_grabbed:
            brake_was_grabbed = brake_grab_timer < brake_grab_time_threshold

    # Calculate lean ratio for brake/lean interaction
    var lean_ratio = abs(player_controller.state.lean_angle) / player_controller.bike_crash.crash_lean_threshold

    # Calculate max safe brake based on lean: more lean = less brake allowed
    var max_safe_brake = 1.0 - (lean_ratio * brake_lean_sensitivity)

    # Update grip usage for UI feedback
    if front_brake > 0.1:
        player_controller.state.grip_usage = clamp(front_brake / max_safe_brake, 0.0, 1.0)
    else:
        player_controller.state.grip_usage = move_toward(player_controller.state.grip_usage, 0.0, 3.0 * delta)

    # Crash logic based on behavior matrix
    if player_controller.state.speed > 10:
        var is_turning = lean_ratio > 0.3

        # Check if currently in a stoppie
        var in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)

        if brake_was_grabbed:
            # Grabbed brake (quick application)
            if is_turning or in_stoppie:
                # Grabbed + turning = crash (lowside)
                # Grabbed + stoppie = crash (over the bars / lowside)
                player_controller.bike_crash.crash_pitch_direction = -1 if in_stoppie else 0
                player_controller.bike_crash.crash_lean_direction = sign(player_controller.state.lean_angle) if player_controller.state.lean_angle != 0 else 1
                player_controller.bike_crash.trigger_crash()
                return true
            # Grabbed + straight (not in stoppie) = skid (handled by is_front_wheel_locked)
        else:
            # Progressive brake
            if is_turning and front_brake > max_safe_brake:
                # Progressive + turning + over lean threshold = crash
                player_controller.bike_crash.crash_pitch_direction = 0
                player_controller.bike_crash.crash_lean_direction = sign(player_controller.state.lean_angle) if player_controller.state.lean_angle != 0 else 1
                player_controller.bike_crash.trigger_crash()
                return true
            # Progressive + straight = stoppie (handled by _update_stoppie)

    return false


func _update_wheelie_distance(delta):
    if player_controller.state.pitch_angle > deg_to_rad(5):
        wheelie_time_held += delta
        if wheelie_time_held >= wheelie_time_for_boost:
            wheelie_time_held -= wheelie_time_for_boost
            player_controller.state.boost_count += 1
            boost_earned.emit()
    else:
        wheelie_time_held = 0.0


func _update_combo_timer(delta: float):
    """Updates combo timer - resets combo when window expires."""
    if _combo_timer > 0:
        _combo_timer -= delta
        if _combo_timer <= 0:
            player_controller.state.combo_multiplier = 1.0
            player_controller.state.combo_count = 0
            combo_expired.emit()
# TODO: move to _update_airborne , _update_trick_air , _update_riding
func _detect_trick() -> Trick:
    """Detects the current trick based on bike state and input."""
    var is_airborne = player_controller.state.player_state in [
        BikeState.PlayerState.AIRBORNE, BikeState.PlayerState.TRICK_AIR
    ]

    # Air tricks (trick button + direction)
    if is_airborne and player_controller.bike_input.trick:
        if Input.is_action_pressed("cam_down"):
            return Trick.HEEL_CLICKER

    # Ground tricks
    if not is_airborne:
        # Wheelie detection (pitch > 15 degrees)
        if player_controller.state.pitch_angle > deg_to_rad(15):
            if player_controller.bike_input.trick:
                return Trick.WHEELIE_STANDING
            else:
                return Trick.WHEELIE_SITTING

        # Stoppie detection (pitch < -10 degrees)
        if player_controller.state.pitch_angle < deg_to_rad(-10):
            return Trick.STOPPIE

        # Fishtail/Drift detection (fishtail angle > 10 degrees)
        if abs(player_controller.state.fishtail_angle) > deg_to_rad(10):
            if player_controller.bike_input.throttle > 0.5:
                return Trick.DRIFT
            else:
                return Trick.FISHTAIL

        # Kickflip trick (trick + left)
        if player_controller.bike_input.trick && Input.is_action_pressed("cam_left"):
            return Trick.KICKFLIP

    return Trick.NONE


func _update_active_trick(delta: float):
    """Main trick update - handles detection, lifecycle, and scoring."""
    var detected = _detect_trick()
    var current = player_controller.state.active_trick

    # Handle trick transitions
    if detected != current:
        if current != Trick.NONE:
            _end_trick(current)
        if detected != Trick.NONE:
            _start_trick(detected)

    # Continue scoring active trick
    if player_controller.state.active_trick != Trick.NONE:
        _continue_trick(delta)
#endregion

#region trick / combo / lifecycle & scoring
func _start_trick(trick: Trick):
    """Called when a new trick begins."""
    player_controller.state.active_trick = trick
    player_controller.state.trick_score = 0.0
    player_controller.state.trick_start_time = Time.get_ticks_msec() / 1000.0
    _trick_timer = 0.0
    trick_started.emit(trick)

func _continue_trick(delta: float):
    """Called each frame while a trick is active - accumulates score."""
    var trick = player_controller.state.active_trick
    if trick == Trick.NONE:
        return

    var data = TRICK_DATA[trick]
    _trick_timer += delta
    player_controller.state.trick_score += data.points_per_sec * delta

func _end_trick(trick: Trick):
    """Called when a trick ends - banks score and updates combo."""
    var data = TRICK_DATA[trick]
    var base_points = data.get("base_points", 0)
    var final_score = (player_controller.state.trick_score + base_points) * player_controller.state.combo_multiplier * DIFFICULTY_MULT[player_controller.state.difficulty]
    player_controller.state.total_score += final_score

    # Update combo
    player_controller.state.combo_count += 1
    player_controller.state.combo_multiplier = minf(
        player_controller.state.combo_multiplier + combo_increment, max_combo_multiplier
    )
    _combo_timer = combo_window

    # Reset trick state
    player_controller.state.active_trick = Trick.NONE
    var duration = _trick_timer
    player_controller.state.trick_score = 0.0

    trick_ended.emit(trick, final_score, duration)

func _bank_boost_trick_score():
    """Banks boost trick score when boost ends."""
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


#region signal handlers
func _on_crashed(_pitch_direction: float, _lean_direction: float):
    """Called when player crashes - cancels active trick and resets combo."""
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

func _on_stoppie_stopped():
    player_controller.bike_physics._bike_reset()
    player_controller.state.speed = 0.0
    player_controller.velocity = Vector3.ZERO

func _on_force_stoppie_requested(target_pitch: float, rate: float):
    _force_stoppie_target = target_pitch
    _force_stoppie_rate = rate
    _force_stoppie_active = true


func _on_trick_btn_changed(btn_pressed: bool):
    """Handles trick button press - double-tap activates boost."""
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

#region local utils
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

func _activate_boost():
    """Activates boost if available."""
    if player_controller.state.is_boosting:
        return
    if player_controller.state.boost_count <= 0:
        return

    player_controller.state.boost_count -= 1
    player_controller.state.is_boosting = true
    player_controller.state.boost_trick_score = 0.0 # Reset boost score
    boost_timer = boost_duration
    boost_started.emit()
#endregion

#region public funcs
func get_current_trick_name() -> String:
    """Returns the display name of the current active trick."""
    var trick = player_controller.state.active_trick
    if trick == Trick.NONE:
        return ""
    return TRICK_DATA[trick].name

func get_fishtail_vibration() -> Vector2:
    """Returns vibration intensity (weak, strong) for fishtail skidding"""
    var fishtail_intensity = abs(player_controller.state.fishtail_angle) / max_fishtail_angle if max_fishtail_angle > 0 else 0.0
    if fishtail_intensity > 0.1:
        var weak = fishtail_intensity * 0.6
        var strong = fishtail_intensity * fishtail_intensity * 0.8
        return Vector2(weak, strong)
    return Vector2.ZERO
func get_fishtail_speed_loss(delta) -> float:
    """Returns how much speed to lose due to fishtail sliding"""
    if abs(player_controller.state.fishtail_angle) > 0.01:
        var slide_friction = abs(player_controller.state.fishtail_angle) / max_fishtail_angle
        return slide_friction * 15.0 * delta
    return 0.0

## Get max speed, higher if boosting.
func get_effective_max_speed() -> float:
    if player_controller.state.is_boosting:
        return player_controller.bike_gearing.get_max_speed_for_gear() * boost_speed_multiplier
    return player_controller.bike_gearing.get_max_speed_for_gear()


func get_boosted_throttle(base_throttle: float) -> float:
    if player_controller.state.is_boosting:
        return 1.0
    return base_throttle

func is_front_wheel_locked() -> bool:
    """Returns true if front brake was grabbed (quick 0→100%) causing wheel lock/skid"""
    # On EASY, front wheel never locks
    if player_controller.state.isEasyDifficulty():
        return false
    return brake_was_grabbed

func get_grip_vibration() -> Vector2:
    """Returns vibration intensity (weak, strong) for grip usage"""
    if player_controller.state.grip_usage > 0.1:
        var intensity = 3.0
        var weak = player_controller.state.grip_usage * intensity
        var strong = player_controller.state.grip_usage * player_controller.state.grip_usage * intensity
        return Vector2(weak, strong)
    return Vector2.ZERO
#endregion
