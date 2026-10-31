local _, ns = ...

local Triggers = ns.Triggers
local lookup = Triggers.Lookup

Triggers.Register({
	key = "mount",
	label = "New mount",
	category = "collections",
	events = { "NEW_MOUNT_ADDED" },
	flavors = { "retail", "mists", "titan" },
	default = { enabled = true, delay = 1.0 },
	handle = function(_, _, mountID)
		local name = C_MountJournal and (lookup(C_MountJournal.GetMountInfoByID, mountID))
		return { mountID = mountID, mountName = name }
	end,
})

Triggers.Register({
	key = "pet",
	label = "New pet",
	category = "collections",
	events = { "NEW_PET_ADDED" },
	flavors = { "retail", "mists", "titan" },
	default = { enabled = true, delay = 1.0 },
	handle = function(_, _, battlePetGUID)
		local speciesID, name
		if C_PetJournal then
			local info = { lookup(C_PetJournal.GetPetInfoByPetID, battlePetGUID) }
			speciesID, name = info[1], info[8]
		end
		return { speciesID = speciesID, petName = name }
	end,
})

Triggers.Register({
	key = "toy",
	label = "New toy",
	category = "collections",
	events = { "NEW_TOY_ADDED" },
	flavors = { "retail", "mists", "titan" },
	default = { enabled = true, delay = 1.0 },
	handle = function(_, _, itemID)
		local name
		if C_ToyBox and C_ToyBox.GetToyInfo then
			name = select(2, lookup(C_ToyBox.GetToyInfo, itemID))
		end
		if not name and C_Item and C_Item.GetItemNameByID then
			name = lookup(C_Item.GetItemNameByID, itemID)
		end
		return { itemID = itemID, toyName = name }
	end,
})

Triggers.Register({
	key = "housingItem",
	label = "New housing item",
	category = "collections",
	events = { "NEW_HOUSING_ITEM_ACQUIRED" },
	flavors = { "retail" },
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, itemType, itemName)
		return { itemType = itemType, itemName = itemName }
	end,
})

Triggers.Register({
	key = "houseLevel",
	label = "House level",
	category = "collections",
	events = { "HOUSE_LEVEL_CHANGED" },
	flavors = { "retail" },
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, info)
		return type(info) == "table" and info or {}
	end,
})
