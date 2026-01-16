class_name TrainingWheelsMod extends BikeComponent

@export var is_left_wheel: bool = true
@export var max_lean_angle: float = 45.0
@export var rotation_speed: float = 12.0

var current_rotation: float = 0.0

func _ready():
    add_to_group("Mods", true)

func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller


func _bike_update(delta):
    if not player_controller.state:
        return

    # Left wheel lifts when turning right (negative lean), right wheel lifts when turning left (positive lean)
    var lean = player_controller.state.lean_angle * (-1.0 if is_left_wheel else 1.0)
    var lean_pct = clamp(lean / deg_to_rad(max_lean_angle), 0.0, 1.0)
    var target_rotation = deg_to_rad(max_lean_angle * 1.1) * lean_pct

    current_rotation = lerpf(current_rotation, target_rotation, rotation_speed * delta)
    rotation.z = current_rotation

# hack - gets called in _apply_bike_config
func _bike_reset():
    if not player_controller:
        return

    if is_left_wheel:
        transform = player_controller.bike_resource.left_training_wheel_transform
    else:
        transform = player_controller.bike_resource.right_training_wheel_transform
