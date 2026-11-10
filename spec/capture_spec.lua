local wow = require("helpers.wow")

describe("Capture", function()
	local ns

	before_each(function()
		wow.reset()
		ns = wow.load_addon({ "src/Init.lua", "src/DB.lua", "src/Capture.lua" })
	end)

	local function new(db, onCaptured)
		return ns.Capture.New({
			db = function()
				return db
			end,
			now = GetTime,
			after = C_Timer.After,
			newTimer = C_Timer.NewTimer,
			screenshot = Screenshot,
			context = ns.Capture.BuildContext,
			onCaptured = onCaptured,
		})
	end

	local function newDb()
		return ns.DB.Init(nil)
	end

	local function batch(name)
		return { events = { { trigger = name, name = "E", unix = 1, data = {} } } }
	end

	describe("Take", function()
		it("spaces two screenshots at least 1.0 s apart", function()
			local db = newDb()
			local capture = new(db)
			capture:Take(batch("a"))
			capture:OnSucceeded()
			wow.advance(0.2)
			capture:Take(batch("b"))
			assert.equal(1, wow.screenshots)
			wow.advance(0.79)
			assert.equal(1, wow.screenshots)
			wow.advance(0.02)
			assert.equal(2, wow.screenshots)
		end)

		it("waits while a capture is awaiting", function()
			local capture = new(newDb())
			capture:Take(batch("a"))
			wow.advance(1.5)
			capture:Take(batch("b"))
			wow.advance(1)
			assert.equal(1, wow.screenshots)
			capture:OnSucceeded()
			wow.advance(2)
			assert.equal(2, wow.screenshots)
		end)

		it("ignores a late success after the await timeout", function()
			local db = newDb()
			local capture = new(db)
			capture:Take(batch("a"))
			wow.advance(3)
			assert.is_false(capture:IsAwaiting())
			capture:OnSucceeded()
			assert.equal(0, #db.captures)
		end)
	end)

	describe("events", function()
		it("ignores a manual screenshot", function()
			local db = newDb()
			new(db):OnSucceeded()
			assert.equal(0, #db.captures)
		end)

		it("records a capture on success", function()
			local db = newDb()
			local capture = new(db)
			capture:Take(batch("levelUp"))
			capture:OnSucceeded()
			assert.equal(1, #db.captures)
			local record = db.captures[1]
			assert.equal(1, record.schema)
			assert.equal(wow.wall, record.unix)
			assert.equal("v1.0.0", record.addonVersion)
			assert.equal("retail", record.game.flavor)
			assert.equal("Kaelys", record.character.name)
			assert.equal("Dornogal", record.location.zone)
			assert.equal("levelUp", record.events[1].trigger)
			assert.matches("^WoWScrnShot_%d%d%d%d%d%d_%d%d%d%d%d%d%.jpg$", record.file)
		end)

		it("adds instance info in an instance", function()
			wow.instance = { name = "Raid", type = "raid", difficultyID = 16, instanceID = 2657 }
			local db = newDb()
			local capture = new(db)
			capture:Take(batch("a"))
			capture:OnSucceeded()
			assert.same(
				{ name = "Raid", type = "raid", difficultyID = 16, instanceID = 2657 },
				db.captures[1].location.instance
			)
		end)

		it("prints once and records nothing on failure", function()
			local db = newDb()
			local capture = new(db)
			capture:Take(batch("a"))
			capture:OnFailed()
			assert.equal(0, #db.captures)
			assert.equal(1, #wow.chat)
			assert.is_false(capture:IsAwaiting())
		end)

		it("ignores a failure without a pending capture", function()
			new(newDb()):OnFailed()
			assert.equal(0, #wow.chat)
		end)

		it("turns a secret context value into nil", function()
			_G.UnitName = function()
				return wow.secret("x")
			end
			local db = newDb()
			local capture = new(db)
			capture:Take(batch("a"))
			capture:OnSucceeded()
			assert.is_nil(db.captures[1].character.name)
		end)
	end)

	describe("onCaptured", function()
		it("is called once with the stored record after it is stored", function()
			local db = newDb()
			local calls, storedAtCall = {}, nil
			local capture = new(db, function(record)
				calls[#calls + 1] = record
				storedAtCall = db.captures[1]
			end)
			capture:Take(batch("a"))
			capture:OnSucceeded()
			assert.equal(1, #calls)
			assert.equal(db.captures[1], calls[1])
			assert.equal(storedAtCall, calls[1])
		end)

		it("is not called on failure", function()
			local called = false
			local capture = new(newDb(), function()
				called = true
			end)
			capture:Take(batch("a"))
			capture:OnFailed()
			assert.is_false(called)
		end)

		it("is not called for a manual screenshot", function()
			local called = false
			new(newDb(), function()
				called = true
			end):OnSucceeded()
			assert.is_false(called)
		end)

		it("is not called after the await timeout", function()
			local called = false
			local capture = new(newDb(), function()
				called = true
			end)
			capture:Take(batch("a"))
			wow.advance(3)
			capture:OnSucceeded()
			assert.is_false(called)
		end)

		it("keeps the capture and keeps working when it raises", function()
			local db = newDb()
			local capture = new(db, function()
				error("boom")
			end)
			capture:Take(batch("a"))
			capture:OnSucceeded()
			assert.equal(1, #db.captures)
			wow.advance(2)
			capture:Take(batch("b"))
			capture:OnSucceeded()
			assert.equal(2, #db.captures)
			assert.same({}, wow.chat)
		end)
	end)

	describe("Note", function()
		local function labelOf(key)
			return ({ levelUp = "Level up", bossKill = "Boss kill" })[key]
		end

		local function events(...)
			local list = {}
			for _, key in ipairs({ ... }) do
				list[#list + 1] = { trigger = key }
			end
			return list
		end

		it("joins labels in event order", function()
			assert.equal("Level up, Boss kill", ns.Capture.Note(events("levelUp", "bossKill"), labelOf))
			assert.equal("Boss kill, Level up", ns.Capture.Note(events("bossKill", "levelUp"), labelOf))
		end)

		it("drops duplicate labels", function()
			assert.equal("Level up, Boss kill", ns.Capture.Note(events("levelUp", "bossKill", "levelUp"), labelOf))
		end)

		it("uses the key when no label exists", function()
			assert.equal("Level up, mystery", ns.Capture.Note(events("levelUp", "mystery"), labelOf))
		end)

		it("passes non-ASCII labels as they are", function()
			assert.equal(
				"Nivel é",
				ns.Capture.Note(events("x"), function()
					return "Nivel é"
				end)
			)
		end)

		it("returns nil for an empty list", function()
			assert.is_nil(ns.Capture.Note({}, labelOf))
			assert.is_nil(ns.Capture.Note(nil, labelOf))
		end)
	end)

	describe("FileName", function()
		local t = 1793560502
		local expected = os.date("%m%d%y_%H%M%S", t)
		it("maps the screenshot formats", function()
			assert.equal("WoWScrnShot_" .. expected .. ".jpg", ns.Capture.FileName(t, "jpeg"))
			assert.equal("WoWScrnShot_" .. expected .. ".jpg", ns.Capture.FileName(t, "jpg"))
			assert.equal("WoWScrnShot_" .. expected .. ".png", ns.Capture.FileName(t, "png"))
			assert.equal("WoWScrnShot_" .. expected .. ".tga", ns.Capture.FileName(t, "tga"))
			assert.equal("WoWScrnShot_" .. expected .. ".jpg", ns.Capture.FileName(t, nil))
			assert.equal("WoWScrnShot_" .. expected .. ".jpg", ns.Capture.FileName(t, "bmp"))
		end)
	end)

	describe("UtcOffset and IsoTime", function()
		local cases =
			{ { 0, "+00:00" }, { 3600, "+01:00" }, { 7200, "+02:00" }, { -18000, "-05:00" }, { 19800, "+05:30" } }
		for _, case in ipairs(cases) do
			it("handles offset " .. case[1], function()
				local base = { year = 2026, month = 10, day = 31, min = 15, sec = 2, isdst = false }
				_G.date = function(fmt)
					if fmt == "*t" then
						local tt = { year = 2026, month = 10, day = 31, hour = 12, min = 15, sec = 2, isdst = false }
						return tt
					elseif fmt == "!*t" then
						local tt =
							{ year = base.year, month = base.month, day = base.day, hour = 12, min = 15, sec = 2 }
						tt.sec = tt.sec - case[1]
						return tt
					end
					return "2026-10-31T12:15:02"
				end
				local offset = ns.Capture.UtcOffset(1)
				assert.equal(case[1], offset)
				assert.equal("2026-10-31T12:15:02" .. case[2], ns.Capture.IsoTime(1, offset))
			end)
		end
	end)
end)
