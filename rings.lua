local rings = {}

local function pseudoangle(x, y)
	r = x / (math.abs(x) + math.abs(y))
	if y < 0 then
		return r - 1.
	end
	return 1. - r
end

local function sign(n)
	return n > 0 and 1
	or  n < 0 and 1
	or  0
end

function table.clone(org)
	return {unpack(org)}
end

function table.toset(org)
	new = {}
	for k, v in pairs(org) do
		new[v] = true
	end
	return new
end

-- With ref at origo, sweep a line counterclockwise starting at refangle
-- and find the node hit first.
local function calc_angles(ref, refangle, neighbours, nodes)
	assert(next(neighbours) ~= nil)
	local angles = {}
	for i, v in ipairs(neighbours) do
		angles[i] = {pseudoangle(nodes[v[1]][1] - nodes[ref][1], nodes[v[1]][2] - nodes[ref][2]), v[2], v[3], i}
	end

	for _, v in ipairs(angles) do
		v[1] = (refangle - v[1]) % 4
	end

	table.sort(angles, function(a, b) return a[1] < b[1] end)
	return angles[1]
end

-- Find the way (endpoint and direction) that sits at the leftmost point of the
-- shape.
local function find_leftmost_way(nodes, waybag, ways)
	-- Find the node furthest to the left (lowest x)
	local minx = nil
	local minnode
	-- The ways that include this node
	local minways = {}
	-- The index of the node in said way
	local mini = {}
	for mem, _ in pairs(waybag) do
		assert(ways[mem] ~= nil, "Way not available: " .. mem)
		for k2 = 1, #ways[mem].refs do
			local v2 = ways[mem].refs[k2]
			assert(nodes[v2] ~= nil, "Node not available: " .. v2 .. " of way " .. mem)
			assert(nodes[v2][1] ~= nil, "Node not available: " .. v2 .. " of way " .. mem)
			if v2 == minnode then
				table.insert(minways, mem)
				table.insert(mini, k2)
			elseif minx == nil or nodes[v2][1] < minx then
				minx = nodes[v2][1]
				minnode = v2
				minways = {mem}
				mini = {k2}
			end
		end
	end

	print("Min node =", minnode)
	-- Find it's neighbour nodes
	local neighbours = {}
	-- Multiple ways may include this node
	for i, v in ipairs(minways) do
		if mini[i] > 1 then
			-- node before this node in the way
			table.insert(neighbours, {ways[v].refs[mini[i]-1], v, -1})
		end

		if mini[i] < #ways[v].refs then
			-- node after this node in the way
			table.insert(neighbours, {ways[v].refs[mini[i]+1], v, 1})
		end
	end

	assert(next(neighbours) ~= nil)
	-- 0 angle is left. Since this is the leftmost point, sweeping a line from
	-- there is guaranteed to find us the neighbour that leads us in the
	-- outermost counterclickwise direction
	-- The way that ties this node and the neighbour together is therefore
	-- (since ways can't cross) also the outermose counterclickwise way, so by
	-- selecting that we know we have started winding a new outer ring in the
	-- counterclockwise direction
	local minangle = calc_angles(minnode, 0, neighbours, nodes)
	local first

	-- Find the start of the selected way so we know when we create a ring.
	-- The node we selected may have been in the middle of the node, so we use
	-- the direction to find the start. Since calc_angles gives us the next
	-- node, the endpoint in the opposite direction must be the start.
	if minangle[3] == -1 then
		first = ways[minangle[2]].refs[#ways[minangle[2]].refs]
	else
		first = ways[minangle[2]].refs[1]
	end

	return {first, minangle[2], minangle[3]}
end


local function next_ring(nodes, waybag, ways)
	local ring = {}

	local res = find_leftmost_way(nodes, waybag, ways)
	local first = res[1]
	local minangle = {"", res[2], res[3]}

	-- Remove the selected way from the bag
	table.insert(ring, {res[2], res[3]})
	waybag[res[2]] = nil

	local neighbours = {}
	for wayi, _ in pairs(waybag) do
		assert(#ways[wayi].refs > 1)
		if neighbours[ways[wayi].refs[1]] == nil then
			neighbours[ways[wayi].refs[1]] = {}
		end
		table.insert(neighbours[ways[wayi].refs[1]], {ways[wayi].refs[2], wayi, 1})

		if neighbours[ways[wayi].refs[#ways[wayi].refs]] == nil then
			neighbours[ways[wayi].refs[#ways[wayi].refs]] = {}
		end
		table.insert(neighbours[ways[wayi].refs[#ways[wayi].refs]], {ways[wayi].refs[#ways[wayi].refs-1], wayi, -1})
	end

	-- Now that we have the first way in the next outermost ring we have to walk
	-- around by repeatedly finding the outermost way and then moving on to
	-- that ways other end
	while true do
		print("We pick way", minangle[2], "in direction", minangle[3])

		-- Get the next endpoint (nnode) and the node connected to that one in
		-- the current way. We need the connected node to calculate the
		-- reference angle we use as a starting point for the sweep
		local nnode, lnode
		if minangle[3] == -1 then
			nnode = ways[minangle[2]].refs[1]
			lnode = ways[minangle[2]].refs[2]
		else
			nnode = ways[minangle[2]].refs[#ways[minangle[2]].refs]
			lnode = ways[minangle[2]].refs[#ways[minangle[2]].refs-1]
		end
		print("Next Node", nnode, "lnode", lnode)

		-- If the next endpoint of this way happens to be the starting endpoint
		-- of the first way we have found a ring and we're done
		if nnode == first then
			break
		end

		-- Find all the ways connected to this endpoint
		local myneighbours = neighbours[nnode]
		if myneighbours == nil then
			error("Incomplete ring")
		end

		print("Neighbours")
		print(myneighbours)
		table_print(myneighbours)
		print(myneighbours)
		-- Pick the outermost way again
		local refangle = pseudoangle(nodes[lnode][1] - nodes[nnode][1], nodes[lnode][2] - nodes[nnode][2])
		minangle = calc_angles(nnode, refangle, myneighbours, nodes)
		assert(minangle ~= nil)

		-- Add the way to the ring
		table.insert(ring, {minangle[2], minangle[3]})
		waybag[minangle[2]] = nil
		print("Remove way " .. minangle[2])
		-- Remove the way from the neighbours
		for k,v in ipairs(neighbours[ways[minangle[2]].refs[1]]) do
			if v[2] == minangle[2] then
				table.remove(neighbours[ways[minangle[2]].refs[1]], k)
			end
		end
		for k,v in ipairs(neighbours[ways[minangle[2]].refs[#ways[minangle[2]].refs]]) do
			if v[2] == minangle[2] then
				table.remove(neighbours[ways[minangle[2]].refs[#ways[minangle[2]].refs]], k)
			end
		end
	end

	return ring
end

local function find_simple_rings(nodes, waybag, ways)
	local rings = {}
	for mem,_ in ipairs(waybag) do
		assert(#ways[mem].refs > 1)
		if #ways[mem].refs > 2 then
			firstnode = ways[mem].refs[1]
			lastnode = ways[mem].refs[#ways[mem].refs]
			if firstnode == lastnode then
				-- @INCOMPLETE: We need to figure out the dirction here
				table.insert(rings, {{mem, 1}})
				waybag[mem] = nil
			end
		end
	end

	return rings
end

function rings.find(nodes, ways, relation)
	local waybag = table.toset(relation.memids)

	local rings = find_simple_rings(nodes, waybag, ways)

	while next(waybag) ~= nil do
		local ring = next_ring(nodes, waybag, ways)
		table.insert(rings, ring)
	end

	return rings
end

return rings
