local wow = require("helpers.wow")

local ERA = { "1.15.9", "1", "d", 11509 }
local MISTS = { "5.5.4", "1", "d", 50504 }

local function enable(key, enabled)
	PaparazziDB.settings.triggers[key].enabled = enabled
end

describe("progress triggers", function()
	describe("achievement", function()
		local function setup()
			_G.GetAchievementInfo = function(id)
				local guild = id >= 1000
				return id, "Ach" .. id, 10, true, 1, 1, 26, "d", 0, 0, "", guild
			end
		end

		it("records a personal achievement", function()
			wow.boot({ setup = setup })
			local record = wow.take("ACHIEVEMENT_EARNED", 500, false)
			assert.same({ achievementID = 500, achievementName = "Ach500", points = 10 }, record.events[1].data)
		end)

		it("skips an achievement that was earned before", function()
			wow.boot({ setup = setup })
			assert.is_nil(wow.take("ACHIEVEMENT_EARNED", 500, true))
		end)

		it("treats a nil alreadyEarned as false", function()
			wow.boot({ setup = setup })
			assert.is_not_nil(wow.take("ACHIEVEMENT_EARNED", 500, nil))
		end)

		it("makes no personal shot for a guild achievement", function()
			wow.boot({ setup = setup })
			assert.is_nil(wow.take("ACHIEVEMENT_EARNED", 1000, false))
		end)

		it("records a guild achievement when enabled", function()
			wow.boot({ setup = setup })
			enable("guildAchievement", true)
			local record = wow.take("ACHIEVEMENT_EARNED", 1000, false)
			assert.equal("guildAchievement", record.events[1].trigger)
			assert.equal(1, #record.events)
		end)

		it("still shoots when the lookup API is missing", function()
			wow.boot({})
			local record = wow.take("ACHIEVEMENT_EARNED", 500, false)
			assert.equal(500, record.events[1].data.achievementID)
			assert.is_nil(record.events[1].data.achievementName)
		end)

		it("is not available on Era or TBC", function()
			for _, interface in ipairs({ 11509, 20506 }) do
				local ns = wow.boot({ build = { "1", "1", "d", interface } })
				for _, def in ipairs(ns.Triggers.Available(ns.GetFlavor())) do
					assert.not_equal("achievement", def.key)
				end
			end
		end)
	end)

	describe("criteria", function()
		it("records the description", function()
			wow.boot({
				setup = function()
					_G.GetAchievementInfo = function(id)
						return id, "Ach" .. id
					end
				end,
			})
			enable("criteria", true)
			local record = wow.take("CRITERIA_EARNED", 5, "Do a thing")
			assert.same(
				{ achievementID = 5, achievementName = "Ach5", description = "Do a thing" },
				record.events[1].data
			)
		end)
	end)

	describe("reputation", function()
		local standings

		local function setup()
			_G.FACTION_STANDING_LABEL5 = "Honored"
			_G.GetNumFactions = function()
				return 2
			end
			_G.GetFactionInfo = function(i)
				return "F" .. i, "", standings[i], 0, 0, 0, false, false, false, false, false, false, false, i
			end
			_G.GetFactionInfoByID = function(id)
				return "F" .. id, "", standings[id]
			end
		end

		before_each(function()
			standings = { 4, 4 }
		end)

		it("shoots when the standing rises", function()
			wow.boot({ build = ERA, setup = setup })
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			standings[1] = 5
			local record = wow.take("FACTION_STANDING_CHANGED", 1, 100)
			assert.same(
				{ factionID = 1, factionName = "F1", oldStanding = 4, newStanding = 5, standingLabel = "Honored" },
				record.events[1].data
			)
		end)

		it("does not shoot when the standing falls", function()
			wow.boot({ build = ERA, setup = setup })
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			standings[1] = 3
			assert.is_nil(wow.take("FACTION_STANDING_CHANGED", 1, -100))
		end)

		it("does not shoot for a faction missing from the snapshot", function()
			wow.boot({ build = ERA, setup = setup })
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			standings[3] = 5
			assert.is_nil(wow.take("FACTION_STANDING_CHANGED", 3, 100))
			standings[3] = 6
			assert.is_not_nil(wow.take("FACTION_STANDING_CHANGED", 3, 100))
		end)

		it("makes no shot on PLAYER_ENTERING_WORLD", function()
			wow.boot({ build = ERA, setup = setup })
			assert.is_nil(wow.take("PLAYER_ENTERING_WORLD", false, true))
		end)

		it("reads Retail standings through C_Reputation", function()
			wow.boot({
				setup = function()
					_G.C_Reputation = {
						GetNumFactions = function()
							return 1
						end,
						GetFactionDataByIndex = function()
							return { factionID = 7, reaction = standings[1] }
						end,
						GetFactionDataByID = function(id)
							return { name = "R" .. id, reaction = standings[1] }
						end,
					}
				end,
			})
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			standings[1] = 5
			local record = wow.take("FACTION_STANDING_CHANGED", 7, 1)
			assert.equal("R7", record.events[1].data.factionName)
		end)

		it("uses the friendship threshold for friendship factions", function()
			local threshold = 1
			wow.boot({
				setup = function()
					_G.C_Reputation = {
						GetNumFactions = function()
							return 1
						end,
						GetFactionDataByIndex = function()
							return { factionID = 9 }
						end,
						GetFactionDataByID = function()
							return { name = "Friend", reaction = 4 }
						end,
					}
					_G.C_GossipInfo = {
						GetFriendshipReputation = function()
							return { friendshipFactionID = 9, reactionThreshold = threshold }
						end,
					}
				end,
			})
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			threshold = 2
			assert.is_not_nil(wow.take("FACTION_STANDING_CHANGED", 9, 1))
		end)
	end)

	describe("renown", function()
		local function setup()
			_G.C_MajorFactions = {
				GetMajorFactionData = function()
					return { name = "Council" }
				end,
			}
		end

		it("shoots when the level rises", function()
			wow.boot({ setup = setup })
			enable("renown", true)
			local record = wow.take("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2590, 5, 4)
			assert.same(
				{ majorFactionID = 2590, factionName = "Council", newRenownLevel = 5, oldRenownLevel = 4 },
				record.events[1].data
			)
		end)

		it("does not shoot when the level does not rise", function()
			wow.boot({ setup = setup })
			enable("renown", true)
			assert.is_nil(wow.take("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2590, 4, 4))
			assert.is_nil(wow.take("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2590, 3, 4))
		end)
	end)

	describe("recipe", function()
		it("records the spell name with C_Spell", function()
			wow.boot({
				setup = function()
					_G.C_Spell = {
						GetSpellName = function()
							return "Brew"
						end,
					}
				end,
			})
			enable("recipe", true)
			assert.same({ recipeID = 3, recipeName = "Brew" }, wow.take("NEW_RECIPE_LEARNED", 3).events[1].data)
		end)

		it("falls back to GetSpellInfo", function()
			wow.boot({
				build = ERA,
				setup = function()
					_G.GetSpellInfo = function()
						return "Old Brew"
					end
				end,
			})
			enable("recipe", true)
			assert.equal("Old Brew", wow.take("NEW_RECIPE_LEARNED", 3).events[1].data.recipeName)
		end)
	end)

	describe("travelersLog", function()
		it("records the activity name", function()
			wow.boot({
				setup = function()
					_G.C_PerksActivities = {
						GetPerksActivityInfo = function()
							return { activityName = "Kill things" }
						end,
					}
				end,
			})
			enable("travelersLog", true)
			assert.same(
				{ perksActivityID = 8, activityName = "Kill things" },
				wow.take("PERKS_ACTIVITY_COMPLETED", 8).events[1].data
			)
		end)

		it("is not available on MoP", function()
			local ns = wow.boot({ build = MISTS })
			for _, def in ipairs(ns.Triggers.Available("mists")) do
				assert.not_equal("travelersLog", def.key)
			end
		end)
	end)
end)
