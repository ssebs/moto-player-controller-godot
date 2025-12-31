class_name PlayerAnimationController extends BikeComponent

# Local state
var tail_light_material: StandardMaterial3D = null

func setup(bike_state: BikeState, input: BikeInput, tail_light: MeshInstance3D):
    state = bike_state

    # Setup tail light material reference
    if tail_light:
        tail_light_material = tail_light.get_surface_override_material(0)

    # Connect to input signals
    input.front_brake_changed.connect(_on_front_brake_changed)
    input.rear_brake_changed.connect(_on_rear_brake_changed)


func _on_front_brake_changed(value: float):
    _update_brake_light(value)

func _on_rear_brake_changed(value: float):
    _update_brake_light(value)


func _update_brake_light(value: float):
    if tail_light_material:
        tail_light_material.emission_enabled = value > 0.01

func reset():
    _update_brake_light(0)
