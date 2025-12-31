# Bike README

## How the bike works:

- **Main** `player_controller.gd` script attached to scene
  - Has all onready Node references
- **Component scripts** are a Node + script.
  - Each of these controls something about the bike (e.g. audio, gearing, ui, etc.)
  - Any vars that need to be passed in should use the `_bike_setup()` func
    - > Which is called in the main script's `_ready()` function.
  - **Signals** are exposed to the main script to handle & pipe between components as needed.
    - **...or are they? should this be handled in each components script instead?**
  - Structure - See `player_animation_controller.gd` as best reference.
    - Component Signals
    - Shared state vars - local BikeState var / other components that are needed
    - Local vars
    - `_bike_setup(bike_state, bike_input, [other params])`
      - Can't find a way to have abstract overridable method in gdscript, so just keep to it!
    - Other Signal handlers
    - `_bike_update()` called in `_physics_update()` from main script
    - `_bike_reset()`
      - Default values for respawning

## Bike Event Loop / Sections in Code:

- `@onready` (Node Refs)
- `_ready()` (Initialization)
  - Call component `_bike_setup()` func with relevant params
  - Connect component signals to handler funcs
- `_physics_process()` (Update tick)
  - Call component `_bike_update()`

## How input is handled:
- Input component `components/bike_input.gd`
  - Listens for Input Events & sends signals with values
  - main script passes ref to this node to each component, they can individually listen for signals
