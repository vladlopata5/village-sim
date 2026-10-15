# Проверки достижимости и подготовка движения

Актуально после P3.1 (2026-10-15). Игровая сцена: main_3d.tscn.

## Два разных контракта

`NavigationGrid.has_walkable_path(start, target)` отвечает только на вопрос о
наличии допустимой точечной ломаной. Это не connectivity precheck и не готовый
маршрут для executor. Он выполняет обычный взвешенный AStarGrid2D и обязательный
`is_raw_path_walkable`; optional smoothing не вызывается.

`NavigationGrid.can_reach_point` остаётся дешёвым X/Z connectivity precheck.
Положительный результат этого precheck не подменяет полную точечную проверку.
Ресурсный адаптер сохраняет последовательность can_reach_point → has_walkable_path.

`find_path` возвращает прежний сглаженный маршрут. `GridMovement3D.advance`
получает raw path/hint, вызывает smooth_path и строит traversal segments.
Реальное движение, стоимость прохода по поверхностям и обработка прибытия прежние.

## Обязательная геометрия

find_raw_path проверяет finite/bounds/world_walkable endpoints, использует сетку
с inflated blockers для resident radius, запретом диагонального срезания углов и
прежними terrain weights. Размер клетки и карта не меняются. Клеточная
дискретизация может закрыть узкий проход даже при формально достаточной ширине
между физическими mesh; probe сохраняет тот же ответ, что прежний find_path.

is_raw_path_walkable повторяет обязательный prefix smooth_path: удаление дубликатов
и точная коллинеарная compaction, допустимая первая точка, supercover LOS каждого
сегмента. Поэтому непустая, но небезопасная ломаная отвергается. После этого prefix
smooth_path лишь сокращает путь и сравнивает стоимость shortcut; не вводит
максимальную длину/стоимость как причину отказа. При исчерпании optional budget
сохраняется уже проверенный tail. Это обосновывает bool-эквивалентность, а не
предположение о безопасности любого raw path.

Проверка не кэшируется и не резервирует ресурс. Если препятствие/revision изменится
после probe, executor заново подготавливает текущую геометрию и может отказать.
Новый helper не меняет выделение portal/entrance, слота работы/посетителя или
ownership intent. Счётчики last_smoothing_* относятся к последнему реальному
сглаживанию и игровыми решениями не используются.

## Карта текущих потребителей

| Потребитель | Назначение | Контракт |
|---|---|---|
| Main3D._reachable_wander_target | Отбор допустимой точки прогулки | has_walkable_path |
| Main3D._resource_route_available | ResourceSources.reachable для еды/перевозок/self logistics | connectivity + has_walkable_path |
| Lumberjack._path | Допустимость экспорта; расстояние оценивается отдельно | has_walkable_path |
| NaturalSourceLocations3D.resolve | Выбор точки approach annulus для дерева/камня/посадки | find_path_to_radius, без изменения |
| Main3D construction material planner | P1 стоимость и одноразовые raw hints | raw + mandatory geometry + raw cost, без изменения |
| GridMovement3D | Фактическое движение | raw/hint + smooth + traversal segments |

WorkArea, локальные ground области и глобальная доступность контейнеров прежние.
Не добавлены queue, scheduler budget, новые routing/cache policies или deferred
AI actions. Порядок RNG/claims не менялся. Переиспользование проверенного raw path
для обычного движения и устранение повторного PLANT scan остаются возможностями
отдельных этапов.

## Верификация и измерения

`tests/test_reachability_probes.gd` сравнивает bool helper с прежним полным путём
на препятствиях, границах/углах, разных clearance и весах; включает unsafe raw
fixture, динамические изменения и реальные canonical access points. Исполнитель
после probe по-прежнему сглаживает, прибывает либо отказывает при новой преграде.
`test_assignment_dialog` считает raw/radius queries, чтобы новый helper не мог
скрыть дорогой запрос от read-only admission assertions.

Внешние before/after microbench, fixed-step traces 30/100 жителей, автономные
120-секундные controls и отдельные counters/timers:
`C:/Users/SW/Documents/Codex/outputs/performance-optimization-p3-1/REPORT.md`.
Показания instrumented runs не используются как обычный FPS. Устранение optional
smoothing не обещает убрать массовый AI/строительный notification fan-out.

В измеренном 120-секундном прогоне на 100 жителях bool smoothing: 20156 → 0;
после правки сохранено 14000 smoothing реального движения. При фиксированном
времени совпали 61 снимок состояния и 21211 action events. Полный набор 137/137,
анализатор 298/298 с четырьмя прежними предупреждениями. В одном ordinary control
P99: 34.871 → 25.504 мс; median практически прежний. Это ограниченное сравнение,
не гарантия устранения всех пиков. Все подробные результаты находятся вне Git.
