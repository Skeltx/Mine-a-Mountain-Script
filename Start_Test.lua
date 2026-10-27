-- ============================================================
-- MaM — Start_Test (модульная сборка из Test/src)
-- Запускает модули скрипта по очереди: от ядра к вкладкам.
-- Остановка при первой ошибке — с указанием сломанного модуля.
-- ============================================================

local BASE = "https://raw.githubusercontent.com/Skeltx/Mine-a-Mountain-Script/main/Test/src/"

local MODULES = {
    "00_main.lua",      -- ядро: сервисы, стейт, окно/вкладки, хелперы
    "10_esp.lua",       -- Crystal ESP + Player ESP (вкладка ESP)
    "15_net.lua",       -- сетевая база: auto-rejoin, тёплый пул серверов
    "20_boulders.lua",  -- Boulder ESP (вкладка ESP)
    "30_farm.lua",      -- вкладка Farming (pickup, авто-сбор, Boulder Farm)
    "40_shop.lua",      -- бомбы/магазин (Bomb Auto Buy)
    "50_teleports.lua", -- вкладка Teleports (Top Crystals, aim-TP, E)
    "60_movement.lua",  -- вкладка Movement (Speed/Noclip/InfJump/Fly)
    "70_settings.lua",  -- вкладка Settings (конфиги, темы, unload)
    "80_events.lua",    -- вкладка Events (Halloween 2026)
    "90_other.lua",     -- Collect Rune, Boulder ESP (Analog), FPS Boost, показ окна
}

print("[MaM Test] Загрузка модульной сборки, модулей: " .. #MODULES)

for i, name in ipairs(MODULES) do
    print("[MaM Test] " .. i .. "/" .. #MODULES .. " — " .. name)
    local ok, err = pcall(function()
        local chunk = game:HttpGet(BASE .. name)
        local fn = loadstring(chunk, name)
        fn()
    end)
    if not ok then
        warn("[MaM Test] МОДУЛЬ УПАЛ: " .. name .. " — " .. tostring(err))
        error("[MaM Test] остановлен на модуле " .. name, 0)
    end
end

print("[MaM Test] Все модули загружены.")
