local wow = require("helpers.wow")

local EPIC = "|cffa335ee|Hitem:1::::::::80:|h[Big Sword]|h|r"
local LEGENDARY = "|cffff8000|Hitem:2::::::::80:|h[Ring]|h|r"
local RARE = "|cff0070dd|Hitem:3::::::::80:|h[Meh]|h|r"

describe("loot triggers", function()
	local function boot()
		wow.boot({})
		PaparazziDB.settings.triggers.epicLoot.enabled = true
	end

	it("records epic loot parsed from the link color", function()
		boot()
		local data = wow.take("SHOW_LOOT_TOAST", "item", EPIC, 1).events[1].data
		assert.same({ itemLink = EPIC, itemName = "Big Sword", quality = 4, quantity = 1 }, data)
	end)

	it("records legendary loot through the toast color", function()
		boot()
		assert.equal(5, wow.take("SHOW_LOOT_TOAST", "item", LEGENDARY, 1).events[1].data.quality)
	end)

	it("prefers the quality API", function()
		wow.boot({
			setup = function()
				_G.C_Item = {
					GetItemQualityByID = function()
						return 4
					end,
				}
			end,
		})
		PaparazziDB.settings.triggers.epicLoot.enabled = true
		assert.is_not_nil(wow.take("SHOW_LOOT_TOAST", "item", RARE, 1))
	end)

	it("makes no shot for rare loot, money, or an unknown color", function()
		boot()
		assert.is_nil(wow.take("SHOW_LOOT_TOAST", "item", RARE, 1))
		assert.is_nil(wow.take("SHOW_LOOT_TOAST", "money", nil, 5))
		assert.is_nil(wow.take("SHOW_LOOT_TOAST", "currency", "link", 5))
		assert.is_nil(wow.take("SHOW_LOOT_TOAST", "item", "|cff123456|h[X]|h|r", 1))
		assert.is_nil(wow.take("SHOW_LOOT_TOAST", "item", nil, 1))
	end)

	it("records legendary loot by default", function()
		wow.boot({})
		local data = wow.take("SHOW_LOOT_TOAST_LEGENDARY_LOOTED", LEGENDARY).events[1].data
		assert.same({ itemLink = LEGENDARY, itemName = "Ring" }, data)
	end)

	it("is not available outside Retail", function()
		local ns = wow.boot({ build = { "5.5.4", "1", "d", 50504 } })
		for _, def in ipairs(ns.Triggers.Available("mists")) do
			assert.not_equal("legendaryLoot", def.key)
		end
	end)
end)
