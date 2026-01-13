class_name BikeCamera extends BikeComponent

signal camera_reset_started
signal camera_reset_completed

@export var rotation_speed: float = 120.0 # degrees per second
@export var vertical_clamp: Vector2 = Vector2(-90, 90) # min/max pitch
@export var reset_duration: float = 1.0 # seconds to lerp back
@export var reset_delay: float = 1.0 # seconds to wait before starting lerp

var current_yaw: float = 0.0
var current_pitch: float = 0.0
var is_resetting: bool = false
var reset_timer: float = 0.0
var reset_start_yaw: float = 0.0
var reset_start_pitch: float = 0.0

#region BikeComponent lifecycle
func _bike_setup(p_controller: PlayerController):
    player_controller = p_controller
    player_controller.state.state_changed.connect(_on_player_state_changed)

    player_controller.bike_input.trick_changed.connect(_on_trick_changed)

func _bike_update(delta: float):
    _update_camera(delta)

func _bike_reset():
    current_yaw = 0.0
    current_pitch = 0.0
    is_resetting = false
    _apply_rotation()

#endregion

func _on_trick_changed(value: float):
    if value:
        _start_reset_cam_pos()


func _update_camera(delta: float):
    # Block rotation while trick button held
    if player_controller.bike_input.trick:
        _start_reset_cam_pos()

    # Handle reset lerp
    if is_resetting:
        _update_reset_cam_pos(delta)
        return

    # Read camera inputs
    var input_yaw = Input.get_action_strength("cam_right") - Input.get_action_strength("cam_left")
    var input_pitch = Input.get_action_strength("cam_down") - Input.get_action_strength("cam_up")

    # Apply invert Y
    if player_controller.invert_camera_y:
        input_pitch *= -1

    # No input = start reset
    if abs(input_yaw) < 0.1 and abs(input_pitch) < 0.1:
        if current_yaw != 0.0 or current_pitch != 0.0:
            _start_reset_cam_pos()
        return

    # Apply rotation
    current_yaw += input_yaw * rotation_speed * delta
    current_pitch += input_pitch * rotation_speed * delta
    current_pitch = clamp(current_pitch, vertical_clamp.x, vertical_clamp.y)

    _apply_rotation()


func _start_reset_cam_pos():
    if is_resetting:
        return
    is_resetting = true
    reset_timer = 0.0
    reset_start_yaw = current_yaw
    reset_start_pitch = current_pitch
    camera_reset_started.emit()


func _update_reset_cam_pos(delta: float):
    reset_timer += delta

    # Wait for delay before starting lerp
    if reset_timer < reset_delay:
        return

    var lerp_time = reset_timer - reset_delay
    var t = clamp(lerp_time / reset_duration, 0.0, 1.0)
    t = ease(t, 2.0) # Smooth ease-out

    current_yaw = lerp(reset_start_yaw, 0.0, t)
    current_pitch = lerp(reset_start_pitch, 0.0, t)
    _apply_rotation()

    if t >= 1.0:
        is_resetting = false
        camera_reset_completed.emit()


func _apply_rotation():
    player_controller.camera_rotate_node.rotation_degrees = Vector3(current_pitch, current_yaw, 0)
