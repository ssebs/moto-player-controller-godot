# Bike Config Resource Design

## Overview

Migrate bike mesh, IK target positions, wheel markers, gearing, and physics values to a Godot Resource (`BikeConfig`). Create a `@tool` BikeMesh scene for visual editing of marker positions in the editor. Support multiple bikes with different stats/positions for IK.

## BikeConfig Resource

**File:** `scenes/bike/bike_config.gd`

```gdscript
class_name BikeConfig extends Resource

# Visual
@export var mesh_scene: PackedScene
@export var mesh_scale: Vector3 = Vector3(0.018, 0.018, 0.018)

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

# Animation
@export var animation_library_name: String = "sport_bike"

# Gearing (applied to BikeGearing component)
@export var gear_ratios: Array[float] = [2.92, 2.05, 1.6, 1.46, 1.15, 1.0]
@export var max_rpm: float = 11000.0
@export var idle_rpm: float = 1000.0
@export var stall_rpm: float = 800.0
@export var clutch_engage_speed: float = 6.0
@export var clutch_release_speed: float = 2.5
@export var clutch_tap_amount: float = 0.35
@export var clutch_hold_delay: float = 0.05
@export var rpm_blend_speed: float = 12.0
@export var rev_match_speed: float = 8.0

# Physics (applied to BikePhysics component)
@export var max_speed: float = 120.0
@export var acceleration: float = 12.0
@export var brake_strength: float = 20.0
@export var friction: float = 2.0
@export var engine_brake_strength: float = 12.0
@export var steering_speed: float = 4.0
@export var max_steering_angle: float = 35.0  # degrees, converted to radians on apply
@export var max_lean_angle: float = 45.0      # degrees, converted to radians on apply
@export var lean_speed: float = 3.5
@export var min_turn_radius: float = 0.25
@export var max_turn_radius: float = 3.0
@export var turn_speed: float = 2.0
@export var fall_rate: float = 0.5
@export var countersteer_factor: float = 1.2
```

## BikeMesh Scene

**Files:** `scenes/bike/bike_mesh.tscn` + `scenes/bike/bike_mesh.gd`

### Scene Structure

```
BikeMesh (Node3D, @tool script)
├── MeshContainer (Node3D) — mesh instance spawned here
├── Targets (Node3D)
│   ├── HeadTarget (Marker3D)
│   ├── LeftArmTarget (Marker3D)
│   ├── RightArmTarget (Marker3D)
│   ├── ButtTarget (Marker3D)
│   ├── LeftLegTarget (Marker3D)
│   └── RightLegTarget (Marker3D)
└── WheelMarkers (Node3D)
    ├── FrontWheelMarker (Marker3D)
    └── RearWheelMarker (Marker3D)
```

### Script Behavior

```gdscript
@tool
class_name BikeMesh extends Node3D

@export var bike_config: BikeConfig:
    set(value):
        bike_config = value
        if bike_config:
            _apply_mesh()

@export_tool_button("Load from Config") var load_btn = _load_from_config
@export_tool_button("Save to Config") var save_btn = _save_to_config

# Node references (use @onready in non-tool, direct refs in tool)
@onready var mesh_container: Node3D = $MeshContainer
@onready var head_target: Marker3D = $Targets/HeadTarget
@onready var left_arm_target: Marker3D = $Targets/LeftArmTarget
@onready var right_arm_target: Marker3D = $Targets/RightArmTarget
@onready var butt_target: Marker3D = $Targets/ButtTarget
@onready var left_leg_target: Marker3D = $Targets/LeftLegTarget
@onready var right_leg_target: Marker3D = $Targets/RightLegTarget
@onready var front_wheel_marker: Marker3D = $WheelMarkers/FrontWheelMarker
@onready var rear_wheel_marker: Marker3D = $WheelMarkers/RearWheelMarker

var _mesh_instance: Node3D = null

func _apply_mesh():
    # Clear existing mesh
    if _mesh_instance:
        _mesh_instance.queue_free()
        _mesh_instance = null

    if not bike_config or not bike_config.mesh_scene:
        return

    # Instance new mesh
    _mesh_instance = bike_config.mesh_scene.instantiate()
    _mesh_instance.scale = bike_config.mesh_scale
    mesh_container.add_child(_mesh_instance)

func _load_from_config():
    if not bike_config:
        push_error("No BikeConfig assigned")
        return

    _apply_mesh()

    # Apply marker positions from config
    head_target.position = bike_config.head_target_position
    head_target.rotation = bike_config.head_target_rotation
    left_arm_target.position = bike_config.left_arm_target_position
    left_arm_target.rotation = bike_config.left_arm_target_rotation
    right_arm_target.position = bike_config.right_arm_target_position
    right_arm_target.rotation = bike_config.right_arm_target_rotation
    butt_target.position = bike_config.butt_target_position
    butt_target.rotation = bike_config.butt_target_rotation
    left_leg_target.position = bike_config.left_leg_target_position
    left_leg_target.rotation = bike_config.left_leg_target_rotation
    right_leg_target.position = bike_config.right_leg_target_position
    right_leg_target.rotation = bike_config.right_leg_target_rotation
    front_wheel_marker.position = bike_config.front_wheel_position
    rear_wheel_marker.position = bike_config.rear_wheel_position

func _save_to_config():
    if not bike_config:
        push_error("No BikeConfig assigned")
        return

    # Read marker positions into config
    bike_config.head_target_position = head_target.position
    bike_config.head_target_rotation = head_target.rotation
    bike_config.left_arm_target_position = left_arm_target.position
    bike_config.left_arm_target_rotation = left_arm_target.rotation
    bike_config.right_arm_target_position = right_arm_target.position
    bike_config.right_arm_target_rotation = right_arm_target.rotation
    bike_config.butt_target_position = butt_target.position
    bike_config.butt_target_rotation = butt_target.rotation
    bike_config.left_leg_target_position = left_leg_target.position
    bike_config.left_leg_target_rotation = left_leg_target.rotation
    bike_config.right_leg_target_position = right_leg_target.position
    bike_config.right_leg_target_rotation = right_leg_target.rotation
    bike_config.front_wheel_position = front_wheel_marker.position
    bike_config.rear_wheel_position = rear_wheel_marker.position

    # Save resource to disk
    var err = ResourceSaver.save(bike_config, bike_config.resource_path)
    if err != OK:
        push_error("Failed to save BikeConfig: %s" % err)
    else:
        print("Saved BikeConfig to: %s" % bike_config.resource_path)
```

## PlayerController Changes

**Add to player_controller.gd:**

```gdscript
@export var bike_config: BikeConfig

func _ready():
    # ... existing spawn tracking ...

    # Apply bike config before component setup
    if bike_config:
        _apply_bike_config()

    # ... existing component setup ...

func _apply_bike_config():
    # Apply mesh
    _apply_bike_mesh()

    # Apply IK target positions to IKCharacterMesh
    _apply_ik_targets()

    # Apply wheel marker positions
    front_wheel.position = bike_config.front_wheel_position
    rear_wheel.position = bike_config.rear_wheel_position

    # Apply gearing values (BikeGearing reads from its @export vars)
    bike_gearing.gear_ratios = bike_config.gear_ratios
    bike_gearing.max_rpm = bike_config.max_rpm
    bike_gearing.idle_rpm = bike_config.idle_rpm
    bike_gearing.stall_rpm = bike_config.stall_rpm
    bike_gearing.clutch_engage_speed = bike_config.clutch_engage_speed
    bike_gearing.clutch_release_speed = bike_config.clutch_release_speed
    bike_gearing.clutch_tap_amount = bike_config.clutch_tap_amount
    bike_gearing.clutch_hold_delay = bike_config.clutch_hold_delay
    bike_gearing.rpm_blend_speed = bike_config.rpm_blend_speed
    bike_gearing.rev_match_speed = bike_config.rev_match_speed

    # Apply physics values
    bike_physics.max_speed = bike_config.max_speed
    bike_physics.acceleration = bike_config.acceleration
    bike_physics.brake_strength = bike_config.brake_strength
    bike_physics.friction = bike_config.friction
    bike_physics.engine_brake_strength = bike_config.engine_brake_strength
    bike_physics.steering_speed = bike_config.steering_speed
    bike_physics.max_steering_angle = deg_to_rad(bike_config.max_steering_angle)
    bike_physics.max_lean_angle = deg_to_rad(bike_config.max_lean_angle)
    bike_physics.lean_speed = bike_config.lean_speed
    bike_physics.min_turn_radius = bike_config.min_turn_radius
    bike_physics.max_turn_radius = bike_config.max_turn_radius
    bike_physics.turn_speed = bike_config.turn_speed
    bike_physics.fall_rate = bike_config.fall_rate
    bike_physics.countersteer_factor = bike_config.countersteer_factor

func _apply_bike_mesh():
    # Clear existing mesh in BikeItself
    for child in bike_itself_mesh.get_children():
        child.queue_free()

    if bike_config.mesh_scene:
        var mesh_instance = bike_config.mesh_scene.instantiate()
        mesh_instance.scale = bike_config.mesh_scale
        bike_itself_mesh.add_child(mesh_instance)

func _apply_ik_targets():
    # Get IKCharacterMesh targets (they're under character_mesh/Targets/)
    var targets = character_mesh.get_node("Targets")

    targets.get_node("HeadTarget").position = bike_config.head_target_position
    targets.get_node("HeadTarget").rotation = bike_config.head_target_rotation
    targets.get_node("LeftArmTarget").position = bike_config.left_arm_target_position
    targets.get_node("LeftArmTarget").rotation = bike_config.left_arm_target_rotation
    targets.get_node("RightArmTarget").position = bike_config.right_arm_target_position
    targets.get_node("RightArmTarget").rotation = bike_config.right_arm_target_rotation
    targets.get_node("ButtTarget").position = bike_config.butt_target_position
    targets.get_node("ButtTarget").rotation = bike_config.butt_target_rotation
    targets.get_node("LeftLegTarget").position = bike_config.left_leg_target_position
    targets.get_node("LeftLegTarget").rotation = bike_config.left_leg_target_rotation
    targets.get_node("RightLegTarget").position = bike_config.right_leg_target_position
    targets.get_node("RightLegTarget").rotation = bike_config.right_leg_target_rotation
```

## Animation Approach

- Animations stay in PlayerController's AnimationPlayer (not in the resource)
- Each bike gets its own AnimationLibrary within the AnimationPlayer
- BikeConfig stores `animation_library_name` to identify which library to use
- Animation paths: `sport_bike/RESET`, `sport_bike/heel_clicker`, `cruiser/RESET`, etc.

**Animation playback changes:**
- Current: `anim_player.play("heel_clicker")`
- New: `anim_player.play(bike_config.animation_library_name + "/heel_clicker")`

## Current Values to Extract (Sport Bike)

### From player_controller.tscn (IKCharacterMesh/Targets):
```
HeadTarget: position=(0, 1.452965, 0.39370275), rotation=(0.43134058, 0, 0)
LeftArmTarget: position=(0.284, 0.9407963, 0.42305174), rotation=(-0.5337216, 1.0176142, 0)
RightArmTarget: position=(-0.284, 0.90103054, 0.44884363), rotation=(1.1478428, 2.5467584, 2.9892645)
ButtTarget: position=(0, 0.98623186, -0.35969338), rotation=(0, 0, 0)
LeftLegTarget: position=(0.2375038, 0.39871255, -0.17106614), rotation from transform
RightLegTarget: position=(-0.238, 0.399, -0.171), rotation from transform
```

### From player_controller.tscn (BikeMarkers):
```
FrontWheelMarker: position=(0, 0, -0.7181249)
RearWheelMarker: position=(0, 0, 0.68403995)
```

### From bike_gearing.gd @export defaults:
```
gear_ratios = [2.92, 2.05, 1.6, 1.46, 1.15, 1.0]
max_rpm = 11000.0
idle_rpm = 1000.0
stall_rpm = 800.0
clutch_engage_speed = 6.0
clutch_release_speed = 2.5
clutch_tap_amount = 0.35
clutch_hold_delay = 0.05
rpm_blend_speed = 12.0
rev_match_speed = 8.0
```

### From bike_physics.gd @export defaults:
```
max_speed = 120.0
acceleration = 12.0
brake_strength = 20.0
friction = 2.0
engine_brake_strength = 12.0
steering_speed = 4.0
max_steering_angle = 35 (degrees)
max_lean_angle = 45 (degrees)
lean_speed = 3.5
min_turn_radius = 0.25
max_turn_radius = 3.0
turn_speed = 2.0
fall_rate = 0.5
countersteer_factor = 1.2
```

### Mesh:
```
mesh_scene = preload("res://assets/bikes/GoogleMotorcycleSportbike.glb")
mesh_scale = Vector3(0.018, 0.018, 0.018)
```

## Files to Create

1. `scenes/bike/bike_config.gd` — Resource class
2. `resources/bikes/sport_bike.tres` — Sport bike config with current values
3. `scenes/bike/bike_mesh.tscn` + `scenes/bike/bike_mesh.gd` — Tool scene for editing
4. `scenes/bike/bikes/README.md` — How to add new bikes (already created)

## Files to Modify

1. `player_controller.tscn` — Rename `[Global]` animation library to `sport_bike`, add bike_config export, set default to sport_bike.tres
2. `player_controller.gd` — Add `_apply_bike_config()`, `_apply_bike_mesh()`, `_apply_ik_targets()` functions
3. `bike_animation.gd` — Update animation playback to use library prefix from config

**Note:** BikeGearing and BikePhysics keep their @export vars — they serve as fallback defaults. PlayerController overwrites them from config at runtime. This preserves the existing architecture.

## Implementation Steps

1. Create `bike_config.gd` resource class with all @export vars
2. Create `resources/bikes/` directory
3. Create `sport_bike.tres` with values extracted from current components/scene
4. Create `bike_mesh.tscn` scene with Marker3D children
5. Create `bike_mesh.gd` @tool script with load/save buttons
6. Add `@export var bike_config: BikeConfig` to player_controller.gd
7. Add `_apply_bike_config()` and helper functions to player_controller.gd
8. In player_controller.tscn: rename animation library `[Global]` → `sport_bike`
9. Update bike_animation.gd to prefix animation names with library name
10. Test: load sport_bike.tres, verify all values apply correctly
11. Test: open bike_mesh.tscn, load config, move markers, save back to config
