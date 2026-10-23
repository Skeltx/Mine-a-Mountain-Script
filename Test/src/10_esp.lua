-- ============================================================
-- MaM :: 10_esp.lua
-- ESP — движок ESP кристаллов/игроков + вкладка Crystals + Player ESP (UI)
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

local function newLabel(name, parent, order, total, color, rich, maxText)
    local label = Instance.new("TextLabel")
    label.Name = name
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Size = UDim2.new(1, 0, 1 / total, 0)
    label.Position = UDim2.new(0, 0, order / total, 0)
    label.Font = ESP.font
    label.TextScaled = true
    label.TextTransparency = 0
    label.TextStrokeTransparency = 0
    label.TextStrokeColor3 = COLORS.stroke
    label.TextColor3 = color
    label.RichText = rich == true
    label.Text = ""
    label.Parent = parent

    local constraint = Instance.new("UITextSizeConstraint")
    constraint.MaxTextSize = maxText
    constraint.Parent = label

    return label, constraint
end

local function crystalGuiSize()
    return UDim2.fromOffset(ESP.width * State.espScale, ESP.height * State.espScale)
end

local function crystalTextSize()
    return math.max(6, math.floor(ESP.text * State.espScale + 0.5))
end

local function playerGuiSize()
    return UDim2.fromOffset(PLAYER.width * State.playerScale, PLAYER.height * State.playerScale)
end

local function playerTextSize()
    return math.max(6, math.floor(PLAYER.text * State.playerScale + 0.5))
end

local function createEntry(inst)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "UniverseEsp"
    billboard.Adornee = inst
    billboard.AlwaysOnTop = true
    billboard.ResetOnSpawn = false
    billboard.LightInfluence = 0
    billboard.Size = crystalGuiSize()
    billboard.StudsOffsetWorldSpace = ESP.offset
    billboard.MaxDistance = math.huge
    billboard.Parent = EspHolder

    local textSize = crystalTextSize()
    local rarity, rarityConstraint = newLabel("Rarity", billboard, 0, 3, COLORS.default, false, textSize)
    local info, infoConstraint = newLabel("Info", billboard, 1, 3, COLORS.money, false, textSize)
    local extra, extraConstraint = newLabel("Extra", billboard, 2, 3, COLORS.extra, true, textSize)

    return {
        gui = billboard,
        rarity = rarity,
        info = info,
        extra = extra,
        constraints = { rarityConstraint, infoConstraint, extraConstraint },
        signature = false,
        luckText = "+0%",
        distanceText = false,
    }
end

local function destroyEntry(inst, entry)
    entry = entry or Storage.espCache[inst]
    if not entry then
        return
    end

    if entry.gui then
        entry.gui:Destroy()
    end

    Storage.espCache[inst] = nil
    State.espCount -= 1
    State.statsDirty = true
end

local function applyEspScale()
    local size = crystalGuiSize()
    local textSize = crystalTextSize()
    for _, entry in pairs(Storage.espCache) do
        if entry.gui then
            entry.gui.Size = size
        end
        for _, constraint in ipairs(entry.constraints) do
            constraint.MaxTextSize = textSize
        end
    end
end

local function applyPlayerScale()
    local size = playerGuiSize()
    local textSize = playerTextSize()
    for _, entry in pairs(Storage.playerCache) do
        if entry.gui then
            entry.gui.Size = size
        end
        for _, constraint in ipairs(entry.constraints) do
            constraint.MaxTextSize = textSize
        end
    end
end

local function applyExtra(entry, distanceText)
    entry.distanceText = distanceText
    entry.extra.Text = string.format(
        '<font color="#%s">%s</font>  \u{2022}  <font color="#%s">%s</font>',
        COLORS.hexDistance,
        distanceText,
        COLORS.hexLuck,
        entry.luckText
    )
end

local function buildTitle(inst)
    local rarity = crystalRarity(inst)
    local name = crystalName(inst)
    local mutation = getAttr(inst, "Mutation")
    if type(mutation) == "string" and mutation ~= "" then
        return string.format("[%s] %s (%s)", rarity, name, mutation)
    end
    return string.format("[%s] %s", rarity, name)
end

local function applyDetails(inst, entry, origin)
    local title = buildTitle(inst)
    local color = crystalColor(inst)
    local money = formatShort(crystalValue(inst), "$")
    local weight = formatWeight(crystalWeight(inst))

    local luckOk, luck = pcall(crystalLuck, inst)
    entry.luckText = formatLuck(luckOk and luck or 0)

    entry.rarity.Text = title
    entry.rarity.TextColor3 = color
    entry.info.Text = string.format("%s  \u{2022}  %s", money, weight)

    local distanceText = "--"
    if origin then
        distanceText = formatDistance((inst.Position - origin).Magnitude)
    end

    applyExtra(entry, distanceText)
end

local function crystalSignature(inst)
    return table.concat({
        tostring(getAttr(inst, "Tier")),
        tostring(getAttr(inst, "TierName")),
        tostring(getAttr(inst, "CrystalName")),
        tostring(getAttr(inst, "Value")),
        tostring(getAttr(inst, "WeightKg")),
        tostring(getAttr(inst, "Mutation")),
        tostring(getAttr(inst, "ExtraMutations")),
        tostring(luckLabelText(inst)),
    }, "|")
end

local function markDirty(inst)
    Storage.dirty[inst] = true
end

local function untrackCrystal(inst)
    local conns = Storage.registry[inst]
    if not conns then
        return
    end

    for _, connection in ipairs(conns) do
        connection:Disconnect()
    end

    Storage.registry[inst] = nil
    State.registryCount -= 1
    Storage.dirty[inst] = nil
    Storage.candidates[inst] = nil
    State.statsDirty = true

    destroyEntry(inst)
end

local function trackCrystal(inst)
    if Storage.registry[inst] then
        return
    end

    local conns = {}
    Storage.registry[inst] = conns
    State.registryCount += 1
    State.statsDirty = true

    local ok = pcall(function()
        conns[#conns + 1] = inst.Destroying:Connect(function()
            untrackCrystal(inst)
        end)

        conns[#conns + 1] = inst.AncestryChanged:Connect(function()
            if not inst:IsDescendantOf(Services.Workspace) then
                untrackCrystal(inst)
            end
        end)

        for _, name in ipairs(WATCHED_ATTRIBUTES) do
            conns[#conns + 1] = inst:GetAttributeChangedSignal(name):Connect(function()
                markDirty(inst)
            end)
        end

        local label = luckLabel(inst)
        if label then
            conns[#conns + 1] = label:GetPropertyChangedSignal("Text"):Connect(function()
                markDirty(inst)
            end)
        end
    end)

    if not ok then
        untrackCrystal(inst)
        return
    end

    markDirty(inst)
end

local function syncCrystal(inst)
    Storage.dirty[inst] = nil

    if not Storage.registry[inst] then
        return
    end

    if not inst.Parent then
        untrackCrystal(inst)
        return
    end

    local entry = Storage.espCache[inst]
    local hidden = not State.espActive or getAttr(inst, "Collected") == true

    if not hidden then
        hidden = not meetsFilter(inst)
    end

    if hidden then
        if entry then
            destroyEntry(inst, entry)
        end
        return
    end

    if not entry then
        local built, result = pcall(createEntry, inst)
        if not built then
            reportError("billboard", result)
            return
        end

        entry = result
        Storage.espCache[inst] = entry
        State.espCount += 1
        State.statsDirty = true
    end

    local signature = crystalSignature(inst)
    if signature == entry.signature then
        return
    end

    local root = getRoot()
    local ok, err = pcall(applyDetails, inst, entry, root and root.Position or nil)
    if ok then
        entry.signature = signature
    else
        reportError("details", err)
    end
end

local function sweep()
    local seen = Storage.sweepSeen
    table.clear(seen)

    eachContainer(function(container)
        for _, child in ipairs(container:GetChildren()) do
            if not seen[child] and isCrystal(child) then
                seen[child] = true
                if not Storage.registry[child] then
                    trackCrystal(child)
                end
            end
        end
    end)

    local stale
    for inst in pairs(Storage.registry) do
        if not seen[inst] then
            stale = stale or {}
            stale[#stale + 1] = inst
        end
    end

    if stale then
        for _, inst in ipairs(stale) do
            untrackCrystal(inst)
        end
    end
end

local function updateDistances()
    local root = getRoot()
    if not root then
        return
    end

    local origin = root.Position
    if Storage.lastDistanceOrigin and (origin - Storage.lastDistanceOrigin).Magnitude < 1 then
        return
    end

    Storage.lastDistanceOrigin = origin

    for inst, entry in pairs(Storage.espCache) do
        if inst.Parent then
            local text = formatDistance((inst.Position - origin).Magnitude)
            if text ~= entry.distanceText then
                applyExtra(entry, text)
            end
        end
    end
end

local function clearEsp()
    for inst, entry in pairs(Storage.espCache) do
        destroyEntry(inst, entry)
    end
    Storage.espCache = {}
    State.espCount = 0
    State.statsDirty = true
end

local function clearRegistry()
    local all
    for inst in pairs(Storage.registry) do
        all = all or {}
        all[#all + 1] = inst
    end

    if all then
        for _, inst in ipairs(all) do
            untrackCrystal(inst)
        end
    end

    clearEsp()
    Storage.registry = {}
    Storage.candidates = {}
    Storage.dirty = {}
    State.registryCount = 0
    State.statsDirty = true
end

local function requestRefresh()
    for inst in pairs(Storage.registry) do
        Storage.dirty[inst] = true
    end
    State.sweepAccumulator = math.huge
end

local function trackingEnabled()
    return State.espActive
end

local function onContainerChild(child)
    if looksLikeCrystal(child) then
        Storage.candidates[child] = os.clock() + ESP.ttl
    end
end

local function watchContainers()
    for container, connection in pairs(Storage.containerConns) do
        if not container:IsDescendantOf(game) then
            connection:Disconnect()
            Storage.containerConns[container] = nil
        end
    end

    eachContainer(function(container)
        if Storage.containerConns[container] then
            return
        end
        Storage.containerConns[container] = container.ChildAdded:Connect(onContainerChild)
    end)
end

local function unwatchContainers()
    for container, connection in pairs(Storage.containerConns) do
        connection:Disconnect()
        Storage.containerConns[container] = nil
    end
end

local function updateTracking()
    if trackingEnabled() then
        State.sweepAccumulator = math.huge
        watchContainers()
        requestRefresh()
    else
        unwatchContainers()
        clearRegistry()
    end
end

local StatsLabel

Connections.espConn = Services.RunService.Heartbeat:Connect(function(deltaTime)
    if State.statsDirty and StatsLabel then
        State.statsDirty = false
        StatsLabel:SetText(string.format("Tracking: %d  |  Shown: %d", State.registryCount, State.espCount))
    end

    if not trackingEnabled() then
        return
    end

    local now = os.clock()

    for inst, expiry in pairs(Storage.candidates) do
        if not inst.Parent then
            Storage.candidates[inst] = nil
        elseif isCrystal(inst) then
            Storage.candidates[inst] = nil
            trackCrystal(inst)
        elseif now > expiry then
            Storage.candidates[inst] = nil
        end
    end

    local deadline = now + ESP.budget
    if next(Storage.dirty) ~= nil then
        for inst in pairs(Storage.dirty) do
            local ok, err = pcall(syncCrystal, inst)
            if not ok then
                Storage.dirty[inst] = nil
                reportError("sync", err)
            end
            if os.clock() > deadline then
                break
            end
        end
    end

    State.sweepAccumulator += deltaTime
    if State.sweepAccumulator >= ESP.sweep then
        State.sweepAccumulator = 0
        local ok, err = pcall(function()
            watchContainers()
            sweep()
        end)
        if not ok then
            reportError("sweep", err)
        end
    end

    State.distanceAccumulator += deltaTime
    if State.distanceAccumulator >= PACE.distance then
        State.distanceAccumulator = 0
        local ok, err = pcall(updateDistances)
        if not ok then
            reportError("distance", err)
        end
    end
end)

local function destroyPlayerEntry(player)
    local entry = Storage.playerCache[player]
    if not entry then
        return
    end

    if entry.gui then
        entry.gui:Destroy()
    end

    Storage.playerCache[player] = nil
end

local function createPlayerEntry(player)
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "UniversePlayerEsp"
    billboard.AlwaysOnTop = true
    billboard.ResetOnSpawn = false
    billboard.LightInfluence = 0
    billboard.Size = playerGuiSize()
    billboard.StudsOffsetWorldSpace = PLAYER.offset
    billboard.MaxDistance = math.huge
    billboard.Parent = EspHolder

    local textSize = playerTextSize()
    local nameLabel, nameConstraint = newLabel("Name", billboard, 0, 2, COLORS.player, false, textSize)
    local distanceLabel, distanceConstraint = newLabel("Distance", billboard, 1, 2, COLORS.extra, false, textSize)

    nameLabel.Text = player.DisplayName

    return {
        gui = billboard,
        name = nameLabel,
        distance = distanceLabel,
        constraints = { nameConstraint, distanceConstraint },
        nameText = player.DisplayName,
        distanceText = false,
    }
end

local function clearPlayerEsp()
    for player in pairs(Storage.playerCache) do
        destroyPlayerEntry(player)
    end
    Storage.playerCache = {}
end

local function updatePlayerEsp()
    if not State.playerEspActive then
        return
    end

    local root = getRoot()
    local origin = root and root.Position or nil

    for _, player in ipairs(Services.Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local character = player.Character
            local target = character and character:FindFirstChild("HumanoidRootPart")

            if target then
                local entry = Storage.playerCache[player]
                if not entry then
                    local built, result = pcall(createPlayerEntry, player)
                    if built then
                        entry = result
                        Storage.playerCache[player] = entry
                    else
                        reportError("player", result)
                    end
                end

                if entry then
                    if entry.gui.Adornee ~= target then
                        entry.gui.Adornee = target
                    end

                    if entry.nameText ~= player.DisplayName then
                        entry.nameText = player.DisplayName
                        entry.name.Text = player.DisplayName
                    end

                    local text = origin and formatDistance((target.Position - origin).Magnitude) or "--"
                    if text ~= entry.distanceText then
                        entry.distanceText = text
                        entry.distance.Text = text
                    end
                end
            else
                destroyPlayerEntry(player)
            end
        end
    end

    local gone
    for player in pairs(Storage.playerCache) do
        if player == LocalPlayer or not player.Parent then
            gone = gone or {}
            gone[#gone + 1] = player
        end
    end

    if gone then
        for _, player in ipairs(gone) do
            destroyPlayerEntry(player)
        end
    end
end


do
    local function install()
        local CrystalBox = Tabs.crystals:AddLeftGroupbox("Crystal ESP", "gem")

        CrystalBox:AddToggle("CrystalEsp", {
            Text = "Crystal ESP",
            Default = false,
            Callback = function(value)
                State.espActive = value
                if not value then
                    clearEsp()
                end
                updateTracking()
            end,
        })

        CrystalBox:AddSlider("EspSize", {
            Text = "Crystal Size",
            Default = 70,
            Min = 40,
            Max = 250,
            Rounding = 0,
            Suffix = "%",
            Compact = false,
            Callback = function(value)
                State.espScale = value / 100
                applyEspScale()
            end,
        })

        CrystalBox:AddDivider()
        CrystalBox:AddLabel("Min Value hides and skips crystals worth less than this. Example: 500k, 2m, 1.5b. Empty shows everything", true)

        local function setMinValue(text)
            local parsed = parseValue(text)
            if not parsed then
                return
            end
            State.minValue = math.max(parsed, 0)
            State.valueFilter = State.minValue > 0
            requestRefresh()
        end

        CrystalBox:AddInput("EspMinValue", {
            Text = "Min Value",
            Default = Config.MinCrystalValue,
            Placeholder = "2m",
            Numeric = false,
            Finished = false,
            Callback = setMinValue,
        })

        StatsLabel = CrystalBox:AddLabel("Tracking: 0  |  Shown: 0")
    end

    install()
end

do
    local function install()
        local PlayerBox = Tabs.players:AddLeftGroupbox("Player ESP", "users")

        PlayerBox:AddToggle("PlayerEsp", {
            Text = "Player ESP",
            Default = false,
            Callback = function(value)
                State.playerEspActive = value
                if not value then
                    clearPlayerEsp()
                end
            end,
        })

        PlayerBox:AddSlider("PlayerEspSize", {
            Text = "Player Size",
            Default = 60,
            Min = 40,
            Max = 250,
            Rounding = 0,
            Suffix = "%",
            Compact = false,
            Callback = function(value)
                State.playerScale = value / 100
                applyPlayerScale()
            end,
        })
    end

    install()
end



-- === Экспорт модуля ===
E.clearRegistry = clearRegistry
E.clearPlayerEsp = clearPlayerEsp
E.unwatchContainers = unwatchContainers

-- === Регистрация тик-функций для центрального планировщика ===
E.PlayerEspTick = updatePlayerEsp
