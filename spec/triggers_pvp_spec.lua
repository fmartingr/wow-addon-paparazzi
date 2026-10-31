local wow = require("helpers.wow")

local function enable()
	PaparazziDB.settings.triggers.pvpMatch.enabled = true
end

local function frames_listening(event)
	local count = 0
	for _, frame in ipairs(wow.frames) do
		if frame.events[event] then
			count = count + 1
		end
	end
	return count
end

describe("pvp triggers", function()
	describe("pvpMatch on Retail", function()
		local function setup()
			_G.GetBattlefieldArenaFaction = function()
				return 1
			end
			_G.C_PvP = {
				IsArena = function()
					return true
				end,
			}
		end

		it("records a win", function()
			wow.boot({ setup = setup })
			enable()
			local record = wow.take("PVP_MATCH_COMPLETE", 1, 300)
			assert.same({ winner = 1, duration = 300, isArena = true }, record.events[1].data)
		end)

		it("makes no shot for a loss", function()
			wow.boot({ setup = setup })
			enable()
			assert.is_nil(wow.take("PVP_MATCH_COMPLETE", 0, 300))
		end)

		it("makes no shot for a draw with no winner", function()
			wow.boot({ setup = setup })
			enable()
			assert.is_nil(wow.take("PVP_MATCH_COMPLETE", nil, 300))
		end)

		it("registers PVP_MATCH_COMPLETE only", function()
			wow.boot({ setup = setup })
			assert.equal(1, frames_listening("PVP_MATCH_COMPLETE"))
			assert.equal(0, frames_listening("UPDATE_BATTLEFIELD_STATUS"))
		end)
	end)

	describe("pvpMatch on Era", function()
		local winner
		local function setup()
			winner = nil
			_G.GetBattlefieldArenaFaction = function()
				return 0
			end
			_G.GetBattlefieldWinner = function()
				return winner
			end
			_G.IsActiveBattlefieldArena = function()
				return false
			end
		end
		local build = { "1.15.9", "1", "d", 11509 }

		it("registers UPDATE_BATTLEFIELD_STATUS only", function()
			wow.boot({ build = build, setup = setup })
			assert.equal(0, frames_listening("PVP_MATCH_COMPLETE"))
			assert.equal(1, frames_listening("UPDATE_BATTLEFIELD_STATUS"))
		end)

		it("shoots once for repeated status updates after a win", function()
			wow.boot({ build = build, setup = setup })
			enable()
			assert.is_nil(wow.take("UPDATE_BATTLEFIELD_STATUS"))
			winner = 0
			local record = wow.take("UPDATE_BATTLEFIELD_STATUS")
			assert.same({ winner = 0, isArena = false }, record.events[1].data)
			assert.is_nil(wow.take("UPDATE_BATTLEFIELD_STATUS"))
			assert.is_nil(wow.take("UPDATE_BATTLEFIELD_STATUS"))
		end)

		it("resets the latch when the winner is nil again", function()
			wow.boot({ build = build, setup = setup })
			enable()
			winner = 0
			assert.is_not_nil(wow.take("UPDATE_BATTLEFIELD_STATUS"))
			winner = nil
			wow.take("UPDATE_BATTLEFIELD_STATUS")
			winner = 0
			assert.is_not_nil(wow.take("UPDATE_BATTLEFIELD_STATUS"))
		end)

		it("makes no shot for a loss", function()
			wow.boot({ build = build, setup = setup })
			enable()
			winner = 1
			assert.is_nil(wow.take("UPDATE_BATTLEFIELD_STATUS"))
		end)
	end)

	it("records a finished duel when enabled", function()
		wow.boot({})
		PaparazziDB.settings.triggers.duel.enabled = true
		assert.same({}, wow.take("DUEL_FINISHED").events[1].data)
	end)
end)
