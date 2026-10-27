# Универсальные события: ядро, представление, первый триггер и личные хранилища

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

## R2-B4a: MemoryStore и MoodletStore — данные без новых последствий

Каждый ResidentData создаёт два независимых RefCounted-хранилища: `memories` и
`moodlets`, привязанные к его стабильному ID. Сами хранилища не содержат ResidentData,
Node, Callable или Resource и не подключаются к GameTime, AI, Diary или EventEngine.
Существующий skill.raised продолжает создавать только дневниковую запись.

### Общий контракт

- `add(record) -> bool`, `get_entry(id) -> Dictionary`, `find(query={}) -> Array`,
  `remove(id) -> bool`, `size() -> int`, `owner() -> Dictionary`.
- ID задаёт вызывающая сторона; уникальность — внутри данного хранилища жителя.
  Повторный add того же ID отклоняется без замены, усиления или уведомления.
- Данные на входе и выходе глубоко копируются. Для будущих read-only fact providers
  используются get_entry/find/active; изменение их результата не меняет хранилище.
  `_entries` — внутреннее поле, не интерфейс читателя.
- `find` точно сопоставляет указанные верхнеуровневые поля, включая вложенные JSON
  значения. Пустой query возвращает все записи в порядке добавления; неизвестное
  поле не совпадает. Это не новый expression engine и не поиск по миру.
- `owner` — `{kind:"resident", id:...}`. Его можно опустить при add; чужой owner
  отклоняется. Необязательный `target` — null или ровно `{kind,id}` с непустыми
  строками. Ссылка хранится как историческое значение даже после удаления цели;
  активность будущего получателя эффекта обязан проверить будущий исполнитель.
- `tags` — массив непустых уникальных строк, `context` — произвольные JSON-данные
  в Dictionary. Времена — целые неотрицательные игровые минуты. Неизвестные поля
  записи отклоняются; дополнительные сведения помещаются в context/provenance.
- EventStoreData проверяет лишь данные (включая конечность чисел). Техническая
  глубина JSON 24 исключает циклический ввод; лимита числа записей нет.
- Локальный `changed(entry_id)` вызывается после завершённого изменения. Ошибочный
  ввод не меняет данные и не уведомляет. Никто в игре пока не подписан на этот сигнал.
  Это не транзакция нескольких JSON-effects и не массовая инвалидация AI.

### MemoryStore

Обязательные поля add:

```json
{
  "id":"memory/1", "type":"envy", "topic":"clothing",
  "target":{"kind":"resident","id":"B"},
  "tags":["negative"], "strength":20, "permanent":false,
  "created_minute":730, "source_occurrence_id":"occurrence/42",
  "provenance":{"kind":"experienced"}
}
```

`target`, tags, context и permanent необязательны (null, [], {}, false).
`type`, `topic`, strength, created_minute, source_occurrence_id и provenance обязательны.
Числа strength принимаются только в диапазоне 0..100. Автоматического permanent
при 80 или 100 нет. Для слуха provenance имеет `kind:"hearsay"` и обязательную
`reported_by:{kind:"resident",id:...}`; experienced не содержит reported_by.
Дополнительные incident_id/evidence_memory_id и другие JSON-сведения допустимы в
provenance. Они позволяют различать происшествия и цепочки источников.

`find_similar(type, topic, target, provenance)` точно сравнивает все четыре значения.
Зависть к одежде и жилью, разные цели, личный опыт и слухи, разные рассказчики или
incident_id не смешиваются. source_occurrence_id не входит в ключ аналогичного
переживания: новый случай может усилить уже найденное воспоминание по явному решению
вызывающей стороны. Несколько отдельных записей об одном типе допустимы.

`reinforce(id, amount, minute, source_occurrence_id)` требует положительную конечную
величину, существующий ID и непустой ID источника усиления; сила насыщается на 100.
Первоначальные created_minute/source_occurrence_id сохраняются, а
last_reinforced_minute/last_changed_minute/last_source_occurrence_id обновляются.

`weaken(id, amount, minute, removal_threshold)` требует явные положительное ослабление
и порог 0..100. Сила насыщается на 0. Обычная запись удаляется при strength <= порога;
постоянная остаётся даже при 0, но может быть явно удалена remove. Ослабление обновляет
last_changed_minute, не last_reinforced_minute. Обновления с временем раньше последнего
изменения отклоняются. Равное время разрешено для нескольких операций одной минуты.

Формула/период забывания, величина усиления, порог удаления и лимиты не назначены.
Никакой автоматический tick не вызывает weaken. Изолированный потребитель может
явно передать рассчитанные параметры; в обычной игре хранилища остаются пустыми.
Операции reinforce/weaken — явные команды, не исполнители событий: будущий coordinator
должен отсеивать повторную доставку effects. История всех source IDs здесь не ведётся;
защита add от повторного ID не заменяет дедупликацию будущего пакета последствий.

### MoodletStore

```json
{
  "id":"moodlet/1", "type":"envy", "tags":["negative"],
  "source_occurrence_id":"occurrence/42", "created_minute":730,
  "expires_at_minute":790, "target":{"kind":"resident","id":"B"},
  "context":{"topic":"clothing"}, "modifiers":[]
}
```

Обязательны id/type/source_occurrence_id/created_minute. Deadline может отсутствовать
или быть null; целое значение должно быть >= created_minute. `is_active(id,minute)`
проверяет интервал [created_minute, expires_at_minute); без deadline — от появления.
`active(minute,query={})` возвращает только активные копии, не меняя хранилище.
Обычный find возвращает также истёкшие записи до явного `expire(minute) -> int`.
Равный времени появления deadline даёт пустой интервал активности.

expire удаляет истёкшие записи одним локальным проходом до уведомлений. Повторный
вызов безопасен; запись, добавленная callback после этого прохода, не удаляется им.
Автоматического GameTime-подключения пока нет. Неограниченный deadline не означает
постоянную Memory: такой мудлет существует до явного удаления вызывающей стороной.

modifiers — только инертный массив JSON-словарей для будущего адаптера к существующему
ResidentModifiers. Новых каналов, формул сложения, бонусов, штрафов и потребителей нет.
Разные ID одного type хранятся независимо; одинаковый ID отклоняется. Политика
refresh/replace/stack не выбирается автоматически. while_cause из проекта R2-B0
не реализован: сейчас поддержаны только явное удаление и необязательный deadline.

Снимки JSON-совместимы, но import/save/load/миграция мира не реализованы. DiaryEntry
остаётся отдельной текстовой моделью; обратного преобразования дневника в Memory нет.
Тесты: test_event_stores.gd плюс неизменённая регрессия R2-B1/B2/B3.

## R2-B4b: исполнение memory.add / moodlet.add

GameEventService по-прежнему принимает только подтверждённый skill.raised и выбирает
одно определение через прежний EventDryRun. Затем EventEffectExecutor выбирает
последствия и применяет один синхронный пакет: обязательный Diary главного жителя,
выбранный опциональный Diary второго и выбранные memory.add/moodlet.add.
Событие без механических последствий всё равно состоялось, если его Diary записан.

### JSON и разрешение значений

Сохранены имена полей R2-B1: `memory.add.kind` становится MemoryStore.type,
`moodlet.add.definition` — MoodletStore.type. Оба требуют owner через role/binding;
необязательный target может быть null/исторической entity-ссылкой и не обязан быть
активным. Получатель записи обязан быть действующим жителем. main_role определяется
отдельно от actor и от owner каждого эффекта.

memory.add принимает kind, topic, tags, strength, permanent, provenance, target,
context. strength/provenance/topic проверяет существующий MemoryStore; hearsay требует
reported_by. Повторное аналогичное переживание создаёт отдельную запись. Неявное
усиление и новые параметры забывания не добавлены.

moodlet.add принимает definition, tags, target, context, modifiers и либо
`duration_minutes`, либо `expires_at_minute`, либо ни одного. Одновременно два срока
запрещены. Целые неотрицательные числовые значения JSON преобразуются в игровые минуты;
отрицательные, дробные, бесконечные и переполнение отклоняются. Deadline проверяется
существующим MoodletStore относительно минуты commit. Модификаторы остаются инертными
JSON-данными; никаких формул и потребителей ResidentModifiers не добавлено.

Внутри данных используются те же выражения EventExpression, включая role/binding,
param/catalog/ctx, field/fact и list. Литеральные словари и массивы разрешаются
рекурсивно. Это не новый язык шаблонов; Unknown или неверный тип выбранного аргумента
дают prepare_failed. EventDryRun возвращает дополнительно замороженные `tables`,
соответствующие выбранному определению: последствия не перечитывают изменённый каталог.

source_occurrence_id генерируется из настоящего триггера, а context._event содержит
ID события, definition_id/revision и slot последствия. context._event зарезервирован:
JSON не может подменить его. ID записи — JSON-массив [occurrence_id, definition_id,
revision, slot]. Для independent slot имеет вид effect/N, для группы —
group/ID/option/N. ID не зависит от RNG, имени или порядка обхода жителей.

opinion.add и skill.add_xp остаются разрешёнными описаниями dry-run R2-B1, но
исполнитель их отвергает как unsupported_effect. Проверяется всё выбранное определение,
включая невыбранные/нулевые варианты: шанс 0 не скрывает неподдерживаемую операцию.
Неизвестные параметры выбранного memory/moodlet также отклоняются. Прочие игровые
триггеры, effects и события без главного жителя не подключены.

### RNG последствий

`executor.rng` — собственный RandomNumberGenerator, отдельно от selector.rng,
SocialEventService и AI. Его можно seed-ить/заменять тестовым источником. Порядок:

1. effects в порядке массива: один draw на chance каждого, даже при 0/1.
2. exclusive_groups в порядке массива: один draw на chance группы (по умолчанию 1).
   При успехе и наличии положительных весов — один weighted draw с нормализацией
   по максимальному весу. Выбирается максимум одна option; нулевые веса исключены.
3. Если у выбранной option явно указан chance из формата R2-B1, выполняется ещё один
   draw. Его неуспех не выбирает другую option. Без явного chance такого draw нет.
4. В конце один draw для secondary_diary.chance, если политика объявлена.

`{"op":"none","weight":70}` — явный вариант без механического действия; кроме
op/weight/chance он не принимает аргументов и допускается только в группе.
Неуспешный шанс группы или все нулевые веса дают отсутствие выбора; weighted draw
в этом случае не расходуется. Вероятность 1 проходит и при тестовом roll=1;
остальные вероятности используют roll < chance. Некорректный RNG даёт отказ.

Все комбинации independent effects допустимы; группы не блокируют их. Неуспех
подготовки не перебрасывает RNG. Повтор ID возвращает сохранённый исход, включая отказ;
повторный publish не эмитит сигналов. Dedup сохраняется и в GameEventService, и внутри
исполнителя. Полного сохранения этих runtime-состояний нет.

### Prepare / commit / publish и предел гарантии

1. Исполнитель выбирает последствия без записи данных. Проверяет главного участника,
   рендерит требуемые Diary общим EventTextRenderer, разрешает аргументы effects.
   Текст/получатель опционального Diary требуются только при выбранной записи;
   вторичная сторона должна отличаться от главной. Неиспользуемый feed не публикуется.
2. Store.prepare_add проверяет запись/ID и возвращает отдельную нормализованную копию.
   ResidentData.can_add_diary_entry проверяет Diary. Пока нет никаких изменений/сигналов.
3. Непосредственно перед записью повторно проверяются источник, все получатели,
   идентичность хранилищ и подготовленные значения. При отказе весь набор отменяется.
4. Внутренние _apply_event_diary/_apply_event_add выполняют только append/присваивание
   уже подготовленных данных. Здесь нет RNG, await, сигналов, вызовов AI, проверок,
   которые могли бы отказать, либо произвольных игровых операций. Откат не используется.
5. GameEventService записывает completed/cooldown/outcome и снимает pending ID.
6. publish удаляет временный список уведомлений до вызова callbacks, затем эмитит
   Diary/store.changed. Последним публикуется event_completed. Любой наблюдатель
   видит все записи и metadata уже состоявшегося события. Вложенные факты ждут в прежней
   локальной синхронной FIFO до окончания публикации; кадровая очередь AI не меняется.

prepare_add/can_add_diary_entry и activity guard — чистые проверки. Внутренние
_apply_event_* — доверенные примитивы записи, не точки расширения/отказа/подписок.
Эта гарантия относится к синхронным изменениям в главном потоке при действующих
доменных API; она не является crash/OOM-транзакцией, защитой от произвольного
GDScript, заменяющего внутренние методы, или общим механизмом отката мира.
После commit обычные callbacks могут менять мир; это последующие операции, а не
частичный результат исходного события. Пакеты ресурсов, отношений, навыков и AI
в этот механизм не включены.

Обычные add/add_diary_entry сохраняют прежние уведомления и используют те же проверки.
Тест отказа Diary R2-B3 перенесён на can_add_diary_entry; его гарантия отказа сохранена.
Ожидание pending в Diary callback заменено на completed намеренно: metadata теперь
обязана быть зафиксирована до первого сигнала. Вся прежняя социальная механика и
необязательные 20% Diary двенадцати историй остаются прежними.

### personal.skill_progress revision 2

В assets/events/skill_progress.json заданы independent memory chance=0.6, strength=30,
permanent=false, topic из payload.skill и moodlet pride chance=0.3 на 120 минут.
Обязательный текст Diary прежний. Группы проверяются на тестовых определениях,
а не искусственно добавляются в эту историю. Мудлеты не изменяют поведение или mood;
память не меняет отношения и не влияет на выбор следующих историй. Автоматическое
ослабление/удаление и лимиты не вводились; срок проверяется прежним is_active/active,
физическое удаление истёкших записей по-прежнему требует явного expire.

Автоматический быстрый тест — test_event_effects.gd; он включает реальное повышение
навыка в canonical Main3D и не требует ручного ожидания. Также сохраняются тесты
R2-B1/B2/B3/B4a и golden старых социальных историй.

## R2-B5: социальный post-commit источник и факты пары

Main подключает GameEventService.attach_social к одному SocialEventService на сессию
мира. Общий источник для CONVERSATION/MEAL/WORK — новый interaction_committed после
существующего resolve. Старые chance, participant_pool, реакции, обе записи отношений,
present, Feed/Diary, logger и event_resolved сохраняют свои вызовы/порядок/RNG.
Новый источник не подписан отдельно на нужды/работу/минуты разговора.

При вложенном legacy resolve новые уведомления ждут окончания внешнего legacy вызова.
Маленькая синхронная очередь SocialEventService публикует результаты в порядке
завершённой механики, после прежних callbacks. Она не переносит решения на другой
кадр и не заменяет FIFO GameEventService либо AI queue. Это не новая атомарность
старых изменений отношений: их прежние сигналы и возможность reentry сохранены.

### Подтверждённый контекст

Каждая успешная resolve-попытка получает монотонный номер внутри SocialEventService.
occurrence_id — JSON ["social.resolved", number]. Счётчик не зависит от RNG, пары или
минуты и не сбрасывается set_seed; два первоначальных разговорных resolve имеют разные
ID. GameEventService допускает один социальный producer в своей runtime-сессии.
Между запусками/сохранениями ID пока не сохраняются.

SocialEvent.confirmed_context() возвращает копию зафиксированных данных. Они отделены
от прежних изменяемых полей представления/ориентации результата:

- trigger="social.resolved", actor/other — две resident-ссылки; actor — инициатор
  исходной legacy попытки, даже если текст старой истории использовал reverse.
- minute — время попытки; payload.time_known отмечает наличие clock. Без clock
  отдельный тестовый сервис использует 0 с time_known=false.
- payload.interaction — CONVERSATION/MEAL/WORK; reaction_1/reaction_2 — NEGATIVE,
  NEUTRAL или POSITIVE; attitude и оба roll — зафиксированные исходы legacy.
- opinion_delta_1/2 — прежние запрошенные -1/0/+1; applied_delta_1/2 учитывают clamp.
  opinion_before/after — значения собственного изменения, а не последующие правки
  callbacks. Например, +1 при opinion=100 даёт applied_delta=0.
- location_id — существующий ID места либо пустая строка; tags_1/2 — прежние теги
  presence. Для разговора здание определяется теми же presence, без нового поиска.

Event содержит только слабые ссылки на исходные ResidentData для проверки identity,
не сохраняет runtime Node. При постановке/обработке проверяются обе исходные личности;
удаление/повторная регистрация другого объекта с тем же ID не переадресуют старый факт.
Синтетический present без подтверждённого resolve не является новым триггером.

### Текущие read-only факты

ResidentEventFacts создаёт временный EventFacts-снимок только этой пары непосредственно
перед оценкой социального определения. Читает существующие ResidentData/stores; после
попытки selector/executor возвращаются к прежнему базовому registry. Это не постоянный
зеркальный кэш Memory/Moodlet/skills и не альтернативное хранилище жителей.

| Fact | Тип / аргумент | Источник |
|---|---|---|
| traits | array строк enum, без аргумента | ResidentData.traits |
| opinion | number, аргумент resident ref | get_opinion(target.id), направленно |
| skill.level | number, аргумент string skill ID | get_skill_level |
| skill.name | string, аргумент string skill ID | Skill.display_name |
| moodlets.active | array records | MoodletStore.active(текущая игровая минута) |
| memories | array records | MemoryStore.find() |

Идентификаторы traits/skills — нижний регистр ключей enum (lazy, gathering,
construction, logistics). Полученные значения — копии. Нет обхода поселения: две
регистрации entity, их три навыка, состояния и направленные отношения. Activity guard
Main теперь пользуется существующим SocialWorld.get_runtime по ID вместо перебора
resident_runtimes. Старый participant_pool по-прежнему выбирает собеседников прежним
способом; его поведение не оптимизировалось.

Подтверждённый payload никогда не перезаписывается текущими фактами. Если после
opinion=-1 callback изменил его на 20, payload.opinion_after_1 остаётся -1, а fact
opinion возвращает 20. Facts ограничены прежними техническими бюджетами R2-B1:
превышение MAX_COLLECTION даёт Unknown/отказ условия, а не усечение до части записей
или новый игровой лимит памяти. Автоматического забывания/лимитов stores нет.

### social.success_envy

assets/events/social_success_envy.json содержит одно включённое определение с
main_role=actor и weight=1. JSON требует отрицательную reaction_1, выбирает из
moodlets.active второго жителя один pride со source definition personal.skill_progress
и сравнивает уровни ровно context.skill этого мудлета. Первый подходящий binding
выбирается детерминированно по ID, без дополнительных tickets на каждую память,
гордость или ориентацию. Имена навыков также читаются через общий fact.

Результат: обязательный Diary; независимо 60% memory success_envy (strength=30,
permanent=false, topic=этот skill, target=собеседник) и 30% moodlet success_envy на
120 игровых минут, modifiers=[]. context сохраняет skill и ID причинного pride;
source_occurrence_id/context._event добавляет прежний исполнитель R2-B4b.
Успешная/нейтральная реакция, отсутствие подходящей активной pride или не меньший
уровень этого навыка не создают историю. Чужой высокий навык без соответствующей
гордости не подставляется случайно.

SOCIAL_FOLLOWUP_EVENT_CHANCE=0.30 в BalanceConfig — отдельный тестовый шанс после
подтверждённого legacy результата, не замена старых 30%/100%/50%. Тесты могут поставить
selector.set_chance("social.resolved",1). Используются существующие собственные
selector/executor RNG универсальной системы, не legacy rng/narrative_rng. В production
JSON не навязан новый cooldown; его прежний необязательный формат работает и проверен.

Первое определение описывает зависть инициатора. Возможность сделать вторую сторону
главной проверена отдельной JSON-конфигурацией с main_role=other/reaction_2, без
автоматического удвоения определений/весов в игре.

Исполнитель, prepare/commit/publish, независимые эффекты и дедупликация R2-B4b не
менялись. Legacy отношения уже применены и не откатываются при отсутствии/отказе
дополнительной истории. Вложенные результаты/повторы не обходят completed/cooldown.
Навыки, AI, выбор собеседников, старая социальная формула и Diary 20% не менялись.

Живой bootstrap объединяет два JSON-файла в существующий EventCatalog; именованные
catalogs можно задавать явно, одинаковые имена таблиц отклоняются. Повреждённый JSON,
неверный корень и конфликты таблиц диагностируются, а не пропускаются молча. Старые
dry-run fixture и их загрузка через EventCatalog остаются прежними.

Автопроверка: test_social_game_events.gd. Есть реальные ResidentSocialController,
meal_begun и Builder.work_cycle_started, плюс 30 seeded взаимодействий при включённом
и выключенном новом канале: совпадают реакции, отношения, Feed, старые Diary и оба
legacy RNG state. Golden R2-B2 двенадцати историй не пересоздаётся.

## R2-B6: шесть историй как контент

assets/events/catalog_expansion.json добавляет шесть enabled definitions. После
объединения файлов — восемь определений: шесть social.resolved и два skill.raised.
interaction_committed остаётся прежним сигналом-источником social.resolved; нового
триггера/алиаса не вводилось. Единственное runtime GDScript-изменение — подключение
файла к прежнему загрузчику. EventEngine/Expression/FactProvider/executor не расширялись.

| ID | Условия | Результат | Локальный cooldown |
|---|---|---|---:|
| social.success_admiration | Positive инициатора, active pride собеседника от реального повышения | Diary; 40% admiration Moodlet на 120 минут | 240 минут |
| social.warm_sympathy | Positive обоих участников | Главный Diary у other; 20% отдельный Diary инициатора, без механики | 240 минут |
| social.rough_conversation | CONVERSATION и negative обоих | Diary; 60% negative Memory о собеседнике, strength 30 | 120 минут |
| social.old_grudge | Negative инициатора; прежняя firsthand negative Memory о собеседнике, strength>0 и created_minute<ctx.minute | Только Diary, без усиления и нового отношения | 480 минут |
| social.character_contrast | CONVERSATION; neutral инициатора; actor sociable, other introverted | Только Diary | 240 минут |
| personal.skill_progress_advanced | Подтверждённое повышение и new_level>=params.minimum_level (3) | Diary; pride на 120 минут (chance=1), без дополнительной Memory | Не нужен: новое подтверждённое повышение — отдельная возможность |

Все веса =1, численные параметры — первоначальный тестовый баланс JSON. Социальные
cooldown направлены: scope=[actor,other]. Это не общий запрет событий для неупорядоченной
пары; обратная legacy попытка остаётся самостоятельной. Глобальные шансы BalanceConfig,
старые 30%/100%/50% и дополнительный SOCIAL_FOLLOWUP_EVENT_CHANCE не изменены.

Симпатия намеренно имеет main_role=other и отдельный текст secondary_diary для actor.
Различия характеров опираются на существующие SOCIABLE/INTROVERTED, не создают черт
и не меняют их. Обе narrative-only истории и старая обида не имеют механических
последствий; необходимость существующей памяти сама меняет набор подходящих историй.
Старая обида не использует слух как подтверждение личной обиды и не считает память
текущей минуты «старой». Разные подходящие воспоминания дают один ticket определения.

Уровневая история конкурирует с personal.skill_progress при достижении уровня 3+
в прежнем weighted choice. Один факт повышения не запускает обе истории. Pride от
новой истории содержит тот же фактический payload.skill, поэтому существующая
social.success_envy revision 2 и новое восхищение принимают оба известных источника
pride: personal.skill_progress и personal.skill_progress_advanced. Это изменение
JSON-условия происхождения; специальный обработчик/новый факт не понадобился.
Восхищение не требует, чтобы уровень самого наблюдателя был ниже — оно не является
замаскированной завистью. Навык во всех success bindings берётся из выбранного pride.

### Проверка универсальности и ограничения

Все шесть сценариев целиком выражены прежними JSON when/bind/fact/exists/has_tag,
params, ролями, весами, cooldown, текстами и двумя разрешёнными effects. Добавлений
к AST, исполнения новых операций, вычислителей отношений или модификаторов нет.
Старая обида — пример влияния памяти на выбор истории, не на AI/поведение/отношение.
Автоматического забывания и неявного reinforcement по-прежнему нет.

Для unary skill.raised достаточно payload.new_level/previous_level/skill_name/skill;
общие текущие resident facts к нему не подключались. Для будущих unary условий по
traits/memories потребуется отдельная интеграция фактов, но этим шести историям она
не нужна. Существующие Unknown/бюджеты коллекций/детерминированный первый binding
сохраняются. Текущие истории не требуют операций над несуществующими данными.

### Регрессии

TestEventCatalogContent использует production-каталог и проверяет каждый definition
на положительных/отрицательных состояниях, конкуренцию между новыми и со старыми
историями, точный уровень/причину pride, secondary Diary, optional effects, local
cooldown, dedup и 27 сочетаний context/reactions/skills/traits/memory. Реальная цепочка
SocialEventService → negative Memory → old_grudge и ResidentSocialController с двумя
исходными попытками проверяются без синтетического trigger-контекста.

Старые fixtures R2-B3/B4b/B5 теперь явно выбирают их исторические один/два определения:
их исходные проверки механики не должны зависеть от добавленной конкуренции контента.
Golden R2-B2 не пересоздаётся; его runtime-часть отключает только новый follow-up шанс,
чтобы сравнивать чистое legacy представление с прежним эталоном. Отдельный тест полного
включённого/выключенного каталога снимает legacy Diary именно в event_resolved до
универсальной публикации, без фильтрации по текстам. Тридцать seeded взаимодействий
дают те же реакции, отношения, Feed, старые Diary и оба legacy RNG state, даже когда
новые истории действительно выполняются. Никакая старая проверка не удалена.

## R2-B7: мировой факт construction.completed и один главный участник

Цепочка: Main._show_building → GameEventService.observe_construction →
BuildingInstance.complete_construction → construction_completed(snapshot) →
EventCandidatePicker → прежние selector/renderer/executor. Подписка идемпотентна,
не удерживает BuildingInstance сильной ссылкой и отключается при выходе сервиса.
Уже построенные начальные здания не получают ретроспективных событий.

Снимок содержит building_id, building_type (ключ enum), building_name, minute,
assigned_builder_ids и initial_construction. Он создаётся до resource/state callbacks
и очистки active_builder_ids, а отправляется после старого construction_changed.
Состав участников — только действующие claims площадки; вклад не учитывается.
Builder._accrue_work и Main3D._poll_building_work передают completion_minute до
уведомлений. Необязательный аргумент -1 сохраняет старый API: в таком изолированном
вызове адаптер читает clock при сигнале. payload.timestamp_source различает caller
и completion_signal. Реконструкция/восстановление и upgrade исключены самой моделью,
в том числе если подписка осталась после первой постройки.

Контекст использует trigger=construction.completed, minute из снимка,
building={kind:"building",id:...} и payload с остальными полями. Список assigned IDs
сохраняется до фильтрации. После фильтрации добавляется eligible_candidate_count,
а actor становится устойчивой resident-ссылкой выбранного живого зарегистрированного
жителя. Кандидаты с неверной ссылкой, без регистрации, неактивные и дубликаты
исключаются. EventCandidatePicker не знает строительных условий или определений:
его choose принимает список resident refs, registry и activity guard для других
мировых фактов. Порядок списка сохраняется; один равномерный randf выбирает одного
участника (даже если он один), пустой список не расходует RNG. Поток принадлежит
picker и допускает seed/тестовую подмену; AI и legacy random streams не используются.

Дальше выполняются отдельный trigger chance и единственный weighted выбор подходящего
JSON для выбранного actor. Если истории нет, шанс не прошёл, cooldown действует или
получатель исчез — попытка заканчивается; второй кандидат не выбирается. main другого
жителя даёт invalid_candidate_main до последствий. Текущие расширенные pair-факты
по-прежнему подключены только для social.resolved; для этой истории достаточно
существующих refs/payload/active_required. Новые факты о вкладе/зданиях не вводились.

ID = JSON ["construction.completed", building.id, runtime source generation].
Повторное уведомление того же экземпляра, в том числе вложенное, останавливается
существующими pending/outcomes до candidate RNG. Удалённый объект не удерживается;
новая площадка с тем же текстовым ID имеет другую generation. Ledger runtime-only,
полноценного save/load нет. Прежний prepare/commit/publish, повторная проверка
активности, согласованная запись Diary/Moodlet и cooldown остаются общими. Время
исполнения/истории cooldown читается сервисом при обработке, как у других триггеров;
подтверждённая minute факта в контексте при этом не перезаписывается.

assets/events/construction_completed.json добавляет девятое живое определение:
personal.construction_finished, main_role=actor, weight=1, обязательный diary_main.
Текст радуется завершённой стройке, не приписывая всю работу выбранному жителю.
Независимый moodlet work_satisfaction: chance=0.5, duration_minutes=120,
target=ctx.building, modifiers=[]. Отношения/память/XP не меняются. Production JSON
не задаёт cooldown; прежний формат поддерживается и проверяется отдельным тестом.
BalanceConfig.CONSTRUCTION_COMPLETED_EVENT_CHANCE=1.0 — технический тестовый баланс,
не изменение вероятностей других триггеров. Старые social/skill определения неизменны.

Автопроверка test_construction_game_events.gd включает настоящую многоэтапную стройку
двумя Builder-контроллерами в canonical Main3D, snapshot до очистки, собственные RNG,
no-match без retry, отсутствие частичных последствий, cooldown и повторные уведомления.
Не подключены новые общественные события, улучшения, восстановление или учёт участия.
