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
	love.graphics.line(offset + p1[1], offset + p1[2], offset +  p2[1], offset + p2[2])
end

function drawEdges(verts, edges)
	for i, edge in pairs(edges) do
		start = verts[edge[1]]
		dest = verts[edge[2]]
		dline(start, dest)
	end
end

function drawTris(verts, tris)
	for i, tri in pairs(tris) do
		v1 = verts[tri[1]]
		v2 = verts[tri[2]]
		v3 = verts[tri[3]]
		dline(v1, v2)
		dline(v2, v3)
		dline(v3, v1)
	end
end

function drawpol(pol)
	local verts = pol["v"]
	if pol["e"] ~= nil then
		drawEdges(verts, pol["e"])
	elseif pol["t"] ~= nil then
		drawTris(verts, pol["t"])
	end

	for i, vert in pairs(verts) do
		love.graphics.points(offset + vert[1], offset + vert[2])
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
			{center[1] + stride, center[2] - inrad},
			{center[1], center[2] + outrad},
		},
		t = {
			{1, 2, 3},
		}
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
	table_print(face)
	return nil
end

function opposing_tri(face, tri, vert)
	local others = {}

	for _, v in pairs(sutri.t[tri]) do
		if v ~= p then
			others[v] = true
		end
	end

	for i, stri in pairs(face.t) do
		local unmatched = nil
		for _, v in ipairs(stri) do
			if others[v] ~= true then
				if unmatched ~= nil then
					print("DOUBLE UNMATCH", unmatched)
					unmatched = nil
					break
				end
				unmatched = v
			end
			if unmatched ~= nil and unmatched ~= vert then
				return i
			end
		end
	end

	return nil
end

function incircle(a, b, c, d)
	local ab = (a[1]*b[2]) - (b[1]*a[2])
	local bc = (b[1]*c[2]) - (c[1]*b[2])
	local cd = (c[1]*d[2]) - (d[1]*c[2])
	local da = (d[1]*a[2]) - (a[1]*d[2])
	local ac = (a[1]*c[2]) - (c[1]*a[2])
	local bd = (b[1]*d[2]) - (d[1]*b[2])

	local abc = ab + bc - ac;
	local bcd = bc + cd - bd;
	local cda = cd + da + ac;
	local dab = da + ab + bd;

	local adet = bcd * a[1] *  a[1] + bcd * a[2] *  a[2];
	local bdet = cda * b[1] * -b[1] + cda * b[2] * -b[2];
	local cdet = dab * c[1] *  c[1] + dab * c[2] *  c[2];
	local ddet = abc * d[1] * -d[1] + abc * d[2] * -d[2];

	local deter = (adet + bdet) + (cdet + ddet);
	return deter
end

function add_point(sutri, p)
	tri1 = find_containing_tri(sutri, p)
	local tri = sutri.t[tri1]
	v0 = tri[1]
	v1 = tri[2]
	v2 = tri[3]
	v3 = #sutri.v+1
	sutri.v[v3] = p
	-- Original tri becomes v0 v1 v3
	tri[3] = v3
	tri2 = {v1, v2, v3}
	tri3 = {v2, v0, v3}
	-- Insert the new tris
	tri2i = #sutri.t+1
	sutri.t[tri2i] = tri2
	tri3i = #sutri.t+1
	sutri.t[tri3i] = tri3

	stack = {tri1, tri2i, tri3i}

	while #stack ~= 0 do
		local tri = table.remove(stack)
		local t_opi = opposing_tri(sutri, tri, v3)
		if t_opi ~= nil then
			print("check in circle")
			local t_op = sutri.t[t_opi]
			-- @COMPLETE check if the edge is fixed
			if incircle(sutri.v[t_op[1]], sutri.v[t_op[2]], sutri.v[t_op[3]], p) then
				print("FLIP THAT EDGE")
				local t_flip = nil
				local op_flip = nil
				if sutri.t[tri][1] ~= v3 then
					t_flip = 1
				elseif sutri[tri][2] ~= v3 then
					t_flip = 2
				end

				if t_op[1] ~= v3 and sutri.t[tri][1] ~= t_op[op_flip] then
					t_flip = 1
				elseif t_op[2] ~= v3 and sutri.t[tri][2] ~= t_op[op_flip] then
					t_flip = 2
				elseif t_op[3] ~= v3 and sutri.t[tri][3] ~= t_op[op_flip] then
					t_flip = 3
				end

				-- Flip edge
				table_print(sutri)
				print("flip", v3, op_flip, t_flip)
				local tmp = t_op[op_flip]
				t_op[op_flip] = sutri.t[tri][t_flip]
				sutri.t[tri][t_flip] = tmp
			end
		end
	end
end

function love.draw()
	drawpol(outer)
	drawpol(inner)

	box = bbox(outer)
	-- drawpol(box)
	sutri = superTri(box)

	p = {100, 100}
	add_point(sutri, p)
	love.graphics.points(offset + p[1], offset + p[2])
	p = {200, 200}
	add_point(sutri, p)
	love.graphics.points(offset + p[1], offset + p[2])
	p = {200, 100}
	add_point(sutri, p)
	love.graphics.points(offset + p[1], offset + p[2])

	drawpol(sutri)
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

function love.update(dt)
end
