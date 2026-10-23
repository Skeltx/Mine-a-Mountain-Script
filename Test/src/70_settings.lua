-- ============================================================
-- MaM :: 70_settings.lua
-- SETTINGS — SaveManager, ThemeManager, вкладка Settings, cleanupAll/unload
-- Все общие имена приходят из getgenv().MaMEnv (заполняет 00_main).
-- ============================================================

local E = getgenv().MaMEnv

local Services = E.Services
local LocalPlayer = E.LocalPlayer
local Mouse = E.Mouse
local Config = E.Config
local State = E.State
local Storage = E.Storage
local Connections = E.Connections
local GuiRoot = E.GuiRoot
local Remotes = E.Remotes
local ESP = E.ESP
local PLAYER = E.PLAYER
local PACE = E.PACE
local TP = E.TP
local PICK = E.PICK
local COLORS = E.COLORS
local TIER_NAMES = E.TIER_NAMES
local LUCK = E.LUCK
local MUTATION_LUCK = E.MUTATION_LUCK
local WATCHED_ATTRIBUTES = E.WATCHED_ATTRIBUTES
local SUFFIXES = E.SUFFIXES
local PARSE_MULTIPLIERS = E.PARSE_MULTIPLIERS
local CONTAINER_NAMES = E.CONTAINER_NAMES
local Library = E.Library
local SaveManager = E.SaveManager
local ThemeManager = E.ThemeManager
local Window = E.Window
local Tabs = E.Tabs
local SettingsTab = E.SettingsTab
local EspHolder = E.EspHolder
local reportError = E.reportError
local formatShort = E.formatShort
local formatWeight = E.formatWeight
local formatDistance = E.formatDistance
local formatLuck = E.formatLuck
local parseValue = E.parseValue
local bindCharacter = E.bindCharacter
local getRoot = E.getRoot
local getAttr = E.getAttr
local crystalValue = E.crystalValue
local crystalWeight = E.crystalWeight
local crystalTier = E.crystalTier
local crystalRarity = E.crystalRarity
local crystalName = E.crystalName
local crystalColor = E.crystalColor
local mutationLuck = E.mutationLuck
local combinedLuckMult = E.combinedLuckMult
local computeLuck = E.computeLuck
local luckLabel = E.luckLabel
local luckLabelText = E.luckLabelText
local crystalLuck = E.crystalLuck
local meetsFilter = E.meetsFilter
local ownsGamepass = E.ownsGamepass
local realStat = E.realStat
local hasActiveRune = E.hasActiveRune
local looksLikeCrystal = E.looksLikeCrystal
local backpackCapacity = E.backpackCapacity
local backpackWeight = E.backpackWeight
local backpackFree = E.backpackFree
local isCrystal = E.isCrystal
local rebuildContainers = E.rebuildContainers
local eachContainer = E.eachContainer
local requestStream = E.requestStream
local applyPivot = E.applyPivot
local findClearGoal = E.findClearGoal
local finishTeleport = E.finishTeleport
local teleportTo = E.teleportTo
local schedule = E.schedule
local Mountain = E.Mountain
local Farm = E.Farm
local Money = E.Money
local Net = E.Net
local Move = E.Move
local setSpeedBoost = E.setSpeedBoost
local restoreInstantPrompts = E.restoreInstantPrompts
local clearRegistry = E.clearRegistry
local clearPlayerEsp = E.clearPlayerEsp
local unwatchContainers = E.unwatchContainers

SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetFolder("Skeltx")

ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder("Skeltx")

do
    local function install()
        local ConfigGroupbox = SettingsTab:AddLeftGroupbox("Configuration", "folder-cog")

        ConfigGroupbox:AddInput("SaveManager_ConfigName", {
            Text = "Config name",
            Placeholder = "My Config",
        })

        ConfigGroupbox:AddButton("Create config", function()
            local name = Library.Options.SaveManager_ConfigName.Value
            if name:gsub(" ", "") == "" then
                Library:Notify("Invalid config name (empty)", 2)
                return
            end

            local success, err = SaveManager:Save(name)
            if not success then
                Library:Notify("Failed to create config: " .. err)
                return
            end

            Library:Notify(string.format("Created config %q", name))
            Library.Options.SaveManager_ConfigList:SetValues(SaveManager:RefreshConfigList())
            Library.Options.SaveManager_ConfigList:SetValue(nil)
        end)

        ConfigGroupbox:AddDivider()

        ConfigGroupbox:AddDropdown("SaveManager_ConfigList", {
            Text = "Config list",
            Values = SaveManager:RefreshConfigList(),
            AllowNull = true,
        })

        ConfigGroupbox:AddButton("Load config", function()
            local name = Library.Options.SaveManager_ConfigList.Value
            local success, err = SaveManager:Load(name)
            if not success then
                Library:Notify("Failed to load config: " .. err)
                return
            end
            Library:Notify(string.format("Loaded config %q", name))
        end)

        ConfigGroupbox:AddButton("Overwrite config", function()
            local name = Library.Options.SaveManager_ConfigList.Value
            local success, err = SaveManager:Save(name)
            if not success then
                Library:Notify("Failed to overwrite config: " .. err)
                return
            end
            Library:Notify(string.format("Overwrote config %q", name))
        end)

        ConfigGroupbox:AddButton("Delete config", function()
            local name = Library.Options.SaveManager_ConfigList.Value
            local success, err = SaveManager:Delete(name)
            if not success then
                Library:Notify("Failed to delete config: " .. err)
                return
            end

            Library:Notify(string.format("Deleted config %q", name))
            Library.Options.SaveManager_ConfigList:SetValues(SaveManager:RefreshConfigList())
            Library.Options.SaveManager_ConfigList:SetValue(nil)
        end)

        ConfigGroupbox:AddButton("Refresh list", function()
            Library.Options.SaveManager_ConfigList:SetValues(SaveManager:RefreshConfigList())
            Library.Options.SaveManager_ConfigList:SetValue(nil)
        end)

        local AutoloadLabel = ConfigGroupbox:AddLabel("Current autoload config: " .. SaveManager:GetAutoloadConfig(), true)

        ConfigGroupbox:AddButton("Set as autoload", function()
            local name = Library.Options.SaveManager_ConfigList.Value
            local success, err = SaveManager:SaveAutoloadConfig(name)
            if not success then
                Library:Notify("Failed to set autoload config: " .. err)
                return
            end

            Library:Notify(string.format("Set %q to auto load", name))
            AutoloadLabel:SetText("Current autoload config: " .. name)
        end)

        ConfigGroupbox:AddButton("Reset autoload", function()
            local success, err = SaveManager:DeleteAutoLoadConfig()
            if not success then
                Library:Notify("Failed to reset autoload config: " .. err)
                return
            end

            Library:Notify("Set autoload to none")
            AutoloadLabel:SetText("Current autoload config: none")
        end)

        local MenuGroup = SettingsTab:AddRightGroupbox("Menu", "wrench")

        MenuGroup:AddLabel("Menu bind"):AddKeyPicker("MenuKeybind", {
            Default = Config.KeybindMenu,
            NoUI = true,
            Text = "Menu keybind",
        })

        MenuGroup:AddButton("Unload", function()
            Library:Unload()
        end)
    end

    install()
end

SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName", "MenuKeybind" })

Library.ToggleKeybind = Library.Options.MenuKeybind
ThemeManager:ApplyToTab(SettingsTab)

SaveManager:LoadAutoloadConfig()

local function cleanupAll()
    State.espActive = false
    State.playerEspActive = false
    State.aimTpEnabled = false
    setSpeedBoost(false)
    finishTeleport()

    unwatchContainers()

    if Mountain.shutdown then
        Mountain.shutdown()
    end

    if Move.shutdown then
        Move.shutdown()
    end

    restoreInstantPrompts()

    table.clear(Storage.pendingActions)
    table.clear(Storage.promptRestores)
    table.clear(Storage.claimed)

    if Net.stop then
        Net.stop()
    end

    for _, connection in ipairs(Storage.netConns) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(Storage.netConns)

    State.afkRunning = false
    for _, connection in ipairs(Storage.afkConns) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(Storage.afkConns)

    if Farm and Farm.stop then
        Farm.stop()
    end

    if Money and Money.stop then
        Money.stop()
    end

    for key, connection in pairs(Connections) do
        if connection then
            connection:Disconnect()
        end
    end
    table.clear(Connections)

    State.speedHooked = nil

    clearRegistry()
    clearPlayerEsp()

    if EspHolder then
        EspHolder:Destroy()
        EspHolder = nil
    end

    State.rootPart = nil
    getgenv().UniverseLoaded = false
    getgenv().UniverseUnload = nil
end

getgenv().UniverseUnload = cleanupAll
Library:OnUnload(cleanupAll)

-- ====================================================================
-- ВАЖНО (fix "Out of local registers"): авторский блок (Events/Other и
-- новые функции ниже) обёрнут в функцию — его локали не занимают регистры
-- основного чанка (лимит 200), а живут в собственном пространстве функции.
-- Запуск — в самом конце файла (__initAuthorBlock()).
-- ====================================================================

