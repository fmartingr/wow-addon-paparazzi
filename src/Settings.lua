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

	Settings.RegisterAddOnCategory(category)
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
