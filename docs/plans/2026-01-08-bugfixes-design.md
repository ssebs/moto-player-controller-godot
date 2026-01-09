# Bugfix Design - 2026-01-08

## Overview

Five bug fixes for the motorcycle controller.

## Bug 1: Input Map Cleanup

**Problem:** `trick_down` and `cam_down` have overlapping bindings. Heel clicker detection uses `cam_down` instead of checking for trick modifier + direction.

**Solution:**
- Remove `trick_up`, `trick_down`, `trick_left`, `trick_right` actions from `project.godot`
- Remove Shift+Down keyboard binding from `cam_down` (keep only right stick axis)
- Update `bike_tricks.gd:536` to check `trick` button + `cam_down` for heel clicker

**Files:** `project.godot`, `bike_tricks.gd`

---

## Bug 2: Easy Mode Auto-Start

**Problem:** Easy mode still requires clutch to start engine.

**Solution:**
- In `bike_gearing.gd` `update_rpm()`, auto-start engine when throttle > 0.1 on EASY difficulty
- Skip clutch requirement entirely for easy mode

**Files:** `bike_gearing.gd`

---

## Bug 3: NOS Steering Reduction

**Problem:** No steering restriction during boost - player can turn freely while boosting.

**Solution:**
- Add `@export var boost_steering_multiplier: float = 0.5` to `bike_tricks.gd`
- In `bike_physics.gd` `handle_steering()`, multiply steering angle by this value when boosting

**Files:** `bike_tricks.gd`, `bike_physics.gd`

---

## Bug 4: Wheelie Lean Forward Fix

**Problem:** On KBM, tapping lean forward then holding lean back locks wheelie at max angle.

**Solution:**
- In `bike_tricks.gd` `_update_wheelie()`, use asymmetric lean multipliers
- Lean back: 0.15 multiplier (current)
- Lean forward: 0.08 multiplier (actively brings front wheel down)

**Files:** `bike_tricks.gd`

---

## Bug 5: Redline RPM Cut

**Problem:** No rev limiter feedback when hitting max RPM.

**Solution:**
- Add `@export var redline_cut_amount: float = 500.0` to `bike_gearing.gd`
- In `update_rpm()`, when RPM >= max and throttle > 0.5, cut RPM by this amount
- Creates natural oscillation, audio follows RPM

**Files:** `bike_gearing.gd`
