class_name PlayerAnimationController extends Node

# Shared state
var state: BikeState

# Mesh references
var mesh: Node3D
var rear_wheel: Marker3D
var front_wheel: Marker3D

# Local state
var tail_light_material: StandardMaterial3D = null

func _bike_setup(bike_state: BikeState, bike_input: BikeInput, tail_light: MeshInstance3D,
        p_mesh: Node3D, p_rear_wheel: Marker3D, p_front_wheel: Marker3D):
    state = bike_state
    mesh = p_mesh
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


func _on_front_brake_changed(value: float):
    _update_brake_light(value)

func _on_rear_brake_changed(value: float):
    _update_brake_light(value)


func _update_brake_light(value: float):
    if tail_light_material:
        tail_light_material.emission_enabled = value > 0.01


func apply_mesh_rotation():
    mesh.transform = Transform3D.IDENTITY

    if state.ground_pitch != 0:
        mesh.rotate_x(-state.ground_pitch)

    var pivot: Vector3
    if state.pitch_angle >= 0:
        pivot = rear_wheel.position
    else:
        pivot = front_wheel.position

    if state.pitch_angle != 0:
        _rotate_mesh_around_pivot(pivot, Vector3.RIGHT, state.pitch_angle)

    var total_lean = state.lean_angle + state.fall_angle
    if total_lean != 0:
        mesh.rotate_z(total_lean)


func _rotate_mesh_around_pivot(pivot: Vector3, axis: Vector3, angle: float):
    var t = mesh.transform
    t.origin -= pivot
    t = t.rotated(axis, angle)
    t.origin += pivot
    mesh.transform = t


func _bike_reset():
    _update_brake_light(0)
