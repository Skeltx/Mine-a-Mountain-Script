param(
    [string]$Source = 'D:\Projects\OpenCode\MaM\MaM.lua',
    [string]$OutDir = 'D:\Projects\GitHub\Mine-a-Mountain-Script\Test\src'
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) { throw "source not found: $Source" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$utf8 = [System.Text.UTF8Encoding]::new($false)
$lines = [IO.File]::ReadAllLines($Source)
Write-Output ("source lines: " + $lines.Count)

function Slice([int]$a, [int]$b) {
    if ($b -lt $a) { return @() }
    return $lines[($a - 1)..($b - 1)]
}

# ---------------------------------------------------------------- defines
$mainExports = @(
    'Services','LocalPlayer','Mouse','Config','State','Storage','Connections','GuiRoot','Remotes',
    'ESP','PLAYER','PACE','TP','PICK','COLORS','TIER_NAMES','LUCK','MUTATION_LUCK','WATCHED_ATTRIBUTES',
    'SUFFIXES','PARSE_MULTIPLIERS','CONTAINER_NAMES',
    'Library','SaveManager','ThemeManager','Window','Tabs','SettingsTab','EventsTab','OtherTab','EspHolder',
    'reportError','formatShort','formatWeight','formatDistance','formatLuck','parseValue',
    'bindCharacter','getRoot','getAttr',
    'crystalValue','crystalWeight','crystalTier','crystalRarity','crystalName','crystalColor',
    'mutationLuck','combinedLuckMult','computeLuck','luckLabel','luckLabelText','crystalLuck',
    'meetsFilter','ownsGamepass','realStat','hasActiveRune','looksLikeCrystal',
    'backpackCapacity','backpackWeight','backpackFree','isCrystal','rebuildContainers','eachContainer',
    'requestStream','applyPivot','findClearGoal','finishTeleport','teleportTo','schedule'
)

$reshowCode = @'
-- === Гарантия видимости окна: AutoShow в Obsidian срабатывает один раз при
-- создании окна; если в этот момент что-то из библиотечных аддонов пометило
-- загрузку активной, окно может остаться скрытым. Через 3 секунды после
-- полной загрузки всех модулей принудительно показываем, если скрыто. ===
task.delay(3, function()
    pcall(function()
        local frame = Library.Window and Library.Window.MainFrame
        if Library.Window and frame and (not Library.Toggled or not frame.Visible) then
            Library:Toggle(true)
        end
    end)
end)
'@

$schedulerCode = @'
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
'@

$fragments = [ordered]@{
    '00_main.lua' = @{
        Title = 'CORE — конфиг, сервисы, стейт, UI-окно, общие хелперы'
        Ranges = @('1-738', '1327-1486')
        Imports = @()
        ExtraBody = $schedulerCode
        Exports = $mainExports
    }
    '10_esp.lua' = @{
        Title = 'ESP — движок ESP кристаллов/игроков + вкладка Crystals + Player ESP (UI)'
        Ranges = @('739-1326', '3185-3275')
        Exports = @('clearRegistry','clearPlayerEsp','unwatchContainers','newLabel')
    }
    '15_net.lua' = @{
        Title = 'NET — серверный хоп/тёплый пул серверов, авто-rejoin'
        Ranges = @('3559-3800')
        Exports = @('Net')
    }
    '20_boulders.lua' = @{
        Title = 'BOULDERS — движок Mountain (копание валунов), aimTeleport, вкладка Boulders, Boulder Farm'
        Ranges = @('2074-2710', '3276-3309', '3801-4997')
        Exports = @('Mountain','Farm','aimTeleport','tpToRank','fireRemote','unfavoriteAll','mountainSpot','mountainSpan','getSellCFrame')
        LocalImports = @('newLabel')
        LazyImports = @('Move','crystalPrompt','firePrompt','sortedByScore')
    }
    '30_farm.lua' = @{
        Title = 'FARM — промпты/авто-сбор кристаллов, бэкпак, Auto Farm Crystal'
        Ranges = @('1487-1898', '3434-3464', '4998-5936', '6017-6021')
        Exports = @('Money','restoreInstantPrompts','crystalPrompt','firePrompt')
        LocalImports = @('Mountain','Farm','fireRemote','unfavoriteAll','mountainSpot','mountainSpan')
        LazyImports = @('Move')
    }
    '40_shop.lua' = @{
        Title = 'SHOP — Bomb Auto Buy (закупка бомб)'
        Ranges = @('5938-6015')
        Exports = @()
    }
    '50_teleports.lua' = @{
        Title = 'TELEPORTS — Top Crystals, Teleports (UI), обработка инпута (E/aim-TP)'
        Ranges = @('2037-2072', '3310-3433', '3509-3558')
        Exports = @()
        LocalImports = @('tpToRank','fireRemote','unfavoriteAll','getSellCFrame')
        LazyImports = @('Move','firePrompt')
    }
    '60_movement.lua' = @{
        Title = 'MOVEMENT — Speed/Noclip/InfJump/Fly + вкладка Movement'
        Ranges = @('1900-1956', '2711-3184', '3465-3508')
        Exports = @('Move','setSpeedBoost')
    }
    '70_settings.lua' = @{
        Title = 'SETTINGS — SaveManager, ThemeManager, вкладка Settings, cleanupAll/unload'
        Ranges = @('6023-6231')
        Exports = @()
        LocalImports = @('Mountain','Farm','Money','Net','Move','setSpeedBoost','restoreInstantPrompts','clearRegistry','clearPlayerEsp','unwatchContainers')
    }
    '80_events.lua' = @{
        Title = 'EVENTS — вкладка Events (Halloween 2026: candy/ghost/pumpkin)'
        Ranges = @('6233-6807')
        Exports = @('_eventsStops')
    }
    '90_other.lua' = @{
        Title = 'OTHER — Other (Collect Rune, FPS Boost) + перенос Boulders ESP/Farm (Analog) в Boulders'
        Ranges = @('6810-7464')
        ExtraBody = $reshowCode
        Exports = @()
        LocalImports = @('_eventsStops')
    }
}

# ---------------------------------------------------------------- headers
$mainHeader = @'
-- ============================================================
-- MaM :: 00_main — ядро скрипта
-- Конфиг, сервисы, общий стейт, окно/вкладки UI, универсальные
-- хелперы (форматтеры, кристаллы, телепорт-ядро), планировщик.
-- Экспортирует всё в getgenv().MaMEnv — таблицу, которую
-- импортируют все остальные модули.
-- ============================================================

getgenv().MaMEnv = getgenv().MaMEnv or {}
local E = getgenv().MaMEnv

'@

$footerCommon = @'

-- === Экспорт модуля ===
'@

# ---------------------------------------------------------------- build
foreach ($name in $fragments.Keys) {
    $f = $fragments[$name]
    $parts = [System.Collections.Generic.List[string]]::new()

    if ($name -eq '00_main.lua') {
        $parts.Add($mainHeader)
    } else {
        $header = "-- ============================================================`n"
        $header += "-- MaM :: $name`n"
        $header += "-- $($f.Title)`n"
        $header += "-- Все общие имена приходят из getgenv().MaMEnv (заполняет 00_main).`n"
        $header += "-- ============================================================`n`n"
        $header += "local E = getgenv().MaMEnv`n`n"
        foreach ($imp in $mainExports) {
            if ($name -in @('80_events.lua','90_other.lua') -and $imp -in @(
                'ESP','PLAYER','PACE','TP','PICK','COLORS','TIER_NAMES','LUCK','MUTATION_LUCK',
                'WATCHED_ATTRIBUTES','SUFFIXES','PARSE_MULTIPLIERS','CONTAINER_NAMES','SaveManager',
                'ThemeManager','EspHolder','formatDistance','bindCharacter','getRoot',
                'getAttr','crystalTier','crystalRarity','mutationLuck','combinedLuckMult','computeLuck',
                'luckLabel','luckLabelText','meetsFilter','ownsGamepass','realStat','hasActiveRune',
                'looksLikeCrystal','isCrystal','rebuildContainers','applyPivot','findClearGoal',
                'finishTeleport','schedule','rebuildContainers')) {
                # широкие импорты не нужны — срезаем для экономии регистров
                continue
            }
            $header += "local $imp = E.$imp`n"
        }
        if ($f.LocalImports) {
            foreach ($n in $f.LocalImports) {
                $header += "local $n = E.$n`n"
            }
        }
        if ($f.LazyImports) {
            $header += "`n-- Lazy-импорты: имена другого модуля, который грузится ПОЗЖЕ текущего.`n"
            foreach ($n in $f.LazyImports) {
                if ($n -eq 'Move') {
                    $header += "local Move = setmetatable({}, { __index = function(_, k) local m = E.Move; return (m and m[k]) or function() end end })`n"
                } else {
                    $header += "local function $n(...) local f = E.$n if not f then return nil end return f(...) end`n"
                }
            }
        }
        $parts.Add($header)
    }

    $body = [System.Collections.Generic.List[string]]::new()
    foreach ($rs in $f.Ranges) {
        $pair = $rs -split '-'
        $a = [int]$pair[0]
        $b = [int]$pair[1]
        $body.AddRange([string[]](Slice $a $b))
        $body.Add('')
    }

    foreach ($t in $body) { $parts.Add($t) }

    if ($f.ExtraBody) {
        $parts.Add($f.ExtraBody)
    }

    # точечный патч фрагмента телепортов: отражаем инпут-хуки через env
    $joined = [string]::Join("`n", $parts)
    if ($name -eq '50_teleports.lua') {
        $joined = $joined.Replace('pcall(instantGrab)',
            'pcall(function() if E.InstantGrab then E.InstantGrab() end end)')
        $joined = $joined.Replace('pcall(aimTeleport)',
            'pcall(function() if E.aimTeleport then E.aimTeleport() end end)')
    }

    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add($joined)

    if ($f.Exports.Count -gt 0) {
        $out.Add($footerCommon)
        foreach ($exp in $f.Exports) {
            $out.Add("E.$exp = $exp")
        }
    }

    if ($name -eq '30_farm.lua') {
        $out.Add(@'

-- === Регистрация тик-функций для центрального планировщика ===
E.PickupTick = pickupStep
E.InstantTick = refreshInstantPrompts
E.InstantGrab = instantGrab
E.SlowTick = updateBackpackLabel
'@)
    }
    if ($name -eq '60_movement.lua') {
        $out.Add(@'

-- === Регистрация тик-функций для центрального планировщика ===
E.MovementTick = function()
    local body = LocalPlayer.Character
    local mover = body and body:FindFirstChildOfClass("Humanoid")
    if mover then
        watchSpeed(mover)
        enforceSpeed(mover)
    end
end
'@)
    }
    if ($name -eq '10_esp.lua') {
        $out.Add(@'

-- === Регистрация тик-функций для центрального планировщика ===
E.PlayerEspTick = updatePlayerEsp
'@)
    }

    $path = Join-Path $OutDir $name
    [IO.File]::WriteAllText($path, ([string]::Join("`n", $out)) + "`n", $utf8)
    Write-Output ("written: " + $path)
}

# ---------------------------------------------------------------- combined check
$combined = [System.Collections.Generic.List[string]]::new()
foreach ($name in $fragments.Keys) {
    $combined.Add('-- @@@@@ PATCH-BOUNDRY: ' + $name)
    $combined.AddRange([string[]][IO.File]::ReadAllLines((Join-Path $OutDir $name)))
}
$combinedPath = 'C:\Users\bolte\AppData\Local\Temp\opencode\MaM_fragments_combined.lua'
[IO.File]::WriteAllText($combinedPath, ([string]::Join("`n", $combined)) + "`n", $utf8)
Write-Output ("combined: " + $combinedPath)
