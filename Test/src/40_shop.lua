-- ============================================================
-- MaM :: 40_shop.lua
-- SHOP — Bomb Auto Buy (закупка бомб)
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
local EventsTab = E.EventsTab
local OtherTab = E.OtherTab
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

        local function buyAllAvailableBombs()
            local query = Remotes.BombShopQuery
            local buyReq = Remotes.BombBuyRequest

            if not query or not buyReq then
                return 0
            end

            local ok, data = pcall(function()
                return query:InvokeServer()
            end)
            if not ok or not data or not data.stock then
                return 0
            end

            local boughtTotal = 0

            for bombId, amount in pairs(data.stock) do
                local count = tonumber(amount) or 0
                if count > 0 then
                    for _ = 1, count do
                        local success, res = pcall(function()
                            return buyReq:InvokeServer(bombId)
                        end)
                        if success and res and res.ok then
                            boughtTotal += 1
                        else
                            break
                        end
                    end
                end
            end

            return boughtTotal
        end

        if Remotes.BombShopRestocked then
            Connections.bombRestockConn = Remotes.BombShopRestocked.OnClientEvent:Connect(function()
                if State.autoBuyBombs then
                    task.spawn(buyAllAvailableBombs)
                end
            end)
        end

        local bombCheckClock = 0
        Connections.bombLoopConn = Services.RunService.Heartbeat:Connect(function(deltaTime)
            if State.autoBuyBombs then
                bombCheckClock += deltaTime
                if bombCheckClock >= 10.0 then
                    bombCheckClock = 0
                    task.spawn(buyAllAvailableBombs)
                end
            end
        end)

        local BombBox = Tabs.farming:AddLeftGroupbox("Bomb Auto Buy", "bomb")
        BombBox:AddLabel("Buys all bombs from shop whenever stock is available", true)
        BombBox:AddDivider()

        BombBox:AddToggle("AutoBuyBombs", {
            Text = "Auto Buy On Restock",
            Default = Config.AutoBuyBombs,
            Callback = function(value)
                State.autoBuyBombs = value
                if value then
                    task.spawn(buyAllAvailableBombs)
                end
            end,
        })

        BombBox:AddButton("Buy All Stock Now", function()
            task.spawn(function()
                local count = buyAllAvailableBombs()
                if Library then
                    Library:Notify(string.format("Purchased %d bombs from shop!", count), 3)
                end
            end)
        end)

