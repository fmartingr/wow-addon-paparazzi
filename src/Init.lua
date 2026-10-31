local addonName, ns = ...

ns.name = addonName

local function getMetadata(field)
	if C_AddOns and C_AddOns.GetAddOnMetadata then
		return C_AddOns.GetAddOnMetadata(addonName, field)
	end
	if GetAddOnMetadata then
		return GetAddOnMetadata(addonName, field)
	end
end

ns.version = getMetadata("Version")

local FLAVOR_RANGES = {
	{ 110000, math.huge, "retail" },
	{ 50000, 59999, "mists" },
	{ 30000, 39999, "titan" },
	{ 20000, 29999, "tbc" },
	{ 16000, 16999, "forever" },
	{ 11000, 11999, "era" },
}

function ns.GetFlavor()
	local interface = select(4, GetBuildInfo())
	for _, range in ipairs(FLAVOR_RANGES) do
		if interface >= range[1] and interface <= range[2] then
			return range[3]
		end
	end
	return "unknown"
end

function ns.GetGameInfo()
	local version, build, _, interface = GetBuildInfo()
	return { flavor = ns.GetFlavor(), version = version, build = build, interface = interface }
end

function ns.Safe(v)
	if issecretvalue and issecretvalue(v) then
		return nil
	end
	return v
end

function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Paparazzi|r: " .. msg)
end
