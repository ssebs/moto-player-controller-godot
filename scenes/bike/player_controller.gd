class_name PlayerController extends CharacterBody3D

#region Onready Node References
# Meshes / Character / Animations
@onready var bike_mesh: Node3D = %BikeMesh
@onready var character_mesh: Node3D = %IKCharacterMesh
@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var tail_light: MeshInstance3D = %TailLight
@onready var training_wheels: Node3D = %TrainingWheels

# Markers
@onready var rear_wheel: Marker3D = %RearWheelMarker
@onready var front_wheel: Marker3D = %FrontWheelMarker

# Sounds
@onready var engine_sound: AudioStreamPlayer = %EngineSound
@onready var tire_screech: AudioStreamPlayer = %TireScreechSound
@onready var engine_grind: AudioStreamPlayer = %EngineGrindSound
@onready var exhaust_pops: AudioStreamPlayer = %ExhaustPopsSound
@onready var nos_sound: AudioStreamPlayer = %NOSSound

# UI
@onready var gear_label: Label = %GearLabel
@onready var speed_label: Label = %SpeedLabel
@onready var throttle_bar: ProgressBar = %ThrottleBar
@onready var rpm_bar: ProgressBar = %RPMBar
@onready var brake_danger_bar: ProgressBar = %BrakeDangerBar
@onready var clutch_bar: ProgressBar = %ClutchBar
@onready var difficulty_label: Label = %DifficultyLabel
@onready var speed_lines_effect: ColorRect = %SpeedLinesEffect
@onready var boost_label: Label = %BoostLabel
@onready var boost_toast: Label = %BoostToast

# Components
@onready var bike_input: BikeInput = %BikeInput
@onready var bike_gearing: BikeGearing = %BikeGearing
@onready var bike_tricks: BikeTricks = %BikeTricks
@onready var bike_physics: BikePhysics = %BikePhysics
@onready var bike_crash: BikeCrash = %BikeCrash
@onready var bike_audio: BikeAudio = %BikeAudio
@onready var bike_ui: BikeUI = %BikeUI
@onready var bike_animation: BikeAnimation = %BikeAnimation
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
    bike_crash._bike_setup(state, bike_input, bike_physics, bike_tricks, self)
    bike_tricks._bike_setup(state, bike_input, bike_physics, bike_gearing, bike_crash, self, rear_wheel, front_wheel)
    bike_gearing._bike_setup(state, bike_input, bike_physics, bike_tricks)
    bike_physics._bike_setup(state, bike_input, bike_gearing, bike_crash, bike_tricks, self)
    bike_audio._bike_setup(state, bike_input, bike_gearing, engine_sound, tire_screech, engine_grind, exhaust_pops, nos_sound)
    bike_ui._bike_setup(state, bike_input, bike_gearing, bike_crash, bike_tricks, gear_label, speed_label, throttle_bar, rpm_bar, brake_danger_bar, clutch_bar, difficulty_label, speed_lines_effect, boost_label, boost_toast)
    bike_animation._bike_setup(state, bike_input, bike_tricks, anim_player, bike_mesh, character_mesh, tail_light, rear_wheel, front_wheel, training_wheels)

    # Connect component signals - direct connections where possible
    bike_gearing.gear_grind.connect(bike_audio.play_gear_grind)
    bike_gearing.gear_changed.connect(bike_audio.on_gear_changed)
    bike_gearing.engine_stalled.connect(bike_audio.stop_engine)
    bike_tricks.tire_screech_start.connect(bike_audio.play_tire_screech)
    bike_tricks.tire_screech_stop.connect(bike_audio.stop_tire_screech)
    bike_tricks.stoppie_stopped.connect(_on_stoppie_stopped)
    bike_tricks.boost_started.connect(_on_boost_started)
    bike_tricks.boost_started.connect(bike_audio.play_nos)
    bike_tricks.boost_ended.connect(_on_boost_ended)
    bike_tricks.boost_ended.connect(bike_audio.stop_nos)
    bike_tricks.boost_earned.connect(bike_ui.show_boost_toast)
    bike_physics.brake_stopped.connect(_on_brake_stopped)
    bike_crash.crashed.connect(_on_crashed)
    bike_crash.respawn_requested.connect(_respawn)


func _physics_process(delta):
    # Handle crash states first (before input)
    if state.player_state == BikeState.PlayerState.CRASHED:
        bike_crash._bike_update(delta)
        bike_animation.apply_mesh_rotation()
        return

    if state.player_state == BikeState.PlayerState.CRASHING:
        bike_crash._bike_update(delta)
        bike_animation._bike_update(delta)
        return

    # Input first, so state detection has current values
    bike_input._bike_update(delta)

    # Update player state based on current conditions (after input)
    _update_player_state()

    # Component updates
    bike_gearing._bike_update(delta)
    bike_physics._bike_update(delta)
    bike_tricks._bike_update(delta)
    bike_crash._bike_update(delta)
    bike_audio._bike_update(delta)
    bike_ui._bike_update(delta)

    # Movement
    bike_physics.apply_movement(delta)

    move_and_slide()

    # Align to ground & bike_mesh rotation
    bike_animation._bike_update(delta)


func _respawn():
    global_position = spawn_position
    rotation = spawn_rotation
    velocity = Vector3.ZERO
    bike_mesh.transform = Transform3D.IDENTITY

    # Reset all components
    bike_gearing._bike_reset()
    bike_physics._bike_reset()
    bike_tricks._bike_reset()
    bike_crash._bike_reset()
    bike_input._bike_reset()
    bike_audio._bike_reset()
    bike_animation._bike_reset()

    # Reset to idle state
    state.player_state = BikeState.PlayerState.IDLE


func _update_player_state():
    # Don't auto-transition out of crash states - they have explicit exits
    if state.player_state in [BikeState.PlayerState.CRASHED, BikeState.PlayerState.CRASHING]:
        return

    var is_airborne = not is_on_floor()
    var is_ground_trick = bike_tricks.is_in_ground_trick()
    var is_air_trick = bike_tricks.is_in_air_trick(is_airborne)
    var has_input = bike_input.has_input()

    var target: BikeState.PlayerState
    if is_airborne:
        target = BikeState.PlayerState.TRICK_AIR if is_air_trick else BikeState.PlayerState.AIRBORNE
    elif is_ground_trick:
        target = BikeState.PlayerState.TRICK_GROUND
    elif state.speed < 0.5 and not has_input:
        # Only go to IDLE if stopped AND no input
        target = BikeState.PlayerState.IDLE
    else:
        target = BikeState.PlayerState.RIDING

    state.request_state_change(target)


# Signal handlers
func _on_stoppie_stopped():
    bike_physics._bike_reset()
    state.speed = 0.0
    state.fall_angle = 0.0
    velocity = Vector3.ZERO


func _on_brake_stopped():
    bike_physics._bike_reset()
    velocity = Vector3.ZERO


func _on_crashed(_pitch_dir: float, lean_dir: float):
    # Play tire screech for lowside crashes
    if lean_dir != 0:
        bike_audio.play_tire_screech(1.0)


func _on_boost_started():
    bike_ui.show_speed_lines()


func _on_boost_ended():
    bike_ui.hide_speed_lines()
