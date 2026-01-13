class_name BikeResource extends Resource

# Visual
@export var mesh_scene: PackedScene
@export var mesh_scale: Vector3 = Vector3(1.0, 1.0, 1.0)
@export var mesh_rotation: Vector3 = Vector3(0, 0, 0)

# IK Target Positions (applied to IKCharacterMesh/Targets/ at runtime)
@export var head_target_position: Vector3
@export var head_target_rotation: Vector3
@export var left_arm_target_position: Vector3
@export var left_arm_target_rotation: Vector3
@export var right_arm_target_position: Vector3
@export var right_arm_target_rotation: Vector3
@export var butt_target_position: Vector3
@export var butt_target_rotation: Vector3
@export var left_leg_target_position: Vector3
@export var left_leg_target_rotation: Vector3
@export var right_leg_target_position: Vector3
@export var right_leg_target_rotation: Vector3

# Wheel Markers (applied to PlayerController wheel markers at runtime)
@export var front_wheel_position: Vector3
@export var rear_wheel_position: Vector3

# Mod transforms
@export var taillight_transform: Transform3D
@export var left_training_wheel_transform: Transform3D
@export var right_training_wheel_transform: Transform3D

# Animation
@export var animation_library_name: String = "sport_bike"

# Audio
@export var engine_sound_stream: AudioStream
@export var engine_sound_volume_db: float = -25.0
@export var engine_min_pitch: float = 0.25
@export var engine_max_pitch: float = 2.2
@export var engine_boost_max_pitch: float = 2.4

# Animation
@export var max_butt_offset: float = 0.25

# Gearing (applied to BikeGearing component)
@export var gear_ratios: Array[float] = [2.92, 2.05, 1.6, 1.46, 1.15, 1.0]
@export var num_gears: int = 6
@export var max_rpm: float = 11000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 800.0
@export var clutch_engage_speed: float = 6.0
@export var clutch_release_speed: float = 2.5
@export var clutch_tap_amount: float = 0.35
@export var clutch_hold_delay: float = 0.05
@export var rpm_blend_speed: float = 12.0
@export var rev_match_speed: float = 8.0
@export var redline_cut_amount: float = 1000.0
@export var redline_threshold: float = 200.0

# Physics (applied to BikePhysics component)
@export var max_speed: float = 120.0
@export var acceleration: float = 12.0
@export var brake_strength: float = 20.0
@export var friction: float = 2.0
@export var engine_brake_strength: float = 12.0
@export var steering_speed: float = 4.0
@export var max_steering_angle: float = 35.0 # degrees, converted to radians on apply
@export var max_lean_angle: float = 45.0 # degrees, converted to radians on apply
@export var lean_speed: float = 3.5
@export var min_turn_radius: float = 0.25
@export var max_turn_radius: float = 3.0
@export var turn_speed: float = 2.0
@export var fall_rate: float = 0.5
@export var countersteer_factor: float = 1.2

# Computed getters (degrees to radians)
var max_steering_angle_rad: float:
    get: return deg_to_rad(max_steering_angle)

var max_lean_angle_rad: float:
    get: return deg_to_rad(max_lean_angle)
