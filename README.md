# Moto Player Controller

Motorcycle Player Controller (+ bike and world) written in Godot 4. Originally created for [Dank Nooner](https://github.com/ssebs/DankNooner), this is the motorcycle + controls + driving physics implementation.

## Gameplay

[Gameplay YT Video](https://youtu.be/0is7bDkfFqs)

- How riding should feel
  - Mix of Sim / Arcade - not as hard as real life, but not as easy as GTA.
  - Fast, but you need to brake to turn during a race.
  - Crashing is easy to do, but the better you get, the less often you'll crash
  - Jumps / doing tricks should feel like Skate (some complexity, need to time right, etc.)
  - Player should think about traction, like IRL. Can't brake too hard during a turn, can't accelerate during a turn unless weight is transferred, etc.
- How turning should feel:
  - More like real life's physics than arcade game physics.
  - Counter steer
    - Leaning left steers you left
    - Tip in / falling
      - Bike should fall when too slow
      - Speeding up should stabilize
  - Some weight to it
  - Higher speed = more stable (harder to turn, easier to stay up) (except tricks)
- How you can crash:
  - wheelie too far back
  - crash into obstacle
  - lowslide (brake too hard during lean)
  - (maybe just on hard difficulty)
    - death wobble after landing too hard
    - if the front tire skids and regains traction, the bike should high-side crash.
  - Failing a trick (hit the ground before you're back on the bike)
- [Controls](https://www.padcrafter.com/?templates=Controller+Scheme+1&leftTrigger=Front+Brake&rightTrigger=Throttle&leftBumper=Clutch&leftStick=Steer+%26+Lean&dpadUp=&dpadRight=&aButton=Rear+Brake&yButton=&xButton=Shift+Down&bButton=Shift+Up&rightBumper=Trick&rightStick=Camera.+If+RB+held%2C+Trick&leftStickClick=Switch+Bike&backButton=Change+Difficulty)

---

# Planning / Tasks

## In Progress:

- [ ] fix bug
      E 0:00:16:063 BikeTricks.\_update_skidding: Invalid access to property or key 'max_steering_angle' on a base object of type 'Node3D (BikePhysics)'.
      <GDScript Source>bike_tricks.gd:367 @ BikeTricks.\_update_skidding()
      <Stack Trace> bike_tricks.gd:367 @ \_update_skidding()
      bike_tricks.gd:202 @ \_update_riding()
      bike_tricks.gd:149 @ \_bike_update()
      player_controller.gd:142 @ \_physics_process()

## TODO:

- [ ] Simplify physics logic
- [ ] Simplify tricks logic
  - [ ] Move `_update_vibration` here from `bike_ui`
- [ ] Simplify crash checks logic
- [ ] Simplify state machines logic
- [ ] Simplify UI logic
- [ ] Simplify bike_state
- [ ] Simplify camera switching (make it possible for Multiplayer to disable)

- [ ] Fix bugs
- [ ] Create Signals that emit from player_controller.gd for use in MultiPlayer
- [ ] Fix brake feel (too easy to crash)
- [ ] Speed carries over even when crashing into collider
- [ ] Cleanup animations / add some polish

## Done:

- [x] add emission on brake light
- [x] Refactor bikemods into resource + new bike_component? Or follow TrainingWheelsMod
  - [x] Move brakelight to "essentialmods", and add position/rotation params
- [x] update_fov_from_speed
- [x] bike_component #regions, just these remaining:
  - [x] bike_tricks
  - [x] bike_ui
- [x] Simplify audio logic
- [x] Simplify animation logic
- [x] Simplify gearing logic
- [x] race track w/ level select
- [x] Camera controller
- [x] lean animation broken with diff bikes
- [x] refactor setters in \_apply_bike_config to use the resource values directly
- [x] Fix lean animations across diff bikes / final animation config cleanup
  - [x] legs get reset on dirt bike - esp right one
- [x] change bikemesh
  - instead of having a scene that has a resource in it, make a resource that takes in a scene AKA the mode
- [x] Multiple bike models w/ diff stats
  - [x] Sounds change from bikeconfig
  - [x] Sport bike (move stats to resource)
  - [x] Dirt bike
  - [x] Pocket bike
- [x] fix rotation on bike mesh from resource (dirtbike is backwards)
  - [x] see mesh_container.rotation_degrees = bike_config.mesh_rotation in @bike_mesh and @bike_config
- [x] Bike stats / mesh / marker positions for tricks should be in a resource so you can add multiple bikes
- [x] can't fall from wheelies
- [x] Riding animations
  - [x] lean
  - [x] wheelie v1 (RB for standing wheelie during wheelie)
  - [x] stoppie
  - [x] Idle / stopped (1 leg down)
  - [x] 1 complex trick (heel clicker) (only in-air)
  - [x] kickflip
  - [x] Blend between leaning & tricks (boost)
- [x] Tune "feeling" of riding the bike & doing tricks
  - [x] Bike should fall when too slow, but should be stable at speed (don't have tip-in over 30)
  - [x] Counter steering
- [x] brakes are too easy to mess up (hard to not crash & brake)
- [x] Cleanup input map (trick_down vs cam_down)
- [x] Fix clutch start on easy mode (shouldn't be needed)
- [x] NOS disable turning during, you can only boost forward
- [x] wheelie if you're on KBM, press down then hold up & the wheelie stays at perfect amount
- [x] Redline sound (bang limiter)
- [x] refactor bike_tricks w/ Trick enum
  - [x] Cleanup file
  - [x] have bike_trick's stoppie logic handle bike_crash's "brake_danger" and rename it
- [x] improve difficulty settings
- [x] Disable counter steer on ez
- [x] try rotating the collider w/ mesh , so you can wheelie up ledges
- [x] tricks
  - [x] Decide how tricks should be tracked / checked.
- [x] Difficulty settings
  - **Easy** - Automatic, can't fall off bike unless crashing into object / during trick
  - **Medium** - Manual, can't fall easily from mistakes (e.g. death wobble), clutch not required
  - **Hard** - Manual, can fall easily from mistakes, clutch required
- [x] Ragdoll character on crash
- [x] Review state machine / refactor
- [x] State machine for biker state & animations
  - > ENUM - code based, not Node based.
    - \_physics has switch statement for each state to have update
    - set_state func to allow for 1 time calls (play animation, etc.)
  - Player States:
    - Idle
    - Riding on ground
    - In air
    - Trick in air
    - Trick on ground
    - Crashing
    - Crashed (press A to reset)
- [x] Basic tricks
  - [x] Basic Wheelie (sitting)
  - [x] Basic stoppie
- [x] Create animated character that sits on bike using IK
  - [x] Basic IK control
  - [x] Procedural animations (move legs here, move arms there, etc.)
    - [x] Playable using animationplayer when doing tricks
- [x] boost
  - [x] Naruto run animation
  - [x] Increase max rpm sound
  - [x] Limited boosts, tricks to increase boost bar.
- [x] Some Refactor
  - [x] setup should be in order: (state, bike_input, [others]).
  - [x] Add custom "\_bike_update()" physics update function - instead of calling handleX and handleY in physics on player_controller, call 1 func that does all of that.
  - [x] Move all handler calls to bike_update
  - [x] Confirm event loop & apply refactor to support it
    - Event loop:
      - Check inputs
      - Component updates:
        - Gear/RPM component
        - Movement/Steering/Physics component (set velocity/rotation)
        - Tricks component
        - Crash component
      - Based on above state, move_and_slide
      - Update animations
      - Update UI
      - Play sounds
- [x] Update TODO's, currently on In Progress
- [x] bike should lean up when accelerating
- [x] bike should tip-in / countersteer when leaning
- [x] the steer angle + lean angle should be based on speed
- [x] crash detection and respawn
- [x] wheelies / stoppies - pitch control during each
- [x] Skidding / fishtail - rear brake skids, fishtail drift physics w/ skidmarks
- [x] engine sound pitch based on RPM
- [x] tire screech on skids/stoppies
- [x] gear grind sound
- [x] gear display, speedometer, throttle bar (with redline color), brake danger bar
- [x] Controller vibration - brake danger, fishtail, redline
- [x] Cleanup / refactor vibe coded `player_controller.gd`
  - [x] Move to its own node/script
- [x] Basic Movement / input system
  - [x] throttle / brake
  - [x] lean
  - [x] clutch / gears
  - [x] crashing (fall off bike, collision)
- [x] Basic sounds
- [x] Skidmarks / drifts
- [x] Import motorcycle 3d model
- [x] Create basic world
- [x] Create godot project
- [x] Control map:
  - [ ] IMG: https://www.padcrafter.com/?templates=Controller+Scheme+1&leftTrigger=Front+Brake&rightTrigger=Throttle&leftBumper=Clutch&leftStick=Steer+%26+Lean&dpadUp=&dpadRight=&aButton=Shift+Up&yButton=Rear+Brake&xButton=Shift+Down&bButton=Shift+Up&rightBumper=Trick&rightStick=Camera
  - Gamepad
    - Throttle `throttle_pct`
      - Gamepad: **RT**
      - KBM: **W**
    - Front Brake `brake_front_pct`
      - Gamepad: **LT**
      - KBM: **S**
    - Rear Brake `brake_rear`
      - > Note: input is cumulative - amount builds based on how long you hold it
      - Gamepad: **A**
      - KBM: **Space**
    - Steering `steer_pct`
      - > Note: steering causes a horizontal lean
      - Gamepad: **Left Stick X Axis**
      - KBM: **A/D**
    - Lean body `lean_pct`
      - Gamepad: **Left Stick Y Axis**
      - KBM: **Arrow Keys**
    - Clutch `clutch`
      - Gamepad: **LB**
      - KBM: **CTRL**
    - Shift Gears `gear_up` `gear_down`
      - Gamepad: **DPAD Up/Down**
      - KBM: **Q/E**
    - Camera movement `cam_x` `cam_y`
      - Gamepad: **Right Stick X / Y Axis**
      - KBM: **Mouse**
    - Trick `trick`
      - Gamepad: **RB**
      - KBM: **Shift + Arrow keys**
      - Hold **RB** while moving right joystick (**RB+Down** => Wheelie, etc.)
    - Pause: `pause`
      - Gamepad: **Start**
      - KBM: `ESC`

## Out of Scope

- [ ] Drift trick
- [ ] Bike crash physics (swich to Rigidbody?)
- [ ] HUD Cleanup
  - [ ] Create hud texture of motorcycle dashboard
  - [ ] make brakedanger only show up when val > 0.2 & move to bottom / center of screen
  - [ ] Font / style / etc.
- [ ] All Tricks (TODO: move to DankNooner)
  - [ ] Standing wheelie
  - [ ] One leg over wheelie
  - [ ] Stoppie to 180
  - [ ] Drift
  - [ ] Burnout
  - [ ] Biker Boyz w/ 2 legs over the side (sparks)
  - [ ] FMX tricks (only off **Ramps**)
    - [ ] Back / Front flip
    - [ ] 360 / 180 turns
    - [ ] Whip (table)
    - [ ] Superman (no hand spread eagle)
  - [ ] Skate tricks for memez (only off **Ramps**)
    - > hop on top of bike, then do it like skater
    - [x] kickflip/heelflip
    - [ ] pop shuvit
    - [ ] hardflip
    - [ ] 360flip
    - [ ] nollie lazerflip
