-- ============================================================
-- MaM :: 50_teleports.lua
-- TELEPORTS — Top Crystals, Teleports (UI), обработка инпута (E/aim-TP)
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

local function sortedByScore(scoreFn)
    local scored = {}
    local seen = {}

    local function consider(inst)
        if seen[inst] or not inst.Parent then
            return
        end

        if getAttr(inst, "Collected") == true then
            return
        end

        seen[inst] = true
        local ok, score = pcall(scoreFn, inst)
        scored[#scored + 1] = { inst = inst, score = ok and score or 0 }
    end

    for inst in pairs(Storage.registry) do
        consider(inst)
    end

    eachContainer(function(container)
        for _, child in ipairs(container:GetChildren()) do
            if isCrystal(child) then
                consider(child)
            end
        end
    end)

    table.sort(scored, function(a, b)
        return a.score > b.score
    end)

    return scored
end

do
    local function install()
        local TopBox = Tabs.teleports:AddLeftGroupbox("Top Crystals", "trophy")

        local function fmtValue(_, score)
            return formatShort(score, "$")
        end

        local function fmtLuck(_, score)
            return formatLuck(score)
        end

        local function fmtWeight(inst)
            return formatWeight(crystalWeight(inst))
        end

        for rank = 1, 3 do
            TopBox:AddButton(string.format("Top %d Value", rank), function()
                tpToRank(crystalValue, rank, fmtValue)
            end)
        end

        TopBox:AddDivider()

        for rank = 1, 3 do
            TopBox:AddButton(string.format("Top %d Luck", rank), function()
                tpToRank(crystalLuck, rank, fmtLuck)
            end)
        end

        TopBox:AddDivider()

        for rank = 1, 3 do
            TopBox:AddButton(string.format("Top %d Weight", rank), function()
                tpToRank(crystalWeight, rank, fmtWeight)
            end)
        end

        local TeleportBox = Tabs.teleports:AddRightGroupbox("Teleports", "crosshair")

        TeleportBox:AddToggle("AimTeleport", {
            Text = "Aim Teleport",
            Default = false,
            Callback = function(value)
                State.aimTpEnabled = value
            end,
        })

        TeleportBox:AddLabel("Aim Teleport"):AddKeyPicker("AimTeleportKey", {
            Default = Config.KeybindAimTp,
            NoUI = false,
            Text = "Aim Teleport",
            Mode = "Always",
        })

        TeleportBox:AddDivider()

        TeleportBox:AddButton("TP Home", function()
            if fireRemote(Remotes.GoHome, "home") then
                Library:Notify("Teleporting home", 2)
            else
                Library:Notify("Remote unavailable", 2)
            end
        end)

        TeleportBox:AddButton("Sell All", function()
            task.spawn(function()
                local character = LocalPlayer.Character
                local root = getRoot()
                local humanoid = character and character:FindFirstChildOfClass("Humanoid")

                if not character or not root then
                    if Library then
                        Library:Notify("Character not found", 2)
                    end
                    return
                end

                Move.glideStop()

                pcall(function()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                end)

                local sellCFrame = getSellCFrame()
                applyPivot(sellCFrame)

                task.wait(0.05)

                pcall(function()
                    root.AssemblyLinearVelocity = Vector3.zero
                    root.AssemblyAngularVelocity = Vector3.zero
                    if humanoid then
                        humanoid.PlatformStand = false
                        humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
                    end
                end)

                task.wait(0.15)

                unfavoriteAll()
                fireRemote(Remotes.SellRequest, "all")

                local things = Services.Workspace:FindFirstChild("Things")
                local prox = things and things:FindFirstChild("SellProx")
                local prompt = prox and prox:FindFirstChildOfClass("ProximityPrompt")
                if prompt then
                    firePrompt(prompt)
                end

                task.wait(0.25)
                fireRemote(Remotes.SellRequest, "all")

                if Library then
                    Library:Notify("Teleported to sell station and sold all!", 3)
                end
            end)
        end)
    end

    install()
end


do
    local function install()
        local MOUSE_KEYS = {
            [Enum.UserInputType.MouseButton1] = "MB1",
            [Enum.UserInputType.MouseButton2] = "MB2",
            [Enum.UserInputType.MouseButton3] = "MB3",
        }

        local function pressedKeyName(input)
            local pressed = MOUSE_KEYS[input.UserInputType]
            if not pressed and input.UserInputType == Enum.UserInputType.Keyboard then
                pressed = input.KeyCode.Name
            end
            return pressed
        end

        Connections.aimInputConn = Services.UserInputService.InputBegan:Connect(function(input, processed)
            if processed or Services.UserInputService:GetFocusedTextBox() then
                return
            end

            local pressed = pressedKeyName(input)
            if not pressed then
                return
            end

            if State.instantPromptActive and pressed == "E" then
                local ok, err = pcall(function() if E.InstantGrab then E.InstantGrab() end end)
                if not ok then
                    reportError("instant", err)
                end
            end

            if not State.aimTpEnabled then
                return
            end

            local aimPicker = Library.Options.AimTeleportKey
            if pressed == (aimPicker and aimPicker.Value or Config.KeybindAimTp) then
                local ok, err = pcall(function() if E.aimTeleport then E.aimTeleport() end end)
                if not ok then
                    reportError("aim", err)
                end
            end
        end)
    end

    install()
end


