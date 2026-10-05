local currentRental = nil
local courierPed = nil
local courierVeh = nil
local deliveryBlip = nil

local function RemoveDeliveryBlip()
    if deliveryBlip and DoesBlipExist(deliveryBlip) then
        RemoveBlip(deliveryBlip)
        deliveryBlip = nil
    end
end

local function CreateDeliveryBlip(entity)
    RemoveDeliveryBlip()
    deliveryBlip = AddBlipForEntity(entity)
    SetBlipSprite(deliveryBlip, 225)
    SetBlipColour(deliveryBlip, 2)
    SetBlipScale(deliveryBlip, 0.85)
    SetBlipRoute(deliveryBlip, true)
    SetBlipRouteColour(deliveryBlip, 2)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentSubstringPlayerName("Véhicule de location")
    EndTextCommandSetBlipName(deliveryBlip)
end

local function ApplyInvincibleVehicle(veh, ped)
    SetEntityInvincible(veh, true)
    SetEntityProofs(veh, true, true, true, true, true, true, true, true)
    SetVehicleDamageModifier(veh, 0.0)
    SetVehicleEngineCanDegrade(veh, false)
    SetVehicleTyresCanBurst(veh, false)
    SetVehicleStrong(veh, true)
    SetVehicleCanBeVisiblyDamaged(veh, false)

    SetVehicleDoorsLocked(veh, 4)
    SetVehicleDoorsLockedForAllPlayers(veh, true)

    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    SetPedCanRagdollFromPlayerImpact(ped, false)
    SetPedCanBeKnockedOffVehicle(ped, false)
    SetPedCanBeDraggedOut(ped, false)
    SetBlockingOfNonTemporaryEvents(ped, true)
    SetPedKeepTask(ped, true)
    SetDriverAbility(ped, 1.0)
    SetDriverAggressiveness(ped, 0.0)
end

local function AddPhoneApp()
    while GetResourceState("lb-phone") ~= "started" do
        Wait(500)
    end

    exports["lb-phone"]:AddCustomApp({
        identifier = "old_rentVehicle",
        name = Config.AppLabel,
        description = "Application de location de véhicules.",
        developer = "discord.gg/F3TH5KMHuR",
        defaultApp = Config.DefaultApp,
        size = 12000,
        ui = GetCurrentResourceName() .. "/ui/dist/index.html",
        icon = Config.AppIcon,
        fixBlur = true,
        images = {
            "https://cfx-nui-old_rentVehicle/ui/dist/screenshot-dark.png",
            "https://cfx-nui-old_rentVehicle/ui/dist/screenshot-light.png"
        },

    })
end

CreateThread(function()
    AddPhoneApp()
end)

AddEventHandler("onResourceStart", function(resource)
    if resource == "lb-phone" then
        AddPhoneApp()
    end
end)

RegisterNUICallback("getInitialConfig", function(_, cb)
    local fleetList = {}
    for modelId, data in pairs(Config.Fleet) do
        table.insert(fleetList, {
            id = modelId,
            name = data.name,
            seats = data.seats,
            pricePer15 = data.pricePer15,
            image = data.image
        })
    end

    ESX.TriggerServerCallback("old_rentVehicle:getActiveRental", function(activeData)
        local initialRental = nil
        local vPos = nil

        if activeData and currentRental and DoesEntityExist(currentRental.vehicle) then
            local pos = GetEntityCoords(currentRental.vehicle)
            vPos = { x = pos.x, y = pos.y }
            initialRental = {
                model = activeData.model,
                duration = activeData.duration,
                price = activeData.price,
                claimed = activeData.claimed,
                remainingSeconds = activeData.remainingSeconds
            }
        end

        cb({
            fleet = fleetList,
            durations = Config.Durations,
            activeRental = initialRental,
            vehiclePos = vPos
        })
    end)
end)

RegisterNUICallback("extendRental", function(data, cb)
    local minutes = tonumber(data.minutes) or 15

    ESX.TriggerServerCallback("old_rentVehicle:extendRental", function(success, result)
        if not success then
            exports["lb-phone"]:SendNotification({
                title = Config.AppLabel,
                content = result,
                icon = Config.AppIcon
            })
            cb({ success = false, message = result })
            return
        end

        exports["lb-phone"]:SendNotification({
            title = Config.AppLabel,
            content = "Location prolongée de " .. minutes .. " minutes !",
            icon = Config.AppIcon
        })

        cb({
            success = true,
            addedSeconds = result.addedSeconds,
            newTotalPrice = result.newTotalPrice
        })
    end, minutes)
end)

local function GetValidRoadSpawn(playerCoords)
    local angle = math.random() * 2 * math.pi
    local distance = math.random(Config.MinSpawnDistance, Config.MaxSpawnDistance)
    local targetX = playerCoords.x + math.cos(angle) * distance
    local targetY = playerCoords.y + math.sin(angle) * distance
    local targetZ = playerCoords.z

    local found, roadPos, heading = GetClosestVehicleNodeWithHeading(targetX, targetY, targetZ, 1, 3.0, 0)
    if found and #(playerCoords - roadPos) >= 30.0 then
        return roadPos, heading
    end

    local fallbackFound, fallbackPos, fallbackHeading = GetClosestVehicleNodeWithHeading(playerCoords.x, playerCoords.y,
        playerCoords.z, 1, 3.0, 0)
    if fallbackFound then
        return fallbackPos, fallbackHeading
    end

    return nil, 0.0
end

local function DeliverVehicleTask(veh, ped, targetCoords)
    TaskVehicleDriveToCoord(
        ped,
        veh,
        targetCoords.x,
        targetCoords.y,
        targetCoords.z,
        22.0,
        0,
        joaat(GetEntityModel(veh)),
        2883621,
        6.0,
        true
    )

    CreateThread(function()
        local arrived = false
        while DoesEntityExist(veh) and DoesEntityExist(ped) and not arrived do
            Wait(1000)
            local playerPed = PlayerPedId()
            local vehPos = GetEntityCoords(veh)
            local playerPos = GetEntityCoords(playerPed)
            local distToPlayer = #(vehPos - playerPos)

            if distToPlayer <= 15.0 or (GetEntitySpeed(veh) < 0.1 and distToPlayer <= 25.0) then
                arrived = true
                TaskVehicleTempAction(ped, veh, 27, 2000)
                Wait(2000)
                TaskLeaveVehicle(ped, veh, 0)
                Wait(1500)
                TaskWanderStandard(ped, 10.0, 10)

                SetVehicleDoorsLocked(veh, 1)
                SetVehicleDoorsLockedForAllPlayers(veh, false)

                exports["lb-phone"]:SendNotification({
                    title = Config.AppLabel,
                    content = "Votre véhicule est arrivé ! Vous avez 5 minutes pour le récupérer.",
                    icon = Config.AppIcon
                })
            end
        end
    end)
end

RegisterNUICallback("requestVehicleRental", function(data, cb)
    local playerPed = PlayerPedId()

    if IsEntityInWater(playerPed) then
        exports["lb-phone"]:SendNotification({
            title = Config.AppLabel,
            content = "Impossible de livrer : vous êtes dans l'eau.",
            icon = Config.AppIcon
        })
        cb({ success = false, message = "dans_l_eau" })
        return
    end

    local playerCoords = GetEntityCoords(playerPed)
    local hasPath = GetClosestVehicleNode(playerCoords.x, playerCoords.y, playerCoords.z, 1, 3.0, 0)
    if not hasPath then
        exports["lb-phone"]:SendNotification({
            title = Config.AppLabel,
            content = "Aucune route carrossable détectée à proximité.",
            icon = Config.AppIcon
        })
        cb({ success = false, message = "pas_de_route" })
        return
    end

    ESX.TriggerServerCallback("old_rentVehicle:canOrder", function(authorized, result)
        if not authorized then
            exports["lb-phone"]:SendNotification({
                title = Config.AppLabel,
                content = result,
                icon = Config.AppIcon
            })
            cb({ success = false, message = result })
            return
        end

        local spawnPos, spawnHeading = GetValidRoadSpawn(playerCoords)
        if not spawnPos then
            TriggerServerEvent("old_rentVehicle:cancelRental")
            cb({ success = false, message = "position_spawn_introuvable" })
            return
        end

        local vehModelHash = joaat(data.model)
        local pedModelHash = joaat(Config.DriverPedModel)

        RequestModel(vehModelHash)
        RequestModel(pedModelHash)
        while not HasModelLoaded(vehModelHash) or not HasModelLoaded(pedModelHash) do
            Wait(10)
        end

        courierVeh = CreateVehicle(vehModelHash, spawnPos.x, spawnPos.y, spawnPos.z, spawnHeading, true, false)
        courierPed = CreatePedInsideVehicle(courierVeh, 26, pedModelHash, -1, true, false)

        SetEntityAsMissionEntity(courierVeh, true, true)
        SetEntityAsMissionEntity(courierPed, true, true)

        ApplyInvincibleVehicle(courierVeh, courierPed)
        CreateDeliveryBlip(courierVeh)

        local vehNet = NetworkGetNetworkIdFromEntity(courierVeh)
        local pedNet = NetworkGetNetworkIdFromEntity(courierPed)

        SetNetworkIdCanMigrate(vehNet, false)
        SetNetworkIdCanMigrate(pedNet, false)

        TriggerServerEvent("old_rentVehicle:registerEntities", vehNet, pedNet)

        currentRental = {
            vehicle = courierVeh,
            ped = courierPed,
            claimed = false,
            duration = data.duration
        }

        DeliverVehicleTask(courierVeh, courierPed, playerCoords)

        SetModelAsNoLongerNeeded(vehModelHash)
        SetModelAsNoLongerNeeded(pedModelHash)

        cb({
            success = true,
            duration = data.duration,
            price = data.price,
            vehiclePos = { x = spawnPos.x, y = spawnPos.y }
        })
    end, data)
end)

AddEventHandler("esx:enteredVehicle", function(vehicle, plate, seat, displayName, netId)
    local rentPhoneNumber = Entity(vehicle).state.rentPhoneNumber

    if rentPhoneNumber then
        if seat == -1 then
            local currentPhone = exports["lb-phone"]:HasPhoneItem(rentPhoneNumber)

            if not currentPhone then
                local playerPed = PlayerPedId()
                SetVehicleEngineOn(vehicle, false, true, true)
                SetVehicleUndriveable(vehicle, true)
                TaskLeaveVehicle(playerPed, vehicle, 0)
                ESX.ShowNotification(
                    "~r~Vous ne pouvez pas démarrer ce véhicule, l'application ne le reconnait.")
                return
            end
            ESX.ShowNotification("~g~Véhicule démarré a l'aide de l'application.")
            SetVehicleUndriveable(vehicle, false)
        end

        if currentRental and not currentRental.claimed and currentRental.vehicle == vehicle then
            currentRental.claimed = true
            RemoveDeliveryBlip()

            SetEntityInvincible(vehicle, false)
            SetVehicleDamageModifier(vehicle, 1.0)
            SetVehicleEngineCanDegrade(vehicle, true)
            SetVehicleTyresCanBurst(vehicle, true)
            SetVehicleStrong(vehicle, false)
            SetVehicleCanBeVisiblyDamaged(vehicle, true)

            TriggerServerEvent("old_rentVehicle:claimVehicle")

            exports["lb-phone"]:SendNotification({
                title = Config.AppLabel,
                content = "Véhicule récupéré. Le chrono a démarré !",
                icon = Config.AppIcon
            })

            exports["lb-phone"]:SendCustomAppMessage("old_rentVehicle", {
                type = "vehicleClaimed",
                duration = currentRental.duration
            })
        end
    end
end)

CreateThread(function()
    while true do
        Wait(1000)
        local playerPed = PlayerPedId()
        local pos = GetEntityCoords(playerPed)

        local payload = {
            type = "updatePositions",
            playerPos = { x = pos.x, y = pos.y }
        }

        if currentRental and DoesEntityExist(currentRental.vehicle) then
            local vPos = GetEntityCoords(currentRental.vehicle)
            payload.vehiclePos = { x = vPos.x, y = vPos.y }
            payload.claimed = currentRental.claimed
        end

        exports["lb-phone"]:SendCustomAppMessage("old_rentVehicle", payload)
    end
end)

RegisterNetEvent("old_rentVehicle:rentalCancelled", function(reason)
    RemoveDeliveryBlip()
    currentRental = nil
    courierPed = nil
    courierVeh = nil

    exports["lb-phone"]:SendNotification({
        title = Config.AppLabel,
        content = reason,
        icon = Config.AppIcon
    })

    exports["lb-phone"]:SendCustomAppMessage("old_rentVehicle", {
        type = "rentalExpired"
    })
end)

RegisterNetEvent("old_rentVehicle:rentalExpired", function()
    RemoveDeliveryBlip()
    currentRental = nil
    courierPed = nil
    courierVeh = nil

    exports["lb-phone"]:SendNotification({
        title = Config.AppLabel,
        content = "Votre période de location est expirée. Le véhicule a été rapatrié.",
        icon = Config.AppIcon
    })

    exports["lb-phone"]:SendCustomAppMessage("old_rentVehicle", {
        type = "rentalExpired"
    })
end)

AddEventHandler("onResourceStop", function(resource)
    if resource == GetCurrentResourceName() then
        RemoveDeliveryBlip()
    end
end)
