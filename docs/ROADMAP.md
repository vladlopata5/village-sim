# Village Sim — Roadmap

## Текущий запуск: canonical main_3d (2026-10-09)

Основная playable scene — `scenes/main_3d.tscn`; F5 / Run Project запускает её.
Основной foundation перехода 2D → 3D/2.5D завершён. `scenes/main.tscn` сохранена
как legacy/reference presentation/runtime и запускается отдельно (F6 / direct
scene startup), включая существующие integration tests. Simulation/Domain остаётся
общей активной архитектурой, не legacy. Новые gameplay/world features развиваются
прежде всего в main_3d; параллельное развитие 2D требует отдельной причины.
Исторические записи ниже о F5/2D default описывают прошлые этапы и заменены этим
статусом. Это завершение foundation, не реализация отложенных cargo visuals, terrain,
crowd avoidance или полноценной interaction-point system.


## Цель первого прототипа

Проверить, интересно ли наблюдать за небольшим поселением, где каждый житель:

- имеет характер;
- имеет потребности;
- работает;
- самостоятельно принимает простые решения;
- взаимодействует с другими;
- оставляет после себя заметные события.

Первый прототип не должен быть полноценной игрой.

Визуальная часть первого прототипа временная.

Для скорости разработки используется простое 2D-представление.

---

## Phase 1 — Техническая основа

Цель:

Получить работающий Godot-проект с базовой игровой сценой и игровым временем.

Сделать:
- основную игровую сцену;
- простое временное 2D-игровое поле;
- базовую камеру;
- паузу;
- скорости времени x1, x2 и x4;
- игровые часы;
- смену фаз суток.

Фазы:
- утро;
- день;
- вечер;
- ночь.

Результат:

Работает базовая игровая сцена, камера и игровое время.

Визуальная часть считается временной и используется только для проверки игровых систем.

---

## Phase 2 — Один житель

Статус: завершён. NightHomeController и ResidentIntent — ранняя основа Phase 3. Shift+1/Shift+2/Shift+3 остаются временными инструментами разработки.

Добавить одного жителя.

Житель должен иметь:
- имя;
- возраст;
- голод;
- усталость;
- настроение;
- профессию;
- несколько черт характера.

Добавить простую карточку жителя.

Добавить возможность перемещения жителя по карте.

Результат:

Игрок может выбрать персонажа, посмотреть базовую информацию и увидеть его движение по миру.

---

## Phase 3 — Распорядок дня

Статус: завершён по принятому объёму Phase 3. Реализован базовый цикл IDLE → рабочий маршрут → WORKING → IDLE → домашний маршрут → SLEEPING → IDLE через единый ResidentScheduleController. Производство, питание, общение и остальные части распорядка пока не реализованы.

Реализовать поведение по времени суток.

Утро:
- подготовка к дню;
- еда;
- простые бытовые действия.

День:
- работа;
- поручения.

Вечер:
- отдых;
- общение;
- личные действия.

Ночь:
- сон;
- ускоренное течение времени.

Результат:

Житель самостоятельно проживает полный игровой день.

---

## Phase 4 — Базовые потребности

Добавлен первый PlayerCommand MOVE_TO: абсолютное управление игрока выше AI,
ПКМ по земле выдаёт команду, ПКМ по объекту открывает capability-based меню.
PlayerOrder заменён разделением PlayerCommand / ResidentAssignment; поручения
теперь работают как хронологический список: EAT_AT_TARGET участвует вместе с
обычными action candidates через UtilitySelector с ASSIGNMENT_BONUS=3000.
Формула UtilitySelector и баланс потребностей не изменены.
Подробности текущего контракта и проверок в PHASE_4.md.

Дополнительно согласован первый Player Control Layer: выбор одного жителя с выделением,
карточка и назначение NONE/PORTER/GATHERER через simulation API. Автономный AI
сохраняется; безопасный рабочий цикл/доставка завершается после смены назначения.
Первоначальная заготовка PlayerOrder затем заменена PlayerCommand и
ResidentAssignment; реализовано поручение «Поесть здесь», без FIFO и без UI списка. Подробности в PHASE_4.md.

Статус: продолжается. Реализованы четыре жителя, HUNGER/FATIGUE/SOCIAL/LEISURE, питание, отдых, групповые разговоры, critical/forced и pending, локальные ограниченные ресурсы, две физические трассы доставки и запрос задач носильщиком через DecisionController. В принятый объём Phase 4 добавлена первая производственная цепочка: GATHERER Фёдор реально WORKING в gatherer_hut_01 → FOOD в локальном output → PORTER Степан → Склад → Кухня. Общий production_progress принадлежит зданию; полный output останавливает накопление. Срочность задач динамическая по projected fill с reserved_in/out; кухня снабжается до capacity=20 без старого target=3. Подробности и проверки в PHASE_4.md. Phase 4 ещё не объявлен завершённым.

Добавить:
- голод;
- сон;
- социальную потребность.

Добавить простые точки или здания для удовлетворения этих потребностей.

Примеры:
- дом;
- место для еды;
- место для общения.

Житель должен самостоятельно реагировать на сильные потребности.

Результат:

Игроку не нужно контролировать каждое движение жителя.

---

## Phase 5 — Работа и ресурсы

Phase 5 не начат. Первая цепочка FOOD и склад уже реализованы в согласованном объёме Phase 4; остальные пункты ниже остаются будущими.

Добавить ресурсы:
- дерево;
- еда.

Добавить:
- лес;
- склад;
- рабочее место лесоруба;
- простое производство еды.

Рабочий цикл:

найти работу → дойти до объекта → выполнить действие → получить или перенести ресурс.

Результат:

Поселение начинает функционировать как простая экономическая система.

---

## Phase 6 — Несколько жителей

Увеличить население примерно до 10 жителей.

Добавить:
- разные имена;
- разные профессии;
- разные параметры;
- разные черты характера;
- распределение рабочих мест.

Результат:

Жители начинают вести себя по-разному в одинаковых ситуациях.

---

## Phase 7 — Простые отношения

Добавить:
- знакомство;
- симпатию;
- неприязнь;
- дружбу.

Жители могут взаимодействовать друг с другом.

Характер влияет на вероятность и результат общения.

Результат:

Между жителями начинают появляться различимые отношения.

---

## Phase 8 — События и летопись

Создать систему событий.

Примеры:
- житель познакомился с другим;
- улучшил навык;
- поссорился;
- сильно устал;
- впервые выполнил работу;
- обнаружил талант.

События должны иметь уровень важности.

В конце дня показывать краткую летопись.

Результат:

Игрок начинает воспринимать симуляцию как последовательность историй.

---

## Phase 9 — Скрытые желания

Добавить простые личные желания.

Пример:

Жителю скучно по вечерам.

Игрок не видит точное внутреннее условие.

Информацию можно получить через:
- наблюдение;
- летопись;
- разговор.

Добавить несколько возможных способов удовлетворить одну проблему.

Результат:

Игрок интерпретирует поведение жителей, а не только оптимизирует числа.

---

## Phase 10 — Разговоры

Добавить простую систему разговоров.

Игрок может выбрать жителя и спросить:
- как дела;
- как работа;
- как семья;
- чего ему не хватает.

Ответы зависят от состояния и характера.

Разговор не должен быть обязательным для обычного управления.

Результат:

Игрок может лучше узнавать отдельных жителей.

---

## Phase 11 — Первый играбельный прототип

Целевая конфигурация:
- 10–15 жителей;
- 3 профессии;
- 5–6 зданий;
- 2–3 простые производственные цепочки;
- день и ночь;
- потребности;
- характер;
- простые отношения;
- события;
- ночная летопись;
- скрытые желания;
- простые разговоры.

После этого разработку временно остановить и оценить:

- интересно ли наблюдать за жителями;
- запоминаются ли отдельные персонажи;
- понятны ли причины их поведения;
- не слишком ли много микроменеджмента;
- хочется ли игроку узнать, что произойдёт завтра;
- работает ли дневная летопись;
- полезны ли разговоры;
- достаточно ли свободы у жителей.

Только после проверки прототипа переходить к следующим системам.

---

## После первого прототипа

Возможные следующие системы:
- семьи;
- дети;
- взросление;
- старение;
- смерть;
- родословные;
- торговля;
- политики;
- экспедиции;
- культура;
- религия;
- более сложные производственные цепочки;
- большая карта;
- поселение на 30–50 жителей;
- развитие поселения по эпохам;
- более сложные события.

Отдельно после прототипа необходимо решить финальное визуальное направление:

- остаться в 2D;
- перейти в изометрию / 2.5D;
- перейти в полноценное 3D.

## 2026-10-06 — TALK_TO: поручение на конкретного собеседника

TALK_TO хранит конкретный resident_id в ResidentAssignment.target. Пункт «Поговорить с …»
в контекстном меню другого жителя добавляет QUEUED-поручение через PlayerControl, не прерывая
текущее действие. Самому себе такое поручение дать нельзя. UI не управляет разговором.

Доступный TALK_TO участвует в обычном UtilitySelector с utility SOCIAL + ASSIGNMENT_BONUS
(3000). Порядок списка не влияет на utility. Временно занятый собеседник исключается из
кандидатов, поручение остаётся QUEUED; удалённый собеседник означает CANCELLED.
Изменения доступности уведомляют ожидающих жителей событиями, без retry cooldown.

Исполнение использует существующие движение SOCIAL, ConversationGroup и правила TALKING.
SOCIAL=0 не мешает принять разговор. Поручение выполняется после MIN_CONVERSATION_MINUTES
(15) непрерывного совместного присутствия жителя и конкретной цели в одной группе.
Время начинается заново при выходе/повторном входе цели; общий возраст группы не заменяет
совместное время. После COMPLETED сам разговор может продолжаться.

Независимый разговор тоже может выполнить одно подходящее поручение. ACTIVE-поручение
имеет право на свой результат первым; иначе закрывается самое старое подходящее QUEUED
(или ожидающее SUSPENDED) по порядку добавления. За один разговор жителя закрывается максимум
один экземпляр; дубликаты остаются отдельными поручениями и не удаляются.

Ранний выход цели или прерывание PlayerCommand/critical AI возвращает незавершённое
исполнение в QUEUED. Уже достигнутый COMPLETED не откатывается. Резервирования еды,
critical EAT merge, UtilitySelector, веса и общая иерархия управления не изменяются.
Отношения, отказ от приглашений и отдельный таймер assignment-разговора не добавлены.


## 2026-10-06 — UI списка поручений

Минимальный UI списка ResidentAssignment реализован в панели выбранного жителя:
незавершённые поручения, читаемые цель/состояние, индивидуальная отмена и прокрутка.
История, reorder и importance controls остаются вне текущего объёма.

## 2026-10-06 — первый контур Building Placement

Реализованы сворачиваемая нижняя панель четырёх текущих типов, placement ghost,
footprint overlap и создание UNDER_CONSTRUCTION в общем реестре. BuildingInstance
сохраняется весь lifecycle UNDER_CONSTRUCTION → BUILT; Definition описывает тип.
Стартовые здания/дома BUILT. Доставка материалов, строительный progress и builder
profession ещё не реализованы; этот шаг не объявляет строительную систему завершённой.

## 2026-10-07 — construction data foundation

Выполнен фундамент: WOOD; требования/work-minutes/max_builders в Definition;
фактически delivered/progress/slot owners в едином BuildingInstance; проверяемый
UNDER_CONSTRUCTION → BUILT без замены entity; реальные данные в BuildingCard.
Следующие этапы по-прежнему отдельные: строительная доставка, Builder profession/AI,
фактическая работа и автоматическое завершение/подключение новых зданий к системам.

## 2026-10-07 — базовый строительный цикл готов

Реализованы BUILDER, самостоятельный выбор стройки, слоты, собственная физическая
доставка WOOD с reservations, building-owned work progress, несколько строителей,
completion и подключение BUILT к обычным системам. Стартовый WOOD=50 — prototype stock.
Строительство проверяется без внешнего назначения task и без Porter HaulJob.
Производство древесины, лесоруб, лес, новые материалы, ремонт и upgrades остаются будущими.


### Выполнено в Phase 4: выбор доставки носильщиком (2026-10-07)

PORTER сам выбирает concrete delivery на своём normal work decision point;
потенциальные deliveries не являются persistent jobs. Current projected urgency
и full route формируют deterministic porter_score; personal modifier пока 0.
HaulJob создаётся только после успешного atomic claim уже assigned и дальше committed.
Свободный pool/refresh priorities удалены. LogisticsController — сервис, не
диспетчер работников. Добавлено независимое физическое выполнение нескольких
носильщиков и local event-driven availability без нового scheduler. Builder
construction transport остаётся отдельным workflow.


### Выполнено в Phase 4: housing relationship/data/UI foundation (2026-10-07)

Optional ResidentData.home_location_id, prototype HOME capacity=4, query жильцов,
ручные assign/clear/reassign через management API/context menu и event-driven
ResidentCard/BuildingCard. Homeless допустим, завершённый дом не auto-fills.
Следующие отдельные этапы: sleep-location behavior и housing quality; в этом шаге
новое назначение дома не меняет сон и не создаёт PlayerCommand/ResidentAssignment.

### Выполнено в Phase 4: ordinary sleep-location (2026-10-07)

Текущий home_location_id выбирает обычный ночной маршрут к валидному BUILT HOME
при старте действия; единственный source of truth — housing связь resident.
Homeless/invalid home — сон снаружи на текущем месте. Pending использует новый home,
committed путь/сон не reroute-ится при переселении. Несколько жителей могут спать
в одном доме. Critical fatigue остаётся on-the-spot; PlayerCommand прерывает сон.
Sleep quality реализована следующим этапом ниже; beds/slots/penalties отсутствуют.

### Выполнено в Phase 4: единая архитектура стартовых HOME (2026-10-07)

Четыре prebuilt starting houses — обычные BuildingInstance HOME в Main.buildings,
capacity 4, без personal ownership. Starting setup и player-built HOME используют
одинаковые definition/view/lookup/selection/card/housing/sleep/collision systems.
Отдельный домашний визуал удалён; новые placement по-прежнему UNDER_CONSTRUCTION.

### Выполнено в Phase 4: базовое качество сна (2026-10-07)

Числовой committed multiplier: HOME_SLEEP_QUALITY=1.0,
OUTDOOR_SLEEP_QUALITY=0.6. Critical fatigue on-the-spot использует outdoor quality.
Восстановление fatigue зависит от base rate × quality, от игровых минут и паузы;
awake growth/другие needs не меняются. Reassign не меняет active sleep quality.
Weather, furniture, beds и различные housing quality tiers отложены.


### Выполнено в Phase 4: foundation профессиональных навыков (2026-10-07)

Три постоянных навыка: GATHERING, CONSTRUCTION, LOGISTICS. ResidentData XP —
source of truth, derived level 0..10 при prototype progression 10 XP/level.
Один завершённый gatherer/construction cycle или Porter delivery даёт +1 XP
соответствующего навыка; interruption/WOOD transport не дают XP. Profession switch
сохраняет все навыки. ResidentCard показывает level/XP с signal update.
Gameplay effects, task requirements, AI preferences и training — отдельные этапы.


### Выполнено в Phase 4: traits + behavior modifier foundation (2026-10-07)

Семь traits, ровно две seeded-compatible черты при generation; persistent data
и add/remove/conflict API. Narrow resolver вычисляет effective ordinary utility,
EAT threshold, movement speed и selector parameters. UI traits event-driven.
UtilitySelector generic, forced/critical/night/management bypass сохранён.
Mood/weather/health/events/policies и skill gameplay modifiers — будущие этапы.


### Выполнено в Phase 4: directed relationship foundation (2026-10-07)

ResidentData хранит sparse исходящие ResidentRelationship: stable target ID и
opinion −100..100. Отсутствующая запись neutral; initial opinions=0. Независимые
направления, get/set/change API, local signals и event-driven ResidentCard.
Gameplay effects, compatibility, social memories, relationship states, shared
events, genealogy и chronicle/biography — следующие отдельные дизайнерские этапы.
Conversation gain/decay и friendship thresholds сейчас отсутствуют.


### Выполнено в Phase 4: личные trait preferences (2026-10-07)

Persistent likes/dislikes (2/1 generated), validation/mutation API, directed
derived +10/−10 trait score без pair storage. Separate seeded preference RNG
сохраняет существующую trait/name/needs generation. ResidentCard показывает
предпочтения и selected→other score с event-driven обновлением target traits.
Отдельная symmetric compatibility заменена на текущем этапе personal tastes.
SOCIAL/TALK_TO/opinion effects и memories/mood/context/event combinations — позже.


### Выполнено в Phase 4: Social Events (2026-10-08)

Одна context-based система, event-driven start hooks Conversation/Meal/work cycle.
Semantic location pool, uniform target, derived directed attitude и independent
reactions → existing opinion API. Twelve data-driven texts, A/B orientation,
equal-weight selection после mechanics. Отдельные Feed и optional resident diary;
TEMPORARY до следующего утра, KEY permanent. Porter WORK social hook отложен до
подходящего semantic work lifecycle. Psychological memory и social AI feedback
остаются будущими этапами.


### Выполнено: первый изолированный 2.5D technical prototype (2026-10-08)

Отдельная 3D-сцена: ground, orthographic camera (50°), primitive Resident/Building,
ray picking, unified selection и direct MOVE_TO по X/Z. Минимальный debug HUD.
Существующий 2D main остаётся default; gameplay systems не мигрированы.
Дальнейший переход presentation/navigation выполняется отдельными этапами;
world scale, препятствия и pathfinding этим prototype не решаются.

Запуск: открыть `scenes/prototypes/2_5d_prototype.tscn` в Godot и нажать F6
(Run Current Scene). F5 по-прежнему запускает 2D игру. Также можно запустить
Godot с `--path <project-directory> res://scenes/prototypes/2_5d_prototype.tscn`.


### Выполнено: static Navigation3D prototype (2026-10-08)

В изолированном 2.5D slice MOVE_TO следует реальному NavigationAgent3D path,
обходит тестовое Building и завершает команду по navigation-aware arrival.
NavigationRegion3D использует pre-baked mesh; есть visual debug path и безопасная
отмена invalid/unreachable targets. Runtime navigation updates для construction
и crowd avoidance отложены. Основная 2D main scene и gameplay systems сохранены.


### Начата отдельная migration phase: основная simulation → 3D presentation

- Выполнен первый `scenes/main_3d.tscn`: общий starter setup/Main wiring, все 4
  residents и 7 buildings, существующие cards/HUD/Feed, unified ray selection,
  настоящие PlayerCommand MOVE_TO и static Navigation3D.
- Согласован executor-owned physical position; simulation Vector2 ↔ world X/Z.
- Добавлен единый временный building default access point bridge.
- Реальные EAT, porter delivery, gatherer production и ordinary home sleep
  проверены через 3D navigation; остальные domain systems остаются подключены.
- Следующие migration этапы: runtime placement/navmesh updates, полноценные
  interaction points, cargo/ground-resource visuals и crowd movement.
- 2D main пока остаётся F5 default; main_3d запускается F6 или отдельной командой.
  Primitive graphics и static bake — временные. Полная migration не завершена.


### Выполнено: dynamic NavigationGrid foundation для main_3d

- Main_3d global pathfinding заменён на NavigationGrid/AStarGrid2D; скрытая сетка
  0.5 world unit, bounds 128×80, 256×160 cells. Presentation scale 1:25 согласован,
  simulation units/баланс сохранены.
- Physical footprint и resident clearance разделены. Stable dynamic blocker IDs /
  refcounts, runtime add/remove, corner-safe диагонали и LOS smoothing реализованы.
- Executor position authority, PlayerCommand, access-point bridge и domain workflows
  сохранены; debug blocked/raw/smooth доступен по отдельному UI toggle.
- Следующие этапы: отдельный BuildGrid 0.5, actual placement integration с blockers,
  demolition/trees/roads и terrain height/cost/slope; эти gameplay systems не добавлены.
- Старый navmesh prototype сохранён. Main_3d navmesh bake/runtime rebake больше не
  требуются для global connectivity. Полная presentation migration ещё не завершена.


### Runtime placement/construction в main_3d через BuildGrid (2026-10-08)

- Выполнены отдельный BuildGrid 0.5 и authoritative owner occupancy; NavigationGrid
  остаётся отдельной системой 0.5 с clearance/refcounts.
- Выполнены 3D ghost/snap, rotation 90° increments, validation, прежняя ConstructionPanel
  и runtime UNDER_CONSTRUCTION placement с немедленным navigation blocker update.
- Existing builder WOOD workflow, 60-minute cycles, completion и live cards работают
  с runtime buildings; starter/runtime registration единая. Unfinished cancellation API
  освобождает occupancy/navigation без rebake; demolition gameplay остаётся позже.
- Footprints в definition build cells: HOME 6×4; остальные current types 12×8.
  Default access point остаётся временным rotation-aware migration bridge.
- Дальше: cargo/ground-resource visuals, полноценные interaction points, terrain,
  roads/trees и crowd movement. F5 остаётся 2D fallback; полная migration не завершена.


### Выполнено: runtime placement blockers (2026-10-09)

- Placement отдельно от static BuildGrid проверяет generic live X/Z circle providers.
- Residents подключены с radius=0.4; partial overlap/rotation и confirm-time recheck
  предотвращают размещение поверх движущейся сущности.
- Future Animal/Cart/Vehicle смогут opt-in в тот же contract; сами systems не добавлены.
  NavigationGrid/crowd avoidance по-прежнему отдельны от placement blockers.


### Выполнено: cleanup main_3d перед default switch (2026-10-09)

- Wander targets проверяются по NavigationGrid до создания intent, до 8 попыток.
- Starter footprints выровнены явно в shared setup по runtime BuildGrid snap.
- Main scene switch не выполнен: F5 по-прежнему запускает 2D fallback.


### First physical forestry chain: Tree → LOG (2026-10-09)

Canonical main_3d имеет 16 deterministic individual Trees в западной области
X=-34.25..-25.25, Z=-13.25..-4.25 world units; они не snapped и не занимают BuildGrid.
TreeData: stable ID/kind TREE, simulation position, physical radius 0.35, STANDING /
DEPLETED, separate reservation owner, persistent work_done/work_required и yield.
Standing tree блокирует NavigationGrid через physical bounding rectangle + standard
resident clearance 0.4 и generic runtime circle placement contract; никаких Tree
branches в validator. Depletion снимает оба blockers без rebake и убирает view.

Исторический forestry foundation: LUMBERJACK первоначально работал без workplace;
текущая модель с хижиной описана ниже.
На обычном daytime WORK decision выбирается ближайшее standing unreserved tree
с reachable access point, deterministic ID tie-break. Perimeter resolver проверяет
8 фиксированных directions / 3 outward rings через NavigationGrid и выбирает
ближайшую доступную точку к worker. Runtime executor по-прежнему владеет WORLD
position; domain positions и target используют scale bridge 1:25.

После реального arrival начинается chopping: 60 actual game work-minutes/tree.
Progress принадлежит Tree, сохраняется при schedule/critical/PlayerCommand/impossible
или resident-removal interruption; reservation освобождается. Новая profession
применяется после committed action, progress не сбрасывается. Полностью срубленное
дерево даёт +1 Gathering XP, без skill effects, и normal decision point.

Default data-driven yield — 3 LOG: отдельные GroundResource amount=1 с deterministic
радиальными offsets 0.35 world unit, простой horizontal cylinder View3D. Существующие
GroundResource drops также используют маленький generic 3D view. Lifetime остаётся
4320 игровых минут. LOG и прежний construction WOOD сосуществуют; recipes, FOOD,
Porter container-to-container logistics не изменены. Ground LOG пока не pickup/source
и не placement/nav blocker; строительство поверх loose resources остаётся известным
ограничением до отдельного решения. Depleted data сохраняется в tree registry.

Следующий этап: ground resource pickup/logistics; Sawmill/PLANK позже. Без procedural
forest, regeneration, tools, chopping animation, tree UI или save/load overhaul.
Legacy 2D запускается, но forestry world-work реализован только в main_3d.


## Forestry: Lumberjack Hut и локальный рабочий цикл

Текущая модель заменяет прежний world-work лесоруб без workplace. LUMBERJACK
требует назначенную BUILT Хижину лесоруба через общий PlayerControl/interaction.
BUILDER остаётся world-work. Worker capacity хижины = 1; список работников
вычисляется по ResidentData.work_location_id, без второй mutable копии.

Хижина — обычный BuildingInstance/Definition: footprint 8×6 build cells
(4×3 world units), quarter-turn rotation, 10 WOOD + 180 construction work-minutes,
2 builder slots. Ghost/BuildGrid/NavGrid/access bridge и UNDER_CONSTRUCTION → BUILT
общие. Starter hut не добавлена; игрок строит её. Container принимает только LOG,
локальная capacity 12; рабочая область от logical center имеет radius 15 world units.

На normal daytime WORK decision используется порядок:
1. COLLECT: available reachable loose Ground LOG внутри собственной области;
   reserve конкретный stable GroundResource ID + hut inbound capacity, физический
   pickup одного LOG в inventory, доставка к default hut access, deposit.
2. CHOP: STANDING, unreserved, reachable tree в области, только если полный
   data-driven yield помещается в available free capacity. 60 actual work-minutes
   → 3 отдельных Ground LOG; они не попадают прямо в inventory/container.
3. PLANT: если STANDING + SAPLING count < target 12 и есть valid spot.
4. EXPORT: если локальных задач нет, 1 LOG из собственной hut в ближайший
   reachable BUILT external_import(LOG) container со свободной capacity.

Пример: buffer 10/12 и yield 3, без loose LOG/посадки → EXPORT; после доставки
одного LOG buffer 9/12 → CHOP снова eligible. Нет отдельного urgent export rule.
Перекрывающиеся work areas не владеют деревьями/брёвнами: конкуренцию разрешают
временные Tree/GroundResource reservations.

Посадка: deterministic samples (7 rings × 16 directions), порядок по близости,
проверки bounds/navigation/buildings/runtime blockers/Tree/Sapling/temporary claims.
Minimum center spacing 2 world units. 30 actual work-minutes → individual SAPLING.
Interrupted planting сбрасывает partial progress и claim. SAPLING radius 0.15,
за 4320 game-minutes (3 дня) → обычный STANDING radius 0.35 с тем же ID.
Оба состояния блокируют navigation/placement, не занимают BuildGrid; рост обновляет
blockers без rebake. Terrain/species/tools/seeds/сезоны не добавлены.

Export переиспользует HaulJob + PorterHaulExecutor полностью: atomic out/in,
physical inventory, completion/drop. Только выбор fallback принадлежит лесорубу;
его job имеет work_phase_only и отменяется вне DAY WORK. Обычный Porter видит
container LOG export Hut → Storage через существующий service; Ground LOG он
не подбирает. Warehouse имеет отдельную LOG capacity 20, начальный LOG stock 0;
FOOD/WOOD balance не изменён.

Interrupt before local pickup оставляет drop и освобождает Ground/inbound claims;
after pickup создаёт GroundResource в текущей позиции и освобождает hut inbound.
Chopping сохраняет Tree progress; planting progress не сохраняет. PlayerCommand,
critical needs и конец WORK используют общий interrupt lifecycle. Profession change
не прерывает committed action, но следующие tasks требуют актуальную hut profession.
После каждого completed task — normal decision point, не автоматическая цепочка.

BuildingCard показывает LOG N/12 и assigned worker/Лесоруб. Radius виден кольцом через существующий Navigation debug toggle; target UI не
добавлен. Chopping сохраняет прежний +1 Gathering XP; local pickup/planting не дают
дополнительного XP; export сохраняет shared successful haul +1 Logistics XP.
GroundResource lifetime остаётся 4320 минут. Sawmill/PLANK/WOOD migration отложены.


## Logistics: назначенная база PORTER и внешние flow policies

PORTER использует ResidentData.work_location_id как единственную ссылку на конкретный
BUILT STORAGE workplace. Общий PlayerControl/контекстное employment menu назначает
склад; capacity остаётся прежней (несколько работников). Появление нового склада
не меняет assignment. Без valid built/action-access базы WORK unavailable; её
удаление/недоступность отменяет active haul с обычным reservation/drop cleanup.

Потенциальные пары фильтруются ДО scoring:
- inbound: external export source → собственный Storage;
- outbound: собственный Storage → external import consumer;
- third-party producer → consumer без собственной базы не является Porter candidate;
- Storage → Storage в обе стороны запрещён: balancing/explicit demand отложены.

BuildingDefinition.logistics_flow — небольшой resource → import/export flags словарь.
Необъявленный resource имеет оба flags false. ResourceContainer не изменён: хранение,
allowed types, количества/capacity/reservations и direct/local deposit — его прежняя
ответственность. External policy не запрещает production/local пополнение.

Текущие policies:
- Storage FOOD/WOOD/LOG: external import true, export true;
- Gatherer Hut FOOD: import false, export true;
- Kitchen FOOD: import true, export false;
- Lumberjack Hut LOG: import false, export true;
- unrelated resource flows не объявлены/не разрешены.

LogisticsController предоставляет общий external destination/filter API. Candidate
creation, preflight и atomic post-reservation recheck используют ту же policy.
Lumberjack fallback export также берёт destinations через этот service; Hut A → Hut B
невозможен независимо от свободной capacity. Hut A → Storage разрешён.
Local Ground LOG → own hut остаётся прямым forestry deposit: все три trips работают
при external_import(LOG)=false. Будущая Sawmill сможет объявить import(LOG)=true.

Scoring/urgency/distance/modifiers неизменны. Storage outbound использует destination
import urgency; producer inbound — source export urgency, как прежде. HaulJob хранит
committed workplace ID для валидации назначенной Porter базы; это snapshot действия,
не дополнительное mutable resident assignment. Safe committed delivery после смены
профессии/assignment сохраняется; исчезновение captured base отменяет её. Политики
проверяются без переоценки priority/маршрута. Runtime data policy edits (debug/tests)
требуют существующий service.recalculate() для немедленной active job validation.

Не добавлены balancing, территории, priorities UI, ground pickup Porter, Sawmill/PLANK.
Builder workflow и waiting logic не менялись.
