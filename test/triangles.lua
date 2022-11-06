local triang = require("triangulation")

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

local poly = {
	v = {
		{188.24725326577, 198.56691389086},
		{188.24831129832, 198.57033238668},
		{188.24901903632, 198.57934479594},
		{188.31486011627, 198.57356442124},
		{188.30205649258, 198.57377574665},
		{188.26689835673, 198.57815142771},
		{188.26413174457, 198.57864866444},
		{188.25619650041, 198.57838761515},
		{188.25425200814, 198.56911415881},
	},
	e = {
		{1, 2},
		{2, 3},
		{4, 5},
		{6, 7},
		{8, 9},
	},
}

local face = triangulate({poly})
assert(type(face) ~= "number")

local face = {
	v = {
		{100, 300},
		{200, 200},
		{200, 220},
		{500, 200},
		{600, 300},

		{150, 320},
		{300, 350},

		{200, 100},
		{150, 400},
		{550, 400},
		{700, 250},
	},
	t = {
		{1, 6, 2},
		{6, 3, 2},
		{6, 7, 3},
		{7, 2, 3},
		{7, 4, 2},
		{4, 7, 5},

		[100] = {1, 2, 8},
		[101] = {9, 6, 1},
		[102] = {9, 7, 6},
		[103] = {2, 4, 8},
		[104] = {10, 5, 7},
		[105] = {4, 5, 11},
	},
	e = {},
	adj = {
		{{2, 2}, {100, 3}, {101, 1}},
		{{4, 1}, {1, 1}, {3, 2}},
		{{4, 2}, {2, 3}, {102, 1}},
		{{2, 1}, {3, 1}, {5, 2}},
		{{103, 3}, {4, 3}, {6, 3}},
		{{104, 1}, {105, 3}, {5, 3}},

		[100] = {{103, 2},      nil, {  1, 2}},
		[101] = {{  1, 3},      nil, {102, 2}},
		[102] = {{  3, 3}, {101, 3},      nil},
		[103] = {     nil, {100, 1}, {  5, 1}},
		[104] = {{  6, 1},      nil,      nil},
		[105] = {     nil,      nil, {  6, 2}},
	},
	inv_t = {
		{1, 1},
		{1, 3},
		{2, 2},
		{5, 2},
		{6, 3},
		{1, 2},
		{3, 2},
		{100, 3},
		{101, 1},
		{104, 1},
		{105, 3},
	},
}
local res = triang.add_edge(face, 1, 5)

-- assert(contains_tri(face, 1, 3, 2))
local t0, t0v = find_tri(face, 1, 3, 2)
assert(t0 ~= nil)
local opp = opposing_tri(face, t0, t0v)
assert(is_tri(face, opp[1], opp[2], 4, 2, 3))
local opp = opposing_tri(face, t0, anticlockwise_vert(t0v))
assert(is_tri(face, opp[1], opp[2], 8, 1, 2))
local opp = opposing_tri(face, t0, clockwise_vert(t0v))
assert(is_tri(face, opp[1], opp[2], 5, 3, 1))

-- assert(contains_tri(face, 1, 5, 3))
local t0, t0v = find_tri(face, 1, 5, 3)
assert(t0 ~= nil)
local opp = opposing_tri(face, t0, t0v)
assert(is_tri(face, opp[1], opp[2], 4, 3, 5))
local opp = opposing_tri(face, t0, anticlockwise_vert(t0v))
assert(is_tri(face, opp[1], opp[2], 2, 1, 3))
local opp = opposing_tri(face, t0, clockwise_vert(t0v))
assert(is_tri(face, opp[1], opp[2], 6, 5, 1))
-- assert(contains_tri(face, 2, 3, 4))
local t0, t0v = find_tri(face, 2, 3, 4)
assert(t0 ~= nil)
local opp = opposing_tri(face, t0, t0v)
assert(is_tri(face, opp[1], opp[2], 4, 3, 5))
local opp = opposing_tri(face, t0, anticlockwise_vert(t0v))
assert(is_tri(face, opp[1], opp[2], 2, 1, 3))
local opp = opposing_tri(face, t0, clockwise_vert(t0v))
assert(is_tri(face, opp[1], opp[2], 6, 5, 1))
-- assert(contains_tri(face, 3, 5, 4))
-- assert(contains_tri(face, 3, 5, 4))
-- assert(contains_tri(face, 1, 6, 5))
-- assert(contains_tri(face, 6, 7, 5))
