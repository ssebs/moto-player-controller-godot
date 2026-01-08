# Moto Player Controller

Motorcycle Player Controller (+ bike and world) written in Godot 4. Originally created for [Dank Nooner](https://github.com/ssebs/DankNooner), this is the motorcycle + controls + driving physics implementation.

## Gameplay

[Gameplay YT Video](https://youtu.be/AbMAysvyk-Q)

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

---

# Planning / Tasks

## In Progress:

- [ ] Bike stats / mesh / marker positions for tricks should be in a resource so you can add multiple bikes
- [ ] Multiple bike models w/ diff stats
  - [ ] Sport bike (move stats to resource)
  - [ ] Pocket bike (only 2 gears, lower stats, etc.)
  - [ ] Move BikeMarkers to this

## Bugs

- [ ] Cleanup input map (trick_down vs cam_down)
- [ ] Fix clutch start on easy mode (shouldn't be needed)
- [ ] NOS disable turning during, you can only boost forward
- [ ] wheelie if you're on KBM, press down then hold up & the wheelie stays at perfect amount
- [ ] Redline sound (bang limiter)
- [ ] Speed carries over even when crashing into collider

## TODO:

- [WIP] Riding animations
  - [x] lean
  - [ ] wheelie v1 (RB for standing wheelie during wheelie)
  - [ ] stoppie
  - [ ] Idle / stopped (1 leg down)
  - [x] 1 complex trick (heel clicker) (only in-air)
- [ ] Bike crash physics (swich to Rigidbody?)
- [ ] Camera controller
- [ ] Tune "feeling" of riding the bike & doing tricks
  - [ ] Bike should fall when too slow, but should be stable at speed (don't have tip-in over 30)
  - [ ] Counter steering
- [ ] Drift
- [ ] Final refactor
  - [ ] Signals that emit from player controller for use in MP
  - [ ] Simpify physics logic
  - [ ] Simplify gearing logic
  - [ ] Simplify tricks logic
  - [ ] Simplify crash checks logic
  - [ ] Simplify state machines / animation logic
  - [ ] Simplify UI logic
- [ ] Fix bugs

## Out of Scope
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
    - [ ] kickflip/heelflip
    - [ ] pop shuvit
    - [ ] hardflip
    - [ ] 360flip
    - [ ] nollie lazerflip

## Done:

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

# Notes copied from ../README.md

### To implement

- Basic controls / movement (gas, steer, brake, cluch?, gears?)
- State machine to sync animations to movement state
- Riding bike Animations (lean/steer, wheelie, start/stop w/ leg down)
- Sync'd animations w/ state machine

### Goals

- Animations
  - IK to animate to hold on to handlebars / lean
  - Ragdoll when you fall off
- Mechanics
  - Fun but challenging
    - Multiple difficult levels
      - **Easy** - Automatic, can't fall off bike unless crashing
      - **Medium** - Manual, can't fall easily from mistakes (e.g. lowside)
      - **Hard** - Manual, can fall (e.g. low side crash if leaning and grabbing a fist full of brake)
  - Manage clutch, balancing, throttle, steering (need to be smooth, don't just slam it.)
  - Falling / crashing has ragdoll physics, player goes flying until they stop moving (or press btn)
- Gameplay
  - Doing wheelies gives you NOS
