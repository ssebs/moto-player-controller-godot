# Bike README

## How the bike works:

- **Main** `player_controller.gd` script attached to scene
  - Has all onready Node references
- **Component scripts** inherit from `BikeComponent` base class (`_bike_component.gd`)
  - Each of these controls something about the bike (e.g. audio, gearing, ui, etc.)
  - Base class provides:
    - `player_controller` reference
    - `_bike_setup(p_controller)` - override to receive PlayerController and additional params
    - `_bike_update(delta)` - override for per-frame logic
    - `_bike_reset()` - override for respawn reset
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

## Trick System

Tricks are managed by `bike_tricks.gd` using an enum-based detection and scoring system.

### Adding a New Trick

1. **Add to enum** in `bike_tricks.gd`:
```gdscript
enum Trick { NONE, WHEELIE_SITTING, ..., MY_NEW_TRICK }
```

2. **Add to TRICK_DATA**:
```gdscript
const TRICK_DATA: Dictionary = {
    Trick.MY_NEW_TRICK: {"name": "My Trick", "mult": 1.5, "points_per_sec": 20.0},
}
```

3. **Add detection** in `_detect_trick()`:
```gdscript
if my_trick_conditions:
    return Trick.MY_NEW_TRICK
```

### Trick Signals

Connect to these signals for UI/audio/animation reactions:
- `trick_started(trick: int)` - Trick began
- `trick_ended(trick: int, score: float, duration: float)` - Trick completed, score banked
- `trick_cancelled(trick: int)` - Trick interrupted (crash)
- `combo_expired` - Combo window closed

### Scoring

- Tricks accumulate `points_per_sec * mult * delta` while active
- Score banks when trick ends: `trick_score * combo_multiplier`
- Combo: +0.25 per trick (max 4x), 2 second window
- Crash: Loses current trick score, resets combo

### State Access

```gdscript
state.active_trick        # Current BikeTricks.Trick enum
state.trick_score         # Score building for current trick
state.total_score         # Total banked score
state.combo_multiplier    # Current combo (1.0 - 4.0)
state.combo_count         # Tricks in current combo
```
