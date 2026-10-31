local _, ns = ...

local Capture = {}
ns.Capture = Capture

local MIN_SPACING = 1.0
local AWAIT_TIMEOUT = 3

local EXTENSIONS = { jpeg = ".jpg", jpg = ".jpg", png = ".png", tga = ".tga" }

function Capture.FileName(t, format)
	local ext = EXTENSIONS[format or ""] or ".jpg"
	return "WoWScrnShot_" .. date("%m%d%y_%H%M%S", t) .. ext
end

function Capture.UtcOffset(t)
	local localTime = date("*t", t)
	local utcTime = date("!*t", t)
	utcTime.isdst = localTime.isdst
	return time(localTime) - time(utcTime)
end

function Capture.IsoTime(t, offset)
	local sign = offset < 0 and "-" or "+"
	local abs = math.abs(offset)
	return date("%Y-%m-%dT%H:%M:%S", t)
		.. string.format("%s%02d:%02d", sign, math.floor(abs / 3600), math.floor(abs % 3600 / 60))
end

function Capture.BuildContext()
	local safe = ns.Safe
	local context = {
		game = ns.GetGameInfo(),
		character = {
			name = safe(UnitName("player")),
			realm = safe(GetRealmName()),
			class = safe(select(2, UnitClass("player"))),
			level = safe(UnitLevel("player")),
		},
		location = {
			zone = safe(GetZoneText()),
			subzone = safe(GetSubZoneText()),
			mapID = C_Map and C_Map.GetBestMapForUnit and safe(C_Map.GetBestMapForUnit("player")) or nil,
		},
	}
	if IsInInstance() then
		local name, instanceType, difficultyID, _, _, _, _, instanceID = GetInstanceInfo()
		context.location.instance = {
			name = safe(name),
			type = safe(instanceType),
			difficultyID = safe(difficultyID),
			instanceID = safe(instanceID),
		}
	end
	return context
end

function Capture.New(opts)
	local instance = {}
	local awaiting, awaitTimer
	local lastShotAt

	local function clear()
		if awaitTimer then
			awaitTimer:Cancel()
		end
		awaiting, awaitTimer = nil, nil
	end

	function instance:IsAwaiting()
		return awaiting ~= nil
	end

	function instance:Take(batch)
		local now = opts.now()
		if awaiting then
			local remaining = AWAIT_TIMEOUT - (now - awaiting.since)
			opts.after(math.max(remaining, 0) + 0.1, function()
				self:Take(batch)
			end)
			return
		end
		if lastShotAt and now - lastShotAt < MIN_SPACING then
			opts.after(math.max(MIN_SPACING - (now - lastShotAt), 0.1), function()
				self:Take(batch)
			end)
			return
		end

		awaiting = { batch = batch, context = opts.context(), since = now }
		lastShotAt = now
		opts.screenshot()
		awaitTimer = opts.newTimer(AWAIT_TIMEOUT, function()
			awaiting, awaitTimer = nil, nil
		end)
	end

	function instance:OnSucceeded()
		if not awaiting then
			return
		end
		local taken = awaiting
		clear()

		local t = time()
		local offset = Capture.UtcOffset(t)
		local context = taken.context
		ns.DB.AppendCapture(opts.db(), {
			schema = 1,
			file = Capture.FileName(t, GetCVar("screenshotFormat")),
			time = Capture.IsoTime(t, offset),
			unix = t,
			utcOffset = offset,
			addonVersion = ns.version,
			game = context.game,
			character = context.character,
			location = context.location,
			events = taken.batch.events,
		})
	end

	function instance:OnFailed()
		if not awaiting then
			return
		end
		clear()
		ns.Print("screenshot failed")
	end

	return instance
end
