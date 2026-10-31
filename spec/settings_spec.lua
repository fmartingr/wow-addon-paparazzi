local wow = require("helpers.wow")

local function variables(category)
	local out = {}
	for _, item in ipairs(category.items) do
		out[#out + 1] = item.type == "header" and ("# " .. item.text) or item.setting.variable
	end
	return out
end

describe("Settings", function()
	it("creates the master switch and the two sliders first", function()
		wow.boot({})
		local category = wow.categories[1]
		assert.equal("Paparazzi", category.name)
		assert.is_true(category.registered)
		local vars = variables(category)
		assert.same(
			{ "Paparazzi_enabled", "Paparazzi_debounceCap", "Paparazzi_retention" },
			{ vars[1], vars[2], vars[3] }
		)
	end)

	it("creates a header, a checkbox, and a slider per available trigger in registry order", function()
		wow.boot({})
		local vars = variables(wow.categories[1])
		local at = {}
		for i, v in ipairs(vars) do
			at[v] = i
		end
		assert.is_truthy(at["# Progress"])
		assert.equal(at["# Progress"] + 1, at["Paparazzi_levelUp_enabled"])
		assert.equal(at["Paparazzi_levelUp_enabled"] + 1, at["Paparazzi_levelUp_delay"])
		assert.is_true(at["Paparazzi_levelUp_enabled"] < at["Paparazzi_achievement_enabled"])
		assert.is_true(at["# Combat"] < at["Paparazzi_bossKill_enabled"])
	end)

	it("creates no controls for unavailable triggers", function()
		wow.boot({ build = { "1.15.9", "1", "d", 11509 } })
		local vars = variables(wow.categories[1])
		for _, v in ipairs(vars) do
			assert.is_nil(v:match("mount"))
			assert.is_nil(v:match("achievement"))
		end
		assert.is_not_nil(wow.categories[1].settings["Paparazzi_levelUp_enabled"])
		assert.is_nil(wow.categories[1].settings["Paparazzi_mount_enabled"])
	end)

	it("binds controls to the saved variables", function()
		wow.boot({})
		local settings = wow.categories[1].settings
		settings.Paparazzi_enabled:SetValue(false)
		settings.Paparazzi_levelUp_delay:SetValue(2.5)
		settings.Paparazzi_levelUp_enabled:SetValue(false)
		assert.is_false(PaparazziDB.settings.enabled)
		assert.equal(2.5, PaparazziDB.settings.triggers.levelUp.delay)
		assert.is_false(PaparazziDB.settings.triggers.levelUp.enabled)
	end)

	it("formats the slider labels", function()
		wow.boot({})
		local category = wow.categories[1]
		assert.equal("5 s", category.items[2].options.formatter(5))
		assert.equal("1.5 s", category.items[#category.items].options.formatter(1.5))
	end)

	it("trims at once when the retention is lowered", function()
		wow.boot({})
		for i = 1, 300 do
			PaparazziDB.captures[i] = { n = i }
		end
		wow.categories[1].settings.Paparazzi_retention:SetValue(100)
		assert.equal(100, #PaparazziDB.captures)
		assert.equal(201, PaparazziDB.captures[1].n)
	end)

	it("opens the category from /paparazzi and from the compartment", function()
		wow.boot({})
		SlashCmdList.PAPARAZZI("")
		assert.equal(1, wow.opened)
		wow.opened = nil
		Paparazzi_OnAddonCompartmentClick()
		assert.equal(1, wow.opened)
	end)

	it("skips headers when the layout API is missing", function()
		wow.boot({
			setup = function()
				_G.SettingsPanel = nil
			end,
		})
		for _, item in ipairs(wow.categories[1].items) do
			assert.not_equal("header", item.type)
		end
	end)

	it("prints usage when Settings is absent", function()
		assert.has_no.errors(function()
			wow.boot({
				setup = function()
					_G.Settings = nil
				end,
			})
		end)
		SlashCmdList.PAPARAZZI("")
		assert.matches("usage", wow.chat[1])
		assert.matches("unavailable", wow.chat[2])
	end)
end)
