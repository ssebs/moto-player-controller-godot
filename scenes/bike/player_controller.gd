@tool
class_name PlayerController extends CharacterBody3D

#region Onready Node References
# Meshes / Character / Animations
@onready var collision_shape: CollisionShape3D = %CollisionShape3D
@onready var rotation_root: Node3D = %LeanAndRotationPoint
@onready var character_mesh: Node3D = %IKCharacterMesh
@onready var bike_mesh: Node3D = %BikeMesh

# TODO: move to bike_mods
@onready var tail_light: MeshInstance3D = %TailLight
@onready var training_wheels: Node3D = %TrainingWheels

@onready var riding_cam_position: Node3D = %RidingCamPosition
@onready var crash_cam_position: Node3D = %CrashCamPosition
@onready var riding_camera: Camera3D = %RidingCamera
@onready var crashing_camera: Camera3D = %CrashingCamera

@onready var anim_player: AnimationPlayer = %AnimationPlayer

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
@export var bike_resources: Array[BikeResource] = [
    preload("res://scenes/bike/resources/sport_bike.tres"),
    preload("res://scenes/bike/resources/dirt_bike.tres"),
    preload("res://scenes/bike/resources/pocket_bike.tres"),
]
@export var current_bike_index: int = 0
var bike_resource: BikeResource

@export_tool_button("Save IK Targets to bike_resource") var save_ik_btn = _save_ik_targets_to_config
@export_tool_button("Save IK Targets to RESET Animation") var save_reset_btn = _save_ik_targets_to_reset
@export_tool_button("Set All Animations first frame to RESET") var init_anims_btn = _init_all_anims_from_reset

# Spawn tracking
var spawn_position: Vector3
var spawn_rotation: Vector3

#region lifecycle

func _ready():
    if bike_resources.is_empty():
        printerr("Add bike_resources to the bike_resources array")
        return

    bike_resource = bike_resources[current_bike_index]
    _apply_bike_config()
    if Engine.is_editor_hint():
        return # Don't run game logic in editor

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
    bike_input.bike_switch_pressed.connect(_switch_bike)


func _physics_process(delta):
    if Engine.is_editor_hint():
        return # Don't run game logic in editor

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

func _update_player_state():
    # Don't auto-transition out of crash states - they have explicit exits
    if state.player_state in [BikeState.PlayerState.CRASHED, BikeState.PlayerState.CRASHING]:
        return
    # Trick states are managed by bike_tricks
    if state.player_state in [BikeState.PlayerState.TRICK_GROUND, BikeState.PlayerState.TRICK_AIR]:
        return

    var is_airborne = !is_on_floor()
    var target: BikeState.PlayerState
    if is_airborne:
        target = BikeState.PlayerState.AIRBORNE
    elif state.speed < 0.5 and bike_input.throttle < 0.1:
        target = BikeState.PlayerState.IDLE
    else:
        target = BikeState.PlayerState.RIDING

    state.request_state_change(target)

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
#endregion

#region bike_resource applies
func _switch_bike():
    if bike_resources.is_empty():
        printerr("cant switch bike since bike_resources is_empty")
        return
    current_bike_index = (current_bike_index + 1) % bike_resources.size()
    bike_resource = bike_resources[current_bike_index]
    _apply_bike_config()
    _respawn()

func _apply_bike_config():
    # Apply mesh
    _apply_bike_mesh()

    # Apply IK target positions to IKCharacterMesh
    _apply_ik_targets()

    # TODO: refactor these setters to use the resource values directly

    # Apply wheel marker positions
    front_wheel.position = bike_resource.front_wheel_position
    rear_wheel.position = bike_resource.rear_wheel_position

    # Apply gearing values
    bike_gearing.gear_ratios = bike_resource.gear_ratios
    bike_gearing.max_rpm = bike_resource.max_rpm
    bike_gearing.idle_rpm = bike_resource.idle_rpm
    bike_gearing.stall_rpm = bike_resource.stall_rpm
    bike_gearing.clutch_engage_speed = bike_resource.clutch_engage_speed
    bike_gearing.clutch_release_speed = bike_resource.clutch_release_speed
    bike_gearing.clutch_tap_amount = bike_resource.clutch_tap_amount
    bike_gearing.clutch_hold_delay = bike_resource.clutch_hold_delay
    bike_gearing.rpm_blend_speed = bike_resource.rpm_blend_speed
    bike_gearing.rev_match_speed = bike_resource.rev_match_speed

    # Apply physics values
    bike_physics.max_speed = bike_resource.max_speed
    bike_physics.acceleration = bike_resource.acceleration
    bike_physics.brake_strength = bike_resource.brake_strength
    bike_physics.friction = bike_resource.friction
    bike_physics.engine_brake_strength = bike_resource.engine_brake_strength
    bike_physics.steering_speed = bike_resource.steering_speed
    bike_physics.max_steering_angle = deg_to_rad(bike_resource.max_steering_angle)
    bike_physics.max_lean_angle = deg_to_rad(bike_resource.max_lean_angle)
    bike_physics.lean_speed = bike_resource.lean_speed
    bike_physics.min_turn_radius = bike_resource.min_turn_radius
    bike_physics.max_turn_radius = bike_resource.max_turn_radius
    bike_physics.turn_speed = bike_resource.turn_speed
    bike_physics.fall_rate = bike_resource.fall_rate
    bike_physics.countersteer_factor = bike_resource.countersteer_factor

    # Apply audio tracks
    engine_sound.stream = bike_resource.engine_sound_stream
    engine_sound.volume_db = bike_resource.engine_sound_volume_db

## Clear mesh under bike_mesh, spawn from bike_resource, apply transforms, play RESET
func _apply_bike_mesh():
    # Clear existing mesh
    if bike_mesh.get_child_count() != 0:
        for child in bike_mesh.get_children():
            child.queue_free()

    var _mesh_instance = bike_resource.mesh_scene.instantiate() as Node3D

    # Apply transforms from resource
    _mesh_instance.scale = bike_resource.mesh_scale
    _mesh_instance.rotation_degrees = bike_resource.mesh_rotation
    bike_mesh.add_child(_mesh_instance)

    anim_player.play(bike_resource.animation_library_name + "/RESET")

## Set Target's position/rotate to values from bike_resource
func _apply_ik_targets():
    # Get IKCharacterMesh targets (they're under character_mesh/Targets/)
    var targets = character_mesh.get_node("Targets")

    targets.get_node("HeadTarget").position = bike_resource.head_target_position
    targets.get_node("HeadTarget").rotation = bike_resource.head_target_rotation
    targets.get_node("LeftArmTarget").position = bike_resource.left_arm_target_position
    targets.get_node("LeftArmTarget").rotation = bike_resource.left_arm_target_rotation
    targets.get_node("RightArmTarget").position = bike_resource.right_arm_target_position
    targets.get_node("RightArmTarget").rotation = bike_resource.right_arm_target_rotation
    targets.get_node("ButtTarget").position = bike_resource.butt_target_position
    targets.get_node("ButtTarget").rotation = bike_resource.butt_target_rotation
    targets.get_node("LeftLegTarget").position = bike_resource.left_leg_target_position
    targets.get_node("LeftLegTarget").rotation = bike_resource.left_leg_target_rotation
    targets.get_node("RightLegTarget").position = bike_resource.right_leg_target_position
    targets.get_node("RightLegTarget").rotation = bike_resource.right_leg_target_rotation

## Save Target's position/rotate to values to bike_resource's file
func _save_ik_targets_to_config():
    if !bike_resource:
        push_error("No bike_resource assigned")
        return

    var targets = character_mesh.get_node("Targets")

    bike_resource.head_target_position = targets.get_node("HeadTarget").position
    bike_resource.head_target_rotation = targets.get_node("HeadTarget").rotation
    bike_resource.left_arm_target_position = targets.get_node("LeftArmTarget").position
    bike_resource.left_arm_target_rotation = targets.get_node("LeftArmTarget").rotation
    bike_resource.right_arm_target_position = targets.get_node("RightArmTarget").position
    bike_resource.right_arm_target_rotation = targets.get_node("RightArmTarget").rotation
    bike_resource.butt_target_position = targets.get_node("ButtTarget").position
    bike_resource.butt_target_rotation = targets.get_node("ButtTarget").rotation
    bike_resource.left_leg_target_position = targets.get_node("LeftLegTarget").position
    bike_resource.left_leg_target_rotation = targets.get_node("LeftLegTarget").rotation
    bike_resource.right_leg_target_position = targets.get_node("RightLegTarget").position
    bike_resource.right_leg_target_rotation = targets.get_node("RightLegTarget").rotation

    var err = ResourceSaver.save(bike_resource, bike_resource.resource_path)
    if err != OK:
        push_error("Failed to save bike_resource: %s" % err)
    else:
        print("Saved IK targets to: %s" % bike_resource.resource_path)
#endregion

#region animation library
func _get_animation_library() -> AnimationLibrary:
    if !bike_resource:
        push_error("No bike_resource assigned")
        return null

    if !anim_player:
        push_error("No AnimationPlayer found")
        return null

    var library_name = bike_resource.animation_library_name
    if library_name.is_empty():
        push_error("bike_resource has no animation_library_name set")
        return null

    var library = anim_player.get_animation_library(library_name)
    if !library:
        push_error("Animation library '%s' not found" % library_name)
        return null

    print("library: %s" % bike_resource.animation_library_name)
    return library


## Save animation library to its path or scene path. Return true on success
func _save_animation_library(library: AnimationLibrary, message: String) -> bool:
    if library.resource_path.is_empty():
        # Library is embedded in scene - save the scene
        var scene_path = get_tree().edited_scene_root.scene_file_path
        var packed_scene = PackedScene.new()
        packed_scene.pack(get_tree().edited_scene_root)
        var err = ResourceSaver.save(packed_scene, scene_path)
        if err != OK:
            push_error("Failed to save scene: %s" % err)
            return false
        else:
            print("%s (scene saved: %s)" % [message, scene_path])
            return true
    else:
        var err = ResourceSaver.save(library, library.resource_path)
        if err != OK:
            push_error("Failed to save animation library: %s" % err)
            return false
        else:
            print("%s: %s" % [message, library.resource_path])
            return true

## Set first keyframes to values from Target's transforms
func _update_animation_first_keyframes(anim: Animation):
    var target_tracks = _get_ik_target_tracks()
    for i in range(anim.get_track_count()):
        var path = str(anim.track_get_path(i))
        if target_tracks.has(path):
            anim.track_set_key_value(i, 0, target_tracks[path])

func _save_ik_targets_to_reset():
    _apply_bike_config()
    _save_ik_targets_to_anim("RESET")

## Save IK targets to first keyframe in anim_name. Return true on success
func _save_ik_targets_to_anim(anim_name: String) -> bool:
    var library = _get_animation_library()
    if !library:
        return false

    if !library.has_animation(anim_name):
        push_error("No %s animation in library '%s'" % [anim_name, bike_resource.animation_library_name])
        return false

    _update_animation_first_keyframes(library.get_animation(anim_name))
    
    var ok = _save_animation_library(library, "Saved IK targets to %s animation" % anim_name)
    return ok


## Set first keyframe in all animationlibrary's animations from the values in RESET animation
func _init_all_anims_from_reset():
    var library = _get_animation_library()
    if !library || !library.has_animation("RESET"):
        push_error("No RESET animation in library '%s'" % bike_resource.animation_library_name)
        return

    # play RESET, then _save_ik_targets_to all anims
    anim_player.play(bike_resource.animation_library_name + "/RESET")

    # Apply RESET's first keyframe values to all other animations
    var updated_count = 0
    for anim_name in library.get_animation_list():
        if anim_name == "RESET":
            continue
        _update_animation_first_keyframes(library.get_animation(anim_name))
        updated_count += 1

    _save_animation_library(library, "Initialized %d animations from RESET values" % updated_count)

## Super hard-coded #TODO: clean this?
func _get_ik_target_tracks() -> Dictionary:
    var targets = character_mesh.get_node("Targets")
    return {
        "LeanAndRotationPoint/IKCharacterMesh/Targets/HeadTarget:position": targets.get_node("HeadTarget").position,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/HeadTarget:rotation": targets.get_node("HeadTarget").rotation,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/LeftArmTarget:position": targets.get_node("LeftArmTarget").position,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/LeftArmTarget:rotation": targets.get_node("LeftArmTarget").rotation,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/RightArmTarget:position": targets.get_node("RightArmTarget").position,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/RightArmTarget:rotation": targets.get_node("RightArmTarget").rotation,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/ButtTarget:position": targets.get_node("ButtTarget").position,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/ButtTarget:rotation": targets.get_node("ButtTarget").rotation,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/LeftLegTarget:position": targets.get_node("LeftLegTarget").position,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/LeftLegTarget:rotation": targets.get_node("LeftLegTarget").rotation,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/RightLegTarget:position": targets.get_node("RightLegTarget").position,
        "LeanAndRotationPoint/IKCharacterMesh/Targets/RightLegTarget:rotation": targets.get_node("RightLegTarget").rotation,
    }

#endregion
