local _, ns = ...

local Triggers = ns.Triggers
local lookup = Triggers.Lookup

local function achievementInfo(id)
	local _, name, points, _, _, _, _, _, _, _, _, isGuild = lookup(GetAchievementInfo, id)
	return name, points, isGuild
end

local function achievementData(id, wantGuild)
	local name, points, isGuild = achievementInfo(id)
	if (isGuild and true or false) ~= wantGuild then
		return nil
	end
	return { achievementID = id, achievementName = name, points = points }
end

Triggers.Register({
	key = "levelUp",
	label = "Level up",
	category = "progress",
	events = { "PLAYER_LEVEL_UP" },
	flavors = "all",
	default = { enabled = true, delay = 1.0 },
	handle = function(_, _, level)
		return { level = level }
	end,
})

Triggers.Register({
	key = "achievement",
	label = "Achievement",
	category = "progress",
	events = { "ACHIEVEMENT_EARNED" },
	flavors = { "retail", "mists", "titan", "forever" },
	default = { enabled = true, delay = 1.0 },
	handle = function(_, _, id, alreadyEarned)
		if alreadyEarned then
			return nil
		end
		return achievementData(id, false)
	end,
})

Triggers.Register({
	key = "guildAchievement",
	label = "Guild achievement",
	category = "progress",
	events = { "ACHIEVEMENT_EARNED" },
	flavors = { "retail", "mists" },
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, id, alreadyEarned)
		if alreadyEarned then
			return nil
		end
		return achievementData(id, true)
	end,
})

Triggers.Register({
	key = "criteria",
	label = "Achievement criteria",
	category = "progress",
	events = { "CRITERIA_EARNED" },
	flavors = { "retail", "mists", "titan", "forever" },
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, achievementID, description)
		local name = achievementInfo(achievementID)
		return { achievementID = achievementID, achievementName = name, description = description }
	end,
})

local function factionName(id)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local data = lookup(C_Reputation.GetFactionDataByID, id)
		return data and data.name
	end
	return (lookup(GetFactionInfoByID, id))
end

local function factionStanding(id)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		if C_GossipInfo and C_GossipInfo.GetFriendshipReputation then
			local friendship = lookup(C_GossipInfo.GetFriendshipReputation, id)
			if friendship and friendship.friendshipFactionID and friendship.friendshipFactionID > 0 then
				return friendship.reactionThreshold
			end
		end
		local data = lookup(C_Reputation.GetFactionDataByID, id)
		return data and data.reaction
	end
	local _, _, standing = lookup(GetFactionInfoByID, id)
	return standing
end

local function eachFaction(fn)
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		for i = 1, C_Reputation.GetNumFactions() do
			local data = C_Reputation.GetFactionDataByIndex(i)
			if data and data.factionID and data.factionID > 0 then
				fn(data.factionID)
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, GetNumFactions() do
			local factionID = select(14, GetFactionInfo(i))
			if factionID and factionID > 0 then
				fn(factionID)
			end
		end
	end
end

Triggers.Register({
	key = "reputation",
	label = "Reputation rank",
	category = "progress",
	events = { "PLAYER_ENTERING_WORLD", "FACTION_STANDING_CHANGED" },
	flavors = "all",
	default = { enabled = true, delay = 1.0 },
	handle = function(state, event, factionID)
		state.snapshot = state.snapshot or {}
		if event == "PLAYER_ENTERING_WORLD" then
			state.snapshot = {}
			eachFaction(function(id)
				state.snapshot[id] = factionStanding(id)
			end)
			return nil
		end

		local new = factionStanding(factionID)
		local old = state.snapshot[factionID]
		if new then
			state.snapshot[factionID] = new
		end
		if not new or not old or new <= old then
			return nil
		end
		return {
			factionID = factionID,
			factionName = factionName(factionID),
			oldStanding = old,
			newStanding = new,
			standingLabel = _G["FACTION_STANDING_LABEL" .. new],
		}
	end,
})

Triggers.Register({
	key = "renown",
	label = "Renown level",
	category = "progress",
	events = { "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" },
	flavors = { "retail" },
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, majorFactionID, newLevel, oldLevel)
		if not (newLevel and oldLevel and newLevel > oldLevel) then
			return nil
		end
		local info = C_MajorFactions and lookup(C_MajorFactions.GetMajorFactionData, majorFactionID)
		return {
			majorFactionID = majorFactionID,
			factionName = info and info.name,
			newRenownLevel = newLevel,
			oldRenownLevel = oldLevel,
		}
	end,
})

Triggers.Register({
	key = "recipe",
	label = "New recipe",
	category = "progress",
	events = { "NEW_RECIPE_LEARNED" },
	flavors = "all",
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, recipeID)
		local name
		if C_Spell and C_Spell.GetSpellName then
			name = lookup(C_Spell.GetSpellName, recipeID)
		else
			name = lookup(GetSpellInfo, recipeID)
		end
		return { recipeID = recipeID, recipeName = name }
	end,
})

Triggers.Register({
	key = "travelersLog",
	label = "Traveler's Log activity",
	category = "progress",
	events = { "PERKS_ACTIVITY_COMPLETED" },
	flavors = { "retail", "forever" },
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, perksActivityID)
		local info = C_PerksActivities and lookup(C_PerksActivities.GetPerksActivityInfo, perksActivityID)
		return { perksActivityID = perksActivityID, activityName = info and info.activityName }
	end,
})

local PROFESSION_STEP = 75

local function professionRanks()
	local ranks = {}
	local inProfessions = false
	for i = 1, GetNumSkillLines() do
		local name, header, _, rank = GetSkillLineInfo(i)
		if header then
			inProfessions = name == TRADE_SKILLS or name == SECONDARY_SKILLS
		elseif inProfessions and name and type(rank) == "number" then
			ranks[name] = rank
		end
	end
	return ranks
end

Triggers.Register({
	key = "professionMilestone",
	label = "Profession milestone",
	category = "progress",
	events = { "PLAYER_ENTERING_WORLD", "SKILL_LINES_CHANGED" },
	flavors = { "era", "tbc", "titan", "forever" },
	requires = function()
		return type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function"
	end,
	default = { enabled = true, delay = 1.0 },
	handle = function(state, event)
		local snapshot = state.snapshot or {}
		state.snapshot = snapshot
		local ranks = professionRanks()
		if event == "PLAYER_ENTERING_WORLD" then
			for name, rank in pairs(ranks) do
				if snapshot[name] == nil then
					snapshot[name] = rank
				end
			end
			return nil
		end

		local names = {}
		for name in pairs(ranks) do
			names[#names + 1] = name
		end
		table.sort(names)
		local result
		for _, name in ipairs(names) do
			local before, after = snapshot[name], ranks[name]
			snapshot[name] = after
			if not result and before and math.floor(after / PROFESSION_STEP) > math.floor(before / PROFESSION_STEP) then
				result = {
					skillName = name,
					rank = after,
					milestone = math.floor(after / PROFESSION_STEP) * PROFESSION_STEP,
				}
			end
		end
		return result
	end,
})
