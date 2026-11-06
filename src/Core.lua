local _, ns = ...

local frame = CreateFrame("Frame")

local function settings()
	return PaparazziDB.settings
end

local function labelOf(key)
	local def = ns.Triggers.Get(key)
	return def and def.label
end

function ns.SendNote(record)
	local api = rawget(_G, "Memories")
	if type(api) ~= "table" or type(api.RecordScreenshot) ~= "function" then
		return
	end
	local note = ns.Capture.Note(record.events, labelOf)
	if note then
		pcall(api.RecordScreenshot, ns.name, note, record.file)
	end
end

local function onAddonLoaded()
	PaparazziDB = ns.DB.Init(PaparazziDB)

	ns.debouncer = ns.Debouncer.New({
		now = GetTime,
		schedule = C_Timer.NewTimer,
		cap = function()
			return settings().debounceCap
		end,
		onFire = function(batch)
			ns.capture:Take(batch)
		end,
	})
	ns.capture = ns.Capture.New({
		db = function()
			return PaparazziDB
		end,
		now = GetTime,
		after = C_Timer.After,
		newTimer = C_Timer.NewTimer,
		screenshot = Screenshot,
		context = ns.Capture.BuildContext,
		onCaptured = ns.SendNote,
	})
	ns.Triggers.Bind({
		settings = settings,
		add = function(record, delay)
			ns.debouncer:Add(record, delay)
		end,
	})
	ns.Triggers.Refresh()

	for _, event in ipairs(ns.Triggers.Events()) do
		local unit = ns.Triggers.EventUnit(event)
		if unit then
			frame:RegisterUnitEvent(event, unit)
		else
			frame:RegisterEvent(event)
		end
	end
	if ns.Settings and ns.Settings.Init then
		ns.Settings.Init(PaparazziDB)
	end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("SCREENSHOT_SUCCEEDED")
frame:RegisterEvent("SCREENSHOT_FAILED")
frame:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" then
		if (...) == ns.name then
			onAddonLoaded()
		end
	elseif not ns.capture then
		return
	elseif event == "SCREENSHOT_SUCCEEDED" then
		ns.capture:OnSucceeded()
	elseif event == "SCREENSHOT_FAILED" then
		ns.capture:OnFailed()
	elseif settings().enabled then
		ns.Triggers.Dispatch(event, ...)
	end
end)

SLASH_PAPARAZZI1 = "/paparazzi"
SlashCmdList.PAPARAZZI = function(msg)
	if not ns.debouncer then
		return
	end
	local arg = strtrim and strtrim(msg or "") or (msg or ""):match("^%s*(.-)%s*$")
	if arg == "test" then
		ns.debouncer:Add({ trigger = "test", name = "PAPARAZZI_TEST", unix = time(), data = {} }, 0)
	elseif ns.Settings and ns.Settings.Open then
		ns.Settings.Open()
	else
		ns.Print("usage: /paparazzi test")
	end
end
