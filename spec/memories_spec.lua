local wow = require("helpers.wow")

describe("Memories notes", function()
	local calls, ns

	local sample = { file = "WoWScrnShot_010126_120000.jpg", events = { { trigger = "levelUp" } } }

	local function stub(fn)
		calls = {}
		_G.Memories = {
			RecordScreenshot = function(...)
				calls[#calls + 1] = { ... }
				if fn then
					return fn(...)
				end
				return true
			end,
		}
	end

	before_each(function()
		ns = wow.boot()
	end)

	after_each(function()
		_G.Memories = nil
	end)

	describe("SendNote", function()
		for _, value in ipairs({ 5, true }) do
			it("does not raise when Memories is a " .. type(value), function()
				_G.Memories = value
				assert.has_no.errors(function()
					ns.SendNote(sample)
				end)
			end)
		end

		it("makes no call when Memories is a string with a RecordScreenshot method", function()
			calls = {}
			local strings = getmetatable("").__index
			strings.RecordScreenshot = function(...)
				calls[#calls + 1] = { ... }
			end
			_G.Memories = "text"
			local ok = pcall(ns.SendNote, sample)
			strings.RecordScreenshot = nil
			assert.is_true(ok)
			assert.equal(0, #calls)
		end)

		it("makes no call when RecordScreenshot is a callable table", function()
			calls = {}
			_G.Memories = {
				RecordScreenshot = setmetatable({}, {
					__call = function(...)
						calls[#calls + 1] = { ... }
					end,
				}),
			}
			ns.SendNote(sample)
			assert.equal(0, #calls)
		end)

		it("does not raise when the API raises", function()
			stub(function()
				error("boom")
			end)
			assert.has_no.errors(function()
				ns.SendNote(sample)
			end)
			assert.equal(1, #calls)
		end)
	end)

	it("sends the trigger label and the stored file name", function()
		stub()
		local record = wow.take("PLAYER_LEVEL_UP", 80)
		assert.equal(1, #calls)
		assert.same({ "Paparazzi", "Level up", record.file }, calls[1])
		assert.equal(PaparazziDB.captures[1].file, calls[1][3])
	end)

	it("makes no call when the setting is off", function()
		stub()
		PaparazziDB.settings.memories = false
		assert.is_table(wow.take("PLAYER_LEVEL_UP", 80))
		assert.equal(0, #calls)
	end)

	it("stores the capture when Memories is missing", function()
		_G.Memories = nil
		assert.is_table(wow.take("PLAYER_LEVEL_UP", 80))
		assert.same({}, wow.chat)
	end)

	it("keeps the capture and prints nothing when the API raises", function()
		stub(function()
			error("boom")
		end)
		assert.is_table(wow.take("PLAYER_LEVEL_UP", 80))
		assert.equal(1, #calls)
		assert.equal(1, #PaparazziDB.captures)
		assert.same({}, wow.chat)
	end)

	it("keeps the capture and prints nothing when the API returns false", function()
		stub(function()
			return false, "rate limit"
		end)
		assert.is_table(wow.take("PLAYER_LEVEL_UP", 80))
		assert.equal(1, #PaparazziDB.captures)
		assert.same({}, wow.chat)
	end)

	it("makes no call for a manual screenshot", function()
		stub()
		wow.fire("SCREENSHOT_SUCCEEDED")
		assert.equal(0, #calls)
	end)

	it("makes no call for a failed screenshot", function()
		stub()
		wow.fire("PLAYER_LEVEL_UP", 80)
		wow.advance(1)
		assert.equal(1, wow.screenshots)
		wow.fire("SCREENSHOT_FAILED")
		assert.equal(0, #calls)
	end)

	it("makes no call for a late success after the await timeout", function()
		stub()
		wow.fire("PLAYER_LEVEL_UP", 80)
		wow.advance(1)
		assert.equal(1, wow.screenshots)
		wow.advance(3)
		wow.fire("SCREENSHOT_SUCCEEDED")
		assert.equal(0, #calls)
	end)
end)
