\# Project Instructions



This is a Godot 4 project written in GDScript.



\## Main goals



\- Keep the code simple and readable.

\- Assume the project owner is a beginner.

\- Prefer straightforward solutions over complex architecture.

\- Do not introduce advanced patterns unless they are clearly necessary.

\- Explain important technical decisions in simple language.



\## Project structure



\- `scenes/` — Godot scenes.

\- `scripts/` — GDScript files.

\- `assets/` — graphics, audio, fonts and other game assets.

\- `docs/` — project documentation.



\## Development rules



\- Use Godot 4.x.

\- Use GDScript unless explicitly requested otherwise.

\- Keep gameplay data separate from visual presentation when practical.

\- Avoid unnecessary dependencies and plugins.

\- Do not rewrite working systems without a clear reason.

\- Make small, focused changes.

\- Before a large change, describe the intended approach.

\- After changing code, check for obvious errors and run the project if possible.

\- If several solutions are possible, prefer the simpler one.



\## Documentation



Before implementing a major feature, check:



\- `docs/GAME\_DESIGN.md`

\- `docs/ROADMAP.md`

\- `docs/DECISIONS.md`



If a technical decision affects future development, record it in `docs/DECISIONS.md`.



Do not invent major game mechanics that are not described in the design documentation. Ask or leave a note when requirements are unclear.



## Current playable scene

Only `res://scenes/main_3d.tscn` is supported. Legacy 2D and its standalone HUD were
removed on 2026-10-14; do not restore legacy compatibility or require legacy startup.
Keep shared simulation/domain systems. `scripts/main.gd` assembles simulation for
Main3D; it is not a retired 2D controller. The independent 2.5D prototype is a tested
camera/navigation bench. Run all remaining `tests/test_*.gd` after shared changes.
