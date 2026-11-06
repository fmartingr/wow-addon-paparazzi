local wow = {}

local INSTALLED = {
	"CreateFrame",
	"C_Timer",
	"GetTime",
	"time",
	"date",
	"Screenshot",
	"GetCVar",
	"GetBuildInfo",
	"C_EventUtils",
	"issecretvalue",
	"UnitName",
	"GetRealmName",
	"UnitClass",
	"UnitLevel",
	"GetZoneText",
	"GetSubZoneText",
	"GetInstanceInfo",
	"IsInInstance",
	"C_Map",
	"DEFAULT_CHAT_FRAME",
	"C_AddOns",
	"GetAddOnMetadata",
	"SlashCmdList",
	"Settings",
	"PaparazziDB",
}

local real_time, real_date = os.time, os.date

local baseline = {}
for k in pairs(_G) do
	baseline[k] = true
end

local function install_frames()
	wow.frames = {}
	_G.CreateFrame = function()
		local frame = { events = {}, scripts = {} }
		function frame:RegisterEvent(e)
			self.events[e] = true
		end
		function frame:RegisterUnitEvent(e, unit)
			self.events[e] = true
			self.units = self.units or {}
			self.units[e] = unit
		end
		function frame:UnregisterEvent(e)
			self.events[e] = nil
		end
		function frame:UnregisterAllEvents()
			self.events = {}
		end
		function frame:IsEventRegistered(e)
			return self.events[e] == true
		end
		function frame:SetScript(name, fn)
			self.scripts[name] = fn
		end
		function frame:GetScript(name)
			return self.scripts[name]
		end
		wow.frames[#wow.frames + 1] = frame
		return frame
	end
end

local function install_timers()
	wow.timers = {}
	local seq = 0
	local function add(delay, fn)
		seq = seq + 1
		local timer = { due = wow.clock + delay, fn = fn, seq = seq, cancelled = false }
		function timer:Cancel()
			self.cancelled = true
		end
		function timer:IsCancelled()
			return self.cancelled
		end
		wow.timers[#wow.timers + 1] = timer
		return timer
	end
	_G.C_Timer = {
		After = function(delay, fn)
			add(delay, fn)
		end,
		NewTimer = add,
	}
end

function wow.reset(opts)
	opts = opts or {}
	for _, name in ipairs(INSTALLED) do
		_G[name] = nil
	end
	for k in pairs(_G) do
		if not baseline[k] then
			_G[k] = nil
		end
	end

	wow.clock = 0
	wow.wall = opts.wall or 1793560500
	wow.cvars = { screenshotFormat = "jpeg" }
	wow.screenshots = 0
	wow.chat = {}
	wow.secrets = setmetatable({}, { __mode = "k" })

	install_frames()
	install_timers()

	_G.GetTime = function()
		return wow.clock
	end
	_G.time = function(t)
		if t then
			return real_time(t)
		end
		return wow.wall
	end
	_G.date = function(fmt, t)
		return real_date(fmt, t or wow.wall)
	end
	_G.Screenshot = function()
		wow.screenshots = wow.screenshots + 1
	end
	_G.GetCVar = function(name)
		return wow.cvars[name]
	end
	local build = opts.build or { "12.1.5", "70688", "Oct 1 2026", 120105 }
	_G.GetBuildInfo = function()
		return build[1], build[2], build[3], build[4]
	end
	local invalid = opts.invalidEvents or {}
	_G.C_EventUtils = {
		IsEventValid = function(e)
			return not invalid[e]
		end,
	}
	if not opts.noSecrets then
		_G.issecretvalue = function(v)
			return type(v) == "table" and wow.secrets[v] == true
		end
	end
	_G.UnitName = function()
		return "Kaelys"
	end
	_G.GetRealmName = function()
		return "Ragnaros"
	end
	_G.UnitClass = function()
		return "Mage", "MAGE", 8
	end
	_G.UnitLevel = function()
		return 80
	end
	_G.GetZoneText = function()
		return "Dornogal"
	end
	_G.GetSubZoneText = function()
		return ""
	end
	wow.instance = nil
	_G.IsInInstance = function()
		return wow.instance ~= nil, wow.instance and wow.instance.type or "none"
	end
	_G.GetInstanceInfo = function()
		local i = wow.instance
		if not i then
			return "Dornogal", "none", 0, "", 0, 0, false, 2339
		end
		return i.name, i.type, i.difficultyID, "", 0, 0, false, i.instanceID
	end
	_G.C_Map = {
		GetBestMapForUnit = function()
			return 2339
		end,
	}
	_G.DEFAULT_CHAT_FRAME = {
		AddMessage = function(_, msg)
			wow.chat[#wow.chat + 1] = msg
		end,
	}
	_G.C_AddOns = {
		GetAddOnMetadata = function()
			return "v1.0.0"
		end,
	}
	_G.SlashCmdList = {}
	wow.install_settings()
end

function wow.install_settings()
	wow.categories = {}
	wow.opened = nil
	_G.Settings = {
		VarType = { Boolean = "boolean", Number = "number" },
		RegisterVerticalLayoutCategory = function(name)
			local category = { name = name, items = {}, id = #wow.categories + 1 }
			function category:GetID()
				return self.id
			end
			wow.categories[#wow.categories + 1] = category
			return category
		end,
		RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
			local setting =
				{ variable = variable, key = key, tbl = tbl, varType = varType, name = name, default = default }
			function setting:GetValue()
				return self.tbl[self.key]
			end
			function setting:SetValue(v)
				self.tbl[self.key] = v
				if self.callback then
					self.callback(self, v)
				end
			end
			function setting:SetValueChangedCallback(fn)
				self.callback = fn
			end
			category.settings = category.settings or {}
			category.settings[variable] = setting
			return setting
		end,
		CreateCheckbox = function(category, setting, tooltip)
			category.items[#category.items + 1] = { type = "checkbox", setting = setting, tooltip = tooltip }
		end,
		CreateSliderOptions = function(min, max, step)
			local options = { min = min, max = max, step = step }
			function options:SetLabelFormatter(_, fn)
				self.formatter = fn
			end
			return options
		end,
		CreateSlider = function(category, setting, options, tooltip)
			category.items[#category.items + 1] =
				{ type = "slider", setting = setting, options = options, tooltip = tooltip }
		end,
		RegisterAddOnCategory = function(category)
			category.registered = true
		end,
		OpenToCategory = function(id)
			wow.opened = id
		end,
	}
	_G.MinimalSliderWithSteppersMixin = { Label = { Right = 2 } }
	_G.CreateSettingsListSectionHeaderInitializer = function(text)
		return { type = "header", text = text }
	end
	_G.SettingsPanel = {
		GetLayout = function(_, category)
			return {
				AddInitializer = function(_, initializer)
					category.items[#category.items + 1] = initializer
				end,
			}
		end,
	}
end

-- A wrapped value stands in for a Midnight secret value.
function wow.secret(v)
	local wrapped = { value = v }
	wow.secrets[wrapped] = true
	return wrapped
end

function wow.set_wall(unix)
	wow.wall = unix
end

function wow.advance(seconds)
	local target = wow.clock + seconds
	while true do
		local next_timer
		for _, timer in ipairs(wow.timers) do
			if not timer.cancelled and not timer.done and timer.due <= target then
				if
					not next_timer
					or timer.due < next_timer.due
					or (timer.due == next_timer.due and timer.seq < next_timer.seq)
				then
					next_timer = timer
				end
			end
		end
		if not next_timer then
			break
		end
		wow.wall = wow.wall + (next_timer.due - wow.clock)
		wow.clock = next_timer.due
		next_timer.done = true
		next_timer.fn()
	end
	wow.wall = wow.wall + (target - wow.clock)
	wow.clock = target
end

function wow.fire(event, ...)
	for _, frame in ipairs(wow.frames) do
		local handler = frame.scripts.OnEvent
		if handler and frame.events[event] then
			handler(frame, event, ...)
		end
	end
end

function wow.toc_files()
	local files = {}
	for line in io.lines("Paparazzi.toc") do
		if line ~= "" and not line:match("^##") then
			files[#files + 1] = (line:gsub("\\", "/"):gsub("%s+$", ""))
		end
	end
	return files
end

function wow.load_addon(files)
	local ns = {}
	for _, path in ipairs(files) do
		assert(loadfile(path))("Paparazzi", ns)
	end
	return ns
end

-- Boots the real addon through the TOC and fires ADDON_LOADED.
function wow.boot(opts)
	opts = opts or {}
	wow.reset(opts)
	if opts.setup then
		opts.setup()
	end
	_G.PaparazziDB = opts.saved
	local ns = wow.load_addon(wow.toc_files())
	wow.fire("ADDON_LOADED", "Paparazzi")
	return ns
end

-- Fires an event, runs the clock until a screenshot is requested, then confirms it.
-- Returns the new capture record, or nil when no screenshot happened.
function wow.take(event, ...)
	local before = wow.screenshots
	local count = #PaparazziDB.captures
	wow.fire(event, ...)
	for _ = 1, 20 do
		if wow.screenshots > before then
			break
		end
		wow.advance(0.5)
	end
	if wow.screenshots == before then
		return nil
	end
	wow.fire("SCREENSHOT_SUCCEEDED")
	wow.advance(1)
	return PaparazziDB.captures[count + 1]
end

wow.reset()

return wow
