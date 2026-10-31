local _, ns = ...

ns.Triggers.Register({
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
