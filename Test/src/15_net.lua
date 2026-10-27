-- ============================================================
-- MaM :: 15_net.lua
-- NET — серверный хоп/тёплый пул серверов, авто-rejoin
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

local Net = {}

do
    local function install()
        local PLACE = game.PlaceId
        local PAGES = 1
        local POOL_TARGET = 20
        local RETRY_STEP = 1.5
        local RETRY_LIMIT = 10
        local BACK_DELAY = 3
        local REFILL_MARK = 8
        local WARM_STEP = 30

        local visited = {}
        local pool = {}
        local hopping = false
        local reviving = false
        local lastCode = 0
        local alive = true

        local function note(text)
            if Library and Library.Notify then
                pcall(function()
                    Library:Notify("Hop  " .. text, 4)
                end)
            end
        end

        local function grab(link)
            local sender = (syn and syn.request) or (http and http.request) or http_request or request
            if type(sender) == "function" then
                local ok, response = pcall(function()
                    return sender({ Url = link, Method = "GET" })
                end)

                if ok and type(response) == "table" then
                    local code = tonumber(response.StatusCode) or 0
                    if code >= 200 and code < 300 and type(response.Body) == "string" then
                        return response.Body, code
                    end
                    return nil, code
                end
            end

            local ok, body = pcall(function()
                return game:HttpGet(link)
            end)

            if ok and type(body) == "string" then
                return body, 200
            end

            return nil, 0
        end

        local function fetch(cursor)
            local link = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&excludeFullGames=true&limit=100", PLACE)
            if type(cursor) == "string" and cursor ~= "" then
                link ..= "&cursor=" .. cursor
            end

            local body, code = grab(link)
            if type(body) ~= "string" then
                lastCode = code or 0
                return nil, nil
            end

            lastCode = 200
            local parsed, data = pcall(function()
                return Services.HttpService:JSONDecode(body)
            end)

            if not parsed or type(data) ~= "table" then
                lastCode = -1
                return nil, nil
            end

            return data.data, data.nextPageCursor
        end

        local function refill()
            table.clear(pool)
            local cursor

            for _ = 1, PAGES do
                local entries, nextCursor = fetch(cursor)

                if type(entries) == "table" then
                    for _, entry in ipairs(entries) do
                        local id = type(entry) == "table" and entry.id or nil
                        if type(id) == "string" and id ~= game.JobId and not visited[id] then
                            local playing = tonumber(entry.playing) or 0
                            local room = tonumber(entry.maxPlayers) or 0
                            if room == 0 or playing < room then
                                pool[#pool + 1] = id
                            end
                        end
                    end
                end

                cursor = nextCursor
                if type(cursor) ~= "string" or cursor == "" or #pool >= POOL_TARGET then
                    break
                end
            end

            for index = #pool, 2, -1 do
                local swap = math.random(1, index)
                pool[index], pool[swap] = pool[swap], pool[index]
            end

            return #pool
        end

        function Net.rejoin()
            if reviving then
                return
            end

            reviving = true
            local jobId = game.JobId

            task.spawn(function()
                for _ = 1, RETRY_LIMIT do
                    local sent = pcall(function()
                        Services.TeleportService:TeleportToPlaceInstance(PLACE, jobId, LocalPlayer)
                    end)

                    if not sent then
                        pcall(function()
                            Services.TeleportService:Teleport(PLACE, LocalPlayer)
                        end)
                    end

                    task.wait(RETRY_STEP)
                end

                reviving = false
            end)
        end

        function Net.hop()
            if hopping then
                return false
            end

            hopping = true
            visited[game.JobId] = true

            task.spawn(function()
                for round = 1, RETRY_LIMIT do
                    if #pool == 0 and refill() == 0 then
                        table.clear(visited)
                        visited[game.JobId] = true
                        refill()
                    end

                    local choice = table.remove(pool)
                    if choice then
                        visited[choice] = true
                        note(string.format("try %d  %s", round, string.sub(choice, 1, 8)))

                        local sent, err = pcall(function()
                            Services.TeleportService:TeleportToPlaceInstance(PLACE, choice, LocalPlayer)
                        end)

                        if not sent then
                            note("blocked  " .. tostring(err))
                        end

                        if #pool <= REFILL_MARK then
                            task.spawn(refill)
                        end
                    else
                        note(string.format("no servers  http %d", lastCode))
                    end

                    task.wait(RETRY_STEP)
                end

                hopping = false
            end)

            return true
        end

        function Net.forget()
            table.clear(visited)
            table.clear(pool)
            visited[game.JobId] = true
        end

        function Net.busy()
            return hopping
        end

        function Net.ready()
            return #pool
        end

        function Net.stop()
            alive = false
        end

        task.spawn(function()
            while alive do
                if #pool < POOL_TARGET and not hopping then
                    refill()
                end
                task.wait(WARM_STEP)
            end
        end)

        Storage.netConns[#Storage.netConns + 1] = Services.TeleportService.TeleportInitFailed:Connect(function()
            hopping = false
        end)

        Storage.netConns[#Storage.netConns + 1] = Services.GuiService.ErrorMessageChanged:Connect(function()
            local ok, message = pcall(function()
                return Services.GuiService:GetErrorMessage()
            end)

            if ok and type(message) == "string" and message ~= "" then
                task.delay(BACK_DELAY, Net.rejoin)
            end
        end)

        local prompts = Services.CoreGui:FindFirstChild("RobloxPromptGui")
        local overlay = prompts and prompts:FindFirstChild("promptOverlay")

        if overlay then
            Storage.netConns[#Storage.netConns + 1] = overlay.ChildAdded:Connect(function(child)
                if child.Name:find("ErrorPrompt") then
                    task.delay(BACK_DELAY, Net.rejoin)
                end
            end)
        end
    end

    install()
end



-- === Экспорт модуля ===
E.Net = Net
