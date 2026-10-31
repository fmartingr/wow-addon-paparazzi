PaparazziDB = {
	["schema"] = 1,
	["settings"] = {
		["enabled"] = true,
		["debounceCap"] = 5,
		["retention"] = 1000,
		["triggers"] = {
			["levelUp"] = {
				["enabled"] = true,
				["delay"] = 1,
			},
		},
	},
	["captures"] = {
		{
			["schema"] = 1,
			["file"] = "WoWScrnShot_103126_201502.jpg",
			["time"] = "2026-10-31T20:15:02+01:00",
			["unix"] = 1793474102,
			["utcOffset"] = 3600,
			["addonVersion"] = "v0.1.0",
			["game"] = {
				["flavor"] = "retail",
				["version"] = "12.1.5",
				["build"] = "70688",
				["interface"] = 120105,
			},
			["character"] = {
				["name"] = "Kaelys",
				["realm"] = "Ragnaros",
				["class"] = "MAGE",
				["level"] = 80,
			},
			["location"] = {
				["zone"] = "Dornogal",
				["subzone"] = "",
				["mapID"] = 2339,
			},
			["events"] = {
				{
					["trigger"] = "levelUp",
					["name"] = "PLAYER_LEVEL_UP",
					["unix"] = 1793474100,
					["data"] = {
						["level"] = 80,
					},
				}, -- [1]
			},
		}, -- [1]
		{
			["schema"] = 1,
			["file"] = "WoWScrnShot_103126_201602.jpg",
			["time"] = "2026-10-31T20:16:02+01:00",
			["unix"] = 1793474162,
			["utcOffset"] = 3600,
			["events"] = {
				{
					["trigger"] = "mount",
					["name"] = "NEW_MOUNT_ADDED",
					["unix"] = 1793474160,
					["data"] = {
						["mountID"] = 12,
						["mountName"] = "Drake",
					},
				}, -- [1]
			},
		}, -- [2]
		{
			["schema"] = 1,
			["file"] = "WoWScrnShot_103126_202502.jpg",
			["time"] = "2026-10-31T20:25:02+01:00",
			["unix"] = 1793474702,
			["utcOffset"] = 3600,
			["events"] = {},
		}, -- [3]
		{
			["schema"] = 2,
			["file"] = "WoWScrnShot_103126_203002.jpg",
			["unix"] = 1793475002,
			["utcOffset"] = 3600,
		}, -- [4]
		{
			["schema"] = 1,
			["file"] = "../evil.jpg",
			["unix"] = 1793475002,
			["utcOffset"] = 3600,
		}, -- [5]
	},
	["visited"] = {},
}
