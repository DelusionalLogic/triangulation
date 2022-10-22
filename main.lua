-- Based on the paper https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.61.3862&rep=rep1&type=pdf
-- and https://github.com/artem-ogre/CDT

local SAFE = false

outer = {
	v = {
		{0, 0},
		{100, 0},
		{300, 200},
		{0, 100},
	},
	e = {
		{1, 2},
		{2, 3},
		{3, 4},
		{4, 1},
	}
}

inner = {
	v = {
		{20, 20},
		{40, 20},
		{40, 40},
		{20, 40},
	},
	e = {
		{1, 2},
		{2, 3},
		{3, 4},
		{4, 1},
	}
}

function dline(p1, p2)
	love.graphics.line(p1[1]*zoom, p1[2]*zoom, p2[1]*zoom, p2[2]*zoom)
end

function drawEdges(verts, edges)
	for _, edge in pairs(edges) do
		start = verts[edge[1]]
		dest = verts[edge[2]]
		dline(start, dest)
	end
end

function drawTris(verts, tris, labels, edge_labels)
	for i, tri in pairs(tris) do
		v1 = verts[tri[1]]
		v2 = verts[tri[2]]
		v3 = verts[tri[3]]
		pv = {}
		for i, v in ipairs(tri) do
			pv[#pv+1] = verts[v][1] * zoom
			pv[#pv+1] = verts[v][2] * zoom
		end
		love.graphics.polygon("fill", pv)

		-- dline(verts[tri[1]], verts[tri[2]])
		-- dline(verts[tri[2]], verts[tri[3]])
		-- dline(verts[tri[3]], verts[tri[1]])
		-- love.graphics.print(labels[i], (v1[1]+v2[1]+v3[1])/3*zoom, (v1[2]+v2[2]+v3[2])/3*zoom)

		if incircle(v1, v2, v3, {mx, my}) then

		-- love.graphics.print(edge_labels[i][1], (v2[1]+v3[1])/2*zoom, (v2[2]+v3[2])/2*zoom)
		-- love.graphics.print(edge_labels[i][2], (v1[1]+v3[1])/2*zoom, (v1[2]+v3[2])/2*zoom)
		-- love.graphics.print(edge_labels[i][3], (v2[1]+v1[1])/2*zoom, (v2[2]+v1[2])/2*zoom)
			cx, cy = circumcenter(v1, v2, v3)
			cr = circumr(v1, v2, v3)
			-- love.graphics.points(cx, cy)
			love.graphics.circle("line", cx*zoom, cy*zoom, cr*zoom, 100)
		end
	end
end

local function pairsByKeys (t, f)
	local a = {}
	for n in pairs(t) do table.insert(a, n) end
	table.sort(a, f)
	local i = 0      -- iterator variable
	local iter = function ()   -- iterator function
		i = i + 1
		if a[i] == nil then return nil
		else return a[i], t[a[i]]
		end
	end
	return iter
end

function adj_tostr(adj)
	if adj == nil then
		return "<NIL>"
	end

	return tostring(adj[1])
end

function drawpol(pol)
	love.graphics.setLineWidth(.1)
	local verts = pol["v"]

	if pol.t ~= nil then

		local tris = pol.t
		local labels = {}
		for i, _ in pairs(tris) do
			labels[i] = tostring(i)
		end

		if true then
			local edge_labels = {}
			-- for i, v in pairs(pol.adj) do
			-- 	edge_labels[i] = {adj_tostr(v[1]), adj_tostr(v[2]), adj_tostr(v[3])}
			-- end

			drawTris(verts, tris, labels, edge_labels)
		else
			local v_tris = {}
			local i_tris = {}
			local nv_tris = {}
			local v_labels = {}
			local i_labels = {}
			local nv_labels = {}
			local offset = 0
			for i, v in pairs(tris) do
				if insides[i] == nil then
					table.insert(nv_tris, v)
					table.insert(nv_labels, labels[i])
				elseif insides[i] then
					table.insert(i_tris, v)
					table.insert(i_labels, labels[i])
				else
					table.insert(v_tris, v)
					table.insert(v_labels, labels[i])
				end
			end

			drawTris(verts, nv_tris, nv_labels, {})
			love.graphics.setColor(0, 0, 255)
			drawTris(verts, v_tris, v_labels, {})
			love.graphics.setColor(255, 0, 255)
			drawTris(verts, i_tris, i_labels, {})
			love.graphics.setColor(255, 255, 255)
		end
	end

	if pol.e ~= nil then
		if pol.t ~= nil then
			love.graphics.setColor(0, 255, 0)
			love.graphics.setLineWidth(.1)
		end

		drawEdges(verts, pol.e)

		love.graphics.setLineWidth(.1)
		love.graphics.setColor(255, 255, 255)
	end

	for i, vert in pairs(verts) do
		-- if i == 4 then
			love.graphics.setColor(255, 0, 0)
		-- end
		if i == 5 then
		-- love.graphics.print(tostring(i), vert[1]*zoom-10, vert[2]*zoom-10)
		end
		-- love.graphics.print(tostring(i), vert[1]*zoom+10, vert[2]*zoom+10)
		love.graphics.setColor(255, 255, 255)
	end
end

function bbox(poly)
	verts = poly["v"]
	min = verts[1]
	max = min
	for i, vert in pairs(verts) do
		min = {
			math.min(min[1], vert[1]),
			math.min(min[2], vert[2])
		}
		max = {
			math.max(max[1], vert[1]),
			math.max(max[2], vert[2])
		}
	end

	return {
		v = {
			min,
			{max[1], min[2]},
			max,
			{min[1], max[2]},
		},
		e = {
			{1, 2},
			{2, 3},
			{3, 4},
			{4, 1},
		}
	}
end

function superTri(bbox)
	verts = bbox["v"]
	center = {
		(verts[1][1] + verts[3][1]) / 2.0,
		(verts[1][2] + verts[3][2]) / 2.0,
	}
	size = {
		verts[3][1] - verts[1][1],
		verts[3][2] - verts[1][2],
	}
	inrad = math.sqrt(math.pow(size[1], 2) + math.pow(size[2], 2)) / 2
	outrad = inrad * 2
	stride = outrad * math.sqrt(3/2.0)
	return {
		v = {
			{center[1] - stride, center[2] - inrad},
			{center[1], center[2] + outrad},
			{center[1] + stride, center[2] - inrad},
		},
		t = {
			{1, 2, 3},
		},
		e={
		},
		adj={
			{{nil, nil}, {nil, nil}, {nil, nil}},
		},
		inv_t = {
			{1, 1},
			{1, 2},
			{1, 3},
		}
	}
end

function det(p1, p2)
	return (p1[1] * p2[2]) - (p1[2] * p2[1])
end

function readInt4(str, cursor)
	local value = 0
	value = bit.bor(bit.rshift(string.byte(str, cursor  ), 24), value)
	value = bit.bor(bit.rshift(string.byte(str, cursor+1), 16), value)
	value = bit.bor(bit.rshift(string.byte(str, cursor+2),  8), value)
	value = bit.bor(           string.byte(str, cursor+3)     , value)
	return value, cursor+4
end

local function int2bin(n)
	local result = ""
	while n ~= 0 do
		if bit.band(n, 0x1) == 0 then
			result = "0" .. result
		else
			result = "1" .. result
		end
		n = bit.rshift(n, 1)
	end
	return result
end

local ffi = require("ffi")
function readVarInt(str, cursor)
	local value = ffi.new("uint64_t", 0)
	local i = 0
	while true do
		local byte = ffi.new("uint64_t", string.byte(str, cursor))

		value = bit.bor(bit.lshift(bit.band(byte, 0x7F), i*7), value)

		cursor = cursor + 1
		-- print(int2bin(value))
		if bit.band(byte, 0x80) == 0 then
			break;
		end
		i = i + 1
	end

	return value, cursor
end

function readVarZig(str, cursor)
	local value, cursor = readVarInt(str, cursor)
	value = ffi.cast("int64_t", bit.bxor(bit.rshift(value, 1), bit.arshift(bit.lshift(value, 63), 63)))

	return value, cursor
end

function readKey(str, cursor)
	local value, cursor = readVarInt(str, cursor)

	local key = bit.rshift(value, 3)
	local t = bit.band(value, 0x3)

	return key, t, cursor
end

function readString(str, cursor)
	local len, cursor = readVarInt(str, cursor)
	len = tonumber(len)
	cursor = tonumber(cursor)

	return str:sub(cursor, cursor+len-1), cursor + len
end

function skip(str, cursor, t)
	if t == 0 then
		local _, cursor = readVarInt(str, cursor)
		return cursor
	elseif t == 1 then
		return cursor + 8
	elseif t == 2 then
		local len, cursor = readVarInt(str, cursor)
		return cursor + tonumber(len)
	elseif t == 3 or t == 4 then
		abort("")
	elseif t == 5 then
		return cursor + 4
	end
end

function buildindex(pbf)
	local index = {}

	file_end = #pbf + 1
	local cursor = 1
	while cursor < file_end do
		local header_len
		header_len, cursor = readInt4(pbf, cursor)
		local header_end = cursor + header_len

		local datatype
		local datasize
		while cursor < header_end do
			local key, t
			key, t, cursor = readKey(pbf, cursor)
			if key == 1 then
				datatype, cursor = readString(pbf, cursor)
			elseif key == 3 then
				datasize, cursor = readVarInt(pbf, cursor)
			else
				cursor = skip(pbf, cursor, t)
			end
		end
		if cursor > header_end then
			abort(1)
		end

		table.insert(index, {datatype, cursor, datasize})
		cursor = cursor + tonumber(datasize)
	end

	return index
end

function extractblob(pbf, cursor, datalen)
	local rawdata

	local data_end = cursor + datalen
	while cursor < data_end do
		local key, t
		key, t, cursor = readKey(pbf, cursor)
		if key == 1 then
			-- raw
			rawdata, cursor = readString(pbf, cursor)
		elseif key == 3 then
			-- zlib_data
			local compresseddata
			compresseddata, cursor = readString(pbf, cursor)
			rawdata = love.data.decompress("string", "zlib", compresseddata)
		else
			cursor = skip(pbf, cursor, t)
		end
	end
	if cursor > data_end then
		abort(1)
	end

	return rawdata
end

function parseChunk(rawdata)
	local granularity = 100 -- nanodegrees
	local latoff, lngoff = 0, 0 -- nanodegrees
	local dategran = 1000 -- ms

	local strings={}

	local nodes={}
	local ways={}
	local relations={}

	local function tohex(data)
		local str = ""
		for i = 1, #data do
			char = string.byte(data, i)
			str = string.format("%s%02x", str, char)
		end
		return str
	end


	local cursor = 1
	local data_end = #rawdata + 1
	while cursor < data_end do
		local key, t
		key, t, cursor = readKey(rawdata, cursor)
		if key == 1 then
			-- stringtable
			local data_len
			data_len, cursor = readVarInt(rawdata, cursor)
			local data_end = cursor + data_len
			while cursor < data_end do
				local key, t
				key, t, cursor = readKey(rawdata, cursor)
				if key == 1 then
					-- s
					local value
					value, cursor = readString(rawdata, cursor)
					table.insert(strings, value)
				else
					cursor = skip(rawdata, cursor, t)
				end
			end
			if cursor > data_end then
				abort(1)
			end
		elseif key == 2 then
			-- primitivegroup
			local data_len
			data_len, cursor = readVarInt(rawdata, cursor)
			local data_end = cursor + data_len
			while cursor < data_end do
				local key, t
				key, t, cursor = readKey(rawdata, cursor)
				if key == 2 then
					-- dense
					local nodeid = {}

					local data_len
					data_len, cursor = readVarInt(rawdata, cursor)
					local data_end = cursor + data_len
					while cursor < data_end do
						local key, t
						key, t, cursor = readKey(rawdata, cursor)
						if key == 1 then
							-- id
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							local last = 0
							while cursor < data_end do
								local value
								value, cursor = readVarZig(rawdata, cursor)
								value = ffi.cast("uint64_t", value + last)
								last = value

								nodeid[#nodeid+1] = tostring(value)
								nodes[tostring(value)] = {}
							end
						elseif key == 8 then
							-- lat
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							local last = 0
							local i = 1
							while cursor < data_end do
								local value
								value, cursor = readVarZig(rawdata, cursor)
								value = ffi.cast("uint64_t", value + last)
								last = value

								nodes[nodeid[i]][1] = tonumber(value)
								i = i + 1
							end
						elseif key == 9 then
							-- lon
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							local last = 0
							local i = 1
							while cursor < data_end do
								local value
								value, cursor = readVarZig(rawdata, cursor)
								value = ffi.cast("uint64_t", value + last)
								last = value

								nodes[nodeid[i]][2] = tonumber(value)
								i = i + 1
							end
						else
							cursor = skip(rawdata, cursor, t)
						end
					end
					if cursor > data_end then
						abort(1)
					end
				elseif key == 3 then
					-- way
					local way = {
						refs = {},
					}

					local data_len
					data_len, cursor = readVarInt(rawdata, cursor)
					local data_end = cursor + data_len
					while cursor < data_end do
						local key, t
						key, t, cursor = readKey(rawdata, cursor)
						if key == 1 then
							local value
							value, cursor = readVarInt(rawdata, cursor)
							way.id = value
						elseif key == 8 then
							assert(t == 2)
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							local last = 0
							while cursor < data_end do
								local org_cursor = cursor
								local rawvalue
								rawvalue, cursor = readVarZig(rawdata, cursor)
								local value = ffi.cast("uint64_t", rawvalue + last)
								last = value

								if way.id == 1011415294 then
									print(way.id)
									print(tohex(string.sub(rawdata, org_cursor, cursor-1)), cursor-org_cursor, rawvalue, value)
								end
								table.insert(way.refs, tostring(value))
							end
						else
							cursor = skip(rawdata, cursor, t)
						end
					end
					if cursor > data_end then
						abort(1)
					end
					ways[tostring(way.id)] = way
				elseif key == 4 then
					-- relations
					local relation = {
						roles_sid = {},
						memids = {},
						types = {},
						keys = {},
						values = {},
					}

					local data_len
					data_len, cursor = readVarInt(rawdata, cursor)
					local data_end = cursor + data_len
					while cursor < data_end do
						local key, t
						key, t, cursor = readKey(rawdata, cursor)
						if key == 1 then
							-- id
							local value
							value, cursor = readVarInt(rawdata, cursor)
							relation.id = value
						elseif key == 2 then
							-- keys
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							while cursor < data_end do
								local value
								value, cursor = readVarInt(rawdata, cursor)
								table.insert(relation.keys, value+1)
							end
							if cursor > data_end then
								abort(1)
							end
						elseif key == 3 then
							-- values
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							while cursor < data_end do
								local value
								value, cursor = readVarInt(rawdata, cursor)
								table.insert(relation.values, value+1)
							end
							if cursor > data_end then
								abort(1)
							end
						elseif key == 8 then
							-- roles_sid
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							while cursor < data_end do
								local value
								value, cursor = readVarInt(rawdata, cursor)
								table.insert(relation.roles_sid, value+1)
							end
							if cursor > data_end then
								abort(1)
							end
						elseif key == 9 then
							-- memids
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							local last = ffi.new("uint64_t", 0)
							while cursor < data_end do
								local value
								value, cursor = readVarZig(rawdata, cursor)
								value = ffi.cast("uint64_t", value + last)
								last = value

								table.insert(relation.memids, tostring(value))
							end
							if cursor > data_end then
								abort(1)
							end
						elseif key == 10 then
							-- types
							local data_len
							data_len, cursor = readVarInt(rawdata, cursor)
							local data_end = cursor + data_len
							while cursor < data_end do
								local value
								value, cursor = readVarInt(rawdata, cursor)

								table.insert(relation.types, value)
							end
							if cursor > data_end then
								abort(1)
							end
						else
							cursor = skip(rawdata, cursor, t)
						end
					end
					if cursor > data_end then
						abort(1)
					end

					for i, v in pairs(relation.roles_sid) do
						relation.roles_sid[i] = strings[tonumber(v)]
					end

					local typeindex, nameindex = nil, nil
					for i, key in ipairs(relation.keys) do
						if strings[tonumber(key)] == "type" then
							typeindex = i
						elseif strings[tonumber(key)] == "name" then
							nameindex = i
						end

						if typeindex ~= nil and nameindex ~= nil then
							break
						end
					end
					if typeindex ~= nil and nameindex ~= nil then
						if strings[tonumber(relation.values[typeindex])] == "multipolygon" and strings[tonumber(relation.values[nameindex])] == "Jylland" then
							relations[relation.id] = relation
						end
					end
				else
					cursor = skip(rawdata, cursor, t)
				end
			end
			if cursor > data_end then
				abort(1)
			end
		else
			cursor = skip(rawdata, cursor, t)
		end
	end
	if cursor > data_end then
		abort(1)
	end

	return nodes, ways, relations
end

function rpairs(tbl)
	local n = #tbl+1
	return function()
		n = n - 1
		if n >= 1 then return n, tbl[n] end
	end
end

local json = require("json")
local rings = require("rings")
local testlib = require("testlib")
local poly = nil
local nextline = nil
function love.load(args)
	for i, arg in ipairs(args) do
		if arg == "--test" then
			testlib.run()
		end
	end

	love.graphics.setPointSize(10)

	if not love.filesystem.exists("poly.nl") then
		nodes, ways, relations = {}, {}, {}

		local pbf, _ = love.filesystem.read("denmark-latest.osm.pbf")
		local cursor = 1
		local header_len, cursor = readInt4(pbf, cursor)

		local index = buildindex(pbf)

		local rawdata = extractblob(pbf, index[1][2], index[1][3])

		-- local required = {}
		-- local optional = {}

		-- local cursor = 1
		-- local data_end = #rawdata + 1
		-- while cursor < data_end do
		-- 	local key, t
		-- 	key, t, cursor = readKey(rawdata, cursor)
		-- 	if key == 4 then
		-- 		-- required_features
		-- 		local feature
		-- 		feature, cursor = readString(rawdata, cursor)
		-- 		table.insert(required, feature)
		-- 	elseif key == 5 then
		-- 		-- optional_features
		-- 		local feature
		-- 		feature, cursor = readString(rawdata, cursor)
		-- 		table.insert(optional, feature)
		-- 	else
		-- 		cursor = skip(rawdata, cursor, t)
		-- 	end
		-- end
		-- if cursor > data_end then
		-- 	abort(1)
		-- end

		-- table_print(required)
		-- table_print(optional)

		for i, chunk in ipairs(index) do
			print(string.format("%d/%d", i, #index))
			if chunk[1] == "OSMData" then
				local rawdata = extractblob(pbf, chunk[2], chunk[3])
				mynodes, myways, myrelations = parseChunk(rawdata)

				for k, node in pairs(mynodes) do
					nodes[k] = node
				end
				for k, way in pairs(myways) do
					ways[k] = way
				end
				for k, v in pairs(myrelations) do
					relations[k] = v
				end
			end
		end

		-- table_print(nodes)
		-- table_print(ways)
		-- table_print(relations)

		local ri, rv = next(relations)
		print(ri)
		local relation = relations[ri]
		for k,v in pairs(relation.memids) do
			-- print(v, ways[v])
			-- print(1011415294, ways[1011415294])
			for k2, v2 in pairs(ways[v].refs) do
				assert(nodes[v2] ~= nil, "Node not available: " .. v2 .. " of way " .. v)
			end
		end
		local rings = rings.find(nodes, ways, relation)
		-- table_print(rings)

		function build_poly(ring, nodes, ways)
			local poly = {
				v={},
				e={},
			}
			local lastv = nil
			local skip = 0
			local first_way = true
			for k, v in ipairs(ring) do
				local it
				if v[2] == -1 then
					it = rpairs
				else
					it = ipairs
				end
				assert(it ~= nil)

				local skip_vert = true
				if first_way then
					skip_vert = false
				end
				for k2, v2 in it(ways[v[1]].refs) do
					print(k, v[1], v[2], k2, v2, nodes[v2][1]/10000000, nodes[v2][2]/10000000)
					if not skip_vert then
						if skip == 0 then
							local x, y = transform(nodes[v2][2]/10000000, nodes[v2][1]/10000000)

							local newv = #poly.v+1
							poly.v[newv] = {x, y}

							if lastv ~= nil then
								poly.e[#poly.e+1] = {lastv, newv}
							end
							lastv = newv
						end
					else
						local x, y = transform(nodes[v2][2]/10000000, nodes[v2][1]/10000000)
						table_print({poly.v[lastv], x, y})
						assert(poly.v[lastv][1] == x)
						assert(poly.v[lastv][2] == y)
					end
					skip_vert = false
					-- skip = (skip + 1) % 100
				end
				first_way = false
			end
			poly.e[#poly.e] = {lastv, 1}

			return poly
		end


		local poly = {
			v = {
				{161.40833445764,188.10104040775},
				{161.28038400715,188.07659031998},
				{161.27615187693,188.07471718271},
				{172.50222043322,192.11390980678},
			},
			e = {
				{1, 2},
				{3, 4},
			},
		}
		for k, v in pairs(poly.v) do
			poly.v[k][1] = (v[1]-160) * 160
			poly.v[k][2] = (v[2]-180) * 160
		end
		poly = build_poly(rings[1], nodes, ways)
		pbf = nil
		ri = nil
		rv = nil
		relation = nil
		rings = nil
		nodes = nil
		ways = nil
		relations = nil
		index = nil

		file, err = love.filesystem.newFile("poly.nl", "w")
		file:write("state nodes\n")
		for k,v in pairs(poly.v) do
			file:write("x")
			file:write(tostring(v[1]))
			file:write(" y")
			file:write(tostring(v[2]))
			file:write("\n")
		end
		file:write("state edges\n")
		for k,v in pairs(poly.e) do
			file:write("p1")
			file:write(tostring(v[1]))
			file:write(" p2")
			file:write(tostring(v[2]))
			file:write("\n")
		end
		file:close()
	else
		-- poly = {
		-- 	v = {
		-- 		{188.24725326577, 198.56691389086},
		-- 		{188.24831129832, 198.57033238668},
		-- 		{188.24901903632, 198.57934479594},
		-- 		{188.31486011627, 198.57356442124},
		-- 		{188.30205649258, 198.57377574665},
		-- 		{188.26689835673, 198.57815142771},
		-- 		{188.26413174457, 198.57864866444},
		-- 		{188.25619650041, 198.57838761515},
		-- 		{188.25425200814, 198.56911415881},
		-- 	},
		-- 	e = {
		-- 		{1, 2},
		-- 		{2, 3},
		-- 		{4, 5},
		-- 		{6, 7},
		-- 		{8, 9},
		-- 	},
		-- }
		-- for k, v in ipairs(poly.v) do
		-- 	v[1] = v[1] - 188.2
		-- 	v[1] = v[1] * 10000
		-- 	v[2] = v[2] - 198.5
		-- 	v[2] = v[2] * 10000
		-- end
		file, err = love.filesystem.newFile("poly.nl", "r")

		local state = "nodes"
		poly = {
			v = {},
			e = {},
		}
		for line in file:lines() do
			if string.sub(line, 1, 5) == "state" then
				state = string.sub(line, 7)
			elseif state == "nodes" then
				local x, y = string.match(line, "^x(%d+%.%d+) y(%d+%.%d+)")
				local vert = {
					tonumber(x),
					tonumber(y),
				}
				table.insert(poly.v, vert)
			elseif state == "edges" then
				local p1, p2 = string.match(line, "^p1(%d+) p2(%d+)")
				local edge = {
					tonumber(p1),
					tonumber(p2),
				}
				table.insert(poly.e, edge)
			end
		end
		file:close()
	end
	-- table_print(poly)
	-- print(winding(poly))

	local smallpoly = {
		v = poly.v,
		e = {},
	}

	-- print(#poly.e)
	-- 63868+63874=127742
	for i=1,#poly.e do
		smallpoly.e[i] = poly.e[i]
	end

	if false then
		smallpoly = {
			v = {
				{100, 100},
				{150, 150},
				{200, 150},
				{250, 100},
				{200, 50},
				{150, 50},
			},
			e = {
				{1, 2},
				{2, 3},
				{3, 4},
				{4, 5},
				{5, 6},
				{6, 1},
			}
		}
	end

	if false then
		face = {
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

				[100] = {nil, nil, nil},
				[101] = {nil, nil, nil},
				[102] = {nil, nil, nil},
				[103] = {nil, nil, nil},
				[104] = {nil, nil, nil},
				[105] = {nil, nil, nil},
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
		assert(check(face))
		local res = add_edge(face, 1, 5)
		table_print(face)
		assert(res)
	else
		local profiler = require("profiler")
		profiler.start()
		face, i = triangulate({smallpoly})
		if type(face) == "number" then
			print("Triangulation failed, distilling error case")
			local minex = bisect_triangulate(poly, i)
			print("DONE, Found minimal example:")
			local vertnum = 1
			local vertset = {}
			io.write(string.format("v = {\n"))
			for _, edgei in pairs(minex) do
				local v1i, v2i = poly.e[edgei][1], poly.e[edgei][2]
				if vertset[v1i] == nil then
					vertset[v1i] = vertnum
					vertnum = vertnum + 1
					io.write(string.format("    {%.11f, %.11f},\n", poly.v[v1i][1], poly.v[v1i][2]))
				end
				if vertset[v2i] == nil then
					vertset[v2i] = vertnum
					vertnum = vertnum + 1
					io.write(string.format("    {%.11f, %.11f},\n", poly.v[v2i][1], poly.v[v2i][2]))
				end
			end
			io.write(string.format("},\ne = {\n"))
			for _, edgei in pairs(minex) do
				local v1i, v2i = poly.e[edgei][1], poly.e[edgei][2]
				io.write(string.format("    {%d, %d},\n", vertset[v1i], vertset[v2i]))
			end
			io.write(string.format("},\n"))
			face = {
				v = {},
				e = {},
				t = {},
			}
		end
		-- Code block and/or called functions to profile --
		profiler.stop()
		profiler.report("profiler.log")
	end

	-- local rings = {
	-- 	{}
	-- }
	-- for j = 1, #ways[relation.memids[1]].refs do
	-- 	table.insert(rings[1], relation.memids[1])
	-- end
	-- local unmatched = {}
	-- for i, wid in ipairs(relation.memids) do
	-- 	if i == 1 then
	-- 	else
	-- 		table.insert(unmatched, wid)
	-- 	end
	-- end

	-- while true do
	-- 	local current = ways[rings[#rings]].refs
	-- 	local lastnode = current[#current]
	-- 	local nextway
	-- 	for i, wid in ipairs(unmatched) do
	-- 		print("compare", ways[wid].refs[1], lastnode)
	-- 		if ways[wid].refs[1] == lastnode then
	-- 			for j = 1, #ways[wid].refs - 1 do
	-- 				table.insert(current, ways[wid].refs[j])
	-- 			end
	-- 			table.remove(unmatched, i)
	-- 			if ways[wid].refs[#ways[wid].refs] == current[1] then
	-- 				print("END")
	-- 			else
	-- 				table.insert(current, ways[wid].refs[#ways[wid].refs])
	-- 			end
	-- 			goto found
	-- 		end
	-- 		print("compare", ways[wid].refs[#ways[wid].refs], lastnode)
	-- 		if ways[wid].refs[#ways[wid].refs] == lastnode then
	-- 			-- reverse the nodes
	-- 			for j = #ways[wid].refs, 2, -1 do
	-- 				table.insert(current, ways[wid].refs[j])
	-- 			end
	-- 			table.remove(unmatched, i)
	-- 			if ways[wid].refs[1] == current[1] then
	-- 				print("END")
	-- 			else
	-- 				table.insert(current, ways[wid].refs[1])
	-- 			end
	-- 			goto found
	-- 		end
	-- 	end
	-- 	table_print(rings)
	-- 	print("Could not find a match for", lastnode)
	-- 	abort(1)

	-- 	::found::
	-- 	table_print(rings)
	-- end

	-- assert(#rings[1] == #relation.memids)

	-- nodes = {
	-- 	[1] = {0, 0},
	-- 	[2] = {0, 100},
	-- 	[3] = {100, 100},
	-- 	[4] = {100, 0},
	-- }
	-- ways = {
	-- 	[1] = {refs = {1, 2, 3}},
	-- 	[2] = {refs = {1, 4, 3}},
	-- 	[3] = {refs = {1, 3}},
	-- }
	-- relations = {
	-- 	[1] = {memids = {1, 2, 3}},
	-- }

	-- local rings = require("rings")
	-- local ring = rings.find(nodes, ways, relations[1])

	-- print("Res")
	-- table_print(ring)
end

function find_closest_vert(face, p)
	-- If you had some sort of cool R-tree here you could probably make this
	-- fast
	local closest = nil
	local closest_dist = nil
	for i, v in ipairs(face.v) do
		local dx, dy = p[1] - v[1], p[2] - v[2]
		local dist = vec_len_sq(dx, dy)
		if closest == nil or dist < closest_dist then
			closest = i
			closest_dist = dist
		end
	end

	return closest
end

function find_tri_with_vert(face, needle)
	if true then
		local tbl = face.inv_t[needle]
		return tbl[1], tbl[2]
	else
		-- for i, tri in pairs(face.t) do
		-- 	for i2, v in ipairs(tri) do
		-- 		if v == needle then
		-- 			return i, i2
		-- 		end
		-- 	end
		-- end
	end
end

function unpack_or_nil(tbl)
	if tbl == nil then
		return nil, nil
	end

	return unpack(tbl)
end

-- based on
-- https://ntrs.nasa.gov/api/citations/19770025881/downloads/19770025881.pdf
-- section 2.4, Yeah it feels pretty cool to implement something based on JPL's
-- work in 1977.
function find_containing_tri(face, p, start_tri)
	local tri, triv = start_tri, 1
	if start_tri == nil then
		local vert = find_closest_vert(face, p)
		tri, triv = find_tri_with_vert(face, vert)
	end

	local containing_tri = nil
	while true do
		if tri == nil then
			break
		end

		local found = true
		for i=1, 3 do
			local vo = face.t[tri][triv]
			local vn = face.t[tri][anticlockwise_vert(triv)]
			local vpx, vpy = vec_minus(face.v[vo][1], face.v[vo][2], p[1], p[2])
			local vnx, vny = vec_minus(face.v[vo][1], face.v[vo][2], face.v[vn][1], face.v[vn][2])

			local cross = vec_cross(vnx, vny, vpx, vpy)
			if cross > 0 then
				found = false
				break
			end
			triv = anticlockwise_vert(triv)
		end

		if found then
			containing_tri = tri
			break
		end

		tri, triv = unpack_or_nil(opposing_tri(face, tri, clockwise_vert(triv)))
	end

	if false then
		function point_inside_tri(p, face, tri)
			verts = face["v"]
			v0 = verts[tri[1]]
			v1 = {verts[tri[2]][1] - v0[1], verts[tri[2]][2] - v0[2]}
			v2 = {verts[tri[3]][1] - v0[1], verts[tri[3]][2] - v0[2]}

			div = det(v1, v2)

			a = (det(p, v2) - det(v0, v2)) / div
			b = -(det(p, v1) - det(v0, v1)) / div
			inside = a > 0 and b > 0 and a + b < 1
			return inside
		end

		-- Disabled. Kept for compat testing
		for i, tri in pairs(face.t) do
			if point_inside_tri(p, face, tri) then
				assert(containing_tri == i)
				return i
			end
		end
	end
	return containing_tri
end

function opposing_tri(face, tri, vert)
	-- local others = {}
	-- local tri_v = vert

	-- if SAFE then
	-- 	for i, v in pairs(face.t[tri]) do
	-- 		if v ~= face.t[tri][vert] then
	-- 			others[v] = true
	-- 		end
	-- 	end
	-- end

	assert(vert ~= nil)
	assert(vert <= 3)
	assert(vert >= 1)
	-- if true then
		return face.adj[tri][vert]
	-- elseif false then
	-- 	for i, stri in pairs(face.t) do
	-- 		local unmatched = nil
	-- 		for j, v in ipairs(stri) do
	-- 			if others[v] ~= true then
	-- 				if unmatched ~= nil then
	-- 					unmatched = nil
	-- 					break
	-- 				end
	-- 				unmatched = j
	-- 			end
	-- 		end
	-- 		if unmatched ~= nil and stri[unmatched] ~= face.t[tri][vert] then
	-- 			assert(face.adj[tri][tri_v] == i)
	-- 			return i, unmatched
	-- 		end
	-- 	end

	-- 	assert(face.adj[tri][tri_v] == nil)
	-- 	return nil
	-- else
	-- 	local i, tv = unpack_or_nil(face.adj[tri][tri_v])
	-- 	if i == nil then
	-- 		return nil
	-- 	end

	-- 	if SAFE then
	-- 		-- table_print({face, tri, vert, others, i})
	-- 		assert(i ~= tri)
	-- 		local unmatched = nil
	-- 		local match = 0
	-- 		for j, v in ipairs(face.t[i]) do
	-- 			if others[v] ~= true then
	-- 				if unmatched ~= nil then
	-- 					table_print({"Multiple nodes were unmatched", face, i, unmatched, j, others, tv})
	-- 					assert(false)
	-- 				end
	-- 				unmatched = j
	-- 			else
	-- 				match = match + 1
	-- 			end
	-- 		end
	-- 		assert(match == 2)
	-- 		assert(unmatched ~= nil)
	-- 		assert(face.t[i][unmatched] ~= face.t[tri][vert])
	-- 		assert(unmatched == tv)
	-- 	end

	-- 	return {i, tv}
	-- end
end

function incircle(a, b, c, d)
	local adx = a[1] - d[1]
	local ady = a[2] - d[2]
	local bdx = b[1] - d[1]
	local bdy = b[2] - d[2]
	local cdx = c[1] - d[1]
	local cdy = c[2] - d[2]

	local bcdet = bdx * cdy - bdy * cdx
	local cadet = cdx * ady - cdy * adx
	local abdet = adx * bdy - ady * bdx

	local alift = adx * adx + ady * ady
	local blift = bdx * bdx + bdy * bdy
	local clift = cdx * cdx + cdy * cdy

	local deter = alift * bcdet + blift * cadet + clift * abdet
	return deter <= 0
end

function split_tri(face, tri1, p)
	local tri = face.t[tri1]
	local v0 = tri[1]
	local v1 = tri[2]
	local v2 = tri[3]

	local o0 = opposing_tri(face, tri1, 1)
	local o1 = opposing_tri(face, tri1, 2)
	local o2 = opposing_tri(face, tri1, 3)

	local v3 = #face.v+1
	face.v[v3] = p
	-- Original tri becomes v0 v1 v3
	tri[3] = v3
	local tri2 = {v1, v2, v3}
	local tri3 = {v2, v0, v3}
	-- Insert the new tris
	local tri2i = #face.t+1
	face.t[tri2i] = tri2
	local tri3i = #face.t+1
	face.t[tri3i] = tri3

	if o0 ~= nil and o0[1] ~= nil then
		face.adj[o0[1]][o0[2]] = {tri2i, 3}
	end
	if o1 ~= nil and o1[1] ~= nil then
		face.adj[o1[1]][o1[2]] = {tri3i, 3}
	end
	if o2 ~= nil and o2[1] ~= nil then
		face.adj[o2[1]][o2[2]] = {tri1, 3}
	end

	face.adj[tri3i] = {{tri1, 2}, {tri2i, 1}, o1}
	face.adj[tri2i] = {{tri3i, 2}, {tri1, 1}, o0}
	face.adj[tri1] = {{tri2i, 2}, {tri3i, 1}, o2}

	face.inv_t[v0] = {tri1, 1}
	face.inv_t[v1] = {tri1, 2}
	face.inv_t[v2] = {tri2i, 2}
	face.inv_t[v3] = {tri1, 3}

	return tri2i, tri3i
end

function anticlockwise_vert(vert)
	vert = vert % 3
	vert = vert + 1
	return vert
end

function clockwise_vert(vert)
	vert = vert - 1
	if vert <= 0 then
		vert = 3
	end
	return vert
end

function vec_minus(x1, y1, x2, y2)
	return x1-x2, y1-y2
end
function vec_neg(x1, y1)
	return -x1, -y1
end
function vec_len_sq(x, y)
	return math.pow(x, 2) + math.pow(y, 2)
end
function vec_len(x, y)
	return math.sqrt(vec_len_sq(x, y))
end
function vec_unit(x, y)
	local len = vec_len(x, y)
	return x/len, y/len
end
function vec_dot(x1, y1, x2, y2)
	return x1 * x2 + y1 * y2
end
function vec_cross(x1, y1, x2, y2)
	return x1 * y2 - y1 * x2
end
function vecu_angle(x1, y1, x2, y2)
	return math.acos(vec_dot(x1, y1, x2, y2))
end

function circumr(p1, p2, p3)
	c = vec_len(vec_minus(p2[1], p2[2], p1[1], p1[2]))
	b = vec_len(vec_minus(p3[1], p3[2], p1[1], p1[2]))
	a = vec_len(vec_minus(p3[1], p3[2], p2[1], p2[2]))

	radius = (a * b * c) / math.sqrt((a+b+c) * (b+c-a) * (c+a-b) * (a+b-c))
	return radius
end

function circumcenter(p1, p2, p3)
	abx, aby = vec_unit(vec_minus(p2[1], p2[2], p1[1], p1[2]))
	acx, acy = vec_unit(vec_minus(p3[1], p3[2], p1[1], p1[2]))

	bcx, bcy = vec_unit(vec_minus(p3[1], p3[2], p2[1], p2[2]))
	bax, bay = vec_neg(abx, aby)

	cax, cay = vec_neg(acx, acy)
	cbx, cby = vec_neg(bcx, bcy)

	arc1 = vecu_angle(abx, aby, acx, acy)
	arc2 = vecu_angle(bcx, bcy, bax, bay)
	arc3 = vecu_angle(cax, cay, cbx, cby)

	local sinstuff = math.sin(2*arc1) + math.sin(2*arc2) + math.sin(2*arc3)

	local x = p1[1] * math.sin(2*arc1) + p2[1] * math.sin(2*arc2) + p3[1] * math.sin(2*arc3)
	x = x / sinstuff

	local y = p1[2] * math.sin(2*arc1) + p2[2] * math.sin(2*arc2) + p3[2] * math.sin(2*arc3)
	y = y / sinstuff

	return x, y
end

local vbefore = {}
insides = {}
local offx, offy = 0, 0
local max_cnt = 0
zoom = 1

local function is_fixed(face, a, b)
	return face.e[string.format("%d.%d", a, b)] ~= nil or face.e[string.format("%d.%d", b, a)] ~= nil
end

-- Keep vout 1 and 2 in counterclockwise order
function trim(face)
	print("trim", max_cnt)
	local tri_cursor, tri_vert = find_tri_with_vert(face, 1)

	local visited = {}

	--  This will end up with one value for each tri
	insides = {
		[tri_cursor] = false,
	}
	local stack = {tri_cursor}

	local tri = nil
	-- local cnt = 0
	while true do
		-- cnt = cnt + 1
		-- if cnt > max_cnt then
		-- 	return
		-- end
		if tri == nil then
			tri = table.remove(stack)
			if tri == nil then
				break
			end
		end

		local start_vert = tri_vert

		local next_tri = nil
		for i = 1,3 do
			local tseg, vseg = unpack_or_nil(opposing_tri(face, tri, i))

			if tseg ~= nil and visited[tseg] == nil then
				visited[tseg] = true
				local s1 = face.t[tseg][clockwise_vert(vseg)]
				local s2 = face.t[tseg][anticlockwise_vert(vseg)]
				insides[tseg] = insides[tri] ~= is_fixed(face, s1, s2)

				if next_tri == nil then
					next_tri = tseg
				else
					table.insert(stack, tseg)
				end
			end
		end

		tri = next_tri
	end

	local verts = {}
	local newface = {
		t = {},
		v = {},
	}

	-- Copy over the face
	for tri, inside in ipairs(insides) do
		if inside then
			local newt = #newface.t+1

			for i, v in ipairs(face.t[tri]) do
				if verts[v] == nil then
					newi = #newface.v+1
					newface.v[newi] = face.v[v]
					verts[v] = newi
				end
			end

			newface.t[newt] = {verts[face.t[tri][1]], verts[face.t[tri][2]], verts[face.t[tri][3]]}
		end
	end

	return newface
end

local RANGE = {}
local SOLO = {}

function range_create(start, end_)
	assert(start <= end_)
	if start == end_ then
		return {SOLO, start}
	else
		return {RANGE, start, end_}
	end
end

function range_split(range)
	assert(range[1] == RANGE)

	local start, end_ = range[2], range[3]
	local range_num = (end_ - start) + 1
	local mid = math.floor(range_num/2) + start
	return range_create(start, mid-1), range_create(mid, end_)
end

function range_str(range)
	if range[1] == RANGE then
		return string.format("[%d,%d]", range[2], range[3])
	else
		return string.format("%d", range[2])
	end
end

function range_min(range)
	return range[2]
end

function range_max(range)
	if range[1] == RANGE then
		return range[3]
	else
		return range[2]
	end
end

function bisect_triangulate(poly, crashpoint)
	-- Distill a triangulation error case by removing edges and seeing if it
	-- still crashes. We try to remove the first half of the edges and check if
	-- it still fails. If it does, we didn't need those edges. If it stops
	-- failing we know that we needed at least someof the edges in the range,
	-- so we subdivide that range again. We start at the lower end since those
	-- are less likely to affect the crash.
	local max = crashpoint-1
	local found_needed = {}
	local s1, s2 = range_split(range_create(1, max))
	local stack = {s2, s1}
	while #stack > 0 do
		local elem = table.remove(stack)
		print("Checking without range", range_str(elem))

		-- Build the new test poly
		local tpoly = {
			v = poly.v,
			e = {},
		}

		for k, v in ipairs(found_needed) do
				print("Copy in", v)
				table.insert(tpoly.e, poly.e[v])
		end
		for k, v in rpairs(stack) do
			print("Copy in range", range_str(v))
			-- Copy over all the unprocessed ranges in the "stack"
			for j = range_min(v), range_max(v) do
				table.insert(tpoly.e, poly.e[j])
			end
		end
		-- Also insert the final edge which triggers the abort
		print("Insert the crashpoint")
		table.insert(tpoly.e, poly.e[crashpoint])

		local face, _ = triangulate({tpoly})
		if type(face) == "number" then
			-- It still failed, so we don't need this
			print("Failed, discard range")
		else
			-- Didn't fail, we need some of these
			if elem[1] == SOLO then
				table.insert(found_needed, elem[2])
			else
				local s1, s2 = range_split(elem)
				table.insert(stack, s2)
				table.insert(stack, s1)
			end
		end
	end

	table.insert(found_needed, crashpoint)
	return found_needed
end

local triang = require("triangulation")
function triangulate(polys)
	local box = bbox(polys[1])
	local face = superTri(box)

	for polyi, poly in ipairs(polys) do
		local points = {}
		-- for i, v in ipairs(poly.v) do
		-- 	points[i] = add_point(face, v)
		-- end

		for i, e in ipairs(poly.e) do
			-- if i < 1374 or (i > 1375 and i < 1415) or (i > 1415 and i < 1418) or (i > 1418 and i < 1423) then
			-- else
				if points[e[1]] == nil then
					points[e[1]] = triang.add_point(face, poly.v[e[1]])
				end
				if points[e[2]] == nil then
					points[e[2]] = triang.add_point(face, poly.v[e[2]])
				end
				if not check(face) then
					error("Incorrect face")
				end
				print("Edge", i)
				if triang.add_edge(face, points[e[1]], points[e[2]]) == false then
					return polyi, i
				end
			-- end
		end
	end

	if not check(face) then
		error("Incorrect face")
	end
	-- drawpol(polys[1])
	face = trim(face)
	return face, 0
end

function love.draw()
	love.graphics.translate(offx, offy)
	-- love.graphics.scale(zoom, zoom)
	-- drawpol(outer)
	-- drawpol(inner)
	-- print(circumcenter({0,2}, {0,0}, {2,0}))
	-- love.exit(1)

	-- drawpol(box)

	-- p = {100, 100}
	-- add_point(sutri, p)
	-- love.graphics.points(p[1], p[2])
	-- p = {300, 200}
	-- add_point(sutri, p)
	-- love.graphics.points(p[1], p[2])
	-- p = {0, 200}
	-- add_point(sutri, p)
	-- love.graphics.points(p[1], p[2])
	-- p = {200, 100}
	-- add_point(sutri, p)
	-- love.graphics.points(p[1], p[2])

	-- add_edge(sutri, 4, 2)

	-- p = {100, 200}
	-- add_point(sutri, p)
	-- love.graphics.points(p[1], p[2])

	-- sutri = {
	-- 	v = {
	-- 		{0, 0},
	-- 		{50, 50},
	-- 		{100, 0},
	-- 	},
	-- 	t = {
	-- 		{1, 2, 3},
	-- 	}
	-- }
	--

	-- f, n = love.filesystem.read("denmark.poly")
	-- it = magiclines(f)

	-- -- Skip 2 first garbage lines
	-- it()
	-- it()
	-- local lastv = nil
	-- for line in it do
	-- 	if line == "END" then
	-- 		break
	-- 	end

	-- 	xstr, ystr = line:match("^ +(%d+%.%d+E%+%d+) +(%d+%.%d+E%+%d+)$")
	-- 	x, y = tonumber(xstr), tonumber(ystr)
	-- 	local newv = #poly.v+1
	-- 	tx, ty = transform(x, y)
	-- 	poly.v[newv] = {tx, ty}

	-- 	if lastv ~= nil then
	-- 		poly.e[#poly.e+1] = {lastv, newv}
	-- 	end

	-- 	lastv = newv
	-- end
	-- poly.e[#poly.e+1] = {lastv, 1}

	-- flippoly(poly)
	-- -- drawpol(poly)

	-- local newface = triangulate({poly})

	-- love.graphics.points(mx, my)
	-- drawpol(newface)

	-- for _, mem in ipairs(v.memids) do
	-- 	for k2 = 2, #ways[mem].refs do
	-- 		local last = ways[mem].refs[k2-1]
	-- 		local v2 = ways[mem].refs[k2]
	-- 		local lastx, lasty = transform(nodes[last][2]/10000000, nodes[last][1]/10000000)
	-- 		local v2x, v2y = transform(nodes[v2][2]/10000000, nodes[v2][1]/10000000)
	-- 		print(lastx, lasty, v2x, v2y)
	-- 		dline({lastx, lasty}, {v2x, v2y})
	-- 	end
	-- end
	drawpol(face)
	if nextline ~= nil then
		love.graphics.setColor(255, 0, 255)
		dline(nextline[1], nextline[2])
		love.graphics.setColor(255, 255, 255)
	end

end

function transform(lng, lat)
	local r = 1
	local lambda = math.rad(lng)
	local phi = math.rad(lat)
	local x = r * lambda
	local y = r * math.log(math.tan((math.pi/4) + phi * .5))
	x, y =  x*4096 - 500, y*4096 - 4516
	return x, y
	-- return x*100 - 800, y*100-5400
end

function flippoly(poly)
	local maxy = 0
	for k, v in ipairs(poly.v) do
		maxy = math.max(maxy, v[2])
	end

	for k, v in ipairs(poly.v) do
		v[2] = maxy - v[2]
	end
end

local step = 1
function love.keypressed(key, scancode, isrepeat)
	if scancode == "x" then
		zoom = zoom + 1
	elseif scancode == "z" then
		zoom = zoom - 1
	elseif scancode == "w" then
		offy = offy + 10*zoom
	elseif scancode == "a" then
		offx = offx + 10*zoom
	elseif scancode == "s" then
		offy = offy - 10*zoom
	elseif scancode == "d" then
		offx = offx - 10*zoom
	elseif scancode == "y" then
		max_cnt = max_cnt + 1
	elseif scancode == "h" then
		max_cnt = max_cnt - 1
	elseif scancode == "t" then
		trim(face)
	end
end

function magiclines(s)
	if s:sub(-1)~="\n" then s=s.."\n" end
	return s:gmatch("(.-)\n")
end

function winding(poly)
	local sum = 0
	for k,v in ipairs(poly.e) do
		local a = poly.v[v[1]]
		local b = poly.v[v[2]]
		sum = sum + (b[1] - a[1]) * (b[2] + a[2])
	end

	return sum
end

function check(face)
	if not SAFE then
		return true
	end

	if #face.inv_t ~= #face.v then
		print("Not enough inverse")
		return false
	end

	for vi, v in pairs(face.inv_t) do
		if face.t[v[1]][v[2]] ~= vi then
			table_print({vi, v, face.t[v[1]]})
			print("inv_t did not point to correct triangle")
			return false
		end
	end

	for _, e1 in pairs(face.e) do
		local v1 = face.v[e1[1]]
		local v2 = face.v[e1[2]]
		for _, e2 in pairs(face.e) do
			if e1 ~= e2 then
				local v3 = face.v[e2[1]]
				local v4 = face.v[e2[2]]

				local tu = (v1[1] - v3[1]) * (v3[2] - v4[2]) - (v1[2] - v3[2]) * (v3[1] - v4[1])
				local tl = (v1[1] - v2[1]) * (v3[2] - v4[2]) - (v1[2] - v2[2]) * (v3[1] - v4[1])

				local su = (v1[1] - v3[1]) * (v1[2] - v2[2]) - (v1[2] - v3[2]) * (v1[1] - v2[1])
				local sl = (v1[1] - v2[1]) * (v3[2] - v4[2]) - (v1[2] - v2[2]) * (v3[1] - v4[1])

				if tu >= tl or tu <= 0 then
				elseif su >= sl or su <= 0 then
				else
					print("Edges collides at", tu/tl, su/sl)
					return false
				end
			end
		end
	end

	local inv_adj = {}
	for i, v in ipairs(face.adj) do
		for i2, v2 in ipairs(v) do
			if inv_adj[v2] ~= nil then
				table_print({"Adjecency value used multiple timed", v2})
				return false
			end
			inv_adj[v2] = {i, i2}
		end
	end

	for i, v in ipairs(face.adj) do
		for i2, v2 in ipairs(v) do
			if i == v2[1] then
				print("Triangle is adjecent to itself", i)
				return false
			end

			local otri, overt = unpack_or_nil(opposing_tri(face, i, i2))
			if otri ~= nil then
				local stri, svert = unpack_or_nil(opposing_tri(face, otri, overt))
				if stri ~= i or svert ~= i2 then
					print("Opposing adjecency doesn't match", i, i2, stri, svert)
					return false
				end
			end
		end
	end

	for i, tri in ipairs(face.t) do
		reverse = {}
		for i, v in ipairs(tri) do
			if reverse[v] == true then
				print("Duplicated vertex in tri ", i, v)
				return false
			end
			reverse[v] = true
		end
		a = face.v[tri[1]]
		b = face.v[tri[2]]
		c = face.v[tri[3]]
		abx, aby = vec_minus(b[1], b[2], a[1], a[2])
		acx, acy = vec_minus(c[1], c[2], a[1], a[2])

		-- amx, amy = vec_minus(mx, my, a[1], a[2])
		if vec_cross(abx, aby, acx, acy) > 0 then
			table_print({"Bad winding on ", i, a, b, c})
			return false
		end
	end

	return true
end

-- Print anything - including nested tables
function table_print (tt, indent, done)
	done = done or {}
	indent = indent or 0
	if type(tt) == "table" then
		for key, value in pairs (tt) do
			io.write(string.rep (" ", indent)) -- indent it
			if type (value) == "table" and not done [value] then
				done[value] = true
				io.write(string.format("[%s] => %s\n", tostring(key), tostring(value)));
				io.write(string.rep (" ", indent+4)) -- indent it
				io.write("(\n");
				table_print (value, indent + 7, done)
				io.write(string.rep (" ", indent+4)) -- indent it
				io.write(")\n");
			else
				io.write(string.format("[%s] => %s\n",
				tostring (key), tostring(value)))
			end
		end
	else
		io.write(tt .. "\n")
	end
end

mx, my = 0, 0

function love.update(dt)
	mx, my = love.mouse.getPosition()
	mx, my = love.graphics.inverseTransformPoint(mx, my)
end
