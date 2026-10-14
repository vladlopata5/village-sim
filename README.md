# VillageSim

Godot 4.7.2 stable, GDScript. Open `project.godot` and Run Project (F5).
The only supported playable scene is `res://scenes/main_3d.tscn`.
Legacy 2D was retired and removed; shared simulation remains active.

Direct startup: `godot --path . res://scenes/main_3d.tscn`.
Import: `godot --headless --editor --path . --import`.
Run a test: `godot --headless --path . --script res://tests/test_game_time.gd`.
Run every remaining `tests/test_*.gd` for full regression; each script exits nonzero
on failure. The orthographic `scenes/prototypes/2_5d_prototype.tscn` is a separate
tested camera/navigation bench, not a gameplay fallback.

Current requirements: `docs/UI_DESIGN.md`, `docs/GAME_DESIGN.md`, `docs/ROADMAP.md`.
Historical decisions/checkpoints: `docs/DECISIONS.md`, `docs/UI_IMPLEMENTATION_PLAN.md`.
