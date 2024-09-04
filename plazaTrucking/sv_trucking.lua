local Server = lib.require('sv_config')
local Config = lib.require('config')
local storedRoutes = {}
local queue = {}
local spawnedTrailers = {}
local handlingPayments = {}

local function removeFromQueue(cid)
    for i, cids in ipairs(queue) do
        if cids == cid then
            table.remove(queue, i)
            break
        end
    end
end

local function createTruckingVehicle(source, model, warp, coords)
    if not coords then coords = Config.VehicleSpawn end

    -- CreateVehicleServerSetter can be funky and I cba, especially for a temp vehicle. Cry about it. I just need the entity handle.
    local vehicle = CreateVehicle(joaat(model), coords.x, coords.y, coords.z, coords.w, true, true)
    local ped = GetPlayerPed(source)

    while not DoesEntityExist(vehicle) do Wait(0) end 

    if warp then
        while GetVehiclePedIsIn(ped, false) ~= vehicle do
            TaskWarpPedIntoVehicle(ped, vehicle, -1)
            Wait(100)
        end
    end

    return vehicle
end

local function resetEverything()
    local players = GetPlayers()
    if #players > 0 then
        for i = 1, #players do
            local src = tonumber(players[i])
            local player = GetPlayer(src)

            if player then
                if Player(src).state.truckDuty then
                    Player(src).state:set('truckDuty', false, true)
                end
                local cid = GetPlyIdentifier(player)
                if storedRoutes[cid] and storedRoutes[cid].vehicle and DoesEntityExist(storedRoutes[cid].vehicle) then
                    DeleteEntity(storedRoutes[cid].vehicle)
                end
            end

            if spawnedTrailers[src] and DoesEntityExist(spawnedTrailers[src]) then
                DeleteEntity(spawnedTrailers[src])
            end
        end
    end
end

local function generateRoute(cid)
    local data = {}
    data.pickup = Server.Pickups[math.random(#Server.Pickups)] 
    data.payment = math.random(Server.Payment.min, Server.Payment.max)
    repeat
        data.deliver = Server.Deliveries[math.random(#Server.Deliveries)]

        local found = false
        for _, route in ipairs(storedRoutes[cid].routes) do
            if route.deliver == data.deliver then
                found = true
                break
            end
        end

        if not found then break end
    until false

    return data
end

lib.callback.register('plazaTrucking:server:clockIn', function(source)
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)

    if storedRoutes[cid] then
        DoNotification(src, 'Du har allerede startet et oppdrag. Sjekk rutene dine.')
        return false
    end

    queue[#queue+1] = cid
    storedRoutes[cid] = { routes = {}, vehicle = 0, }
    Player(src).state:set('truckDuty', true, true)

    DoNotification(src, 'Du har startet et oppdrag for Logistikk AS. Se etter jobbmeldinger eller sjekk gjeldende ruter.', 'success', 7000)
    return true
end)

lib.callback.register('plazaTrucking:server:clockOut', function(source) 
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)

    if not storedRoutes[cid] or not Player(src).state.truckDuty then
        DoNotification(src, 'Du har ikke startet et oppdrag for Logistikk AS.', 'error')
        return false
    end

    local workTruck = storedRoutes[cid].vehicle
    local workTrailer = spawnedTrailers[src]

    if workTruck and DoesEntityExist(workTruck) then DeleteEntity(workTruck) end
    if workTrailer and DoesEntityExist(workTrailer) then DeleteEntity(workTrailer) end

    removeFromQueue(cid)
    storedRoutes[cid] = nil
    Player(src).state:set('truckDuty', false, true)
    TriggerClientEvent('plazaTrucking:client:clearRoutes', src)
    DoNotification(src, 'Du har avsluttet oppdrag og fjernet alle de gamle rutene dine.', 'success')
    return true
end)

lib.callback.register('plazaTrucking:server:spawnTruck', function(source) 
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)

    if not storedRoutes[cid] or not Player(src).state.truckDuty then
        DoNotification(src, 'Du er ikke i et oppdrag for Logistikk AS.', 'error')
        return false
    end

    local workTruck = storedRoutes[cid].vehicle

    if DoesEntityExist(workTruck) then
        local coords = GetEntityCoords(workTruck)
        return false, coords, NetworkGetNetworkIdFromEntity(workTruck)
    end

    local model = Server.Trucks[math.random(#Server.Trucks)]
    local vehicle = createTruckingVehicle(src, model, true)

    storedRoutes[cid].vehicle = vehicle
    DoNotification(src, 'Du har hentet ut arbeidsbilen din fra jobbgarasje. Sjekk ut dine nåværende ruter eller vent til en kommer gjennom systemet.', 'success')
    TriggerClientEvent('plazaTrucking:server:spawnTruck', src, NetworkGetNetworkIdFromEntity(vehicle))
    return true
end)

lib.callback.register('plazaTrucking:server:spawnTrailer', function(source) 
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)

    if not storedRoutes[cid] or not Player(src).state.truckDuty then return false end

    local model = Server.Trailers[math.random(#Server.Trailers)]
    local coords = storedRoutes[cid].currentRoute.pickup
    local trailer = createTruckingVehicle(src, model, false, coords)

    spawnedTrailers[src] = trailer
    return true, NetworkGetNetworkIdFromEntity(trailer)
end)

lib.callback.register('plazaTrucking:server:chooseRoute', function(source, index) 
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)

    if not storedRoutes[cid] or not Player(src).state.truckDuty then return false end

    if spawnedTrailers[src] or storedRoutes[cid].currentRoute then
        DoNotification(src, 'Du har allerede en aktiv rute å fullføre.', 'success')
        return false 
    end

    storedRoutes[cid].currentRoute = storedRoutes[cid].routes[index]
    storedRoutes[cid].currentRoute.index = index

    return storedRoutes[cid].currentRoute
end)

lib.callback.register('plazaTrucking:server:getRoutes', function(source) 
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)

    if not storedRoutes[cid] or not Player(src).state.truckDuty then return false end

    return storedRoutes[cid].routes
end)

lib.callback.register('plazaTrucking:server:updateRoute', function(source, netid, route)
    if handlingPayments[source] then return false end
    handlingPayments[source] = true
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)
    local pos = GetEntityCoords(GetPlayerPed(src))
    local entity = NetworkGetEntityFromNetworkId(netid)
    local coords = GetEntityCoords(entity)
    local data = storedRoutes[cid]

    if not data or not DoesEntityExist(entity) or #(coords - data.currentRoute.deliver.xyz) > 15.0 or #(pos - data.currentRoute.deliver.xyz) > 15.0 then
        handlingPayments[src] = nil
        return false 
    end
    
    if spawnedTrailers[src] == entity and route.index == data.currentRoute.index then
        local payout = data.currentRoute.payment
        DeleteEntity(entity)
        spawnedTrailers[src] = nil
        data.currentRoute = nil
        table.remove(data.routes, route.index)
        AddMoney(player, 'cash', payout)
        DoNotification(src, ('Du fullførte kontrakt og mottok %s kr i kontanter!'):format(payout), 'success', 7000)
        SetTimeout(2000, function()
            handlingPayments[src] = nil
        end)
    end
end)

lib.callback.register('plazaTrucking:server:abortRoute', function(source, index)
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)

    if not storedRoutes[cid] or not Player(src).state.truckDuty then return false end

    local data = storedRoutes[cid]

    if data.currentRoute and data.currentRoute.index == index then
        if spawnedTrailers[src] and DoesEntityExist(spawnedTrailers[src]) then
            DeleteEntity(spawnedTrailers[src])
            spawnedTrailers[src] = nil
        end
        data.currentRoute = nil
        table.remove(data.routes, index)
        TriggerClientEvent('plazaTrucking:client:clearRoutes', src)
        return true
    end

    return false
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    resetEverything()
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Player(src).state.truckDuty then
        Player(src).state:set('truckDuty', false, true)
        if spawnedTrailers[src] and DoesEntityExist(spawnedTrailers[src]) then
            DeleteEntity(spawnedTrailers[src])
        end
    end
end)

function OnPlayerLoaded(source)
    local src = source
    local player = GetPlayer(src)
    local cid = GetPlyIdentifier(player)
    
    if storedRoutes[cid] then
        Player(src).state:set('truckDuty', true, true)
    end
end

function OnPlayerUnload(source)
    local src = source
    if Player(src).state.truckDuty then
        Player(src).state:set('truckDuty', false, true)
        if spawnedTrailers[src] and DoesEntityExist(spawnedTrailers[src]) then
            DeleteEntity(spawnedTrailers[src])
        end
    end
end

local function initQueue()
    if #queue == 0 then return end

    for i = 1, #queue do
        local cid = queue[i]
        local src = GetSourceFromIdentifier(cid)
        local player = GetPlayer(src)
        if player and Player(src).state.truckDuty then
            if #storedRoutes[cid].routes < 5 then
                storedRoutes[cid].routes[#storedRoutes[cid].routes + 1] = generateRoute(cid)
                DoNotification(src, 'En ny rute er lagt til i liste over tilgjengelige ruter.')
            end
        end
    end
end

SetInterval(initQueue, Server.QueueTimer * 60000)