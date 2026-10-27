-- ============================================================
-- MaM :: 00_main — ядро скрипта
-- Конфиг, сервисы, общий стейт, окно/вкладки UI, универсальные
-- хелперы (форматтеры, кристаллы, телепорт-ядро), планировщик.
-- Экспортирует всё в getgenv().MaMEnv — таблицу, которую
-- импортируют все остальные модули.
-- ============================================================

getgenv().MaMEnv = getgenv().MaMEnv or {}
local E = getgenv().MaMEnv

local Config = {
    MinCrystalValue = "2m",
    SpeedBoost = 35,
    NormalSpeed = 16,
    FlySpeed = 100,
    AutoRejoinBoulders = false,
    AutoBuyBombs = false,
    RuneGrabRange = 20,
    PickRange = 13,
    PickBurst = 8,
    AutoSellThreshold = 0.5,
    MountainCenter = Vector3.new(42.67, 1066.7, 102.2),
    MountainRadius = 862.7,
    RemotesFolder = "Remotes",
    KeybindMenu = "RightControl",
    KeybindAimTp = "F",
}

if getgenv().UniverseLoaded then
    if getgenv().UniverseUnload then
        pcall(getgenv().UniverseUnload)
    end
end
getgenv().UniverseLoaded = true

local Services = {
    Players = game:GetService("Players"),
    CoreGui = game:GetService("CoreGui"),
    RunService = game:GetService("RunService"),
    Workspace = game:GetService("Workspace"),
    ReplicatedStorage = game:GetService("ReplicatedStorage"),
    UserInputService = game:GetService("UserInputService"),
    HttpService = game:GetService("HttpService"),
    TeleportService = game:GetService("TeleportService"),
    GuiService = game:GetService("GuiService"),
    VirtualUser = game:GetService("VirtualUser"),
}

local LocalPlayer = Services.Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()

local State = {
    afkRunning = true,
    espActive = false,
    playerEspActive = false,
    aimTpEnabled = false,
    speedActive = false,
    autoPickupActive = false,
    instantPromptActive = false,
    autoBuyBombs = false,
    minValue = 2000000,
    valueFilter = true,
    espScale = 0.7,
    playerScale = 0.6,
    boulderScale = 0.6,
    rootPart = nil,
    lastReport = 0,
    tpState = nil,
    sweepAccumulator = math.huge,
    statsDirty = true,
    statsAccumulator = 0,
    distanceAccumulator = math.huge,
    lastPickup = 0,
    lastBagWarn = 0,
    instantAccumulator = math.huge,
    registryCount = 0,
    espCount = 0,
    containerClock = 0,
    streamMark = 0,
    streamSpot = nil,
    speedHooked = nil,
}

local Storage = {
    afkConns = {},
    registry = {},
    candidates = {},
    dirty = {},
    espCache = {},
    containerConns = {},
    playerCache = {},
    containerList = {},
    sweepSeen = {},
    lastDistanceOrigin = nil,
    pendingActions = {},
    promptRestores = {},
    claimed = {},
    promptCache = setmetatable({}, { __mode = "k" }),
    instantPatched = {},
    netConns = {},
}

local Connections = {}

do
    local function silenceIdle()
        local ok, list = pcall(function()
            return getconnections(LocalPlayer.Idled)
        end)
        if not ok or type(list) ~= "table" then
            return
        end
        for _, connection in ipairs(list) do
            pcall(function()
                connection:Disable()
            end)
        end
    end

    local function nudge()
        pcall(function()
            Services.VirtualUser:CaptureController()
            Services.VirtualUser:ClickButton2(Vector3.new())
        end)
    end

    silenceIdle()
    Storage.afkConns[#Storage.afkConns + 1] = LocalPlayer.Idled:Connect(nudge)

    task.spawn(function()
        while State.afkRunning do
            task.wait(60)
            if not State.afkRunning or not LocalPlayer.Parent then
                break
            end
            silenceIdle()
            nudge()
        end
    end)
end

local function resolveGuiRoot()
    local ok, hidden = pcall(function()
        return gethui()
    end)
    if ok and typeof(hidden) == "Instance" then
        return hidden
    end

    local playerGui = LocalPlayer:FindFirstChildOfClass("PlayerGui")
    if playerGui then
        return playerGui
    end

    return LocalPlayer:WaitForChild("PlayerGui", 10) or Services.CoreGui
end

local GuiRoot = resolveGuiRoot()

for _, container in ipairs({ GuiRoot, Services.CoreGui }) do
    for _, name in ipairs({ "UniverseESPGui", "UniverseCrystalEsp" }) do
        pcall(function()
            local existing = container:FindFirstChild(name)
            if existing then
                existing:Destroy()
            end
        end)
    end
end

local function findRemote(name)
    local folder = Services.ReplicatedStorage:FindFirstChild(Config.RemotesFolder) or Services.ReplicatedStorage:WaitForChild(Config.RemotesFolder, 10)
    if not folder then
        return nil
    end
    return folder:FindFirstChild(name) or folder:WaitForChild(name, 5)
end

local Remotes = {
    SellRequest = findRemote("SellRequest"),
    GoHome = findRemote("GoHome"),
    HoldComplete = findRemote("CrystalHoldComplete"),
    ToggleFavorite = findRemote("ToggleFavorite"),
    DigRequest = findRemote("DigRequest"),
    BombShopQuery = findRemote("BombShopQuery"),
    BombBuyRequest = findRemote("BombBuyRequest"),
    BombShopRestocked = findRemote("BombShopRestocked"),
    PlotPlaceRequest = findRemote("PlotPlaceRequest"),
}

local ESP = {
    font = Enum.Font.GothamBold,
    sweep = 0.5,
    budget = 0.005,
    offset = Vector3.new(0, 3, 0),
    width = 250,
    height = 66,
    text = 16,
    ttl = 5,
}

pcall(function()
    ESP.font = Enum.Font.LuckiestGuy
end)

local PLAYER = {
    offset = Vector3.new(0, -8, 0),
    width = 220,
    height = 44,
    text = 15,
}

local PACE = {
    boost = Config.SpeedBoost,
    normal = Config.NormalSpeed,
    stats = 0.25,
    distance = 0.05,
}

local TP = {
    offset = Vector3.new(0, 4.5, 0),
    hold = 0.35,
    clear = {
        Vector3.new(0, 0, 0),
        Vector3.new(0, 3, 0),
        Vector3.new(0, 7, 0),
        Vector3.new(5, 3, 0),
        Vector3.new(-5, 3, 0),
        Vector3.new(0, 3, 5),
        Vector3.new(0, 3, -5),
        Vector3.new(0, 12, 0),
        Vector3.new(9, 6, 0),
        Vector3.new(-9, 6, 0),
        Vector3.new(0, 6, 9),
        Vector3.new(0, 6, -9),
        Vector3.new(0, 20, 0),
    },
}

local PICK = {
    aimRange = 5000,
    aimDot = 0.995,
    range = Config.PickRange,
    cooldown = 0.04,
    restore = 0.2,
    burst = Config.PickBurst,
    retry = 0.15,
    forget = 5,
    pad = 4,
    instantRadius = 60,
    instantTick = 0.25,
}

local COLORS = {
    money = Color3.fromRGB(60, 255, 90),
    default = Color3.fromRGB(0, 225, 255),
    extra = Color3.fromRGB(255, 255, 255),
    player = Color3.fromRGB(255, 40, 140),
    stroke = Color3.fromRGB(0, 0, 0),
    hexDistance = "00E5FF",
    hexLuck = "FFC400",
}

local TIER_NAMES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

local LUCK = {
    rarity = { 1, 1.6, 2.6, 4.2, 7, 12 },
    base = 0.00045,
    exponent = 0.5,
    cap = 500,
    bomb = 3,
    blood = 4,
}

local MUTATION_LUCK = {
    Verdant = 15,
    Voltaic = 20,
    Gilded = 18,
    Onyx = 28,
    Terminus = 40,
    Frost = 1.4,
    Fire = 1.4,
    Thunder = 1.5,
    Starfall = 1.3,
    Aurora = 2.2,
    Radioactive = 2,
    Poison = 1.5,
    Wet = 1,
}

local WATCHED_ATTRIBUTES = {
    "Value",
    "Collected",
    "WeightKg",
    "Tier",
    "TierName",
    "CrystalName",
    "Mutation",
    "ExtraMutations",
}

local SUFFIXES = { "", "k", "M", "B", "T", "Qa" }
local PARSE_MULTIPLIERS = { k = 1e3, m = 1e6, b = 1e9, t = 1e12, qa = 1e15 }
local CONTAINER_NAMES = { "DroppedCrystals", "Crystals" }

local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "Mine a Mountain",
    Footer = "by Skeltx",
    AutoShow = true,
    NotifySide = "Right",
    ShowCustomCursor = false,
})

local Tabs = {
    crystals = Window:AddTab("Crystals", "gem"),
    players = Window:AddTab("Players", "users"),
    boulders = Window:AddTab("Boulders", "mountain"),
    teleports = Window:AddTab("Teleports", "crosshair"),
    farming = Window:AddTab("Farming", "pickaxe"),
    movement = Window:AddTab("Movement", "zap"),
}

local SettingsTab = Window:AddTab("Settings", "sliders-horizontal")

local EspHolder = Instance.new("Folder")
EspHolder.Name = "UniverseCrystalEsp"
EspHolder.Parent = GuiRoot

local function reportError(context, err)
    local now = os.clock()
    if now - State.lastReport < 5 then
        return
    end
    State.lastReport = now
    warn(string.format("[Skeltx] %s: %s", context, tostring(err)))
end

local function formatShort(n, prefix)
    n = tonumber(n) or 0
    prefix = prefix or ""
    local sign = n < 0 and "-" or ""
    n = math.abs(n)
    if n < 1000 then
        return string.format("%s%s%d", sign, prefix, math.floor(n + 0.5))
    end
    local index = 0
    while n >= 1000 and index < #SUFFIXES - 1 do
        n /= 1000
        index += 1
    end
    return string.format("%s%s%.2f%s", sign, prefix, n, SUFFIXES[index + 1])
end

local function formatWeight(kg)
    kg = tonumber(kg) or 0
    if kg >= 1000 then
        return formatShort(kg) .. "kg"
    end
    return string.format("%.1fkg", kg)
end

local function formatDistance(studs)
    studs = tonumber(studs) or 0
    if studs >= 1000 then
        return string.format("%.1fkm", studs / 1000)
    end
    return string.format("%dm", math.floor(studs + 0.5))
end

local function formatLuck(score)
    local pct = (tonumber(score) or 0) * 100
    if pct <= 0 then
        return "+0%"
    end
    if pct < 1 then
        return string.format("+%.2f%%", pct)
    end
    if pct < 10 then
        return string.format("+%.1f%%", pct)
    end
    return string.format("+%.0f%%", pct)
end

local function parseValue(text)
    if type(text) ~= "string" then
        return nil
    end
    local cleaned = text:lower():gsub("[%s,%$_]", "")
    if cleaned == "" then
        return 0
    end
    local number, suffix = cleaned:match("^(%d*%.?%d+)(%a*)$")
    if not number then
        return nil
    end
    local base = tonumber(number)
    if not base then
        return nil
    end
    if suffix == "" then
        return base
    end
    local multiplier = PARSE_MULTIPLIERS[suffix]
    if not multiplier then
        return nil
    end
    return base * multiplier
end

local function bindCharacter(character)
    if not character then
        State.rootPart = nil
        return
    end
    State.rootPart = character:FindFirstChild("HumanoidRootPart")
end

bindCharacter(LocalPlayer.Character)

Connections.characterConn = LocalPlayer.CharacterAdded:Connect(function(character)
    State.rootPart = nil
    State.tpState = nil
    local waiter
    waiter = character.ChildAdded:Connect(function(child)
        if child.Name == "HumanoidRootPart" then
            State.rootPart = child
            waiter:Disconnect()
        end
    end)
    bindCharacter(character)
    if State.rootPart then
        waiter:Disconnect()
    end
end)

local function getRoot()
    if State.rootPart and State.rootPart.Parent then
        return State.rootPart
    end
    bindCharacter(LocalPlayer.Character)
    return State.rootPart
end

local function getAttr(inst, name)
    if not inst then
        return nil
    end
    local ok, value = pcall(inst.GetAttribute, inst, name)
    if ok then
        return value
    end
    return nil
end

local function crystalValue(inst)
    return tonumber(getAttr(inst, "Value")) or 0
end

local function crystalWeight(inst)
    return tonumber(getAttr(inst, "WeightKg")) or 0
end

local function crystalTier(inst)
    return tonumber(getAttr(inst, "Tier")) or 0
end

local function crystalRarity(inst)
    local name = getAttr(inst, "TierName")
    if type(name) == "string" and name ~= "" then
        return name
    end
    return TIER_NAMES[crystalTier(inst)] or "Unknown"
end

local function crystalName(inst)
    local name = getAttr(inst, "CrystalName")
    if type(name) == "string" and name ~= "" then
        return name
    end
    return inst and inst.Name or "Crystal"
end

local function crystalColor(inst)
    local r = tonumber(getAttr(inst, "TierColorR"))
    local g = tonumber(getAttr(inst, "TierColorG"))
    local b = tonumber(getAttr(inst, "TierColorB"))
    if r and g and b then
        return Color3.fromRGB(r, g, b)
    end
    return COLORS.default
end

local function mutationLuck(name)
    if type(name) ~= "string" or name == "" then
        return 1
    end
    return MUTATION_LUCK[name] or 1
end

local function combinedLuckMult(inst)
    local mutation = getAttr(inst, "Mutation")
    local roll = tonumber(getAttr(inst, "MutationLuckRoll"))
    local multiplier = (roll and roll > 0) and roll or mutationLuck(mutation)

    local extra = getAttr(inst, "ExtraMutations")
    if type(extra) == "string" and extra ~= "" then
        for name in string.gmatch(extra, "[^,]+") do
            if name ~= "" then
                multiplier *= mutationLuck(name)
            end
        end
    end

    if getAttr(inst, "IsBloodCrystal") == true then
        multiplier *= LUCK.blood
    end

    if getAttr(inst, "AdminMutation") == "Radioactive" and mutation ~= "Radioactive" then
        local hasRadioactive = type(extra) == "string" and extra:find("Radioactive", 1, true) ~= nil
        if not hasRadioactive then
            multiplier *= mutationLuck("Radioactive")
        end
    end

    return multiplier
end

local function computeLuck(inst)
    local tier = crystalTier(inst)
    if tier <= 0 then
        return 0
    end

    local weight = math.max(0, crystalWeight(inst))
    local base = (LUCK.rarity[tier] or LUCK.rarity[1]) * math.min(weight, LUCK.cap) ^ LUCK.exponent * LUCK.base

    if getAttr(inst, "BombCrystal") == true then
        base *= LUCK.bomb
    end

    return base * combinedLuckMult(inst)
end

local function luckLabel(inst)
    local hover = inst:FindFirstChild("CrystalHover")
    if not hover then
        return nil
    end
    local label = hover:FindFirstChild("LuckBoost")
    if not label or not label:IsA("TextLabel") then
        return nil
    end
    return label
end

local function luckLabelText(inst)
    local label = luckLabel(inst)
    if not label then
        return nil
    end
    return label.Text
end

local function crystalLuck(inst)
    local text = luckLabelText(inst)
    if type(text) == "string" then
        local pct = tonumber(text:match("([%d%.]+)%s*%%"))
        if pct and pct > 0 then
            return pct / 100
        end
    end
    return computeLuck(inst)
end

local function meetsFilter(inst, value)
    if not State.valueFilter then
        return true
    end
    return (value or crystalValue(inst)) >= State.minValue
end

local function ownsGamepass(name)
    local folder = LocalPlayer:FindFirstChild("GamepassesOwned")
    if not folder then
        return false
    end
    local flag = folder:FindFirstChild(name)
    return flag ~= nil and flag:IsA("BoolValue") and flag.Value == true
end

local function realStat(name)
    local data = LocalPlayer:FindFirstChild("PlayerData")
    local stats = data and data:FindFirstChild("RealStats")
    local entry = stats and stats:FindFirstChild(name)
    if not entry then
        return nil
    end
    return tonumber(entry.Value)
end

local function hasActiveRune(keyword)
    local data = LocalPlayer:FindFirstChild("PlayerData")
    local plot = data and data:FindFirstChild("PlotData")
    local runes = plot and plot:FindFirstChild("Runes")
    if not runes then
        return false
    end

    for _, child in ipairs(runes:GetChildren()) do
        local runeName = child:GetAttribute("RuneName")
        if type(runeName) == "string" and runeName:find(keyword, 1, true) then
            if (tonumber(child:GetAttribute("Remaining")) or 0) > 0 then
                return true
            end
        end
    end
    return false
end

local function backpackCapacity()
    if LocalPlayer:GetAttribute("InfBackpack") == true then
        return math.huge
    end

    local base = realStat("CarryWeight") or 10
    if ownsGamepass("CarryKgPlus4") then
        base *= 4
    end

    local total = base + (realStat("CarryWeightBonus") or 0)
    if hasActiveRune("Weight") then
        return total * 2
    end

    return total
end

local function backpackWeight()
    local total = 0

    local function scan(container)
        if not container then
            return
        end
        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") and getAttr(child, "Tier") ~= nil then
                local kg = tonumber(getAttr(child, "WeightKg"))
                if kg then
                    total += kg
                end
            end
        end
    end

    scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
    scan(LocalPlayer.Character)

    return total
end

local function backpackFree()
    local capacity = backpackCapacity()
    if capacity == math.huge then
        return math.huge
    end
    return capacity - backpackWeight()
end

local function looksLikeCrystal(inst)
    if not inst:IsA("BasePart") then
        return false
    end
    return inst.Name:find("Crystal", 1, true) ~= nil
end

local crystalFlags = setmetatable({}, { __mode = "k" })

local function isCrystal(inst)
    local cached = crystalFlags[inst]
    if cached ~= nil then
        return cached
    end

    local result = false
    if inst:IsA("BasePart") and getAttr(inst, "Value") ~= nil then
        result = getAttr(inst, "CrystalName") ~= nil or inst.Name:find("Crystal", 1, true) ~= nil
    end

    crystalFlags[inst] = result
    return result
end

local function rebuildContainers()
    table.clear(Storage.containerList)
    local seen = {}

    local function push(container)
        if not container or seen[container] then
            return
        end
        seen[container] = true
        Storage.containerList[#Storage.containerList + 1] = container
    end

    push(Services.Workspace)
    for _, name in ipairs(CONTAINER_NAMES) do
        push(Services.Workspace:FindFirstChild(name))
    end

    local things = Services.Workspace:FindFirstChild("Things")
    if things then
        for _, name in ipairs(CONTAINER_NAMES) do
            push(things:FindFirstChild(name))
        end
    end
end

local function eachContainer(fn)
    local now = os.clock()
    local stale = #Storage.containerList == 0 or now - State.containerClock >= 1

    if not stale then
        for _, container in ipairs(Storage.containerList) do
            if not container.Parent and container ~= Services.Workspace then
                stale = true
                break
            end
        end
    end

    if stale then
        State.containerClock = now
        rebuildContainers()
    end

    for _, container in ipairs(Storage.containerList) do
        fn(container)
    end
end


local function requestStream(position)
    if typeof(position) ~= "Vector3" then
        return
    end

    local now = os.clock()
    if State.streamSpot and now - State.streamMark < 0.3 and (State.streamSpot - position).Magnitude < 32 then
        return
    end

    State.streamMark = now
    State.streamSpot = position

    task.spawn(function()
        pcall(function()
            LocalPlayer:RequestStreamAroundAsync(position, 1)
        end)
    end)
end

local function applyPivot(cframe)
    local character = LocalPlayer.Character
    if not character then
        return false
    end

    requestStream(cframe.Position)

    local root = getRoot()
    if not root then
        return false
    end

    local moved = pcall(function()
        character:PivotTo(cframe)
    end)

    if not moved then
        moved = pcall(function()
            root.CFrame = cframe
        end)
    end

    if not moved then
        return false
    end

    pcall(function()
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
    end)

    return true
end

local function findClearGoal(position, ignore)
    local params = OverlapParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignore
    params.MaxParts = 1

    for _, offset in ipairs(TP.clear) do
        local candidate = position + offset
        local ok, hits = pcall(function()
            return Services.Workspace:GetPartBoundsInRadius(candidate, 2.5, params)
        end)

        if ok and #hits == 0 then
            return candidate
        end
    end

    return position + TP.clear[#TP.clear]
end

local function finishTeleport()
    if not State.tpState then
        return
    end

    local root = getRoot()
    if root then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end

    local character = LocalPlayer.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function()
            humanoid.PlatformStand = false
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Freefall, true)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, true)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, true)
            humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
        end)
    end

    State.tpState = nil
end

local function teleportTo(target)
    local position
    if typeof(target) == "Vector3" then
        position = target
    elseif typeof(target) == "Instance" and target.Parent then
        position = target.Position
    end

    if not position then
        return false
    end

    local character = LocalPlayer.Character
    if not character then
        return false
    end

    local root = getRoot()
    if not root then
        return false
    end

    finishTeleport()

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        pcall(function()
            if humanoid.SeatPart or humanoid.Sit then
                humanoid.Sit = false
            end
            humanoid:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
            humanoid:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
        end)
    end

    local ignore = { character }
    if typeof(target) == "Instance" then
        ignore[#ignore + 1] = target
    end

    local goalFrame = CFrame.new(findClearGoal(position + TP.offset, ignore))
    if not applyPivot(goalFrame) then
        return false
    end

    State.tpState = {
        goal = goalFrame,
        holdUntil = os.clock() + TP.hold,
    }

    return true
end

local function schedule(delay, fn)
    Storage.pendingActions[#Storage.pendingActions + 1] = { at = os.clock() + delay, fn = fn }
end


-- === Центральный планировщик Heartbeat (перенесён из монолита) ===
-- Каждый модуль регистрирует свои тик-функции через E.* — см. футеры модулей.
Connections.schedulerConn = Services.RunService.Heartbeat:Connect(function(deltaTime)
    if State.tpState then
        local ok, err = pcall(function()
            local fnPivot, fnFinish = E.applyPivot, E.finishTeleport
            if not fnPivot or not fnFinish then
                error("teleport core module not loaded yet")
            end
            if not fnPivot(State.tpState.goal) then
                fnFinish()
                return
            end

            if os.clock() >= State.tpState.holdUntil then
                fnFinish()
            end
        end)

        if not ok then
            if E.finishTeleport then
                pcall(E.finishTeleport)
            end
            reportError("teleport", err)
        end
    end

    if State.autoPickupActive and E.PickupTick then
        local ok, err = pcall(E.PickupTick)
        if not ok then
            reportError("pickup", err)
        end
    end

    if State.instantPromptActive and E.InstantTick then
        State.instantAccumulator += deltaTime
        if State.instantAccumulator >= PICK.instantTick then
            State.instantAccumulator = 0
            local ok, err = pcall(E.InstantTick)
            if not ok then
                reportError("instant", err)
            end
        end
    end

    if State.speedActive and E.MovementTick then
        local ok, err = pcall(E.MovementTick)
        if not ok then
            reportError("speed", err)
        end
    end

    if State.playerEspActive and E.PlayerEspTick then
        local ok, err = pcall(E.PlayerEspTick)
        if not ok then
            reportError("playerEsp", err)
        end
    end

    if E.SlowTick then
        State.statsAccumulator += deltaTime
        if State.statsAccumulator >= PACE.stats then
            State.statsAccumulator = 0
            local ok, err = pcall(E.SlowTick)
            if not ok then
                reportError("backpack", err)
            end
        end
    end

    if #Storage.pendingActions == 0 then
        return
    end

    local now = os.clock()
    for index = #Storage.pendingActions, 1, -1 do
        local job = Storage.pendingActions[index]
        if now >= job.at then
            table.remove(Storage.pendingActions, index)
            local ok, err = pcall(job.fn)
            if not ok then
                reportError("action", err)
            end
        end
    end
end)

-- === Экспорт модуля ===
E.Services = Services
E.LocalPlayer = LocalPlayer
E.Mouse = Mouse
E.Config = Config
E.State = State
E.Storage = Storage
E.Connections = Connections
E.GuiRoot = GuiRoot
E.Remotes = Remotes
E.ESP = ESP
E.PLAYER = PLAYER
E.PACE = PACE
E.TP = TP
E.PICK = PICK
E.COLORS = COLORS
E.TIER_NAMES = TIER_NAMES
E.LUCK = LUCK
E.MUTATION_LUCK = MUTATION_LUCK
E.WATCHED_ATTRIBUTES = WATCHED_ATTRIBUTES
E.SUFFIXES = SUFFIXES
E.PARSE_MULTIPLIERS = PARSE_MULTIPLIERS
E.CONTAINER_NAMES = CONTAINER_NAMES
E.Library = Library
E.SaveManager = SaveManager
E.ThemeManager = ThemeManager
E.Window = Window
E.Tabs = Tabs
E.SettingsTab = SettingsTab
E.EspHolder = EspHolder
E.reportError = reportError
E.formatShort = formatShort
E.formatWeight = formatWeight
E.formatDistance = formatDistance
E.formatLuck = formatLuck
E.parseValue = parseValue
E.bindCharacter = bindCharacter
E.getRoot = getRoot
E.getAttr = getAttr
E.crystalValue = crystalValue
E.crystalWeight = crystalWeight
E.crystalTier = crystalTier
E.crystalRarity = crystalRarity
E.crystalName = crystalName
E.crystalColor = crystalColor
E.mutationLuck = mutationLuck
E.combinedLuckMult = combinedLuckMult
E.computeLuck = computeLuck
E.luckLabel = luckLabel
E.luckLabelText = luckLabelText
E.crystalLuck = crystalLuck
E.meetsFilter = meetsFilter
E.ownsGamepass = ownsGamepass
E.realStat = realStat
E.hasActiveRune = hasActiveRune
E.looksLikeCrystal = looksLikeCrystal
E.backpackCapacity = backpackCapacity
E.backpackWeight = backpackWeight
E.backpackFree = backpackFree
E.isCrystal = isCrystal
E.rebuildContainers = rebuildContainers
E.eachContainer = eachContainer
E.requestStream = requestStream
E.applyPivot = applyPivot
E.findClearGoal = findClearGoal
E.finishTeleport = finishTeleport
E.teleportTo = teleportTo
E.schedule = schedule
