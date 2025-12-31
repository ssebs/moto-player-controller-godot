class_name PlayerController extends CharacterBody3D

#region Onready Node References
# Meshes / Character / Animations
@onready var mesh: Node3D = %Mesh
@onready var player_animation: PlayerAnimationController = %PlayerAnimationController
@onready var tail_light: MeshInstance3D = %TailLight
# @onready var character_skeleton: Skeleton3D = $CharacterMesh/Male_Shirt/HumanArmature/Skeleton3D

# Markers
@onready var rear_wheel: Marker3D = %RearWheelMarker
@onready var front_wheel: Marker3D = %FrontWheelMarker
@onready var right_handlebar_marker: Marker3D = %RightHandleBarMarker
@onready var left_handlebar_marker: Marker3D = %LeftHandleBarMarker
@onready var seat_marker: Marker3D = %SeatMarker

# Sounds
@onready var engine_sound: AudioStreamPlayer = %EngineSound
@onready var tire_screech: AudioStreamPlayer = %TireScreechSound
@onready var engine_grind: AudioStreamPlayer = %EngineGrindSound
@onready var exhaust_pops: AudioStreamPlayer = %ExhaustPopsSound

# UI 
@onready var gear_label: Label = %GearLabel
@onready var speed_label: Label = %SpeedLabel
@onready var throttle_bar: ProgressBar = %ThrottleBar
@onready var brake_danger_bar: ProgressBar = %BrakeDangerBar
@onready var clutch_bar: ProgressBar = %ClutchBar
@onready var difficulty_label: Label = %DifficultyLabel

# Components
@onready var bike_input: BikeInput = %BikeInput
@onready var bike_gearing: BikeGearing = %BikeGearing
@onready var bike_tricks: BikeTricks = %BikeTricks
@onready var bike_physics: BikePhysics = %BikePhysics
@onready var bike_crash: BikeCrash = %BikeCrash
@onready var bike_audio: BikeAudio = %BikeAudio
@onready var bike_ui: BikeUI = %BikeUI
#endregion

# Shared state
@export var state: BikeState = BikeState.new()

# Local state

# Ground alignment
@export var ground_align_speed: float = 10.0
var ground_pitch: float = 0.0

# Spawn tracking
var spawn_position: Vector3
var spawn_rotation: Vector3

func _ready():
    spawn_position = global_position
    spawn_rotation = rotation

    # Setup all components with shared state and input signals
    bike_input._bike_setup(state, bike_input)
    bike_gearing._bike_setup(state, bike_input, bike_physics)
    bike_crash._bike_setup(state, bike_input, bike_physics, self)
    bike_physics._bike_setup(state, bike_input, bike_gearing, bike_crash)
    bike_tricks._bike_setup(state, bike_input, bike_physics, bike_gearing, bike_crash, self, rear_wheel, front_wheel)
    bike_audio._bike_setup(state, bike_input, bike_gearing, engine_sound, tire_screech, engine_grind, exhaust_pops)
    bike_ui._bike_setup(state, bike_input, bike_gearing, bike_crash, bike_tricks, gear_label, speed_label, throttle_bar, brake_danger_bar, clutch_bar, difficulty_label)
    player_animation._bike_setup(state, bike_input, tail_light)

    # Connect component signals
    bike_gearing.gear_grind.connect(_on_gear_grind)
    bike_gearing.gear_changed.connect(_on_gear_changed)
    bike_gearing.engine_stalled.connect(_on_engine_stalled)
    bike_tricks.tire_screech_start.connect(_on_tire_screech_start)
    bike_tricks.tire_screech_stop.connect(_on_tire_screech_stop)
    bike_tricks.stoppie_stopped.connect(_on_stoppie_stopped)
    bike_physics.brake_stopped.connect(_on_brake_stopped)
    bike_crash.crashed.connect(_on_crashed)


func _physics_process(delta):
    if state.is_crashed:
        _handle_crash_state(delta)
        return

    # Input
    bike_input._bike_update(delta)

    # Component updates
    bike_gearing._bike_update(delta)
    bike_physics._bike_update(delta)
    bike_tricks._bike_update(delta)
    bike_crash._bike_update(delta)

    # Force stoppie if brake danger while going straight
    if bike_crash.should_force_stoppie():
        bike_tricks.force_pitch(-bike_crash.crash_stoppie_threshold * 1.2, 4.0, delta)

    # Movement
    _apply_movement(delta)
    _apply_mesh_rotation()

    move_and_slide()

    # Align to ground
    _align_to_ground(delta)

    # Check for collisions
    _check_collision_crash()

    # Audio and UI (after move_and_slide)
    bike_audio._bike_update(delta)
    bike_ui._bike_update(delta)
    player_animation._bike_update(delta)


func _check_collision_crash():
    if state.is_crashed:
        return

    for i in get_slide_collision_count():
        var collision = get_slide_collision(i)
        var collider = collision.get_collider()

        # Check if collider is on layer 2 (bit 1)
        var is_crash_layer = false
        if collider is CollisionObject3D:
            is_crash_layer = collider.get_collision_layer_value(2)
        elif collider is CSGShape3D and collider.use_collision:
            is_crash_layer = (collider.collision_layer & 2) != 0

        if is_crash_layer:
            var normal = collision.get_normal()
            if state.speed > 5:
                var local_normal = global_transform.basis.inverse() * normal
                bike_crash.trigger_collision_crash(local_normal)
                return


func _align_to_ground(delta):
    if is_on_floor():
        var floor_normal = get_floor_normal()
        var forward_dir = - global_transform.basis.z
        var forward_dot = forward_dir.dot(floor_normal)
        var target_pitch = asin(clamp(forward_dot, -1.0, 1.0))
        ground_pitch = lerp(ground_pitch, target_pitch, ground_align_speed * delta)
    else:
        ground_pitch = lerp(ground_pitch, 0.0, ground_align_speed * 0.5 * delta)


func _apply_movement(delta):
    var forward = - global_transform.basis.z

    if state.speed > 0.5:
        var turn_rate = bike_physics.get_turn_rate()
        rotate_y(-state.steering_angle * turn_rate * delta)

        if abs(state.fishtail_angle) > 0.01:
            rotate_y(state.fishtail_angle * delta * 1.5)
            bike_physics.apply_fishtail_friction(delta, bike_tricks.get_fishtail_speed_loss(delta))

    var vertical_velocity = velocity.y
    velocity = forward * state.speed
    velocity.y = vertical_velocity
    velocity = bike_physics.apply_gravity(delta, velocity, is_on_floor())


func _apply_mesh_rotation():
    mesh.transform = Transform3D.IDENTITY

    if ground_pitch != 0:
        mesh.rotate_x(-ground_pitch)

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


func _handle_crash_state(delta):
    if bike_crash.handle_crash_state(delta):
        _respawn()
        return

    if bike_crash.crash_pitch_direction != 0:
        bike_tricks.force_pitch(bike_crash.crash_pitch_direction * deg_to_rad(90), 3.0, delta)
    elif bike_crash.crash_lean_direction != 0:
        state.fall_angle = move_toward(state.fall_angle, bike_crash.crash_lean_direction * deg_to_rad(90), 3.0 * delta)

        if state.speed > 0.1:
            var forward = - global_transform.basis.z
            velocity = forward * state.speed
            state.speed = move_toward(state.speed, 0, 20.0 * delta)
            move_and_slide()

    _apply_mesh_rotation()


func _respawn():
    global_position = spawn_position
    rotation = spawn_rotation
    velocity = Vector3.ZERO
    mesh.transform = Transform3D.IDENTITY

    # Reset all components
    bike_gearing._bike_reset()
    bike_physics._bike_reset()
    bike_tricks._bike_reset()
    bike_crash._bike_reset()
    bike_input._bike_reset()
    bike_audio._bike_reset()
    player_animation._bike_reset()


# Signal handlers
func _on_gear_grind():
    bike_audio.play_gear_grind()


func _on_gear_changed(_new_gear: int):
    bike_audio.on_gear_changed()


func _on_engine_stalled():
    bike_audio.stop_engine()


func _on_tire_screech_start(volume: float):
    bike_audio.play_tire_screech(volume)


func _on_tire_screech_stop():
    bike_audio.stop_tire_screech()


func _on_stoppie_stopped():
    bike_physics._bike_reset()
    state.speed = 0.0
    state.fall_angle = 0.0
    velocity = Vector3.ZERO


func _on_brake_stopped():
    bike_physics._bike_reset()
    velocity = Vector3.ZERO


func _on_crashed(pitch_dir: float, lean_dir: float):
    if lean_dir != 0 and pitch_dir == 0:
        state.speed *= 0.7
    else:
        state.speed = 0.0
        velocity = Vector3.ZERO

    if lean_dir != 0:
        tire_screech.volume_db = 0.0
        tire_screech.play()
