local _, ns = ...

local DB = {}
ns.DB = DB

DB.defaults = {
	schema = 1,
	settings = { enabled = true, debounceCap = 5, retention = 1000, triggers = {} },
	captures = {},
	visited = {},
}

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[k] = copy(x)
	end
	return out
end

local function fill(dst, src)
	for k, v in pairs(src) do
		if dst[k] == nil then
			dst[k] = copy(v)
		elseif type(dst[k]) == "table" and type(v) == "table" then
			fill(dst[k], v)
		end
	end
end

local function clamp(value, min, max, default)
	if type(value) ~= "number" or value ~= value then
		return default
	end
	return math.max(min, math.min(max, value))
end

local function snapHalf(value)
	return math.floor(value * 2 + 0.5) / 2
end

function DB.Init(saved)
	local db = type(saved) == "table" and saved or {}
	if type(db.schema) ~= "number" then
		db.schema = nil
	end
	for _, key in ipairs({ "settings", "captures", "visited" }) do
		if type(db[key]) ~= "table" then
			db[key] = nil
		end
	end
	fill(db, DB.defaults)
	if type(db.settings.triggers) ~= "table" then
		db.settings.triggers = {}
	end

	local triggers = ns.Triggers and ns.Triggers.All() or {}
	for _, def in ipairs(triggers) do
		if type(db.settings.triggers[def.key]) ~= "table" then
			db.settings.triggers[def.key] = { enabled = def.default.enabled, delay = def.default.delay }
		end
	end

	-- A newer schema keeps its data as written.
	if db.schema > DB.defaults.schema then
		return db
	end

	local settings = db.settings
	settings.debounceCap = math.floor(clamp(settings.debounceCap, 2, 10, 5) + 0.5)
	settings.retention = math.floor(clamp(settings.retention, 100, 5000, 1000) / 100 + 0.5) * 100
	for key, entry in pairs(settings.triggers) do
		if type(entry) == "table" then
			entry.delay = snapHalf(clamp(entry.delay, 0, 5, 1))
			if type(entry.enabled) ~= "boolean" then
				local def = ns.Triggers and ns.Triggers.Get(key)
				entry.enabled = def and def.default.enabled or false
			end
		end
	end
	return db
end

function DB.Trim(db)
	local captures = db.captures
	while #captures > db.settings.retention do
		table.remove(captures, 1)
	end
end

function DB.AppendCapture(db, record)
	db.captures[#db.captures + 1] = record
	DB.Trim(db)
end
