class_name BikeAnimation extends BikeComponent

# Local config (not in BikeResource)
@export var lean_lerp_speed: float = 5.0

# Local state
var tail_light_material: StandardMaterial3D = null
var butt_position_offset: float = 0.0

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    player_controller.state.state_changed.connect(_on_player_state_changed)

    # Setup tail light material reference
    if player_controller.tail_light:
        tail_light_material = player_controller.tail_light.get_surface_override_material(0)

    # Connect to input signals
    player_controller.bike_input.front_brake_changed.connect(_on_front_brake_changed)
    player_controller.bike_input.rear_brake_changed.connect(_on_rear_brake_changed)
    player_controller.bike_input.difficulty_toggled.connect(_on_difficulty_toggled)

    # Connect to boost signals from tricks
    player_controller.bike_tricks.boost_started.connect(_on_boost_started)
    player_controller.bike_tricks.boost_ended.connect(_on_boost_ended)

    # Connect to trick signals for animations
    player_controller.bike_tricks.trick_started.connect(_on_trick_started)
    player_controller.bike_tricks.trick_ended.connect(_on_trick_ended)
    
    _update_training_wheels_visibility()


func _bike_update(delta):
    # Skip mesh rotation when idle - let the idle_stopped animation control the pose
    if player_controller.state.player_state != BikeState.PlayerState.IDLE:
        var total_lean = player_controller.state.lean_angle + player_controller.state.fall_angle
        _update_bike_root_rotation(total_lean)
        _update_butt_lean_animation(delta, total_lean)

func _bike_reset():
    _update_brake_light(0)
    _update_training_wheels_visibility()
    butt_position_offset = 0.0
    player_controller.anim_player.stop()
    _update_bike_root_rotation(player_controller.state.lean_angle + player_controller.state.fall_angle)

func _on_player_state_changed(old_state: BikeState.PlayerState, new_state: BikeState.PlayerState):
    # Handle state exit
    match old_state:
        BikeState.PlayerState.CRASHED:
            # Reset animations on respawn
            butt_position_offset = 0.0
            player_controller.anim_player.stop()
        BikeState.PlayerState.IDLE:
            if new_state == BikeState.PlayerState.RIDING:
                player_controller.anim_player.play_backwards(_get_anim("idle_stopped"))

    # Handle state entry
    match new_state:
        BikeState.PlayerState.IDLE:
            butt_position_offset = 0.0
            player_controller.anim_player.play(_get_anim("idle_stopped"))
            await player_controller.anim_player.animation_finished
            player_controller.anim_player.pause()
        BikeState.PlayerState.CRASHING:
            # Could trigger crash animation here
            pass
        BikeState.PlayerState.CRASHED:
            # Could show "press to respawn" animation
            pass

#endregion

#region input handlers 
func _on_front_brake_changed(value: float):
    _update_brake_light(value)

func _on_rear_brake_changed(value: float):
    _update_brake_light(value)

func _on_difficulty_toggled():
    _update_training_wheels_visibility()
#endregion

#region boost handlers
func _on_boost_started():
    if player_controller.anim_player.is_playing():
        return
    player_controller.anim_player.play(_get_anim("naruto_run_start"))
    player_controller.anim_player.animation_finished.connect(_on_boost_anim_finished)

func _on_boost_ended():
    if player_controller.anim_player.animation_finished.is_connected(_on_boost_anim_finished):
        player_controller.anim_player.animation_finished.disconnect(_on_boost_anim_finished)
    player_controller.anim_player.play_backwards(_get_anim("naruto_run_start"))

func _on_boost_anim_finished(anim_name: String):
    if anim_name == _get_anim("naruto_run_start"):
        player_controller.anim_player.play(_get_anim("naruto_run_loop"))

#endregion

#region tricks handlers
func _on_trick_started(trick: int):
    match trick:
        BikeTricks.Trick.HEEL_CLICKER:
            player_controller.anim_player.play(_get_anim("heel_clicker"))
        BikeTricks.Trick.KICKFLIP:
            player_controller.anim_player.play(_get_anim("kickflip"))

func _on_trick_ended(trick: int, _score: float, _duration: float):
    match trick:
        BikeTricks.Trick.HEEL_CLICKER, BikeTricks.Trick.KICKFLIP:
            await player_controller.anim_player.animation_finished
            player_controller.anim_player.play(_get_anim("RESET"))
#endregion

#region MISC / implementation details
func _update_butt_lean_animation(delta: float, total_lean: float):
    var target_offset = signf(total_lean) * player_controller.bike_resource.max_butt_offset if absf(total_lean) > 0.1 else 0.0
    butt_position_offset = lerpf(butt_position_offset, target_offset, lean_lerp_speed * delta)

    # Move butt
    var base_pos = player_controller.bike_resource.butt_target_position
    var butt_target = player_controller.character_mesh.get_node("Targets/ButtTarget")
    butt_target.position = base_pos + Vector3(butt_position_offset, 0, 0)

## Rotate (lean, wheelie angles, etc.)
func _update_bike_root_rotation(total_lean: float):
    player_controller.rotation_root.transform = Transform3D.IDENTITY
    player_controller.collision_shape.rotation.x = deg_to_rad(-90.0)

    if player_controller.state.ground_pitch != 0:
        player_controller.rotation_root.rotate_x(-player_controller.state.ground_pitch)

    var pivot: Vector3
    if player_controller.state.pitch_angle >= 0:
        pivot = player_controller.rear_wheel.position
    else:
        pivot = player_controller.front_wheel.position

    if player_controller.state.pitch_angle != 0:
        _rotate_around_pivot(player_controller.rotation_root, pivot, Vector3.RIGHT)
        player_controller.collision_shape.rotation.x = deg_to_rad(-90.0) + player_controller.state.pitch_angle

    if total_lean != 0:
        player_controller.rotation_root.rotate_z(total_lean)

func _update_training_wheels_visibility():
    if player_controller.training_wheels:
        if player_controller.state.isEasyDifficulty():
            player_controller.training_wheels.show()
        else:
            player_controller.training_wheels.hide()

func _update_brake_light(value: float):
    if tail_light_material:
        tail_light_material.emission_enabled = value > 0.01

func _rotate_around_pivot(node: Node3D, pivot: Vector3, axis: Vector3):
    var t = node.transform
    t.origin -= pivot
    t = t.rotated(axis, player_controller.state.pitch_angle)
    t.origin += pivot
    node.transform = t

func _get_anim(anim_name: String) -> String:
    if player_controller.bike_resource:
        return player_controller.bike_resource.animation_library_name + "/" + anim_name
    return anim_name

#endregion
