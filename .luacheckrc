std = "lua51"
max_line_length = 120
codes = true
exclude_files = { ".lua/", ".luarocks/", ".release/", "build/" }
ignore = { "212/self", "211/_.*", "212/_.*" }

globals = { "PaparazziDB", "SLASH_PAPARAZZI1", "SlashCmdList", "Paparazzi_OnAddonCompartmentClick" }

read_globals = {
	"C_AddOns",
	"GetAddOnMetadata",
	"GetBuildInfo",
	"DEFAULT_CHAT_FRAME",
	"issecretvalue",
	"CreateFrame",
	"C_Timer",
	"C_Map",
	"C_EventUtils",
	"GetTime",
	"time",
	"date",
	"strtrim",
	"Screenshot",
	"GetCVar",
	"UnitName",
	"GetRealmName",
	"UnitClass",
	"UnitLevel",
	"GetZoneText",
	"GetSubZoneText",
	"GetInstanceInfo",
	"IsInInstance",
}

files["spec/"] = { std = "+busted", globals = { "_G" } }
