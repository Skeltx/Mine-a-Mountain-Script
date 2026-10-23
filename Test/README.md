# Test — модульная сборка MaM

Разработка идёт здесь: скрипт разбит на независимые модули, каждый можно
редактировать отдельно. Для публикации объединяем в основную версию.

## Структура

```
Test/
├── README.md          — этот файл
├── tools/
│   └── build.ps1      — генератор: режет чистовую версию (MaM v0.6.lua) на модули
└── src/               — модули в порядке загрузки (Start_Test.lua грузит их подряд)
    ├── 00_main.lua       — ядро: сервисы, стейт, окно/вкладки UI, хелперы, планировщик
    ├── 10_esp.lua        — Crystal ESP, Player ESP (вкладки Crystals, Players)
    ├── 15_net.lua        — сеть: auto-rejoin, тёплый пул серверов
    ├── 20_boulders.lua   — Boulder ESP, Boulder Farm (вкладка Boulders)
    ├── 30_farm.lua       — Pickup, авто-сбор, вкладка Farming
    ├── 40_shop.lua       — Bomb Auto Buy (магазин)
    ├── 50_teleports.lua  — вкладка Teleports (Top Crystals, TP Home/Sell, aim-TP, E)
    ├── 60_movement.lua   — вкладка Movement (Speed/Noclip/InfJump/Fly)
    ├── 70_settings.lua   — вкладка Settings (SaveManager, темы, unload/cleanup)
    ├── 80_events.lua     — вкладка Events (Halloween 2026)
    └── 90_other.lua      — вкладка Other (Collect Rune, Boulder ESP/Farm, FPS Boost)
```

## Как страницы связаны

- Все общие имена (Services, State, Library, хелперы и т.д.) живут в
  `getgenv().MaMEnv` — их заполняет `00_main`, остальные модули импортируют.
- Новый модуль = новый файл `NN_name.lua` + добавить имя в `Start_Test.lua`.
- Лимит Luau «не больше 200 локалей» теперь действует на каждый модуль
  отдельно — правки не должны переполнить бюджет своего модуля.

## Запуск тестовой сборки в Xeno

Вставить `Start_Test.lua` (в корне репозитория) и выполнить — он скачает
и запустит все модули по очереди с нумерацией в консоли.

## Как сделать модули основными (публикация v0.7)

1. Дорабатываем модули в `Test/src/`.
2. Запускаем `tools/build.ps1` (читает корневой `MaM v0.6.lua` и пересобирает
   `src/`) — либо, если модули уже переписаны вручную, собираем монолит.
3. Монолит публикуем как новый корневой файл `MaM v0.7.lua`, прежний
   переносим в `Old Versions/`, ссылку обновляем в `Start.lua`.
