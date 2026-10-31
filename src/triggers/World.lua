local _, ns = ...

local Triggers = ns.Triggers
local lookup = Triggers.Lookup

Triggers.Register({
	key = "trade",
	label = "Trade",
	category = "world",
	events = { "TRADE_SHOW", "TRADE_ACCEPT_UPDATE" },
	flavors = "all",
	default = { enabled = false, delay = 0.0 },
	handle = function(state, event, playerAccepted, targetAccepted)
		if event == "TRADE_SHOW" then
			state.shot = false
			return nil
		end
		if state.shot or (playerAccepted == 1) == (targetAccepted == 1) then
			return nil
		end
		state.shot = true
		return { playerAccepted = playerAccepted, targetAccepted = targetAccepted, tradeTarget = UnitName("NPC") }
	end,
})

Triggers.Register({
	key = "login",
	label = "Login",
	category = "world",
	events = { "PLAYER_ENTERING_WORLD" },
	flavors = "all",
	default = { enabled = false, delay = 5.0 },
	handle = function(_, _, isInitialLogin)
		if not isInitialLogin then
			return nil
		end
		return { isInitialLogin = true }
	end,
})

local function zoneMapID(mapID)
	if MapUtil and MapUtil.GetMapParentInfo and Enum and Enum.UIMapType then
		local parent = lookup(MapUtil.GetMapParentInfo, mapID, Enum.UIMapType.Zone, true)
		if parent and parent.mapID then
			return parent.mapID
		end
	end
	return mapID
end

-- Returns the location key, the zone map ID, the instance ID, and the instance type.
local function locationKey()
	local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	if IsInInstance() then
		local _, instanceType, _, _, _, _, _, instanceID = GetInstanceInfo()
		return "i:" .. tostring(instanceID), mapID, instanceID, instanceType
	end
	if not mapID then
		return nil
	end
	if MapUtil and MapUtil.GetMapParentInfo then
		return "z:" .. zoneMapID(mapID), mapID
	end
	return "n:" .. tostring(GetZoneText()), mapID
end

local function visitedTable()
	local key = UnitName("player") .. "-" .. GetRealmName()
	PaparazziDB.visited[key] = PaparazziDB.visited[key] or {}
	return PaparazziDB.visited[key]
end

Triggers.Register({
	key = "firstVisit",
	label = "First visit to a zone",
	category = "world",
	events = { "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" },
	flavors = "all",
	default = { enabled = false, delay = 2.0 },
	handle = function(_, event)
		local key, mapID, instanceID, instanceType = locationKey()
		if not key then
			return nil
		end
		local visited = visitedTable()
		local isNew = not visited[key]
		visited[key] = true
		if event == "PLAYER_ENTERING_WORLD" or not isNew then
			return nil
		end
		return { zoneName = GetZoneText(), mapID = mapID, instanceID = instanceID, instanceType = instanceType }
	end,
})
