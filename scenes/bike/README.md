# Bike README

## How the bike works:

- Main `player_controller.gd` script attached to scene
  - Has all onready Node references
- Component scripts are a Node + script.
  - Each of these controls something about the bike (e.g. audio, gearing, ui, etc.)
  - Any vars that need to be passed in should use the `bike_setup()` func, which is called in the main script's `_ready()` function.
  - Signals are exposed to the main script to handle & pipe between components as needed.
  - Structure - See `player_animation_controller.gd` as best reference.
    - > Extends BikeComponent
    - Shared state vars - local BikeState var / other components that are needed
    - Local vars
    - `bike_setup(bike_state, bike_input, [other params])`
    - Signal handlers
    - `bike_update()` called in _physics_update() from main script
    - `bike_reset()`
      - Default values for respawning

## Bike Event Loop / Sections in Code:

- `@onready` (Node Refs)
- `_ready()` (Initialization)
  - Call component `bike_setup()` func with relevant params
  - Connect component signals to handler funcs
- `_physics_process()` (Update tick)
  - Call component `bike_update()`

## How input is handled:
- Input component `components/bike_input.gd`
  - Listens for Input Events & sends signals with values
  - main script passes ref to this node to each component, they can individually listen for signals
