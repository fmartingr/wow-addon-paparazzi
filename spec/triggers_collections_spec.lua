local wow = require("helpers.wow")

describe("collections triggers", function()
	it("records a mount", function()
		wow.boot({
			setup = function()
				_G.C_MountJournal = {
					GetMountInfoByID = function()
						return "Drake"
					end,
				}
			end,
		})
		assert.same({ mountID = 12, mountName = "Drake" }, wow.take("NEW_MOUNT_ADDED", 12).events[1].data)
	end)

	it("shoots for a mount when the name API is missing", function()
		wow.boot({})
		local data = wow.take("NEW_MOUNT_ADDED", 12).events[1].data
		assert.equal(12, data.mountID)
		assert.is_nil(data.mountName)
	end)

	it("shoots for a mount when the name API fails", function()
		wow.boot({
			setup = function()
				_G.C_MountJournal = {
					GetMountInfoByID = function()
						error("boom")
					end,
				}
			end,
		})
		assert.is_not_nil(wow.take("NEW_MOUNT_ADDED", 12))
	end)

	it("records a pet", function()
		wow.boot({
			setup = function()
				_G.C_PetJournal = {
					GetPetInfoByPetID = function()
						return 99, nil, 1, 0, 0, 0, false, "Cat"
					end,
				}
			end,
		})
		assert.same({ speciesID = 99, petName = "Cat" }, wow.take("NEW_PET_ADDED", "guid").events[1].data)
	end)

	it("records a toy with C_ToyBox", function()
		wow.boot({
			setup = function()
				_G.C_ToyBox = {
					GetToyInfo = function(id)
						return id, "Ball"
					end,
				}
			end,
		})
		assert.same({ itemID = 4, toyName = "Ball" }, wow.take("NEW_TOY_ADDED", 4).events[1].data)
	end)

	it("falls back to the item name for a toy", function()
		wow.boot({
			setup = function()
				_G.C_Item = {
					GetItemNameByID = function()
						return "Item Ball"
					end,
				}
			end,
		})
		assert.equal("Item Ball", wow.take("NEW_TOY_ADDED", 4).events[1].data.toyName)
	end)

	it("records a housing item and a house level when enabled", function()
		wow.boot({})
		PaparazziDB.settings.triggers.housingItem.enabled = true
		PaparazziDB.settings.triggers.houseLevel.enabled = true
		assert.same(
			{ itemType = 1, itemName = "Chair" },
			wow.take("NEW_HOUSING_ITEM_ACQUIRED", 1, "Chair").events[1].data
		)
		local record = wow.take("HOUSE_LEVEL_CHANGED", { level = 3, nested = {} })
		assert.same({ level = 3 }, record.events[1].data)
		assert.same({}, wow.take("HOUSE_LEVEL_CHANGED", nil).events[1].data)
	end)

	it("does not offer a mount on Era", function()
		local ns = wow.boot({ build = { "1", "1", "d", 11509 } })
		for _, def in ipairs(ns.Triggers.Available("era")) do
			assert.not_equal("mount", def.key)
		end
	end)
end)
