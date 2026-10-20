# Village Sim — Roadmap

Актуальные цены: см. «2026-10-12 — Актуальные строительные рецепты» в конце документа.
Исторические цены ниже не являются текущим балансом.

## Единственная поддерживаемая игровая сцена (2026-10-14)

VillageSim запускается только через `res://scenes/main_3d.tscn` (F5 / Run Project).
Legacy 2D окончательно выведена из эксплуатации и удалена. Совместимость со старым
HUD и legacy startup больше не являются требованиями. Simulation/Domain остаётся
общей действующей системой; Vector2 в ней обозначает логические координаты мира,
а не поддержку 2D-рендеринга. Независимый ортографический 2.5D-прототип сохранён
как тестовый стенд камеры/навигации; он не является альтернативной игровой сценой.
Исторические записи о старой сцене описывают завершённые этапы и не служат
инструкцией запуска. Каноническая камера перспективная; результаты E6 и P1 сохранены.

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
Standing tree замедляет NavigationGrid через physical bounding rectangle без дополнительного
resident clearance; generic runtime circle сохраняет запрет placement, без Tree
branches в validator. Depletion снимает slow source/placement blocker и убирает view.

Исторический forestry foundation: LUMBERJACK первоначально работал без workplace;
текущая модель с хижиной описана ниже.
На обычном daytime WORK decision eligible STANDING unreserved trees сортируются
по squared XZ distance от logical center собственной hut, затем stable tree ID.
Первое reachable tree выбирается без оценки всех остальных маршрутов. Forestry
resolver делает один region-goal A* к области взаимодействия, вместо 24 perimeter
searches. Runtime executor по-прежнему владеет WORLD position; domain positions
и target используют scale bridge 1:25. См. исправление workday freeze ниже.

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
Оба состояния замедляют navigation и блокируют placement, не занимают BuildGrid; рост обновляет
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


### 2026-10-09 — Builder сохраняет commitment при доставке последних материалов

Исправлена ветка ResidentBuilderController._continue_task: пустой material trip раньше
означал одновременно отсутствие источника и нулевой uncovered deficit, поэтому после
доставки builder завершал task, освобождал slot и выбирал другую стройку. Теперь
существующие site + active_builder_ids сохраняют assignment: если для каждого required
resource delivered + construction_reserved_in >= required, но delivered ещё недостаточно,
уже назначенный builder входит в WAITING_FOR_MATERIALS. Свободный builder по-прежнему
выбирает обычные candidates; формула site score и WORK utility не изменились.

Ожидание происходит у общего DEFAULT ACCESS POINT, при необходимости через GOING_TO_WAIT.
Это interruptible stationary intent с прежним WORK_PRIORITY, не forced action. Общий
continue_intent допускает movement/stationary стадии одного action и сохраняет pending goal.
construction_changed/availability_changed ставят один deferred reconsider текущего task
после завершения синхронной material mutation. Нет minute/frame polling поиска материала.
9 delivered + 1 inbound сохраняет ожидание; последний delivery запускает work на той же
стройке. Потеря inbound возобновляет обычный one-unit fetch, а невозможный uncovered fetch
освобождает task. 8 delivered + 1 inbound при требовании 10 не является полным покрытием.

PlayerCommand, critical needs, completion/cancellation/removal, конец WORK phase в 17:00
освобождают assignment стандартным cleanup; накопленный construction progress сохраняется.
Смена профессии во время ожидания завершает безопасный stationary этап. Рейсы и рабочие
циклы сохраняют прежнюю committed семантику. Логи только переходов wait/resume/lost delivery.

Deadlock audit: реальные inbound reservations принадлежат уже активным builders с их
собственными slots. Ожидающий первый доставивший не отменяет рейс второго; тому не нужен
новый slot для доставки. Два последних рейса физически заканчиваются, затем оба builder
работают на прежней стройке. Capacity остаётся 2; Porter не участвует, отдельного scheduler
и копии reservation/material state нет. Direct reservation APIs по-прежнему требуют от
владельца освобождения reservation при cancellation — новой ownership системы нет.


### 2026-10-09 — первая processing chain: LOG → Sawmill → PLANK

SAWMILL («Лесопилка») — обычный BuildingInstance: 12×8 build cells (6×4 world units),
rotation 90°, construction 15 WOOD / 240 work-minutes / 2 builders. Placement, ghost,
BuildGrid/NavGrid blockers, DEFAULT ACCESS POINT, selection и completion переиспользованы.
BUILT Sawmill имеет 1 workplace для SAWYER («Пильщик»); assignment — прежний
ResidentData.work_location_id и PlayerControl employment API. Стартовая лесопилка не создаётся.

BuildingDefinition.production_recipe — небольшой ProductionRecipe с inputs/outputs и
work_required. Текущий временный recipe: 1 LOG → 1 PLANK за 30 actual work-minutes.
PLANK («Доски») — игровая единица обработанной древесины, не буквальная одна доска.
Отдельные buffers LOG=12 и PLANK=12 используют существующие per-resource capacities.
Gatherer FOOD observer/60-minute professional cycle не переписан и не изменён.
Input-consuming recipes исполняет небольшой ResidentRecipeController в общем runtime:
обычный workplace WORK candidate → reserve input/output → идти к access point → WORKING.
Никакого world-work exception, scheduler или per-frame production availability polling.

Input reserve_out и output reserve_in создаются до цикла: LOG остаётся физически в
контейнере, место под PLANK гарантировано. ResourceContainer.transform_reserved проверяет
и обновляет весь локальный ledger до отправки synchronous resource signals. External import
policy не ограничивает local production deposit. При completion input consumed, output
produced, building.production_progress=0 и owner/reservations очищены; затем normal decision.
Progress принадлежит BuildingInstance, как в Gatherer, и прибавляется по фактическим игровым
минутам у action location. Short interruption сохраняет partial progress; обе reservations
освобождаются и заново claim при resume. При отсутствии LOG/output capacity WORK unavailable.
Relevant container events дают idle worker новый decision point, не прерывая personal action.
PlayerCommand/critical/schedule используют прежний pipeline; после 17:00 production не идёт.

External policies: Sawmill LOG import=true/export=false, PLANK import=false/export=true.
Storage PLANK import=true/export=true, capacity=20; Storage→Storage по-прежнему запрещён.
Lumberjack fallback может экспортировать LOG в Sawmill через общий destination provider;
Hut A→Hut B остаётся запрещён. Porter выполняет Storage→Sawmill LOG и Sawmill→own Storage
PLANK через обычные candidates/reservations/physical execution, без special deliveries.
BuildingCard показывает LOG/PLANK, assigned Sawyer и production work progress.

WOOD остаётся отдельным construction resource; PLANK пока не имеет потребителя кроме
Storage. Заполненные output/storage buffers естественно останавливают recipe. Следующий
крупный этап — migration construction WOOD → PLANK, вне текущего commit. Не добавлены
tools/fuel/sawdust, animations, multiple recipes/workers, recipe selection или новые skills.


Отдельный backlog, НЕ реализован в Sawmill commit:
CLOSED 2026-10-09: construction work accrues every simulation minute; interruptions preserve domain progress.

## 2026-10-09 — Construction economy: PLANK replaces abstract WOOD

Текущее строительство использует физические Доски (PLANK). Старые записи WOOD
ниже/выше относятся к историческим этапам; WOOD удалён из ResourceType, runtime
stock/config и gameplay. Enum содержит FOOD/LOG/PLANK; FOOD сохраняет ID 0.
Сохранений с numeric resource IDs в текущем прототипе нет; save migration не добавлена.

Construction balance задаёт generic requirements dictionary ResourceType → amount,
а не отдельное wood/plank поле. Стоимости: HOME/GATHERER_HUT/LUMBERJACK_HUT —
10 PLANK; STORAGE/FOOD/SAWMILL — 15 PLANK. Work time (180/240), builders=2,
worker capacity и recipe 1 LOG → 1 PLANK / 30 actual work-minutes не изменены.
Позже несколько материалов можно задать тем же словарём без новых requirement fields.

Starter Storage: 35 PLANK = актуальные costs Hut (10) + Sawmill (15) + explicit
bootstrap reserve 10 (одно малое здание). Stock вычисляется из definitions через
balance helper; PLANK per-resource capacity повышена с 20 до 35, чтобы bootstrap
реально помещался. FOOD 10/20, LOG 0/20 и другие стартовые данные не изменены.

Tree → Ground LOG → own Hut → Sawmill → PLANK → Porter own Storage → Builder
→ construction теперь замыкает экономику. Builder остаётся resource-generic:
requirement → source reservation → inventory → delivered construction material.
Существующий source filter допускает любой BUILT container с available material,
не только Storage; новая Storage-only policy не вводилась. Porter ownership не менялся.
Events проверяют наличие resource в требованиях активных строек, без WOOD/PLANK branch.
Полное inbound покрытие сохраняет текущую стройку/slot и event-driven wait. Interrupt
после pickup создаёт GroundResource(PLANK), до pickup освобождает обе reservations.
Cancelled construction сохраняет прежний cleanup; BuildGrid/NavGrid/lifecycle не менялись.

Smooth construction progress backlog закрыт этапом incremental construction (2026-10-09).
Нет новых ресурсов, recipe modifiers, storage balancing или anti-softlock системы.


## 2026-10-09 — Worker self-logistics and shared physical sources

Workers remain ordinary WORK candidates at priority 7000. Sawyer first runs an
available production recipe; otherwise fetches missing input for its OWN Sawmill,
or exports its own output to a BUILT accepting Storage (output-blocked export wins).
Gatherer produces while capacity exists and only self-exports own Hut FOOD when
production is unavailable. There is no mandatory export after every cycle.
Lumberjack retains local COLLECT → CHOP → PLANT → EXPORT order and work radius.
Production can operate without Porter; Porter improves throughput.

ResourceSourceRef contains only CONTAINER + building_id or GROUND + drop_id.
ResourceSources resolves live domain objects, positions, external_export policy,
route availability and native reservations. It contains no candidate priorities,
work assignment or scheduler. Container uses reserve_out/release_out; Ground uses
exclusive claim/release and remains globally claimable. Owner ledgers identify
managed reservations; quantities remain in ResourceContainer/GroundResource.
Destination remains BuildingInstance/ResourceContainer. Builder keeps its existing
construction inbound reservations, slots, event-driven waiting and work cycles.
All external container sourcing, including Builder, requires external_export=true:
Sawmill LOG is protected, Sawmill PLANK is exportable.

Porter-specific own-Storage eligibility and no Storage→Storage remain in its
workflow. Ground candidates deliver only to the assigned Storage, obey projected
capacity/import policy, and receive PORTER_GROUND_CLEANUP_BONUS=200 (roughly 2%
of maximum world urgency), then the existing route penalty. Ground never has
absolute priority; there is no age/despawn urgency. Shared source selection uses
full reachable route and stable IDs, with no absolute Ground/container preference.

Existing HaulJob now carries a stable source reference and workflow validation.
HaulExecutor (renamed from porter_haul_executor) executes movement → pickup → carry
→ delivery and interruption cleanup; no Storage-only eligibility lives there.
Claim reserves source and destination atomically, rechecks synchronous changes,
then creates an assigned committed job. Pickup/delivery revalidate ownership,
lifecycle and resource policy. Ground despawn before pickup cancels/releases inbound;
after pickup inventory is authoritative and the job no longer depends on that drop.
Before pickup interrupts release reservations; after pickup cargo drops at actual
resident position. Self-logistics stops/cleans up at end of WORK; no forced night haul.
New Sawyer/Gatherer self-hauls grant no additional skill XP; existing Porter and
Lumberjack export XP behavior is preserved. Event-driven resource/claim/capacity
signals wake idle workers through normal decisions; no polling or second logistics
engine was introduced. Builder and Lumberjack keep existing task execution while
sharing source resolve/selection/reservation adapters.

Deferred: age urgency, roads, carts, stacks, storage
balancing, new resources/buildings, and profession/workplace infrastructure refactor.


## 2026-10-09 — Incremental construction work (completed)

Construction contribution is applied on GameClock minute_changed, by actual elapsed
working game minutes, directly to BuildingInstance.construction_progress. Builder's
work_minutes is transient cycle timing only, never buffered uncredited building work.
At the valid access point with materials complete, WORKING action and owned slot,
one working minute contributes one work-minute. Existing Builder has no construction
skill/trait speed multiplier; no new modifier or balance change was introduced.
FPS and wall-frame count do not affect contribution; pause produces no time ticks.
The final interval ending at 17:00 is credited, then schedule cleanup stops work.

Interruption/cancellation keeps already applied progress; cleanup never credits
unobserved future time or re-applies work. Resume starts a new cycle from domain
progress. Multiple Builders add independently; elapsed timestamp advances before
synchronous callbacks, and contribution clamps to cycle remainder and building
remaining work. Completion immediately calls the existing complete_construction()
path and releases assignments/slots, with the existing building activation signals.
If final work was applied before a synchronous interrupt, completion wins; an
interrupt before a work tick contributes no additional work.

The 60-minute cycle remains the XP/decision boundary. Only a full cycle awards
+1 CONSTRUCTION XP; a building completed mid-cycle grants no partial/bonus XP.
Social WORK remains triggered once at work-cycle start, never per progress tick.
BuildingCard already subscribes to construction_changed and updates incrementally;
no frame polling or new UI. PLANK delivery/reservations, waiting, source selection,
logistics and production are unchanged. Smooth construction progress backlog CLOSED.
Current resolution is integer simulation minutes, not sub-minute/frame animation.


## 2026-10-09 — Weighted traversal and soft tree zones (completed)

Canonical NavigationGrid now supports generic source-owned speed modifiers and
travel-time A*. Trees/saplings are walkable at speed .20, retaining independent
placement blocking. Buildings remain hard obstacles with resident clearance.
Cost-aware smoothing and cell-boundary time integration share the same multipliers.
The two-tree Hut/Sawmill corridor stays reachable; faster detours remain preferred.
Future speedups use normalized admissible weights. Roads, terrain heights/slopes,
crowd avoidance and separate trunk obstacles remain deferred. See DECISIONS.


## 2026-10-09 — Dirt roads v1 (implemented)

Optional free instant world road cells (.5 units), player 1-unit paint/erase brush,
MultiMesh visuals and generic weighted traversal at speed1.25. Buildings delete
road under physical footprint; cancellation never restores it. Trees prevent paint.
Existing Navigation toggle controls routes + cached aligned grid. No world save/load
was introduced; future traffic may use the same road model API. Automatic roads,
maintenance, terrain and connectivity requirements deferred. See DECISIONS.


## 2026-10-10 — Town Center v1
Canonical new games start with one ordinary BUILT TOWN_CENTER (id town_center),
four unchanged residents and the existing forest. The four starter HOME buildings,
warehouse, Kitchen and Gatherer Hut are replaced. Legacy 2D keeps its historical
reference setup; explicit legacy-starter integration fixtures preserve those scenarios.
Town Center uses the shared BuildingInstance, 16x12 build-cell footprint (8x6 world
units), BuildGrid/NavigationGrid, selection/card and deterministic default access point.
It is not in the construction catalog, has no player placement recipe and cannot be
cancelled as a BUILT building; no demolition system was added.

Starting resources: 60 PLANK, 20 FOOD, 0 LOG; capacity 100 for each. Definition.is_storage
is the small shared storage capability used by Porter eligibility and storage destination
queries. Storage and Town Center have it; import/export remain explicit per resource.
Porter can work from Town Center. Production-first self-logistics priorities are unchanged.
The first runtime Gatherer Hut/Kitchen activates existing production/needs and HUD wiring.

Definition.fallback_housing_capacity supplies ten transient committed trip/sleep claims.
ResidentData.home_location_id remains optional permanent HOME ownership only. A valid
normal HOME wins; otherwise deterministic available fallback housing is claimed on sleep
action activation, then outdoor sleep when full/unavailable. Fallback sleep quality is 1.0;
critical on-the-spot sleep remains outdoor quality. Wake, interruption, forced commands,
critical needs and runtime removal release claims; invalidated targets are safely retried
through the existing schedule path. No beds, rooms, rent or persistent occupant list.

Town Center BuildingCard exposes "Управление поселением": the sole "Жители" panel
lists current PlayerControl residents, refreshes on residents_changed and selects through
existing ResidentSelection/ResidentCard. New resident lifecycle callers must register /
unregister with PlayerControl and create/remove their runtime as usual. No migration,
economy, politics or placeholder tabs. Entrance/interior points, relocation/demolition,
final visuals and save/load remain later work; default access point is still a bridge.


## 2026-10-10 — Entrances and physical building slots v1
Canonical main_3d now uses WORLD → one authored exterior entrance → acquire on
arrival → instant interior transition → action → release/exit at the same entrance.
Layouts in scenes/building_layouts are editable Godot Marker3D scenes, rotated by
normal transform hierarchy. Slot types: WORKER, COURIER, VISITOR, SLEEP; exterior
CONSTRUCTION places are available only while UNDER_CONSTRUCTION. Gameplay domain
capacities and assignments remain authoritative; marker counts are validated.
Gatherer Hut now explicitly has worker_capacity=4 (approved prototype capacity);
Kitchen has four Visitor places, HOME four Sleep places, Town Center ten fallback
Sleep places, and every current resource building one Courier place.

There are no advance interior reservations or queues. WORKER/COURIER wait at the
entrance and retry on slot-release events; committed resource reservations survive.
A full VISITOR arrival cancels the attempt and returns to normal decisions. Full HOME
Sleep uses fallback housing; full Town Center uses outdoor sleep without changing
home_location_id. Town Center transient claims now start at actual sleep arrival,
not trip activation; this supersedes the earlier trip-claim description. Forced
interruption and completion release occupancy. ResidentExecutor3D owns physical
position; controllers request building ID + purpose, never set interior coordinates.

Builders use nearest free valid exterior Construction places, retaining existing
max_builders/active_builder ownership, incremental progress, waiting, XP and social
cycle semantics. Ground pickup, trees, planting, world MOVE_TO and outdoor social
behavior are unchanged. Occupied interiors make the whole primitive building
translucent; colored cubes and entrance platforms are temporary visuals.

Placement protects footprint↔entrance and entrance↔entrance for BUILT and
UNDER_CONSTRUCTION. Trees/runtime blockers also reject entrance overlap. Roads may
cross entrances and are preserved there; only actual footprint road cells are removed.
No global entrance connectivity validation is performed. Interior navigation,
multiple entrances, rooms, furniture, queues and final art remain deferred.
Derived DEFAULT ACCESS POINT remains only in explicit historical 3D reference
fixtures; legacy 2D keeps its old presentation. Canonical building actions execute
at occupied authored places rather than the old derived access point.


### 2026-10-10 — External courier handling foundation complete
COURIER is exterior and physically reached; building and Ground loading/unloading
take 10 + 10 game minutes. Builder UC deliveries use COURIER separately from
CONSTRUCTION. Committed deliveries finish across WORK boundaries with existing
forced interruption cleanup. Shared deadline helper, no new logistics engine.
Crowd avoidance, queue visuals, indoor movement and cargo animations remain deferred.


## 2026-10-11 — Forestry workday freeze fix
Implemented hut-centered deterministic first-reachable tree choice, one region-goal
A* per checked tree and one-use CHOP availability reuse. No global navigation/cache
migration. Four-resident 06:59→07:00 benchmark: 1/8/15 eligible trees now need one
forestry region query + three ordinary wander queries; phase medians 16.23/20.45/
23.62 ms versus 64.50/784.21/1505.45 ms. Unreachable trees still require additional
queries; no reachability rules weakened. See DECISIONS for API/discretization limits.


### 2026-10-11 — Residual navigation A* optimization
Completed local region-search heap/data optimization and shared live dense grid
data; existing native point backend, smoothing and gameplay rules retained.
Two-lumberjack x20/no-road long-route phase median 299.25 -> 59.10 ms; minute
decision 282.95 -> 61.69 ms in repeated paired runs. This is substantial progress,
not a claim that all freezes are solved: the desired <50 ms target is not reached,
and unreachable/broad searches remain synchronous. Do not solve this by slowing
game time or changing profession rules. Further scheduling/backend changes need
separate agreement; none are introduced here.


## 2026-10-11 — Independent work areas / free forestry

LUMBERJACK may hold its profession without a built hut. With no valid workplace
or independent area, WORK is unavailable. Existing convenience assignment to an
available hut remains; players can explicitly replace it with a FREE area. Other
professions retain their existing workplace requirements.

WorkArea is world-owned domain geometry: stable ID, simulation-space center/radius,
revision and contains(). Player-created circles have fixed radius 15 world units
(375 simulation units through the 1:25 bridge). The property-based geometry can
evolve later; no size/shape editor exists now. Shared areas contain no worker or
resource ownership lists: ResidentData.work_area_id is the assignment reference.
work_location_id and work_area_id are mutually exclusive, changed atomically by
PlayerControl after validation. Failed reassignment preserves the previous choice.

BUILDING keeps COLLECT -> CHOP -> PLANT -> EXPORT, buffer capacity, reservations,
physical courier slots and handling. FREE only selects/claims/approaches/chops a
tree and creates the existing GroundResource LOG; no collection, transport, export,
planting or extraction speed penalty. XP, needs priorities and schedule unchanged.
Both modes share execution, partial tree progress, completion and cleanup.

A transient context is resolved at selection and captured for committed execution.
Editing/removing an area or changing assignment affects future work, not an already
claimed chop or delivery. Explicit/critical/movement interruptions still release
claims; partial tree work remains, cargo cleanup follows existing rules. A missing
hut never implicitly turns into FREE. Availability reuses one revalidated CHOP
candidate; context identity/revision invalidate it even within one frame. Region
A* and first-reachable ordering remain, without new navigation backend/scheduler.

ResidentCard shows building/area/unassigned and offers creating an area or choosing
an existing area ID. Creation: choose ResidentCard action, click ground to freeze
circle preview, confirm button/Enter; RMB/Esc cancels. It excludes road/build tools
and resident commands while allowing camera pan/zoom. Clear assignment is management,
not cancellation of the current action. Area geometry edits/removal are domain API
only; no full area editor, names, save/load, STONE/miner or resource stacks added.
Ground lifetime and Porter/Builder source rules remain unchanged.


## 2026-10-11 — Shared NavigationConnectivity precheck

NavigationGrid owns a derived packed component-label index over its effective solids.
Cardinal flood-fill is equivalent to current diagonal connectivity because diagonals
require both adjacent cells walkable. Directed/height transitions must revisit this
assumption. Component IDs are meaningful only within their topology generation.

The existing navigation revision/changed signal retains all cost/solid edits. Separate
topology_generation advances once per completed blocker edit only when final effective
solid bits differ; overlapping owners and identical replacement do not invalidate it.
Costs, roads and soft tree/sapling traversal modifiers do not rebuild connectivity.
Initial main_3d registration prepares once; later queries rebuild lazily after topology
changes, coalescing edits with no intervening query. Direct grid callers also ensure.

find_path_to_radius retains input/start checks and the continuous already-in-annulus
fast path. It then checks exact walkable cell-center annulus goals against the start
component, never just the object center. Disconnected rings return unavailable without
region A*. Reachable rings use the unchanged weighted region A*, endpoint and smoothing.
Native point navigation, forestry ordering/claims, FREE/BUILDING policies and gameplay
balance are unchanged. This index is shared by all future region-navigation clients.

This removes repeated broad negative searches, not all synchronous navigation peaks.
A topology rebuild and distant positive paths still cost time; resumable pathfinding is
a possible separate future stage. No asynchronous scheduler or per-tree negative cache.


## 2026-10-11 — Finite rocks and FREE mining (current policy)

STONE is appended after FOOD/LOG/PLANK. Storage and starter Town Center accept and
export it, capacity 100, initial stock zero. Existing building recipes are unchanged.
MINER (Камнедобытчик) may be assigned without a building, but requires an existing
shared WorkArea to receive ordinary WORK. The existing area creation/reuse/clear UI
serves MINER too; player circles remain radius 15 world units (375 simulation units).

RockData owns finite stock (10), 60-minute cycle work, partial progress and exclusive
claim. Each completion produces one uniquely numbered receipt, resets partial work,
decrements stock and releases the claim. The world publishes exactly one Ground STONE
per receipt at the walkable worker position. Last depletion removes view/physics/hard
blocker; earlier cycles do not edit topology. Ground survives its source and keeps
existing expiration/Porter/Builder rules. One completed cycle grants 1 GATHERING XP.

FREE mining selects first reachable rock ordered by area-center distance and stable ID,
uses one annulus query per tested candidate, and reuses availability once after identity/
revision validation. Tree and rock approach geometry share a small helper; no scheduler
or extraction hierarchy. Active claims capture source/target and survive area edits or
removal; forced interrupts release claims while retaining elapsed partial work. No
COLLECT/EXPORT/hauling, buffer, capacity gate, speed bonus or Quarry is implemented.

Quarry remains future work: check room for 1 STONE before MINE, without reserving future
output. Yield stays Ground, action ends into normal AI; COLLECT precedes another MINE,
EXPORT may free room, and personal delivery is not guaranteed.


## 2026-10-11 — Interior COURIER portal lifecycle (supersedes exterior courier policy)

All seven authored layouts (kitchen, warehouse, gatherer_hut, home, lumberjack_hut,
sawmill, town_center) now place COURIER inside. For BUILT buildings, resource route
positions resolve to the walkable entrance, never the interior marker. The existing
ResidentExecutor3D portal lifecycle acquires a free slot on arrival, waits through
slot-release events if occupied, performs 10+10-minute handling inside, releases and
exits through the same portal before the next path starts. COURIER counts as interior
occupancy/transparency. Claims, inbound/outbound, policies and inventory are unchanged.

UNDER_CONSTRUCTION does not admit interior COURIER. Builder material delivery resolves
to its existing exterior CONSTRUCTION slots with active-builder ownership; unloading
does not accrue construction work. Existing progress/material lifecycle remains.

Cancelled cargo from an interior is dropped at the walkable entrance, including
resource/lifecycle invalidation before the executor receives intent cancellation.
No new queue, reservation framework, transport engine or HaulExecutor rewrite.
Legacy 2D/reference location behavior remains separate and unchanged.


## 2026-10-11 — Generic internal delivery and worker export
EXTERNAL keeps explicit external import policy. INTERNAL uses the same HaulJob,
HaulExecutor, ResourceSources and inbound ledger, with job-bound captured workplace
admission held by LogisticsController. Claim checks current assigned worker against
definition.worker_profession and explicit internal resource policy; execution checks
captured building identity/lifecycle/policy, not a later assignment. An internal flag
alone grants no right. Reassignment allows an existing delivery to finish, never a new
claim to the old workplace. Generic worker export requires own authorized workplace,
external export policy and a reachable allowed destination with external import/room.
Existing forestry LOG exports to Sawmill remain valid; Miner selects Storage/Town Center.
Profession priorities remain controller-owned. No second transport engine or ledger.


## 2026-10-11 — Quarry and BUILDING mining
Quarry is a normal constructible BuildingInstance: 10 LOG + 5 STONE, 180 work
minutes, two Builders, 12x8 build cells (6x4 world), one MINER, radius 15 world,
buffer 12 STONE. Authored layout has one interior WORKER, one interior COURIER,
one entrance and two exterior CONSTRUCTION places. No automatic production.
FREE mining is unchanged. BUILDING resolves current Quarry area and chooses
COLLECT -> MINE -> EXPORT through normal WORK decisions. COLLECT filters Ground
STONE/unclaimed/in-area before navigation and uses generic INTERNAL HaulExecutor.
MINE requires room for one STONE but never reserves future inbound: yield remains
public Ground and ends into normal AI. Later pickup is not guaranteed. Full buffer
suppresses new mining; EXPORT can free room to resume. Miner selects Storage/Town
Center; external import to Quarry stays forbidden. Current assignments drive new
claims, captured actions finish without redirecting cargo. Lost Quarry never implies
FREE. Skill, schedule, existing recipes and starter stocks remain unchanged.

Quarry COLLECT ranks cheap eligible Ground sources before routes and stops at the
first reachable source, preserving Euclidean route-distance + stable-ID ordering.
ResourceSources availability revision invalidates one-use mining selection on same-
frame Ground claim/release/add/remove; buffer room is also revalidated. Resource route
checks now reuse NavigationConnectivity point precheck before unchanged positive A*.
This closes measured negative Ground-route spikes without a backend/scheduler change.
Forestry COLLECT remains its existing specialized committed lifecycle; its EXPORT
compatibility wrapper delegates generic export and preserves prior Logistics XP.
Migrating COLLECT requires a separate lifecycle-focused task, not a copied miner policy.


## 2026-10-12 — Forestry COLLECT uses shared INTERNAL HaulExecutor
BUILDING forestry keeps COLLECT -> CHOP -> PLANT -> EXPORT and the unchanged 12 LOG
buffer. COLLECT now uses ResourceSources.find_ground_in_area with the same combined
Euclidean route-distance/stable-ID ranking, early Ground/LOG/area/claim filtering and
first-reachable selection. One-use availability covers COLLECT and CHOP, invalidated
by assignment/area revision, navigation, source availability and buffer room changes.

LumberjackController only owns task policy and CHOP/PLANT execution. COLLECT creates
LogisticsController.claim_internal; HaulJob/HaulExecutor own Ground claim, inbound,
10+10-minute handling, cargo, interior COURIER/portal, completion and cleanup. No
profession-specific pickup/CARRYING/handling/inbound/cargo-cleanup branch remains.
Captured workplace permits committed delivery after reassignment or17:00; no new
claim outside daytime or to an old workplace. Hut external LOG import stays closed.
COLLECT awards no XP; existing generic EXPORT wrapper retains its previous XP and
allowed destinations including Sawmill. FREE forestry/extraction/planting unchanged.

HaulJob.execution_priority separates committed movement from candidate score; forestry
COLLECT preserves WORK_PRIORITY=7000, other hauls keep their previous default8000.
HaulExecutor now cancels on intent replacement on either leg (including carrying),
closing an existing destination-leg orphan-job gap. Completion already committed wins
reentrant exit/deposit callbacks; earlier interruptions retain/drop only real cargo.
Quarry/Miner use the same unchanged INTERNAL admission; no new ledger or scheduler.


## 2026-10-12 — Porter exact lazy selection
Porter ranks transient cheaply eligible deliveries by unchanged geometric score DESC,
then exact-equality lexical stable_key ASC. Both complete route predicates are checked
in that order until the first feasible delivery; no candidate-count cutoff or resource
cache is added. On a stable valid world this is the exhaustive feasible-pool winner.
Availability is read-only; claim rebuilds current scores and keeps existing transactional
reservation/revalidation/owned rollback. Failed claims retain attempted keys and finite
retries bounded by the initial cheap pool (previously the initial feasible pool); no
unreachable candidate is claimed. Full feasible collect_candidates stays diagnostic.
DEBUG normal selection reports the chosen feasible candidate rather than constructing
all routes for logging. Generic HaulExecutor, resource policies and balance are unchanged.


## 2026-10-12 — Development Debug Panel (F10)
Canonical main_3d has a development-only panel guarded by OS.is_debug_build(). F10
opens/closes it. Select Residents (1–50, existing professions), Ground resources
(1–100 individual FOOD/LOG/PLANK/STONE), or an authored buildable building, then
Create and LMB on ground. Esc/RMB cancels; successful spawn ends placement. A yellow
cursor marker indicates the prospective point. UI clicks do not issue world commands;
road/build/work-area and debug placement modes exclude each other. Paused placement
is supported. Existing resident/building cards remain the normal inspection UI.

DebugSpawnService validates requests and delegates shared resident runtime registration,
GroundResources.create_drop and _show_building/_activate_completed_building. Residents
use normal AI/needs/social/logistics/natural controllers and PlayerControl assignment
rules; unavailable workplace leaves the chosen profession unassigned and is reported.
No work area is created automatically. Buildings start BUILT without filling construction
ledgers/material cost, but retain normal layouts/entrances/slots/containers and validated
BuildGrid/NavigationGrid/physical occupancy. Ordinary construction is unchanged.
No alternative data/runtime/ledger/navigation/clock exists. Batch points use bounded
local square rings; partially blocked batches report the actual created count. No path
search or nav rebuild per Ground unit. Trees/rocks are not added to this panel version.

Time tab uses existing pause/speeds and new small GameTime developer entry points
debug_set_time_of_day/debug_next_day through the existing minute-advance pipeline. Set HH:MM advances only
forward to its next occurrence (same time is a no-op); Next Day advances to next 00:00.
Every minute/phase event is retained, so deadlines never rewind. These synchronous
debug jumps may take time with many residents; they do not simulate physical walking
between frames. Use x1–x20 for physical work/transport tests. Release builds expose
neither the panel nor debug-spawn/time commands. No mass deletion or state saving.

## 2026-10-12 — Logistics lookup optimization: Ground
Implemented owner-managed GroundResource ID references, replacing repeated linear
resolve scans while preserving ordered candidate enumeration and resource lifecycle.
This does not make the entire Porter candidate search O(1). Marker reference reuse is
the next separate optimization; COURIER broadcasts and cancellation recursion remain
outside this step. No resource stacks, balance changes or new scheduler.

## 2026-10-12 — Logistics lookup optimization: building markers
Completed per-view marker reference reuse for runtime action/slot resolution, replacing
repeated authored-layout DFS. Ground ID lookup and marker references remain separate
owner-managed read indexes; live resource/marker state is authoritative. Normal Porter
ranking, haul handling, navigation and schedules are unchanged. COURIER broadcast/dedup,
deep cancellation callbacks and further candidate allocation costs remain separate work.

## 2026-10-12 — Reduce repeated Porter work selection
Completed: availability uses a short-circuit existence scan with shared cheap eligibility
and exact scoring, avoiding full-pool allocation/sorting before the fresh ranked claim.
Exhaustive winner equivalence and normal main_3d decision/pickup/delivery are tested.
No scheduler, cross-decision cache, resource balance or transport policy changes.
Separate next steps: investigate recursive recalculate cancellation, then consider AI
decision distribution across rendered frames and repeat scaling stress tests. Existing
COURIER broadcasts and per-claim active-job validations have not been optimized here.

## 2026-10-12 — Logistics recalculate reentrancy
Completed: repeated requests are drained in synchronous pending passes, eliminating
recursive full validation scans during mass cancellation. Approved callback ordering,
claim rollback, no-change notification feedback, new/removed executors and real
occupied/waiting COURIER cleanup have targeted coverage. No resource or haul-rule changes.
Remaining separate work: AI decision distribution across real frames, COURIER broadcast
amplification and further stress/scaling assessment. No AI time slicing is implemented.

## 2026-10-12 — Ordinary AI dispatcher: initial Porter integration
Completed: shared real-frame FIFO/dedup dispatcher, current-state revalidation, pause,
command/critical bypass and ordinary daytime Porter wiring before expensive availability.
Production default is one request/frame. Real Main3D tests cover mass WORK, exact fresh
claims, notifications, schedule/assignment changes, stale runtime, physical delivery and
synchronous safety cleanup. Benchmarks compare complete waves and limits 1/2/3, separately
for headless and rendered runs; lower WORK boundary alone is not treated as total speedup.

Other professions are not connected yet. Future integrations need their own contract
and urgency audit. Residual single-decision cost, active-haul validation, COURIER broadcast
amplification and synchronous developer time jumps remain separate investigations.
No navigation, resource, handling, priority or production balance changes in this stage.

## 2026-10-12 — Navigation smoothing cost
Completed: exact collinear compaction, bounded four-waypoint greedy shortening with64
optional checks, unchanged LOS/terrain-cost rules and full safe raw-tail fallback.
Targeted independent geometry checks cover obstacles, clearance, diagonal corners,
rotation, long budget-exhausting routes, exact targets and movement replanning. Current
movement does not smooth again while following an unchanged path. Long-route and real
30Porter/200LOG x1/x20 comparisons are recorded outside the repository.

Smoother routes are intentionally not guaranteed. Further work must separate raw A*,
smoothing, movement and process/logistics/HUD costs; time slicing of path requests,
global path caching and changes to terrain/clearance require separate decisions. The
user's precise 942ms frame is not assumed reproduced by a different stress layout.

## 2026-10-12 — Актуальные строительные рецепты

Текущий источник цен — `BuildingDefinition.CONSTRUCTION_BALANCE`. Эта политика
заменяет исторические рецепты PLANK-only от 2026-10-09 и Quarry 10 LOG + 5 STONE.

| Тип | LOG | STONE | PLANK |
|---|---:|---:|---:|
| Хижина лесоруба (`lumberjack_hut`) | 10 | 0 | 0 |
| Каменоломня (`quarry`) | 8 | 4 | 0 |
| Хижина собирателя (`gatherer_hut`) | 6 | 0 | 0 |
| Дом (`home`) | 8 | 2 | 0 |
| Лесопилка (`sawmill`) | 6 | 6 | 0 |
| Склад (`warehouse`) | 2 | 4 | 6 |
| Общая кухня (`kitchen`) | 6 | 0 | 0 |

Нулевые потребности отсутствуют в словаре и интерфейсе. Town Center, рабочее время
180/240 минут, лимиты Builders/работников, производство, policies и стартовые
ресурсы не изменены. Меню показывает цену в tooltip из той же definition;
BuildingCard показывает фактически доставленные материалы и текущий progress.

Builder использует все ресурсы рецепта через существующие Ground/container sources,
резервирует по одной единице и доставляет на CONSTRUCTION access point. Материалы
принадлежат строительному ledger `BuildingInstance`, без дополнительного контейнера.
Porter по прежним правилам не доставляет в UNDER_CONSTRUCTION; LogisticsController
обслуживает готовые источники/назначения и не получает новую construction-demand
модель. Это ограничение сохранено, а не обойдено новым типом job.

Лесопилка строится без досок из добытых FREE лесорубом/каменодобытчиком LOG/STONE.
Затем Sawyer производит 1 LOG -> 1 PLANK за прежние 30 минут, Porter может отвезти
доски в Town Center, Builder расходует шесть произведённых досок на Storage.
Интеграционная проверка использует реальный canonical world, естественные starter
деревья/камни, физические пути/handling и контролируемые WORK windows; без DebugSpawn
или добавления ресурсов. Это не длительный автономный playtest потребностей/ночей.
Канонический Town Center сохраняет 60 PLANK/20 FOOD/0 LOG/0 STONE. Legacy 2D сохраняет
35 PLANK/10 FOOD; его исторический запас теперь явно фиксирован, а не вычисляется
из изменившихся цен. Физическая добыча/логистика и cycle-based semantics не изменены.


## 2026-10-13 — Личное питание из доступных источников FOOD

Актуальная политика заменяет прежнее ограничение личного питания кухней:
Kitchen → другие совместимые BUILT-здания → Ground FOOD. Категория важнее
расстояния. В зданиях сохраняется первый достижимый кандидат в порядке registry;
Ground кандидаты упорядочены по расстоянию от жителя и стабильному ID, маршруты
проверяются последовательно до первого доступного источника.

ResidentNeedsController использует существующий ResourceSourceRef и один EAT
lifecycle. Container резервирует ровно одну FOOD через reserve_out/take_reserved;
Ground использует существующий exclusive claim с владельцем meal:<resident_id>
и pickup одной единицы. Количество, ресурс, позиция и ownership остаются в исходных
ResourceContainer/GroundResource. Личное питание не является внешним экспортом:
external_export продолжает ограничивать перевозки, но не потребление жителем.
Чужая reservation/claim не отбирается, включая critical hunger.

Источник проверяется на существование, BUILT lifecycle, FOOD policy/capacity,
свободное количество, допустимый вход и достижимость. UNDER_CONSTRUCTION исключён.
Kitchen сохраняет VISITOR; другие здания используют существующий COURIER с его
обычным ожиданием. Новое автономное питание не выбирает заведомо полный VISITOR
pool; уже committed совместимый EAT сохраняет прежние critical merge semantics.
Ground требует физического подхода без HaulJob, профессии Porter и инвентаря.

FOOD списывается только после настоящего прибытия/входа, при начале еды. Прежние
30 игровых минут и восстановление голода по NeedDynamics сохранены. Отмена до
прибытия освобождает собственный резерв; после начала еда уже оплачена. Исчезновение
источника до прибытия приводит к cleanup и обычной новой decision point; оплаченный
Ground meal продолжает работать после удаления съеденного объекта. Проверка после
reserve учитывает синхронные callbacks удаления источника.

Транзиентный локальный cache выбора учитывает source/navigation revision,
позицию и доступность слотов; отрицательный результат не запускает новый поиск
каждую минуту при неизменном пустом мире. Производные notification totals не
резервируют и не расходуют FOOD. Ground total обновляется по coalesced source event,
а container notifications не сканируют Ground повторно. Critical hunger остаётся
синхронным, обычный Porter AI Dispatcher и его лимиты не изменены.

Ограничения: личная еда в другом здании занимает существующий COURIER на время
приёма пищи; массовый голод может создавать длинную очередь, без нового capacity
или wakeup policy. Ground не получает выдуманную building MEAL location для social
events; существующие building MEAL triggers и social формулы не изменены. Стопки,
новая логистика Porter и мгновенная удалённая выдача FOOD не реализованы.


## 2026-10-13 — Наружное питание после получения FOOD

Актуальная процедура заменяет прежнее удержание COURIER на всё время еды.
Приоритет поиска Kitchen → Other BUILT → Ground и выбор внутри tier сохранены.
Kitchen: одна FOOD после VISITOR arrival, 30 game minutes по -2 hunger/min,
прежние внутренние MEAL events и выход. Other: одна FOOD после входа в COURIER,
затем штатный portal exit, освобождение COURIER и только после этого наружное
EAT 10 game minutes по -6/min. Ground: pickup одной FOOD и наружное EAT 10мин.
Оба режима дают 60 hunger points с прежним clamp и fixed-point rounding.

Согласовано сохранение мгновенного портала ResidentExecutor3D, без walking path
через заблокированный интерьер. Action-owned exit bridge проверяет завершённый
выход, отсутствие marker/waiting и walkable внешнюю позицию. Общий portal и
BuildingUse3D acquire/release/fairness не изменены. Следующий посетитель может
войти во время наружного EAT; стоящий житель не занимает interior slot/nav cells.

Transient paid guard отделяет полученную FOOD от запущенного meal timer и
защищает pickup/exit callbacks и critical merge. До pickup cancel освобождает
резерв; после pickup FOOD не возвращается, interruption сохраняет только уже
полученный benefit. Личного inventory, переносимой порции или dropped meal нет.
NeedDynamics сохраняет hunger growth/clamp/fractions и получает rate текущего
EAT через provider; вне активного оплаченного EAT новый rate не применяется.
Outside не публикует искусственный indoor MEAL context. Source ownership,
производство, recipes, Porter/HaulJob/dispatcher/navigation/schedule unchanged.


## 2026-10-13 — Закреплённые Porter: отдельная вместимость и собственные endpoints

Первая функциональная часть завершена. ResidentData.profession/work_location_id/
work_area_id остаются единственным источником назначения. BuildingDefinition имеет
отдельную porter_capacity: Town Center/Storage = 2; Lumberjack Hut, Quarry,
Gatherer Hut, Sawmill, Kitchen = 1; Home = 0 (запрет назначения). Производственная
worker_capacity и физические WORKER/COURIER slots не изменены. Staffing вычисляется
по зарегистрированным жителям; active HaulJob не занимает дополнительное кадровое место.

PlayerControl.assign_workplace принимает необязательную явную profession. Старые
двухаргументные вызовы сохраняют основную роль здания: производственная профессия
в Hut/Quarry/Sawmill, Porter в Storage/Town Center. Новый явный PORTER допустим у всех
семи поддерживаемых BUILT types. Capacity проверяется до замены старого назначения.
assign_profession=true означает принятую профессию; Porter может остаться без места,
что видно в ResidentCard/DebugSpawn. Такие residents не получают новых перевозок.
При admission/setup исторический overflow исправляется по stable resident ID:
первые K сохраняют место, остальные остаются PORTER без workplace. Обычная попытка
занять заполненное место отвергается и никого не вытесняет. Normalization публикует
assignment events после исправления всей группы; production assignments не меняются.

Новые Porter jobs требуют own source или own destination; Ground имеет только own
совместимый destination, без выдуманного building owner. External policies, запрет
Storage balancing, protected Sawmill LOG, Builder hauling и production INTERNAL/self-
supply сохранены. Porter scan перечисляет только пары собственного здания в прежнем
source/destination/resource порядке. Exact score, stable key, existence probe, fresh
claim, lazy feasibility и frame budget ordinary AI остаются прежними.

Claim захватывает resident/base identity, assignment revision (включая A -> B -> A),
capacity и endpoints до callbacks. Изменение контекста до commit вызывает owned
rollback. HaulJob.workplace_location_id устанавливается до публикации. Переназначение,
смена профессии или увольнение после commit не перенаправляют безопасный старый рейс;
следующий decision использует новое назначение. Resource/lifecycle invalidation по-
прежнему отменяет unsafe job синхронно. Короткая локальная ссылка на исходный container
позволяет очистить собственный reserve_out даже при удалении source внутри callback;
это не новая копия resource state и не долгоживущий resource registry.

Существующая регистрация/удаление очищает workplace metadata и pending AI requests.
Resident unregister использует прежний executor.cancel/unbind и сохраняет реальный
cargo на Ground; полноценный despawn/demolition UI не добавлен. Pending dispatcher
context учитывает assignment revision; команды и critical needs остаются синхронными.

Минимальный UI: раздельные interaction actions production/Porter, причины отказа,
статус unassigned и отдельные counts в BuildingCard. Полный staffing panel, выбор
конкретного workplace в F10 и окончательный большой распределённый playtest отложены.
DebugSpawn пользуется штатной capacity и сообщает unassigned count без bypass.

## 2026-10-14 — E6 Integration QA после перспективной камеры

Фаза A: `25fd81d40e33e0ddf4a6333ce3e4fb68244cfa2a`. Функциональная E6-проверка
использует текущий UI Polish, а не старую геометрию checkpoints. Новый
test_ui_integration проходит полный цикл Sawmill: catalogue/rotation/site,
реальная доставка LOG/STONE Builder, completion, GUI назначения Sawyer/Porter,
физический Ground→buffer haul, clock-driven LOG→PLANK, housing и 100 циклов
cards/windows на каждом целевом разрешении. Дополнительные suites сохраняют
capacity refusal, stale identity, committed hauling, EAT/social/diary и legacy.

Autonomous rendered прогоны 4/30/100 жителей: по 225 секунд, более трёх игровых
дней каждый, 13 смен фаз; AI/движение/needs/dispatcher не отключались. Проверены
повторные 06:59/07:00. Очереди и committed jobs ограничены населением, резервов
с отрицательным количеством или сверх stock не найдено. Активные owned резервы
в конце рабочих рейсов не объявляются утечками и не обнуляются ради теста.

Performance fixture исправлен: DebugSpawn принимает максимум 50 за команду;
для настоящих 100 жителей используются batches с assertion реальной численности.
Это исправление тестового окружения, не правил spawn или gameplay. UI-only
30/100, x1/x20, open/closed: нет роста nodes/TreeItems, hidden roster не poll-ится.

Функциональная регрессия и rendered геометрия подтверждены; нагрузочная приёмка
имеет замечание: 100 жителей x20 дают p99 около 71 ms и первый пик около 411 ms.
Сопоставимый 20-second orthographic контроль также имеет пик около 418 ms
(perspective около 425 ms), поэтому новое ухудшение от камеры не подтверждено.
Это не обещание стабильного FPS и не заявление «фризов нет». Лимит массовой
симуляции и стоимость стартового world setup требуют отдельного решения,
если такой масштаб необходим. Полностью успешная приёмка производительности
100 жителей не заявлена; AI/nav/logistics для неё не менялись.

Все логи, численные результаты, диагностика и screenshots вне Git:
`C:/Users/SW/Documents/Codex/outputs/e6-perspective-camera/REPORT.md`.
История E1–E5 не переписывается; новые механики не начаты.


## 2026-10-15 — Ground Resource Search Areas

Добавлен локальный допуск новых наземных источников: union resident/work-object/
применимой WorkArea. Начальные радиусы 4/10 world units, type definition override;
контейнеры сохраняют глобальную доступность. P1 ranking/early stopping/raw hints,
резервирование и committed delivery не заменены. UI, камера, tree/mining targets,
AI scheduler и GameTime не перерабатывались. Технические правила и потребители:
GROUND_RESOURCE_SEARCH.md; результаты приёмки — внешний отчёт ground-resource-
search-areas/REPORT.md. История P1 и Legacy Removal сохранена. Food availability
fan-out и массовые AI decisions остаются отдельными задачами, здесь не начаты.

## 2026-10-15 — P2 Food Availability

Общий предварительный FOOD total заменяет повторные population-wide source scans.
Синхронная реакция на контейнерную еду, реальные проверки источника и резервов,
личный Ground radius и действующий AI scheduler сохранены. Ground aggregate
обновляется прежним coalesced событием. Архитектура: FOOD_AVAILABILITY.md;
измерения/результаты: внешний performance-optimization-p2/REPORT.md. P1 и Ground
Search Areas не перерабатываются. Массовые фазовые AI decisions остаются отдельным
направлением P3; реализация P3 в эту задачу не входит.


### 2026-10-15 — P3.2: очередь обычных AI-решений

Реализована единая очередь на основе существующего Porter dispatcher: объединение
повторов, проверка актуальности, мягкий настраиваемый бюджет 1 мс, приоритеты/aging,
F10-метрики. Немедленный lifecycle ресурсов и критических реакций сохранён.
Проверки и измерения зафиксированы в отчёте P3.2 вне Git; контракт описан в
[AI_DECISION_QUEUE.md](AI_DECISION_QUEUE.md). Это не реализация последующих оптимизаций
PLANT, строительных уведомлений или GameTime; они требуют отдельного задания.


### 2026-10-15 — P3.3: randomized idle retry

Обычный пустой IDLE получает один случайный период10–30 игровых минут от RNG жителя.
Истечение входит в существующую очередь P3.2 без повторных timer requests во время
ожидания service. Прерывания и другие lifecycle сохранены; новых массовых уведомлений
нет. Изменение уменьшает регулярность retry, но допускает более позднее обнаружение
работы без внешнего события. Контракт — AI_DECISION_QUEUE.md, контрольные измерения
и полный regression suite — во внешнем отчёте performance-optimization-p3-3.
PLANT, строительные notifications и P3.4 в это изменение не входят.


## 2026-10-20 — D2: естественные тропинки

Вытаптывание 0–15 при физических входах, 25% на +1; зарастание неиспользованных
клеток одним пакетом в 23:00 за период 23:00–23:00. Бонус 1,25 с уровня 11 влияет
только на исполнение движения; A*/smoothing и AI не выбирают вытоптанные пути.
Адресные цвета одного MultiMesh сохраняют оттенок мицелия. Бесплатная ручная кисть
убрана из UI, прежний технический API дорог сохранён. См. DECISIONS, раздел D2.
Каменные дороги и новые экономические механики в D2 не входят.


## 2026-10-20 — D2.1: распределённое ночное зарастание

Пакет в 23:00 заменён псевдослучайным вычисляемым обходом 23:00–06:00, 97–98
клеток за минуту на основной карте. Суточные отметки передаются без копирования;
ночные проходы защищают текущую и соответствующую следующую ночь. Изменены только
RoadGrid и связанные проверки времени; визуализация и навигация D2 сохранены.
