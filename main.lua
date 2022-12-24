-- Based on the paper https://citeseerx.ist.psu.edu/viewdoc/download?doi=10.1.1.61.3862&rep=rep1&type=pdf
-- and https://github.com/artem-ogre/CDT

package.path = package.path..";/usr/lib/node_modules/local-lua-debugger-vscode/debugger/?.lua"
if os.getenv("LOCAL_LUA_DEBUGGER_VSCODE") == "1" then
	require("lldebugger").start()
end

local triang = require("triangulation")

local json = require("json")
local rings = require("rings")
local testlib = require("testlib")

function rpairs(tbl)
	local n = #tbl+1
	return function()
		n = n - 1
		if n >= 1 then return n, tbl[n] end
	end
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
	return math.acros(vec_dot(x1, y1, x2, y2))
end

local poly = {}
local grid = {}
local intersects = {}
local grid_polys = {}
local covered = {}

function load_poly_from_disk()
	local contents, size = love.filesystem.read("test/cdtfile/inputs/kidney.txt")
	local nextLine = contents:gmatch("([^\n]*)\n?")
	local nvert, nedge = nextLine():match("(%d*) (%d*)")

	-- read verts
	local verts = {}
	for i = 1, nvert do
		local x, y = nextLine():match("(-?[%d%.]+) +(-?[%d%.]+)")
		table.insert(verts, {tonumber(x), tonumber(y)})
	end
	return verts
end

function load_poly_from_other_format()
	file, err = love.filesystem.newFile("poly.nl", "r")

	local state = "nodes"
	local  poly = {
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
			table.insert(poly, vert)
		elseif state == "edges" then
			-- We assume the edges just connect adjecent points in a single closed loop
			break
		end
	end
	file:close()

	return poly
end

function love.load(args)
	love.graphics.setPointSize(2)

poly = {
	{307, 409},
	{296, 195},
	{307, 180},
	{246, 76},
	{66, 54},
	{120, 205},
	{290, 215},
	{290, 230},
	{130, 270},
	{282, 409},
	{294, 385},
}
	-- poly = load_poly_from_disk()
	poly = load_poly_from_other_format()
	local bbox = {
		min = {x = poly[1][1], y = poly[1][2]},
		max = {x = poly[1][1], y = poly[1][2]},
	}
	for k,v in ipairs(poly) do
		bbox.min.x = math.min(bbox.min.x, v[1])
		bbox.min.y = math.min(bbox.min.y, v[2])

		bbox.max.x = math.max(bbox.max.x, v[1])
		bbox.max.y = math.max(bbox.max.y, v[2])
	end

	local intended = {
		w = 600,
		h = 400,
	}
	local adjust = {
		offset = {x=bbox.min.x, y=bbox.min.y},
		scale = {
			w = (bbox.max.x - bbox.min.x)/intended.w,
			h = (bbox.max.y - bbox.min.y)/intended.h,
		},
	}
	for k,v in ipairs(poly) do
		v[1] = (v[1] - adjust.offset.x) / adjust.scale.w + 10
		v[2] = intended.h - ((v[2] - adjust.offset.y) / adjust.scale.h) + 10
	end

	if false then
		local newpoly = {}
		local poly_len = #poly
		for i = 0,poly_len-1 do
			newpoly[poly_len-i] = poly[i+1]
		end
		poly = newpoly
	end

	grid = {
		size = 40,
	}
end

function math.clamp(a, min, max)
	return math.max(math.min(a, max), min)
end

local dstep = 0
function love.keypressed(key, scancode, isrepeat)
	if scancode == "e" then
		dstep = dstep + 1
	elseif scancode == "q" then
		dstep = dstep - 1
	end
end

local function isign(x, y)
	local t = bit.arshift(bit.bxor(x, y), 31)
	return bit.bxor(x, t) - t
end

local function sign(x)
	if x == 0 then
		return 0
	elseif x < 0 then
		return -1
	else
		return 1
	end
end

local function point_to_circumlength(sidelen, x, y)
	local len = 0
	if y > x then
		-- Handle the first half of the square
		assert((y < sidelen and x == 0) or (y == sidelen and x < sidelen))
		len = y + x
	else
		-- Handle the other half
		assert((y <= sidelen and x == sidelen) or (y == 0 and x <= sidelen))
		len = sidelen * 2 + (sidelen - y) + (sidelen - x)
	end
	return len
end

local function circumlength_to_point(sidelen, len)
	local x, y = 0, 0
	y = math.min(len, sidelen)
	if y >= len then
		return x, y
	end
	len = len - sidelen

	x = math.min(len, sidelen)
	if x >= len then
		return x, y
	end
	len = len - sidelen

	y = y - math.min(len, sidelen)
	if sidelen >= len then
		return x, y
	end
	len = len - sidelen

	x = x - math.min(len, sidelen)
	return x, y
end

local function circumlength_segment(sidelen, len)
	return math.floor(len / sidelen)
end

local function circumlength_cwdistance(sidelen, x1, x2)
	local span = x1 - x2
	if span < 0 then
		span = span + sidelen * 4
	end

	return span
end

local function circumlength_cwbetween(sidelen, start, end_, p)
	local span = circumlength_cwdistance(sidelen, start, end_)
	return span > circumlength_cwdistance(sidelen, start, p)
end

local function polygon_intersections()
	local intersects = {}

	local function mk_intersection(comes_after, x, y, gridx, gridy)
		table.insert(intersects, {x, y, gridx, gridy, comes_after, x=x, y=y, gridx=gridx, gridy=gridy, comes_after=comes_after})
	end

	for i = 1,#poly do
		local p = poly[i]
		local gridx = math.floor(p[1] / grid.size) + 1 -- +1 because lua indexing
		local gridy = math.floor(p[2] / grid.size) + 1

		-- @SPEED: You could proabably do a fastpath here for when this
		-- point falls within the same grid square as the last one since
		-- that would be pretty common in real data

		local nexti = (i%#poly)+1
		local pend = poly[nexti]
		do
			-- Insert all the intersections in the straight line path
			-- between this point and the next one. This algorithm is
			-- careful to insert the points in line order, meaning
			-- intersections closer to the point p will be inserted be
			-- inserted before those further away
			-- The whole algorithm works in absolute coords
			-- and multiplies the sign back on as the last stage
			local start_x = gridx-1
			local start_y = gridy-1
			local end_x = math.floor(pend[1] / grid.size)
			local end_y = math.floor(pend[2] / grid.size)
			local x_span = pend[1] - p[1]
			local y_span = pend[2] - p[2]
			local slope_x = (y_span) / (x_span) -- Slope x is actually the slope of the y in the x
			local slope_y = (x_span) / (y_span)

			-- Figure out the direction of the line while also getting the
			-- gridwise length of it
			local span_x = end_x-start_x
			local span_y = end_y-start_y
			local dir_x = sign(span_x)
			local dir_y = sign(span_y)
			span_x = math.abs(span_x)
			span_y = math.abs(span_y)
			-- Calculate the offset of the point from the first x/y grid
			-- line. If the line is in the positive direction this means
			-- the delta to the next grid start, if negative it's the delta
			-- to the my own grid start
			local startoff_x = math.abs((start_x+math.max(dir_x, 0))*grid.size - p[1])
			local startoff_y = math.abs((start_y+math.max(dir_y, 0))*grid.size - p[2])

			local d_x = startoff_x
			local d_y = startoff_y
			local cursor_x = 1
			local cursor_y = 1

			-- Precompute the first y axis intersection x value for comparison later
			local cursor_y_isect = 0
			if span_y > 0 then
				cursor_y_isect = slope_y * d_y
			end
			while cursor_x <= span_x or cursor_y <= span_y do
				if (math.abs(d_x) < math.abs(cursor_y_isect) and cursor_x <= span_x) or cursor_y > span_y then
					local y_intersect = slope_x * d_x * dir_x
					mk_intersection(i, p[1] + d_x*dir_x, p[2] + y_intersect, gridx + cursor_x*dir_x, gridy + (cursor_y-1)*dir_y)
					d_x = (cursor_x*grid.size + startoff_x)
					cursor_x = cursor_x + 1
				else
					mk_intersection(i, p[1] + cursor_y_isect*dir_y, p[2] + d_y*dir_y, gridx + (cursor_x-1)*dir_x, gridy + cursor_y*dir_y)
					d_y = (cursor_y*grid.size + startoff_y)
					cursor_y_isect = slope_y * d_y
					cursor_y = cursor_y + 1
				end
			end
		end
	end

	return intersects
end

local function anno_points_consumed(intersects)
	-- Calculate how many fall within the grid square the intersection enters
	for i = 1, #intersects-1 do
		local me = intersects[i]
		local nxt = intersects[i+1]

		local consumes = nxt.comes_after - me.comes_after

		me.consumes = consumes
	end

	do
		local last = intersects[#intersects]
		local first = intersects[1]

		local consumes = #poly - last.comes_after + first.comes_after
		last.consumes = consumes
	end
end

local function anno_enter_exit(intersects)
	-- Calculate the enter and exit point for each segment in
	-- circumlength coords
	for i = 1, #intersects do
		local me = intersects[i]
		local nxt = intersects[(i%#intersects)+1]

		local grid_base_x = (me.gridx-1) * grid.size
		local grid_base_y = (me.gridy-1) * grid.size

		local enter = point_to_circumlength(grid.size, me.x-grid_base_x, me.y-grid_base_y)
		local exit = point_to_circumlength(grid.size, nxt.x-grid_base_x, nxt.y-grid_base_y)

		me.enter = enter
		me.exit = exit
	end
end

local function index_intersections_tile_enter(intersects)
	local gindex = {}
	local index = {}

	-- Create an index that groups the intersections by the grid cell they
	-- enter ordered by the circumlength of the entrypoint. This index also
	-- happens to sort the cells in the reading direction, but that doesn't
	-- really matter for the algo's
	for i = 1, #intersects do
		index[i] = i
	end

	table.sort(index, function(x, y)
		if intersects[x].gridy ~= intersects[y].gridy then
			return intersects[x].gridy < intersects[y].gridy
		end

		if intersects[x].gridx ~= intersects[y].gridx then
			return intersects[x].gridx < intersects[y].gridx
		end

		return intersects[x].enter < intersects[y].enter
	end)


	local cx, cy = nil, nil
	for k,v in ipairs(index) do
		local v = intersects[v]

		if v.gridx ~= cx or v.gridy ~= cy then
			table.insert(gindex, {pos=k, len=0})
			cx = v.gridx
			cy = v.gridy
		end

		local ip = gindex[#gindex]
		ip.len = ip.len + 1
	end

	return gindex, index
end

local function create_polygon_for_grid_tiles(gindex, index, intersects)
	-- Make a grid cell
	for k,g in ipairs(gindex) do
		local gpolys = {}

		-- Make an array to keep track of which segments are left
		local active = {}
		for i = 1, g.len do
			active[i] = true
		end

		local intersect = intersects[index[g.pos]]

		while true do
			local new_poly = {}
			-- Pick a random segment that's still active to close
			local picked
			for i = 1, g.len do
				if active[i] then
					picked = i
					break
				end
			end
			if picked == nil then
				break
			end


			local cursor = picked
			-- Scan from the endpoint of the picked segment to find the
			-- closest startpoint in the counterclockwise (forward)
			-- direction.
			while true do
				-- We have not picked this segment and it can no longer
				-- be considered
				active[cursor] = false

				-- Insert all the points from this segment along with
				-- the start and end
				local intersect = intersects[index[cursor+g.pos-1]]
				do
					local x, y = circumlength_to_point(grid.size, intersect.enter)
					table.insert(new_poly, x)
					table.insert(new_poly, y)
				end
				for i = 1, intersect.consumes do
					local point_id = ((intersect.comes_after+i-1)%#poly) + 1
					local point = poly[point_id]
					table.insert(new_poly, point[1]%grid.size)
					table.insert(new_poly, point[2]%grid.size)
				end
				do
					local x, y = circumlength_to_point(grid.size, intersect.exit)
					table.insert(new_poly, x)
					table.insert(new_poly, y)
				end

				-- Now we need to find the next segement of this poly
				-- ring

				-- Binary search for the intersection that enters right
				-- after this one exits
				local icursor = intersects[index[cursor+g.pos-1]].exit
				local nxt = table.search(index, icursor, function(x)
					return intersects[x].enter
				end, g.pos, g.pos+g.len-1)
				-- Skip any inactive (already used) segments
				local nxt_offset = (nxt - g.pos)%g.len
				while not active[nxt_offset+1] and nxt_offset+1 ~= picked do nxt_offset = (nxt_offset+1)%g.len end
				nxt = nxt_offset + g.pos

				-- Include corners if we cross them
				local entry = intersects[index[nxt]].enter
				local outline_span = entry - icursor
				if outline_span < 0 then
					-- Remember that icursor is negative here, so the
					-- plus results in subtraction
					outline_span = grid.size*4 + outline_span
				end
				-- The distance from the exitpoint (start of the span)
				-- until the first fixed node
				local exit_offset = grid.size - (icursor%grid.size)
				while exit_offset <= outline_span do
					local circumlength = (icursor + exit_offset)%(grid.size*4)
					local x, y = circumlength_to_point(grid.size, circumlength)
					table.insert(new_poly, x)
					table.insert(new_poly, y)

					exit_offset = exit_offset + grid.size
				end

				-- When we find our start position we are done
				if nxt_offset+1 == picked then
					break
				end

				cursor = nxt_offset+1
			end

			table.insert(gpolys, new_poly)
		end

		local intersect = intersects[index[g.pos]]
		grid_polys[k] = {x = intersect.gridx, y = intersect.gridy, polys=gpolys}
	end
	return grid_polys
end

local function anno_open_states(grid_polys, gindex, index, intersects)
	for k,g in pairs(gindex) do
		local left_closest_dist = nil
		local left_closest = nil
		local right_closest_dist = nil
		local right_closest = nil
		local left = nil
		local right = nil
		for i = 1, g.len do
			local id = g.pos + i-1
			local intersect = intersects[index[id]]

			if left == nil then
				if circumlength_segment(grid.size, intersect.enter) == 2 then
					left = false
				end

				if circumlength_segment(grid.size, intersect.exit) == 2 then
					left = false
				end
			end

			if right == nil then
				if circumlength_segment(grid.size, intersect.enter) == 0 then
					right = false
				end

				if circumlength_segment(grid.size, intersect.exit) == 0 then
					right = false
				end
			end

			local enter_dist = circumlength_cwdistance(grid.size, grid.size*2, intersect.enter)
			if left_closest_dist == nil or left_closest_dist > enter_dist then
				left_closest_dist = enter_dist
				left_closest = id
			end

			local enter_dist = circumlength_cwdistance(grid.size, grid.size*2, intersect.exit)
			if left_closest_dist == nil or left_closest_dist > enter_dist then
				left_closest_dist = enter_dist
				left_closest = id
			end

			local enter_dist = circumlength_cwdistance(grid.size, grid.size*4, intersect.enter)
			if right_closest_dist == nil or right_closest_dist > enter_dist then
				right_closest_dist = enter_dist
				right_closest = id
			end

			local enter_dist = circumlength_cwdistance(grid.size, grid.size*4, intersect.exit)
			if right_closest_dist == nil or right_closest_dist > enter_dist then
				right_closest_dist = enter_dist
				right_closest = id
			end
		end

		if left == nil and left_closest ~= nil then
			local intersect = intersects[index[left_closest]]
			local internal = circumlength_cwbetween(grid.size, intersect.enter, grid.size*3, intersect.exit)
			left = not internal
		end

		if right == nil and right_closest ~= nil then
			local intersect = intersects[index[right_closest]]
			local internal = circumlength_cwbetween(grid.size, intersect.enter, grid.size*4, intersect.exit)
			right = not internal
		end

		local intersect = intersects[index[g.pos]]
		-- @CLEANUP: Do we want to store this outside the grid polys?
		-- @CLEANUP @CORRECTNESS Why is right and left swapped here?
		grid_polys[k].open_right = left
		grid_polys[k].open_left = right
	end
end

local function is_covered(grid_polys)
	local covered = {}

	local begin_x = 0
	local begin_y = 0
	for k,v in ipairs(grid_polys) do
		if v.open_left then
			assert(v.y == begin_y)
			for i = begin_x+1,v.x-1 do
				table.insert(covered, {x=i, y=begin_y})
			end
		end

		if v.open_right then
			begin_x =  v.x
			begin_y =  v.y
		end
	end

	return covered
end

local step = 0
local mx, my = 0, 0
local mbx, mby, mbc = 0, 0, 0
local mgx, mgy = 0, 0
function love.update(dt)
	mx, my = love.mouse.getPosition()
	mx, my = love.graphics.inverseTransformPoint(mx, my)


	do
		mgx = math.floor(mx / grid.size)
		mgy = math.floor(my / grid.size)
		mbx = mx % grid.size
		mby = my % grid.size
		local dr, db = math.abs(mbx-grid.size), math.abs(mby - grid.size)
		local m = math.min(mbx, dr, mby, db)

		if m == mby then mbx, mby = mbx, 0
		elseif m == db then mbx, mby = mbx, grid.size
		elseif m == mbx then mbx, mby = 0, mby
		else mbx, mby = grid.size, mby end

		mbc = point_to_circumlength(grid.size, mbx, mby)
		mbx, mby = circumlength_to_point(grid.size, mbc)
		mbx, mby = mbx + (mgx * grid.size), mby + (mgy * grid.size)
	end

	if dstep ~= 0 then
		step = step + dstep
		dstep = 0
		step = math.clamp(step, 0, #poly)

		intersects = polygon_intersections(poly)
		anno_points_consumed(intersects)
		anno_enter_exit(intersects)

		local gindex, index = index_intersections_tile_enter(intersects)

		grid_polys = create_polygon_for_grid_tiles(gindex, index, intersects)
		anno_open_states(grid_polys, gindex, index, intersects)
		covered = is_covered(grid_polys)
	end
end

function love.draw()
	love.graphics.setColor(1, 1, 1, 1)
	do
		for k = 2,#poly do
			lastp = poly[k-1]
			p = poly[k]
			love.graphics.line(lastp[1], lastp[2], p[1], p[2])
		end
		love.graphics.line(poly[1][1], poly[1][2], poly[#poly][1], poly[#poly][2])
	end

	do
		love.graphics.setColor(255, 255, 255, .2)
		local height = love.graphics.getHeight()
		local width = love.graphics.getWidth()

		-- Render the grid lines
		for i = 0,width/grid.size do
			local x = grid.size * i
			love.graphics.line(x, 0, x, height)
		end
		for i = 1,height/grid.size do
			local y = grid.size * i
			love.graphics.line(0, y, width, y)
		end

		love.graphics.setColor(.5, .5, 1, .8)
		-- Render the text labels
		love.graphics.print("0", 10, 0, math.pi/4)
		for i = 1,width/grid.size do
			local x = grid.size * i
			love.graphics.print(string.format("%d", x), x+10, 0, math.pi/4)
		end
		for i = 1,height/grid.size do
			local y = grid.size * i
			love.graphics.print(string.format("%d", y), 10, y, math.pi/4)
		end
	end

	do
		love.graphics.setPointSize(5)
		local width = love.graphics.getWidth()
		for k,v in pairs(intersects) do
			love.graphics.points(v[1], v[2])
			if v.consumes ~= nil then
				-- love.graphics.print(string.format("%d", v.consumes), v[1], v[2], math.pi/4)
				-- love.graphics.print(string.format("%d", k), v[1], v[2], math.pi/4)
				-- love.graphics.print(string.format("%d/%d", v.gridx, v.gridy), v[1], v[2], math.pi/4)
				-- love.graphics.print(string.format("%d/%d", v.enter, v.exit), v[1], v[2], math.pi/4)
			end
		end
	end

	do
		love.graphics.push()
		love.graphics.setColor(0, 0, 0, 1)
		love.graphics.translate(500, 400)
		love.graphics.scale(3, 3)
		love.graphics.rectangle("fill", -10, -10, grid.size+20, grid.size+20)
		love.graphics.setColor(255, 255, 255, .7)
		love.graphics.rectangle("line", 0, 0, grid.size, grid.size)
		for k,v in pairs(grid_polys) do
			if v.x == mgx+1 and v.y == mgy+1 then
				love.graphics.print(string.format("Polys = %d", #v.polys), 0, 20)
				for k2, v2 in pairs(v.polys) do
					local triangles = love.math.triangulate(v2)

					for i, triangle in ipairs(triangles) do
						love.graphics.polygon("fill", triangle)
					end
					-- love.graphics.polygon("line", v2)
					-- love.graphics.points(v2)
					love.graphics.setColor(1, 0, 0, .4)
					if v.open_right then
						love.graphics.line(grid.size, grid.size, grid.size, 0)
					end
					if v.open_left then
						love.graphics.line(0, 0, 0, grid.size)
					end
					love.graphics.setColor(255, 255, 255, .7)
				end
			end
		end
		love.graphics.pop()

		love.graphics.push()
		love.graphics.setColor(1, 1, 1, .2)
		for k,v in pairs(grid_polys) do
			love.graphics.origin()
			love.graphics.translate((v.x-1)*grid.size, (v.y-1)*grid.size)
			for k2, v2 in pairs(v.polys) do
				local triangles = love.math.triangulate(v2)

				for i, triangle in ipairs(triangles) do
					love.graphics.polygon("fill", triangle)
				end
			end
		end
		love.graphics.pop()

		love.graphics.push()
		love.graphics.setColor(1, 0, 0, .4)
		for k,v in pairs(grid_polys) do
			love.graphics.origin()
			love.graphics.translate((v.x-1)*grid.size, (v.y-1)*grid.size)
			if v.open_right then
				love.graphics.line(grid.size, grid.size, grid.size, 0)
			end
			if v.open_left then
				love.graphics.line(0, 0, 0, grid.size)
			end
		end
		love.graphics.pop()

		love.graphics.push()
		love.graphics.setColor(1, 0, 0, .1)
		for k,v in pairs(covered) do
			love.graphics.origin()
			love.graphics.translate((v.x-1)*grid.size, (v.y-1)*grid.size)
			love.graphics.polygon("fill", {0, 0, 0, grid.size, grid.size, grid.size, grid.size, 0})
		end
		love.graphics.pop()
	end

	love.graphics.setColor(1, 1, 1, .7)
	love.graphics.points(mbx, mby)
	love.graphics.print(string.format("%d", mbc), mbx, mby, math.pi/4)

	love.graphics.setColor(255, 255, 255, .7)
	love.graphics.print(string.format("Step = %d", step), 0, 10)

	love.graphics.print(string.format("Mouse position = %d %d", mgx+1, mgy+1), 0, 20)
end

function table.search(tbl, key, f, low, high)
	if low == nil then
		low = 1
	end
	if high == nil then
		high = #tbl
	end
	if f == nil then
		f = function(x)
			return x
		end
	end

	while low <= high do
		local pivot = math.floor((high - low) / 2) + low

		local pval = f(tbl[pivot])
		if pval == key then
			return pivot
		elseif pval > key then
			high = pivot - 1
		else
			low = pivot + 1
		end
	end

	return high + 1
end

-- Print anything - including nested tables
function table.print (tt, indent, done)
	done = done or {}
	indent = indent or 0
	if tt == nil then
		io.write("<NIL>\n")
	elseif type(tt) == "table" then
		for key, value in pairs(tt) do
			io.write(string.rep(" ", indent)) -- indent it
			if type (value) == "table" and not done[value] then
				done[value] = true
				io.write(string.format("[%s] => %s\n", tostring(key), tostring(value)));
				io.write(string.rep(" ", indent+4)) -- indent it
				io.write("(\n");
				table.print(value, indent + 7, done)
				io.write(string.rep(" ", indent+4)) -- indent it
				io.write(")\n");
			else
				io.write(
					string.format("[%s] => %s\n", tostring(key), tostring(value))
				)
			end
		end
	else
		io.write(tt .. "\n")
	end
end
