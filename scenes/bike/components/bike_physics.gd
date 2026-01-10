class_name BikePhysics extends BikeComponent

signal brake_stopped

# Local config (not in BikeResource)
@export var ground_align_speed: float = 10.0

# Local state
var has_started_moving: bool = false

# Gravity
var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

    brake_stopped.connect(_on_brake_stopped)


func _bike_update(delta):
    match player_controller.state.player_state:
        BikeState.PlayerState.IDLE:
            _update_idle(delta)
        BikeState.PlayerState.RIDING:
            _update_riding(delta)
        BikeState.PlayerState.AIRBORNE, BikeState.PlayerState.TRICK_AIR:
            _update_airborne(delta)
        BikeState.PlayerState.TRICK_GROUND:
            _update_trick_ground(delta)
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            pass # Handled by crash system


func _update_idle(delta):
    # Keep bike stable at rest, handle braking to full stop
    player_controller.state.fall_angle = move_toward(player_controller.state.fall_angle, 0, player_controller.bike_resource.fall_rate * 2.0 * delta)
    handle_acceleration(
        delta,
        player_controller.bike_gearing.get_power_output(),
        player_controller.bike_gearing.get_max_speed_for_gear(),
        player_controller.bike_tricks.is_front_wheel_locked()
    )
    align_to_ground(delta)


func _update_riding(delta):
    # Normal riding physics
    handle_acceleration(
        delta,
        player_controller.bike_gearing.get_power_output(),
        player_controller.bike_gearing.get_max_speed_for_gear(),
        player_controller.bike_tricks.is_front_wheel_locked()
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
    var br := player_controller.bike_resource
    # Apply boost multiplier to max speed
    var effective_max_speed = player_controller.bike_tricks.get_boosted_max_speed(gear_max_speed)

    # Braking
    if player_controller.bike_input.front_brake > 0 or player_controller.bike_input.rear_brake > 0:
        var front_effectiveness = 0.6 if front_wheel_locked else 1.0
        var rear_effectiveness = 0.6 if player_controller.bike_input.rear_brake > 0.5 else 1.0
        var total_braking = clamp(player_controller.bike_input.front_brake * front_effectiveness + player_controller.bike_input.rear_brake * rear_effectiveness, 0, 1)
        player_controller.state.speed = move_toward(player_controller.state.speed, 0, br.brake_strength * total_braking * delta)

    if player_controller.state.is_stalled:
        player_controller.state.speed = move_toward(player_controller.state.speed, 0, br.friction * delta)
        return

    # Acceleration
    if power_output > 0:
        if player_controller.state.speed < effective_max_speed:
            player_controller.state.speed += br.acceleration * power_output * delta
            player_controller.state.speed = min(player_controller.state.speed, effective_max_speed)
        else:
            player_controller.state.speed = move_toward(player_controller.state.speed, effective_max_speed, br.friction * 2.0 * delta)

    # Engine braking when coasting (includes friction + RPM-based drag)
    if player_controller.bike_input.throttle == 0 and player_controller.bike_input.front_brake == 0 and player_controller.bike_input.rear_brake == 0:
        var clutch_engagement = player_controller.bike_gearing.get_clutch_engagement()
        var rpm_ratio = player_controller.state.rpm_ratio
        # Clutch engaged: friction + RPM-based engine braking
        # Clutch disengaged: reduced friction only (freewheeling)
        var drag = br.friction * (0.5 + clutch_engagement * 0.5) + br.engine_brake_strength * rpm_ratio * clutch_engagement
        player_controller.state.speed = move_toward(player_controller.state.speed, 0, drag * delta)


func handle_fall_physics(delta):
    """
    Fall physics with speed-based stability curve:
    - Below stability_speed: bike falls over (low speed wobble)
    - Between stability_speed and high_speed_instability_start: stable zone
    - Above high_speed_instability_start: high speed wobble begins
    """
    if player_controller.state.speed > 0.25:
        has_started_moving = true

    if !has_started_moving:
        player_controller.state.fall_angle = 0.0
        return

    # pull upright if speed increases
    player_controller.state.fall_angle = move_toward(player_controller.state.fall_angle, 0, player_controller.bike_resource.fall_rate * 2.0 * delta)

func apply_fishtail_friction(_delta, fishtail_speed_loss: float):
    player_controller.state.speed = move_toward(player_controller.state.speed, 0, fishtail_speed_loss)


func check_brake_stop():
    if !player_controller.state:
        return

    var is_upright = abs(player_controller.state.lean_angle + player_controller.state.fall_angle) < deg_to_rad(15)
    var is_straight = abs(player_controller.state.steering_angle) < deg_to_rad(10)

    var total_brake = clamp(player_controller.bike_input.front_brake + player_controller.bike_input.rear_brake, 0.0, 1.0)
    if player_controller.state.speed < 0.5 and total_brake > 0.3 and is_upright and is_straight and has_started_moving:
        player_controller.state.speed = 0.0
        player_controller.state.fall_angle = 0.0
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
    var br := player_controller.bike_resource
    # If no steer input and throttle is applied, straighten out
    if abs(player_controller.bike_input.steer) < 0.1 and player_controller.bike_input.throttle > 0.1:
        player_controller.state.steering_angle = lerpf(player_controller.state.steering_angle, 0, br.steering_speed * delta)
        return

    # Total lean (visual lean + fall) drives automatic countersteer
    var total_lean = player_controller.state.lean_angle + player_controller.state.fall_angle

    # Countersteer: lean induces steering in same direction
    # More lean = tighter turn radius (more steering)
    var lean_induced_steer = - total_lean * br.countersteer_factor
    if player_controller.state.difficulty == player_controller.state.PlayerDifficulty.EASY:
        lean_induced_steer = 0

    # Player input adds to the automatic countersteer
    var input_steer = br.max_steering_angle_rad * player_controller.bike_input.steer

    # At higher speeds, countersteer effect is stronger (bike turns more from lean)
    var speed_factor = clamp(player_controller.state.speed / 20.0, 0.3, 1.0)
    var target_steer = clamp(input_steer + lean_induced_steer * speed_factor, -br.max_steering_angle_rad, br.max_steering_angle_rad)

    # Reduce steering during boost
    if player_controller.state.is_boosting:
        target_steer *= player_controller.bike_tricks.boost_steering_multiplier

    # Smooth interpolation to target
    player_controller.state.steering_angle = lerpf(player_controller.state.steering_angle, target_steer, br.steering_speed * delta)


func update_lean(delta):
    """
    Visual lean angle based on steering and player input.
    Fall angle is added separately in mesh rotation.
    """
    var br := player_controller.bike_resource
    # Lean from steering (centripetal force in turns)
    var speed_factor = clamp(player_controller.state.speed / 20.0, 0.0, 1.0)
    var steer_lean = - player_controller.state.steering_angle * speed_factor * 1.2

    # Direct player lean input
    var input_lean = - player_controller.bike_input.steer * br.max_lean_angle_rad * 0.3

    var target_lean = steer_lean + input_lean
    target_lean = clamp(target_lean, -br.max_lean_angle_rad, br.max_lean_angle_rad)

    # Smooth interpolation
    player_controller.state.lean_angle = lerpf(player_controller.state.lean_angle, target_lean, br.lean_speed * delta)


func get_turn_rate() -> float:
    var br := player_controller.bike_resource
    var speed_pct = player_controller.state.speed / br.max_speed
    var turn_radius = lerpf(br.min_turn_radius, br.max_turn_radius, speed_pct)
    return br.turn_speed / turn_radius


func is_turning() -> bool:
    return abs(player_controller.state.steering_angle) > 0.2


func align_to_ground(delta):
    if player_controller.is_on_floor():
        var floor_normal = player_controller.get_floor_normal()
        var forward_dir = - player_controller.global_transform.basis.z
        var forward_dot = forward_dir.dot(floor_normal)
        var target_pitch = asin(clamp(forward_dot, -1.0, 1.0))
        player_controller.state.ground_pitch = lerp(player_controller.state.ground_pitch, target_pitch, ground_align_speed * delta)
    else:
        player_controller.state.ground_pitch = lerp(player_controller.state.ground_pitch, 0.0, ground_align_speed * 0.5 * delta)


func apply_movement(delta):
    var forward = - player_controller.global_transform.basis.z

    if player_controller.state.speed > 0.5:
        var turn_rate = get_turn_rate()
        player_controller.rotate_y(-player_controller.state.steering_angle * turn_rate * delta)

        if abs(player_controller.state.fishtail_angle) > 0.01:
            player_controller.rotate_y(player_controller.state.fishtail_angle * delta * 1.5)
            apply_fishtail_friction(delta, player_controller.bike_tricks.get_fishtail_speed_loss(delta))

    var vertical_velocity = player_controller.velocity.y
    player_controller.velocity = forward * player_controller.state.speed
    player_controller.velocity.y = vertical_velocity
    player_controller.velocity = apply_gravity(delta, player_controller.velocity, player_controller.is_on_floor())


func _on_brake_stopped():
    _bike_reset()
    player_controller.velocity = Vector3.ZERO


func _bike_reset():
    player_controller.state.speed = 0.0
    player_controller.state.fall_angle = 0.0
    has_started_moving = false
    player_controller.state.steering_angle = 0.0
    player_controller.state.lean_angle = 0.0
