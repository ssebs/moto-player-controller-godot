# IK Target Marker Consolidation Design

## Problem

Duplicate Marker3D nodes exist in both BikeMesh and IKCharacterMesh for IK targets (head, arms, butt, legs). The BikeMesh copies exist only for editing in isolation, but editing there doesn't show real-time IK feedback on the character. This creates:

1. **Poor editing experience** - Can't see how marker positions affect the actual character pose
2. **Duplicate data** - Same 6 markers defined in two places
3. **Confusing workflow** - Which markers are "real"?

## Solution

- **Delete** the `Targets/` folder from BikeMesh (6 Marker3D nodes)
- **Keep** `WheelMarkers/` in BikeMesh for wheel position editing
- **Edit** IK targets directly on IKCharacterMesh in the PlayerController scene
- **Add** a `@tool` button on PlayerController that saves IKCharacterMesh target positions to BikeConfig

## Architecture After Changes

```
PlayerController (@tool - adds "Save IK Targets to Config" button)
├── BikeMesh
│   ├── MeshContainer
│   └── WheelMarkers/        ← keeps existing editing workflow
│       ├── FrontWheelMarker
│       └── RearWheelMarker
│
└── IKCharacterMesh
    └── Targets/             ← NOW the single source of truth
        ├── HeadTarget
        ├── LeftArmTarget
        ├── RightArmTarget
        ├── ButtTarget
        ├── LeftLegTarget
        └── RightLegTarget
```

## Workflow After Changes

### Editing IK Target Positions (NEW)
1. Open `scenes/bike/player_controller.tscn` in editor
2. Assign desired BikeConfig to PlayerController's `bike_config` export
3. Expand `IKCharacterMesh/Targets/` in scene tree
4. Move target markers - see IK results on the character in real-time
5. Click **"Save IK Targets to Config"** button on PlayerController inspector
6. Positions are saved to the BikeConfig `.tres` file

### Editing Wheel Markers / Mesh (unchanged)
1. Open `scenes/bike/bike_mesh.tscn`
2. Assign BikeConfig, click "Load from Config"
3. Adjust `WheelMarkers/` positions
4. Click "Save to Config"

## Implementation Changes

### 1. Delete BikeMesh Targets folder
**File:** `scenes/bike/bike_mesh.tscn`

Remove the entire `Targets/` node and its 6 children:
- `Targets/HeadTarget`
- `Targets/LeftArmTarget`
- `Targets/RightArmTarget`
- `Targets/ButtTarget`
- `Targets/LeftLegTarget`
- `Targets/RightLegTarget`

### 2. Update BikeMesh script
**File:** `scenes/bike/bike_mesh.gd`

- Remove target marker variables (lines 15-20)
- Remove target marker caching from `_cache_node_refs()` (lines 35-40)
- Remove target loading from `_load_from_config()` (lines 75-86)
- Remove target saving from `_save_to_config()` (lines 99-110)
- Keep wheel marker handling intact

### 3. Add @tool and save button to PlayerController
**File:** `scenes/bike/player_controller.gd`

Add at top:
```gdscript
@tool
```

Add new export button and function:
```gdscript
@export_tool_button("Save IK Targets to Config") var save_ik_btn = _save_ik_targets_to_config

func _save_ik_targets_to_config():
    if not bike_config:
        push_error("No BikeConfig assigned")
        return

    var targets = $IKCharacterMesh/Targets

    bike_config.head_target_position = targets.get_node("HeadTarget").position
    bike_config.head_target_rotation = targets.get_node("HeadTarget").rotation
    bike_config.left_arm_target_position = targets.get_node("LeftArmTarget").position
    bike_config.left_arm_target_rotation = targets.get_node("LeftArmTarget").rotation
    bike_config.right_arm_target_position = targets.get_node("RightArmTarget").position
    bike_config.right_arm_target_rotation = targets.get_node("RightArmTarget").rotation
    bike_config.butt_target_position = targets.get_node("ButtTarget").position
    bike_config.butt_target_rotation = targets.get_node("ButtTarget").rotation
    bike_config.left_leg_target_position = targets.get_node("LeftLegTarget").position
    bike_config.left_leg_target_rotation = targets.get_node("LeftLegTarget").rotation
    bike_config.right_leg_target_position = targets.get_node("RightLegTarget").position
    bike_config.right_leg_target_rotation = targets.get_node("RightLegTarget").rotation

    var err = ResourceSaver.save(bike_config, bike_config.resource_path)
    if err != OK:
        push_error("Failed to save BikeConfig: %s" % err)
    else:
        print("Saved IK targets to: %s" % bike_config.resource_path)
```

Add guard for tool mode in `_ready()` and `_physics_process()`:
```gdscript
func _ready():
    if Engine.is_editor_hint():
        return  # Don't run game logic in editor
    # ... existing code

func _physics_process(delta):
    if Engine.is_editor_hint():
        return  # Don't run game logic in editor
    # ... existing code
```

### 4. Update AddingBikes.md documentation
**File:** `scenes/bike/AddingBikes.md`

Update "Position the IK Markers" section to reflect new workflow (edit in player_controller.tscn).

Add new sections:
- "Adding New BikeConfig Variables" - how to extend the resource
- "Creating Bike Animations" - how to create RESET and trick animations

## Files Changed

| File | Change |
|------|--------|
| `scenes/bike/bike_mesh.tscn` | Delete `Targets/` folder (6 nodes) |
| `scenes/bike/bike_mesh.gd` | Remove target marker handling |
| `scenes/bike/player_controller.gd` | Add `@tool`, save button, editor guards |
| `scenes/bike/AddingBikes.md` | Update workflow, add new sections |

## Testing

1. Open `player_controller.tscn` in editor
2. Verify no errors in Output panel
3. Move an IK target marker (e.g., `LeftArmTarget`)
4. Click "Save IK Targets to Config"
5. Check that the `.tres` file updated
6. Reload scene, verify positions persisted
7. Run game, verify character IK still works
