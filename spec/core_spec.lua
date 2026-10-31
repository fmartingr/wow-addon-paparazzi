local wow = require("helpers.wow")

describe("Core", function()
	local ns

	local function boot(saved)
		wow.reset()
		_G.PaparazziDB = saved
		ns = wow.load_addon(wow.toc_files())
		wow.fire("ADDON_LOADED", "Paparazzi")
	end

	it("creates PaparazziDB on ADDON_LOADED", function()
		boot(nil)
		assert.equal(1, PaparazziDB.schema)
		assert.is_table(PaparazziDB.settings.triggers.levelUp)
	end)

	it("ignores ADDON_LOADED of another addon", function()
		wow.reset()
		ns = wow.load_addon(wow.toc_files())
		wow.fire("ADDON_LOADED", "Other")
		assert.is_nil(PaparazziDB)
	end)

	it("takes one screenshot and records it for a level up", function()
		boot(nil)
		wow.fire("PLAYER_LEVEL_UP", 80)
		wow.advance(0.9)
		assert.equal(0, wow.screenshots)
		wow.advance(0.1)
		assert.equal(1, wow.screenshots)
		wow.fire("SCREENSHOT_SUCCEEDED")
		assert.equal(1, #PaparazziDB.captures)
		local record = PaparazziDB.captures[1]
		assert.equal("levelUp", record.events[1].trigger)
		assert.equal("PLAYER_LEVEL_UP", record.events[1].name)
		assert.same({ level = 80 }, record.events[1].data)
	end)

	it("merges events that happen together", function()
		boot(nil)
		ns.Triggers.Register({
			key = "extra",
			label = "Extra",
			category = "progress",
			events = { "EXTRA_EVENT" },
			flavors = "all",
			default = { enabled = true, delay = 1.0 },
			handle = function()
				return {}
			end,
		})
		PaparazziDB.settings.triggers.extra = { enabled = true, delay = 1 }
		ns.Triggers.Refresh()
		wow.fire("PLAYER_LEVEL_UP", 80)
		ns.Triggers.Dispatch("EXTRA_EVENT")
		wow.advance(1)
		wow.fire("SCREENSHOT_SUCCEEDED")
		assert.equal(1, wow.screenshots)
		assert.equal(2, #PaparazziDB.captures[1].events)
	end)

	it("makes one test capture with /paparazzi test", function()
		boot(nil)
		SlashCmdList.PAPARAZZI("test")
		wow.advance(0)
		wow.fire("SCREENSHOT_SUCCEEDED")
		assert.equal(1, #PaparazziDB.captures)
		assert.equal("test", PaparazziDB.captures[1].events[1].trigger)
	end)

	it("prints usage for other arguments without a settings panel", function()
		boot(nil)
		ns.Settings = nil
		SlashCmdList.PAPARAZZI("")
		assert.matches("usage", wow.chat[1])
	end)

	it("opens the settings panel when it exists", function()
		boot(nil)
		local opened = false
		ns.Settings = {
			Open = function()
				opened = true
			end,
		}
		SlashCmdList.PAPARAZZI("  ")
		assert.is_true(opened)
	end)

	it("captures nothing when the master switch is off", function()
		boot({ settings = { enabled = false } })
		wow.fire("PLAYER_LEVEL_UP", 80)
		wow.advance(5)
		assert.equal(0, wow.screenshots)
	end)

	it("ignores a manual screenshot", function()
		boot(nil)
		wow.fire("SCREENSHOT_SUCCEEDED")
		assert.equal(0, #PaparazziDB.captures)
	end)

	it("reports a failed screenshot", function()
		boot(nil)
		wow.fire("PLAYER_LEVEL_UP", 80)
		wow.advance(1)
		wow.fire("SCREENSHOT_FAILED")
		assert.equal(0, #PaparazziDB.captures)
		assert.matches("failed", wow.chat[1])
	end)

	it("does nothing before the addon loads", function()
		wow.reset()
		ns = wow.load_addon(wow.toc_files())
		assert.has_no.errors(function()
			wow.fire("SCREENSHOT_SUCCEEDED")
			SlashCmdList.PAPARAZZI("test")
		end)
	end)
end)
