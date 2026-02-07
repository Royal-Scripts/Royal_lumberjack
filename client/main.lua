local spawnedTrees = {}
local treeBlips = {}
local growthPoints = {}
local onDuty = false
local pendingToggle = false
local jobPed = nil
local lastWaveTime = 0

-- ხმის მაქსიმალური რადიუსი (20 მეტრი)
local SOUND_RADIUS = 20.0

-- დამხმარე ფუნქცია ხმის სიმძლავრის გამოსათვლელად მანძილის მიხედვით
local function GetDistanceVolume(coords, baseVolume)
    local playerCoords = GetEntityCoords(cache.ped)
    local distance = #(playerCoords - coords)
    
    if distance > SOUND_RADIUS then
        return 0.0
    end
    
    -- ხმის სიმძლავრის კლება მანძილის პროპორციულად (Linear Roll-off)
    -- math.max უზრუნველყოფს რომ რადიუსში ყოფნისას ხმა ყოველთვის ისმოდეს
    local multiplier = 1.0 - (distance / SOUND_RADIUS)
    return math.max(0.05, baseVolume * multiplier)
end

-- ოპტიმიზირებული 3D ტექსტი
local function DrawText3D(coords, text)
    local onScreen, _x, _y = World3dToScreen2d(coords.x, coords.y, coords.z)
    if onScreen then
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        BeginTextCommandDisplayText("STRING")
        SetTextCentre(1)
        AddTextComponentSubstringPlayerName(text)
        EndTextCommandDisplayText(_x, _y)
        local factor = (string.len(text)) / 370
        DrawRect(_x, _y + 0.0125, 0.015 + factor, 0.03, 15, 23, 42, 200)
    end
end

-- ხის წაქცევის ანიმაცია (რადიუსის კონტროლით)
local function AnimateTreeFall(entity)
    if not DoesEntityExist(entity) then return end
    SetEntityCollision(entity, false, true)
    local rotation = GetEntityRotation(entity, 2)
    local coords = GetEntityCoords(entity)
    
    -- ხმის სიმძლავრე გაზრდილია უკეთესი აღქმისთვის
    local dynamicVolume = GetDistanceVolume(coords, 0.8)
    if dynamicVolume > 0 then
        SendNUIMessage({ action = "playSound", file = "woodfall", volume = dynamicVolume, loop = false })
    end
    
    local startTime = GetGameTimer()
    CreateThread(function()
        while GetGameTimer() - startTime < 5000 do
            local progress = (GetGameTimer() - startTime) / 5000
            local currentX = rotation.x + (85.0 * (progress * progress))
            if DoesEntityExist(entity) then
                SetEntityRotation(entity, currentX, rotation.y, rotation.z, 2, true)
                SetEntityCoords(entity, coords.x, coords.y, coords.z, false, false, false, false)
            else return end
            Wait(0)
        end
        if DoesEntityExist(entity) then
            SetEntityRotation(entity, rotation.x + 85.0, rotation.y, rotation.z, 2, true)
            SetEntityCollision(entity, true, true)
            FreezeEntityPosition(entity, true) 
        end
    end)
end

-- ხის სპაუნის მენეჯერი
function SpawnTree(id, model, state)
    if spawnedTrees[id] and DoesEntityExist(spawnedTrees[id]) then 
        exports.ox_target:removeLocalEntity(spawnedTrees[id])
        DeleteEntity(spawnedTrees[id]) 
        spawnedTrees[id] = nil
    end

    if not lib.requestModel(model, 5000) then return end
    
    local coords = Config.TreeLocations[id]
    local tree = CreateObject(model, coords.x, coords.y, coords.z - 1.1, false, false, false)
    
    SetEntityAsMissionEntity(tree, true, true)
    FreezeEntityPosition(tree, true)
    spawnedTrees[id] = tree
    SetModelAsNoLongerNeeded(model)

    if not treeBlips[id] then
        local tBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(tBlip, 836)
        SetBlipScale(tBlip, 0.5)
        SetBlipAsShortRange(tBlip, true) 
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("ხე")
        EndTextCommandSetBlipName(tBlip)
        treeBlips[id] = tBlip
    end

    if state == 'standing' then
        exports.ox_target:addLocalEntity(tree, {
            { 
                label = 'მოჭრა', 
                icon = 'fa-solid fa-axe', 
                distance = 2.0, -- ინტერაქციის მანძილი 2 მეტრი
                onSelect = function() ChopLogic(id) end 
            }
        })
    elseif state == 'falling' then
        SetEntityRotation(tree, 85.0, 0.0, GetEntityHeading(tree), 2, true)
        exports.ox_target:addLocalEntity(tree, {
            { 
                label = 'დამუშავება', 
                icon = 'fa-solid fa-scissors', 
                distance = 2.0, -- ინტერაქციის მანძილი 2 მეტრი
                onSelect = function() ProcessLogic(id) end 
            }
        })
    end
end

-- ზრდის ტაიმერის მართვა
function CreateGrowthPoint(id, endTime)
    if growthPoints[id] then growthPoints[id]:remove() end
    local coords = Config.TreeLocations[id]
    
    growthPoints[id] = lib.points.new({
        coords = vec3(coords.x, coords.y, coords.z + 1.5),
        distance = 7.0,
        nearby = function(self)
            local timeLeft = math.max(0, math.floor((endTime - GetGameTimer()) / 1000))
            if timeLeft > 0 then
                DrawText3D(self.coords, string.format("~w~Growing:~b~ %02d:%02d", math.floor(timeLeft / 60), timeLeft % 60))
            else
                self:remove()
                growthPoints[id] = nil
            end
        end
    })
end

-- ჭრის ლოგიკა (ხმის რადიუსით - მაქს 20 მეტრი)
function ChopLogic(id)
    if not onDuty then return lib.notify({type = 'error', description = 'ჯერ დაიწყე მუშაობა!'}) end
    if GetSelectedPedWeapon(cache.ped) ~= GetHashKey(Config.AxeItemName) then return lib.notify({type = 'error', description = 'დაიჭირე ნაჯახი!'}) end
    
    local treeCoords = Config.TreeLocations[id]
    
    if lib.skillCheck({'easy', 'medium'}, {'w', 'a', 's', 'd'}) then
        -- საბაზისო ხმა გაზრდილია 0.6-მდე უკეთესი სმენადობისთვის
        local dynamicVolume = GetDistanceVolume(treeCoords, 0.6)
        if dynamicVolume > 0 then
            SendNUIMessage({ action = "playSound", file = "woodcut", volume = dynamicVolume, loop = true })
        end

        if lib.progressBar({
            duration = 15000, 
            label = 'ხე იჭრება...',
            disable = { move = true, car = true, combat = true },
            anim = { dict = 'melee@large_wpn@streamed_core', clip = 'ground_attack_on_spot', flags = 1 }
        }) then
            SendNUIMessage({ action = "stopSound" })
            TriggerServerEvent('royal_lumberjack:server:startChop', id)
        else
            SendNUIMessage({ action = "stopSound" })
        end
    else
        lib.notify({type = 'error', description = 'აცაცი!'})
    end
end

-- დამუშავება (ხმის რადიუსით - მაქს 20 მეტრი)
function ProcessLogic(id)
    local treeCoords = Config.TreeLocations[id]
    
    -- საბაზისო ხმა გაზრდილია 0.6-მდე
    local dynamicVolume = GetDistanceVolume(treeCoords, 0.6)
    if dynamicVolume > 0 then
        SendNUIMessage({ action = "playSound", file = "woodcut", volume = dynamicVolume, loop = true })
    end

    if lib.progressBar({ 
        duration = 15000, 
        label = 'ხის დამუშავება...', 
        disable = { move = true },
        anim = { dict = 'melee@large_wpn@streamed_core', clip = 'ground_attack_on_spot', flags = 1 } 
    }) then
        SendNUIMessage({ action = "stopSound" })
        TriggerServerEvent('royal_lumberjack:server:processTimber', id)
    else
        SendNUIMessage({ action = "stopSound" })
    end
end

-- ინიციალიზაცია
CreateThread(function()
    for name, data in pairs(Config.Blips) do
        local blip = AddBlipForCoord(data.coords.x, data.coords.y, data.coords.z)
        SetBlipSprite(blip, data.sprite)
        SetBlipScale(blip, data.scale)
        SetBlipColour(blip, data.color)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString(data.label)
        EndTextCommandSetBlipName(blip)
    end

    lib.requestModel(Config.PedModel)
    jobPed = CreatePed(0, Config.PedModel, Config.JobLocation.x, Config.JobLocation.y, Config.JobLocation.z, Config.JobLocation.w, false, false)
    FreezeEntityPosition(jobPed, true)
    SetEntityInvincible(jobPed, true)
    SetBlockingOfNonTemporaryEvents(jobPed, true)
    exports.ox_target:addLocalEntity(jobPed, {
        { label = 'მენიუ', icon = 'fa-solid fa-tree-city', onSelect = function() TriggerServerEvent('royal_lumberjack:server:requestUI') end }
    })
    
    lib.points.new({
        coords = vec3(Config.JobLocation.x, Config.JobLocation.y, Config.JobLocation.z),
        distance = 15,
        nearby = function(self)
            DrawMarker(27, Config.JobLocation.x, Config.JobLocation.y, Config.JobLocation.z + 0.05, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 0, 191, 255, 150, false, false, 2, nil, nil, false)
            
            if self.currentDistance < 6.0 and GetGameTimer() - lastWaveTime > 15000 then 
                lastWaveTime = GetGameTimer()
                if jobPed and DoesEntityExist(jobPed) then
                    CreateThread(function()
                        lib.requestAnimDict("anim@mp_player_intupperwave")
                        TaskPlayAnim(jobPed, "anim@mp_player_intupperwave", "idle_a_fp", 8.0, -8.0, 3000, 49, 0, false, false, false)
                        
                        -- NPC-ის ხმის რადიუსი
                        local dynamicVolume = GetDistanceVolume(GetEntityCoords(jobPed), 0.7)
                        if dynamicVolume > 0 then
                            SendNUIMessage({ action = "playSound", file = "pedvoice", volume = dynamicVolume, loop = false, extension = "ogg" })
                        end
                        
                        Wait(3000)
                        StopAnimTask(jobPed, "anim@mp_player_intupperwave", "idle_a_fp", 1.0)
                    end)
                end
            end
        end
    })
    
    TriggerServerEvent('royal_lumberjack:server:requestTreeSync')
end)

-- სინქრონიზაციის ივენთები
RegisterNetEvent('royal_lumberjack:client:syncAllTrees', function(states)
    local serverNow = GetCloudTimeAsInt() * 1000
    for id, data in pairs(states) do
        if data.state == 'standing' then 
            SpawnTree(id, Config.Tree.model, 'standing')
        elseif data.state == 'falling' then 
            SpawnTree(id, Config.Tree.model, 'falling')
        elseif data.state == 'growing' then 
            SpawnTree(id, Config.Tree.stump, 'growing')
            if data.endTime and data.endTime > serverNow then
                CreateGrowthPoint(id, GetGameTimer() + (data.endTime - serverNow))
            end
        end
    end
end)

RegisterNetEvent('royal_lumberjack:client:syncTreeFall', function(id)
    if spawnedTrees[id] then
        AnimateTreeFall(spawnedTrees[id])
        exports.ox_target:removeLocalEntity(spawnedTrees[id])
        exports.ox_target:addLocalEntity(spawnedTrees[id], {
            { 
                label = 'დამუშავება', 
                icon = 'fa-solid fa-scissors', 
                distance = 1.2, -- ინტერაქციის მანძილი 2 მეტრი
                onSelect = function() ProcessLogic(id) end 
            }
        })
    end
end)

RegisterNetEvent('royal_lumberjack:client:syncTreeGrowth', function(id)
    CreateGrowthPoint(id, GetGameTimer() + Config.GrowthTime)
    SpawnTree(id, Config.Tree.stump, 'growing')
end)

RegisterNetEvent('royal_lumberjack:client:syncTreeStanding', function(id)
    if growthPoints[id] then growthPoints[id]:remove(); growthPoints[id] = nil end
    SpawnTree(id, Config.Tree.model, 'standing')
end)

RegisterNetEvent('royal_lumberjack:client:openUI', function(data)
    SendNUIMessage({ 
        action = "openUI", 
        wood = data.wood, 
        leaderboard = data.leaderboard, 
        onDuty = onDuty,
        shopItems = data.shopItems 
    })
    SetNuiFocus(true, true)
end)

RegisterNetEvent('royal_lumberjack:client:updateAxeUsage', function(remaining)
    SendNUIMessage({ action = "updateAxe", remaining = remaining })
end)

RegisterNetEvent('royal_lumberjack:client:confirmJobToggle', function(allowed)
    pendingToggle = false
    if allowed then
        onDuty = not onDuty
        LocalPlayer.state:set('isRoyalLumberjack', onDuty, true)
        SendNUIMessage({ action = "updateOnDuty", state = onDuty })
    end
end)

RegisterNUICallback('toggleJob', function(_, cb)
    if pendingToggle then return cb('pending') end
    pendingToggle = true
    TriggerServerEvent('royal_lumberjack:server:checkJobToggle')
    cb('ok')
end)

RegisterNUICallback('buyItem', function(data, cb)
    TriggerServerEvent('royal_lumberjack:server:buyItem', data.index)
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb) SetNuiFocus(false, false); cb('ok') end)
RegisterNUICallback('claimReward', function(_, cb) TriggerServerEvent('royal_lumberjack:server:claimReward'); cb('ok') end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, entity in pairs(spawnedTrees) do if DoesEntityExist(entity) then DeleteEntity(entity) end end
end)