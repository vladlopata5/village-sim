\# Village Sim — Technical Decisions



\## 2026-10-04



\### Engine



Use Godot 4.x.



\### Programming language



Use GDScript.



Reason:

\- simple syntax;

\- close to Python;

\- suitable for a beginner;

\- well integrated with Godot.



\### Game type



The first prototype is 2D.



Do not introduce 3D systems unless the project direction explicitly changes.



\### Project scale



The intended final settlement size is approximately:



\- 30–50 inhabitants for normal gameplay;

\- around 100 inhabitants as an approximate upper limit.



Systems should be designed with this scale in mind.



\### Development approach



Build the game incrementally.



Each development task should be small and testable.



Do not implement systems that are not required by the current roadmap phase.



\### Architecture



Prefer simple composition over complex inheritance hierarchies.



Avoid introducing ECS or other advanced architectures during the early prototype unless a clear performance problem requires it.



\### Simulation and visuals



Game simulation data should not depend directly on visual presentation when practical.



For example:



\- inhabitant data and state should be separable from the sprite representing the inhabitant;

\- game time should be controlled by a dedicated system;

\- events should be represented as data rather than only UI messages.



\### Inhabitant AI



Inhabitants should be autonomous.



The first implementation should use a simple priority-based decision system rather than complex machine learning or behaviour systems.



Decisions may depend on:



\- schedule;

\- needs;

\- assigned job;

\- player orders;

\- personality;

\- current state.



\### Time



The game uses a simulated day/night cycle.



Initial schedule:



\- 06:00–07:00 — morning;

\- 07:00–17:00 — work day;

\- 17:00–23:00 — evening;

\- 23:00–06:00 — night.



Exact timings may change after testing.



\### Population simulation



Do not update every inhabitant's full decision logic every rendered frame.



Decision-making should happen at sensible intervals or when relevant events occur.



\### UI philosophy



Avoid exposing every internal numeric value to the player.



Some information should be communicated through:



\- descriptions;

\- behaviour;

\- conversations;

\- daily chronicles;

\- visible conditions.



Important management information must still remain understandable.



\### Version control



Use Git.



The main branch is:



`main`



Make commits after meaningful working milestones.



Avoid large commits containing several unrelated systems.

