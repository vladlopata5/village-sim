# Ground resource search areas

Текущее согласованное правило от 2026-10-15: **resident circle OR work-object circle
OR applicable activity WorkArea**. Это допуск нового наземного источника, а не
право выполнять любую операцию с ресурсом и не ограничение всех маршрутов.

## Координаты и конфигурация

Симуляция использует Vector2; WorldCoordinates переводит их в плоскость 3D XZ:
25 simulation units = 1 world unit. BuildGrid имеет клетку 0.5 world units и bounds
128×80; типичные footprints 6×4, Home 3×2, Town Center 8×6 world units.
BalanceConfig задаёт resident_ground_search_radius через константу
RESIDENT_GROUND_SEARCH_RADIUS=100 и default_building_ground_search_radius через
DEFAULT_BUILDING_GROUND_SEARCH_RADIUS=250. Это 4 и 10 world units соответственно.
Рабочие области добычи 15 world units остаются без изменений.

BuildingDefinition.ground_search_radius=-1 означает общий стандарт;
get_ground_search_radius() также отклоняет NaN/Infinity к стандарту. Конечное
значение >=0 переопределяет радиус в simulation units. Определение типа можно
настроить при его создании; нового редактора, manager или UI нет. Если definition
разделяется несколькими экземплярами одного типа, её настройка применяется к ним.
Изменение отдельного определения не меняет другие определения.
Круги включают границу по distance_squared <= radius². WorkArea проверяется
своим contains(), без аппроксимации или изменения её исходной геометрии.

## Карта реальных потребителей

| Поиск | Новый допуск Ground | Контекст рабочего объекта / области |
|---|---|---|
| Builder._material_trip → find_construction_trip (P1) | Да, до lower bounds/A* | Рассматриваемая площадка; самостоятельной Builder WorkArea нет |
| Builder fallback → ResourceSources.find | Да | Та же площадка; используется также isolated domain fixtures |
| LogisticsController._candidate_scan, Porter | Да, до score/route checks | Назначенный workplace; текущие правила Porter не допускают WorkArea |
| ResidentSelfLogistics.task, Sawyer input supply | Да | Собственная лесопилка; существующие назначения не сочетаются с WorkArea |
| Lumberjack COLLECT → find_ground_in_area | Да, объединение вместо прежнего area-only допуска | Своя хижина и area из ForestryWorkContext |
| Miner COLLECT → find_ground_in_area | Да, то же объединение | Своя каменоломня и area из NaturalWorkContext |
| ResidentNeedsController, FOOD Ground | Да | Только фактическое положение жителя; потребность не является его работой |
| Gatherer production | Нет нового наземного поиска | Производство FOOD и собственный контейнер; self-export сохраняется |
| Forestry CHOP/PLANT, free forestry | Не затронуты | Прежние цели деревьев/посадок и WorkArea |
| Quarry MINE, free mining | Не затронуты | Прежние месторождения и WorkArea |
| Container supply/export, storage destinations | Пространственный фильтр не применяется | Прежние flow policies, capacity, ownership, routes |
| Pickup/delivery/release/expiry/dropped cargo | Не являются новым поиском | Прежние транзакции и физическое выполнение |

FREE-лесоруб и FREE-каменщик не приобретают новую механику COLLECT: они добывают
Ground по существующим правилам. Их зарегистрированная WorkArea по-прежнему
задаёт цели добычи. У работников здания existing effective area строится прежними
WorkContext из position/work_radius; фильтр получает именно эту area. При смене
назначения контроллер снова разрешает актуальный контекст.

## Граница query и мутации

GroundSearchAreas — небольшой статический predicate/identity helper, не registry.
ResourceSources.ground_candidates(resource, origin, workplace=null, area=null)
один раз обходит drops; resource=-1 означает все типы для Porter. Не подходящие
по типу/количеству/свободе/геометрии drops не превращаются в SourceRef и не
передаются маршрутизатору. GroundResource не имеет spatial index (есть ID index).
Простой O(N) проход выбран вместо новой spatial database; его стоимость измеряется
отдельно. Контейнеры добавляются независимо и сохраняют прежнюю доступность.

ResourceSources.ground_allowed проверяет одну ссылку без изменения данных.
find и find_construction_trip получили необязательные workplace/area в конце
аргументов; find_ground_in_area получил workplace. Название последнего сохранено
как activity-context query, но допуск теперь union. Параметр origin обязателен и
является положением конкретного исполнителя. Без валидного origin Ground закрыт.
При отсутствии workplace используется resident circle и явно применимая area.

work_object_current — read-only callback в существующий Main.buildings. Он нужен
потому, что resource container registry включает только функционирующие здания,
а стройплощадка уже является рабочим объектом. Изолированный ResourceSources без
callback разрешает workplace по собственной существующей buildings dictionary.
Удалённый или заменённый объект не даёт старую область.

Контроллеры передают тот же predicate в уже существующую pre-publication
eligibility (Porter/self-supply/internal COLLECT). Builder и EAT повторяют допуск
в конце собственной reservation transaction и при отказе выполняют прежний
owned rollback. claim_transport, ResourceSources.reserve/reserved/pickup/release,
HaulExecutor и движение не получают универсальных ограничений радиуса. Прямые
низкоуровневые claim APIs остаются транзакциями; выбор источника и activity context
являются обязанностью вызывающего контроллера.

## Актуальность и P1

Builder negative key: current position, sources.revision, геометрия/identity/radius
живых площадок. Положительный one-use trip дополнительно проверяет свою search
identity, прежние source/path/navigation invariants. Количество изменилось, но
геометрия и выбранный источник остаются допустимы — сохранённый raw trip может
переиспользоваться. Другие источники не превращаются в глобальный route cache.
Natural worker one-use offers сравнивают текущую area identity/geometry и radius
здания. Porter/self-supply снова строят актуальный небольшой pool при выборе.
FOOD probe учитывает текущую actual resident position отдельно от portal origin.

GroundResource.world_position setter публикует прежний availability_changed;
GroundResources передаёт его в ResourceSources.revision/отложенный coalesced changed.
3D-представление синхронизирует только свою позицию тем же сигналом. Ресурсы/резервы
не копируются. Обычная игра не перемещает лежащий ресурс сама по себе.

Проверка новой геометрии выполняется на существующих decision boundaries/events,
а не через новый movement listener, обход ресурсов каждый кадр или новый scheduler.
Неизменный отрицательный Builder/FOOD query не планируется заново. Движение,
перемещение/появление/исчезновение ресурса, изменение area/radius/назначения или
навигации позволяют следующему запросу найти актуальный источник.

После публикации committed job область больше не проверяется. Житель вправе
дойти до зарезервированного предмета и доставить его за пределы исходного круга.
Переезд рабочего объекта/источника и lifecycle invalidation по-прежнему могут
требовать обычной проверки пути/сущности; это не новый radius-based interrupt.
У Builder следующая единица после разгрузки выбирается новым поиском: завершённый
рейс не открывает глобальный доступ к оставшимся предметам.
P1 lower bound ranking, 1.25 early stopping и одноразовые raw hints сохранены;
кандидаты не сглаживаются, execution smoothing остаётся прежним.

## Проверки и ограничения

Новые test_ground_search_areas и test_ground_search_jobs проверяют inclusive
границы, union без дубликатов, отсутствие контекста, живое перемещение/удаление,
разные radii, actual WorkArea, дальние контейнеры, исключение до route query,
достижимость, negative cache, устаревший claim и завершение реальных Builder,
Porter, Lumberjack/Miner INTERNAL hauls после ухода/переназначения.

Старые tests, которые предполагали глобальный Ground, адаптированы:
геометрические ranking fixtures явно задают большую область/override; участники
конкуренции находятся рядом; economy/quarry физически собирают добычу в storage
через обычного Porter до удалённого строительства. Проверки рецептов, сохранения
материалов, маршрутов, резерва и завершения работы сохранены.

Результаты полного набора, analyzer, отдельных before/after benchmark, обычных
x20-прогонов и rendered QA находятся вне Git:
C:/Users/SW/Documents/Codex/outputs/ground-resource-search-areas/REPORT.md.
Это не food fan-out/AI scheduler optimization и не обещание устранения всех фризов.
