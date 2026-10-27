-- ============================================================
-- MaM :: 20_boulders.lua
-- BOULDERS — движок Mountain (копание валунов), aimTeleport, вкладка Boulders, Boulder Farm
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
local newLabel = E.newLabel

-- Lazy-импорты: имена другого модуля, который грузится ПОЗЖЕ текущего.
local Move = setmetatable({}, { __index = function(_, k) local m = E.Move; return (m and m[k]) or function() end end })
local function crystalPrompt(...) local f = E.crystalPrompt if not f then return nil end return f(...) end
local function firePrompt(...) local f = E.firePrompt if not f then return nil end return f(...) end
local function sortedByScore(...) local f = E.sortedByScore if not f then return nil end return f(...) end

local Mountain = {}

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude
aimParams.IgnoreWater = true

local function getAimedCrystal()
    local unitRay = Mouse.UnitRay
    local origin = unitRay.Origin
    local direction = unitRay.Direction.Unit

    local character = LocalPlayer.Character
    aimParams.FilterDescendantsInstances = character and { character } or {}

    local hit = Services.Workspace:Raycast(origin, direction * PICK.aimRange, aimParams)
    if hit and hit.Instance and (Storage.registry[hit.Instance] or isCrystal(hit.Instance)) then
        return hit.Instance
    end

    local best, bestDot
    local seen = {}

    local function consider(inst)
        if seen[inst] or not inst.Parent then
            return
        end

        seen[inst] = true

        local offset = (inst.Position + ESP.offset) - origin
        local magnitude = offset.Magnitude
        if magnitude > 0 then
            local dot = direction:Dot(offset / magnitude)
            if not bestDot or dot > bestDot then
                bestDot = dot
                best = inst
            end
        end
    end

    for inst in pairs(Storage.espCache) do
        consider(inst)
    end

    eachContainer(function(container)
        for _, child in ipairs(container:GetChildren()) do
            if isCrystal(child) then
                consider(child)
            end
        end
    end)

    if best and bestDot and bestDot >= PICK.aimDot then
        return best
    end
    return nil
end

local function aimTeleport()
    if not State.espActive then
        Library:Notify("Enable Crystal ESP first", 3)
        return
    end

    local inst = getAimedCrystal()
    if not inst then
        Library:Notify("No crystal aimed", 2)
        return
    end

    if teleportTo(inst) then
        Library:Notify(string.format("TP -> %s", crystalName(inst)), 2)
    else
        Library:Notify("Teleport failed", 2)
    end
end

local function tpToRank(scoreFn, rank, formatter)
    local entry = sortedByScore(scoreFn)[rank]
    if not entry or entry.score <= 0 then
        Library:Notify(string.format("No crystal for #%d", rank), 3)
        return
    end

    if teleportTo(entry.inst) then
        Library:Notify(string.format("TP #%d %s (%s)", rank, crystalName(entry.inst), formatter(entry.inst, entry.score)), 3)
    else
        Library:Notify("Teleport failed", 3)
    end
end

local function fireRemote(remote, ...)
    if not remote or typeof(remote) ~= "Instance" then
        return false
    end

    local args = table.pack(...)
    local ok = pcall(function()
        if remote:IsA("RemoteEvent") then
            remote:FireServer(table.unpack(args, 1, args.n))
        elseif remote:IsA("BindableEvent") then
            remote:Fire(table.unpack(args, 1, args.n))
        elseif remote:IsA("RemoteFunction") then
            remote:InvokeServer(table.unpack(args, 1, args.n))
        end
    end)

    return ok
end

local function unfavoriteAll()
    local cleared = 0

    local function scan(container)
        if not container then
            return
        end

        for _, child in ipairs(container:GetChildren()) do
            if child:IsA("Tool") and child:GetAttribute("Favorited") == true then
                pcall(function()
                    child:SetAttribute("Favorited", false)
                end)
                fireRemote(Remotes.ToggleFavorite, child, false)
                cleared += 1
            end
        end
    end

    scan(LocalPlayer:FindFirstChildOfClass("Backpack"))
    scan(LocalPlayer.Character)

    return cleared
end

local function mountainSpot()
    local centerX = Services.Workspace:GetAttribute("MountainCenterX") or Config.MountainCenter.X
    local centerZ = Services.Workspace:GetAttribute("MountainCenterZ") or Config.MountainCenter.Z

    if typeof(centerX) == "number" and typeof(centerZ) == "number" then
        local base = Services.Workspace:GetAttribute("MountainBaseY") or 22
        local peak = Services.Workspace:GetAttribute("MountainPeakY") or 1675
        local height = 700

        if typeof(base) == "number" and typeof(peak) == "number" then
            height = base + (peak - base) * 0.55
        end

        return Vector3.new(centerX, height, centerZ)
    end

    local things = Services.Workspace:FindFirstChild("Things")
    local zones = things and things:FindFirstChild("MountainZones")

    if zones then
        for _, child in ipairs(zones:GetChildren()) do
            if child:IsA("BasePart") and child.Name == "MountainZone" then
                return child.Position
            end
        end
    end

    return Config.MountainCenter
end

local function mountainSpan()
    local radius = Services.Workspace:GetAttribute("MountainRadius")
    if typeof(radius) == "number" and radius > 20 then
        return radius
    end
    return Config.MountainRadius
end

local function getSellCFrame()
    local things = Services.Workspace:FindFirstChild("Things")
    local prox = things and things:FindFirstChild("SellProx")
    if prox and prox:IsA("BasePart") then
        return CFrame.new(prox.Position + Vector3.new(0, 3, 0), prox.Position)
    end
    local model = things and things:FindFirstChild("SellModel")
    local part = model and model:FindFirstChild("SellPart")
    if part and part:IsA("BasePart") then
        return CFrame.new(part.Position + Vector3.new(0, 3, 0), part.Position)
    end
    return CFrame.new(-45.85, 32, 1066.58)
end

local function doRemoteSell()
    local now = os.clock()
    if now - sellClock < 1.5 then
        return false
    end

    sellClock = now
    unfavoriteAll()
    fireRemote(Remotes.SellRequest, "all")
    return true
end

local function doSell()
    local now = os.clock()
    if now - sellClock < 1.5 then
        return false
    end

    sellClock = now
    unfavoriteAll()
    fireRemote(Remotes.GoHome, "sell")

    schedule(0.6, function()
        unfavoriteAll()
        fireRemote(Remotes.SellRequest, "all")
    end)

    return true
end

do
    local function install()
        local BOULDER_INFO = {
            Mossite = { rarity = "Common", pickaxe = "Titanium Spike", crystals = "8-11", runes = "Luck / Haste", color = Color3.fromRGB(150, 220, 120) },
            Voltite = { rarity = "Uncommon", pickaxe = "Celestial Apex", crystals = "10-14", runes = "Storm / Weight", color = Color3.fromRGB(110, 190, 240) },
            Gildrite = { rarity = "Rare", pickaxe = "Eclipse Fang", crystals = "11-15", runes = "Fortune / Detonation", color = Color3.fromRGB(255, 200, 60) },
            Rimeveil = { rarity = "Epic", pickaxe = "Voidreign", crystals = "13-18", runes = "Preservation / Warmth", color = Color3.fromRGB(170, 100, 255) },
            Nocturnite = { rarity = "Legendary", pickaxe = "The Terminus", crystals = "16-22", runes = "Excavator / Colossus", color = Color3.fromRGB(255, 80, 180) },
        }

        local BOULDER_OFFSET = Vector3.new(0, 7, 0)
        local BOULDER_WIDTH = 300
        local BOULDER_HEIGHT = 78
        local BOULDER_STEP = 0.4

        local GRAB_RANGE = Config.RuneGrabRange
        local GRAB_STEP = 0.15
        local GRAB_LIMIT = 4
        local GRAB_RETRY = 0.2

        local boulderEsp = false
        local autoGrab = false
        local boulderCache = {}
        local grabbed = {}
        local boulderClock = 0
        local grabClock = 0

        local scanParams = OverlapParams.new()
        scanParams.FilterType = Enum.RaycastFilterType.Exclude

        local function textSize()
            return math.max(6, math.floor(ESP.text * State.boulderScale + 0.5))
        end

        local function anchorPart(inst)
            if not inst then
                return nil
            end
            if inst:IsA("BasePart") then
                return inst
            end
            if inst:IsA("Model") then
                return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
            end
            return nil
        end

        local function createCard(anchor, offset, colors, width, height)
            local billboard = Instance.new("BillboardGui")
            billboard.Name = "UniverseMountainEsp"
            billboard.Adornee = anchor
            billboard.AlwaysOnTop = true
            billboard.ResetOnSpawn = false
            billboard.LightInfluence = 0
            billboard.Size = UDim2.fromOffset(width * State.boulderScale, height * State.boulderScale)
            billboard.StudsOffsetWorldSpace = offset
            billboard.MaxDistance = math.huge
            billboard.Parent = EspHolder

            local total = #colors
            local size = textSize()
            local labels = {}
            local constraints = {}

            for index, color in ipairs(colors) do
                local label, constraint = newLabel("Line" .. index, billboard, index - 1, total, color, false, size)
                labels[index] = label
                constraints[index] = constraint
            end

            return {
                gui = billboard,
                labels = labels,
                constraints = constraints,
                width = width,
                height = height,
                text = {},
            }
        end

        local function scaleCard(entry)
            entry.gui.Size = UDim2.fromOffset(entry.width * State.boulderScale, entry.height * State.boulderScale)
            local size = textSize()
            for _, constraint in ipairs(entry.constraints) do
                constraint.MaxTextSize = size
            end
        end

        local function setLine(entry, index, text)
            if entry.text[index] == text then
                return
            end
            entry.text[index] = text
            entry.labels[index].Text = text
        end

        local function dropCard(cache, key)
            local entry = cache[key]
            if not entry then
                return
            end
            if entry.gui then
                entry.gui:Destroy()
            end
            cache[key] = nil
        end

        local function clearCache(cache)
            for key in pairs(cache) do
                dropCard(cache, key)
            end
        end

        local function boulderKind(inst)
            if not inst then
                return nil
            end
            for kind in pairs(BOULDER_INFO) do
                if inst.Name:find(kind, 1, true) then
                    return kind
                end
            end
            return nil
        end

        local function boulderRoots()
            local roots = {}
            local decorations = Services.Workspace:FindFirstChild("MountainDecorations")
            local folder = decorations and decorations:FindFirstChild("Boulders")
            if folder then
                roots[#roots + 1] = folder
            end
            local test = Services.Workspace:FindFirstChild("BoulderTest")
            if test then
                roots[#roots + 1] = test
            end
            return roots
        end

        local function eachBoulder(fn)
            for _, container in ipairs(boulderRoots()) do
                for _, child in ipairs(container:GetChildren()) do
                    local kind = boulderKind(child)
                    if kind then
                        fn(child, kind)
                    end
                end
            end
        end

        local function isRune(inst)
            if not inst then
                return false
            end
            if getAttr(inst, "RuneId") ~= nil or getAttr(inst, "IsRune") == true or getAttr(inst, "RuneName") ~= nil then
                return true
            end
            return inst.Name:find(" Rune", 1, true) ~= nil
        end

        local function runeTitle(inst)
            local id = getAttr(inst, "RuneId") or getAttr(inst, "RuneName")
            if type(id) == "string" and id ~= "" then
                if id:find("Rune", 1, true) then
                    return id
                end
                return id .. " Rune"
            end
            return inst and inst.Name or "Rune"
        end

        local function eachRune(origin, radius, fn)
            local seen = {}

            local function offer(owner, part)
                if not owner or seen[owner] then
                    return
                end
                local anchor = part or anchorPart(owner)
                if not anchor or not anchor.Parent then
                    return
                end
                if (anchor.Position - origin).Magnitude > radius then
                    return
                end

                seen[owner] = true
                fn(owner, anchor)
            end

            local function scanFolder(container)
                if not container then
                    return
                end
                for _, child in ipairs(container:GetChildren()) do
                    if isRune(child) then
                        offer(child, anchorPart(child))
                    end
                end
            end

            scanFolder(Services.Workspace)
            scanFolder(Services.Workspace:FindFirstChild("Things"))
            scanFolder(Services.Workspace:FindFirstChild("DroppedCrystals"))

            local character = LocalPlayer.Character
            scanParams.FilterDescendantsInstances = character and { character } or {}

            local ok, parts = pcall(function()
                return Services.Workspace:GetPartBoundsInRadius(origin, radius, scanParams)
            end)

            if not ok or not parts then
                return
            end

            for _, part in ipairs(parts) do
                if isRune(part) then
                    offer(part, part)
                else
                    local parent = part.Parent
                    if parent and parent ~= Services.Workspace and isRune(parent) then
                        offer(parent, anchorPart(parent) or part)
                    end
                end
            end
        end

        local function syncBoulders()
            local root = getRoot()
            local origin = root and root.Position or nil
            local seen = {}

            eachBoulder(function(model, kind)
                local anchor = anchorPart(model)
                if not anchor then
                    return
                end

                seen[model] = true
                local info = BOULDER_INFO[kind]
                local entry = boulderCache[model]

                if entry and not entry.gui.Parent then
                    dropCard(boulderCache, model)
                    entry = nil
                end

                if not entry then
                    entry = createCard(anchor, BOULDER_OFFSET, { info.color, COLORS.extra, COLORS.money }, BOULDER_WIDTH, BOULDER_HEIGHT)
                    boulderCache[model] = entry
                end

                if entry.gui.Adornee ~= anchor then
                    entry.gui.Adornee = anchor
                end

                scaleCard(entry)
                setLine(entry, 1, string.format("[%s] %s", info.rarity, kind))
                setLine(entry, 2, string.format("%s  \u{2022}  %s crystals", info.pickaxe, info.crystals))

                local distance = origin and formatDistance((anchor.Position - origin).Magnitude) or "--"
                setLine(entry, 3, string.format("%s  \u{2022}  %s", info.runes, distance))
            end)

            local stale
            for model in pairs(boulderCache) do
                if not seen[model] then
                    stale = stale or {}
                    stale[#stale + 1] = model
                end
            end

            if stale then
                for _, model in ipairs(stale) do
                    dropCard(boulderCache, model)
                end
            end
        end

        local function grabRunes(radius)
            local root = getRoot()
            if not root then
                return 0
            end

            local now = os.clock()
            local fired = 0

            for prompt, stamp in pairs(grabbed) do
                if now - stamp > 5 or not prompt.Parent then
                    grabbed[prompt] = nil
                end
            end

            eachRune(root.Position, radius or GRAB_RANGE, function(owner, part)
                if fired >= GRAB_LIMIT then
                    return
                end

                local prompt = owner:FindFirstChildOfClass("ProximityPrompt")
                if not prompt then
                    prompt = crystalPrompt(owner)
                end
                if not prompt and part ~= owner then
                    prompt = crystalPrompt(part)
                end

                if not prompt or not prompt.Parent then
                    return
                end

                local last = grabbed[prompt]
                if last and now - last < GRAB_RETRY then
                    return
                end

                grabbed[prompt] = now
                if firePrompt(prompt) then
                    fired += 1
                    Library:Notify(string.format("Rune: %s", runeTitle(owner)), 2)
                end
            end)

            return fired
        end

        function Mountain.applyScale()
            for _, entry in pairs(boulderCache) do
                scaleCard(entry)
            end
        end

        function Mountain.boulderList()
            local list = {}
            for _, kind in ipairs({ "Mossite", "Voltite", "Gildrite", "Rimeveil", "Nocturnite" }) do
                local info = BOULDER_INFO[kind]
                list[#list + 1] = string.format("%s  \u{2022}  %s", kind, info.pickaxe)
            end
            return list
        end

        function Mountain.setBoulderEsp(value)
            boulderEsp = value
            if value then
                boulderClock = math.huge
            else
                clearCache(boulderCache)
            end
        end

        function Mountain.setAutoGrab(value)
            autoGrab = value
            if value then
                grabClock = math.huge
            else
                table.clear(grabbed)
            end
        end

        function Mountain.grabRange()
            return GRAB_RANGE
        end

        function Mountain.grabNear(radius)
            local ok, fired = pcall(grabRunes, radius)
            if not ok then
                reportError("runeGrab", fired)
                return 0
            end
            return fired or 0
        end

        function Mountain.runesNear(radius)
            local root = getRoot()
            if not root then
                return 0
            end
            local count = 0
            eachRune(root.Position, radius or GRAB_RANGE, function()
                count += 1
            end)
            return count
        end

        function Mountain.shutdown()
            boulderEsp = false
            autoGrab = false
            clearCache(boulderCache)
            table.clear(grabbed)
        end

        Connections.mountainConn = Services.RunService.Heartbeat:Connect(function(deltaTime)
            if boulderEsp then
                boulderClock += deltaTime
                if boulderClock >= BOULDER_STEP then
                    boulderClock = 0
                    local ok, err = pcall(syncBoulders)
                    if not ok then
                        reportError("boulder", err)
                    end
                end
            end

            if autoGrab then
                grabClock += deltaTime
                if grabClock >= GRAB_STEP then
                    grabClock = 0
                    local ok, err = pcall(grabRunes)
                    if not ok then
                        reportError("runeGrab", err)
                    end
                end
            end
        end)
    end

    install()
end


do
    local function install()
        local BoulderBox = Tabs.boulders:AddLeftGroupbox("Boulder ESP", "mountain")

        BoulderBox:AddToggle("BoulderEsp", {
            Text = "Boulder ESP",
            Default = false,
            Callback = Mountain.setBoulderEsp,
        })

        BoulderBox:AddSlider("BoulderEspSize", {
            Text = "Boulder Size",
            Default = 60,
            Min = 40,
            Max = 250,
            Rounding = 0,
            Suffix = "%",
            Compact = false,
            Callback = function(value)
                State.boulderScale = value / 100
                Mountain.applyScale()
            end,
        })

        BoulderBox:AddDivider()

        for _, text in ipairs(Mountain.boulderList()) do
            BoulderBox:AddLabel(text, true)
        end
    end

    install()
end


local Farm = {}

do
    local function install()
        -- Пресеты типов валунов убраны: список Targets заполняется автоматически
        -- сканом карты (кнопки Select All / Clear Filter).
        local FARM_KINDS = {}

        local SCAN_SPOTS = {
            CFrame.new(-12.7105675, 459.090942, 818.847412, 0.993408799, -0.00500036497, -0.11451605, 0.000644713698, 0.999275982, -0.0380407833, 0.114623353, 0.0377162211, 0.992692769),
            CFrame.new(13.0506754, 318.450409, -488.078888, -0.99998939, 0.000884758658, -0.00452193478, -0.000498382491, 0.954864502, 0.297041386, 0.00458064489, 0.297040492, -0.954853892),
            CFrame.new(74.3923645, 610.789368, 210.838226, -0.94896102, -0.27110818, 0.161162555, 2.26557495e-06, 0.51098305, 0.859590769, -0.315393418, 0.815718472, -0.484902382),
        }

        local PLACE_ID = game.PlaceId
        local HOLD_DIST = 8
        local SCAN_HOLD = 1.4
        local SWING_GAP = 0.04
        local SWING_BURST = 6
        local SWING_FLOOR = 0.02
        local COOLDOWN_KEYS = { "SwingCooldown", "DigCooldown", "Cooldown", "SwingSpeed", "DigSpeed" }
        local AIM_ANGLES = { 0, 35, -35, 70, -70, 110, -110, 145, -145, 180 }
        local AIM_LIFT = { 0, 5, -4, 12 }
        local SIGHT_GRACE = 1.5
        local SIGHT_STEPS = 8
        local LOST_GRACE = 1.8
        local DRY_ROUNDS = 3
        local DRY_TIME = 1.0
        local PROBE_DIST = { 0, -3, 4, -5, 8 }
        local CENTER_STEP = 0.75
        local CENTER_SHIFT = 7
        local SPOT_HOLD = 5.0
        local SPOT_SLACK = 12
        local ARRIVE_DIST = 3.5
        local STUCK_TIME = 4.0
        local DRY_SWAP = 4.0
        local SKIP_TIME = 9.0
        local SWEEP_PARTS = 3
        local RUNE_SWEEP = 90
        local LOOT_TIME = 2.5
        local EQUIP_STEP = 0.5
        local RESET_WAIT = 1.5

        local PICK_NAMES = {
            ["Rusty Scrapper"] = true, ["Weathered Wood"] = true, ["Chipped Stone"] = true,
            ["Hardened Iron"] = true, ["Copper Pick"] = true, ["Reinforced Steel"] = true,
            ["Titanium Spike"] = true, ["Frostbite Pick"] = true, ["Emerald Carver"] = true,
            ["Volcano Basalt"] = true, ["Obsidian Edge"] = true, ["Tempest Pick"] = true,
            ["Celestial Apex"] = true, ["Astral Rend"] = true, ["Eclipse Fang"] = true,
            ["Nebular Throne"] = true, Voidreign = true, Singularity = true,
            ["The Terminus"] = true, ["Admin Pickaxe"] = true, ["Shark Pickaxe"] = true,
            ["Diamond Pickaxe"] = true,
        }

        local active = false
        local autoRejoin = Config.AutoRejoinBoulders
        local targets = {}
        local phase = "idle"
        local target, anchor
        local swingClock = 0
        local equipClock = 0
        local waitUntil = 0
        local lastSpot
        local hpMark
        local dryRounds = 0
        local scanned = false
        local scanIndex = 0
        local heldPick
        local spotFrame
        local aimTurn = 0
        local blindClock = 0
        local lostClock = 0
        local dryClock = 0
        local probeIndex = 0
        local partCursor = 0
        local pendingFinish = false
        local lootUntil = 0
        local statusText = "Idle"
        local scanRetries = 0
        local lastPos
        local stuckClock = 0
        local lockedCenter
        local spotCenter
        local centerClock = 0
        local spotClock = 0

        local function toggleValue(name)
            local store = Library and Library.Toggles
            local entry = store and store[name]
            if entry and type(entry.Value) == "boolean" then
                return entry.Value
            end
            return false
        end

        local function isPickaxe(tool)
            if not tool or not tool:IsA("Tool") then
                return false
            end
            if getAttr(tool, "IsPickaxe") == true then
                return true
            end
            if PICK_NAMES[tool.Name] then
                return true
            end
            return getAttr(tool, "DigPower") ~= nil and getAttr(tool, "Tier") == nil
        end

        local function pickScore(tool)
            if not isPickaxe(tool) then
                return 0
            end
            local score = 1
            local power = tonumber(getAttr(tool, "DigPower"))
            if power then
                score += power
            end
            return score
        end

        local function equipPick()
            local character = LocalPlayer.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if not character or not humanoid then
                return nil
            end

            local held = character:FindFirstChildOfClass("Tool")
            if held and isPickaxe(held) then
                return held
            end

            local choice
            local best = 0

            local function consider(tool)
                local score = pickScore(tool)
                if score > best then
                    best = score
                    choice = tool
                end
            end

            consider(held)
            local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
            if backpack then
                for _, tool in ipairs(backpack:GetChildren()) do
                    consider(tool)
                end
            end

            if not choice then
                if backpack then
                    for _, tool in ipairs(backpack:GetChildren()) do
                        if tool:IsA("Tool") then
                            choice = tool
                            break
                        end
                    end
                end
            end

            if not choice then
                return nil
            end
            if choice == held then
                return held
            end

            pcall(function()
                humanoid:EquipTool(choice)
            end)

            local now = character:FindFirstChildOfClass("Tool")
            if now then
                return now
            end

            return choice
        end

        local rayParams = RaycastParams.new()
        rayParams.FilterType = Enum.RaycastFilterType.Exclude
        rayParams.IgnoreWater = true
        rayParams.RespectCanCollide = false

        local JUNK_WORDS = { "vfx", "effect", "fx", "debris", "particle", "shard", "chunk", "dust", "smoke" }

        local function junkName(instance)
            local name = string.lower(instance.Name)
            for _, word in ipairs(JUNK_WORDS) do
                if string.find(name, word, 1, true) then
                    return true
                end
            end
            return false
        end

        local function ignorable(instance, model)
            if not instance then
                return true
            end
            if model and instance:IsDescendantOf(model) then
                return true
            end
            if instance:IsA("Terrain") then
                return true
            end
            if not instance:IsA("BasePart") then
                return true
            end
            if instance.Transparency >= 0.5 or not instance.CanCollide or not instance.CanQuery then
                return true
            end
            if not instance.Anchored or instance.Massless then
                return true
            end
            if junkName(instance) then
                return true
            end

            local owner = instance:FindFirstAncestorOfClass("Model")
            if owner and Services.Players:GetPlayerFromCharacter(owner) then
                return true
            end
            return false
        end

        local function sightClear(origin, part, model)
            if not part or not part.Parent then
                return true
            end

            local delta = part.Position - origin
            local distance = delta.Magnitude
            if distance < 1 then
                return true
            end

            local skip = { LocalPlayer.Character, Services.Workspace.Terrain }

            for _ = 1, SIGHT_STEPS do
                rayParams.FilterDescendantsInstances = skip
                local hit = Services.Workspace:Raycast(origin, delta.Unit * (distance + 2), rayParams)
                if not hit then
                    return true
                end

                local instance = hit.Instance
                if instance == part or (model and instance:IsDescendantOf(model)) then
                    return true
                end

                if not ignorable(instance, model) then
                    return false
                end

                skip[#skip + 1] = instance
            end

            return true
        end

        local function usablePart(item)
            if not item:IsA("BasePart") then
                return false
            end
            if not item.Anchored or item.Transparency >= 0.9 or item.Massless then
                return false
            end
            return not junkName(item)
        end

        local function partList(model)
            local list = {}
            if not model then
                return list
            end

            if model:IsA("BasePart") then
                list[1] = model
                return list
            end

            local spare = {}
            for _, item in ipairs(model:GetDescendants()) do
                if item:IsA("BasePart") then
                    if usablePart(item) then
                        list[#list + 1] = item
                    else
                        spare[#spare + 1] = item
                    end
                end
            end

            if #list > 0 then
                return list
            end
            return spare
        end

        local function anchorSpot(model, part)
            if part and part.Parent then
                return part.Position
            end
            if not model or not model.Parent then
                return nil
            end
            local ok, pivot = pcall(model.GetPivot, model)
            if ok and pivot then
                return pivot.Position
            end
            return nil
        end

        local function coreSpot(model)
            if not model or not model.Parent then
                return nil
            end
            if model:IsA("BasePart") then
                return model.Position
            end
            local boxed, box = pcall(model.GetBoundingBox, model)
            if boxed and box then
                return box.Position
            end
            local ok, pivot = pcall(model.GetPivot, model)
            if ok and pivot then
                return pivot.Position
            end
            return nil
        end

        local function coreFrame(core, part)
            local look = part and part.Parent and part.Position or nil
            if not look or (look - core).Magnitude < 1 then
                look = core + Vector3.new(0, -2, 0)
            end
            return CFrame.new(core, look)
        end

        local function visibleAnchor(model)
            if not model then
                return nil
            end

            local root = getRoot()
            local origin = root and root.Position
            local pick, pickDistance, fallback, fallbackDistance

            for _, part in ipairs(partList(model)) do
                local distance = origin and (part.Position - origin).Magnitude or 0
                if not fallback or distance < fallbackDistance then
                    fallback = part
                    fallbackDistance = distance
                end

                if origin and sightClear(origin, part, model) then
                    if not pick or distance < pickDistance then
                        pick = part
                        pickDistance = distance
                    end
                end
            end

            return pick or fallback
        end

        local function freshAnchor(model)
            local list = partList(model)
            local count = #list
            if count == 0 then
                return nil
            end

            for _ = 1, count do
                partCursor = partCursor % count + 1
                local item = list[partCursor]
                if item and item.Parent then
                    return item
                end
            end
            return nil
        end

        local function hitSpot(part, model)
            local root = getRoot()
            if not root then
                return part.Position
            end

            local origin = root.Position
            local delta = part.Position - origin
            local distance = delta.Magnitude
            if distance < 1 then
                return part.Position
            end

            local skip = { LocalPlayer.Character, Services.Workspace.Terrain }

            for _ = 1, SIGHT_STEPS do
                rayParams.FilterDescendantsInstances = skip
                local hit = Services.Workspace:Raycast(origin, delta.Unit * (distance + 2), rayParams)
                if not hit then
                    break
                end

                if hit.Instance == part or hit.Instance:IsDescendantOf(model) then
                    return hit.Position
                end

                skip[#skip + 1] = hit.Instance
            end

            return part.Position
        end

        local function swingGap(tool)
            local pick = tool or heldPick
            if pick then
                for _, key in ipairs(COOLDOWN_KEYS) do
                    local value = tonumber(getAttr(pick, key))
                    if value and value > 0 then
                        return math.clamp(value, SWING_FLOOR, 0.5)
                    end
                end
            end
            return SWING_GAP
        end

        local function swing(part, model, center)
            local event = Remotes.DigRequest
            if not event or not heldPick then
                return false
            end

            local name = heldPick.Name
            local core = center or (part and part.Parent and part.Position)
            local spot = core

            if part and part.Parent then
                spot = hitSpot(part, model) or core
            end

            if not spot and not core then
                return false
            end

            spot = spot or core
            core = core or spot

            local sweepList = {}
            if model and model.Parent then
                local list = partList(model)
                local count = #list

                if count > 0 then
                    for _ = 1, math.min(SWEEP_PARTS, count) do
                        partCursor = partCursor % count + 1
                        local item = list[partCursor]
                        if item and item.Parent then
                            sweepList[#sweepList + 1] = item.Position
                        end
                    end
                end
            end

            return pcall(function()
                for index = 1, SWING_BURST do
                    if index % 2 == 0 then
                        fireRemote(event, name, core)
                    else
                        fireRemote(event, name, spot)
                    end
                end

                for _, point in ipairs(sweepList) do
                    fireRemote(event, name, point)
                end
            end)
        end

        local function hold(goal, aim)
            return Move.glide(goal, aim)
        end

        local function restart()
            task.spawn(function()
                pcall(function()
                    LocalPlayer:Kick("Universe: restarting server")
                end)

                for _ = 1, 20 do
                    task.wait(1.5)
                    local sent = pcall(function()
                        Services.TeleportService:Teleport(PLACE_ID, LocalPlayer)
                    end)

                    if not sent then
                        pcall(function()
                            Services.TeleportService:TeleportToPlaceInstance(PLACE_ID, game.JobId, LocalPlayer)
                        end)
                    end
                end
            end)
        end

        local function boulderRoots()
            local roots = {}
            local decorations = Services.Workspace:FindFirstChild("MountainDecorations")
            local folder = decorations and decorations:FindFirstChild("Boulders")
            if folder then
                roots[#roots + 1] = folder
            end
            local test = Services.Workspace:FindFirstChild("BoulderTest")
            if test then
                roots[#roots + 1] = test
            end
            return roots
        end

        local function boulderKind(inst)
            if not inst then
                return nil
            end
            local attrName = getAttr(inst, "BoulderName")
            local str = tostring(attrName or inst.Name)
            for _, kind in ipairs(FARM_KINDS) do
                if str:find(kind, 1, true) then
                    return kind
                end
            end
            -- неизвестный игре тип: имя модели само становится "типом" — так фармятся
            -- любые новые валуны, добавленные разработчиком, без правки FARM_KINDS
            if str ~= "" then
                return str
            end
            return nil
        end

        local function anchorOf(model)
            if not model then
                return nil
            end
            if model:IsA("BasePart") then
                return model
            end

            local list = partList(model)
            if list[1] then
                return list[1]
            end

            local ok, part = pcall(model.FindFirstChildWhichIsA, model, "BasePart", true)
            if ok and part then
                return part
            end
            return nil
        end

        local function boulderHealth(model)
            if not model then
                return nil
            end
            local hp = getAttr(model, "HP")
            if hp == nil then
                hp = getAttr(model, "Health")
            end
            if hp == nil then
                hp = getAttr(model, "Hp")
            end
            if hp == nil then
                hp = getAttr(model, "CurrentHealth")
            end
            return tonumber(hp)
        end

        local blacklistedBoulders = {}
        local lastDamageClock = 0

        local function swingGap(tool)
            local pick = tool or heldPick
            if pick then
                for _, key in ipairs(COOLDOWN_KEYS) do
                    local value = tonumber(getAttr(pick, key))
                    if value and value > 0 then
                        return math.clamp(value, SWING_FLOOR, 0.5)
                    end
                end
            end
            return SWING_GAP
        end

        local function pickTarget()
            local root = getRoot()
            if not root then
                return nil
            end

            local now = os.clock()
            for b, expire in pairs(blacklistedBoulders) do
                if now > expire or not b.Parent then
                    blacklistedBoulders[b] = nil
                end
            end

            local best, bestAnchor, bestScore

            for _, container in ipairs(boulderRoots()) do
                for _, child in ipairs(container:GetChildren()) do
                    if not blacklistedBoulders[child] then
                        local kind = boulderKind(child)
                        if kind and targets[kind] then
                            local part = anchorOf(child)
                            if part then
                                local distance = (part.Position - root.Position).Magnitude
                                local hp = boulderHealth(child) or 0
                                if hp >= 0 then
                                    local priority = 10
                                    for idx, k in ipairs(FARM_KINDS) do
                                        if k == kind then
                                            priority = idx
                                            break
                                        end
                                    end

                                    local score = priority * 1000 + distance

                                    if not best or score < bestScore then
                                        best = child
                                        bestAnchor = part
                                        bestScore = score
                                    end
                                end
                            end
                        end
                    end
                end
            end

            return best, bestAnchor
        end

        local function approach(part, model, turn, spot, pad)
            local root = getRoot()
            if not root then
                return nil
            end

            local center = spot or (part and part.Parent and part.Position)
            if not center then
                return nil
            end

            local away = root.Position - center
            away = Vector3.new(away.X, 0, away.Z)

            if away.Magnitude < 0.5 then
                away = Vector3.new(0, 0, 1)
            end
            away = away.Unit

            local modelSize
            if model and model:IsA("Model") then
                local ok, ext = pcall(model.GetExtentsSize, model)
                if ok and ext then
                    modelSize = ext
                end
            end
            if not modelSize and part and part.Parent then
                modelSize = part.Size
            end
            modelSize = modelSize or Vector3.new(12, 12, 12)

            local outerRadius = math.max(modelSize.X, modelSize.Z) * 0.5
            local reach = math.max(outerRadius + 6.5 + (pad or 0), 8.5)
            local skip = turn or 0

            for _, lift in ipairs(AIM_LIFT) do
                for _, angle in ipairs(AIM_ANGLES) do
                    local dir = (CFrame.fromAxisAngle(Vector3.yAxis, math.rad(angle)) * away).Unit
                    local candidate = center + dir * reach + Vector3.new(0, lift, 0)

                    if sightClear(candidate, part, model) then
                        if skip <= 0 then
                            return CFrame.new(candidate, center)
                        end
                        skip -= 1
                    end
                end
            end

            return CFrame.new(center + away * reach + Vector3.new(0, AIM_LIFT[2], 0), center)
        end

        local function beginLoot(finish)
            pendingFinish = finish == true
            lootUntil = os.clock() + LOOT_TIME
            phase = "loot"
            statusText = "Looting runes"
        end

        local function stop()
            active = false
            phase = "idle"
            target = nil
            anchor = nil
            waitUntil = 0
            Move.glideStop()
            hpMark = nil
            dryRounds = 0
            pendingFinish = false
            lootUntil = 0
            spotFrame = nil
            aimTurn = 0
            blindClock = 0
            lostClock = 0
            dryClock = 0
            probeIndex = 0
            scanRetries = 0
            stuckClock = 0
            lastPos = nil
            lastDamageClock = 0
            lockedCenter = nil
            spotCenter = nil
            centerClock = 0
            spotClock = 0
            table.clear(blacklistedBoulders)
            statusText = "Idle"

            Move.setFly(toggleValue("Fly"))
            Move.setNoclip(toggleValue("Noclip"))
            Mountain.setAutoGrab(toggleValue("AutoRunePickup"))
        end

        local function step(deltaTime)
            local root = getRoot()
            if not root then
                statusText = "Waiting for character"
                return
            end

            local now = os.clock()

            local travelling = spotFrame ~= nil and (root.Position - spotFrame.Position).Magnitude > ARRIVE_DIST

            if travelling and lastPos and (root.Position - lastPos).Magnitude < 0.5 then
                stuckClock += deltaTime
                if stuckClock >= STUCK_TIME then
                    stuckClock = 0
                    spotFrame = nil
                    aimTurn = (aimTurn + 1) % #AIM_ANGLES
                    probeIndex += 1
                end
            else
                stuckClock = 0
                lastPos = root.Position
            end

            if phase == "scan" then
                if not scanned then
                    if scanIndex == 0 then
                        scanIndex = 1
                        waitUntil = now + SCAN_HOLD
                    end

                    if scanIndex <= #SCAN_SPOTS then
                        hold(SCAN_SPOTS[scanIndex])
                        statusText = string.format("Scanning %d/%d", scanIndex, #SCAN_SPOTS)

                        if now >= waitUntil then
                            scanIndex += 1
                            waitUntil = now + SCAN_HOLD
                        end

                        return
                    end

                    scanned = true
                end

                local model = pickTarget()
                if not model then
                    scanRetries += 1
                    if scanRetries <= 3 then
                        statusText = "Waiting for boulders..."
                        waitUntil = now + 1.5
                        return
                    end

                    scanRetries = 0
                    beginLoot(true)
                    statusText = "Final rune sweep"
                    return
                end

                scanRetries = 0
                target = model
                anchor = visibleAnchor(model) or anchorOf(model)
                spotFrame = nil
                spotCenter = nil
                lockedCenter = nil
                centerClock = 0
                spotClock = 0
                aimTurn = 0
                blindClock = 0
                lostClock = 0
                dryClock = 0
                probeIndex = 0
                hpMark = nil
                dryRounds = 0
                lastDamageClock = now
                phase = "mine"
                return
            end

            if phase == "mine" then
                if not target or not target.Parent then
                    lastSpot = root.CFrame
                    beginLoot(false)
                    return
                end

                local kind = boulderKind(target) or "Boulder"
                local hp = boulderHealth(target)

                if hp and hp <= 0 then
                    lastSpot = root.CFrame
                    beginLoot(false)
                    return
                end

                if not anchor or not anchor.Parent or not anchor:IsDescendantOf(target) then
                    anchor = visibleAnchor(target) or anchorOf(target)
                end

                centerClock += deltaTime
                local center = lockedCenter

                if not center or centerClock >= CENTER_STEP then
                    centerClock = 0
                    local fresh = coreSpot(target) or anchorSpot(target, anchor)
                    if fresh and (not center or (fresh - center).Magnitude >= CENTER_SHIFT) then
                        center = fresh
                        lockedCenter = fresh
                    end
                end

                if not center then
                    lostClock += deltaTime
                    if lostClock >= LOST_GRACE then
                        lastSpot = root.CFrame
                        beginLoot(false)
                        return
                    end
                    statusText = string.format("Holding %s", kind)
                    return
                end

                lostClock = 0
                spotClock += deltaTime

                if spotFrame and spotCenter and (spotCenter - center).Magnitude > SPOT_SLACK then
                    spotFrame = nil
                end

                if not spotFrame then
                    spotFrame = approach(anchor, target, aimTurn, center, PROBE_DIST[probeIndex % #PROBE_DIST + 1])
                    spotCenter = center
                    spotClock = 0
                end

                if spotFrame then
                    Move.setNoclip(true)
                    hold(spotFrame, center)
                end

                if heldPick == nil or heldPick.Parent ~= LocalPlayer.Character then
                    equipClock = 0
                    heldPick = equipPick()
                else
                    equipClock += deltaTime
                    if equipClock >= EQUIP_STEP then
                        equipClock = 0
                        heldPick = equipPick() or heldPick
                    end
                end

                if not heldPick then
                    statusText = "Equipping pickaxe..."
                    return
                end

                swingClock += deltaTime
                local gap = swingGap()
                local swung = 0

                if swingClock >= gap then
                    swung = math.min(math.floor(swingClock / gap), 4)
                    swingClock -= swung * gap

                    for _ = 1, swung do
                        swing(anchor, target, center)
                    end
                end

                if hp then
                    if hpMark == nil or hp < (hpMark - 0.001) then
                        hpMark = hp
                        dryRounds = 0
                        dryClock = 0
                        blindClock = 0
                        lastDamageClock = now
                    else
                        dryClock += deltaTime
                        dryRounds += swung

                        if dryClock >= DRY_SWAP then
                            dryClock = 0
                            dryRounds = 0
                            anchor = freshAnchor(target) or visibleAnchor(target) or anchor
                            if spotClock >= SPOT_HOLD then
                                aimTurn = (aimTurn + 1) % #AIM_ANGLES
                                probeIndex += 1
                                spotFrame = nil
                            end
                        end
                    end

                    if now - lastDamageClock >= SKIP_TIME then
                        blacklistedBoulders[target] = now + 15
                        target = nil
                        anchor = nil
                        spotFrame = nil
                        phase = "scan"
                        statusText = "Skipping unhittable boulder"
                        return
                    end

                    statusText = string.format("Mining %s  %.0f hp", kind, hp)
                    return
                end

                if sightClear(root.Position, anchor, target) then
                    blindClock = 0
                else
                    blindClock += deltaTime
                    if blindClock >= SIGHT_GRACE then
                        blindClock = 0
                        anchor = visibleAnchor(target) or anchor
                        if spotClock >= SPOT_HOLD then
                            aimTurn = (aimTurn + 1) % #AIM_ANGLES
                            spotFrame = nil
                        end
                    end
                end

                statusText = string.format("Mining %s", kind)
                return
            end

            if phase == "loot" then
                if lastSpot then
                    hold(lastSpot)
                end

                Mountain.grabNear(RUNE_SWEEP)

                if now < lootUntil then
                    statusText = string.format("Looting runes  %.1fs", lootUntil - now)
                    return
                end

                if pendingFinish then
                    phase = "reset"
                    waitUntil = now + RESET_WAIT
                    statusText = "Runes collected"
                else
                    target = nil
                    anchor = nil
                    phase = "scan"
                    statusText = "Next boulder"
                end

                return
            end

            if phase == "reset" then
                if now < waitUntil then
                    return
                end

                if autoRejoin then
                    statusText = "Restarting server"
                    Library:Notify("No boulders left - rejoining", 3)
                    stop()
                    restart()
                else
                    statusText = "Re-scanning mountain..."
                    Library:Notify("No boulders left - re-scanning in 4s", 3)
                    target = nil
                    anchor = nil
                    scanned = false
                    scanIndex = 0
                    phase = "scan"
                    waitUntil = now + 4.0
                end
            end
        end

        -- Скан всех валунов на карте: уникальные типы для списка Targets/ESP
        local function scanBoulderKinds()
            local found, list = {}, {}
            for _, container in ipairs(boulderRoots()) do
                for _, child in ipairs(container:GetChildren()) do
                    local attrName = getAttr(child, "BoulderName")
                    local str = tostring(attrName or child.Name)
                    if str ~= "" and not found[str] then
                        found[str] = true
                        list[#list + 1] = str
                    end
                end
            end
            table.sort(list)
            return list
        end

        local function setTargets(value)
            table.clear(targets)
            if type(value) == "table" then
                for key, flag in pairs(value) do
                    if type(key) == "string" and flag == true then
                        targets[key] = true
                    elseif type(flag) == "string" then
                        targets[flag] = true
                    end
                end
            elseif type(value) == "string" then
                targets[value] = true
            end
        end

        local function setActive(value)
            if not value then
                stop()
                return
            end

            if not next(targets) then
                Library:Notify("Pick at least one boulder", 2)
                local store = Library and Library.Toggles
                local entry = store and store.AutoFarmBoulders
                if entry and entry.SetValue then
                    entry:SetValue(false)
                end
                return
            end

            active = true
            phase = "scan"
            waitUntil = 0
            target = nil
            anchor = nil
            lastSpot = nil
            swingClock = 0
            equipClock = 0
            hpMark = nil
            dryRounds = 0
            spotFrame = nil
            aimTurn = 0
            blindClock = 0
            lostClock = 0
            dryClock = 0
            probeIndex = 0
            scanned = false
            scanIndex = 0
            heldPick = nil
            pendingFinish = false
            lootUntil = 0
            scanRetries = 0
            stuckClock = 0
            lastPos = nil
            lockedCenter = nil
            spotCenter = nil
            centerClock = 0
            spotClock = 0
            statusText = "Starting"

            Move.setFly(false)
            Move.setNoclip(true)
            Mountain.setAutoGrab(true)
        end

        local FarmBox = Tabs.boulders:AddRightGroupbox("Boulder Farm", "bot")
        FarmBox:AddLabel("Specialized in rune farming", true)
        FarmBox:AddDivider()

        FarmBox:AddDropdown("FarmTargets", {
            Text = "Targets",
            Values = FARM_KINDS,
            Multi = true,
            AllowNull = true,
            Callback = setTargets,
        })

        -- Сканирует валуны, реально присутствующие на карте, и обновляет список Targets.
        FarmBox:AddButton("Select All", function()
            local present = scanBoulderKinds()
            local values, seen = {}, {}
            for _, kind in ipairs(FARM_KINDS) do
                values[#values + 1] = kind
                seen[kind] = true
            end
            for _, kind in ipairs(present) do
                if not seen[kind] then
                    values[#values + 1] = kind
                    seen[kind] = true
                end
            end
            local all = {}
            for _, kind in ipairs(values) do
                all[kind] = true
            end
            local dd = Library.Options and Library.Options.FarmTargets
            if dd then
                pcall(function() dd:SetValues(values) end)
                pcall(function() dd:SetValue(all) end)
            end
            setTargets(all)
            Library:Notify(string.format("Boulders на карте: %d типов (выбраны все)", #values), 3)
        end)

        FarmBox:AddButton("Clear Filter", function()
            local present = scanBoulderKinds()
            local values, seen = {}, {}
            for _, kind in ipairs(FARM_KINDS) do
                values[#values + 1] = kind
                seen[kind] = true
            end
            for _, kind in ipairs(present) do
                if not seen[kind] then
                    values[#values + 1] = kind
                    seen[kind] = true
                end
            end
            local dd = Library.Options and Library.Options.FarmTargets
            if dd then
                pcall(function() dd:SetValues(values) end)
                pcall(function() dd:SetValue({}) end)
                pcall(function() dd:SetValue(nil) end)
            end
            setTargets(nil)
            Library:Notify(string.format("Boulders на карте: %d типов (фильтр сброшен)", #values), 3)
        end)

        FarmBox:AddToggle("AutoFarmBoulders", {
            Text = "Auto Farm",
            Default = false,
            Callback = setActive,
        })

        FarmBox:AddToggle("AutoRejoinBoulders", {
            Text = "Auto Rejoin On Finish",
            Default = Config.AutoRejoinBoulders,
            Callback = function(value)
                autoRejoin = value
            end,
        })

        FarmBox:AddDivider()

        local StatusLabel = FarmBox:AddLabel("Idle", true)
        local labelClock = 0

        Connections.farmConn = Services.RunService.Heartbeat:Connect(function(deltaTime)
            if active then
                local ok, err = pcall(step, deltaTime)
                if not ok then
                    reportError("boulderFarm", err)
                end
            end

            labelClock += deltaTime
            if labelClock >= 0.25 then
                labelClock = 0
                StatusLabel:SetText(statusText)
            end
        end)

        Farm.stop = stop
        Farm.equipPick = equipPick
        Farm.swingGap = swingGap
    end

    install()
end



-- === Экспорт модуля ===
E.Mountain = Mountain
E.Farm = Farm
E.aimTeleport = aimTeleport
E.tpToRank = tpToRank
E.fireRemote = fireRemote
E.unfavoriteAll = unfavoriteAll
E.mountainSpot = mountainSpot
E.mountainSpan = mountainSpan
E.getSellCFrame = getSellCFrame
