local wow = require("helpers.wow")

describe("Debouncer", function()
	local ns, fired, cap, debouncer

	before_each(function()
		wow.reset()
		ns = wow.load_addon({ "src/Debouncer.lua" })
		fired, cap = {}, 5
		debouncer = ns.Debouncer.New({
			now = GetTime,
			schedule = C_Timer.NewTimer,
			cap = function()
				return cap
			end,
			onFire = function(batch)
				fired[#fired + 1] = { at = GetTime(), batch = batch }
			end,
		})
	end)

	it("fires one event after its delay", function()
		debouncer:Add("a", 2)
		assert.is_true(debouncer:IsPending())
		wow.advance(1.9)
		assert.equal(0, #fired)
		wow.advance(0.1)
		assert.equal(1, #fired)
		assert.equal(2, fired[1].at)
		assert.is_false(debouncer:IsPending())
	end)

	it("merges a later event that is due earlier", function()
		debouncer:Add("level", 2)
		wow.advance(0.3)
		debouncer:Add("achievement", 1)
		wow.advance(5)
		assert.equal(1, #fired)
		assert.equal(2, fired[1].at)
		assert.same({ "level", "achievement" }, fired[1].batch.events)
	end)

	it("extends the due time up to the cap", function()
		debouncer:Add("level", 2)
		wow.advance(1.5)
		debouncer:Add("mount", 4)
		wow.advance(10)
		assert.equal(5, fired[1].at)
	end)

	it("keeps the first delay when it exceeds the cap", function()
		cap = 2
		debouncer:Add("a", 5)
		wow.advance(10)
		assert.equal(5, fired[1].at)
	end)

	it("starts a new batch after the fire", function()
		debouncer:Add("a", 1)
		wow.advance(1)
		debouncer:Add("b", 1)
		wow.advance(1)
		assert.equal(2, #fired)
		assert.same({ "b" }, fired[2].batch.events)
	end)

	it("merges two events in the same frame at delay 0", function()
		debouncer:Add("a", 0)
		debouncer:Add("b", 0)
		wow.advance(0)
		assert.equal(1, #fired)
		assert.equal(2, #fired[1].batch.events)
	end)

	it("uses the new cap on the next Add", function()
		debouncer:Add("a", 1)
		cap = 2
		wow.advance(0.5)
		debouncer:Add("b", 4)
		wow.advance(10)
		assert.equal(2, fired[1].at)
	end)

	it("drops the pending batch on Reset", function()
		debouncer:Add("a", 1)
		debouncer:Reset()
		wow.advance(5)
		assert.equal(0, #fired)
		assert.is_false(debouncer:IsPending())
	end)
end)
