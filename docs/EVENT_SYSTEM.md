# Универсальные события: изолированное ядро R2-B1

Система не подключена к игровому процессу. SocialEventService, отношения, дневник,
AI и игровые триггеры продолжают работать по прежним правилам. Новые классы —
RefCounted без Node, сигналов и автоматической загрузки каталога.

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
`text.diary_main` для будущего исполнения. Сейчас текст не выводится.

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
Заведомо невалидный context не потребляет RNG. Игровые источники occurrence ID,
реальный lifecycle, effect transactions и save/load остаются последующим этапам.

## Проверки

`test_event_expression.gd`, `test_event_engine.gd`, `test_event_scaling.gd` используют
существующий формат SceneTree-тестов. Большой тест валидирует 5000 definitions,
разделённых на 100 trigger buckets, и проверяет ровно 50 посещений на нужный trigger.
Его микрозамеры относятся к изолированному matching, не к FPS игры.
