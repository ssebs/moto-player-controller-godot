class_name PlayerController extends CharacterBody3D

#region Onready Node References
# Meshes / Character / Animations
@onready var collision_shape: CollisionShape3D = %CollisionShape3D
@onready var rotation_root: Node3D = %LeanAndRotationPoint
@onready var bike_mesh: Node3D = %BikeMesh
@onready var character_mesh: Node3D = %IKCharacterMesh
@onready var riding_cam_position: Node3D = %RidingCamPosition
@onready var crash_cam_position: Node3D = %CrashCamPosition
@onready var riding_camera: Camera3D = %RidingCamera
@onready var crashing_camera: Camera3D = %CrashingCamera
@onready var bike_itself_mesh: Node3D = %BikeItself
@onready var anim_player: AnimationPlayer = %AnimationPlayer
@onready var lean_anim_player: AnimationPlayer = %LeanAnimationPlayer
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
@onready var respawn_label: Label = %RespawnLabel
@onready var score_label: Label = %ScoreLabel
@onready var trick_label: Label = %TrickLabel
@onready var combo_label: Label = %ComboLabel
@onready var trick_feed_label: Label = %TrickFeedLabel

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

    # TODO: call this from %FunctionalityComponents.get_children()
    bike_input._bike_setup(self)
    bike_crash._bike_setup(self)
    bike_tricks._bike_setup(self)
    bike_gearing._bike_setup(self)
    bike_physics._bike_setup(self)
    bike_audio._bike_setup(self)
    bike_ui._bike_setup(self)
    bike_animation._bike_setup(self)

    bike_crash.respawn_requested.connect(_respawn)


func _physics_process(delta):
    # Handle crash states first (before input)
    if state.player_state == BikeState.PlayerState.CRASHED || \
        state.player_state == BikeState.PlayerState.CRASHING:
        bike_crash._bike_update(delta)
        bike_animation._bike_update(delta)
        return

    # Input first, so state detection has current values
    bike_input._bike_update(delta)

    _update_player_state()

    # Component updates
    # TODO: call this from %FunctionalityComponents.get_children()
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
    rotation_root.transform = Transform3D.IDENTITY

    # TODO: call this from %FunctionalityComponents.get_children()

    # Reset all components
    bike_gearing._bike_reset()
    bike_physics._bike_reset()
    bike_tricks._bike_reset()
    bike_crash._bike_reset()
    bike_input._bike_reset()
    bike_audio._bike_reset()
    bike_ui._bike_reset()
    bike_animation._bike_reset()

    # Reset to idle state
    state.player_state = BikeState.PlayerState.IDLE


func _update_player_state():
    # Don't auto-transition out of crash states - they have explicit exits
    if state.player_state in [BikeState.PlayerState.CRASHED, BikeState.PlayerState.CRASHING]:
        return
    # Trick states are managed by bike_tricks
    if state.player_state in [BikeState.PlayerState.TRICK_GROUND, BikeState.PlayerState.TRICK_AIR]:
        return

    var is_airborne = not is_on_floor()
    var target: BikeState.PlayerState
    if is_airborne:
        target = BikeState.PlayerState.AIRBORNE
    elif state.speed < 0.5 and bike_input.throttle < 0.1:
        target = BikeState.PlayerState.IDLE
    else:
        target = BikeState.PlayerState.RIDING

    state.request_state_change(target)
