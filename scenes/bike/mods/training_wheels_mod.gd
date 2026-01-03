class_name TrainingWheelsMod extends Node3D

@export var is_left_wheel: bool = true
@export var max_steering_angle: float = 35.0 # import from physics
@export var rotation_speed: float = 12.0

var state: BikeState
var current_rotation: float = 0.0

func setup(bike_state: BikeState):
	state = bike_state


func _physics_process(delta):
	if not state:
		return

	# Left wheel lifts when turning right (negative steer), right wheel lifts when turning left (positive steer)
	var steer = state.steering_angle * (-1.0 if is_left_wheel else 1.0)
	var steer_pct = clamp(steer / deg_to_rad(max_steering_angle), 0.0, 1.0)
	var target_rotation = deg_to_rad(max_steering_angle*1.1) * steer_pct

	current_rotation = lerpf(current_rotation, target_rotation, rotation_speed * delta)
	rotation.z = current_rotation
