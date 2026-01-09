## Adding a New Bike

### 1. Create the BikeConfig Resource
- Right-click in `resources/bikes/` → Create New → Resource
- Select `BikeConfig` as the type
- Save as `your_bike_name.tres`

### 2. Set Up the Mesh
- Import your bike model to `assets/bikes/`
- Open `your_bike_name.tres` in the inspector
- Set `mesh_scene` to your imported model
- Adjust `mesh_scale` and `mesh_rotation` as needed (sport bike uses scale `0.018`)

### 3. Position the IK Markers
- Open `scenes/bike/player_controller.tscn` in editor
- Assign your BikeConfig to `bike_config` in the PlayerController inspector
- Expand `IKCharacterMesh/Targets/` in the scene tree
- Move the Marker3D nodes to match your bike's rider position (you'll see IK feedback in real-time):
  - `HeadTarget` — rider's head
  - `LeftArmTarget` / `RightArmTarget` — handlebar grips
  - `ButtTarget` — seat position
  - `LeftLegTarget` / `RightLegTarget` — footpeg positions
- Click **"Save IK Targets to Config"** button on PlayerController to save positions to the `.tres`

### 4. Position the Wheel Markers
- Open `scenes/bike/bike_mesh.tscn`
- Assign your config to `bike_config` in the inspector
- Click "Load from Config" to apply current values
- Adjust `WheelMarkers/FrontWheelMarker` and `WheelMarkers/RearWheelMarker` positions
- Click "Save to Config" to write wheel positions back to the `.tres`

### 5. Set Gearing & Physics
- Open your `.tres` file in the inspector
- Adjust values under Gearing (gear_ratios, RPM values)
- Adjust values under Physics (max_speed, acceleration, etc.)

### 6. Create Animations
- Open `scenes/bike/player_controller.tscn`
- Set `animation_library_name` in your BikeConfig to match your bike name (e.g., `cruiser`)
- In AnimationPlayer, click "Animation" → "Manage Libraries"
- Add a new library named after your bike (must match `animation_library_name`)
- Copy all animations from another library (e.g., `sport_bike`) as a starting point
- With your BikeConfig assigned, click **"Initialize All Animations from RESET"** to update the first keyframe of all animations to match your bike's IK target positions

### 7. Use the Bike
```gdscript
# In PlayerController or via inspector
bike_config = preload("res://resources/bikes/your_bike_name.tres")
```

---

## Tool Buttons Reference

PlayerController has three tool buttons for saving IK target positions:

| Button | What it saves | When to use |
|--------|---------------|-------------|
| **Save IK Targets to Config** | Saves positions to BikeConfig `.tres` file | After adjusting marker positions |
| **Save IK Targets to RESET Animation** | Saves positions to RESET animation keyframes | After adjusting markers, to update the RESET pose |
| **Initialize All Animations from RESET** | Updates first keyframe of ALL animations in library | One-time use after copying animations from another bike |

BikeMesh has buttons for wheel markers:

| Button | What it saves | When to use |
|--------|---------------|-------------|
| **Load from Config** | Loads wheel positions from BikeConfig | When opening bike_mesh.tscn |
| **Save to Config** | Saves wheel positions to BikeConfig | After adjusting wheel markers |
