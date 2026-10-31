local _, ns = ...

local Triggers = {}
ns.Triggers = Triggers

Triggers.categories = { "progress", "combat", "pvp", "collections", "loot", "world" }

local registry, byKey = {}, {}
local states = {}
local reported = {}
local bound
local cache

function Triggers.Register(def)
	assert(not byKey[def.key], "duplicate trigger " .. def.key)
	registry[#registry + 1] = def
	byKey[def.key] = def
	states[def.key] = {}
	cache = nil
end

function Triggers.All()
	return registry
end

function Triggers.Get(key)
	return byKey[key]
end

function Triggers.EventsFor(def, flavor)
	if type(def.events) == "function" then
		return def.events(flavor)
	end
	return def.events
end

local function inFlavor(def, flavor)
	if flavor == "unknown" or def.flavors == nil or def.flavors == "all" then
		return true
	end
	for _, f in ipairs(def.flavors) do
		if f == flavor then
			return true
		end
	end
	return false
end

function Triggers.Available(flavor)
	local list = {}
	for _, def in ipairs(registry) do
		local valid = inFlavor(def, flavor)
		if valid then
			for _, event in ipairs(Triggers.EventsFor(def, flavor)) do
				if not C_EventUtils.IsEventValid(event) then
					valid = false
					break
				end
			end
		end
		if valid and def.requires and not def.requires() then
			valid = false
		end
		if valid then
			list[#list + 1] = def
		end
	end
	return list
end

function Triggers.Refresh()
	cache = nil
end

local function available()
	if not cache then
		cache = Triggers.Available(ns.GetFlavor())
	end
	return cache
end

function Triggers.Events()
	local seen, events = {}, {}
	for _, def in ipairs(available()) do
		for _, event in ipairs(Triggers.EventsFor(def, ns.GetFlavor())) do
			if not seen[event] then
				seen[event] = true
				events[#events + 1] = event
			end
		end
	end
	return events
end

-- Name lookups must never cancel a shot, so a missing or failing API gives nil.
function Triggers.Lookup(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local results = { pcall(fn, ...) }
	if results[1] then
		return unpack(results, 2)
	end
end

function Triggers.Bind(opts)
	bound = opts
end

local function sanitize(result)
	local data = {}
	for k, v in pairs(result) do
		local t = type(v)
		if t == "string" or t == "number" or t == "boolean" then
			v = ns.Safe(v)
			if v ~= nil then
				data[k] = v
			end
		end
	end
	return data
end

local function listens(def, event)
	for _, e in ipairs(Triggers.EventsFor(def, ns.GetFlavor())) do
		if e == event then
			return true
		end
	end
	return false
end

function Triggers.Dispatch(event, ...)
	local settings = bound.settings().triggers
	for _, def in ipairs(available()) do
		local setting = settings[def.key]
		if setting and setting.enabled and listens(def, event) then
			local ok, result = pcall(def.handle, states[def.key], event, ...)
			if not ok then
				if not reported[def.key] then
					reported[def.key] = true
					ns.Print("trigger " .. def.key .. " failed: " .. tostring(result))
				end
			elseif result ~= nil then
				bound.add({ trigger = def.key, name = event, unix = time(), data = sanitize(result) }, setting.delay)
			end
		end
	end
end
