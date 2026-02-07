local treeStates = {}
local axeUsage = {}


function ProcessGrowthFinish(id)
    treeStates[id].state = 'standing'
    treeStates[id].endTime = 0
    MySQL.update('UPDATE royal_lumberjack_trees SET state = ?, endTime = 0 WHERE id = ?', {'standing', id})
    TriggerClientEvent('royal_lumberjack:client:syncTreeStanding', -1, id)
end

MySQL.ready(function()
    -- Ensure tables exist
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `royal_lumberjack_trees` (
            `id` int(11) NOT NULL,
            `state` varchar(50) DEFAULT 'standing',
            `endTime` bigint(20) DEFAULT 0,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `royal_lumberjack_leaderboard` (
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) DEFAULT NULL,
            `wood_collected` int(11) DEFAULT 0,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])

    local results = MySQL.query.await('SELECT * FROM royal_lumberjack_trees')
    local dbStates = {}
    for i=1, #results do dbStates[results[i].id] = results[i] end
    
    for i = 1, #Config.TreeLocations do
        if dbStates[i] then
            treeStates[i] = { state = dbStates[i].state, endTime = tonumber(dbStates[i].endTime) }
            if treeStates[i].state == 'growing' then
                local remaining = treeStates[i].endTime - (os.time() * 1000)
                if remaining > 0 then
                    SetTimeout(remaining, function() ProcessGrowthFinish(i) end)
                else
                    ProcessGrowthFinish(i)
                end
            end
        else
            treeStates[i] = { state = 'standing', endTime = 0 }
            MySQL.insert('INSERT INTO royal_lumberjack_trees (id, state, endTime) VALUES (?, ?, ?)', {i, 'standing', 0})
        end
    end
end)

local function IsNear(src, coords, dist)
    local pPed = GetPlayerPed(src)
    if not DoesEntityExist(pPed) then return false end
    return #(GetEntityCoords(pPed) - coords) < (dist or 15.0)
end

RegisterNetEvent('royal_lumberjack:server:checkJobToggle', function()
    local src = source
    TriggerClientEvent('royal_lumberjack:client:confirmJobToggle', src, true)
end)

RegisterNetEvent('royal_lumberjack:server:buyItem', function(index)
    local src = source
    local p = exports.qbx_core:GetPlayer(src)
    local itemData = Config.ShopItems[index]
    
    if not p or not itemData or not IsNear(src, vec3(Config.JobLocation.x, Config.JobLocation.y, Config.JobLocation.z)) then return end
    
    if p.Functions.RemoveMoney('cash', itemData.price, "royal_lumberjack-shop") then 
        exports.ox_inventory:AddItem(src, itemData.item, 1) 
        TriggerClientEvent('ox_lib:notify', src, {title = 'წარმატებული შესყიდვა', description = itemData.label .. ' შეძენილია', type = 'success'})
    else
        TriggerClientEvent('ox_lib:notify', src, {title = 'შეცდომა', description = 'არ გაქვს საკმარისი თანხა', type = 'error'})
    end
end)

RegisterNetEvent('royal_lumberjack:server:requestUI', function()
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player then return end
    local data = MySQL.single.await('SELECT wood_collected FROM royal_lumberjack_leaderboard WHERE citizenid = ?', {player.PlayerData.citizenid})
    local leaderboard = MySQL.query.await('SELECT name, wood_collected FROM royal_lumberjack_leaderboard ORDER BY wood_collected DESC LIMIT 5')
    TriggerClientEvent('royal_lumberjack:client:openUI', src, { 
        wood = data and data.wood_collected or 0, 
        leaderboard = leaderboard or {},
        shopItems = Config.ShopItems
    })
end)

-- დანარჩენი server/main.lua კოდი (startChop, processTimber და ა.შ.) უცვლელია...
RegisterNetEvent('royal_lumberjack:server:startChop', function(id)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player or not treeStates[id] or treeStates[id].state ~= 'standing' then return end
    if not IsNear(src, Config.TreeLocations[id]) then return end
    treeStates[id].state = 'falling'
    MySQL.update('UPDATE royal_lumberjack_trees SET state = "falling" WHERE id = ?', {id})
    TriggerClientEvent('royal_lumberjack:client:syncTreeFall', -1, id)
end)

RegisterNetEvent('royal_lumberjack:server:processTimber', function(id)
    local src = source
    local player = exports.qbx_core:GetPlayer(src)
    if not player or not treeStates[id] or treeStates[id].state ~= 'falling' then return end
    if not IsNear(src, Config.TreeLocations[id]) then return end
    local citizenId = player.PlayerData.citizenid
    
    -- Durability Logic using ox_inventory metadata
    local items = exports.ox_inventory:Search(src, 'slots', Config.AxeItemName)
    local axeItem = nil
    
    -- Find the first available axe
    if items then
        for _, item in pairs(items) do
            axeItem = item
            break
        end
    end

    if not axeItem then
        return TriggerClientEvent('ox_lib:notify', src, {title = 'შეცდომა', description = 'ნაჯახი არ გაქვს!', type = 'error'})
    end

    local durability = (axeItem.metadata and axeItem.metadata.durability) or 100
    local degradation = (100 / Config.AxeMaxUses)
    durability = durability - degradation

    if durability <= 0 then
        exports.ox_inventory:RemoveItem(src, Config.AxeItemName, 1, nil, axeItem.slot)
        TriggerClientEvent('ox_lib:notify', src, {title = 'ნაჯახი გატყდა!', type = 'error'})
        TriggerClientEvent('royal_lumberjack:client:updateAxeUsage', src, 0)
    else
        exports.ox_inventory:SetMetadata(src, axeItem.slot, { durability = durability })
        -- Convert durability back to "uses left" for UI
        local usesLeft = math.floor((durability / 100) * Config.AxeMaxUses)
        TriggerClientEvent('royal_lumberjack:client:updateAxeUsage', src, usesLeft)
    end

    treeStates[id].state = 'growing'
    treeStates[id].endTime = (os.time() * 1000) + Config.GrowthTime
    MySQL.update('UPDATE royal_lumberjack_trees SET state = "growing", endTime = ? WHERE id = ?', {treeStates[id].endTime, id})
    
    if exports.ox_inventory:CanCarryItem(src, 'wood', 3) then
        exports.ox_inventory:AddItem(src, 'wood', 3)
        local fullName = player.PlayerData.charinfo.firstname .. " " .. player.PlayerData.charinfo.lastname
        MySQL.prepare('INSERT INTO royal_lumberjack_leaderboard (citizenid, name, wood_collected) VALUES (?, ?, 3) ON DUPLICATE KEY UPDATE wood_collected = wood_collected + 3', {player.PlayerData.citizenid, fullName})
    else
        TriggerClientEvent('ox_lib:notify', src, {title = 'ინვენტარი სავსეა', description = 'ვერ აიღე ხე', type = 'error'})
    end

    TriggerClientEvent('royal_lumberjack:client:syncTreeGrowth', -1, id)
    SetTimeout(Config.GrowthTime, function() ProcessGrowthFinish(id) end)
end)

RegisterNetEvent('royal_lumberjack:server:requestTreeSync', function() TriggerClientEvent('royal_lumberjack:client:syncAllTrees', source, treeStates) end)