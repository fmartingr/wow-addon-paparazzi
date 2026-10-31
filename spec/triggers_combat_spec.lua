local wow = require("helpers.wow")

local function enable(key)
	PaparazziDB.settings.triggers[key].enabled = true
end

describe("combat triggers", function()
	local function setup()
		_G.GetDifficultyInfo = function()
			return "Heroic"
		end
	end

	it("records a boss kill", function()
		wow.boot({ setup = setup })
		local record = wow.take("ENCOUNTER_END", 2820, "Boss", 15, 20, 1)
		assert.same({
			encounterID = 2820,
			encounterName = "Boss",
			difficultyID = 15,
			difficultyName = "Heroic",
			groupSize = 20,
		}, record.events[1].data)
	end)

	it("makes no boss kill shot for a wipe", function()
		wow.boot({ setup = setup })
		assert.is_nil(wow.take("ENCOUNTER_END", 2820, "Boss", 15, 20, 0))
	end)

	it("records a wipe when enabled", function()
		wow.boot({ setup = setup })
		enable("bossWipe")
		local record = wow.take("ENCOUNTER_END", 2820, "Boss", 15, 20, 0)
		assert.equal("bossWipe", record.events[1].trigger)
	end)

	it("merges ENCOUNTER_END and BOSS_KILL into one image", function()
		wow.boot({ setup = setup })
		wow.fire("ENCOUNTER_END", 1, "Boss", 15, 20, 1)
		local record = wow.take("BOSS_KILL", 1, "Boss")
		assert.equal(1, wow.screenshots)
		assert.is_nil(record and record.events[3])
	end)

	it("records a world boss only outside an instance", function()
		wow.boot({})
		assert.same({ encounterID = 5, encounterName = "W" }, wow.take("BOSS_KILL", 5, "W").events[1].data)
		wow.instance = { name = "Raid", type = "raid", difficultyID = 1, instanceID = 9 }
		assert.is_nil(wow.take("BOSS_KILL", 5, "W"))
	end)

	it("records two events for a boss kill in the world", function()
		wow.boot({ setup = setup })
		wow.fire("ENCOUNTER_END", 1, "Boss", 15, 20, 1)
		local record = wow.take("BOSS_KILL", 1, "Boss")
		assert.equal(2, #record.events)
	end)

	describe("challengeMode", function()
		it("reads the Retail completion table", function()
			wow.boot({
				setup = function()
					_G.C_ChallengeMode = {
						GetChallengeCompletionInfo = function()
							return {
								mapChallengeModeID = 3,
								level = 12,
								time = 1500,
								onTime = true,
								keystoneUpgradeLevels = 2,
								practiceRun = false,
							}
						end,
						GetMapUIInfo = function()
							return "Dungeon"
						end,
					}
				end,
			})
			local data = wow.take("CHALLENGE_MODE_COMPLETED").events[1].data
			assert.equal(3, data.mapChallengeModeID)
			assert.equal("Dungeon", data.mapName)
			assert.equal(12, data.level)
			assert.is_true(data.onTime)
			assert.is_false(data.practiceRun)
		end)

		it("reads the MoP completion returns", function()
			wow.boot({
				build = { "5.5.4", "1", "d", 50504 },
				setup = function()
					_G.C_ChallengeMode = {
						GetCompletionInfo = function()
							return 4, 7, 900, true, 1
						end,
					}
				end,
			})
			local data = wow.take("CHALLENGE_MODE_COMPLETED").events[1].data
			assert.equal(4, data.mapChallengeModeID)
			assert.equal(7, data.level)
		end)

		it("falls back to empty data", function()
			wow.boot({})
			assert.same({}, wow.take("CHALLENGE_MODE_COMPLETED").events[1].data)
			wow.boot({
				setup = function()
					_G.C_ChallengeMode = {}
				end,
			})
			assert.same({}, wow.take("CHALLENGE_MODE_COMPLETED").events[1].data)
			wow.boot({
				setup = function()
					_G.C_ChallengeMode = {
						GetCompletionInfo = function() end,
					}
				end,
			})
			assert.same({}, wow.take("CHALLENGE_MODE_COMPLETED").events[1].data)
		end)

		it("records a new record when enabled", function()
			wow.boot({})
			enable("challengeModeRecord")
			assert.same(
				{ mapID = 1, timeMS = 2, medal = 3 },
				wow.take("CHALLENGE_MODE_NEW_RECORD", 1, 2, 3).events[1].data
			)
		end)
	end)

	describe("delve", function()
		it("shoots only when the delve is complete", function()
			local complete = false
			wow.boot({
				setup = function()
					_G.C_PartyInfo = {
						IsDelveComplete = function()
							return complete
						end,
					}
					_G.C_ScenarioInfo = {
						GetScenarioInfo = function()
							return { name = "Fungal Folly" }
						end,
					}
				end,
			})
			enable("delve")
			assert.is_nil(wow.take("SCENARIO_COMPLETED"))
			complete = true
			assert.same({ scenarioName = "Fungal Folly" }, wow.take("SCENARIO_COMPLETED").events[1].data)
		end)

		it("makes no shot without the delve API", function()
			wow.boot({})
			enable("delve")
			assert.is_nil(wow.take("SCENARIO_COMPLETED"))
		end)
	end)

	it("shoots on death after 0.5 s when enabled", function()
		wow.boot({})
		assert.is_nil(wow.take("PLAYER_DEAD"))
		enable("death")
		local before = wow.clock
		assert.same({}, wow.take("PLAYER_DEAD").events[1].data)
		assert.is_true(wow.clock - before >= 0.5)
	end)
end)
