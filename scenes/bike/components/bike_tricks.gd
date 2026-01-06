class_name BikeTricks extends BikeComponent

# Existing signals
signal tire_screech_start(volume: float)
signal tire_screech_stop
signal stoppie_stopped # Emitted when bike comes to rest during a stoppie
signal boost_started
signal boost_ended
signal boost_earned # Emitted when a boost is earned from tricks

# Trick lifecycle signals
signal trick_started(trick: int)
signal trick_ended(trick: int, score: float, duration: float)
signal trick_cancelled(trick: int)
signal combo_expired

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
}

# Trick data configuration
# base_points: instant score when trick completes
# points_per_sec: score accumulated per second while trick is active
# mult: multiplier applied to points_per_sec
const TRICK_DATA: Dictionary = {
	Trick.WHEELIE_SITTING: {"name": "Sitting Wheelie", "base_points": 50, "mult": 1.0, "points_per_sec": 10.0},
	Trick.WHEELIE_STANDING: {"name": "Standing Wheelie", "base_points": 100, "mult": 1.5, "points_per_sec": 20.0},
	Trick.STOPPIE: {"name": "Stoppie", "base_points": 75, "mult": 1.2, "points_per_sec": 15.0},
	Trick.FISHTAIL: {"name": "Fishtail", "base_points": 25, "mult": 1.0, "points_per_sec": 8.0},
	Trick.DRIFT: {"name": "Drift", "base_points": 50, "mult": 1.3, "points_per_sec": 12.0},
	Trick.HEEL_CLICKER: {"name": "Heel Clicker", "base_points": 200, "mult": 2.0, "points_per_sec": 50.0},
	Trick.BOOST: {"name": "Boost", "base_points": 0, "mult": 1.5, "points_per_sec": 25.0, "is_modifier": true},
}

# Combo system constants
const COMBO_WINDOW: float = 2.0
const COMBO_INCREMENT: float = 0.25
const MAX_COMBO_MULT: float = 4.0

# Difficulty score multipliers
const DIFFICULTY_MULT: Dictionary = {
	BikeState.PlayerDifficulty.EASY: 0.8,
	BikeState.PlayerDifficulty.MEDIUM: 1.0,
	BikeState.PlayerDifficulty.HARD: 1.5,
}

# Boost double-tap activation
const BOOST_DOUBLE_TAP_WINDOW: float = 1.0

# Rotation tuning
@export var max_wheelie_angle: float = deg_to_rad(80)
@export var max_stoppie_angle: float = deg_to_rad(50)
@export var rotation_speed: float = 2.0
@export var return_speed: float = 3.0

# Wheelie RPM tuning - wheelies start at this RPM ratio and scale up to max at redline
@export var wheelie_rpm_threshold: float = 0.65 # RPM ratio where wheelies can start
@export var wheelie_rpm_full: float = 0.95 # RPM ratio for maximum wheelie effect

# Fishtail/drift tuning
@export var max_fishtail_angle: float = deg_to_rad(30)
@export var fishtail_speed: float = 8.0
@export var fishtail_recovery_speed: float = 3.0

# Skid marks
@export var skidmark_texture = preload("res://assets/textures/skidmarktex.png")
@export var skid_volume: float = 0.5

# Boost tuning
@export var boost_speed_multiplier: float = 1.5
@export var boost_duration: float = 2.0
@export var starting_boosts: int = 2
@export var wheelie_time_for_boost: float = 5.0 # seconds

# Boost state
var boost_timer: float = 0.0
var wheelie_time_held: float = 0.0

# Trick lifecycle state
var _trick_timer: float = 0.0
var _combo_timer: float = 0.0
var _last_trick_press_time: float = 0.0

const SKID_SPAWN_INTERVAL: float = 0.025
const SKID_MARK_LIFETIME: float = 5.0
var skid_spawn_timer: float = 0.0
var front_skid_spawn_timer: float = 0.0

# Input tracking for clutch dump detection
var last_throttle_input: float = 0.0
var last_clutch_input: float = 0.0

# Frame delta for signal handlers
var current_delta: float = 0.0


func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

    player_controller.bike_input.trick_changed.connect(_on_trick_changed)
    player_controller.bike_crash.force_stoppie_requested.connect(_on_force_stoppie_requested)
    player_controller.bike_crash.crashed.connect(_on_crashed_signal)
    stoppie_stopped.connect(_on_stoppie_stopped)

func _bike_update(delta):
    current_delta = delta
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


func _update_riding(delta):
    # Check for skidding, can initiate ground tricks
    _update_wheelie_distance(delta)
    handle_wheelie_stoppie(delta, player_controller.state.rpm_ratio, player_controller.bike_crash.is_front_wheel_locked(), false)
    handle_skidding(delta, player_controller.bike_crash.is_front_wheel_locked(),
        player_controller.rear_wheel.global_position, player_controller.front_wheel.global_position,
        player_controller.global_rotation, true)


func _update_airborne(delta):
    # Can initiate air tricks with pitch control
    handle_wheelie_stoppie(delta, player_controller.state.rpm_ratio, false, true)


func _update_trick_air(delta):
    # Actively controlling pitch in air
    _update_wheelie_distance(delta)
    handle_wheelie_stoppie(delta, player_controller.state.rpm_ratio, false, true)


func _update_trick_ground(delta):
    # Wheelie/stoppie/fishtail active
    _update_wheelie_distance(delta)
    handle_wheelie_stoppie(delta, player_controller.state.rpm_ratio, player_controller.bike_crash.is_front_wheel_locked(), false)
    handle_skidding(delta, player_controller.bike_crash.is_front_wheel_locked(),
        player_controller.rear_wheel.global_position, player_controller.front_wheel.global_position,
        player_controller.global_rotation, true)


# =============================================================================
# TRICK DETECTION AND SCORING SYSTEM
# =============================================================================

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

    # Update boost trick score separately (boost stacks with other tricks)
    if player_controller.state.is_boosting:
        _update_boost_trick_score(delta)


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
    player_controller.state.trick_score += data.points_per_sec * delta * data.mult


func _get_difficulty_mult() -> float:
    """Returns the score multiplier for the current difficulty."""
    return DIFFICULTY_MULT.get(player_controller.state.difficulty, 1.0)


func _end_trick(trick: Trick):
    """Called when a trick ends - banks score and updates combo."""
    var data = TRICK_DATA[trick]
    var base_points = data.get("base_points", 0)
    var final_score = (player_controller.state.trick_score + base_points) * player_controller.state.combo_multiplier * _get_difficulty_mult()
    player_controller.state.total_score += final_score

    # Update combo
    player_controller.state.combo_count += 1
    player_controller.state.combo_multiplier = minf(
        player_controller.state.combo_multiplier + COMBO_INCREMENT, MAX_COMBO_MULT
    )
    _combo_timer = COMBO_WINDOW

    # Reset trick state
    player_controller.state.active_trick = Trick.NONE
    var duration = _trick_timer
    player_controller.state.trick_score = 0.0

    trick_ended.emit(trick, final_score, duration)


func _update_boost_trick_score(delta: float):
    """Updates boost trick score separately (boost is a modifier that stacks)."""
    var data = TRICK_DATA[Trick.BOOST]
    player_controller.state.boost_trick_score += data.points_per_sec * delta * data.mult


func _bank_boost_trick_score():
    """Banks boost trick score when boost ends."""
    var final_score = player_controller.state.boost_trick_score * player_controller.state.combo_multiplier * _get_difficulty_mult()
    player_controller.state.total_score += final_score

    # Update combo for boost ending
    if player_controller.state.boost_trick_score > 0:
        player_controller.state.combo_count += 1
        player_controller.state.combo_multiplier = minf(
            player_controller.state.combo_multiplier + COMBO_INCREMENT, MAX_COMBO_MULT
        )
        _combo_timer = COMBO_WINDOW

    player_controller.state.boost_trick_score = 0.0


func _update_combo_timer(delta: float):
    """Updates combo timer - resets combo when window expires."""
    if _combo_timer > 0:
        _combo_timer -= delta
        if _combo_timer <= 0:
            player_controller.state.combo_multiplier = 1.0
            player_controller.state.combo_count = 0
            combo_expired.emit()


func _on_crashed_signal(_pitch_direction: float, _lean_direction: float):
    """Signal handler for crashed signal - wraps _on_crashed."""
    _on_crashed()


func _on_crashed():
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


func get_current_trick_name() -> String:
    """Returns the display name of the current active trick."""
    var trick = player_controller.state.active_trick
    if trick == Trick.NONE:
        return ""
    return TRICK_DATA[trick].name


func handle_wheelie_stoppie(delta, rpm_ratio: float,
                             front_wheel_locked: bool = false, is_airborne: bool = false):
    # Airborne pitch control - free rotation with lean input
    if is_airborne:
        if abs(player_controller.bike_input.lean) > 0.1:
            var air_pitch_target = player_controller.bike_input.lean * max_wheelie_angle
            player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, air_pitch_target, rotation_speed * 1.5 * delta)
        return

    # Detect clutch dump
    var clutch_dump = last_clutch_input > 0.7 and player_controller.state.clutch_value < 0.3 and player_controller.bike_input.throttle > 0.5
    last_throttle_input = player_controller.bike_input.throttle
    last_clutch_input = player_controller.state.clutch_value

    # Can't START a wheelie/stoppie while turning, but can continue one
    var currently_in_wheelie = player_controller.state.pitch_angle > deg_to_rad(5)
    var currently_in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)
    var can_start_trick = not player_controller.bike_physics.is_turning()

    # Wheelie logic - wheelies scale with RPM above threshold
    var wheelie_target = 0.0
    var rpm_above_threshold = rpm_ratio >= wheelie_rpm_threshold
    var can_pop_wheelie = player_controller.bike_input.lean > 0.3 and player_controller.bike_input.throttle > 0.7 and (rpm_above_threshold or clutch_dump)

    # Calculate how much wheelie power based on where we are in the RPM range
    # 0 at threshold, 1 at full RPM
    var rpm_wheelie_factor = 0.0
    if rpm_ratio >= wheelie_rpm_threshold:
        rpm_wheelie_factor = clamp((rpm_ratio - wheelie_rpm_threshold) / (wheelie_rpm_full - wheelie_rpm_threshold), 0.0, 1.0)

    if player_controller.state.speed > 1 and (currently_in_wheelie or (can_pop_wheelie and can_start_trick)):
        if player_controller.bike_input.throttle > 0.3:
            # Wheelie intensity scales with both throttle AND rpm position in the power band
            wheelie_target = max_wheelie_angle * player_controller.bike_input.throttle * rpm_wheelie_factor
            wheelie_target += max_wheelie_angle * player_controller.bike_input.lean * 0.15

    # Stoppie logic - only works with progressive braking (not grabbed)
    # If front wheel is locked (brake grabbed), no stoppie - just skid
    var stoppie_target = 0.0
    if not front_wheel_locked:
        var wants_stoppie = player_controller.bike_input.lean < -0.1 and player_controller.bike_input.front_brake > 0.5
        if player_controller.state.speed > 1 and (currently_in_stoppie or (wants_stoppie and can_start_trick)):
            stoppie_target = - max_stoppie_angle * player_controller.bike_input.front_brake * (1.0 - player_controller.bike_input.throttle * 0.5)
            stoppie_target += -max_stoppie_angle * (-player_controller.bike_input.lean) * 0.15

    # Apply pitch
    var was_in_stoppie = player_controller.state.pitch_angle < deg_to_rad(-5)
    if wheelie_target > 0:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, wheelie_target, rotation_speed * delta)
    elif stoppie_target < 0:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, stoppie_target, rotation_speed * delta)
        if not was_in_stoppie:
            tire_screech_start.emit(skid_volume)
        # Check if bike stopped during stoppie - soft reset without position change
        if player_controller.state.speed < 0.5 and currently_in_stoppie:
            player_controller.state.pitch_angle = 0.0
            tire_screech_stop.emit()
            stoppie_stopped.emit()
    else:
        player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, 0, return_speed * delta)
        if was_in_stoppie and player_controller.state.pitch_angle >= deg_to_rad(-5):
            tire_screech_stop.emit()


func handle_skidding(delta, is_front_wheel_locked: bool, rear_wheel_position: Vector3,
                      front_wheel_position: Vector3, bike_rotation: Vector3, is_on_floor: bool):
    var is_rear_skidding = player_controller.bike_input.rear_brake > 0.5 and player_controller.state.speed > 2 and is_on_floor
    var is_front_skidding = is_front_wheel_locked and player_controller.state.speed > 2 and is_on_floor

    # Rear wheel skid
    if is_rear_skidding:
        skid_spawn_timer += delta
        if skid_spawn_timer >= SKID_SPAWN_INTERVAL:
            skid_spawn_timer = 0.0
            _spawn_skid_mark(rear_wheel_position, bike_rotation)

        # Fishtail calculation - steering induces fishtail direction
        var steer_influence = player_controller.state.steering_angle / player_controller.bike_physics.max_steering_angle
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
        if front_skid_spawn_timer >= SKID_SPAWN_INTERVAL:
            front_skid_spawn_timer = 0.0
            _spawn_skid_mark(front_wheel_position, bike_rotation)
        tire_screech_start.emit(skid_volume)
    else:
        front_skid_spawn_timer = 0.0

    # Tire screech for rear skid (only if not already screeching from front)
    if is_rear_skidding and not is_front_skidding:
        tire_screech_start.emit(skid_volume)


func get_fishtail_speed_loss(delta) -> float:
    """Returns how much speed to lose due to fishtail sliding"""
    if abs(player_controller.state.fishtail_angle) > 0.01:
        var slide_friction = abs(player_controller.state.fishtail_angle) / max_fishtail_angle
        return slide_friction * 15.0 * delta
    return 0.0


func is_in_wheelie() -> bool:
    return player_controller.state.pitch_angle > deg_to_rad(5)


func is_in_stoppie() -> bool:
    return player_controller.state.pitch_angle < deg_to_rad(-5)


func is_in_ground_trick() -> bool:
    """Returns true if doing any ground-based trick (wheelie, stoppie, fishtail)"""
    return abs(player_controller.state.pitch_angle) > deg_to_rad(5) or abs(player_controller.state.fishtail_angle) > deg_to_rad(5)


func is_in_air_trick(is_airborne: bool) -> bool:
    """Returns true if doing an air trick (pitch control while airborne)"""
    return is_airborne and abs(player_controller.state.pitch_angle) > deg_to_rad(5)


func force_pitch(target: float, rate: float, delta):
    """Force pitch toward a target (used by crash system)"""
    player_controller.state.pitch_angle = move_toward(player_controller.state.pitch_angle, target, rate * delta)


func get_fishtail_vibration() -> Vector2:
    """Returns vibration intensity (weak, strong) for fishtail skidding"""
    var fishtail_intensity = abs(player_controller.state.fishtail_angle) / max_fishtail_angle if max_fishtail_angle > 0 else 0.0
    if fishtail_intensity > 0.1:
        var weak = fishtail_intensity * 0.6
        var strong = fishtail_intensity * fishtail_intensity * 0.8
        return Vector2(weak, strong)
    return Vector2.ZERO

func _spawn_skid_mark(pos: Vector3, rot: Vector3):
    var decal = Decal.new()
    decal.texture_albedo = skidmark_texture
    decal.size = Vector3(0.15, 0.5, 0.4)
    decal.cull_mask = 1

    get_tree().current_scene.add_child(decal)

    decal.global_position = Vector3(pos.x, pos.y - 0.05, pos.z)
    decal.global_rotation = rot

    var timer = get_tree().create_timer(SKID_MARK_LIFETIME)
    timer.timeout.connect(func(): if is_instance_valid(decal): decal.queue_free())


func _on_force_stoppie_requested(target_pitch: float, rate: float):
    force_pitch(target_pitch, rate, current_delta)


func _on_trick_changed(btn_pressed: bool):
    """Handles trick button press - double-tap activates boost."""
    if not btn_pressed:
        return

    var current_time = Time.get_ticks_msec() / 1000.0
    var time_since_last = current_time - _last_trick_press_time

    # Double-tap detection for boost activation
    if time_since_last <= BOOST_DOUBLE_TAP_WINDOW and time_since_last > 0.05:
        # Double-tap detected - activate boost
        _activate_boost()
        _last_trick_press_time = 0.0  # Reset to prevent triple-tap
    else:
        # First tap - record time (single tap used for other trick actions)
        _last_trick_press_time = current_time


func _activate_boost():
    """Activates boost if available."""
    if player_controller.state.is_boosting:
        return
    if player_controller.state.boost_count <= 0:
        return

    player_controller.state.boost_count -= 1
    player_controller.state.is_boosting = true
    player_controller.state.boost_trick_score = 0.0  # Reset boost score
    boost_timer = boost_duration
    boost_started.emit()


func _update_boost(delta):
    if not player_controller.state.is_boosting:
        return

    boost_timer -= delta
    if boost_timer <= 0:
        player_controller.state.is_boosting = false
        _bank_boost_trick_score()  # Bank boost trick score when boost ends
        boost_ended.emit()


func _update_wheelie_distance(delta):
    if is_in_wheelie():
        wheelie_time_held += delta
        if wheelie_time_held >= wheelie_time_for_boost:
            wheelie_time_held -= wheelie_time_for_boost
            player_controller.state.boost_count += 1
            boost_earned.emit()
    else:
        wheelie_time_held = 0.0


func get_boosted_max_speed(base_max_speed: float) -> float:
    if player_controller.state.is_boosting:
        return base_max_speed * boost_speed_multiplier
    return base_max_speed


func get_boosted_throttle(base_throttle: float) -> float:
    if player_controller.state.is_boosting:
        return 1.0
    return base_throttle


func _on_stoppie_stopped():
    player_controller.bike_physics._bike_reset()
    player_controller.state.speed = 0.0
    player_controller.state.fall_angle = 0.0
    player_controller.velocity = Vector3.ZERO


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
