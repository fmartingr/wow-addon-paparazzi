local wow = require("helpers.wow")

describe("Triggers", function()
	local ns, added

	local function load(opts)
		wow.reset(opts)
		ns = wow.load_addon({ "src/Init.lua", "src/Triggers.lua" })
		added = {}
		ns.Triggers.Bind({
			settings = function()
				return { triggers = { a = { enabled = true, delay = 1 }, b = { enabled = false, delay = 1 } } }
			end,
			add = function(record, delay)
				added[#added + 1] = { record = record, delay = delay }
			end,
		})
	end

	local function register(def)
		def.label = def.label or def.key
		def.category = def.category or "progress"
		def.default = def.default or { enabled = true, delay = 1 }
		ns.Triggers.Register(def)
	end

	describe("Available", function()
		it("gates by flavor", function()
			load()
			register({ key = "a", events = { "E1" }, flavors = { "mists" }, handle = function() end })
			assert.equal(0, #ns.Triggers.Available("retail"))
			assert.equal(1, #ns.Triggers.Available("mists"))
		end)

		it("ignores flavors for the unknown flavor", function()
			load()
			register({ key = "a", events = { "E1" }, flavors = { "mists" }, handle = function() end })
			assert.equal(1, #ns.Triggers.Available("unknown"))
		end)

		it("gates by IsEventValid", function()
			load({ invalidEvents = { E2 = true } })
			register({ key = "a", events = { "E1", "E2" }, flavors = "all", handle = function() end })
			assert.equal(0, #ns.Triggers.Available("retail"))
		end)

		it("gates by requires", function()
			load()
			local ok = false
			register({
				key = "a",
				events = { "E1" },
				flavors = "all",
				requires = function()
					return ok
				end,
				handle = function() end,
			})
			assert.equal(0, #ns.Triggers.Available("retail"))
			ok = true
			assert.equal(1, #ns.Triggers.Available("retail"))
		end)

		it("accepts events as a function of the flavor", function()
			load()
			register({
				key = "a",
				flavors = "all",
				events = function(flavor)
					return { flavor == "retail" and "NEW" or "OLD" }
				end,
				handle = function() end,
			})
			assert.same({ "NEW" }, ns.Triggers.EventsFor(ns.Triggers.Get("a"), "retail"))
			assert.same({ "OLD" }, ns.Triggers.EventsFor(ns.Triggers.Get("a"), "era"))
		end)
	end)

	describe("Register", function()
		it("rejects a duplicate key", function()
			load()
			register({ key = "a", events = { "E1" }, handle = function() end })
			assert.has_error(function()
				register({ key = "a", events = { "E1" }, handle = function() end })
			end)
		end)
	end)

	describe("Dispatch", function()
		it("adds a record with sanitized data and the trigger delay", function()
			load()
			register({
				key = "a",
				events = { "E1" },
				flavors = "all",
				handle = function()
					return { n = 1, s = "x", b = true, tbl = {}, secret = wow.secret(1), fn = print }
				end,
			})
			ns.Triggers.Dispatch("E1")
			assert.equal(1, #added)
			assert.equal(1, added[1].delay)
			assert.equal("a", added[1].record.trigger)
			assert.equal("E1", added[1].record.name)
			assert.same({ n = 1, s = "x", b = true }, added[1].record.data)
		end)

		it("skips a disabled trigger", function()
			load()
			register({
				key = "b",
				events = { "E1" },
				flavors = "all",
				handle = function()
					return {}
				end,
			})
			ns.Triggers.Dispatch("E1")
			assert.equal(0, #added)
		end)

		it("skips a handler that returns nil", function()
			load()
			register({ key = "a", events = { "E1" }, flavors = "all", handle = function() end })
			ns.Triggers.Dispatch("E1")
			assert.equal(0, #added)
		end)

		it("ignores events that the trigger does not list", function()
			load()
			register({
				key = "a",
				events = { "E1" },
				flavors = "all",
				handle = function()
					return {}
				end,
			})
			ns.Triggers.Dispatch("E2")
			assert.equal(0, #added)
		end)

		it("catches a handler error and prints once", function()
			load()
			register({
				key = "a",
				events = { "E1" },
				flavors = "all",
				handle = function()
					error("boom")
				end,
			})
			ns.Triggers.Dispatch("E1")
			ns.Triggers.Dispatch("E1")
			assert.equal(0, #added)
			assert.equal(1, #wow.chat)
		end)

		it("lists the union of available events", function()
			load()
			register({ key = "a", events = { "E1", "E2" }, flavors = "all", handle = function() end })
			register({ key = "b", events = { "E2", "E3" }, flavors = "all", handle = function() end })
			assert.same({ "E1", "E2", "E3" }, ns.Triggers.Events())
		end)
	end)
end)
