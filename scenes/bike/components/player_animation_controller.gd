class_name PlayerAnimationController extends Node

# Shared state
var state: BikeState

# Local state
var tail_light_material: StandardMaterial3D = null

func _bike_setup(bike_state: BikeState, bike_input: BikeInput, tail_light: MeshInstance3D):
    state = bike_state

    # Setup tail light material reference
    if tail_light:
        tail_light_material = tail_light.get_surface_override_material(0)

    # Connect to input signals
    bike_input.front_brake_changed.connect(_on_front_brake_changed)
    bike_input.rear_brake_changed.connect(_on_rear_brake_changed)


func _bike_update(_delta):
    pass


func _on_front_brake_changed(value: float):
    _update_brake_light(value)

func _on_rear_brake_changed(value: float):
    _update_brake_light(value)


func _update_brake_light(value: float):
    if tail_light_material:
        tail_light_material.emission_enabled = value > 0.01

func _bike_reset():
    _update_brake_light(0)
