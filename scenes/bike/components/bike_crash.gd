class_name BikeCrash extends BikeComponent

signal crashed
signal respawn_requested
signal respawned

# Crash thresholds
@export var crash_wheelie_threshold: float = deg_to_rad(75)
@export var crash_stoppie_threshold: float = deg_to_rad(55)
@export var crash_lean_threshold: float = deg_to_rad(80)
@export var respawn_delay: float = 5.0

# Crash physics
@export var crash_deceleration: float = 20.0
@export var crash_rotation_speed: float = 3.0

# Brake/grip system
@export var brake_grab_time_threshold: float = 0.4 # seconds, 0→100% - quick grab locks wheel
@export var brake_lean_sensitivity: float = 0.7 # how much lean reduces safe brake amount

# Local state
var crash_timer: float = 0.0
var crash_pitch_direction: float = 0.0
var crash_lean_direction: float = 0.0
var _ragdoll_stopped: bool = false
var _ragdoll_stop_time: float = 0.0

#region Brake Grab Detection
var _brake_grab_timer: float = 0.0
var _brake_was_zero: bool = true
var _brake_was_grabbed: bool = false
#endregion

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    player_controller.state.state_changed.connect(_on_player_state_changed)

    switch_to_riding_camera()

func _bike_update(delta):
    match player_controller.state.player_state:
        BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED:
            _update_crash_state(delta)
        BikeState.PlayerState.RIDING, BikeState.PlayerState.TRICK_GROUND:
            _update_grip(delta)
            _check_crash_conditions()
            _check_collision_crash()
        BikeState.PlayerState.AIRBORNE, BikeState.PlayerState.TRICK_AIR:
            _check_collision_crash()

    
func _bike_reset():
    crash_timer = 0.0
    crash_pitch_direction = 0.0
    crash_lean_direction = 0.0
    _ragdoll_stopped = false
    _ragdoll_stop_time = 0.0
    _brake_grab_timer = 0.0
    _brake_was_zero = true
    _brake_was_grabbed = false
    player_controller.state.grip_usage = 0.0
    switch_to_riding_camera()
    respawned.emit()

#endregion

#region Brake Grab Detection

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
            trigger_crash()
        elif not _brake_was_grabbed and is_turning and front_brake > max_safe_brake:
            trigger_crash()


## Returns true if front brake was grabbed causing wheel lock.
func is_front_wheel_locked() -> bool:
    if player_controller.state.isEasyDifficulty():
        return false
    return _brake_was_grabbed

#endregion

func _update_crash_state(delta):
    crash_timer += delta

    if Input.is_action_just_pressed("pause"):
        _do_respawn()
        return
    
    _update_ragdoll(delta)
    
    # TODO: bike crash physics

## Checks pitch/lean angles for crash thresholds. Calls trigger_crash()
func _check_crash_conditions():
    if player_controller.state.pitch_angle > crash_wheelie_threshold:
        trigger_crash()
        return

    if player_controller.state.pitch_angle < -crash_stoppie_threshold:
        trigger_crash()
        return

    if player_controller.state.pitch_angle < deg_to_rad(-15) and abs(player_controller.state.lean_angle) > deg_to_rad(15):
        trigger_crash()
        return

    if abs(player_controller.state.lean_angle) >= crash_lean_threshold:
        trigger_crash()

## Checks slide collisions for crash layer (layer 2) and triggers collision crash.
func _check_collision_crash():
    if player_controller.state.player_state in [BikeState.PlayerState.CRASHING, BikeState.PlayerState.CRASHED]:
        return

    for i in player_controller.get_slide_collision_count():
        var collision = player_controller.get_slide_collision(i)
        var collider = collision.get_collider()

        var is_crash_layer = false
        if collider is CollisionObject3D:
            is_crash_layer = collider.get_collision_layer_value(2)
        elif collider is CSGShape3D and collider.use_collision:
            is_crash_layer = (collider.collision_layer & 2) != 0

        if is_crash_layer and player_controller.state.speed > 5:
            var normal = collision.get_normal()
            var local_normal = player_controller.global_transform.basis.inverse() * normal
            trigger_collision_crash(local_normal)
            return

## Triggers crash from obstacle collision. Direction derived from collision normal.
func trigger_collision_crash(local_normal: Vector3):
    if local_normal.z > 0.5:
        crash_pitch_direction = -1
        crash_lean_direction = 0
    elif abs(local_normal.x) > 0.3:
        crash_pitch_direction = 0
        crash_lean_direction = sign(local_normal.x)
    else:
        crash_pitch_direction = -1
        crash_lean_direction = 0

    _do_crash()


func _update_ragdoll(delta):
    if not player_controller.character_mesh.is_ragdoll:
        player_controller.character_mesh.start_ragdoll(player_controller.velocity, 0.5)
    switch_to_crash_camera()

    # Smoothly follow ragdoll hips position
    var hips_bone = player_controller.character_mesh.ragdoll_bones.get_node("Physical Bone mixamorig6_Hips")
    if hips_bone:
        var target_pos = hips_bone.global_position + Vector3(0, 2, 3)
        player_controller.crash_cam_position.global_position = player_controller.crash_cam_position.global_position.lerp(target_pos, 5.0 * delta)
        player_controller.crash_cam_position.look_at(hips_bone.global_position)


    # Respawn once ragdoll speed drops below 1 (with minimum time to let physics settle)
    if hips_bone:
        var ragdoll_velocity = hips_bone.linear_velocity
        var ragdoll_speed = ragdoll_velocity.length()

        # Wait for ragdoll to slow down, then wait 1 more second before respawning
        if crash_timer > 1.0 and ragdoll_speed < 1.0:
            # Track time since ragdoll stopped
            if not _ragdoll_stopped:
                _ragdoll_stopped = true
                _ragdoll_stop_time = crash_timer
            elif crash_timer - _ragdoll_stop_time >= 1.0:
                _do_respawn()
        else:
            _ragdoll_stopped = false

    # Force respawn after respawn_delay regardless of ragdoll state
    if crash_timer >= respawn_delay:
        _do_respawn()

func _do_respawn():
    player_controller.state.request_state_change(BikeState.PlayerState.CRASHED)
    player_controller.character_mesh.stop_ragdoll()
    var reset_anim = "RESET"
    if player_controller.bike_resource:
        reset_anim = player_controller.bike_resource.animation_library_name + "/RESET"
    player_controller.anim_player.play(reset_anim)
    respawn_requested.emit()


#region public funcs

## Triggers crash from physics state. Direction derived from pitch/lean angles.
func trigger_crash():
    if abs(player_controller.state.pitch_angle) > abs(player_controller.state.lean_angle):
        crash_pitch_direction = sign(player_controller.state.pitch_angle)
        crash_lean_direction = 0
    else:
        crash_pitch_direction = 0
        crash_lean_direction = sign(player_controller.state.lean_angle)

    _do_crash()

## Common crash logic. Emits crashed signal.
func _do_crash():
    player_controller.state.request_state_change(BikeState.PlayerState.CRASHING)
    crash_timer = 0.0

    if crash_lean_direction != 0 and crash_pitch_direction == 0:
        player_controller.state.speed *= 0.7

    crashed.emit()

func switch_to_crash_camera():
    player_controller.crashing_camera.make_current()

func switch_to_riding_camera():
    player_controller.riding_camera.make_current()

#endregion
