# Bike README

## How the bike works:

- **Main** `player_controller.gd` script attached to scene
  - Has all onready Node references
- **Component scripts** are a Node + script.
  - Each of these controls something about the bike (e.g. audio, gearing, ui, etc.)
  - Any vars that need to be passed in should use the `_bike_setup()` func
    - > Which is called in the main script's `_ready()` function.
  - **Signals** are exposed to the main script to handle & pipe between components as needed.
  - Structure - See `player_animation_controller.gd` as best reference.
    - Component Signals
    - Shared state vars - local BikeState var / other components that are needed
    - Local vars
    - `_bike_setup(bike_state, bike_input, [other params])`
    - Other Signal handlers
    - `_bike_update()` called in `_physics_process()` from main script
    - `_bike_reset()` - reset to default values for respawning

## Player State Machine

The bike uses an enum-based state machine defined in `BikeState`:

```
IDLE          - Stationary, no throttle/brake input
RIDING        - On ground, moving normally
AIRBORNE      - In the air, no trick active
TRICK_AIR     - In the air with pitch control active
TRICK_GROUND  - Wheelie/stoppie/fishtail on ground
CRASHING      - Crash in progress (rotating to ground)
CRASHED       - Fully crashed, waiting for respawn
```

### State Transitions
- Components request state changes via `state.request_state_change(new_state)`
- Transitions are validated against `VALID_TRANSITIONS` dictionary
- `state_changed` signal emits on successful transitions

### Component State Handling
Each component uses a `match` statement in `_bike_update()` to run state-specific logic:

```gdscript
func _bike_update(delta):
    match state.player_state:
        BikeState.PlayerState.IDLE:
            _update_idle(delta)
        BikeState.PlayerState.RIDING:
            _update_riding(delta)
        # ... etc
```

Components can also connect to `state.state_changed` for one-time entry/exit actions.

## Bike Event Loop / Sections in Code:

- `@onready` (Node Refs)
- `_ready()` (Initialization)
  - Call component `_bike_setup()` func with relevant params
  - Connect component signals to handler funcs
- `_physics_process()` (Update tick)
  - Handle crash states (early return)
  - `bike_input._bike_update()` - process input first
  - `_update_player_state()` - detect and transition states
  - Call component `_bike_update()` for gearing, physics, tricks, crash, audio, ui
  - `bike_physics.apply_movement()` and `move_and_slide()`
  - `player_animation._bike_update()` - mesh rotation

## How input is handled:
- Input component `components/bike_input.gd`
  - Listens for Input Events & sends signals with values
  - Main script passes ref to this node to each component, they can individually listen for signals
