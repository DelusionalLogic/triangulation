local triang = require("triangulation")

local function read_test_input(path)
	local contents, size = love.filesystem.read(path)
	local nextLine = contents:gmatch("([^\n]*)\n?")
	local nvert, nedge = nextLine():match("(%d*) (%d*)")

	-- read verts
	local verts = {}
	for i = 1, nvert do
		local x, y = nextLine():match("(-?[%d%.]+) +(-?[%d%.]+)")
		table.insert(verts, {tonumber(x), tonumber(y)})
	end

	-- read edges
	local edges = {}
	for i = 1, nedge do
		local s, e = nextLine():match("(%d+) +(%d+)")
		table.insert(edges, {s+1, e+1})
	end

	return {
		v = verts,
		e = edges,
	}
end

local function triulate(poly)
	local box = bbox(poly)
	local face = superTri(box)

	local points = {}
	for i, v in ipairs(poly.v) do
		points[i] = triang.add_point(face, v)
	end

	for i, e in ipairs(poly.e) do
		triang.add_edge(face, points[e[1]], points[e[2]])
	end

	face = trim(face)
	return face, 0
end

local function smallest_vert(tris)
	local res = {}
	for k,tri in pairs(tris) do
		local small = 1
		for i = 2,3 do
			if tri[i] < tri[small] then
				small = i
			end
		end
		res[k] = small
	end

	return res
end

local function assert_matches_file(face, path)
	local contents, size = love.filesystem.read(path)
	local nextLine = contents:gmatch("([^\n]*)\n?")
	local ntris = tonumber(nextLine())

	local map = {}
	for k,v in pairs(face.t) do
		table.insert(map, k)
	end

	local stris = smallest_vert(face.t)
	table.sort(map, function(a, b)
		local ia, ib = stris[a], stris[b]
		for i = 1,3 do
			if face.t[a][ia] ~= face.t[b][ib] then
				return face.t[a][ia] < face.t[b][ib]
			end
			
			ia, ib = clockwise_vert(ia), clockwise_vert(ib)
		end

		return false
	end)

	local revmap = {}
	for k,v in ipairs(map) do
		revmap[v] = k
	end

	assert(ntris == #map)

	for _,v in ipairs(map) do
		local line = nextLine()
		local nextSymbolRaw = line:gmatch("(%d+)")
		local nextSymbol = function() return tonumber(nextSymbolRaw()) end

		local c = stris[v]
		for i = 1,3 do
			expected = nextSymbol()
			assert(face.t[v][c]-1 == expected)
			c = clockwise_vert(c)
		end

		local c = anticlockwise_vert(stris[v])
		for i = 1,3 do
			local adjtri = face.adj[v][c][1]
			if adjtri == nil then
				adjtri = 4294967295
			else
				adjtri = revmap[adjtri]-1
			end
			local expected = nextSymbol()
			print(adjtri, expected)
			assert(adjtri == expected)
			c = clockwise_vert(c)
		end
	end
end

-- local poly = read_test_input("test/cdtfile/inputs/capital_a.txt")
-- local face = triulate(poly)
-- assert_matches_file(face, "test/cdtfile/full/capital_a.txt")

local poly = read_test_input("test/cdtfile/inputs/cdt.txt")
local face = triulate(poly)
assert_matches_file(face, "test/cdtfile/full/cdt.txt")
