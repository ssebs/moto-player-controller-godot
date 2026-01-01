class_name PlayerAnimationController extends Node

# Shared state
var state: BikeState

# Mesh references
var bike_mesh: Node3D
var character_mesh: IKCharacterMesh
var anim_player: AnimationPlayer
var rear_wheel: Marker3D
var front_wheel: Marker3D

# Local state
var tail_light_material: StandardMaterial3D = null

# Lean animation state
enum LeanState { CENTER, LEANING_LEFT, HELD_LEFT, RETURNING_LEFT, LEANING_RIGHT, HELD_RIGHT, RETURNING_RIGHT }
var lean_state: LeanState = LeanState.CENTER
const LEAN_THRESHOLD := 0.1  # Minimum lean angle to trigger animation

func _bike_setup(bike_state: BikeState, bike_input: BikeInput, animation_player: AnimationPlayer, b_mesh: Node3D, c_mesh: IKCharacterMesh,
                tail_light: MeshInstance3D, p_rear_wheel: Marker3D, p_front_wheel: Marker3D
    ):
    state = bike_state
    bike_mesh = b_mesh
    character_mesh = c_mesh
    anim_player = animation_player
    rear_wheel = p_rear_wheel
    front_wheel = p_front_wheel

    # Setup tail light material reference
    if tail_light:
        tail_light_material = tail_light.get_surface_override_material(0)

    # Connect to input signals
    bike_input.front_brake_changed.connect(_on_front_brake_changed)
    bike_input.rear_brake_changed.connect(_on_rear_brake_changed)


func _bike_update(_delta):
    apply_mesh_rotation()
    update_lean_animation()


func _on_front_brake_changed(value: float):
    _update_brake_light(value)

func _on_rear_brake_changed(value: float):
    _update_brake_light(value)


func _update_brake_light(value: float):
    if tail_light_material:
        tail_light_material.emission_enabled = value > 0.01


func update_lean_animation():
    var total_lean = state.lean_angle + state.fall_angle
    var is_leaning_left = total_lean > LEAN_THRESHOLD
    var is_leaning_right = total_lean < -LEAN_THRESHOLD

    match lean_state:
        LeanState.CENTER:
            if is_leaning_left:
                anim_player.play("lean_left")
                lean_state = LeanState.LEANING_LEFT
            elif is_leaning_right:
                anim_player.play("lean_right")
                lean_state = LeanState.LEANING_RIGHT

        LeanState.LEANING_LEFT:
            if not anim_player.is_playing():
                lean_state = LeanState.HELD_LEFT
            elif not is_leaning_left:
                # Started returning before animation finished
                anim_player.play_backwards("lean_left")
                lean_state = LeanState.RETURNING_LEFT

        LeanState.HELD_LEFT:
            if not is_leaning_left:
                anim_player.play_backwards("lean_left")
                lean_state = LeanState.RETURNING_LEFT

        LeanState.RETURNING_LEFT:
            if not anim_player.is_playing():
                lean_state = LeanState.CENTER
            elif is_leaning_left:
                # Changed direction, go back to leaning
                anim_player.play("lean_left")
                lean_state = LeanState.LEANING_LEFT

        LeanState.LEANING_RIGHT:
            if not anim_player.is_playing():
                lean_state = LeanState.HELD_RIGHT
            elif not is_leaning_right:
                anim_player.play_backwards("lean_right")
                lean_state = LeanState.RETURNING_RIGHT

        LeanState.HELD_RIGHT:
            if not is_leaning_right:
                anim_player.play_backwards("lean_right")
                lean_state = LeanState.RETURNING_RIGHT

        LeanState.RETURNING_RIGHT:
            if not anim_player.is_playing():
                lean_state = LeanState.CENTER
            elif is_leaning_right:
                anim_player.play("lean_right")
                lean_state = LeanState.LEANING_RIGHT


func apply_mesh_rotation():
    bike_mesh.transform = Transform3D.IDENTITY

    if state.ground_pitch != 0:
        bike_mesh.rotate_x(-state.ground_pitch)

    var pivot: Vector3
    if state.pitch_angle >= 0:
        pivot = rear_wheel.position
    else:
        pivot = front_wheel.position

    if state.pitch_angle != 0:
        _rotate_mesh_around_pivot(pivot, Vector3.RIGHT)


    var total_lean = state.lean_angle + state.fall_angle
    if total_lean != 0:
        bike_mesh.rotate_z(total_lean)


func _rotate_mesh_around_pivot(pivot: Vector3, axis: Vector3):
    var t = bike_mesh.transform
    t.origin -= pivot
    t = t.rotated(axis, state.pitch_angle)
    t.origin += pivot
    bike_mesh.transform = t


func _bike_reset():
    _update_brake_light(0)
    lean_state = LeanState.CENTER
    anim_player.stop()
