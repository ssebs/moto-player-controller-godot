class_name BikeAnimation extends BikeComponent

# Local state
var tail_light_material: StandardMaterial3D = null

# Lean animation state
enum LeanState {CENTER, LEANING_LEFT, HELD_LEFT, RETURNING_LEFT, LEANING_RIGHT, HELD_RIGHT, RETURNING_RIGHT}
var lean_state: LeanState = LeanState.CENTER
const LEAN_THRESHOLD := 0.1 # Minimum lean angle to trigger animation

func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller

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

    # Connect to player state changes
    player_controller.state.state_changed.connect(_on_player_state_changed)

    # Setup training wheel mods with state reference
    _setup_training_wheels()


func _bike_update(_delta):
    apply_mesh_rotation()
    update_lean_animation()


func _on_front_brake_changed(value: float):
    _update_brake_light(value)

func _on_rear_brake_changed(value: float):
    _update_brake_light(value)


func _on_difficulty_toggled():
    _update_training_wheels_visibility()


func _update_training_wheels_visibility():
    if player_controller.training_wheels:
        if player_controller.state.difficulty == player_controller.state.PlayerDifficulty.EASY:
            player_controller.training_wheels.show()
        else:
            player_controller.training_wheels.hide()


func _setup_training_wheels():
    if not player_controller.training_wheels:
        return
    _update_training_wheels_visibility()

    for child in player_controller.training_wheels.get_children():
        if child is TrainingWheelsMod:
            child.setup(player_controller.state)


func _on_boost_started():
    if player_controller.anim_player.is_playing():
        return
    player_controller.anim_player.play("naruto_run_start")
    player_controller.anim_player.animation_finished.connect(_on_boost_anim_finished)


func _on_boost_ended():
    if player_controller.anim_player.animation_finished.is_connected(_on_boost_anim_finished):
        player_controller.anim_player.animation_finished.disconnect(_on_boost_anim_finished)
    player_controller.anim_player.play_backwards("naruto_run_start")


func _on_boost_anim_finished(anim_name: String):
    if anim_name == "naruto_run_start":
        player_controller.anim_player.play("naruto_run_loop")


func _on_trick_started(trick: int):
    match trick:
        BikeTricks.Trick.HEEL_CLICKER:
            player_controller.anim_player.play("snap_neck")


func _on_trick_ended(trick: int, _score: float, _duration: float):
    match trick:
        BikeTricks.Trick.HEEL_CLICKER:
            player_controller.anim_player.play_backwards("snap_neck")


func _update_brake_light(value: float):
    if tail_light_material:
        tail_light_material.emission_enabled = value > 0.01


func update_lean_animation():
    var total_lean = player_controller.state.lean_angle + player_controller.state.fall_angle
    var is_leaning_left = total_lean > LEAN_THRESHOLD
    var is_leaning_right = total_lean < -LEAN_THRESHOLD

    match lean_state:
        LeanState.CENTER:
            if is_leaning_left:
                player_controller.anim_player.play("lean_left")
                lean_state = LeanState.LEANING_LEFT
            elif is_leaning_right:
                player_controller.anim_player.play("lean_right")
                lean_state = LeanState.LEANING_RIGHT

        LeanState.LEANING_LEFT:
            if not player_controller.anim_player.is_playing():
                lean_state = LeanState.HELD_LEFT
            elif not is_leaning_left:
                # Started returning before animation finished
                player_controller.anim_player.play_backwards("lean_left")
                lean_state = LeanState.RETURNING_LEFT

        LeanState.HELD_LEFT:
            if not is_leaning_left:
                player_controller.anim_player.play_backwards("lean_left")
                lean_state = LeanState.RETURNING_LEFT

        LeanState.RETURNING_LEFT:
            if not player_controller.anim_player.is_playing():
                lean_state = LeanState.CENTER
            elif is_leaning_left:
                # Changed direction, go back to leaning
                player_controller.anim_player.play("lean_left")
                lean_state = LeanState.LEANING_LEFT

        LeanState.LEANING_RIGHT:
            if not player_controller.anim_player.is_playing():
                lean_state = LeanState.HELD_RIGHT
            elif not is_leaning_right:
                player_controller.anim_player.play_backwards("lean_right")
                lean_state = LeanState.RETURNING_RIGHT

        LeanState.HELD_RIGHT:
            if not is_leaning_right:
                player_controller.anim_player.play_backwards("lean_right")
                lean_state = LeanState.RETURNING_RIGHT

        LeanState.RETURNING_RIGHT:
            if not player_controller.anim_player.is_playing():
                lean_state = LeanState.CENTER
            elif is_leaning_right:
                player_controller.anim_player.play("lean_right")
                lean_state = LeanState.LEANING_RIGHT


func apply_mesh_rotation():
    player_controller.rotation_root.transform = Transform3D.IDENTITY

    if player_controller.state.ground_pitch != 0:
        player_controller.rotation_root.rotate_x(-player_controller.state.ground_pitch)

    var pivot: Vector3
    if player_controller.state.pitch_angle >= 0:
        pivot = player_controller.rear_wheel.position
    else:
        pivot = player_controller.front_wheel.position

    if player_controller.state.pitch_angle != 0:
        _rotate_around_pivot(player_controller.rotation_root, pivot, Vector3.RIGHT)

    var total_lean = player_controller.state.lean_angle + player_controller.state.fall_angle
    if total_lean != 0:
        player_controller.rotation_root.rotate_z(total_lean)


func _rotate_around_pivot(node: Node3D, pivot: Vector3, axis: Vector3):
    var t = node.transform
    t.origin -= pivot
    t = t.rotated(axis, player_controller.state.pitch_angle)
    t.origin += pivot
    node.transform = t


func _on_player_state_changed(old_state: BikeState.PlayerState, new_state: BikeState.PlayerState):
    # Handle state exit
    match old_state:
        BikeState.PlayerState.CRASHED:
            # Reset animations on respawn
            lean_state = LeanState.CENTER
            player_controller.anim_player.stop()

    # Handle state entry
    match new_state:
        BikeState.PlayerState.IDLE:
            lean_state = LeanState.CENTER
        BikeState.PlayerState.CRASHING:
            # Could trigger crash animation here
            pass
        BikeState.PlayerState.CRASHED:
            # Could show "press to respawn" animation
            pass


func _bike_reset():
    _update_brake_light(0)
    lean_state = LeanState.CENTER
    player_controller.anim_player.stop()
