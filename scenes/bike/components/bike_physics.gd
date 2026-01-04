class_name BikePhysics extends Node

signal brake_stopped

# Shared state
var state: BikeState
var bike_input: BikeInput
var bike_gearing: BikeGearing
var bike_crash: BikeCrash
var bike_tricks: BikeTricks
var player: CharacterBody3D

# Movement tuning
@export var max_speed: float = 120.0
@export var acceleration: float = 12.0
@export var brake_strength: float = 20.0
@export var friction: float = 2.0
@export var engine_brake_strength: float = 12.0 # Max engine braking at high RPM

# Steering tuning
@export var steering_speed: float = 4.0
@export var max_steering_angle: float = deg_to_rad(35)
@export var max_lean_angle: float = deg_to_rad(45)
@export var lean_speed: float = 3.5

# Turn radius
@export var min_turn_radius: float = 0.25
@export var max_turn_radius: float = 3.0
@export var turn_speed: float = 2.0

# Fall physics
@export var fall_rate: float = 0.5 # How fast bike falls over at zero speed
@export var countersteer_factor: float = 1.2 # How much lean induces automatic steering

# Ground alignment
@export var ground_align_speed: float = 10.0

# Local state
var has_started_moving: bool = false

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _bike_setup(bike_state: BikeState, input: BikeInput, gearing: BikeGearing, crash: BikeCrash, tricks: BikeTricks, p_player: CharacterBody3D):
    state = bike_state
    bike_input = input
    bike_gearing = gearing
    bike_crash = crash
    bike_tricks = tricks
    player = p_player


func _bike_update(delta):
    match state.player_state:
        BikeState.PlayerState.IDLE:
            _update_idle(delta)
        BikeState.PlayerState.RIDING:
            _update_riding(delta)
        BikeState.PlayerState.AIRBORNE, BikeState.PlayerState.TRICK_AIR:
            _update_airborne(delta)
        BikeState.PlayerState.TRICK_GROUND:
            _update_trick_ground(delta)
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            pass  # Handled by crash system


func _update_idle(delta):
    # Keep bike stable at rest, handle braking to full stop
    state.fall_angle = move_toward(state.fall_angle, 0, fall_rate * 2.0 * delta)
    handle_acceleration(
        delta,
        bike_gearing.get_power_output(),
        bike_gearing.get_max_speed_for_gear(),
        bike_crash.is_front_wheel_locked()
    )
    align_to_ground(delta)


func _update_riding(delta):
    # Normal riding physics
    handle_acceleration(
        delta,
        bike_gearing.get_power_output(),
        bike_gearing.get_max_speed_for_gear(),
        bike_crash.is_front_wheel_locked()
    )
    handle_steering(delta)
    update_lean(delta)
    handle_fall_physics(delta)
    check_brake_stop()
    align_to_ground(delta)


func _update_airborne(delta):
    # In air - can shift weight but no ground physics
    update_lean(delta)
    # Gravity is handled in apply_movement()


func _update_trick_ground(delta):
    # Same as riding - wheelie/stoppie physics handled by BikeTricks
    _update_riding(delta)


func handle_acceleration(delta, power_output: float, gear_max_speed: float,
                           front_wheel_locked: bool = false):
    # Apply boost multiplier to max speed
    var effective_max_speed = bike_tricks.get_boosted_max_speed(gear_max_speed)

    # Braking
    if bike_input.front_brake > 0 or bike_input.rear_brake > 0:
        var front_effectiveness = 0.6 if front_wheel_locked else 1.0
        var rear_effectiveness = 0.6 if bike_input.rear_brake > 0.5 else 1.0
        var total_braking = clamp(bike_input.front_brake * front_effectiveness + bike_input.rear_brake * rear_effectiveness, 0, 1)
        state.speed = move_toward(state.speed, 0, brake_strength * total_braking * delta)

    if state.is_stalled:
        state.speed = move_toward(state.speed, 0, friction * delta)
        return

    # Acceleration
    if power_output > 0:
        if state.speed < effective_max_speed:
            state.speed += acceleration * power_output * delta
            state.speed = min(state.speed, effective_max_speed)
        else:
            state.speed = move_toward(state.speed, effective_max_speed, friction * 2.0 * delta)

    # Engine braking when coasting (includes friction + RPM-based drag)
    if bike_input.throttle == 0 and bike_input.front_brake == 0 and bike_input.rear_brake == 0:
        var clutch_engagement = bike_gearing.get_clutch_engagement()
        var rpm_ratio = state.rpm_ratio
        # Clutch engaged: friction + RPM-based engine braking
        # Clutch disengaged: reduced friction only (freewheeling)
        var drag = friction * (0.5 + clutch_engagement * 0.5) + engine_brake_strength * rpm_ratio * clutch_engagement
        state.speed = move_toward(state.speed, 0, drag * delta)


func handle_fall_physics(delta):
    """
    Fall physics with speed-based stability curve:
    - Below stability_speed: bike falls over (low speed wobble)
    - Between stability_speed and high_speed_instability_start: stable zone
    - Above high_speed_instability_start: high speed wobble begins
    """
    if state.speed > 0.25:
        has_started_moving = true

    if !has_started_moving:
        state.fall_angle = 0.0
        return

    # pull upright if speed increases
    state.fall_angle = move_toward(state.fall_angle, 0, fall_rate * 2.0 * delta)

func apply_fishtail_friction(_delta, fishtail_speed_loss: float):
    state.speed = move_toward(state.speed, 0, fishtail_speed_loss)


func check_brake_stop():
    if !state:
        return

    var is_upright = abs(state.lean_angle + state.fall_angle) < deg_to_rad(15)
    var is_straight = abs(state.steering_angle) < deg_to_rad(10)

    var total_brake = clamp(bike_input.front_brake + bike_input.rear_brake, 0.0, 1.0)
    if state.speed < 0.5 and total_brake > 0.3 and is_upright and is_straight and has_started_moving:
        state.speed = 0.0
        state.fall_angle = 0.0
        has_started_moving = false
        brake_stopped.emit()


func apply_gravity(delta, velocity: Vector3, is_on_floor: bool) -> Vector3:
    if !is_on_floor:
        velocity.y -= gravity * delta
    return velocity


func handle_steering(delta):
    """
    Countersteering: lean angle induces automatic steering in that direction.
    When you lean right, the bike naturally steers right (turns into the lean).
    Steering radius depends on lean angle and speed.
    Releasing steer while on throttle straightens the bike.
    """
    # If no steer input and throttle is applied, straighten out
    if abs(bike_input.steer) < 0.1 and bike_input.throttle > 0.1:
        state.steering_angle = lerpf(state.steering_angle, 0, steering_speed * delta)
        return

    # Total lean (visual lean + fall) drives automatic countersteer
    var total_lean = state.lean_angle + state.fall_angle

    # Countersteer: lean induces steering in same direction
    # More lean = tighter turn radius (more steering)
    var lean_induced_steer = - total_lean * countersteer_factor

    # Player input adds to the automatic countersteer
    var input_steer = max_steering_angle * bike_input.steer

    # At higher speeds, countersteer effect is stronger (bike turns more from lean)
    var speed_factor = clamp(state.speed / 20.0, 0.3, 1.0)
    var target_steer = clamp(input_steer + lean_induced_steer * speed_factor, -max_steering_angle, max_steering_angle)

    # Smooth interpolation to target
    state.steering_angle = lerpf(state.steering_angle, target_steer, steering_speed * delta)


func update_lean(delta):
    """
    Visual lean angle based on steering and player input.
    Fall angle is added separately in mesh rotation.
    """
    # Lean from steering (centripetal force in turns)
    var speed_factor = clamp(state.speed / 20.0, 0.0, 1.0)
    var steer_lean = - state.steering_angle * speed_factor * 1.2

    # Direct player lean input
    var input_lean = - bike_input.steer * max_lean_angle * 0.3

    var target_lean = steer_lean + input_lean
    target_lean = clamp(target_lean, -max_lean_angle, max_lean_angle)

    # Smooth interpolation
    state.lean_angle = lerpf(state.lean_angle, target_lean, lean_speed * delta)


func get_turn_rate() -> float:
    var speed_pct = state.speed / max_speed
    var turn_radius = lerpf(min_turn_radius, max_turn_radius, speed_pct)
    return turn_speed / turn_radius


func is_turning() -> bool:
    return abs(state.steering_angle) > 0.2


func align_to_ground(delta):
    if player.is_on_floor():
        var floor_normal = player.get_floor_normal()
        var forward_dir = -player.global_transform.basis.z
        var forward_dot = forward_dir.dot(floor_normal)
        var target_pitch = asin(clamp(forward_dot, -1.0, 1.0))
        state.ground_pitch = lerp(state.ground_pitch, target_pitch, ground_align_speed * delta)
    else:
        state.ground_pitch = lerp(state.ground_pitch, 0.0, ground_align_speed * 0.5 * delta)


func apply_movement(delta):
    var forward = -player.global_transform.basis.z

    if state.speed > 0.5:
        var turn_rate = get_turn_rate()
        player.rotate_y(-state.steering_angle * turn_rate * delta)

        if abs(state.fishtail_angle) > 0.01:
            player.rotate_y(state.fishtail_angle * delta * 1.5)
            apply_fishtail_friction(delta, bike_tricks.get_fishtail_speed_loss(delta))

    var vertical_velocity = player.velocity.y
    player.velocity = forward * state.speed
    player.velocity.y = vertical_velocity
    player.velocity = apply_gravity(delta, player.velocity, player.is_on_floor())


func _bike_reset():
    state.speed = 0.0
    state.fall_angle = 0.0
    has_started_moving = false
    state.steering_angle = 0.0
    state.lean_angle = 0.0
