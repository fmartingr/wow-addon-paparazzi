local _, ns = ...

local SettingsUI = {}
ns.Settings = SettingsUI

local CATEGORY_LABELS = {
	progress = "Progress",
	combat = "Combat",
	pvp = "PvP",
	collections = "Collections",
	loot = "Loot",
	world = "World",
}

local MEMORIES_TEXT = {
	"Memories records the journey of your character.",
	"Paparazzi sends a note to Memories after each screenshot.",
	"The note lists the triggers that took the screenshot.",
	"The checkbox is on by default when Memories is installed.",
	"The checkbox is locked when Memories is not installed.",
}
local MEMORIES_TOOLTIP = "Send the reason of each screenshot to the Memories addon."

local category

local function supported()
	return Settings and Settings.RegisterAddOnSetting and Settings.RegisterVerticalLayoutCategory and true or false
end

function SettingsUI.Init(db)
	if not supported() then
		return
	end
	category = Settings.RegisterVerticalLayoutCategory("Paparazzi")

	local function checkbox(variable, key, tbl, name, default, tooltip)
		local setting =
			Settings.RegisterAddOnSetting(category, variable, key, tbl, Settings.VarType.Boolean, name, default)
		Settings.CreateCheckbox(category, setting, tooltip)
		return setting
	end

	local function slider(variable, key, tbl, name, default, range, format, tooltip)
		local setting =
			Settings.RegisterAddOnSetting(category, variable, key, tbl, Settings.VarType.Number, name, default)
		local options = Settings.CreateSliderOptions(range[1], range[2], range[3])
		options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
			return string.format(format, value)
		end)
		Settings.CreateSlider(category, setting, options, tooltip)
		return setting
	end

	local settings = db.settings
	checkbox("Paparazzi_enabled", "enabled", settings, "Enabled", true, "Switch all automatic screenshots on or off.")
	slider(
		"Paparazzi_debounceCap",
		"debounceCap",
		settings,
		"Merge window",
		5,
		{ 2, 10, 1 },
		"%d s",
		"Events that follow the first event of a screenshot extend its time up to this limit."
	)
	local retention = slider(
		"Paparazzi_retention",
		"retention",
		settings,
		"Records kept",
		1000,
		{ 100, 5000, 100 },
		"%d",
		"The number of capture records that the addon keeps. The oldest records go first."
	)
	retention:SetValueChangedCallback(function()
		ns.DB.Trim(db)
	end)

	local available = ns.Triggers.Available(ns.GetFlavor())
	local layout = SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category)
	for _, name in ipairs(ns.Triggers.categories) do
		local first = true
		for _, def in ipairs(available) do
			if def.category == name then
				if first and layout and CreateSettingsListSectionHeaderInitializer then
					layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(CATEGORY_LABELS[name]))
				end
				first = false
				local entry = settings.triggers[def.key]
				checkbox("Paparazzi_" .. def.key .. "_enabled", "enabled", entry, def.label, def.default.enabled)
				slider(
					"Paparazzi_" .. def.key .. "_delay",
					"delay",
					entry,
					"Delay",
					def.default.delay,
					{ 0, 5, 0.5 },
					"%.1f s",
					"Seconds to wait after the event before the screenshot."
				)
			end
		end
	end

	SettingsUI.InitMemories(db)

	Settings.RegisterAddOnCategory(category)
end

function SettingsUI.InitMemories(db)
	local target = category
	if Settings.RegisterVerticalLayoutSubcategory then
		target = Settings.RegisterVerticalLayoutSubcategory(category, "Memories")
	end
	local layout = SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(target)
	if layout and CreateSettingsListSectionHeaderInitializer then
		for _, line in ipairs(MEMORIES_TEXT) do
			layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(line))
		end
	end
	local setting = Settings.RegisterAddOnSetting(
		target,
		"Paparazzi_memories",
		"memories",
		db.settings,
		Settings.VarType.Boolean,
		"Send notes to Memories",
		true
	)
	local initializer = Settings.CreateCheckbox(target, setting, MEMORIES_TOOLTIP)
	if initializer and initializer.AddModifyPredicate then
		initializer:AddModifyPredicate(function()
			return ns.MemoriesApi() ~= nil
		end)
	end
end

function SettingsUI.Open()
	if not category then
		ns.Print("usage: /paparazzi test")
		ns.Print("settings UI unavailable in this client")
		return
	end
	Settings.OpenToCategory(category:GetID())
end

function Paparazzi_OnAddonCompartmentClick()
	SettingsUI.Open()
end
