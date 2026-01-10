## Adding a New Bike

### Adding a bike

- Create animation library w/ name of new bike_resource file
  - Animation Player > Animation > Manage Animations
  - Save to file
- Create new RESET animation manually - 
  - select all IKCharacterMesh Targets & add keyframe for position/rotation
  - select all IKCharacterMesh IK nodes & add keyframe for magnets
- Create new bike_resource (add this anim_library name to it)
- Add to bike_resources preload list

### Setting positions

- set the current bike idx
- ALT+R - reload the scene
- Update bike_resource values & save resource in resource panel
- Move IKCharacterMesh targets to position
- Click Save IK Targets to bike_resource
- Click Save IK Targets to RESET Animation
- Open Animation libary => copy animations from other bikes
- Click Set All Animations first frame to RESET
- ALT+R - reload the scene
