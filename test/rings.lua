local rings = require("rings")

local function table_eq(value, expect)
	for k, v in pairs(value) do
		local expectt = expect[k]
		expect[k] = nil
		if v ~= nil and expectt == nil then
			return false
		end
		if type(v) == "table" then
			if not table_eq(v, expectt) then
				return false
			end
		elseif v ~= expectt then
			return false
		end
	end

	if next(expect) ~= nil then
		return false
	end

	return true
end

local function assert(cond, message)
	tests = tests + 1
	_G.assert(cond, message)
end

local nodes = {
	[1] = {0, 0},
	[2] = {0, 100},
	[3] = {100, 100},
	[4] = {100, 0},
}
local ways = {
	[1] = {refs = {1, 2, 3}},
	[2] = {refs = {1, 4, 3}},
	[3] = {refs = {1, 3}},
}
local relations = {
	[1] = {memids = {1, 2, 3}},
}

local status, err = pcall(rings.find, nodes, ways, relations[1])
assert(status == false)

local nodes = {
	[1] = {0, 0},
	[2] = {0, 100},
	[3] = {100, 100},
	[4] = {100, 0},
}
local ways = {
	[1] = {refs = {1, 2, 3}},
	[2] = {refs = {1, 4, 3}},
}
local relations = {
	[1] = {memids = {1, 2}},
}

local ring = rings.find(nodes, ways, relations[1])
assert(table_eq(ring, {{{1, 1}, {2, -1}}}))

local nodes = {
	[1] = {0, 0},
	[2] = {0, 100},
	[2] = {100, 100},
}
local ways = {
	[1] = {refs = {1, 2, 3, 1}},
}
local relations = {
	[1] = {memids = {1}},
}

local ring = rings.find(nodes, ways, relations[1])
assert(table_eq(ring, {{{1, 1}}}))
