-- Based on the paper https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.61.3862&rep=rep1&type=pdf
-- and https://github.com/artem-ogre/CDT

offset = 100

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
	love.graphics.line(p1[1], p1[2], p2[1], p2[2])
end

function drawEdges(verts, edges)
	for i, edge in pairs(edges) do
		start = verts[edge[1]]
		dest = verts[edge[2]]
		dline(start, dest)
	end
end

function drawTris(verts, tris, labels)
	for i, tri in pairs(tris) do
		v1 = verts[tri[1]]
		v2 = verts[tri[2]]
		v3 = verts[tri[3]]
		dline(v1, v2)
		dline(v2, v3)
		dline(v3, v1)

		love.graphics.print(labels[i], (v1[1]+v2[1]+v3[1])/3, (v1[2]+v2[2]+v3[2])/3)

		if incircle(v1, v2, v3, {mx, my}) then
			cx, cy = circumcenter(v1, v2, v3)
			cr = circumr(v1, v2, v3)
			-- love.graphics.points(offset + cx, offset + cy)
			love.graphics.circle("line", cx, cy, cr, 100)
		end
	end
end

visited = {}

function drawpol(pol)
	love.graphics.setLineWidth(1)
	local verts = pol["v"]

	if pol.t ~= nil then

		local tris = pol.t
		labels = {}
		for i, _ in ipairs(tris) do
			labels[i] = tostring(i)
		end

		-- v_tris = {}
		-- v_labels = {}
		-- local offset = 0
		-- for i, v in pairs(visited) do
		-- 	table.insert(v_tris, table.remove(tris, i-offset))
		-- 	local label = table.remove(labels, i-offset)
		-- 	if v then
		-- 		label = label .. "O"
		-- 	end
		-- 	table.insert(v_labels, label)
		-- 	offset = offset + 1
		-- end

		drawTris(verts, tris, labels)

		-- love.graphics.setColor(0, 0, 255)
		-- drawTris(verts, v_tris, v_labels)
		-- love.graphics.setColor(255, 255, 255)
	end

	if pol.e ~= nil then
		if pol.t ~= nil then
			love.graphics.setColor(0, 255, 0)
			love.graphics.setLineWidth(3)
		end

		drawEdges(verts, pol.e)

		love.graphics.setLineWidth(1)
		love.graphics.setColor(255, 255, 255)
	end

	for i, vert in pairs(verts) do
		if i == 4 then
			love.graphics.setColor(255, 0, 0)
		end
		love.graphics.points(vert[1], vert[2])
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
	}
end

function det(p1, p2)
	return (p1[1] * p2[2]) - (p1[2] * p2[1])
end

function love.load()
	love.graphics.setPointSize(10)
end
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

function find_containing_tri(face, p)
	for i, tri in pairs(sutri.t) do
		if point_inside_tri(p, sutri, tri) then
			return i
		end
	end
	return nil
end

function opposing_tri(face, tri, vert)
	local others = {}

	for _, v in pairs(sutri.t[tri]) do
		if v ~= vert then
			others[v] = true
		end
	end

	for i, stri in ipairs(face.t) do
		local unmatched = nil
		for j, v in ipairs(stri) do
			if others[v] ~= true then
				if unmatched ~= nil then
					unmatched = nil
					break
				end
				unmatched = j
			end
		end
		if unmatched ~= nil and stri[unmatched] ~= vert then
			return i, unmatched
		end
	end

	return nil
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
function vec_len(x, y)
	return math.sqrt(math.pow(x, 2) + math.pow(y, 2))
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

function is_fixed(face, a, b)
	for i, v in ipairs(face.e) do
		if v[1] == a and v[2] == b or v[1] == b and v[2] == a then
			return true
		end
	end
	return false
end

function add_point(sutri, p)
	tri1 = find_containing_tri(sutri, p)
	-- tri1 is reused
	tri2, tri3 = split_tri(sutri, tri1, p)
	-- @HACK find the new vertex id
	local v3 = sutri.t[tri1][3]

	stack = {tri1, tri2, tri3}

	while #stack ~= 0 do
		local tri = table.remove(stack)
		local t_opi, oppo_vert = opposing_tri(sutri, tri, v3)
		if t_opi ~= nil then
			local t_op = sutri.t[t_opi]
			if not is_fixed(sutri, sutri.t[tri1][1], sutri.t[tri1][2]) and incircle(sutri.v[t_op[1]], sutri.v[t_op[2]], sutri.v[t_op[3]], p) then
				local t_op_swap = anticlockwise_vert(oppo_vert)
				local t_me_swap
				for i, v in ipairs(sutri.t[tri]) do
					if v == v3 then
						t_me_swap = anticlockwise_vert(i)
					end
				end
				
				check(sutri)

				-- Flip edge
				t_op[t_op_swap] = v3
				sutri.t[tri][t_me_swap] = t_op[oppo_vert]

				table.insert(stack, tri)
				table.insert(stack, t_opi)
			end
		end
	end
	return v3
end

function add_edge(face, v1i, v2i)
	local tri_cursor = nil
	local tri_vert = nil
	for i, tri in ipairs(face.t) do
		for j, vert in ipairs(tri) do
			if vert == v1i then
				tri_cursor = i
				tri_vert = j
				goto found
			end
		end
	end
	fail()
	::found::

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
			local new_tri, oppo_vert = opposing_tri(face, tri_cursor, tri[clockwise_vert(tri_vert)])
			if new_tri == nil then
				deadlocwk()
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
	if face.t[tri_cursor][clockwise_vert(tri_vert)] ~= v2i then
		upper = {face.t[tri_cursor][clockwise_vert(tri_vert)]}
	else
		upper = {}
	end
	local lower
	if face.t[tri_cursor][anticlockwise_vert(tri_vert)] ~= v2i then
		lower = {face.t[tri_cursor][anticlockwise_vert(tri_vert)]}
	else
		lower = {}
	end

	vi = v1i

	dead_tris = {}

	while true do
		for _, v in ipairs(face.t[tri_cursor]) do
			if v == v2i then
				goto done
			end
		end

		local v = face.v[vi]
		local tseg, vseg = opposing_tri(face, tri_cursor, vi)
		local vo = face.v[face.t[tseg][vseg]]

		v1vox, v1voy = vec_minus(vo[1], vo[2], v1[1], v1[2])
		if face.t[tseg][vseg] == v2i then
		elseif vec_cross(v1vox, v1voy, av2x, av2y) > 0 then
			upper[#upper+1] = face.t[tseg][vseg]
			vi = face.t[tseg][anticlockwise_vert(vseg)]
		else
			lower[#lower+1] = face.t[tseg][vseg]
			vi = face.t[tseg][clockwise_vert(vseg)]
		end

		dead_tris[#dead_tris+1] = tri_cursor
		tri_cursor = tseg
	end
	::done::
	dead_tris[#dead_tris+1] = tri_cursor

	local offset = 0
	table.sort(dead_tris)
	for _, v in ipairs(dead_tris) do
		table.remove(face.t, v - offset)
		offset = offset + 1
	end
	
	rebuild_tris(face, upper, v1i, v2i, false)
	rebuild_tris(face, lower, v1i, v2i, true)

	face.e[#face.e+1] = {v1i, v2i}

	check(face)

	-- return tri_cursor
	return 9
end

function rebuild_tris(face, verts, v1, v2, swap)
	local c = verts[1]
	if #verts > 1 then

		local ci = 1
		for i, v in ipairs(verts) do
			if incircle(face.v[v1], face.v[v2], face.v[c], face.v[v]) then
				ci = i
				c = v
			end
		end

		pe = {}
		pd = {}
		for i = 1, ci-1 do
			pe[#pe+1] = verts[i]
		end
		for i = ci+1, #verts do
			pd[#pd+1] = verts[i]
		end

		rebuild_tris(face, pe, v1, c, swap)
		rebuild_tris(face, pd, c, v2, swap)
	end

	if #verts > 0 then
		local tri
		if swap then
			tri = {v2, v1, c}
		else
			tri = {v1, v2, c}
		end
		face.t[#face.t+1] = tri
	end
end

function trim(face, vout)
	local inside = false

	local tri_cursor
	local tri_vert
	for i, tri in ipairs(face.t) do
		for j, v in ipairs(tri) do
			if v == vout then
				tri_vert = j
				tri_cursor = i
				goto found
			end
		end
	end
	::found::

	local verts = {}
	local newface = {
		t = {},
		v = {},
	}
	local visited = {}

	while true do
		visited[tri_cursor] = inside

		if inside then
			for i, v in ipairs(face.t[tri_cursor]) do
				if verts[v] == nil then
					newi = #newface.v+1
					newface.v[newi] = face.v[v]
					verts[v] = newi
				end
			end

			newface.t[#newface.t+1] = {verts[face.t[tri_cursor][1]], verts[face.t[tri_cursor][2]], verts[face.t[tri_cursor][3]]}
		end

		local start_vert = tri_vert
		local tseg, vseg
		while true do
			tseg, vseg = opposing_tri(face, tri_cursor, face.t[tri_cursor][tri_vert])
			if tseg == nil or visited[tseg] ~= nil then
			else
				break
			end

			tri_vert = anticlockwise_vert(tri_vert)
			if tri_vert == start_vert then
				goto done
			end
		end

		local s1 = face.t[tseg][clockwise_vert(vseg)]
		local s2 = face.t[tseg][anticlockwise_vert(vseg)]
		if is_fixed(face, s1, s2) then
			inside = not inside
		end

		tri_cursor = tseg
		tri_vert = anticlockwise_vert(vseg)
	end
	::done::

	return newface
end

function love.draw()
	love.graphics.translate(offset, offset)
	-- drawpol(outer)
	-- drawpol(inner)
	-- print(circumcenter({0,2}, {0,0}, {2,0}))
	-- love.exit(1)

	 box = bbox(outer)
	 -- drawpol(box)
	 sutri = superTri(box)

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

	 local points = {}
	 for i, v in ipairs(outer.v) do
		 points[i] = add_point(sutri, v)
	 end

	 add_edge(sutri, 4, 5)
	 for i, e in ipairs(outer.e) do
		 add_edge(sutri, points[e[1]], points[e[2]])
	 end

	 local points = {}
	 for i, v in ipairs(inner.v) do
		 points[i] = add_point(sutri, v)
	 end

	 for i, e in ipairs(inner.e) do
		 add_edge(sutri, points[e[1]], points[e[2]])
	 end
	
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
	
	check(sutri)

	local newface = trim(sutri, 1)
	table_print(newface)

	love.graphics.points(mx, my)
	drawpol(newface)
end

function check(face)
	for i, tri in ipairs(face.t) do
		reverse = {}
		for i, v in ipairs(tri) do
			if reverse[v] == true then
				print("Duplicated vertex in tri")
				table_print(face)
				kill()
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
			print("Bad winding on ", i)
			kill()
		end
	end
end

-- Print anything - including nested tables
function table_print (tt, indent, done)
  done = done or {}
  indent = indent or 0
  if type(tt) == "table" then
    for key, value in pairs (tt) do
      io.write(string.rep (" ", indent)) -- indent it
      if type (value) == "table" and not done [value] then
        done [value] = true
        io.write(string.format("[%s] => table\n", tostring (key)));
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
	mx, my = mx - offset, my - offset
end
