class_name BikeCrash extends BikeComponent

signal crashed(pitch_direction: float, lean_direction: float)
signal respawn_requested
signal respawned

# Crash thresholds
@export var crash_wheelie_threshold: float = deg_to_rad(75)
@export var crash_stoppie_threshold: float = deg_to_rad(55)
@export var crash_lean_threshold: float = deg_to_rad(80)
@export var respawn_delay: float = 10.0

# Crash physics
@export var crash_deceleration: float = 20.0
@export var crash_rotation_speed: float = 3.0

# Local state
var crash_timer: float = 0.0
var crash_pitch_direction: float = 0.0
var crash_lean_direction: float = 0.0
var _ragdoll_stopped: bool = false
var _ragdoll_stop_time: float = 0.0


func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

    _switch_to_riding_camera()


func _bike_update(delta):
    if player_controller.state.player_state == BikeState.PlayerState.CRASHING or player_controller.state.player_state == BikeState.PlayerState.CRASHED:
        _update_crash_state(delta)
        return

    if player_controller.is_on_floor():
        check_crash_conditions(delta)
    _check_collision_crash()


func _check_collision_crash():
    if player_controller.state.player_state == BikeState.PlayerState.CRASHING or player_controller.state.player_state == BikeState.PlayerState.CRASHED:
        return

    for i in player_controller.get_slide_collision_count():
        var collision = player_controller.get_slide_collision(i)
        var collider = collision.get_collider()

        # Check if collider is on layer 2 (bit 1)
        var is_crash_layer = false
        if collider is CollisionObject3D:
            is_crash_layer = collider.get_collision_layer_value(2)
        elif collider is CSGShape3D and collider.use_collision:
            is_crash_layer = (collider.collision_layer & 2) != 0

        if is_crash_layer:
            var normal = collision.get_normal()
            if player_controller.state.speed > 5:
                var local_normal = player_controller.global_transform.basis.inverse() * normal
                trigger_collision_crash(local_normal)
                return


func check_crash_conditions(_delta) -> String:
    """Returns crash reason or empty string if no crash"""
    var crash_reason = ""

    # Wheelie too far
    if player_controller.state.pitch_angle > crash_wheelie_threshold:
        crash_reason = "wheelie"
        crash_pitch_direction = 1
        crash_lean_direction = 0

    # Stoppie too far
    elif player_controller.state.pitch_angle < -crash_stoppie_threshold:
        crash_reason = "stoppie"
        crash_pitch_direction = -1
        crash_lean_direction = 0

    # Turning while in a stoppie - lowside crash
    elif player_controller.state.pitch_angle < deg_to_rad(-15) and abs(player_controller.state.steering_angle) > deg_to_rad(15):
        crash_reason = "stoppie_turn"
        crash_pitch_direction = 0
        crash_lean_direction = sign(player_controller.state.steering_angle)

    # Falling over (gyro instability)
    if crash_reason == "" and abs(player_controller.state.fall_angle) >= crash_lean_threshold:
        crash_reason = "fall"
        crash_pitch_direction = 0
        crash_lean_direction = sign(player_controller.state.fall_angle)

    # Total lean too far
    if crash_reason == "" and abs(player_controller.state.lean_angle + player_controller.state.fall_angle) >= crash_lean_threshold:
        crash_reason = "lean"
        crash_pitch_direction = 0
        crash_lean_direction = sign(player_controller.state.lean_angle + player_controller.state.fall_angle)

    if crash_reason != "":
        trigger_crash()

    return crash_reason


func trigger_crash():
    player_controller.state.request_state_change(BikeState.PlayerState.CRASHING)
    crash_timer = 0.0

    # Speed reduction for lowside crashes
    if is_lowside_crash():
        player_controller.state.speed *= 0.7

    crashed.emit(crash_pitch_direction, crash_lean_direction)


func _update_crash_state(delta):
    crash_timer += delta
    # Allow pause input to force respawn immediately
    if Input.is_action_just_pressed("pause"):
        _do_respawn()
        return
    
    _update_ragdoll(delta)
    
    # TODO: bike crash physics

func _update_ragdoll(delta):
    if not player_controller.character_mesh.is_ragdoll:
        player_controller.character_mesh.start_ragdoll(player_controller.velocity, 0.5)
    _switch_to_crash_camera()

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


func is_lowside_crash() -> bool:
    return crash_lean_direction != 0 and crash_pitch_direction == 0


func trigger_collision_crash(collision_normal: Vector3):
    """Trigger crash from hitting an obstacle"""
    # Determine crash direction from collision normal
    var local_normal = collision_normal

    # If hit from front, flip over handlebars
    if local_normal.z > 0.5:
        crash_pitch_direction = -1
        crash_lean_direction = 0
    # If hit from side, lowside in that direction
    elif abs(local_normal.x) > 0.3:
        crash_pitch_direction = 0
        crash_lean_direction = sign(local_normal.x)
    # Otherwise default to forward flip
    else:
        crash_pitch_direction = -1
        crash_lean_direction = 0

    trigger_crash()

func _bike_reset():
    crash_timer = 0.0
    crash_pitch_direction = 0.0
    crash_lean_direction = 0.0
    _ragdoll_stopped = false
    _ragdoll_stop_time = 0.0
    _switch_to_riding_camera()
    respawned.emit()


func _switch_to_crash_camera():
    player_controller.crashing_camera.make_current()

func _switch_to_riding_camera():
    player_controller.riding_camera.make_current()
