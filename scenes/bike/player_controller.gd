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

# Spawn tracking
var spawn_position: Vector3
var spawn_rotation: Vector3

func _ready():
    spawn_position = global_position
    spawn_rotation = rotation

    # Setup all components with shared state and input signals
    bike_input._bike_setup(state, bike_input)
    bike_gearing._bike_setup(state, bike_input, bike_physics)
    bike_crash._bike_setup(state, bike_input, bike_physics, bike_tricks, self)
    bike_physics._bike_setup(state, bike_input, bike_gearing, bike_crash, self)
    bike_tricks._bike_setup(state, bike_input, bike_physics, bike_gearing, bike_crash, self, rear_wheel, front_wheel)
    bike_audio._bike_setup(state, bike_input, bike_gearing, engine_sound, tire_screech, engine_grind, exhaust_pops)
    bike_ui._bike_setup(state, bike_input, bike_gearing, bike_crash, bike_tricks, gear_label, speed_label, throttle_bar, brake_danger_bar, clutch_bar, difficulty_label)
    player_animation._bike_setup(state, bike_input, tail_light, mesh, rear_wheel, front_wheel)

    # Connect component signals
    bike_gearing.gear_grind.connect(_on_gear_grind)
    bike_gearing.gear_changed.connect(_on_gear_changed)
    bike_gearing.engine_stalled.connect(_on_engine_stalled)
    bike_tricks.tire_screech_start.connect(_on_tire_screech_start)
    bike_tricks.tire_screech_stop.connect(_on_tire_screech_stop)
    bike_tricks.stoppie_stopped.connect(_on_stoppie_stopped)
    bike_physics.brake_stopped.connect(_on_brake_stopped)
    bike_crash.crashed.connect(_on_crashed)
    bike_crash.respawn_requested.connect(_respawn)


func _physics_process(delta):
    if state.is_crashed:
        bike_crash._bike_update(delta)
        player_animation.apply_mesh_rotation()
        return

    # Input
    bike_input._bike_update(delta)

    # Component updates
    bike_gearing._bike_update(delta)
    bike_physics._bike_update(delta)
    bike_tricks._bike_update(delta)
    bike_crash._bike_update(delta)
    bike_audio._bike_update(delta)
    bike_ui._bike_update(delta)

    # Movement
    # have to pass bike_tricks here since it's setup is before tricks'
    bike_physics.apply_movement(delta, bike_tricks)

    move_and_slide()

    # Align to ground & mesh rotation
    player_animation._bike_update(delta)


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
    # Lowside crashes keep some momentum, others stop immediately
    if lean_dir != 0 and pitch_dir == 0:
        state.speed *= 0.7
    else:
        state.speed = 0.0
        velocity = Vector3.ZERO

    # Play tire screech for lowside crashes
    if lean_dir != 0:
        bike_audio.play_tire_screech(1.0)
