## Adding a New Bike

### 1. Create the BikeConfig Resource
- Right-click in `resources/bikes/` → Create New → Resource
- Select `BikeConfig` as the type
- Save as `your_bike_name.tres`

### 2. Set Up the Mesh
- Import your bike model to `assets/bikes/`
- Open `your_bike_name.tres` in the inspector
- Set `mesh_scene` to your imported model
- Adjust `mesh_scale` as needed (sport bike uses `0.018`)

### 3. Position the IK Markers
- Open `scenes/bike/bike_mesh.tscn`
- Assign your config to `bike_config` in the inspector
- Click "Load from Config" to apply current values
- Move the Marker3D nodes to match your bike's rider position:
  - `HeadTarget` — rider's head
  - `LeftArmTarget` / `RightArmTarget` — handlebar grips
  - `ButtTarget` — seat position
  - `LeftLegTarget` / `RightLegTarget` — footpeg positions
  - `FrontWheelMarker` / `RearWheelMarker` — wheel centers
- Click "Save to Config" to write positions back to the `.tres`

### 4. Set Gearing & Physics
- Open your `.tres` file in the inspector
- Adjust values under Gearing (gear_ratios, RPM values)
- Adjust values under Physics (max_speed, acceleration, etc.)

### 5. Create Animations
- Open `scenes/bike/player_controller.tscn`
- In AnimationPlayer, click "Animation" → "Manage Libraries"
- Add a new library named after your bike (e.g., `cruiser`)
- Create at minimum a `RESET` animation with your bike's resting pose
- Copy/adapt trick animations from `sport_bike` library as needed

### 6. Use the Bike
```gdscript
# In PlayerController or via inspector
bike_config = preload("res://resources/bikes/your_bike_name.tres")
```
