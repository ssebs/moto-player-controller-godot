class_name BikePhysics extends BikeComponent

# Local config (not in BikeResource)
@export var ground_align_speed: float = 10.0
@export var lean_to_steer_factor: float = 1.0
@export var gravity_mult: float = 2.0

# Local state
var br: BikeResource # Cached reference for brevity

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    player_controller.state.state_changed.connect(_on_player_state_changed)
    
    br = player_controller.bike_resource

func _bike_update(delta):
    # Note: player_controller will call apply_movement using the values from these _update funcs
    match player_controller.state.player_state:
        BikeState.PlayerState.IDLE, BikeState.PlayerState.RIDING, BikeState.PlayerState.TRICK_GROUND:
            _update_riding(delta)
        BikeState.PlayerState.AIRBORNE, BikeState.PlayerState.TRICK_AIR:
            _update_airborne(delta)
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            pass # Handled by crash system

func _bike_reset():
    player_controller.state.speed = 0.0
    player_controller.state.lean_angle = 0.0

#endregion

#region update based on state
func _update_riding(delta):
    _handle_acceleration(delta)
    _update_lean(delta)
    _handle_ground_alignment(delta)
    # _update_countersteering(delta)

func _update_airborne(delta):
    _update_lean(delta)
#endregion


# TODO: split into handle_acceleration & handle_deceleration
## replace_me
# Sets player_controller.state.speed
func _handle_acceleration(delta):
    var power_output: float = player_controller.bike_gearing.get_power_output()
    var gear_max_speed: float = player_controller.bike_gearing.get_max_speed_for_gear()
    var front_wheel_locked: bool = player_controller.bike_tricks.is_front_wheel_locked()
    
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


## Lean angle from player input. Lean directly controls both visual tilt and steering.
# Sets player_controller.state.lean_angle
func _update_lean(delta):
    var target_lean = player_controller.bike_input.steer * br.max_lean_angle_rad

    # Reduce lean during boost
    if player_controller.state.is_boosting:
        target_lean *= player_controller.bike_tricks.boost_steering_multiplier

    player_controller.state.lean_angle = lerpf(
        player_controller.state.lean_angle,
        target_lean,
        br.lean_speed * delta
    )

## replace_me
# Sets player_controller.state.lean_angle
func _update_countersteering(_delta):
    print("_update_countersteering does nothing atm")
    # if abs(player_controller.bike_input.steer) < 0.1 and player_controller.bike_input.throttle > 0.1:
    #     var stability = clamp(player_controller.state.speed / 20.0, 0.0, 1.0)
    #     player_controller.state.lean_angle = move_toward(
    #         player_controller.state.lean_angle,
    #         0,
    #         stability * br.lean_speed * delta
    #     )

## aligns the bike visually to slopes/ramps while riding.
func _handle_ground_alignment(delta):
    if player_controller.is_on_floor():
        var floor_normal = player_controller.get_floor_normal()
        var forward_dir = - player_controller.global_transform.basis.z
        var forward_dot = forward_dir.dot(floor_normal)
        var target_pitch = asin(clamp(forward_dot, -1.0, 1.0))
        player_controller.state.ground_pitch = lerp(player_controller.state.ground_pitch, target_pitch, ground_align_speed * delta)
    else:
        player_controller.state.ground_pitch = lerp(player_controller.state.ground_pitch, 0.0, ground_align_speed * 0.5 * delta)

## rotate / update speed if fishtailing
func _handle_fishtail(delta: float):
    if abs(player_controller.state.fishtail_angle) < 0.01:
        return

    # Fishtail rotation
    player_controller.rotate_y(player_controller.state.fishtail_angle * delta * 1.5)

    # Fishtail friction
    player_controller.state.speed = move_toward(player_controller.state.speed, 0, player_controller.bike_tricks.get_fishtail_speed_loss(delta))

## Reduce turn angle based on speed. Used in apply_movement
func _get_turn_rate() -> float:
    var speed_pct = player_controller.state.speed / br.max_speed
    var turn_radius = lerpf(br.min_turn_radius, br.max_turn_radius, speed_pct)
    return br.turn_speed / turn_radius


#region public funcs
func is_turning() -> bool:
    return abs(player_controller.state.lean_angle) > 0.2

## set velocity from state.speed
func apply_movement(delta):
    var forward = - player_controller.global_transform.basis.z

    if player_controller.state.speed > 0.5:
        # Lean directly controls turning
        player_controller.rotate_y(-player_controller.state.lean_angle * lean_to_steer_factor * _get_turn_rate() * delta)

        _handle_fishtail(delta)

    # Set movement velocity
    var old_vertical_velocity = player_controller.velocity.y
    # Move X/Z
    player_controller.velocity = forward * player_controller.state.speed
    # Move Y from prev val
    player_controller.velocity.y = old_vertical_velocity

    # Apply gravity
    if !player_controller.is_on_floor():
        player_controller.velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") * delta * gravity_mult

#endregion
