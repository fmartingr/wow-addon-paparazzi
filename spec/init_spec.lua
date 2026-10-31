local wow = require("helpers.wow")

describe("Init", function()
	local function load(interface)
		wow.reset({ build = { "1.0.0", "1", "d", interface } })
		return wow.load_addon({ "src/Init.lua" })
	end

	describe("GetFlavor", function()
		local cases = {
			{ 120105, "retail" },
			{ 50504, "mists" },
			{ 38002, "titan" },
			{ 20506, "tbc" },
			{ 16001, "forever" },
			{ 11509, "era" },
			{ 40402, "unknown" },
			{ 0, "unknown" },
		}
		for _, case in ipairs(cases) do
			it("maps " .. case[1] .. " to " .. case[2], function()
				assert.equal(case[2], load(case[1]).GetFlavor())
			end)
		end
	end)

	describe("GetGameInfo", function()
		it("returns version, build, interface, and flavor", function()
			wow.reset()
			local ns = wow.load_addon({ "src/Init.lua" })
			assert.same(
				{ flavor = "retail", version = "12.1.5", build = "70688", interface = 120105 },
				ns.GetGameInfo()
			)
		end)
	end)

	describe("Safe", function()
		it("changes a secret value to nil", function()
			local ns = load(120105)
			assert.is_nil(ns.Safe(wow.secret(5)))
		end)

		it("keeps a normal value", function()
			local ns = load(120105)
			assert.equal(5, ns.Safe(5))
		end)

		it("works when issecretvalue is absent", function()
			wow.reset({ noSecrets = true })
			local ns = wow.load_addon({ "src/Init.lua" })
			assert.equal("x", ns.Safe("x"))
		end)
	end)

	describe("metadata", function()
		it("reads the version through C_AddOns", function()
			wow.reset()
			assert.equal("v1.0.0", wow.load_addon({ "src/Init.lua" }).version)
		end)

		it("falls back to GetAddOnMetadata", function()
			wow.reset()
			_G.C_AddOns = nil
			_G.GetAddOnMetadata = function()
				return "v2"
			end
			assert.equal("v2", wow.load_addon({ "src/Init.lua" }).version)
		end)
	end)

	it("prints with the addon prefix", function()
		wow.reset()
		local ns = wow.load_addon({ "src/Init.lua" })
		ns.Print("hi")
		assert.matches("Paparazzi|r: hi", wow.chat[1], 1, true)
	end)

	it("loads the real TOC without error", function()
		wow.reset()
		assert.has_no.errors(function()
			wow.load_addon(wow.toc_files())
		end)
	end)
end)
