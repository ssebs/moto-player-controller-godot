# Bike README

## How the bike works:

- Main `player_controller.gd` script attached to scene
  - Has all onready Node references
- Component scripts are a Node + script.
  - Each of these controls something about the bike (e.g. audio, gearing, ui, etc.)
  - Any vars that need to be passed in should use the `setup()` func, which is called in the main script's `_ready()` function.
  - Signals are exposed to the main script to handle & pipe between components as needed.

## Bike Event Loop / Sections in Code:

- `@onready` (Node Refs)
- `_ready()` (Initialization)
- .

## How input is handled:
- Input component `components/bike_input.gd`
  - Listens for Input Events & sends signals with values
  - main script passes ref to this node to each component, they can individually listen for signals
