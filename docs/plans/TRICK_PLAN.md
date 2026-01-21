# Trick System Redesign Plan

## Status: Design Phase

This plan is a work-in-progress. The proposed architecture (BaseTrick + TrickModifier with a registry) is one approach being considered, but not yet finalized.

**Open questions:**
- Is the modifier system worth the added complexity, or should all tricks be flat/independent?
- How should trick priority and conflicts be resolved (e.g., Kickflip vs Wheelie when both inputs are active)?
- Should detection be purely state-based, or include input buffering for responsiveness?
- How tightly should animations be coupled to trick definitions?
- Is a registry pattern overkill for ~10-15 tricks?

**Do not begin implementation until this section is removed and the plan is marked as approved.**

---

## Problem

The current trick system in [bike_tricks.gd](scenes/bike/components/bike_tricks.gd) is monolithic and hard to extend:
- Hardcoded detection in `_detect_ground_trick()` and `_detect_air_trick()`
- Trick enum, TRICK_DATA dictionary, and detection logic all tightly coupled
- Adding a new trick requires edits in multiple places
- No support for trick modifiers (e.g., "Standing Wheelie" as a variant of "Wheelie")

## Solution: Script-Only Trick Registry

A modular system where each trick is a self-contained script with its own detection logic, scoring, and animation reference.

### Core Concepts

1. **BaseTrick** - A standalone trick (Wheelie, Stoppie, Backflip, Heel Clicker)
2. **TrickModifier** - Requires a parent BaseTrick to be active (Standing Wheelie requires Wheelie active)
3. **TrickRegistry** - Manages detection loop, tracks active trick + modifiers, emits signals
4. **TrickContext** - Snapshot of state/input passed to detection functions

### Trick Hierarchy Examples

```
Wheelie (base, ground)
├── Standing Wheelie (modifier: RB held during wheelie)
├── Wheelie Legs Over Left (modifier: RB + LEFT during wheelie)
└── Wheelie Legs Over Right (modifier: RB + RIGHT during wheelie)

Stoppie (base, ground)

Backflip (base, air) - pitch < -45°
├── Backflip Heel Clicker (modifier: RB + DOWN during backflip)
└── Backflip No Hander (modifier: RB + UP during backflip)

Heel Clicker (base, air) - RB + DOWN while airborne
Kickflip (base, ground) - RB + LEFT on ground
```

## File Structure

```
scenes/bike/tricks/
├── base_trick.gd           # Base class for standalone tricks
├── trick_modifier.gd       # Base class for modifiers
├── trick_registry.gd       # Detection loop, active trick management
├── trick_context.gd        # State snapshot for detection
├── base/
│   ├── wheelie_trick.gd
│   ├── stoppie_trick.gd
│   ├── backflip_trick.gd
│   ├── heel_clicker_trick.gd
│   └── kickflip_trick.gd
└── modifiers/
    ├── standing_wheelie.gd
    ├── wheelie_legs_over_left.gd
    ├── wheelie_legs_over_right.gd
    ├── backflip_heel_clicker.gd
    └── backflip_no_hander.gd
```

## Class Definitions

### TrickContext

```gdscript
# trick_context.gd
class_name TrickContext extends RefCounted

var state: BikeState
var input: BikeInput
var is_on_ground: bool
var is_airborne: bool

# Set by registry before checking modifiers
var active_base: BaseTrick
var active_modifiers: Array[TrickModifier]

static func from_controller(pc: PlayerController) -> TrickContext:
    var ctx = TrickContext.new()
    ctx.state = pc.state
    ctx.input = pc.bike_input
    ctx.is_on_ground = pc.is_on_floor()
    ctx.is_airborne = not ctx.is_on_ground
    ctx.active_base = null
    ctx.active_modifiers = []
    return ctx
```

### BaseTrick

```gdscript
# base_trick.gd
class_name BaseTrick extends RefCounted

enum Context { GROUND, AIR, BOTH }

var id: StringName
var display_name: String
var valid_context: Context = Context.GROUND

# Scoring
var base_points: int = 0
var points_per_sec: float = 0.0

# Animation (played via AnimationPlayer, uses bike's animation library)
var animation_name: StringName = &""  # Empty = no special animation
var animation_loops: bool = false

## Override: Returns true if this trick can start
func can_activate(ctx: TrickContext) -> bool:
    return false

## Override: Returns true if this trick should continue (defaults to can_activate)
func can_continue(ctx: TrickContext) -> bool:
    return can_activate(ctx)

## Override: Called when trick starts
func on_start(ctx: TrickContext) -> void:
    pass

## Override: Called when trick ends
func on_end(ctx: TrickContext) -> void:
    pass
```

### TrickModifier

```gdscript
# trick_modifier.gd
class_name TrickModifier extends RefCounted

var id: StringName
var display_name: String

# Hierarchy
var parent_trick_id: StringName  # ID of the BaseTrick this modifies
var priority: int = 0  # Higher priority wins when multiple modifiers match
var replaces_name: bool = true  # If true, replaces parent's display name

# Scoring (added to base trick)
var bonus_points: int = 0
var bonus_per_sec: float = 0.0

# Animation
var animation_name: StringName = &""
var replaces_animation: bool = true  # If true, overrides base trick animation

## Override: Returns true if this modifier should activate (parent guaranteed active)
func can_activate(ctx: TrickContext) -> bool:
    return false

func on_start(ctx: TrickContext) -> void:
    pass

func on_end(ctx: TrickContext) -> void:
    pass
```

### TrickRegistry

```gdscript
# trick_registry.gd
class_name TrickRegistry extends RefCounted

signal trick_started(trick: BaseTrick, modifiers: Array[TrickModifier])
signal trick_ended(trick: BaseTrick, modifiers: Array[TrickModifier], score: float, duration: float)
signal trick_changed(trick: BaseTrick, modifiers: Array[TrickModifier])  # Modifier changed mid-trick

var _base_tricks: Array[BaseTrick] = []
var _modifiers: Dictionary = {}  # parent_id -> Array[TrickModifier] sorted by priority desc

var active_base: BaseTrick
var active_modifiers: Array[TrickModifier] = []

var _start_time: float = 0.0
var _accumulated_score: float = 0.0

func register_base(trick: BaseTrick) -> void:
    _base_tricks.append(trick)

func register_modifier(modifier: TrickModifier) -> void:
    var parent_id = modifier.parent_trick_id
    if not _modifiers.has(parent_id):
        _modifiers[parent_id] = []
    _modifiers[parent_id].append(modifier)
    _modifiers[parent_id].sort_custom(func(a, b): return a.priority > b.priority)

func update(ctx: TrickContext, delta: float) -> void:
    _update_base_trick(ctx)
    _update_modifiers(ctx)
    _accumulate_score(delta)

## Returns combined display name (modifier overrides or "Base + Mod1 + Mod2")
func get_display_name() -> String:
    ...

## Returns animation to play (highest priority modifier with replaces_animation, or base)
func get_current_animation() -> StringName:
    ...
```

## Example Trick Implementations

### Wheelie (Base)

```gdscript
# base/wheelie_trick.gd
class_name WheelieTrick extends BaseTrick

const PITCH_THRESHOLD_DEG = 15.0

func _init():
    id = &"wheelie"
    display_name = "Sitting Wheelie"
    valid_context = Context.GROUND
    base_points = 50
    points_per_sec = 10.0

func can_activate(ctx: TrickContext) -> bool:
    return ctx.state.pitch_angle > deg_to_rad(PITCH_THRESHOLD_DEG)

func can_continue(ctx: TrickContext) -> bool:
    return ctx.state.pitch_angle > deg_to_rad(PITCH_THRESHOLD_DEG * 0.8)
```

### Standing Wheelie (Modifier)

```gdscript
# modifiers/standing_wheelie.gd
class_name StandingWheelieMod extends TrickModifier

func _init():
    id = &"standing_wheelie"
    display_name = "Standing Wheelie"
    parent_trick_id = &"wheelie"
    priority = 10
    replaces_name = true
    bonus_points = 50
    bonus_per_sec = 10.0
    animation_name = &"wheelie_standing"

func can_activate(ctx: TrickContext) -> bool:
    # RB (trick button) held during wheelie
    return ctx.input.trick
```

### Wheelie Legs Over Left (Modifier)

```gdscript
# modifiers/wheelie_legs_over_left.gd
class_name WheelieLegsOverLeftMod extends TrickModifier

func _init():
    id = &"wheelie_legs_over_left"
    display_name = "Wheelie Legs Over"
    parent_trick_id = &"wheelie"
    priority = 20  # Higher than standing wheelie
    replaces_name = true
    bonus_points = 100
    bonus_per_sec = 25.0
    animation_name = &"wheelie_legs_over_left"

func can_activate(ctx: TrickContext) -> bool:
    # RB + LEFT during wheelie
    return ctx.input.trick and Input.is_action_pressed("cam_left")
```

### Backflip (Base - Air Only)

```gdscript
# base/backflip_trick.gd
class_name BackflipTrick extends BaseTrick

const ROTATION_THRESHOLD_DEG = 45.0

func _init():
    id = &"backflip"
    display_name = "Backflip"
    valid_context = Context.AIR
    base_points = 300
    points_per_sec = 50.0

func can_activate(ctx: TrickContext) -> bool:
    # Backward rotation (negative pitch) while airborne
    return ctx.state.pitch_angle < deg_to_rad(-ROTATION_THRESHOLD_DEG)
```

### Backflip Heel Clicker (Modifier)

```gdscript
# modifiers/backflip_heel_clicker.gd
class_name BackflipHeelClickerMod extends TrickModifier

func _init():
    id = &"backflip_heel_clicker"
    display_name = "Backflip Heel Clicker"
    parent_trick_id = &"backflip"
    priority = 10
    replaces_name = true
    bonus_points = 200
    bonus_per_sec = 30.0
    animation_name = &"heel_clicker"

func can_activate(ctx: TrickContext) -> bool:
    # RB + DOWN during backflip
    return ctx.input.trick and Input.is_action_pressed("cam_down")
```

### Heel Clicker (Base - Air Only, Standalone)

```gdscript
# base/heel_clicker_trick.gd
class_name HeelClickerTrick extends BaseTrick

func _init():
    id = &"heel_clicker"
    display_name = "Heel Clicker"
    valid_context = Context.AIR
    base_points = 200
    points_per_sec = 50.0
    animation_name = &"heel_clicker"

func can_activate(ctx: TrickContext) -> bool:
    # RB + DOWN while airborne (but not during backflip - registry handles priority)
    return ctx.input.trick and Input.is_action_pressed("cam_down")
```

### Kickflip (Base - Ground Only)

```gdscript
# base/kickflip_trick.gd
class_name KickflipTrick extends BaseTrick

func _init():
    id = &"kickflip"
    display_name = "Kickflip"
    valid_context = Context.GROUND
    base_points = 200
    points_per_sec = 0.0  # Instant trick, no duration scoring
    animation_name = &"kickflip"

func can_activate(ctx: TrickContext) -> bool:
    # RB + LEFT on ground
    return ctx.input.trick and Input.is_action_pressed("cam_left")
```

## Integration with BikeTricks

The existing `bike_tricks.gd` delegates detection to the registry:

```gdscript
# bike_tricks.gd (simplified)
var registry: TrickRegistry

func _bike_setup(p_controller):
    super(p_controller)
    registry = TrickRegistry.new()
    _register_tricks()

    registry.trick_started.connect(_on_trick_started)
    registry.trick_ended.connect(_on_trick_ended)
    registry.trick_changed.connect(_on_trick_changed)

func _register_tricks():
    # Base tricks
    registry.register_base(WheelieTrick.new())
    registry.register_base(StoppieTrick.new())
    registry.register_base(BackflipTrick.new())
    registry.register_base(HeelClickerTrick.new())
    registry.register_base(KickflipTrick.new())

    # Modifiers
    registry.register_modifier(StandingWheelieMod.new())
    registry.register_modifier(WheelieLegsOverLeftMod.new())
    registry.register_modifier(WheelieLegsOverRightMod.new())
    registry.register_modifier(BackflipHeelClickerMod.new())
    registry.register_modifier(BackflipNoHanderMod.new())

func _bike_update(delta):
    var ctx = TrickContext.from_controller(player_controller)
    registry.update(ctx, delta)
    _update_combo_timer(delta)
    _update_boost(delta)
```

## Animation Integration

Each trick/modifier has an optional `animation_name` that references animations in the bike's animation library (e.g., `sport_bike/heel_clicker`). The `BikeAnimation` component listens to registry signals:

```gdscript
func _on_trick_started(trick: BaseTrick, modifiers: Array[TrickModifier]):
    var anim = player_controller.bike_tricks.registry.get_current_animation()
    if anim != &"":
        player_controller.anim_player.play(_get_anim(anim))

func _on_trick_changed(trick: BaseTrick, modifiers: Array[TrickModifier]):
    var anim = player_controller.bike_tricks.registry.get_current_animation()
    if anim != &"":
        player_controller.anim_player.play(_get_anim(anim))

func _on_trick_ended(trick: BaseTrick, modifiers: Array[TrickModifier], score: float, duration: float):
    player_controller.anim_player.play(_get_anim("RESET"))
```

## Input Reference

Current input actions used for tricks:
- `trick` (RB) - Trick button, accessed via `ctx.input.trick`
- `cam_left` - D-pad/stick left
- `cam_right` - D-pad/stick right
- `cam_up` - D-pad/stick up
- `cam_down` - D-pad/stick down
- `lean_forward` / `lean_back` - Lean input, accessed via `ctx.input.lean`

## Existing Animation Library

Animations are defined per-bike in animation libraries:
- `sport_bike/heel_clicker`
- `sport_bike/kickflip`
- `sport_bike/naruto_run_start` (boost)
- `sport_bike/naruto_run_loop` (boost loop)
- `sport_bike/idle_stopped`

New animations needed for modifiers:
- `{bike}/wheelie_standing`
- `{bike}/wheelie_legs_over_left`
- `{bike}/wheelie_legs_over_right`
- `{bike}/backflip` (if visual needed)
- `{bike}/no_hander`

## Detection Flow

Each frame:
1. Create `TrickContext` from current state
2. Check if `active_base` can continue → if not, end trick
3. If no `active_base`, iterate `_base_tricks` and check `can_activate()`
4. If `active_base` exists, check all modifiers for that base
5. Highest priority modifier that `can_activate()` wins
6. If modifier set changed, emit `trick_changed`
7. Accumulate score: `(base.points_per_sec + sum(mod.bonus_per_sec)) * delta`

## Scoring

- **While active:** `points_per_sec` accumulated each frame
- **On end:** `base_points + sum(modifier.bonus_points)` added
- **Combo multiplier:** Applied by `BikeTricks` when committing score (not in registry)

## Next Steps

1. Create the folder structure under `scenes/bike/tricks/`
2. Implement `TrickContext`, `BaseTrick`, `TrickModifier`, `TrickRegistry`
3. Implement base tricks: Wheelie, Stoppie, Backflip, Heel Clicker, Kickflip
4. Implement modifiers: Standing Wheelie, Wheelie Legs Over variants, Backflip Heel Clicker
5. Refactor `bike_tricks.gd` to use the registry
6. Update `bike_animation.gd` to listen to registry signals
7. Create missing animations
