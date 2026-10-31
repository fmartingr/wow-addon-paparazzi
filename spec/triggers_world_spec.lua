local wow = require("helpers.wow")

describe("world triggers", function()
	describe("trade", function()
		local function boot()
			wow.boot({
				setup = function()
					local base = _G.UnitName
					_G.UnitName = function(unit)
						if unit == "NPC" then
							return "Partner"
						end
						return base and base(unit) or "Kaelys"
					end
				end,
			})
			PaparazziDB.settings.triggers.trade.enabled = true
		end

		it("shoots once when exactly one side accepts", function()
			boot()
			wow.fire("TRADE_SHOW")
			local record = wow.take("TRADE_ACCEPT_UPDATE", 1, 0)
			assert.equal("Partner", record.events[1].data.tradeTarget)
			assert.is_nil(wow.take("TRADE_ACCEPT_UPDATE", 0, 1))
		end)

		it("makes no shot when both or none accept", function()
			boot()
			wow.fire("TRADE_SHOW")
			assert.is_nil(wow.take("TRADE_ACCEPT_UPDATE", 1, 1))
			assert.is_nil(wow.take("TRADE_ACCEPT_UPDATE", 0, 0))
		end)

		it("shoots again for a new trade", function()
			boot()
			wow.fire("TRADE_SHOW")
			assert.is_not_nil(wow.take("TRADE_ACCEPT_UPDATE", 0, 1))
			wow.fire("TRADE_SHOW")
			assert.is_not_nil(wow.take("TRADE_ACCEPT_UPDATE", 1, 0))
		end)
	end)

	describe("login", function()
		it("shoots only on an initial login", function()
			wow.boot({})
			PaparazziDB.settings.triggers.login.enabled = true
			assert.is_nil(wow.take("PLAYER_ENTERING_WORLD", false, true))
			assert.same({ isInitialLogin = true }, wow.take("PLAYER_ENTERING_WORLD", true, false).events[1].data)
		end)
	end)

	describe("firstVisit", function()
		local mapID
		local function boot(withMapUtil)
			wow.boot({
				setup = function()
					mapID = 100
					_G.C_Map.GetBestMapForUnit = function()
						return mapID
					end
					if withMapUtil then
						_G.Enum = { UIMapType = { Zone = 3 } }
						_G.MapUtil = {
							GetMapParentInfo = function(id)
								return { mapID = id - 1 }
							end,
						}
					end
				end,
			})
			PaparazziDB.settings.triggers.firstVisit.enabled = true
		end

		it("marks the current location without a shot on PLAYER_ENTERING_WORLD", function()
			boot(true)
			assert.is_nil(wow.take("PLAYER_ENTERING_WORLD", false, false))
			assert.is_true(PaparazziDB.visited["Kaelys-Ragnaros"]["z:99"])
		end)

		it("shoots for a new zone and not for the same zone again", function()
			boot(true)
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			mapID = 200
			local data = wow.take("ZONE_CHANGED_NEW_AREA").events[1].data
			assert.same({ zoneName = "Dornogal", mapID = 200 }, data)
			assert.is_nil(wow.take("ZONE_CHANGED_NEW_AREA"))
		end)

		it("uses an instance key inside an instance", function()
			boot(true)
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			wow.instance = { name = "Raid", type = "raid", difficultyID = 1, instanceID = 2657 }
			local data = wow.take("ZONE_CHANGED_NEW_AREA").events[1].data
			assert.equal(2657, data.instanceID)
			assert.equal("raid", data.instanceType)
			assert.is_true(PaparazziDB.visited["Kaelys-Ragnaros"]["i:2657"])
		end)

		it("falls back to the zone name without MapUtil", function()
			boot(false)
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			assert.is_true(PaparazziDB.visited["Kaelys-Ragnaros"]["n:Dornogal"])
		end)

		it("falls back to the map when the parent has no map ID", function()
			boot(true)
			_G.MapUtil.GetMapParentInfo = function() end
			wow.fire("PLAYER_ENTERING_WORLD", false, false)
			assert.is_true(PaparazziDB.visited["Kaelys-Ragnaros"]["z:100"])
		end)

		it("makes no shot and no mark while the map is unknown", function()
			boot(true)
			mapID = nil
			assert.is_nil(wow.take("ZONE_CHANGED_NEW_AREA"))
			assert.is_nil(next(PaparazziDB.visited))
		end)
	end)
end)
