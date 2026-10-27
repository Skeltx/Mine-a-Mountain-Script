-- ============================================================
-- MaM вЂ” Start_Test (РјРѕРґСѓР»СЊРЅР°СЏ СЃР±РѕСЂРєР° РёР· Test/src)
-- Р—Р°РїСѓСЃРєР°РµС‚ РјРѕРґСѓР»Рё СЃРєСЂРёРїС‚Р° РїРѕ РѕС‡РµСЂРµРґРё: РѕС‚ СЏРґСЂР° Рє РІРєР»Р°РґРєР°Рј.
-- РћСЃС‚Р°РЅРѕРІРєР° РїСЂРё РїРµСЂРІРѕР№ РѕС€РёР±РєРµ вЂ” СЃ СѓРєР°Р·Р°РЅРёРµРј СЃР»РѕРјР°РЅРЅРѕРіРѕ РјРѕРґСѓР»СЏ.
-- ============================================================

local BASE = "https://raw.githubusercontent.com/Skeltx/Mine-a-Mountain-Script/test/Test/src/"

local MODULES = {
    "00_main.lua",      -- СЏРґСЂРѕ: СЃРµСЂРІРёСЃС‹, СЃС‚РµР№С‚, РѕРєРЅРѕ/РІРєР»Р°РґРєРё, С…РµР»РїРµСЂС‹
    "10_esp.lua",       -- Crystal ESP + Player ESP (РІРєР»Р°РґРєРё Crystals/Players)
    "15_net.lua",       -- СЃРµС‚РµРІР°СЏ Р±Р°Р·Р°: auto-rejoin, С‚С‘РїР»С‹Р№ РїСѓР» СЃРµСЂРІРµСЂРѕРІ
    "20_boulders.lua",  -- Boulder ESP/Farm (РІРєР»Р°РґРєР° Boulders)
    "30_farm.lua",      -- РІРєР»Р°РґРєР° Farming (pickup, Р°РІС‚Рѕ-СЃР±РѕСЂ, Money-С„Р°СЂРј)
    "40_shop.lua",      -- Р±РѕРјР±С‹/РјР°РіР°Р·РёРЅ (Bomb Auto Buy)
    "50_teleports.lua", -- РІРєР»Р°РґРєР° Teleports (Top Crystals, aim-TP, E)
    "60_movement.lua",  -- РІРєР»Р°РґРєР° Movement (Speed/Noclip/InfJump/Fly)
    "70_settings.lua",  -- РІРєР»Р°РґРєР° Settings (РєРѕРЅС„РёРіРё, С‚РµРјС‹, unload)
    "80_events.lua",    -- РІРєР»Р°РґРєР° Events (Halloween 2026)
    "90_other.lua",     -- РІРєР»Р°РґРєР° Other (Collect Rune, Boulder ESP+Farm, FPS Boost)
}

print("[MaM Test] Р—Р°РіСЂСѓР·РєР° РјРѕРґСѓР»СЊРЅРѕР№ СЃР±РѕСЂРєРё, РјРѕРґСѓР»РµР№: " .. #MODULES)

for i, name in ipairs(MODULES) do
    print("[MaM Test] " .. i .. "/" .. #MODULES .. " вЂ” " .. name)
    local ok, err = pcall(function()
        local chunk = game:HttpGet(BASE .. name)
        local fn = loadstring(chunk, name)
        fn()
    end)
    if not ok then
        warn("[MaM Test] РњРћР”РЈР›Р¬ РЈРџРђР›: " .. name .. " вЂ” " .. tostring(err))
        error("[MaM Test] РѕСЃС‚Р°РЅРѕРІР»РµРЅ РЅР° РјРѕРґСѓР»Рµ " .. name, 0)
    end
end

print("[MaM Test] Р’СЃРµ РјРѕРґСѓР»Рё Р·Р°РіСЂСѓР¶РµРЅС‹.")
