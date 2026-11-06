local _, ns = ...

local Triggers = ns.Triggers
local lookup = Triggers.Lookup

local function encounterData(encounterID, encounterName, difficultyID, groupSize)
	local difficultyName
	if GetDifficultyInfo then
		difficultyName = lookup(GetDifficultyInfo, difficultyID)
	end
	return {
		encounterID = encounterID,
		encounterName = encounterName,
		difficultyID = difficultyID,
		difficultyName = difficultyName,
		groupSize = groupSize,
	}
end

Triggers.Register({
	key = "bossKill",
	label = "Boss kill",
	category = "combat",
	events = { "ENCOUNTER_END" },
	flavors = "all",
	default = { enabled = true, delay = 1.0 },
	handle = function(_, _, encounterID, encounterName, difficultyID, groupSize, success)
		if success ~= 1 then
			return nil
		end
		return encounterData(encounterID, encounterName, difficultyID, groupSize)
	end,
})

Triggers.Register({
	key = "bossWipe",
	label = "Boss wipe",
	category = "combat",
	events = { "ENCOUNTER_END" },
	flavors = "all",
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, encounterID, encounterName, difficultyID, groupSize, success)
		if success ~= 0 then
			return nil
		end
		return encounterData(encounterID, encounterName, difficultyID, groupSize)
	end,
})

Triggers.Register({
	key = "worldBoss",
	label = "World boss kill",
	category = "combat",
	events = { "BOSS_KILL" },
	flavors = { "retail", "mists", "titan" },
	default = { enabled = true, delay = 1.0 },
	handle = function(_, _, encounterID, encounterName)
		if IsInInstance() then
			return nil
		end
		return { encounterID = encounterID, encounterName = encounterName }
	end,
})

local function mapName(mapID)
	if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
		return (lookup(C_ChallengeMode.GetMapUIInfo, mapID))
	end
end

Triggers.Register({
	key = "challengeMode",
	label = "Mythic+ completed",
	category = "combat",
	events = { "CHALLENGE_MODE_COMPLETED" },
	flavors = { "retail", "mists" },
	default = { enabled = true, delay = 1.0 },
	handle = function()
		if not C_ChallengeMode then
			return {}
		end
		if C_ChallengeMode.GetChallengeCompletionInfo then
			local info = lookup(C_ChallengeMode.GetChallengeCompletionInfo)
			if type(info) == "table" then
				return {
					mapChallengeModeID = info.mapChallengeModeID,
					mapName = mapName(info.mapChallengeModeID),
					level = info.level,
					time = info.time,
					onTime = info.onTime,
					keystoneUpgradeLevels = info.keystoneUpgradeLevels,
					practiceRun = info.practiceRun,
				}
			end
		end
		if C_ChallengeMode.GetCompletionInfo then
			local mapID, level, time, onTime, upgrades = lookup(C_ChallengeMode.GetCompletionInfo)
			if mapID then
				return {
					mapChallengeModeID = mapID,
					mapName = mapName(mapID),
					level = level,
					time = time,
					onTime = onTime,
					keystoneUpgradeLevels = upgrades,
				}
			end
		end
		return {}
	end,
})

Triggers.Register({
	key = "challengeModeRecord",
	label = "Mythic+ new record",
	category = "combat",
	events = { "CHALLENGE_MODE_NEW_RECORD" },
	flavors = { "retail", "mists" },
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, mapID, timeMS, medal)
		return { mapID = mapID, timeMS = timeMS, medal = medal }
	end,
})

Triggers.Register({
	key = "delve",
	label = "Delve completed",
	category = "combat",
	events = { "SCENARIO_COMPLETED" },
	flavors = { "retail" },
	default = { enabled = false, delay = 1.0 },
	handle = function()
		if not (C_PartyInfo and C_PartyInfo.IsDelveComplete and C_PartyInfo.IsDelveComplete()) then
			return nil
		end
		local info = C_ScenarioInfo and lookup(C_ScenarioInfo.GetScenarioInfo)
		return { scenarioName = info and info.name }
	end,
})

Triggers.Register({
	key = "death",
	label = "Death",
	category = "combat",
	events = { "PLAYER_DEAD" },
	flavors = "all",
	default = { enabled = false, delay = 0.5 },
	handle = function()
		return {}
	end,
})

-- Matches the threshold of the red low health warning in the default UI.
local LOW_HEALTH = 20

Triggers.Register({
	key = "closeCall",
	label = "Close call",
	category = "combat",
	events = { "UNIT_HEALTH", "PLAYER_DEAD" },
	unit = "player",
	flavors = "all",
	default = { enabled = false, delay = 1.0 },
	handle = function(state, event, unit)
		if event == "PLAYER_DEAD" then
			state.low = nil
			return nil
		end
		if unit ~= "player" then
			return nil
		end
		if UnitIsDeadOrGhost and UnitIsDeadOrGhost("player") then
			state.low = nil
			return nil
		end
		local health, max = ns.Safe(UnitHealth("player")), ns.Safe(UnitHealthMax("player"))
		if type(health) ~= "number" or type(max) ~= "number" or max <= 0 then
			return nil
		end
		local percent = health * 100 / max
		if percent < LOW_HEALTH then
			state.low = math.min(state.low or percent, percent)
			return nil
		end
		local lowest = state.low
		state.low = nil
		if lowest then
			return { lowestPercent = math.floor(lowest), healthPercent = math.floor(percent) }
		end
	end,
})
