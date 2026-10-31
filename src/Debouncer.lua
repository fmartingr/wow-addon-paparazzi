local _, ns = ...

local Debouncer = {}
ns.Debouncer = Debouncer

function Debouncer.New(opts)
	local instance = {}
	local pending, timer

	local function arm(due)
		timer = opts.schedule(math.max(due - opts.now(), 0), function()
			local batch = pending
			pending, timer = nil, nil
			opts.onFire(batch)
		end)
	end

	function instance:Add(event, delay)
		local now = opts.now()
		if not pending then
			pending = { t0 = now, due0 = now + delay, due = now + delay, events = { event } }
			arm(pending.due)
			return
		end

		pending.events[#pending.events + 1] = event
		local capped = math.min(math.max(pending.due, now + delay), pending.t0 + opts.cap())
		local newDue = math.max(pending.due0, capped)
		if newDue ~= pending.due then
			timer:Cancel()
			pending.due = newDue
			arm(newDue)
		end
	end

	function instance:IsPending()
		return pending ~= nil
	end

	function instance:Reset()
		if timer then
			timer:Cancel()
		end
		pending, timer = nil, nil
	end

	return instance
end
