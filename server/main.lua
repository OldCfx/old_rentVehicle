local ActiveRentals = {}

local webhook = "" -- ajoute ton webhook ici pour les logs Discord

local function sendDiscordLog(title, fields, color)
    if not webhook or webhook == '' then return end

    local description = ""
    if type(fields) == "table" then
        for _, data in ipairs(fields) do
            description = description .. ("**%s :** %s\n"):format(data.key, data.value)
        end
    else
        description = fields
    end

    local embed = {
        {
            ["color"] = color or 5763719,
            ["title"] = title,
            ["description"] = description,
            ["footer"] = {
                ["text"] = os.date('%d/%m/%Y %H:%M:%S')
            }
        }
    }

    PerformHttpRequest(webhook, function(err, text, headers) end, 'POST',
        json.encode({ username = 'OldXBlunt', embeds = embed, avatar_url = 'https://i.goopics.net/sek245.png' }),
        { ['Content-Type'] = 'application/json' })
end

local function AddBankTransaction(source, amount, title)
    local phoneNumber = exports["lb-phone"]:GetEquippedPhoneNumber(source)
    if phoneNumber then
        exports["lb-phone"]:AddTransaction(phoneNumber, -amount, title, Config.AppIcon)
    end
end

ESX.RegisterServerCallback("old_rentVehicle:canOrder", function(source, cb, data)
    local xPlayer = ESX.GetPlayerFromId(source)
    if not xPlayer then
        cb(false, "Joueur introuvable")
        return
    end

    if ActiveRentals[source] then
        cb(false, "Vous avez déjà une location en cours")
        return
    end

    local phoneNumber = exports["lb-phone"]:GetEquippedPhoneNumber(source)
    if not phoneNumber then
        cb(false, "Aucun numéro de téléphone détecté")
        return
    end

    local vehicleData = Config.Fleet[data.model]
    if not vehicleData then
        cb(false, "Modèle invalide")
        return
    end

    local durationMinutes = tonumber(data.duration) or 15
    local calculatedPrice = tonumber(data.price) or vehicleData.pricePer15

    local playerMoney = xPlayer.getMoney()
    local playerBank = xPlayer.getAccount("bank").money

    if playerBank >= calculatedPrice then
        xPlayer.removeAccountMoney("bank", calculatedPrice)
    elseif playerMoney >= calculatedPrice then
        xPlayer.removeMoney(calculatedPrice)
    else
        cb(false, "Fonds insuffisants")
        return
    end

    AddBankTransaction(source, calculatedPrice, "Location " .. vehicleData.name)

    ActiveRentals[source] = {
        model = data.model,
        duration = durationMinutes,
        price = calculatedPrice,
        startTime = nil,
        endTime = nil,
        phoneNumber = phoneNumber,
        unclaimedTimeout = os.time() + 300,
        vehicleNetId = nil,
        pedNetId = nil,
        claimed = false
    }

    sendDiscordLog("Nouvelle location de véhicule", {
        { key = "Joueur",              value = GetPlayerName(source) .. " (" .. source .. ")" },
        { key = "Numéro de téléphone", value = phoneNumber },
        { key = "Véhicule",            value = vehicleData.name .. " (" .. data.model .. ")" },
        { key = "Durée",               value = durationMinutes .. " minutes" },
        { key = "Prix payé",           value = calculatedPrice .. "$" }
    }, 5763719)

    cb(true)
end)

ESX.RegisterServerCallback("old_rentVehicle:getActiveRental", function(source, cb)
    local rental = ActiveRentals[source]
    if not rental then
        cb(nil)
        return
    end

    local remaining = 0
    if rental.claimed and rental.endTime then
        remaining = math.max(0, rental.endTime - os.time())
    elseif not rental.claimed and rental.unclaimedTimeout then
        remaining = math.max(0, rental.unclaimedTimeout - os.time())
    end

    cb({
        model = rental.model,
        duration = rental.duration,
        price = rental.price,
        claimed = rental.claimed,
        remainingSeconds = remaining,
        vehicleNetId = rental.vehicleNetId
    })
end)

ESX.RegisterServerCallback("old_rentVehicle:extendRental", function(source, cb, extraMinutes)
    local xPlayer = ESX.GetPlayerFromId(source)
    local rental = ActiveRentals[source]

    if not xPlayer or not rental or not rental.claimed then
        cb(false, "Aucune location active à prolonger")
        return
    end

    local vehicleData = Config.Fleet[rental.model]
    if not vehicleData then
        cb(false, "Véhicule introuvable")
        return
    end

    local minutes = tonumber(extraMinutes) or 15
    local extraPrice = math.round(vehicleData.pricePer15 * (minutes / 15))

    local playerMoney = xPlayer.getMoney()
    local playerBank = xPlayer.getAccount("bank").money

    if playerBank >= extraPrice then
        xPlayer.removeAccountMoney("bank", extraPrice)
    elseif playerMoney >= extraPrice then
        xPlayer.removeMoney(extraPrice)
    else
        cb(false, "Fonds insuffisants pour prolonger")
        return
    end

    AddBankTransaction(source, extraPrice, "Prolongation " .. vehicleData.name)

    rental.endTime = rental.endTime + (minutes * 60)
    rental.price = rental.price + extraPrice

    sendDiscordLog("Prolongation de location de véhicule", {
        { key = "Joueur",              value = GetPlayerName(source) .. " (" .. source .. ")" },
        { key = "Numéro de téléphone", value = rental.phoneNumber },
        { key = "Véhicule",            value = vehicleData.name .. " (" .. rental.model .. ")" },
        { key = "Durée",               value = minutes .. " minutes" },
        { key = "Prix payé",           value = extraPrice .. "$" }
    }, 16705372)

    cb(true, {
        addedSeconds = minutes * 60,
        newTotalPrice = rental.price
    })
end)

RegisterNetEvent("old_rentVehicle:registerEntities", function(vehNet, pedNet)
    local src = source
    local rental = ActiveRentals[src]
    if not rental then return end

    rental.vehicleNetId = vehNet
    rental.pedNetId = pedNet

    local vehEntity = NetworkGetEntityFromNetworkId(vehNet)
    if DoesEntityExist(vehEntity) then
        Entity(vehEntity).state:set("rentPhoneNumber", rental.phoneNumber, true)
    end
end)

RegisterNetEvent("old_rentVehicle:claimVehicle", function()
    local src = source
    local rental = ActiveRentals[src]
    if not rental or rental.claimed then return end

    rental.claimed = true
    rental.unclaimedTimeout = nil
    rental.startTime = os.time()
    rental.endTime = os.time() + (rental.duration * 60)

    local pedEntity = NetworkGetEntityFromNetworkId(rental.pedNetId)
    if DoesEntityExist(pedEntity) then
        DeleteEntity(pedEntity)
    end

    sendDiscordLog("Véhicule récupré", {
        { key = "Joueur",              value = GetPlayerName(src) .. " (" .. src .. ")" },
        { key = "Numéro de téléphone", value = rental.phoneNumber },
        { key = "Véhicule",            value = rental.model },
        { key = "Durée",               value = rental.duration .. " minutes" },
        { key = "Prix payé",           value = rental.price .. "$" }
    }, 5763719)
end)

RegisterNetEvent("old_rentVehicle:cancelRental", function()
    local src = source
    local rental = ActiveRentals[src]
    if not rental then return end

    if rental.vehicleNetId then
        local vehEntity = NetworkGetEntityFromNetworkId(rental.vehicleNetId)
        if DoesEntityExist(vehEntity) then
            DeleteEntity(vehEntity)
        end
    end

    if rental.pedNetId then
        local pedEntity = NetworkGetEntityFromNetworkId(rental.pedNetId)
        if DoesEntityExist(pedEntity) then
            DeleteEntity(pedEntity)
        end
    end

    ActiveRentals[src] = nil
end)

CreateThread(function()
    while true do
        Wait(2500)
        local currentTime = os.time()

        for src, rental in pairs(ActiveRentals) do
            if rental.vehicleNetId then
                local veh = NetworkGetEntityFromNetworkId(rental.vehicleNetId)
                if not DoesEntityExist(veh) then
                    if rental.pedNetId then
                        local ped = NetworkGetEntityFromNetworkId(rental.pedNetId)
                        if DoesEntityExist(ped) then DeleteEntity(ped) end
                    end

                    TriggerClientEvent("old_rentVehicle:rentalCancelled", src,
                        "Le véhicule n'existe plus. Location annulée.")

                    sendDiscordLog("Location de véhicule annulé", {
                        { key = "Joueur",              value = GetPlayerName(src) .. " (" .. src .. ")" },
                        { key = "Numéro de téléphone", value = rental.phoneNumber },
                        { key = "Véhicule",            value = rental.model },
                        { key = "Durée",               value = rental.duration .. " minutes" },
                        { key = "Prix payé",           value = rental.price .. "$" },
                        { key = "Raison",              value = "Le véhicule n'existe plus" }
                    }, 15548997)
                    ActiveRentals[src] = nil
                    goto continue
                end
            end

            if not rental.claimed and rental.unclaimedTimeout and currentTime >= rental.unclaimedTimeout then
                if rental.vehicleNetId then
                    local veh = NetworkGetEntityFromNetworkId(rental.vehicleNetId)
                    if DoesEntityExist(veh) then DeleteEntity(veh) end
                end

                if rental.pedNetId then
                    local ped = NetworkGetEntityFromNetworkId(rental.pedNetId)
                    if DoesEntityExist(ped) then DeleteEntity(ped) end
                end

                TriggerClientEvent("old_rentVehicle:rentalCancelled", src,
                    "Délai de récupération de 5 minutes dépassé. Véhicule annulé.")

                sendDiscordLog("Location de véhicule annulé", {
                    { key = "Joueur",              value = GetPlayerName(src) .. " (" .. src .. ")" },
                    { key = "Numéro de téléphone", value = rental.phoneNumber },
                    { key = "Véhicule",            value = rental.model },
                    { key = "Durée",               value = rental.duration .. " minutes" },
                    { key = "Prix payé",           value = rental.price .. "$" },
                    { key = "Raison",              value = "Délai de récupération de 5 minutes dépassé" }
                }, 15548997)
                ActiveRentals[src] = nil
                goto continue
            end

            if rental.claimed and rental.endTime and currentTime >= rental.endTime then
                if rental.vehicleNetId then
                    local veh = NetworkGetEntityFromNetworkId(rental.vehicleNetId)
                    if DoesEntityExist(veh) then DeleteEntity(veh) end
                end

                sendDiscordLog("Location de véhicule expirée", {
                    { key = "Joueur",              value = GetPlayerName(src) .. " (" .. src .. ")" },
                    { key = "Numéro de téléphone", value = rental.phoneNumber },
                    { key = "Véhicule",            value = rental.model },
                    { key = "Durée",               value = rental.duration .. " minutes" },
                    { key = "Prix payé",           value = rental.price .. "$" },
                    { key = "Raison",              value = "Délai de location dépassé" }
                }, 15548997)
                TriggerClientEvent("old_rentVehicle:rentalExpired", src)
                ActiveRentals[src] = nil
            end

            ::continue::
        end
    end
end)

AddEventHandler("playerDropped", function()
    local src = source
    local rental = ActiveRentals[src]
    if not rental then return end

    if rental.vehicleNetId then
        local veh = NetworkGetEntityFromNetworkId(rental.vehicleNetId)
        if DoesEntityExist(veh) then DeleteEntity(veh) end
    end
    if rental.pedNetId then
        local ped = NetworkGetEntityFromNetworkId(rental.pedNetId)
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end

    ActiveRentals[src] = nil
end)
