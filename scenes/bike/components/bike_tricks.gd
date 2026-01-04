class_name BikeTricks extends Node

signal tire_screech_start(volume: float)
signal tire_screech_stop
signal stoppie_stopped # Emitted when bike comes to rest during a stoppie
signal boost_started
signal boost_ended
signal boost_earned # Emitted when a boost is earned from tricks

# Shared state
var state: BikeState
var bike_input: BikeInput
var bike_physics: BikePhysics
var bike_gearing: BikeGearing
var bike_crash: BikeCrash
var controller: CharacterBody3D
var rear_wheel_marker: Marker3D
var front_wheel_marker: Marker3D

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
@export var skidmark_texture = preload("res://assets/skidmarktex.png")
@export var skid_volume: float = 0.5

# Boost tuning
@export var boost_speed_multiplier: float = 1.5
@export var boost_duration: float = 2.0
@export var starting_boosts: int = 2
@export var wheelie_time_for_boost: float = 5.0 # seconds

# Boost state
var boost_timer: float = 0.0
var wheelie_time_held: float = 0.0

const SKID_SPAWN_INTERVAL: float = 0.025
const SKID_MARK_LIFETIME: float = 5.0
var skid_spawn_timer: float = 0.0
var front_skid_spawn_timer: float = 0.0

# Input tracking for clutch dump detection
var last_throttle_input: float = 0.0
var last_clutch_input: float = 0.0

# Frame delta for signal handlers
var current_delta: float = 0.0


func _bike_setup(bike_state: BikeState, input: BikeInput, physics: BikePhysics,
        gearing: BikeGearing, crash: BikeCrash, ctrl: CharacterBody3D,
        rear_wheel: Marker3D, front_wheel: Marker3D):
    state = bike_state
    bike_input = input
    bike_physics = physics
    bike_gearing = gearing
    bike_crash = crash
    controller = ctrl
    rear_wheel_marker = rear_wheel
    front_wheel_marker = front_wheel

    bike_input.trick_changed.connect(_on_trick_changed)
    bike_crash.force_stoppie_requested.connect(_on_force_stoppie_requested)

func _bike_update(delta):
    current_delta = delta
    _update_boost(delta)

    match state.player_state:
        BikeState.PlayerState.IDLE:
            pass  # No trick updates when idle
        BikeState.PlayerState.RIDING:
            _update_riding(delta)
        BikeState.PlayerState.AIRBORNE:
            _update_airborne(delta)
        BikeState.PlayerState.TRICK_AIR:
            _update_trick_air(delta)
        BikeState.PlayerState.TRICK_GROUND:
            _update_trick_ground(delta)
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            pass  # Handled by crash system


func _update_riding(delta):
    # Check for skidding, can initiate ground tricks
    _update_wheelie_distance(delta)
    handle_wheelie_stoppie(delta, state.rpm_ratio, bike_crash.is_front_wheel_locked(), false)
    handle_skidding(delta, bike_crash.is_front_wheel_locked(),
        rear_wheel_marker.global_position, front_wheel_marker.global_position,
        controller.global_rotation, true)


func _update_airborne(delta):
    # Can initiate air tricks with pitch control
    handle_wheelie_stoppie(delta, state.rpm_ratio, false, true)


func _update_trick_air(delta):
    # Actively controlling pitch in air
    _update_wheelie_distance(delta)
    handle_wheelie_stoppie(delta, state.rpm_ratio, false, true)


func _update_trick_ground(delta):
    # Wheelie/stoppie/fishtail active
    _update_wheelie_distance(delta)
    handle_wheelie_stoppie(delta, state.rpm_ratio, bike_crash.is_front_wheel_locked(), false)
    handle_skidding(delta, bike_crash.is_front_wheel_locked(),
        rear_wheel_marker.global_position, front_wheel_marker.global_position,
        controller.global_rotation, true)

func handle_wheelie_stoppie(delta, rpm_ratio: float,
                             front_wheel_locked: bool = false, is_airborne: bool = false):
    # Airborne pitch control - free rotation with lean input
    if is_airborne:
        if abs(bike_input.lean) > 0.1:
            var air_pitch_target = bike_input.lean * max_wheelie_angle
            state.pitch_angle = move_toward(state.pitch_angle, air_pitch_target, rotation_speed * 1.5 * delta)
        return

    # Detect clutch dump
    var clutch_dump = last_clutch_input > 0.7 and state.clutch_value < 0.3 and bike_input.throttle > 0.5
    last_throttle_input = bike_input.throttle
    last_clutch_input = state.clutch_value

    # Can't START a wheelie/stoppie while turning, but can continue one
    var currently_in_wheelie = state.pitch_angle > deg_to_rad(5)
    var currently_in_stoppie = state.pitch_angle < deg_to_rad(-5)
    var can_start_trick = not bike_physics.is_turning()

    # Wheelie logic - wheelies scale with RPM above threshold
    var wheelie_target = 0.0
    var rpm_above_threshold = rpm_ratio >= wheelie_rpm_threshold
    var can_pop_wheelie = bike_input.lean > 0.3 and bike_input.throttle > 0.7 and (rpm_above_threshold or clutch_dump)

    # Calculate how much wheelie power based on where we are in the RPM range
    # 0 at threshold, 1 at full RPM
    var rpm_wheelie_factor = 0.0
    if rpm_ratio >= wheelie_rpm_threshold:
        rpm_wheelie_factor = clamp((rpm_ratio - wheelie_rpm_threshold) / (wheelie_rpm_full - wheelie_rpm_threshold), 0.0, 1.0)

    if state.speed > 1 and (currently_in_wheelie or (can_pop_wheelie and can_start_trick)):
        if bike_input.throttle > 0.3:
            # Wheelie intensity scales with both throttle AND rpm position in the power band
            wheelie_target = max_wheelie_angle * bike_input.throttle * rpm_wheelie_factor
            wheelie_target += max_wheelie_angle * bike_input.lean * 0.15

    # Stoppie logic - only works with progressive braking (not grabbed)
    # If front wheel is locked (brake grabbed), no stoppie - just skid
    var stoppie_target = 0.0
    if not front_wheel_locked:
        var wants_stoppie = bike_input.lean < -0.1 and bike_input.front_brake > 0.5
        if state.speed > 1 and (currently_in_stoppie or (wants_stoppie and can_start_trick)):
            stoppie_target = - max_stoppie_angle * bike_input.front_brake * (1.0 - bike_input.throttle * 0.5)
            stoppie_target += -max_stoppie_angle * (-bike_input.lean) * 0.15

    # Apply pitch
    var was_in_stoppie = state.pitch_angle < deg_to_rad(-5)
    if wheelie_target > 0:
        state.pitch_angle = move_toward(state.pitch_angle, wheelie_target, rotation_speed * delta)
    elif stoppie_target < 0:
        state.pitch_angle = move_toward(state.pitch_angle, stoppie_target, rotation_speed * delta)
        if not was_in_stoppie:
            tire_screech_start.emit(skid_volume)
        # Check if bike stopped during stoppie - soft reset without position change
        if state.speed < 0.5 and currently_in_stoppie:
            state.pitch_angle = 0.0
            tire_screech_stop.emit()
            stoppie_stopped.emit()
    else:
        state.pitch_angle = move_toward(state.pitch_angle, 0, return_speed * delta)
        if was_in_stoppie and state.pitch_angle >= deg_to_rad(-5):
            tire_screech_stop.emit()


func handle_skidding(delta, is_front_wheel_locked: bool, rear_wheel_position: Vector3,
                      front_wheel_position: Vector3, bike_rotation: Vector3, is_on_floor: bool):
    var is_rear_skidding = bike_input.rear_brake > 0.5 and state.speed > 2 and is_on_floor
    var is_front_skidding = is_front_wheel_locked and state.speed > 2 and is_on_floor

    # Rear wheel skid
    if is_rear_skidding:
        skid_spawn_timer += delta
        if skid_spawn_timer >= SKID_SPAWN_INTERVAL:
            skid_spawn_timer = 0.0
            _spawn_skid_mark(rear_wheel_position, bike_rotation)

        # Fishtail calculation - steering induces fishtail direction
        var steer_influence = state.steering_angle / bike_physics.max_steering_angle
        var target_fishtail = - steer_influence * max_fishtail_angle * bike_input.rear_brake

        # Small natural wobble when skidding straight (random direction, small amplitude)
        if abs(steer_influence) < 0.1:
            var wobble_direction = 1.0 if state.fishtail_angle >= 0 else -1.0
            if abs(state.fishtail_angle) < deg_to_rad(2):
                wobble_direction = [-1.0, 1.0][randi() % 2]
            target_fishtail = wobble_direction * deg_to_rad(8) * bike_input.rear_brake

        var speed_factor = clamp(state.speed / 20.0, 0.5, 1.5)
        target_fishtail *= speed_factor

        if abs(state.fishtail_angle) > deg_to_rad(15):
            target_fishtail *= 1.1 # Amplify once sliding

        state.fishtail_angle = move_toward(state.fishtail_angle, target_fishtail, fishtail_speed * delta)
    else:
        skid_spawn_timer = 0.0
        state.fishtail_angle = move_toward(state.fishtail_angle, 0, fishtail_recovery_speed * delta)

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
    if abs(state.fishtail_angle) > 0.01:
        var slide_friction = abs(state.fishtail_angle) / max_fishtail_angle
        return slide_friction * 15.0 * delta
    return 0.0


func is_in_wheelie() -> bool:
    return state.pitch_angle > deg_to_rad(5)


func is_in_stoppie() -> bool:
    return state.pitch_angle < deg_to_rad(-5)


func is_in_ground_trick() -> bool:
    """Returns true if doing any ground-based trick (wheelie, stoppie, fishtail)"""
    return abs(state.pitch_angle) > deg_to_rad(5) or abs(state.fishtail_angle) > deg_to_rad(5)


func is_in_air_trick(is_airborne: bool) -> bool:
    """Returns true if doing an air trick (pitch control while airborne)"""
    return is_airborne and abs(state.pitch_angle) > deg_to_rad(5)


func force_pitch(target: float, rate: float, delta):
    """Force pitch toward a target (used by crash system)"""
    state.pitch_angle = move_toward(state.pitch_angle, target, rate * delta)


func get_fishtail_vibration() -> Vector2:
    """Returns vibration intensity (weak, strong) for fishtail skidding"""
    var fishtail_intensity = abs(state.fishtail_angle) / max_fishtail_angle if max_fishtail_angle > 0 else 0.0
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
    if not btn_pressed:
        return
    if state.is_boosting:
        return
    if state.boost_count <= 0:
        return

    state.boost_count -= 1
    state.is_boosting = true
    boost_timer = boost_duration
    boost_started.emit()


func _update_boost(delta):
    if not state.is_boosting:
        return

    boost_timer -= delta
    if boost_timer <= 0:
        state.is_boosting = false
        boost_ended.emit()


func _update_wheelie_distance(delta):
    if is_in_wheelie():
        wheelie_time_held += delta
        if wheelie_time_held >= wheelie_time_for_boost:
            wheelie_time_held -= wheelie_time_for_boost
            state.boost_count += 1
            boost_earned.emit()
    else:
        wheelie_time_held = 0.0


func get_boosted_max_speed(base_max_speed: float) -> float:
    if state.is_boosting:
        return base_max_speed * boost_speed_multiplier
    return base_max_speed


func get_boosted_throttle(base_throttle: float) -> float:
    if state.is_boosting:
        return 1.0
    return base_throttle


func _bike_reset():
    state.pitch_angle = 0.0
    state.fishtail_angle = 0.0
    state.is_boosting = false
    state.boost_count = starting_boosts
    boost_timer = 0.0
    wheelie_time_held = 0.0
    skid_spawn_timer = 0.0
    front_skid_spawn_timer = 0.0
    last_throttle_input = 0.0
    last_clutch_input = 0.0
