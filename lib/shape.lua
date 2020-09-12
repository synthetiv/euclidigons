Shape = {}
Shape.__index = Shape

function Shape.new(n, r, x, rate)
	local shape = {
		n = n,
		r = r,
		x = x,
		rate = rate,
		theta = 0,
		vertices = {},
		side_levels = {}
	}
	for v = 1, n do
		shape.vertices[v] = {
			x = x,
			y = y_center,
			nx = x,
			ny = y_center,
			level = 0
		}
		shape.side_levels[v] = 0
	end
	setmetatable(shape, Shape)
	shape:calculate_points()
	shape:calculate_points()
	shape:calculate_area()
	return shape
end

function Shape:calculate_points()
	local vertex_angle = tau / self.n
	for v = 1, self.n do
		local vertex = self.vertices[v]
		vertex.x = vertex.nx
		vertex.y = vertex.ny
		vertex.nx = self.x + math.cos(self.theta + v * vertex_angle) * self.r
		vertex.ny = y_center + math.sin(self.theta + v * vertex_angle) * self.r
	end
end

function Shape:calculate_area()
	local area = 0
	for v = 1, self.n do
		local vertex = self.vertices[v]
		local vertex2 = self.vertices[v % self.n + 1]
		area = area + vertex.x * vertex2.y - vertex2.x * vertex.y
	end
	self.area = area
end

function Shape:rotate()
	self.theta = self.theta + self.rate
	while self.theta > tau do
		self.theta = self.theta - tau
	end
	self:calculate_points()
end

function Shape:draw_lines()
	for v = 1, self.n do
		local vertex1 = self.vertices[v]
		local vertex2 = self.vertices[v % self.n + 1]
		local level = self.side_levels[v]
		screen.move(vertex1.x, vertex1.y)
		screen.line(vertex2.x, vertex2.y)
		screen.level(math.floor(2 + level * 13))
		screen.line_width(math.floor(1 + level))
		screen.stroke()
	end
end
	
function Shape:draw_points()
	for v = 1, self.n do
		local vertex = self.vertices[v]
		screen.circle(vertex.x, vertex.y, 0.5 + vertex.level * 3)
		screen.level(15)
		screen.fill()
	end
end

return Shape