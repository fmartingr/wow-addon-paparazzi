local _, ns = ...

local Triggers = ns.Triggers
local lookup = Triggers.Lookup

local COLOR_QUALITY = { a335ee = 4, ff8000 = 5 }

local function itemName(link)
	return type(link) == "string" and link:match("|h%[(.-)%]|h") or nil
end

local function quality(link)
	local q
	if C_Item and C_Item.GetItemQualityByID then
		q = lookup(C_Item.GetItemQualityByID, link)
	end
	if q == nil and type(link) == "string" then
		local color = link:match("|cff(%x%x%x%x%x%x)")
		q = color and COLOR_QUALITY[color:lower()]
	end
	return q
end

Triggers.Register({
	key = "epicLoot",
	label = "Epic loot",
	category = "loot",
	events = { "SHOW_LOOT_TOAST" },
	flavors = { "retail" },
	default = { enabled = false, delay = 1.0 },
	handle = function(_, _, typeIdentifier, itemLink, quantity)
		if typeIdentifier ~= "item" then
			return nil
		end
		local q = quality(itemLink)
		if not q or q < 4 then
			return nil
		end
		return { itemLink = itemLink, itemName = itemName(itemLink), quality = q, quantity = quantity }
	end,
})

Triggers.Register({
	key = "legendaryLoot",
	label = "Legendary loot",
	category = "loot",
	events = { "SHOW_LOOT_TOAST_LEGENDARY_LOOTED" },
	flavors = { "retail" },
	default = { enabled = true, delay = 1.0 },
	handle = function(_, _, itemLink)
		return { itemLink = itemLink, itemName = itemName(itemLink) }
	end,
})
