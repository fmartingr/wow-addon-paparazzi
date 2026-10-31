local _, ns = ...

local Triggers = ns.Triggers
local lookup = Triggers.Lookup

Triggers.Register({
	key = "pvpMatch",
	label = "PvP match won",
	category = "pvp",
	events = function(flavor)
		if flavor == "retail" then
			return { "PVP_MATCH_COMPLETE" }
		end
		return { "UPDATE_BATTLEFIELD_STATUS" }
	end,
	flavors = "all",
	default = { enabled = false, delay = 1.0 },
	handle = function(state, event, winner, duration)
		local myTeam = GetBattlefieldArenaFaction and GetBattlefieldArenaFaction()
		if event == "PVP_MATCH_COMPLETE" then
			if winner == nil or winner ~= myTeam then
				return nil
			end
			return {
				winner = winner,
				duration = duration,
				isArena = C_PvP and C_PvP.IsArena and lookup(C_PvP.IsArena) or false,
			}
		end

		local result = GetBattlefieldWinner and GetBattlefieldWinner()
		if result == nil then
			state.latched = false
			return nil
		end
		if state.latched then
			return nil
		end
		state.latched = true
		if result ~= myTeam then
			return nil
		end
		return { winner = result, isArena = IsActiveBattlefieldArena and IsActiveBattlefieldArena() or false }
	end,
})

Triggers.Register({
	key = "duel",
	label = "Duel finished",
	category = "pvp",
	events = { "DUEL_FINISHED" },
	flavors = "all",
	default = { enabled = false, delay = 1.0 },
	handle = function()
		return {}
	end,
})
