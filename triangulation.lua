local lib = {}

local function bbox(poly)
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

function lib.superTri(bbox)
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

local function is_fixed(face, a, b)
	return face.e[string.format("%d.%d", a, b)] ~= nil or face.e[string.format("%d.%d", b, a)] ~= nil
end

local function set_fixed(face, a, b)
	face.e[string.format("%d.%d", a, b)] = {a, b}
end

local function resolve_with_swaps(sutri, tri1, v3, stack)
	while #stack ~= 0 do
		local tri, t_me = unpack(table.remove(stack))
		local t_opt = opposing_tri(sutri, tri, t_me)
		if t_opt[1] ~= nil then
			local t_opi, oppo_vert = unpack(t_opt)
			local t_op = sutri.t[t_opi]
			local oppo_clock = clockwise_vert(oppo_vert)
			local me_clock = clockwise_vert(t_me)
			local t_op_swap = anticlockwise_vert(oppo_vert)
			if not is_fixed(sutri, sutri.t[t_opi][oppo_clock], sutri.t[t_opi][t_op_swap])
				and incircle(sutri.v[t_op[1]], sutri.v[t_op[2]], sutri.v[t_op[3]], sutri.v[v3]) then
				local t_me_swap = anticlockwise_vert(t_me)

				-- Reassign the adjecency information
				local t3 = opposing_tri(sutri, tri, me_clock)
				local t2 = opposing_tri(sutri, t_opi, oppo_clock)

				sutri.adj[tri][t_me][1] = t2[1]
				sutri.adj[tri][t_me][2] = t2[2]
				if t2[1] ~= nil then
					sutri.adj[t2[1]][t2[2]][1] = tri
					sutri.adj[t2[1]][t2[2]][2] = t_me
				end
				sutri.adj[t_opi][oppo_vert][1] = t3[1]
				sutri.adj[t_opi][oppo_vert][2] = t3[2]
				if t3[1] ~= nil then
					sutri.adj[t3[1]][t3[2]][1] = t_opi
					sutri.adj[t3[1]][t3[2]][2] = oppo_vert
				end
				sutri.adj[tri][me_clock][1] = t_opi
				sutri.adj[tri][me_clock][2] = oppo_clock
				sutri.adj[t_opi][oppo_clock][1] = tri
				sutri.adj[t_opi][oppo_clock][2] = me_clock

				sutri.inv_t[sutri.t[tri][t_me_swap]][1] = t_opi
				sutri.inv_t[sutri.t[tri][t_me_swap]][2] = oppo_clock
				sutri.inv_t[sutri.t[t_opi][t_op_swap]][1] = tri
				sutri.inv_t[sutri.t[t_opi][t_op_swap]][2] = me_clock

				-- Flip edge
				t_op[t_op_swap] = sutri.t[tri][t_me]
				sutri.t[tri][t_me_swap] = t_op[oppo_vert]

				table.insert(stack, {tri, t_me})
				table.insert(stack, {t_opi, t_op_swap})
			end
		end
	end

	return true
end

local function rebuild_tris(face, dead_tris, verts, verts_adj, v1, v2, swap, start, end_, link)
	if end_-start+1 == 0 then
		return
	end

	local ci = start
	local c = verts[start]

	local v1_t
	local v2_t

	local newt = table.remove(dead_tris)

	local v2_link = {newt, 2}
	local v1_link = {newt, 1}
	if swap then
		v2_link[2] = 1
		v1_link[2] = 2
	end

	if end_-start+1 > 1 then
		for i = start,end_ do
			v = verts[i]
			if incircle(face.v[v1], face.v[v2], face.v[c], face.v[v]) then
				ci = i
				c = v
			end
		end

		v2_t = {rebuild_tris(face, dead_tris, verts, verts_adj, v1, c, swap, start, ci-1, v2_link), 3}
		v1_t = {rebuild_tris(face, dead_tris, verts, verts_adj, c, v2, swap,  ci+1, end_, v1_link), 3}
	end

	if ci == end_ then
		v1_t = verts_adj[ci+1][1]
		verts_adj[ci+1][2] = v1_link
	end
	if ci == start then
		v2_t = verts_adj[ci][1]
		verts_adj[ci][2] = v2_link
	end

	local tri
	local adj
	if swap then
		tri = {v2, v1, c}
		adj = {v2_t, v1_t, link}
	else
		tri = {v1, v2, c}
		adj = {v1_t, v2_t, link}
	end
	face.t[newt] = tri
	face.adj[newt] = adj
	face.inv_t[c] = {newt, 3}

	return newt
end

local lasttri = nil
function lib.add_point(sutri, p)
	tri1 = find_containing_tri(sutri, p, lasttri)
	if tri1 == nil then
		error("The point is outside the mesh")
	end
	lasttri = tri1

	-- tri1 is reused
	tri2, tri3 = split_tri(sutri, tri1, p)
	-- @HACK find the new vertex id
	local v3 = sutri.t[tri1][3]

	local stack = {{tri1, 3}, {tri2, 3}, {tri3, 3}}
	resolve_with_swaps(sutri, tri1, v3, stack)

	return v3
end

function lib.add_edge(face, v1i, v2i)
	assert(v1i ~= v2i)
	if is_fixed(face, v1i, v2i) then
		return
	end

	local tri_cursor, tri_vert = find_tri_with_vert(face, v1i)
	if tri_cursor == nil then
		error("Vertex is not part of any triangle")
	end

	local v1 = face.v[v1i]
	local v2 = face.v[v2i]

	local av2x, av2y = vec_minus(v2[1], v2[2], v1[1], v1[2])

	local start_tri = tri_cursor

	while true do
		local tri = face.t[tri_cursor]
		b = face.v[tri[clockwise_vert(tri_vert)]]
		c = face.v[tri[anticlockwise_vert(tri_vert)]]

		abx, aby = vec_minus(b[1], b[2], v1[1], v1[2])
		acx, acy = vec_minus(c[1], c[2], v1[1], v1[2])

		inside = (vec_cross(abx, aby, acx, acy) * vec_cross(abx, aby, av2x, av2y) >= 0 and
			vec_cross(acx, acy, abx, aby) * vec_cross(acx, acy, av2x, av2y) >= 0)

		if not inside then
			local new_tri, oppo_vert = unpack_or_nil(opposing_tri(face, tri_cursor, clockwise_vert(tri_vert)))
			if new_tri == nil then
				deadlock()
			end
			if new_tri == start_tri then
				deadlock()
			end
			tri_cursor = new_tri
			tri_vert = clockwise_vert(oppo_vert)
		else
			break
		end
	end

	local upper
	local upper_adj = {}
	if face.t[tri_cursor][clockwise_vert(tri_vert)] ~= v2i then
		upper = {face.t[tri_cursor][clockwise_vert(tri_vert)]}
		upper_adj[#upper_adj+1] = {opposing_tri(face, tri_cursor, anticlockwise_vert(tri_vert))}
	else
		set_fixed(face, v1i, v2i)
		return 9
	end
	local lower
	local lower_adj = {}
	if face.t[tri_cursor][anticlockwise_vert(tri_vert)] ~= v2i then
		lower = {face.t[tri_cursor][anticlockwise_vert(tri_vert)]}
		lower_adj[#lower_adj+1] = {opposing_tri(face, tri_cursor, clockwise_vert(tri_vert))}
	else
		set_fixed(face, v1i, v2i)
		return 9
	end

	local vi = tri_vert

	dead_tris = {}

	while true do
		for i, v in ipairs(face.t[tri_cursor]) do
			if v == v2i then
				upper_adj[#upper_adj+1] = {opposing_tri(face, tri_cursor, clockwise_vert(i))}
				lower_adj[#lower_adj+1] = {opposing_tri(face, tri_cursor, anticlockwise_vert(i))}
				goto done
			end
		end

		-- local v = face.v[vi]
		local tseg, vseg = unpack_or_nil(opposing_tri(face, tri_cursor, vi))
		local vo = face.v[face.t[tseg][vseg]]

		v1vox, v1voy = vec_minus(vo[1], vo[2], v1[1], v1[2])
		if face.t[tseg][vseg] == v2i then
		elseif vec_cross(v1vox, v1voy, av2x, av2y) > 0 then
			upper[#upper+1] = face.t[tseg][vseg]
			upper_adj[#upper_adj+1] = {opposing_tri(face, tseg, clockwise_vert(vseg))}
			vi = anticlockwise_vert(vseg)
		else
			lower[#lower+1] = face.t[tseg][vseg]
			lower_adj[#lower_adj+1] = {opposing_tri(face, tseg, anticlockwise_vert(vseg))}
			vi = clockwise_vert(vseg)
		end

		dead_tris[#dead_tris+1] = tri_cursor
		tri_cursor = tseg
	end
	::done::
	dead_tris[#dead_tris+1] = tri_cursor

	upper_end = #upper
	table.insert(upper, "-- SEP --")
	for i,v in ipairs(lower) do
		table.insert(upper, v)
	end
	for i,v in ipairs(lower_adj) do
		table.insert(upper_adj, v)
	end

	uv = rebuild_tris(face, dead_tris, upper, upper_adj, v1i, v2i, false, 1, upper_end, nil)
	lv = rebuild_tris(face, dead_tris, upper, upper_adj, v1i, v2i, true, upper_end+2, #upper, nil)
	-- Set the adjecency of the root triangles
	-- table_print(uv)
	if lv ~= nil then
		face.adj[uv][3] = {lv, 3}
	end
	if uv ~= nil then
		face.adj[lv][3] = {uv, 3}
	end

	face.inv_t[v1i] = {uv, 1}
	face.inv_t[v2i] = {uv, 2}

	for i=3,#upper do
		if type(upper[i]) ~= "string" and type(upper[i-2]) ~= "string" then
			-- print(upper[i], upper[i-2])
			if upper[i] == upper[i-2] then
				-- print("They are the same")
				local s1 = upper_adj[i-1]
				local s2 = upper_adj[i]
				s1.adj = true
				s2.adj = true

				-- Adjust the adjecencies
				face.adj[s1[2][1]][s1[2][2]] = s2[2]
				face.adj[s2[2][1]][s2[2][2]] = s1[2]
			end
		end
	end

	for _,v in ipairs(upper_adj) do
		if not v.adj then
			face.adj[v[1][1]][v[1][2]] = v[2]
		end
	end

	::complete::
	set_fixed(face, v1i, v2i)

	-- return tri_cursor
	return 9
end

return lib
