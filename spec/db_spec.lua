local wow = require("helpers.wow")

describe("DB", function()
	local ns

	before_each(function()
		wow.reset()
		ns = wow.load_addon({ "src/Init.lua", "src/DB.lua", "src/Triggers.lua", "src/triggers/Progress.lua" })
	end)

	it("fills defaults on first run", function()
		local db = ns.DB.Init(nil)
		assert.equal(1, db.schema)
		assert.is_true(db.settings.enabled)
		assert.equal(5, db.settings.debounceCap)
		assert.equal(1000, db.settings.retention)
		assert.same({}, db.captures)
		assert.same({}, db.visited)
	end)

	it("fills a setting for each registered trigger", function()
		local db = ns.DB.Init(nil)
		assert.same({ enabled = true, delay = 1.0 }, db.settings.triggers.levelUp)
	end)

	it("keeps existing values", function()
		local db = ns.DB.Init({
			settings = { enabled = false, retention = 300, triggers = { levelUp = { enabled = false, delay = 2 } } },
		})
		assert.is_false(db.settings.enabled)
		assert.equal(300, db.settings.retention)
		assert.same({ enabled = false, delay = 2 }, db.settings.triggers.levelUp)
		assert.equal(5, db.settings.debounceCap)
	end)

	it("clamps values", function()
		local db = ns.DB.Init({
			settings = { debounceCap = 99, retention = 5, triggers = { levelUp = { enabled = true, delay = 3.3 } } },
		})
		assert.equal(10, db.settings.debounceCap)
		assert.equal(100, db.settings.retention)
		assert.equal(3.5, db.settings.triggers.levelUp.delay)
		db = ns.DB.Init({ settings = { debounceCap = 0, retention = 9999, triggers = { levelUp = { delay = -4 } } } })
		assert.equal(2, db.settings.debounceCap)
		assert.equal(5000, db.settings.retention)
		assert.equal(0, db.settings.triggers.levelUp.delay)
		assert.is_true(db.settings.triggers.levelUp.enabled)
	end)

	it("replaces a non-number setting with its default", function()
		local db = ns.DB.Init({ settings = { debounceCap = "x" } })
		assert.equal(5, db.settings.debounceCap)
	end)

	it("keeps newer schema data unclamped", function()
		local db = ns.DB.Init({ schema = 2, settings = { retention = 5 } })
		assert.equal(2, db.schema)
		assert.equal(5, db.settings.retention)
	end)

	it("drops the oldest record at retention + 1", function()
		local db = ns.DB.Init({ settings = { retention = 100 } })
		for i = 1, 101 do
			ns.DB.AppendCapture(db, { n = i })
		end
		assert.equal(100, #db.captures)
		assert.equal(2, db.captures[1].n)
		assert.equal(101, db.captures[100].n)
	end)

	it("trims after the retention is lowered", function()
		local db = ns.DB.Init(nil)
		for i = 1, 300 do
			db.captures[i] = { n = i }
		end
		db.settings.retention = 100
		ns.DB.Trim(db)
		assert.equal(100, #db.captures)
		assert.equal(201, db.captures[1].n)
	end)
end)
