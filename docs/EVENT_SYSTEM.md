# Универсальные события: ядро, представление и первый игровой триггер

Ядро R2-B1 по-прежнему пригодно для изолированного dry-run. R2-B3 подключает к нему
только skill.raised через GameEventService и обязательный дневник. Общий renderer
R2-B2 используется и старым социальным представлением, механика которого сохранена.
Ядро состоит из RefCounted; игровой адаптер — один Node без покадровых обновлений.

## Компоненты и вызов

- `event_facts.gd`: зарегистрированные схемы и подготовленные JSON-снимки фактов.
- `event_expression.gd`: проверка выражений и их чистое вычисление.
- `event_catalog.gd`: атомарная загрузка/валидация JSON и индекс trigger → definitions.
- `event_dry_run.gd`: один chance roll, matching, один weighted choice, локальный dedup.

Пример из тестового стенда (не код инициализации мира):

```gdscript
var facts = preload("res://scripts/event_facts.gd").new()
facts.register_entity({"kind": "resident", "id": "a"})
facts.register_fact("profession", "resident", "string")
facts.set_value({"kind": "resident", "id": "a"}, "profession", "builder")
var catalog = preload("res://scripts/event_catalog.gd").new()
if catalog.load_file("res://tests/fixtures/event_examples.json", facts):
    var runner = preload("res://scripts/event_dry_run.gd").new(catalog, facts)
    runner.set_chance("interaction.started", 0.3)
    runner.rng.seed = 42
    # runner.run(context, committed_history, true)
```

Все определения fixture выключены. Тесты включают собственные копии; runtime-сцены
не загружают эту fixture. Базовый словарь фактов наполняет вызывающая сторона,
в R2-B1 только синтетическими данными. Читатели не вызывают произвольный Callable,
Object.get или GDScript из JSON. Будущие живые адаптеры — отдельная интеграция.

## Формат

Корень: `schema_version:1`, `catalogs:{...}`, `definitions:[...]`. Для таблиц также
понимается корневое расположение R2-B0. Само определение версии 1 требует id,
revision, enabled, trigger, roles, main_role, weight. params/bind/when/effects/text
содержат данные из R2-B0. main_role — имя роли или binding с активной сущностью;
оно не обязано совпадать с ctx.actor. В роли-главном жителе нужен непустой
`text.diary_main` для будущего исполнения. Ядро dry-run само текст не выводит;
отдельный renderer может сформировать строки из выбранного результата.

Роль: `{type:"resident", from:"ctx.other", active_required:true,
participant:true, different_from:["actor"]}`. Ссылка ровно `{kind, id}`;
активность находится в реестре фактов. Обсуждаемая архивная цель может быть
binding типа resident_ref с active_required:false, но главным действующим
адресатом она стать не может. `participant` — описательная семантика, не команда AI.

Пять исходных определений R2-B0 сохранены в fixture с явными main_role,
diary_main и новым cooldown. Кухонный пример сохранён; шестое определение добавлено
для construction.completed из перечня R2-B1. Красота одежды, память и завершение
разговора остаются синтетическими фактами, настоящие механики не добавлены.

Будущие последствия только валидируются и возвращаются:

```json
{
  "effects":[
    {"op":"skill.add_xp","owner":{"role":"actor"},"skill":"construction","amount":1,"chance":0.5}
  ],
  "exclusive_groups":[
    {"id":"response","chance":1,"options":[
      {"op":"opinion.add","owner":{"role":"actor"},"target":{"role":"other"},"amount":1,"weight":3}
    ]}
  ]
}
```

У независимых effects есть chance; у группы — chance и взвешенные options для
будущего выбора не более одного. Это резерв формата, не уже работающий выбор
последствий. Описания поддерживают opinion.add, skill.add_xp, moodlet.add, memory.add.
`secondary_diary:{role:"other", chance:0.2}` с `text.diary_secondary` описывает
необязательный будущий дневник второго участника. Обязательный дневник главного
жителя и правило «механические эффекты могут не сработать» относятся к будущему
исполнению. Dry-run возвращает **selected**, не объявляет событие состоявшимся.

Приоритетные tiers, глобальные/индивидуальные count limits и старый limits не
используются. Ненулевой priority и наличие limits отклоняются. Нулевой priority
R2-B0 допускается для совместимости, но на выбор не влияет.

## Условия и типы

Выражения: role/binding/param/catalog/local/ctx; fact; field; all/any/not;
eq/ne/lt/lte/gt/gte; add/sub; has_tag; list; exists. Иные операции отклоняются.
ctx/field читают только подготовленные словари, не свойства живых объектов.

Fact registry задаёт entity kind, тип результата, тип необязательного аргумента и
nullable. Примитивы, array, record и entity различаются; bool не является number.
Известные статические типы проверяются при загрузке. Динамические поля и FactKeys
проверяются при вычислении тем же зарегистрированным reader; несовместимость даёт
Unknown и причину отказа, не значение по умолчанию. Нет полного структурного
type checker всех полей вложенных records.

`known:false` означает Unknown; `known:true,value:null` — известное отсутствие.
NOT Unknown остаётся Unknown; false AND Unknown = false, true OR Unknown = true.
Подходит только известный bool true. В exists достаточно известного свидетеля;
без свидетеля неизвестные элементы дают Unknown. Required select консервативнее:
неизвестный кандидат не должен скрыто менять первый выбранный элемент.

Bindings объявляются последовательно; forward/self refs запрещены. select требует
from/as:candidate/where, take:1, order_by:id/value. Сортировка детерминированна,
равные ключи разрешаются исходным порядком. Binding и роли возвращаются вместе с
определением, повторный поиск для последствий/текста не нужен. Никаких RNG в условиях.

Технические границы: 10 000 definitions, 16 млн символов JSON; 256 элементов
коллекции/полей record, 8 ролей/bindings; глубина 24, 512 узлов AST выражения,
32 768 шагов вычисления. Это ограничения входных данных/стоимости, не лимиты
количества событий на жителя. Коллекции не обрезаются до префикса; превышение
возвращает Unknown/ошибку бюджета. Не добавлены очереди продолжения между кадрами.

## Выбор, cooldown и ID

`set_chance` задаёт вероятность для типа trigger. Все определения одного trigger
используют один chance roll. При успехе проверяется только его индексированный
bucket, в порядке definition ID. Один подходящий definition даёт один ticket,
число bindings не размножает вес. Нулевой weight исключён из выбора, все положительные
конечные weights нормализуются для защиты суммы от переполнения.

Отдельный RNG можно заменить тестовым объектом с randf. Даже при chance 0/1
расходуется один draw; при положительных подходящих весах — ещё один для выбора.
Эффекты/текст/дневник не расходуют RNG. Тот же seed, каталог, факты и порядок
occurrences воспроизводят выбор; это не обещание детерминизма всего VillageSim.

Необязательный cooldown: `{minutes:240, scope:[{"role":"actor"}]}`.
Scope содержит скаляры/refs; ключ — JSON `[definition_id, normalized_scope]`.
Revision не сбрасывает интервал. run принимает history key→last_committed_minute;
при точном истечении интервала событие снова допускается. История только читается:
dry-run не создал обязательный дневник и не записывает в неё выбор.

context требует occurrence_id (уникальный в сессии), trigger, целую неотрицательную
minute и используемые роли/payload. Изолированный runner запоминает итог по ID,
включая chance_failed/no_match. Повторный ID возвращает копию прежнего результата
с duplicate:true, без повторного броска или перечитывания изменившихся фактов.
clear_session очищает только этот тестовый dedup. Удаление старых ID/сериализация
runner сейчас не реализованы; не использовать его бесконечно как игровой сервис.

Результат содержит status, chance_passed, eligible, selected, roles, bindings,
main, definitions_checked и duplicate. С diagnostic:true — id/причины отказов.
Заведомо невалидный context не потребляет RNG. Другие игровые источники occurrence ID,
общая переработка lifecycle, effect transactions и save/load остаются последующим
этапам. Единственный живой источник R2-B3 описан ниже.

## Проверки

`test_event_expression.gd`, `test_event_engine.gd`, `test_event_scaling.gd` используют
существующий формат SceneTree-тестов. Большой тест валидирует 5000 definitions,
разделённых на 100 trigger buckets, и проверяет ровно 50 посещений на нужный trigger.
Его микрозамеры относятся к изолированному matching, не к FPS игры.

## Общий текстовый renderer R2-B2

`event_text_renderer.gd` — чистая подстановка значений. Она не выбирает историю,
не рассчитывает реакции, не расходует RNG, не эмитит ленту и не записывает дневник.
В границах R2-B2 игровые triggers ещё не подключались; R2-B3 использует тот же renderer.

`render(template, values)` возвращает `{ok, text, errors}`. Шаблоны используют
`{actor.name}`, `{payload.skill}`, `{facet.label}` и другие разрешённые пути по
подготовленным словарям. Поддерживаются строковые, числовые и bool-значения.
Отсутствующий путь/null/composite вместо строки даёт диагностический отказ без
частичного текста. Объекты Godot не читаются. Строки вне грамматики placeholder
остаются буквальным текстом, а не командами/выражениями.

Подставленные имена не сканируются повторно: имя `{other.name}` выводится буквально.
Получить методы, свойства Node или исполнить код через такую строку невозможно.

`render_event(selection, context, projections)` принимает результат EventDryRun.run,
исходный context и локальные проекции имён. Ключ projections — EventFacts.ref_key(ref),
значение — словарь явно разрешённых скалярных полей, например `{name:"Анна"}`.
ID/kind переопределять нельзя; отсутствующее имя не заменяется ближайшим жителем.
Проверяются только используемые проекции и выбранный текстовый контекст, не весь
список eligible/diagnostics или всё население.

Возвращается `{ok, texts, errors}`: ключи feed, diary_main, diary_secondary сохранены
раздельно. Names берутся из разрешённых roles/bindings, а payload — из context;
коллизия корневых имён диагностируется. Соответствие главной/вторичной стороны и
политика отправки остаются у вызывающей стороны. Формирование этих строк не означает
создания обязательной записи дневника или исполнения выбранного события.

### Адаптер старых историй

SocialNarrativeEntry сохраняет свой формат, фильтры и render(template,a,b). Этот метод
передаёт renderer только два имени и включает legacy-диалект %A%/%B%. Для него сохранён
прежний порядок замен: сначала A, затем B; фигурные скобки не интерпретируются.
Это совместимый вход в общий renderer, не второй каталог историй/планировщик.
Все 12 entries.json остаются побайтно прежними. Fallback также формируется renderer,
с прежними строками и однопроходной подстановкой имён, как у старого sprintf.

SocialEventService по-прежнему владеет matching, одним ticket на entry, выбором
ориентации, Feed и опциональным Diary. Шансы, RNG draws, реакции, −1/0/+1, границы
20% для каждой непустой дневниковой стороны и две попытки при создании пары прежние.
Правило обязательного diary_main универсальных событий к legacy не применяется.

До изменений presentation снят golden на 03b590b: 648 сочетаний фильтров, 24 случая
историй (12 × обе ориентации), границы Diary/пустые строки, 150 seeded resolves,
runtime-вступления в разговор и сервисные MEAL/WORK. Fixture не пересоздаётся обычным запуском
теста. test_event_presentation_compatibility.gd сравнивает её с текущим поведением;
test_event_text_renderer.gd проверяет новые шаблоны и результаты R2-B1.

## R2-B3: skill.raised → обязательный Diary

GameEventService использует тот же EventCatalog/EventDryRun и EventTextRenderer;
отдельного выбора историй для навыков нет. Единственный активный игровой каталог —
assets/events/skill_progress.json: одно unary-определение personal.skill_progress,
main_role=actor, условие new_level>previous_level, только diary_main, effects пусты.
Настоящие русские названия берутся из Skill.display_name. BalanceConfig задаёт
SKILL_RAISED_EVENT_CHANCE=1.0 для первого среза; selector позволяет отдельный seeded/
injected RNG. Социальный RNG не используется.

### Подтверждённый факт

ResidentData.add_skill_xp сохраняет XP по прежней формуле и вызывает прежний
skill_changed с прежними аргументами. Новый skill_raised(transition_id, skill,
previous_level, new_level) публикуется только при фактическом переходе уровня,
после старых уведомлений. Owner-local FIFO сохраняет snapshots и порядок при
вложенном add_skill_xp из старого callback. Прыжок 0→N одной операцией — один факт,
а не N выдуманных промежуточных commits. XP без повышения и XP после cap не дают факта.

Occurrence ID состоит из типа, resident.id, внутриигрового source token и номера
перехода. Token закреплён за ResidentData через WeakRef: повторная регистрация того
же объекта не переименовывает старые факты; новый объект не сталкивается со старым
serial. Scene instance IDs не используются в идентичности события. Регистрация
не создаёт события задним числом для уже имеющегося XP.

### Выбор и подтверждение

GameEventService подключён в общей сборке Main, включая каноническую Main3D. Он
наблюдает residents_changed для своих подписок; глобальный lifecycle и SocialWorld
не меняются. Живой адресат обязан совпадать с PlayerControl registry и иметь активный,
не queued-for-deletion runtime в дереве. Проверка повторяется непосредственно перед
append; оставшаяся в памяти ResidentData сама по себе не делает жителя активным.
Главный получатель берётся из selection.main, а не неявно из context.actor.

Поток: подтверждённый факт → core chance/matching/weighted choice → renderer →
активный main resident → add_diary_entry → completed/history. Existing Diary API
теперь возвращает bool: false без append, true после append и прежнего diary_changed.
Старые callers могут игнорировать ответ; их поведение/уведомления сохранены.

Необязательное поле определения diary_importance поддерживает TEMPORARY=1/KEY=2;
NONE недопустим для обязательной записи. Первый каталог явно задаёт KEY=2. Запись
получает текущее игровое время append. Исторический текст не является Memory и не
меняет XP, opinion или mood. Обязательный текст должен успешно сформироваться и
быть непустым. Только положительный ответ append фиксирует event_id, completed и
cooldown key, рассчитанный самим ядром. Chance failure/no match/неактивность/text
failure/отказ append не создают completed и не запускают cooldown.

Текущая FIFO сервиса сериализует только вложенные доставки фактов в том же вызове,
без await/следующего кадра, чтобы callback Diary не обходил ещё не записанный cooldown.
Pending/processed IDs не дают повторной записи или нового RNG. replay возвращает
копию прежнего исхода, а не пытается заново разыграть failed event. Dry-run по-прежнему
только читает переданную history: новую запись делает исключительно live service
после успешного обязательного Diary. Callback completed публикуется после фиксации.

### Границы и проверка

Срез исполняет только обязательный Diary. Определения с mechanical effects,
exclusive_groups или secondary_diary возвращают unsupported_execution; их политики
не реализованы и не исполняются молча. Универсальный Feed сейчас не публикуется.
Старые 12 социальных историй по-прежнему имеют независимые опциональные 20% Diary.
Новых триггеров, Moodlet/Memory stores, AI feedback, UI или save/load нет.

Runtime ledgers/ID tokens живут до закрытия мира; сохранение counters/history/RNG
и их очистка для долгой persisted-сессии не реализованы. Состояние не гарантирует
устойчивость к завершению процесса. KEY сохраняется в данных, но существующая
карточка показывает текущий игровой день. Глобальный lifecycle из R2-A не исправлен.

test_live_skill_events проверяет реальные add_skill_xp, snapshots/reentrancy,
повторные доставки и регистрацию, text/append failure, cooldown, чужой main и
удаление после выбора. Отдельно завершается настоящий строительный цикл, а в
канонической main_3d проверяется обновление существующей карточки и новый resident.

Ручная проверка: F5 → назначить строителя и обеспечить несколько строек материалами →
дать ему закончить десять полных 60-минутных рабочих циклов (10 XP, уровень 1) →
выбрать его карточку «Дневник» в тот же игровой день. Ожидается одна ключевая запись
с именем, «Строительство» и 0→1. Передвижение/незавершённый цикл не дают награду;
следующая XP внутри уровня не создаёт новую запись. Для первого среза вероятность
100%; специальные кнопки XP или новый интерфейс не добавлены.
