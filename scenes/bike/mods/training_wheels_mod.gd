class_name TrainingWheelsMod extends BikeComponent

@export var is_left_wheel: bool = true
@export var max_steering_angle: float = 35.0 # import from physics
@export var rotation_speed: float = 12.0

var current_rotation: float = 0.0

func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller


func _bike_update(delta):
    if not player_controller.state:
        return

    # Left wheel lifts when turning right (negative steer), right wheel lifts when turning left (positive steer)
    var steer = player_controller.state.steering_angle * (-1.0 if is_left_wheel else 1.0)
    var steer_pct = clamp(steer / deg_to_rad(max_steering_angle), 0.0, 1.0)
    var target_rotation = deg_to_rad(max_steering_angle*1.1) * steer_pct

    current_rotation = lerpf(current_rotation, target_rotation, rotation_speed * delta)
    rotation.z = current_rotation

func _bike_reset():
    pass