local Config = lib.require('config')
local DropOffZone, activeTrailer, pickupZone, PICKUP_BLIP, DELIVERY_BLIP
local activeRoute = {}
local droppingOff = false
local delay = false

local TruckerWork = AddBlipForCoord(Config.BossCoords.x, Config.BossCoords.y, Config.BossCoords.z)
SetBlipSprite(TruckerWork, 479)
SetBlipDisplay(TruckerWork, 4)
SetBlipScale(TruckerWork, 0.5)
SetBlipAsShortRange(TruckerWork, true)
SetBlipColour(TruckerWork, 24)
BeginTextCommandSetBlipName('STRING')
AddTextComponentSubstringPlayerName('Logistikk AS')
EndTextCommandSetBlipName(TruckerWork)

local function targetLocalEntity(entity, options, distance)
    if GetResourceState('ox_target') == 'started' then
        for _, option in ipairs(options) do
            option.distance = distance
            option.onSelect = option.action
            option.action = nil
        end
        exports.ox_target:addLocalEntity(entity, options)
    else
        exports['qb-target']:AddTargetEntity(entity, {
            options = options,
            distance = distance
        })
    end
end

local function cleanupShit()
    if DropOffZone then DropOffZone:remove() DropOffZone = nil end
    if pickupZone then pickupZone:remove() pickupZone = nil end
    if DoesBlipExist(PICKUP_BLIP) then RemoveBlip(PICKUP_BLIP) end
    if DoesBlipExist(DELIVERY_BLIP) then RemoveBlip(DELIVERY_BLIP) end

    activeTrailer, PICKUP_BLIP, DELIVERY_BLIP = nil
    table.wipe(activeRoute)
    delay = false
    droppingOff = false
end

local function getStreetandZone(coords)
    local currentStreetHash = GetStreetNameAtCoord(coords.x, coords.y, coords.z)
    local currentStreetName = GetStreetNameFromHashKey(currentStreetHash)
    return currentStreetName
end

local function createRouteBlip(coords, label)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, 479)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.5)
    SetBlipAsShortRange(blip, true)
    SetBlipColour(blip, 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, 83)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(label)
    EndTextCommandSetBlipName(blip)
    return blip
end

local function viewRoutes()
    local context = {}

    local routes = lib.callback.await('plazaTrucking:server:getRoutes', false)
    if not next(routes) then
        return DoNotification('Du har ingen ruter for øyeblikket.', 'error')
    end

    for index, data in pairs(routes) do
        local isDisabled = activeRoute.index == index
        local info = ('Rute: %s \nBetaling: %s kr'):format(getStreetandZone(data.deliver.xyz), data.payment)
        context[#context + 1] = {
            title = ('%s'):format(getStreetandZone(data.pickup.xyz)),
            description = info,
            icon = 'fa-solid fa-location-dot',
            disabled = isDisabled,
            onSelect = function()
                local choice = lib.callback.await('plazaTrucking:server:chooseRoute', false, index)
                if choice and type(choice) == 'table' then
                    activeRoute = choice
                    activeRoute.index = index
                    SetRoute()
                end
            end,
        }
    end

    lib.registerContext({ id = 'view_work_routes', title = 'Logistikk AS - Tilgjengelige ruter', options = context })
    lib.showContext('view_work_routes')
end

local function nearZone(point)
    DrawMarker(1, point.coords.x, point.coords.y, point.coords.z - 1, 0, 0, 0, 0, 0, 0, 6.0, 6.0, 1.5, 79, 194, 247, 165, 0, 0, 0,0)
    
    if point.isClosest and point.currentDistance <= 4 then
        if not showText then
            showText = true
            lib.showTextUI('[**E**] Lever tilhenger', {position = 'right-center'})
        end
        if next(activeRoute) and cache.vehicle and IsEntityAttachedToEntity(cache.vehicle, activeTrailer) then
            if IsControlJustPressed(0, 38) and not droppingOff then
                droppingOff = true
                FreezeEntityPosition(cache.vehicle, true)
                lib.hideTextUI()
                if lib.progressCircle({
                    duration = 5000,
                    position = 'bottom',
                    label = 'Slipper av tilhenger..',
                    useWhileDead = false,
                    canCancel = false,
                    disable = { move = true, car = true, mouse = false, combat = true, },
                }) then
                    DetachEntity(activeTrailer, true, true)
                    NetworkFadeOutEntity(activeTrailer, 0, 1)
                    Wait(500)
                    lib.callback.await('plazaTrucking:server:updateRoute', false, NetworkGetNetworkIdFromEntity(activeTrailer), activeRoute)
                    FreezeEntityPosition(cache.vehicle, false)
                    cleanupShit()
                end
            end
        end
    elseif showText then
        showText = false
        lib.hideTextUI()
    end
end

local function createDropoff()
    RemoveBlip(PICKUP_BLIP)
    pickupZone:remove()
    DropOffZone = lib.points.new({ coords = vec3(activeRoute.deliver.x, activeRoute.deliver.y, activeRoute.deliver.z), distance = 20, nearby = nearZone })
    DELIVERY_BLIP = createRouteBlip(activeRoute.deliver.xyz, 'Leveringspunkt')
    SetNewWaypoint(activeRoute.deliver.x, activeRoute.deliver.y)
    DoNotification('Din leveringsrute er merket.', 'success')
    Wait(1000)
    delay = false
end

function SetRoute()
    PICKUP_BLIP = createRouteBlip(activeRoute.pickup.xyz, 'Hentepunkt')
    DoNotification('Gå til hentestedet og hent tilhengeren din.')
    pickupZone = lib.points.new({ 
        coords = vec3(activeRoute.pickup.x, activeRoute.pickup.y, activeRoute.pickup.z), 
        distance = 70, 
        onEnter = function()
            if not activeTrailer then
                local success, netid = lib.callback.await('plazaTrucking:server:spawnTrailer', false)
                if success and netid then
                    activeTrailer = lib.waitFor(function()
                        if NetworkDoesEntityExistWithNetworkId(netid) then
                            return NetToVeh(netid)
                        end
                    end, 'Kunne ikke laste inn tilhenger i tide.', 3000)
                end
            end
        end,
        nearby = function()
            DrawMarker(1, activeRoute.pickup.x, activeRoute.pickup.y, activeRoute.pickup.z - 1, 0, 0, 0, 0, 0, 0, 6.0, 6.0, 1.5, 79, 194, 247, 165, 0, 0, 0,0)
            
            if cache.vehicle and IsEntityAttachedToEntity(cache.vehicle, activeTrailer) and not delay then
                delay = true
                createDropoff()
            end
        end,
    })
end

local function removePedSpawned()
    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:removeLocalEntity(truckerPed, {'Start oppdrag', 'Avslutt oppdrag', 'Vis ruter', 'Jobbkjøretøy', 'Avbryt rute'})
    else
        exports['qb-target']:RemoveTargetEntity(truckerPed, {'Start oppdrag', 'Avslutt oppdrag', 'Vis ruter', 'Jobbkjøretøy', 'Avbryt rute'})
    end
    DeleteEntity(truckerPed)
    truckerPed = nil
end

local function spawnPed()
    if DoesEntityExist(truckerPed) then return end

    lib.requestModel(Config.BossModel)
    truckerPed = CreatePed(0, Config.BossModel, Config.BossCoords, false, false)
    SetEntityAsMissionEntity(truckerPed, true, true)
    SetPedFleeAttributes(truckerPed, 0, 0)
    SetBlockingOfNonTemporaryEvents(truckerPed, true)
    SetEntityInvincible(truckerPed, true)
    FreezeEntityPosition(truckerPed, true)
    SetModelAsNoLongerNeeded(Config.BossModel)
    targetLocalEntity(truckerPed, {
        { 
            num = 1,
            icon = 'fa-solid fa-clipboard-check',
            label = 'Start oppdrag',
            canInteract = function()
                return not LocalPlayer.state.truckDuty
            end,
            action = function()
                lib.callback.await('plazaTrucking:server:clockIn', false)
            end,
        },
        { 
            num = 2,
            icon = 'fa-solid fa-clipboard-check',
            label = 'Avslutt oppdrag',
            canInteract = function() return LocalPlayer.state.truckDuty end,
            action = function()
                lib.callback.await('plazaTrucking:server:clockOut', false)
            end,
        },
        {
            num = 3,
            icon = 'fa-solid fa-clipboard-check',
            label = 'Vis ruter',
            canInteract = function() return LocalPlayer.state.truckDuty end,
            action = function()
                viewRoutes()
            end,
        },
        {
            num = 4,
            icon = 'fa-solid fa-truck',
            label = 'Jobbkjøretøy',
            canInteract = function() return LocalPlayer.state.truckDuty end,
            action = function()
                if IsAnyVehicleNearPoint(Config.VehicleSpawn.x, Config.VehicleSpawn.y, Config.VehicleSpawn.z, 15.0) then 
                    return DoNotification('Et kjøretøy blokkerer henting av jobbkjøretøy.', 'error') 
                end

                local success, coords = lib.callback.await('plazaTrucking:server:spawnTruck', false)
                if not success and coords then
                    SetNewWaypoint(coords.x, coords.y)
                    DoNotification('Jobbkjøretøyet ditt er allerede ute. Den har blitt lokalisert på GPS-en din.')
                end
            end,
        },
        {
            num = 5,
            icon = 'fa-solid fa-xmark',
            label = 'Avbryt rute',
            canInteract = function() return LocalPlayer.state.truckDuty and next(activeRoute) end,
            action = function()
                local success = lib.callback.await('plazaTrucking:server:abortRoute', false, activeRoute.index)
                if success then
                    DoNotification('Du avbrøt den nåværende ruten.', 'error')
                end
            end,
        },
    }, 1.5)
end

RegisterNetEvent('plazaTrucking:client:clearRoutes', function()
    if GetInvokingResource() then return end
    cleanupShit()
end)

RegisterNetEvent('plazaTrucking:server:spawnTruck', function(netid)
    if GetInvokingResource() or not netid then return end
    local MY_VEH = lib.waitFor(function()
        if NetworkDoesEntityExistWithNetworkId(netid) then
            return NetToVeh(netid)
        end
    end, 'Kunne ikke laste inn tilhenger i tide.', 3000)
    
    handleVehicleKeys(MY_VEH)
    if Config.Fuel.enable then
        exports[Config.Fuel.script]:SetFuel(MY_VEH, 100.0)
    else
        Entity(MY_VEH).state.fuel = 100
    end
end)

local function createTruckingStart()
    truckingPedZone = lib.points.new({
        coords = Config.BossCoords.xyz,
        distance = 60,
        onEnter = spawnPed,
        onExit = removePedSpawned,
    })
end

AddEventHandler('onResourceStop', function(resourceName) 
    if GetCurrentResourceName() == resourceName and hasPlyLoaded() then
        OnPlayerUnload()
    end 
end)

AddEventHandler('onResourceStart', function(resource)
    if GetCurrentResourceName() == resource and hasPlyLoaded() then
        createTruckingStart()
    end
end)

function OnPlayerLoaded()
    createTruckingStart()
end

function OnPlayerUnload()
    if truckingPedZone then truckingPedZone:remove() truckingPedZone = nil end
    removePedSpawned()
    cleanupShit()
end
