function love.load()
	love.graphics.setPointSize(10)
end

function pseudoangle(x, y)
	r = x / (math.abs(x) + math.abs(y))
	if y < 0 then
		return 1. + r
	end
	return 3. - r
end

function love.draw()
	love.graphics.translate(200, 200)
	love.graphics.points(0, 0)

	ma = pseudoangle(mx, my)
	refa = pseudoangle(refx, refy)
	love.graphics.print(tostring(refa), refx + 10, refy + 10)
	love.graphics.print(tostring(ma), mx + 10, my + 10)
	love.graphics.print(tostring((ma - refa) % 4), 40, 40)
	love.graphics.line(0, 0, mx, my)
	love.graphics.line(0, 0, refx, refy)
end

refx, refy = 100, 0
mx, my = 0, 0

function love.update(dt)
	mx, my = love.mouse.getPosition()
	mx, my = love.graphics.inverseTransformPoint(mx, my)

	if love.mouse.isDown(1) then
		refx, refy = mx, my
	end
end
